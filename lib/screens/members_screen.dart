import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Admin-only member management: list, add, reset password, disable/enable,
/// set quota/pool, delete. Non-admins see a friendly empty state.
class MembersScreen extends StatefulWidget {
  static VoidCallback? requestNew;
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  static final _userRe = RegExp(r'^[a-z0-9_.-]{3,32}$');

  List<TeamMember>? _members;
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    MembersScreen.requestNew = _showAddMemberDialog;
    _load();
  }

  @override
  void dispose() {
    MembersScreen.requestNew = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final members = await guard(context, () => _api.getMembers());
    if (!mounted) return;
    setState(() {
      _members = members;
      _loading = false;
      if (members == null) _error = 'Could not load members.';
    });
  }

  List<TeamMember> get _filtered {
    final all = _members ?? [];
    if (_q.isEmpty) return all;
    final q = _q.toLowerCase();
    return all.where((m) => m.username.toLowerCase().contains(q)).toList();
  }

  // ---------------- dialogs ----------------

  Future<void> _showAddMemberDialog() async {
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'lowercase a-z 0-9 _ . - (3–32 chars)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (min 6 chars)'),
              onSubmitted: (_) => Navigator.pop(c, true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
        ],
      ),
    );
    final username = userCtrl.text.trim();
    final password = passCtrl.text;
    userCtrl.dispose();
    passCtrl.dispose();
    if (ok != true || !mounted) return;
    if (!_userRe.hasMatch(username)) {
      showMsg(context, 'Username must be 3–32 chars: lowercase a-z, 0-9, _ . -',
          error: true);
      return;
    }
    if (password.length < 6) {
      showMsg(context, 'Password must be at least 6 characters.', error: true);
      return;
    }
    final ok2 = await guard(context, () async {
      await _api.createOrResetMember(username: username, password: password);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(context, 'Member "$username" created.');
    _load();
  }

  Future<void> _resetPassword(TeamMember m) async {
    final next = await promptDialog(context,
        title: 'Reset password — ${m.username}',
        hint: 'New password (min 6 chars)',
        obscure: true,
        okLabel: 'Reset');
    if (next == null || next.length < 6 || !mounted) {
      if (next != null && mounted) {
        showMsg(context, 'Password must be at least 6 characters.', error: true);
      }
      return;
    }
    final ok2 = await guard(context, () async {
      await _api.createOrResetMember(
          username: m.username, password: next, reset: true);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(context, 'Password for "${m.username}" was reset. Their session is now invalid.');
    _load();
  }

  Future<void> _toggleDisabled(TeamMember m) async {
    final disable = !m.disabled;
    final ok = await confirmDialog(context,
        title: disable ? 'Disable member' : 'Enable member',
        message: disable
            ? '"${m.username}" will be signed out immediately and cannot log in again until re-enabled.'
            : 'Allow "${m.username}" to log in again.',
        okLabel: disable ? 'Disable' : 'Enable');
    if (!ok || !mounted) return;
    final ok2 = await guard(context, () async {
      await _api.setMemberDisabled(username: m.username, disabled: disable);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(
        context, disable ? '"${m.username}" disabled.' : '"${m.username}" enabled.');
    _load();
  }

  Future<void> _setQuota(TeamMember m) async {
    final quotaCtrl = TextEditingController(
        text: m.quotaGB != null ? m.quotaGB.toString() : '');
    final poolCtrl = TextEditingController(text: m.pool);
    bool unlimited = m.quotaGB == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text('Quota — ${m.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unlimited quota'),
                value: unlimited,
                onChanged: (v) => setDlg(() => unlimited = v ?? true),
              ),
              TextField(
                controller: quotaCtrl,
                enabled: !unlimited,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Quota (GB)', hintText: 'e.g. 20'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: poolCtrl,
                decoration: const InputDecoration(
                    labelText: 'Pool',
                    hintText: 'auto, or a pool id'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final quotaText = quotaCtrl.text.trim();
    final poolText = poolCtrl.text.trim();
    quotaCtrl.dispose();
    poolCtrl.dispose();
    if (ok != true || !mounted) return;
    double? quotaGB;
    if (!unlimited) {
      quotaGB = double.tryParse(quotaText);
      if (quotaGB == null || quotaGB <= 0) {
        showMsg(context, 'Enter a valid quota in GB, or tick Unlimited.',
            error: true);
        return;
      }
    }
    final ok2 = await guard(context, () async {
      await _api.setMemberQuota(
          username: m.username,
          quotaGB: quotaGB,
          pool: poolText.isEmpty ? null : poolText);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(context, 'Quota for "${m.username}" updated.');
    _load();
  }

  Future<void> _deleteMember(TeamMember m) async {
    final ok = await confirmDialog(context,
        title: 'Delete member',
        message:
            'Delete "${m.username}"? This removes their notes, avatars and diary, and keeps their folder as "${m.username} (removed)". This cannot be undone.',
        okLabel: 'Delete');
    if (!ok || !mounted) return;
    final ok2 = await guard(context, () async {
      await _api.deleteMember(m.username);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(context, '"${m.username}" deleted.');
    _load();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    if (!session.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Members')),
        body: const EmptyView(
            icon: Icons.lock_outline,
            message: 'Members is for admins only.'),
      );
    }
    final avatars = session.drive?.avatars ?? {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add member',
            onPressed: _showAddMemberDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search members…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(child: _buildBody(avatars)),
        ],
      ),
    );
  }

  Widget _buildBody(Map<String, String> avatars) {
    if (_loading) return const LoadingView(label: 'Loading members…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final members = _filtered;
    if (members.isEmpty) {
      return EmptyView(
          icon: Icons.people_outline,
          message: _q.isEmpty ? 'No members yet.' : 'No members match "$_q".');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (c, i) => _memberCard(c, members[i], avatars),
      ),
    );
  }

  Widget _memberCard(BuildContext context, TeamMember m, Map<String, String> avatars) {
    final theme = Theme.of(context);
    final quotaLabel = m.quotaGB != null ? '${m.quotaGB} GB' : 'Unlimited';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: AvatarWidget(url: avatars[m.username], name: m.username, radius: 22),
        title: Row(
          children: [
            Expanded(
              child: Text(m.username,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            if (m.disabled)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('DISABLED',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.error)),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  Text('${m.files} files',
                      style: const TextStyle(fontSize: 12)),
                  Text(formatBytes(m.size),
                      style: const TextStyle(fontSize: 12)),
                  Text('quota: $quotaLabel',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('last login ${timeAgo(m.lastLogin)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color)),
                  if (m.pool.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('pool: ${m.pool}',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color)),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'reset':
                _resetPassword(m);
              case 'toggle':
                _toggleDisabled(m);
              case 'quota':
                _setQuota(m);
              case 'delete':
                _deleteMember(m);
            }
          },
          itemBuilder: (c) => [
            const PopupMenuItem(
                value: 'reset', child: Text('Reset password')),
            PopupMenuItem(
                value: 'toggle',
                child: Text(m.disabled ? 'Enable' : 'Disable')),
            const PopupMenuItem(
                value: 'quota', child: Text('Set quota / pool')),
            const PopupMenuItem(
                value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
