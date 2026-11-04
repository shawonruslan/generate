import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

enum _SortMode { name, size, newest, oldest }
enum _ViewMode { list, grid }

/// Flagship file browser: folder navigation, list/grid, search, sort,
/// uploads, downloads, previews, versions, shares, locks, multi-select.
class DriveScreen extends StatefulWidget {
  /// Handoff from HomeScreen's global Ctrl+K search. Values:
  /// `folder:<id>`, `file:<id>:<folderId>`, or plain text (in-folder search).
  /// Consumed (set to null) after applying.
  static String? pendingQuery;

  /// Set in initState, cleared in dispose. Opens the "New" bottom sheet
  /// (Upload files / New folder). Wired to the sidebar "New" button and
  /// the mobile FAB by HomeScreen.
  static VoidCallback? requestNew;

  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  String _folderId = 'root';
  _SortMode _sort = _SortMode.name;
  _ViewMode _view = _ViewMode.list;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selFiles = {};
  final Set<String> _selFolders = {};
  String? _highlightId;
  bool _scrollToHighlight = false;
  Timer? _highlightTimer;
  final _scrollCtrl = ScrollController();
  String? _loadError;
  late final VoidCallback _newHandler;

  bool get _inSelection => _selFiles.isNotEmpty || _selFolders.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _newHandler = _showNewSheet;
    DriveScreen.requestNew = _newHandler;
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text);
    });
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _consumePendingQuery();
      if (context.read<SessionProvider>().drive == null) {
        _initialLoad();
      }
    });
  }

  @override
  void dispose() {
    if (identical(DriveScreen.requestNew, _newHandler)) {
      DriveScreen.requestNew = null;
    }
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sort = _SortMode.values.firstWhere(
          (e) => e.name == prefs.getString('td_sort'),
          orElse: () => _SortMode.name);
      _view = prefs.getString('td_layout') == 'grid'
          ? _ViewMode.grid
          : _ViewMode.list;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('td_sort', _sort.name);
    await prefs.setString('td_layout',
        _view == _ViewMode.grid ? 'grid' : 'list');
  }

  Future<void> _initialLoad() async {
    final session = context.read<SessionProvider>();
    setState(() => _loadError = null);
    await guard(context, () => session.refreshDrive());
    if (!mounted) return;
    setState(() {
      if (session.drive == null) _loadError = 'Could not load your drive.';
    });
  }

  /// Run [fn] with error snackbars; returns true on success and shows
  /// [doneMsg] (when non-empty) afterwards.
  Future<bool> _run(Future<void> Function() fn, String doneMsg) async {
    try {
      await fn();
    } on UnauthorizedException {
      if (mounted) {
        showMsg(context, 'Session expired — please log in again.',
            error: true);
      }
      return false;
    } on ApiException catch (e) {
      if (mounted) showMsg(context, e.message, error: true);
      return false;
    } catch (e) {
      if (mounted) showMsg(context, 'Something went wrong: $e', error: true);
      return false;
    }
    if (mounted && doneMsg.isNotEmpty) showMsg(context, doneMsg);
    return true;
  }

  // ---------------- navigation / query ----------------

  void _consumePendingQuery() {
    final q = DriveScreen.pendingQuery;
    DriveScreen.pendingQuery = null;
    if (q == null || q.isEmpty || !mounted) return;
    final drive = context.read<SessionProvider>().drive;
    if (q.startsWith('folder:')) {
      final id = q.substring('folder:'.length);
      _navigate(id == 'root' || (drive?.folders.containsKey(id) ?? false)
          ? id
          : 'root');
    } else if (q.startsWith('file:')) {
      final rest = q.substring('file:'.length);
      final sep = rest.indexOf(':');
      if (sep > 0) {
        final fileId = rest.substring(0, sep);
        final folderId = rest.substring(sep + 1);
        _navigate(folderId == 'root' ||
                (drive?.folders.containsKey(folderId) ?? false)
            ? folderId
            : 'root');
        _highlightFile(fileId);
      }
    } else {
      _searchCtrl.text = q;
    }
  }

  void _navigate(String id) {
    setState(() {
      _folderId = id;
      _selFiles.clear();
      _selFolders.clear();
      _highlightId = null;
      _scrollToHighlight = false;
    });
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  void _goParent() {
    final drive = context.read<SessionProvider>().drive;
    if (drive == null || _folderId == 'root') return;
    _navigate(drive.folders[_folderId]?.parent ?? 'root');
  }

  void _highlightFile(String id) {
    setState(() {
      _highlightId = id;
      _scrollToHighlight = true;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  /// After a highlighted row is laid out, scroll it into view (once).
  void _maybeScrollTo(BuildContext ctx, String id) {
    if (id == _highlightId && _scrollToHighlight) {
      _scrollToHighlight = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 350), alignment: 0.4);
        }
      });
    }
  }

  // ---------------- folder helpers ----------------

  List<DriveFolder> _pathFor(DriveData drive, String folderId) {
    final path = <DriveFolder>[];
    var id = folderId;
    var guardN = 0;
    while (id != 'root' && drive.folders.containsKey(id) && guardN++ < 100) {
      final f = drive.folders[id]!;
      path.insert(0, f);
      id = f.parent;
    }
    return path;
  }

  String _folderPathText(DriveData drive, String folderId) {
    final names = _pathFor(drive, folderId).map((f) => f.name);
    return ['My Drive', ...names].join(' / ');
  }

  List<DriveFolder> _sortedFolders(DriveData drive) {
    final q = _query.trim().toLowerCase();
    final list = drive.folders.values
        .where((f) => f.parent == _folderId)
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      switch (_sort) {
        case _SortMode.name:
        case _SortMode.size:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.newest:
          return b.createdAt.compareTo(a.createdAt);
        case _SortMode.oldest:
          return a.createdAt.compareTo(b.createdAt);
      }
    });
    return list;
  }

  List<DriveFile> _sortedFiles(DriveData drive) {
    final q = _query.trim().toLowerCase();
    final list = drive.files.values
        .where((f) => f.folder == _folderId)
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      switch (_sort) {
        case _SortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.size:
          return b.size.compareTo(a.size);
        case _SortMode.newest:
          return b.uploadedAt.compareTo(a.uploadedAt);
        case _SortMode.oldest:
          return a.uploadedAt.compareTo(b.uploadedAt);
      }
    });
    return list;
  }

  int _folderItemCount(DriveData drive, String folderId) {
    var n = 0;
    for (final f in drive.folders.values) {
      if (f.parent == folderId) n++;
    }
    for (final f in drive.files.values) {
      if (f.folder == folderId) n++;
    }
    return n;
  }

  bool _previewable(DriveFile f) =>
      isImageMime(f.type) ||
      isPdfMime(f.type) ||
      isVideoMime(f.type) ||
      isAudioMime(f.type);

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final drive = session.drive;
    return PopScope(
      canPop: _folderId == 'root' && !_inSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_inSelection) {
          _clearSelection();
        } else if (_folderId != 'root') {
          _goParent();
        }
      },
      child: _buildBody(context, session, drive),
    );
  }

  /// Empty-drive card (mirrors the web): white rounded-16 card with the
  /// empty message plus side-by-side "New folder" (outlined) and
  /// "Upload" (solid blue) buttons.
  Widget _emptyStateCard() {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined,
              size: 48, color: theme.hintColor),
          const SizedBox(height: 12),
          const Text('No files in this drive yet',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Create a folder or upload files to get started',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.hintColor)),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _newFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New folder'),
              ),
              ElevatedButton.icon(
                onPressed: _uploadFiles,
                icon: const Icon(Icons.upload_outlined),
                label: const Text('Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, SessionProvider session, DriveData? drive) {
    if (drive == null) {
      if (_loadError != null) {
        return ErrorView(
            message: _loadError!,
            onRetry: () {
              setState(() {
                _loadError = null;
              });
              _initialLoad();
            });
      }
      return const LoadingView(label: 'Loading drive…');
    }
    final folders = _sortedFolders(drive);
    final files = _sortedFiles(drive);
    final total = folders.length + files.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(drive),
        if (_query.trim().isNotEmpty) _queryChip(),
        if (_inSelection) _selectionBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await guard(context, () => session.refreshDrive());
            },
            child: total == 0
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _query.trim().isEmpty
                          ? _emptyStateCard()
                          : SizedBox(
                              height: 320,
                              child: EmptyView(
                                icon: Icons.folder_outlined,
                                message:
                                    'No matches for "${_query.trim()}"',
                              ),
                            ),
                    ],
                  )
                : _view == _ViewMode.list
                    ? _listView(drive, folders, files)
                    : _gridView(drive, folders, files),
          ),
        ),
      ],
    );
  }

  /// Header: "My Drive" 22px/800 + small folder icon + "Home /" breadcrumb
  /// prefix, with the sort dropdown and list/grid toggle at the right.
  /// The breadcrumb chips row below handles subfolder navigation.
  Widget _headerTitleRow(DriveData drive) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    final path = _pathFor(drive, _folderId);
    final name =
        path.isNotEmpty ? path.last.name : 'My Drive';
    final prefix = _folderId == 'root' || path.isEmpty
        ? 'Home / '
        : 'Home / ${path.take(path.length - 1).map((f) => f.name).join(' / ')}'
            '${path.length > 1 ? ' / ' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Icon(Icons.folder, size: 22, color: brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: prefix,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.hintColor),
                  ),
                  TextSpan(
                    text: name,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _sortDropdown(),
          IconButton(
            tooltip: _view == _ViewMode.list ? 'Grid view' : 'List view',
            icon: Icon(_view == _ViewMode.list
                ? Icons.grid_view_outlined
                : Icons.view_list_outlined),
            onPressed: () {
              setState(() => _view = _view == _ViewMode.list
                  ? _ViewMode.grid
                  : _ViewMode.list);
              _savePrefs();
            },
          ),
        ],
      ),
    );
  }

  /// Single toolbar column (mirrors the web): title row on top, breadcrumb
  /// chips below it for subfolders. The global topbar owns search, so there
  /// is no second search field here.
  Widget _toolbar(DriveData drive) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _headerTitleRow(drive),
        if (_folderId != 'root')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _crumbRow(drive),
          ),
      ],
    );
  }

  /// Horizontally scrollable breadcrumb chips: "My Drive" + path segments.
  Widget _crumbRow(DriveData drive) {
    final path = _pathFor(drive, _folderId);
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    Widget chip(
        String label, IconData icon, bool active, VoidCallback? onTap) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active ? brand.withOpacity(0.14) : theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active
                    ? brand.withOpacity(0.45)
                    : theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: active ? brand : theme.iconTheme.color),
              const SizedBox(width: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? brand : null)),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('My Drive', Icons.hard_drive, _folderId == 'root',
              _folderId == 'root' ? null : () => _navigate('root')),
          for (final f in path) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.chevron_right, size: 15, color: Colors.grey),
            ),
            chip(f.name, Icons.folder_outlined, f.id == _folderId,
                f.id == _folderId ? null : () => _navigate(f.id)),
          ],
        ],
      ),
    );
  }

  /// "Newest first" style sort dropdown (mirrors the web app).
  Widget _sortDropdown() {
    const labels = <_SortMode, String>{
      _SortMode.newest: 'Newest first',
      _SortMode.oldest: 'Oldest first',
      _SortMode.name: 'Name A–Z',
      _SortMode.size: 'Largest first',
    };
    const order = [
      _SortMode.newest,
      _SortMode.oldest,
      _SortMode.name,
      _SortMode.size
    ];
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: _sort,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 20),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyMedium?.color),
          items: [
            for (final m in order)
              DropdownMenuItem(value: m, child: Text(labels[m]!)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _sort = v);
            _savePrefs();
          },
        ),
      ),
    );
  }

  /// Shown when the global search hands this screen an in-folder query,
  /// so the active filter stays visible and clearable without a second
  /// search bar.
  Widget _queryChip() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('Results for "${_query.trim()}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: theme.hintColor)),
          ),
          TextButton(
            onPressed: () => _searchCtrl.clear(),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// Section divider header ("FOLDERS" / "FILES"), like the web app.
  Widget _sectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: theme.hintColor)),
    );
  }

  /// Purple owner badge (lock icon + owner name) for member home folders.
  Widget _ownerBadge(String owner) {
    final night = Theme.of(context).brightness == Brightness.dark;
    const purple = Color(0xFF7E22CE);
    final fg = night ? const Color(0xFFC084FC) : purple;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: purple.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(owner,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }

  /// Blue "v2" version badge with a small circular-arrow icon, shown when a
  /// file has versions (mirrors the web's .vbadge).
  Widget _verBadge(int ver) {
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: brand.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.autorenew, size: 11, color: brand),
          const SizedBox(width: 3),
          Text('v$ver',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand)),
        ],
      ),
    );
  }

  /// Member avatar photo with a small folder badge overlaid (web parity).
  Widget _ownerAvatar(String owner, String? url) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarWidget(url: url, name: owner, radius: 26),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: theme.cardColor, width: 2),
            ),
            child:
                const Icon(Icons.folder, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _selectionBar() {
    final n = _selFiles.length + _selFolders.length;
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primary.withOpacity(0.10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.close), onPressed: _clearSelection),
          Text('$n selected',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            tooltip: 'Move',
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: _moveSelected,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline,
                color: theme.colorScheme.error),
            onPressed: _deleteSelected,
          ),
        ],
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _selFiles.clear();
      _selFolders.clear();
    });
  }

  void _toggleFile(String id) {
    setState(() {
      if (_selFiles.contains(id)) {
        _selFiles.remove(id);
      } else {
        _selFiles.add(id);
      }
    });
  }

  void _toggleFolder(String id) {
    setState(() {
      if (_selFolders.contains(id)) {
        _selFolders.remove(id);
      } else {
        _selFolders.add(id);
      }
    });
  }

  // ---------------- list / grid ----------------

  /// White rounded-16 card containing a table of rows, with a "NAME" header
  /// row in small gray caps and hairline dividers (mirrors the web list).
  Widget _listCard(List<Widget> rows) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: theme.dividerColor.withOpacity(0.25),
              border: Border(
                  bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Text('NAME',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: theme.hintColor)),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.dividerColor.withOpacity(0.6)),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// Solid blue square download button (white down-arrow) for list rows.
  Widget _dlButton(DriveFile f) {
    final brand = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _downloadFile(f),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: brand,
          borderRadius: BorderRadius.circular(8),
        ),
        child:
            const Icon(Icons.download, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _listView(
      DriveData drive, List<DriveFolder> folders, List<DriveFile> files) {
    return ListView(
      controller: _scrollCtrl,
      children: [
        if (folders.isNotEmpty) ...[
          _sectionHeader('Folders'),
          _listCard([for (final fo in folders) _folderRow(drive, fo)]),
        ],
        if (files.isNotEmpty) ...[
          _sectionHeader('Files'),
          _listCard([for (final f in files) _fileRow(drive, f)]),
        ],
      ],
    );
  }

  Widget _gridView(
      DriveData drive, List<DriveFolder> folders, List<DriveFile> files) {
    const delegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 170,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
    );
    Widget headerSliver(String title, double topPad) => SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topPad, 16, 0),
            child: _sectionHeader(title),
          ),
        );
    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        if (folders.isNotEmpty) ...[
          headerSliver('Folders', 4),
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.builder(
              gridDelegate: delegate,
              itemCount: folders.length,
              itemBuilder: (_, i) => _folderGridTile(drive, folders[i]),
            ),
          ),
        ],
        if (files.isNotEmpty) ...[
          headerSliver('Files', 0),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            sliver: SliverGrid.builder(
              gridDelegate: delegate,
              itemCount: files.length,
              itemBuilder: (_, i) => _fileGridTile(drive, files[i]),
            ),
          ),
        ],
      ],
    );
  }

  /// Folder avatar for list rows: owner avatar circle with a small purple
  /// badge overlapping bottom-right (mirrors the web's .fav + .b).
  Widget _folderRowAvatar(DriveData drive, String? owner) {
    final theme = Theme.of(context);
    if (owner == null) {
      return const Icon(Icons.folder, size: 36, color: Color(0xFFD97706));
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarWidget(url: drive.avatars[owner], name: owner, radius: 18),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF9333EA),
              shape: BoxShape.circle,
              border: Border.all(color: theme.cardColor, width: 2),
            ),
            child: const Icon(Icons.folder, size: 9, color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// Folder row for the list card: avatar + bold name + purple owner pill,
  /// item count caption, 3-dot menu at the right edge.
  Widget _folderRow(DriveData drive, DriveFolder fo) {
    final selected = _selFolders.contains(fo.id);
    final count = _folderItemCount(drive, fo.id);
    final owner = fo.owner;
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return InkWell(
      onTap: () =>
          _inSelection ? _toggleFolder(fo.id) : _navigate(fo.id),
      onLongPress: () => _toggleFolder(fo.id),
      child: Container(
        color: selected ? brand.withOpacity(0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _inSelection
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => _toggleFolder(fo.id))
                : _folderRowAvatar(drive, owner),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(fo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (owner != null) ...[
                        const SizedBox(width: 6),
                        _ownerBadge(owner),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '$count item${count == 1 ? '' : 's'} · ${formatDate(fo.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: theme.hintColor)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _folderMenu(fo),
            ),
          ],
        ),
      ),
    );
  }

  /// File row for the list card: color tile icon, bold name, gray
  /// "size · relative" caption, blue v2 pill, blue download button, 3-dot.
  Widget _fileRow(DriveData drive, DriveFile f) {
    final selected = _selFiles.contains(f.id);
    final theme = Theme.of(context);
    final brand = theme.colorScheme.primary;
    return Builder(builder: (ctx) {
      _maybeScrollTo(ctx, f.id);
      final highlighted = f.id == _highlightId;
      return InkWell(
        onTap: () => _inSelection ? _toggleFile(f.id) : _fileMenu(f),
        onLongPress: () => _toggleFile(f.id),
        child: Container(
          color:
              selected || highlighted ? brand.withOpacity(0.10) : null,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _inSelection
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleFile(f.id))
                  : FileTypeIcon(name: f.name, mime: f.type, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (f.isLocked) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.lock,
                              size: 14,
                              color: theme.colorScheme.error),
                        ],
                        if (f.ver > 1 || f.vc > 0) ...[
                          const SizedBox(width: 6),
                          _verBadge(f.ver),
                        ],
                        if (f.shares > 0) ...[
                          const SizedBox(width: 6),
                          Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.link,
                                    size: 13,
                                    color: Colors.grey.shade600),
                                const SizedBox(width: 2),
                                Text('${f.shares}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600)),
                              ]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                        '${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: theme.hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              f.url != null
                  ? _dlButton(f)
                  : Icon(Icons.lock_outline,
                      size: 18, color: theme.colorScheme.error),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _fileMenu(f),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _folderGridTile(DriveData drive, DriveFolder fo) {
    final selected = _selFolders.contains(fo.id);
    final theme = Theme.of(context);
    final count = _folderItemCount(drive, fo.id);
    final owner = fo.owner;
    final brand = theme.colorScheme.primary;
    return Card(
      color: selected ? brand.withOpacity(0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? brand : theme.dividerColor,
            width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            _inSelection ? _toggleFolder(fo.id) : _navigate(fo.id),
        onLongPress: () => _toggleFolder(fo.id),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (owner != null)
                    _ownerAvatar(owner, drive.avatars[owner])
                  else
                    Icon(Icons.folder_outlined,
                        size: 44, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(fo.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  if (owner != null) ...[
                    const SizedBox(height: 6),
                    _ownerBadge(owner),
                  ],
                  const SizedBox(height: 4),
                  Text('$count item${count == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.check_circle,
                    color: theme.colorScheme.primary),
              ),
            Positioned(
              bottom: 2,
              right: 2,
              child: IconButton(
                iconSize: 18,
                icon: const Icon(Icons.more_vert),
                onPressed: () => _folderMenu(fo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// File grid tile (mirrors the web): white rounded-16 card, a large
  /// light-gray preview area on top with the color tile icon centered,
  /// then file name (+ small type icon), gray "size · relative" caption,
  /// 3-dot at the bottom-right.
  Widget _fileGridTile(DriveData drive, DriveFile f) {
    final selected = _selFiles.contains(f.id);
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final brand = theme.colorScheme.primary;
    final thumbBg =
        night ? const Color(0xFF1B1B1B) : const Color(0xFFF2F1ED);
    return Builder(builder: (ctx) {
      _maybeScrollTo(ctx, f.id);
      final highlighted = f.id == _highlightId;
      return Card(
        color: selected || highlighted
            ? brand.withOpacity(0.06)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? brand : theme.dividerColor,
              width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              _inSelection ? _toggleFile(f.id) : _fileMenu(f),
          onLongPress: () => _toggleFile(f.id),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 104,
                    color: thumbBg,
                    child: Center(
                      child: FileTypeIcon(
                          name: f.name, mime: f.type, size: 56),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 34, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              FileTypeIcon(
                                  name: f.name,
                                  mime: f.type,
                                  size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor)),
                          if (f.ver > 1 ||
                              f.vc > 0 ||
                              f.isLocked) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (f.isLocked)
                                  Icon(Icons.lock,
                                      size: 13,
                                      color:
                                          theme.colorScheme.error),
                                if (f.isLocked &&
                                    (f.ver > 1 || f.vc > 0))
                                  const SizedBox(width: 6),
                                if (f.ver > 1 || f.vc > 0)
                                  _verBadge(f.ver),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.check_circle, color: brand),
                ),
              Positioned(
                bottom: 6,
                right: 6,
                child: IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _fileMenu(f),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------- "New" sheet / upload ----------------

  void _showNewSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Upload files'),
              onTap: () {
                Navigator.pop(c);
                _uploadFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder'),
              onTap: () {
                Navigator.pop(c);
                _newFolder();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || !mounted) return;
    final picked = res.files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .toList();
    if (picked.isEmpty || !mounted) return;
    final session = context.read<SessionProvider>();
    var failed = 0;
    for (final pf in picked) {
      final name = cleanName(pf.name);
      if (name.isEmpty) {
        failed++;
        continue;
      }
      final ok = await ProgressDialog.show(
        context,
        title: 'Uploading $name',
        task: (prog) => session.api.uploadFile(
          localPath: pf.path!,
          folderId: _folderId,
          displayName: name,
          mime: guessMime(pf.name),
          onProgress: (s, t) => prog(s, t),
        ),
      );
      if (!ok) failed++;
      if (!mounted) return;
    }
    await guard(context, () => session.refreshDrive());
    if (!mounted) return;
    if (failed == 0) {
      showMsg(context,
          picked.length == 1 ? 'Upload complete' : '${picked.length} files uploaded');
    } else {
      showMsg(context, '$failed of ${picked.length} uploads failed',
          error: true);
    }
  }

  Future<void> _newFolder() async {
    final name = await promptDialog(context,
        title: 'New folder', hint: 'Folder name', okLabel: 'Create');
    if (name == null || !mounted) return;
    final clean = cleanName(name);
    if (clean.isEmpty) {
      showMsg(context, 'Enter a folder name', error: true);
      return;
    }
    final session = context.read<SessionProvider>();
    final ok = await _run(
        () => session.api.createFolder(name: clean, parent: _folderId),
        'Folder created');
    if (ok) await guard(context, () => session.refreshDrive());
  }

  // ---------------- download / preview ----------------

  Future<Directory> _saveDir() async =>
      await getDownloadsDirectory() ??
      await getApplicationDocumentsDirectory();

  Future<void> _downloadFile(DriveFile f) async {
    if (f.url == null) {
      showMsg(context, 'This file is locked — download unavailable.',
          error: true);
      return;
    }
    final dir = await _saveDir();
    final savePath =
        '${dir.path}${Platform.pathSeparator}${cleanName(f.name)}';
    final session = context.read<SessionProvider>();
    final ok = await ProgressDialog.show(
      context,
      title: 'Downloading ${f.name}',
      task: (prog) => session.api.downloadFile(
        url: f.url!,
        savePath: savePath,
        onProgress: (rec, total) => prog(rec, total),
      ),
    );
    if (ok && mounted) showMsg(context, 'Saved to $savePath');
  }

  Future<void> _previewFile(DriveFile f) async {
    if (f.url == null) {
      showMsg(context, 'This file is locked — preview unavailable.',
          error: true);
      return;
    }
    if (isImageMime(f.type)) {
      await _previewImage(f);
    } else if (isVideoMime(f.type) || isAudioMime(f.type)) {
      final ok = await confirmDialog(context,
          title: 'Play media',
          message:
              'The app has no built-in player. Download "${f.name}" to play it?',
          okLabel: 'Download');
      if (ok && mounted) await _downloadFile(f);
    } else if (isPdfMime(f.type)) {
      if (!mounted) return;
      final dl = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('PDF preview'),
          content: const Text(
              'In-app PDF preview is not available. Download the file to view it.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Close')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Download')),
          ],
        ),
      );
      if (dl == true && mounted) await _downloadFile(f);
    }
  }

  Future<void> _previewImage(DriveFile f) async {
    final session = context.read<SessionProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: SizedBox(
          width: 200,
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    Uint8List? bytes;
    try {
      final r = await Dio().get<List<int>>(
        session.api.previewUrl(f.url!),
        options: Options(responseType: ResponseType.bytes),
      );
      final data = r.data;
      if (data != null && data.isNotEmpty) bytes = Uint8List.fromList(data);
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showMsg(context, 'Preview failed: $e', error: true);
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (bytes == null) {
      showMsg(context, 'Preview failed: empty response', error: true);
      return;
    }
    final img = bytes;
    await showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(c),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(img, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
                onPressed: () {
                  Navigator.pop(c);
                  _downloadFile(f);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- context menus ----------------

  void _fileMenu(DriveFile f) {
    final session = context.read<SessionProvider>();
    final isAdmin = session.isAdmin;
    final locked = f.url == null;
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: FileTypeIcon(name: f.name, mime: f.type),
                title: Text(f.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${formatBytes(f.size)} · ${formatRelativeMs(f.uploadedAt)}'),
              ),
              const Divider(height: 1),
              if (locked)
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Locked'),
                  subtitle: Text((f.locked?['reason'] ??
                          f.locked?['by'] ??
                          'Locked by admin')
                      .toString()),
                )
              else ...[
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Download'),
                  onTap: () {
                    Navigator.pop(c);
                    _downloadFile(f);
                  },
                ),
                if (_previewable(f))
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Preview'),
                    onTap: () {
                      Navigator.pop(c);
                      _previewFile(f);
                    },
                  ),
              ],
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(c);
                  _renameFile(f);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Move to…'),
                onTap: () {
                  Navigator.pop(c);
                  _moveDialog(fileIds: [f.id]);
                },
              ),
              if (!locked)
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Upload new version'),
                  onTap: () {
                    Navigator.pop(c);
                    _uploadNewVersion(f);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text('Versions${f.vc > 0 ? ' (${f.vc + 1})' : ''}'),
                onTap: () {
                  Navigator.pop(c);
                  _showVersions(f);
                },
              ),
              if (isAdmin && !locked)
                ListTile(
                  leading: const Icon(Icons.link_outlined),
                  title: const Text('Share link…'),
                  onTap: () {
                    Navigator.pop(c);
                    _shareFile(f);
                  },
                ),
              if (isAdmin)
                ListTile(
                  leading: Icon(f.isLocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline),
                  title:
                      Text(f.isLocked ? 'Unlock file' : 'Lock file…'),
                  onTap: () {
                    Navigator.pop(c);
                    _toggleLock(f);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outlined),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(c);
                  _fileDetails(f);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                title: Text('Delete',
                    style:
                        TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.pop(c);
                  _deleteFiles([f.id], label: '"${f.name}"');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _folderMenu(DriveFolder fo) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined, size: 40),
              title: Text(fo.name,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('Created ${formatDate(fo.createdAt)}'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(c);
                _navigate(fo.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Upload files here'),
              onTap: () {
                Navigator.pop(c);
                _navigate(fo.id);
                _uploadFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(c);
                _renameFolder(fo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to…'),
              onTap: () {
                Navigator.pop(c);
                _moveDialog(folderIds: [fo.id]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outlined),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(c);
                _folderDetails(fo);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(c);
                _deleteFolders([fo.id], label: '"${fo.name}"');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------- item actions ----------------

  Future<void> _renameFile(DriveFile f) async {
    final name = await promptDialog(context,
        title: 'Rename file', initial: f.name, okLabel: 'Rename');
    if (name == null || !mounted) return;
    final clean = cleanName(name);
    if (clean.isEmpty || clean == f.name) return;
    final session = context.read<SessionProvider>();
    final ok = await _run(
        () => session.api
            .patchItem(id: f.id, kind: 'file', name: clean),
        'Renamed');
    if (ok) await guard(context, () => session.refreshDrive());
  }

  Future<void> _renameFolder(DriveFolder fo) async {
    final name = await promptDialog(context,
        title: 'Rename folder', initial: fo.name, okLabel: 'Rename');
    if (name == null || !mounted) return;
    final clean = cleanName(name);
    if (clean.isEmpty || clean == fo.name) return;
    final session = context.read<SessionProvider>();
    final ok = await _run(
        () => session.api
            .patchItem(id: fo.id, kind: 'folder', name: clean),
        'Renamed');
    if (ok) await guard(context, () => session.refreshDrive());
  }

  Future<void> _uploadNewVersion(DriveFile f) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (res == null || !mounted) return;
    final pf = res.files.first;
    if (pf.path == null || pf.path!.isEmpty) return;
    final note = await promptDialog(context,
        title: 'New version',
        hint: 'Version note (optional)',
        okLabel: 'Upload');
    if (note == null || !mounted) return;
    final session = context.read<SessionProvider>();
    final ok = await ProgressDialog.show(
      context,
      title: 'Uploading new version',
      task: (prog) => session.api.uploadFile(
        localPath: pf.path!,
        folderId: f.folder,
        displayName: f.name,
        mime: guessMime(pf.name),
        versionNote: note.trim().isEmpty ? null : note.trim(),
        onProgress: (s, t) => prog(s, t),
      ),
    );
    if (ok) {
      await guard(context, () => session.refreshDrive());
      if (mounted) showMsg(context, 'New version uploaded');
    }
  }

  Future<void> _moveDialog(
      {List<String>? fileIds, List<String>? folderIds}) async {
    final session = context.read<SessionProvider>();
    final drive = session.drive;
    if (drive == null) return;
    // Folders cannot be moved into themselves or their own descendants.
    final banned = <String>{};
    for (final id in folderIds ?? const <String>[]) {
      banned.add(id);
      var changed = true;
      while (changed) {
        changed = false;
        for (final e in drive.folders.entries) {
          if (banned.contains(e.value.parent) &&
              !banned.contains(e.key)) {
            banned.add(e.key);
            changed = true;
          }
        }
      }
    }
    final options = drive.folders.entries
        .where((e) => !banned.contains(e.key))
        .toList()
      ..sort((a, b) => _folderPathText(drive, a.key)
          .compareTo(_folderPathText(drive, b.key)));
    final dest = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Move to…'),
        content: SizedBox(
          width: 400,
          height: 380,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('My Drive'),
                subtitle: const Text('Root folder'),
                onTap: () => Navigator.pop(c, 'root'),
              ),
              const Divider(),
              for (final e in options)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(e.value.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_folderPathText(drive, e.key),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(c, e.key),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (dest == null || !mounted) return;
    final n = (fileIds?.length ?? 0) + (folderIds?.length ?? 0);
    await _run(() async {
      for (final id in fileIds ?? const <String>[]) {
        await session.api.patchItem(id: id, kind: 'file', parent: dest);
      }
      for (final id in folderIds ?? const <String>[]) {
        await session.api.patchItem(id: id, kind: 'folder', parent: dest);
      }
      await session.refreshDrive();
    }, n == 1 ? 'Moved' : '$n items moved');
  }

  Future<void> _showVersions(DriveFile f) async {
    final session = context.read<SessionProvider>();
    final versions =
        await guard(context, () => session.api.getVersions(f.id));
    if (versions == null || !mounted) return;
    var list = versions;
    Future<void> reload(StateSetter setD) async {
      final v = await guard(context, () => session.api.getVersions(f.id));
      if (v != null) setD(() => list = v);
      await guard(context, () => session.refreshDrive());
    }

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Versions — ${f.name}'),
          content: SizedBox(
            width: 460,
            height: 400,
            child: list.isEmpty
                ? const Center(child: Text('No versions'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final v = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                            child: Text('v${v.ver}',
                                style: const TextStyle(fontSize: 12))),
                        title: Text(
                            '${formatBytes(v.size)} · ${formatDateTime(v.uploadedAt)}'),
                        subtitle: Text(
                            '${v.uploadedBy}${v.note != null && v.note!.isNotEmpty ? ' — ${v.note}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: v.current
                            ? const Chip(
                                label: Text('Current',
                                    style: TextStyle(fontSize: 11)))
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    child: const Text('Restore'),
                                    onPressed: () async {
                                      final ok = await _run(
                                          () => session.api.restoreVersion(
                                              id: f.id, ver: v.ver),
                                          'Version v${v.ver} restored');
                                      if (ok) await reload(setD);
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Delete version',
                                    icon: Icon(Icons.delete_outline,
                                        size: 20,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error),
                                    onPressed: () async {
                                      final yes = await confirmDialog(
                                          context,
                                          title: 'Delete version v${v.ver}',
                                          message:
                                              'Delete this old version permanently?');
                                      if (!yes || !mounted) return;
                                      final ok = await _run(
                                          () => session.api.deleteVersion(
                                              id: f.id, ver: v.ver),
                                          'Version deleted');
                                      if (ok) await reload(setD);
                                    },
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Future<void> _shareFile(DriveFile f) async {
    final pw = await promptDialog(context,
        title: 'Share link',
        hint: 'Optional password (leave empty for none)',
        okLabel: 'Create link');
    if (pw == null || !mounted) return;
    final session = context.read<SessionProvider>();
    final link = await guard(
        context,
        () => session.api.createShare(
            fileId: f.id, password: pw.trim().isEmpty ? null : pw.trim()));
    if (link == null || !mounted) return;
    final url = session.api.shareUrl(link.id);
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Share link created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(url),
            const SizedBox(height: 8),
            const Text(
                'Anyone with this link can download the file.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
              showMsg(context, 'Link copied');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLock(DriveFile f) async {
    final session = context.read<SessionProvider>();
    if (f.isLocked) {
      final yes = await confirmDialog(context,
          title: 'Unlock file',
          message: 'Unlock "${f.name}"? Members will be able to download it again.',
          okLabel: 'Unlock');
      if (!yes || !mounted) return;
      final ok = await _run(
          () => session.api.setFileLock(id: f.id, locked: false),
          'File unlocked');
      if (ok) await guard(context, () => session.refreshDrive());
    } else {
      final reason = await promptDialog(context,
          title: 'Lock file',
          hint: 'Reason shown to members (optional)',
          okLabel: 'Lock');
      if (reason == null || !mounted) return;
      final ok = await _run(
          () => session.api.setFileLock(
              id: f.id,
              locked: true,
              reason: reason.trim().isEmpty ? null : reason.trim()),
          'File locked');
      if (ok) await guard(context, () => session.refreshDrive());
    }
  }

  void _fileDetails(DriveFile f) {
    final drive = context.read<SessionProvider>().drive;
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(f.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(theme, 'Type', f.type),
              _kv(theme, 'Size', formatBytes(f.size)),
              _kv(theme, 'Location',
                  drive == null ? f.folder : _folderPathText(drive, f.folder)),
              _kv(theme, 'Uploaded',
                  '${formatDateTime(f.uploadedAt)} (${formatRelativeMs(f.uploadedAt)})'),
              _kv(theme, 'Uploaded by', f.uploadedBy),
              _kv(theme, 'Version',
                  'v${f.ver}${f.vc > 0 ? ' · ${f.vc} older' : ''}'),
              if (f.note != null && f.note!.isNotEmpty)
                _kv(theme, 'Note', f.note!),
              _kv(theme, 'Status',
                  f.isLocked
                      ? 'Locked${f.locked?['reason'] != null ? ' — ${f.locked!['reason']}' : ''}'
                      : 'Unlocked'),
              if (f.shares > 0) _kv(theme, 'Shares', '${f.shares}'),
            ],
          ),
        ),
        actions: [
          if (f.url != null && _previewable(f))
            TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _previewFile(f);
                },
                child: const Text('Preview')),
          if (f.url != null)
            TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _downloadFile(f);
                },
                child: const Text('Download')),
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _folderDetails(DriveFolder fo) {
    final drive = context.read<SessionProvider>().drive;
    final theme = Theme.of(context);
    var subFolders = 0;
    var files = 0;
    if (drive != null) {
      for (final f in drive.folders.values) {
        if (f.parent == fo.id) subFolders++;
      }
      for (final f in drive.files.values) {
        if (f.folder == fo.id) files++;
      }
    }
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(fo.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(theme, 'Location',
                drive == null ? fo.parent : _folderPathText(drive, fo.parent)),
            _kv(theme, 'Created', formatDateTime(fo.createdAt)),
            _kv(theme, 'Contents',
                '$subFolders folder${subFolders == 1 ? '' : 's'}, $files file${files == 1 ? '' : 's'}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(k,
                  style: TextStyle(color: theme.colorScheme.outline)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );

  // ---------------- delete ----------------

  Future<void> _deleteFiles(List<String> ids, {String? label}) async {
    final yes = await confirmDialog(context,
        title: 'Delete ${label ?? '${ids.length} files'}',
        message: ids.length == 1
            ? 'Delete this file permanently? This cannot be undone.'
            : 'Delete ${ids.length} files permanently? This cannot be undone.');
    if (!yes || !mounted) return;
    final session = context.read<SessionProvider>();
    final ok = await _run(() async {
      await session.api.deleteItems(folders: [], files: ids);
      await session.refreshDrive();
    }, 'Deleted');
    if (ok) _clearSelection();
  }

  Future<void> _deleteFolders(List<String> ids, {String? label}) async {
    final yes = await confirmDialog(context,
        title: 'Delete ${label ?? '${ids.length} folders'}',
        message:
            'Delete ${ids.length == 1 ? 'this folder' : '${ids.length} folders'} and ALL of its contents? This cannot be undone.');
    if (!yes || !mounted) return;
    final session = context.read<SessionProvider>();
    final ok = await _run(() async {
      await session.api.deleteItems(folders: ids, files: []);
      await session.refreshDrive();
    }, 'Deleted');
    if (ok) {
      _clearSelection();
      if (ids.contains(_folderId)) _navigate('root');
    }
  }

  Future<void> _deleteSelected() async {
    final nf = _selFiles.length;
    final nd = _selFolders.length;
    final label = [
      if (nf > 0) '$nf file${nf == 1 ? '' : 's'}',
      if (nd > 0) '$nd folder${nd == 1 ? '' : 's'}',
    ].join(' and ');
    final yes = await confirmDialog(context,
        title: 'Delete $label',
        message:
            'Delete $label permanently? Folders are deleted with ALL of their contents. This cannot be undone.');
    if (!yes || !mounted) return;
    final session = context.read<SessionProvider>();
    final fileIds = _selFiles.toList();
    final folderIds = _selFolders.toList();
    final ok = await _run(() async {
      await session.api
          .deleteItems(folders: folderIds, files: fileIds);
      await session.refreshDrive();
    }, 'Deleted');
    if (ok) {
      _clearSelection();
      if (folderIds.contains(_folderId)) _navigate('root');
    }
  }

  Future<void> _moveSelected() =>
      _moveDialog(fileIds: _selFiles.toList(), folderIds: _selFolders.toList());
}
