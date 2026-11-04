import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import 'announcements_screen.dart';
import 'database_screen.dart';
import 'diary_screen.dart';
import 'drive_screen.dart';
import 'group_screen.dart';
import 'members_screen.dart';
import 'notes_screen.dart';
import 'recent_screen.dart';
import 'settings_screen.dart';
import 'shares_screen.dart';
import 'storage_screen.dart';
import 'tickets_screen.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final Widget Function() build;
  final bool adminOnly;
  const _NavItem(
      {required this.label,
      required this.icon,
      required this.build,
      this.adminOnly = false});
}

/// App shell: sidebar navigation (WORKSPACE / TEAM / MANAGE sections),
/// topbar with search (Ctrl+K), refresh, theme toggle, profile menu,
/// and the storage card at the bottom of the sidebar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  Key _bodyKey = UniqueKey();

  List<_NavItem> _items(bool isAdmin) => [
        _NavItem(
            label: 'My Drive',
            icon: Icons.cloud_outlined,
            build: () => const DriveScreen()),
        _NavItem(
            label: 'Recent',
            icon: Icons.history_outlined,
            build: () => const RecentScreen()),
        _NavItem(
            label: 'Notes',
            icon: Icons.note_outlined,
            build: () => const NotesScreen()),
        _NavItem(
            label: 'Support',
            icon: Icons.support_agent_outlined,
            build: () => const SupportScreen()),
        _NavItem(
            label: 'Diary',
            icon: Icons.book_outlined,
            build: () => const DiaryScreen()),
        _NavItem(
            label: 'Database',
            icon: Icons.table_chart_outlined,
            build: () => const DatabaseScreen()),
        _NavItem(
            label: 'Group',
            icon: Icons.forum_outlined,
            build: () => const GroupScreen()),
        _NavItem(
            label: 'Shared links',
            icon: Icons.link_outlined,
            build: () => const SharesScreen(),
            adminOnly: true),
        _NavItem(
            label: 'Announcements',
            icon: Icons.campaign_outlined,
            build: () => const AnnouncementsScreen(),
            adminOnly: true),
        _NavItem(
            label: 'Members',
            icon: Icons.group_outlined,
            build: () => const MembersScreen(),
            adminOnly: true),
        _NavItem(
            label: 'Storage',
            icon: Icons.storage_outlined,
            build: () => const StorageScreen(),
            adminOnly: true),
      ];

  List<_NavItem> _visible(bool isAdmin) =>
      _items(isAdmin).where((i) => !i.adminOnly || isAdmin).toList();

  void _refresh() {
    setState(() => _bodyKey = UniqueKey());
    context.read<SessionProvider>().refreshDrive().catchError((_) {});
  }

  Future<void> _globalSearch() async {
    final session = context.read<SessionProvider>();
    final drive = session.drive;
    if (drive == null) return;
    final q = await showDialog<String>(
      context: context,
      builder: (c) => _SearchDialog(drive: drive),
    );
    if (q != null && q.isNotEmpty && mounted) {
      // Jump to My Drive and let it apply the query.
      final items = _visible(session.isAdmin);
      final idx = items.indexWhere((e) => e.label == 'My Drive');
      setState(() {
        _index = idx;
        _bodyKey = UniqueKey();
      });
      // Hand the query to the drive screen via a static handoff.
      DriveScreen.pendingQuery = q;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final theme = context.watch<ThemeProvider>();
    final night = theme.night;
    final isAdmin = session.isAdmin;
    final items = _visible(isAdmin);
    if (_index >= items.length) _index = 0;
    final wide = MediaQuery.of(context).size.width >= 900;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const _SearchIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(
              onInvoke: (_) {
            _globalSearch();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                if (wide) _buildSidebar(context, session, theme, night, items),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopbar(context, session, theme, night, items),
                      Expanded(
                          child: KeyedSubtree(
                              key: _bodyKey, child: items[_index].build())),
                    ],
                  ),
                ),
              ],
            ),
            drawer: wide
                ? null
                : Drawer(
                    child: _buildSidebar(context, session, theme, night, items,
                        inDrawer: true)),
            floatingActionButton: wide
                ? null
                : FloatingActionButton(
                    onPressed: () => _newAction(items[_index].label),
                    child: const Icon(Icons.add),
                  ),
          ),
        ),
      ),
    );
  }

  void _newAction(String tab) {
    // Dispatches the "+ New" button / mobile FAB to the active tab's screen.
    // Each screen exposes `static VoidCallback? requestNew` for its "new item" flow.
    final handler = <String, VoidCallback?>{
      'My Drive': () => DriveScreen.requestNew?.call(),
      'Notes': () => NotesScreen.requestNew?.call(),
      'Support': () => SupportScreen.requestNew?.call(),
      'Diary': () => DiaryScreen.requestNew?.call(),
      'Database': () => DatabaseScreen.requestNew?.call(),
      'Group': () => GroupScreen.requestNew?.call(),
      'Shared links': () => SharesScreen.requestNew?.call(),
      'Announcements': () => AnnouncementsScreen.requestNew?.call(),
      'Members': () => MembersScreen.requestNew?.call(),
    }[tab];
    handler?.call();
  }

  // ---------------- sidebar ----------------

  Widget _buildSidebar(BuildContext context, SessionProvider session,
      ThemeProvider theme, bool night, List<_NavItem> items,
      {bool inDrawer = false}) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final drive = session.drive;
    final user = session.user!;

    Widget sectionLabel(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(t,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: night ? AppColors.nightMuted : AppColors.dayMuted)),
        );

    Widget navTile(int i, _NavItem item) {
      final active = i == _index;
      final iconBg = active
          ? brand
          : (night ? AppColors.nightSide2 : Colors.white);
      final iconFg = active
          ? Colors.white
          : (night ? AppColors.nightSideText : AppColors.daySideText);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: active
              ? brand.withOpacity(0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _index = i);
              if (inDrawer) Navigator.pop(context);
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(item.icon, size: 18, color: iconFg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14)),
                ),
                if (item.label == 'Support' &&
                    (drive?.ticketsUnread ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('${drive!.ticketsUnread}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    // Section membership mirrors the web app.
    int idxOf(String label) => items.indexWhere((e) => e.label == label);

    return Container(
      width: 264,
      color: night ? AppColors.nightSide : AppColors.daySide,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_outlined,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Team Drive',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text('Secure file manager',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _newAction(items[_index].label),
                  icon: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 16),
                  ),
                  label: const Text('New',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  sectionLabel('WORKSPACE'),
                  for (final l in ['My Drive', 'Recent', 'Notes'])
                    if (idxOf(l) >= 0) navTile(idxOf(l), items[idxOf(l)]),
                  sectionLabel('TEAM'),
                  for (final l in ['Support', 'Diary', 'Database', 'Group'])
                    if (idxOf(l) >= 0) navTile(idxOf(l), items[idxOf(l)]),
                  if (session.isAdmin) ...[
                    sectionLabel('MANAGE'),
                    for (final l in [
                      'Shared links',
                      'Announcements',
                      'Members',
                      'Storage'
                    ])
                      if (idxOf(l) >= 0)
                        navTile(idxOf(l), items[idxOf(l)]),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: drive != null
                  ? StorageCard(
                      stats: drive.stats,
                      onTap: session.isAdmin
                          ? () {
                              final i = idxOf('Storage');
                              if (i >= 0) {
                                setState(() => _index = i);
                                if (inDrawer) Navigator.pop(context);
                              }
                            }
                          : null,
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Signed in as ${user.username} · ${user.role}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    color: night ? AppColors.nightMuted : AppColors.dayMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- topbar ----------------

  Widget _buildTopbar(BuildContext context, SessionProvider session,
      ThemeProvider theme, bool night, List<_NavItem> items) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final user = session.user!;
    return Container(
      color: night ? AppColors.nightSide : AppColors.daySide,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (!wide)
            Builder(
              builder: (c) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(c).openDrawer(),
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTap: _globalSearch,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: night ? AppColors.nightSide2 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: night
                          ? AppColors.nightLine
                          : AppColors.dayLine),
                ),
                child: Row(children: [
                  Icon(Icons.search,
                      size: 18,
                      color: night
                          ? AppColors.nightMuted
                          : AppColors.dayMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Search files…',
                        style: TextStyle(
                            color: night
                                ? AppColors.nightMuted
                                : AppColors.dayMuted,
                            fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: night
                          ? AppColors.nightHover
                          : const Color(0xFFEFEDE6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Ctrl K',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: night ? 'Day mode' : 'Night mode',
            icon: Icon(
                night ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => theme.toggle(),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _refresh,
          ),
          Container(
              width: 1,
              height: 28,
              color: night ? AppColors.nightLine : AppColors.dayLine,
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          _profileChip(context, session, night, user),
        ],
      ),
    );
  }

  Widget _profileChip(
      BuildContext context, SessionProvider session, bool night, SessionUser user) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 44),
      onSelected: (v) async {
        if (v == 'password') {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SettingsScreen()));
        } else if (v == 'logout') {
          final ok = await confirmDialog(context,
              title: 'Log out',
              message: 'Log out of Team Drive on this device?',
              okLabel: 'Log out');
          if (ok) await session.logout();
        }
      },
      itemBuilder: (c) => [
        if (!user.isAdmin)
          const PopupMenuItem(
              value: 'password',
              child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Change password'),
                  contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'logout',
            child: ListTile(
                leading: Icon(Icons.logout_outlined),
                title: Text('Log out'),
                contentPadding: EdgeInsets.zero)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
              color: night ? AppColors.nightLine : AppColors.dayLine),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AvatarWidget(
              url: session.drive?.avatars[user.username],
              name: user.username,
              radius: 14),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user.username,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text(user.role,
                    style: TextStyle(
                        fontSize: 10,
                        color: night
                            ? AppColors.nightMuted
                            : AppColors.dayMuted)),
              ]),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    );
  }
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

/// Global file search dialog (Ctrl+K).
class _SearchDialog extends StatefulWidget {
  final DriveData drive;
  const _SearchDialog({required this.drive});
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final files = widget.drive.files.entries
        .where((e) => q.isEmpty || e.value.name.toLowerCase().contains(q))
        .take(30)
        .toList();
    final folders = widget.drive.folders.entries
        .where((e) => e.key != 'root')
        .where((e) => q.isEmpty || e.value.name.toLowerCase().contains(q))
        .take(10)
        .toList();
    return AlertDialog(
      title: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: 'Search files and folders…',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none),
        onChanged: (v) => setState(() => _q = v),
      ),
      content: SizedBox(
        width: 420,
        height: 320,
        child: ListView(
          children: [
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.value.name),
                onTap: () => Navigator.pop(context, 'folder:${f.key}'),
              ),
            for (final e in files)
              ListTile(
                leading: FileTypeIcon(
                    name: e.value.name, mime: e.value.type, size: 32),
                title: Text(e.value.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(e.value.size)),
                onTap: () =>
                    Navigator.pop(context, 'file:${e.key}:${e.value.folder}'),
              ),
            if (files.isEmpty && folders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No matches')),
              ),
          ],
        ),
      ),
    );
  }
}
