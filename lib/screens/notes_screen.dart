import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Private notes, Google-Keep-like. Parity with the web app's Notes view:
/// pinned section, checklist notes, 11 colors, labels, archive view, search.
class NotesScreen extends StatefulWidget {
  /// Set by the shell: opens the editor for a new note.
  static VoidCallback? requestNew;

  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

// 11 note colors, light + dark palettes (lifted from the web app).
const _colorKeys = [
  'default',
  'red',
  'orange',
  'yellow',
  'green',
  'teal',
  'blue',
  'purple',
  'pink',
  'brown',
  'gray'
];
const _lightCols = {
  'default': 0xFFFFFFFF,
  'red': 0xFFFAAFA8,
  'orange': 0xFFF39F76,
  'yellow': 0xFFFFF8B8,
  'green': 0xFFE2F6D3,
  'teal': 0xFFB4DDD3,
  'blue': 0xFFD4E4ED,
  'purple': 0xFFD3BFDB,
  'pink': 0xFFF6E2DD,
  'brown': 0xFFE9E3D4,
  'gray': 0xFFEFEFF1,
};
const _darkCols = {
  'default': 0xFF1E293B,
  'red': 0xFF5C1F2B,
  'orange': 0xFF5E2B14,
  'yellow': 0xFF5A4410,
  'green': 0xFF264D3B,
  'teal': 0xFF0F4C48,
  'blue': 0xFF1F4A5E,
  'purple': 0xFF3F2B55,
  'pink': 0xFF5A2D40,
  'brown': 0xFF4B3F30,
  'gray': 0xFF2B3140,
};

Color _noteBg(String? key, Brightness b) {
  final map = b == Brightness.dark ? _darkCols : _lightCols;
  return Color(map[key] ?? map['default']!);
}

Color _noteFg(String? key, Brightness b) {
  final bg = _noteBg(key, b);
  return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _showArchived = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    NotesScreen.requestNew = _openNew;
    _load();
  }

  @override
  void dispose() {
    NotesScreen.requestNew = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final notes = await guard(context, () => _api.getNotes());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notes = notes ?? [];
      if (notes == null) _error = 'Could not load notes.';
    });
  }

  void _openNew() {
    if (!mounted) return;
    _openEditor(null);
  }

  Future<void> _openEditor(Note? note, {bool checklist = false}) async {
    final wide = MediaQuery.of(context).size.width >= 700;
    bool? changed;
    if (wide) {
      changed = await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _NoteEditorPage(note: note, startChecklist: checklist),
            ),
          ),
        ),
      );
    } else {
      changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (_) =>
                _NoteEditorPage(note: note, startChecklist: checklist)),
      );
    }
    if (changed == true && mounted) _load();
  }

  /// Deep copy used by the card quick-actions (pin / archive / color / items).
  Note _clone(Note n) => Note(
        id: n.id,
        title: n.title,
        body: n.body,
        items:
            n.items?.map((i) => NoteItem(t: i.t, d: i.d)).toList(),
        color: n.color,
        pinned: n.pinned,
        archived: n.archived,
        labels: List.of(n.labels),
      );

  /// Web-app `quick(patch)`: save a patched note, then refresh the list.
  Future<void> _quickSave(Note n) async {
    final ok = await guard(context, () => _api.saveNote(n));
    if (ok != null && mounted) _load();
  }

  Future<void> _togglePin(Note n) async {
    final c = _clone(n);
    c.pinned = !c.pinned;
    await _quickSave(c);
  }

  Future<void> _toggleArchive(Note n) async {
    final c = _clone(n);
    c.archived = !c.archived;
    c.pinned = false;
    final ok = await guard(context, () => _api.saveNote(c));
    if (ok != null && mounted) {
      showMsg(context, c.archived ? 'Note archived' : 'Note unarchived');
      _load();
    }
  }

  Future<void> _toggleItem(Note n, NoteItem it) async {
    final c = _clone(n);
    c.items = (n.items ?? [])
        .map((i) => NoteItem(t: i.t, d: identical(i, it) ? !i.d : i.d))
        .toList();
    await _quickSave(c);
  }

  Future<void> _pickColor(Note n) async {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Background'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final k in _colorKeys)
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(k),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _noteBg(k, theme.brightness),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: k == n.color
                          ? (night
                              ? AppColors.brandDark
                              : AppColors.brandLight)
                          : theme.dividerColor,
                      width: k == n.color ? 2.5 : 1,
                    ),
                  ),
                  child: k == n.color
                      ? Icon(Icons.check,
                          size: 18,
                          color:
                              _noteFg(k, theme.brightness))
                      : null,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen != null && chosen != n.color && mounted) {
      final c = _clone(n);
      c.color = chosen;
      await _quickSave(c);
    }
  }

  /// Web-app "Copy text": copies title + checklist/body to the clipboard.
  Future<void> _copyNoteText(Note n) async {
    final items = n.items ?? [];
    final parts = <String>[];
    if (n.title.isNotEmpty) parts.add(n.title);
    if (items.isNotEmpty) {
      parts.add(items.map((x) => '${x.d ? '[x]' : '[ ]'} ${x.t}').join('\n'));
    } else if (n.body.isNotEmpty) {
      parts.add(n.body);
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (mounted) showMsg(context, 'Note copied');
  }

  Future<void> _deleteNote(Note n) async {
    final id = n.id;
    if (id == null) return;
    final yes = await confirmDialog(context,
        title: 'Delete note?',
        message: 'This note will be permanently deleted.');
    if (!yes || !mounted) return;
    final ok = await guard(context, () async {
      await _api.deleteNote(id);
      return true;
    });
    if (ok == true && mounted) _load();
  }

  List<Note> get _visible {
    var list = _notes.where((n) => n.archived == _showArchived).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) {
        if (n.title.toLowerCase().contains(q)) return true;
        if (n.body.toLowerCase().contains(q)) return true;
        if (n.labels.any((l) => l.toLowerCase().contains(q))) return true;
        if (n.items?.any((i) => i.t.toLowerCase().contains(q)) ?? false) {
          return true;
        }
        return false;
      }).toList();
    }
    return list;
  }

  /// Web-app parity card: colored pastel bg, blue pin top-right, tappable
  /// square checkboxes, bottom tools row (palette / archive / copy / delete).
  /// Interactive children are never nested inside another tap handler, so a
  /// tap does exactly one thing (mirrors the web's stopPropagation).
  Widget _noteCard(Note n) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final night = b == Brightness.dark;
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final bg = _noteBg(n.color, b);
    final fg = _noteFg(n.color, b);
    final dim = fg.withOpacity(0.55);
    final items = n.items ?? [];
    void open() => _openEditor(n);

    final titleStyle = TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: fg);

    Widget? preview;
    if (items.isNotEmpty) {
      final undone = items.where((i) => !i.d).toList();
      final doneList = items.where((i) => i.d).toList();
      final shown = [...undone, ...doneList].take(10).toList();
      preview = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: it.d,
                      onChanged: (_) => _toggleItem(n, it),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      activeColor: brand,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      onTap: open,
                      child: Text(it.t,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: fg,
                              decoration: it.d
                                  ? TextDecoration.lineThrough
                                  : null)),
                    ),
                  ),
                ],
              ),
            ),
          if (items.length > 10)
            InkWell(
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${items.length - 10} more',
                    style: TextStyle(fontSize: 12, color: dim)),
              ),
            ),
        ],
      );
    } else if (n.body.isNotEmpty) {
      preview = InkWell(
        onTap: open,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 2),
          child: Text(n.body,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: fg)),
        ),
      );
    }

    Widget toolBtn(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 18),
          color: dim,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: onTap,
        );

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: open,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12)),
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 14, 0, 2),
                    child: n.title.isEmpty
                        ? const SizedBox(height: 8)
                        : Text(n.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.only(top: 8, right: 8),
                child: IconButton(
                  tooltip: n.pinned ? 'Unpin' : 'Pin',
                  icon: Icon(
                      n.pinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 18),
                  color: n.pinned ? brand : dim,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: () => _togglePin(n),
                ),
              ),
            ],
          ),
          if (preview != null)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: preview,
            ),
          if (n.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: open,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final l in n.labels)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: night
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.07),
                          borderRadius:
                              BorderRadius.circular(12),
                        ),
                        child: Text(l,
                            style: TextStyle(
                                fontSize: 11, color: fg)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                toolBtn(Icons.palette_outlined, 'Background',
                    () => _pickColor(n)),
                toolBtn(
                    n.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    n.archived ? 'Unarchive' : 'Archive',
                    () => _toggleArchive(n)),
                toolBtn(Icons.copy_outlined, 'Copy text',
                    () => _copyNoteText(n)),
                toolBtn(Icons.delete_outline, 'Delete',
                    () => _deleteNote(n)),
                const Spacer(),
                if (n.updatedAt > 0)
                  Text(
                      DateFormat('MMM d, yyyy').format(
                          DateTime.fromMillisecondsSinceEpoch(n.updatedAt)),
                      style: TextStyle(fontSize: 11, color: dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Web `.sec-title`: 11px/800 uppercase, muted, with a divider rule after.
  Widget _section(String label, bool night) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
        child: Row(
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: night
                        ? AppColors.nightMuted
                        : AppColors.dayMuted)),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: night
                    ? AppColors.nightLine2
                    : AppColors.dayLine,
              ),
            ),
          ],
        ),
      );

  /// "Notes" heading + Notes/Archive segmented control (web parity).
  Widget _header(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Text('Notes',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: night
                      ? AppColors.nightText
                      : AppColors.dayText)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: night
                  ? AppColors.nightSide2
                  : const Color(0xFFE4E1D6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segBtn('Notes', Icons.lightbulb_outline,
                    !_showArchived,
                    () => setState(() => _showArchived = false),
                    night, brand),
                _segBtn('Archive', Icons.archive_outlined,
                    _showArchived,
                    () => setState(() => _showArchived = true),
                    night, brand),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segBtn(String label, IconData icon, bool active,
      VoidCallback onTap, bool night, Color brand) {
    final fg = active
        ? (night ? Colors.white : const Color(0xFF1E40AF))
        : (night ? AppColors.nightMuted : AppColors.dayMuted);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? (night
                  ? const Color(0xFF33415E)
                  : const Color(0xFFD7E3FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg)),
          ],
        ),
      ),
    );
  }

  /// "Take a note…" composer bar — checklist icon left, pencil right.
  /// The middle area opens the text editor; the icons open their own modes.
  /// (Icons are siblings of the tap area, never nested inside it, so one
  /// tap can only ever fire one action.)
  Widget _composerBar(bool night) {
    final muted =
        night ? AppColors.nightMuted : AppColors.dayMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: night ? AppColors.nightPanel : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  night ? AppColors.nightLine : AppColors.dayLine),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'New list',
              icon:
                  const Icon(Icons.checklist_outlined, size: 20),
              color: muted,
              onPressed: () =>
                  _openEditor(null, checklist: true),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openEditor(null),
                child: Container(
                  height: 52,
                  alignment: Alignment.centerLeft,
                  child: Text('Take a note…',
                      style:
                          TextStyle(fontSize: 14, color: muted)),
                ),
              ),
            ),
            IconButton(
              tooltip: 'New note',
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: muted,
              onPressed: () => _openEditor(null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(bool night) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search notes…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  }),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(night),
          if (!_showArchived) _composerBar(night),
          _searchBar(night),
          Expanded(
            child: _loading
                ? const LoadingView(label: 'Loading notes…')
                : _error != null
                    ? ErrorView(
                        message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: Builder(builder: (context) {
                          final vis = _visible;
                          if (vis.isEmpty) {
                            return ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                    height:
                                        MediaQuery.of(context)
                                                .size
                                                .height *
                                            0.55,
                                    child: EmptyView(
                                        icon: _showArchived
                                            ? Icons.archive_outlined
                                            : Icons
                                                .lightbulb_outline,
                                        message: _showArchived
                                            ? 'No archived notes.'
                                            : 'No notes yet — tap "Take a note…" to create one.')),
                              ],
                            );
                          }
                          final pinned = _showArchived
                              ? <Note>[]
                              : vis
                                  .where((n) => n.pinned)
                                  .toList();
                          final others = _showArchived
                              ? vis
                              : vis
                                  .where((n) => !n.pinned)
                                  .toList();
                          return LayoutBuilder(
                              builder: (context, cons) {
                            final maxW = cons.maxWidth;
                            final cardW = maxW >= 700
                                ? 300.0
                                : (maxW - 48)
                                    .clamp(200.0, 600.0);
                            Widget wrap(List<Note> list) =>
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                          24, 0, 24, 12),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      for (final n in list)
                                        SizedBox(
                                            width: cardW,
                                            child:
                                                _noteCard(n)),
                                    ],
                                  ),
                                );
                            return ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              children: [
                                if (!_showArchived &&
                                    pinned.isNotEmpty) ...[
                                  _section('Pinned', night),
                                  wrap(pinned),
                                ],
                                if (others.isNotEmpty) ...[
                                  if (pinned.isNotEmpty &&
                                      !_showArchived)
                                    _section('Others', night),
                                  if (_showArchived)
                                    _section(
                                        'Archived', night),
                                  wrap(others),
                                ],
                                const SizedBox(height: 80),
                              ],
                            );
                          });
                        }),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------- note editor ----------------

/// Full-screen note editor: title, body, checklist, color, pin, archive,
/// labels, save, delete. Auto-deletes an existing note saved empty
/// (web-app behavior).
class _NoteEditorPage extends StatefulWidget {
  final Note? note;
  final bool startChecklist;
  const _NoteEditorPage({this.note, this.startChecklist = false});

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _labelsCtrl;
  late List<NoteItem> _items;
  late List<FocusNode> _itemFocus;
  late List<TextEditingController> _itemCtrls;
  late String _color;
  late bool _pinned;
  late bool _archived;
  bool _saving = false;
  bool _checklist = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _titleCtrl = TextEditingController(text: n?.title ?? '');
    _bodyCtrl = TextEditingController(text: n?.body ?? '');
    _labelsCtrl =
        TextEditingController(text: (n?.labels ?? []).join(', '));
    _items = (n?.items ?? []).map((i) => NoteItem(t: i.t, d: i.d)).toList();
    _itemFocus = List.generate(_items.length, (_) => FocusNode());
    _itemCtrls = _items.map((i) => TextEditingController(text: i.t)).toList();
    _color = n?.color ?? 'default';
    _pinned = n?.pinned ?? false;
    _archived = n?.archived ?? false;
    _checklist = _items.isNotEmpty || widget.startChecklist;
    if (_checklist && _items.isEmpty) {
      _items.add(NoteItem(t: '', d: false));
      _itemFocus.add(FocusNode());
      _itemCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _labelsCtrl.dispose();
    for (final f in _itemFocus) {
      f.dispose();
    }
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  bool get _isEmpty =>
      _titleCtrl.text.trim().isEmpty &&
      _bodyCtrl.text.trim().isEmpty &&
      _items.every((i) => i.t.trim().isEmpty);

  List<String> _labels() => _labelsCtrl.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .take(10)
      .map((s) => s.length > 40 ? s.substring(0, 40) : s)
      .toList();

  void _addItem([String text = '']) {
    setState(() {
      _items.add(NoteItem(t: text, d: false));
      _itemFocus.add(FocusNode());
      _itemCtrls.add(TextEditingController(text: text));
      _checklist = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _itemFocus.last.requestFocus();
    });
  }

  void _removeItem(int i) {
    setState(() {
      _itemFocus[i].dispose();
      _itemFocus.removeAt(i);
      _itemCtrls[i].dispose();
      _itemCtrls.removeAt(i);
      _items.removeAt(i);
      if (_items.isEmpty) _checklist = false;
    });
  }

  void _toggleChecklist() {
    setState(() {
      _checklist = !_checklist;
      if (_checklist && _items.isEmpty) {
        _items.add(NoteItem(t: '', d: false));
        _itemFocus.add(FocusNode());
        _itemCtrls.add(TextEditingController());
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // Sync checklist text fields back into the item models.
    for (var i = 0; i < _items.length && i < _itemCtrls.length; i++) {
      _items[i].t = _itemCtrls[i].text;
    }
    final id = widget.note?.id;
    if (_isEmpty) {
      // Web-app behavior: auto-delete a note saved empty.
      if (id != null) {
        final ok = await guard(context, () async {
          await _api.deleteNote(id);
          return true;
        });
        if (ok == true && mounted) Navigator.pop(context, true);
      } else if (mounted) {
        Navigator.pop(context, false);
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final note = Note(
        id: id,
        title: _titleCtrl.text.trim().length > 500
            ? _titleCtrl.text.trim().substring(0, 500)
            : _titleCtrl.text.trim(),
        body: _bodyCtrl.text.length > 50000
            ? _bodyCtrl.text.substring(0, 50000)
            : _bodyCtrl.text,
        items: _checklist
            ? _items
                .where((i) => i.t.trim().isNotEmpty)
                .take(500)
                .map((i) => NoteItem(
                    t: i.t.length > 2000
                        ? i.t.substring(0, 2000)
                        : i.t,
                    d: i.d))
                .toList()
            : null,
        color: _color,
        pinned: _pinned,
        archived: _archived,
        labels: _labels(),
      );
      final savedId = await guard(context, () => _api.saveNote(note));
      if (savedId != null && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.note?.id;
    if (id == null) {
      Navigator.pop(context, false);
      return;
    }
    final yes = await confirmDialog(context,
        title: 'Delete note?',
        message: 'This note will be permanently deleted.');
    if (!yes) return;
    final ok = await guard(context, () async {
      await _api.deleteNote(id);
      return true;
    });
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  Widget _checklistEditor(Color fg) {
    return Column(
      children: [
        for (var i = 0; i < _items.length; i++)
          Row(
            children: [
              Checkbox(
                value: _items[i].d,
                onChanged: (v) =>
                    setState(() => _items[i].d = v ?? false),
              ),
              Expanded(
                child: TextField(
                  focusNode: _itemFocus[i],
                  controller: _itemCtrls[i],
                  style: TextStyle(
                      color: fg,
                      decoration: _items[i].d
                          ? TextDecoration.lineThrough
                          : null),
                  decoration: const InputDecoration(
                      hintText: 'List item',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero),
                  onChanged: (v) => _items[i].t = v,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _addItem(),
                  onEditingComplete: () {},
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: fg.withOpacity(0.6),
                onPressed: () => _removeItem(i),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () => _addItem(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add item'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = _noteBg(_color, theme.brightness);
    final fg = _noteFg(_color, theme.brightness);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Background color',
            icon: const Icon(Icons.palette_outlined),
            onSelected: (k) => setState(() => _color = k),
            itemBuilder: (c) => [
              for (final k in _colorKeys)
                PopupMenuItem(
                  value: k,
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _noteBg(k, theme.brightness),
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: k == _color
                            ? Icon(Icons.check,
                                size: 14,
                                color: _noteFg(k, theme.brightness))
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Text(k == 'default' ? 'Default' : k),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _pinned ? 'Unpin' : 'Pin',
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => setState(() => _pinned = !_pinned),
          ),
          IconButton(
            tooltip: _archived ? 'Unarchive' : 'Archive',
            icon: Icon(_archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            onPressed: () => setState(() => _archived = !_archived),
          ),
          if (widget.note?.id != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: fg))
                : Text('Save',
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              maxLength: 500,
              style: TextStyle(
                  color: fg,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(color: fg.withOpacity(0.5)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
            TextField(
              controller: _labelsCtrl,
              style: TextStyle(color: fg),
              decoration: InputDecoration(
                hintText: 'Labels (comma-separated)',
                hintStyle: TextStyle(color: fg.withOpacity(0.5)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                prefixIcon: Icon(Icons.label_outline,
                    size: 18, color: fg.withOpacity(0.6)),
              ),
            ),
            const SizedBox(height: 4),
            if (!_checklist)
              TextField(
                controller: _bodyCtrl,
                maxLines: null,
                minLines: 8,
                style: TextStyle(color: fg),
                decoration: InputDecoration(
                  hintText: 'Note…',
                  hintStyle:
                      TextStyle(color: fg.withOpacity(0.5)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              )
            else
              _checklistEditor(fg),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _toggleChecklist,
              icon: Icon(_checklist
                  ? Icons.notes_outlined
                  : Icons.checklist_outlined),
              label: Text(
                  _checklist ? 'Remove checklist' : 'Add checklist'),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
