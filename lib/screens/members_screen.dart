import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/images.dart';
import '../widgets/app_widgets.dart';

/// Admin-only member management, mirroring the web app's Members view:
/// heading + count, default-limit info bar, inline add-member card,
/// MEMBER table with avatar/camera badge, relative last-login, and
/// icon action buttons (folder / limit / reset / disable / delete).
class MembersScreen extends StatefulWidget {
  static VoidCallback? requestNew;
  const MembersScreen({super.key});
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  static final _userRe = RegExp(r'^[a-z0-9_.-]{3,32}$');
  static _MembersScreenState? _state;

  List<TeamMember>? _members;
  Map<String, dynamic>? _settings;
  bool _loading = true;
  String? _error;

  final _scrollCtrl = ScrollController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _state = this;
    // Home's "+ New" focuses the add-member form.
    MembersScreen.requestNew = () => _state?._focusAddForm();
    _load();
  }

  @override
  void dispose() {
    if (_state == this) _state = null;
    MembersScreen.requestNew = null;
    _scrollCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  ApiClient get _api => context.read<SessionProvider>().api;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final members = await guard(context, () => _api.getMembers());
    final settings = await guard(context, () => _api.getSettings());
    if (!mounted) return;
    setState(() {
      _members = members;
      _settings = settings;
      _loading = false;
      if (members == null) _error = 'Could not load members.';
    });
  }

  void _focusAddForm() {
    if (!mounted) return;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _userFocus.requestFocus();
  }

  double get _defaultGB {
    final v = _settings?['defaultQuotaGB'];
    return v is num ? v.toDouble() : 0.5;
  }

  // ---------------- actions ----------------

  Future<void> _addMember() async {
    final username = _userCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;
    if (!_userRe.hasMatch(username)) {
      showMsg(context, 'Username must be 3–32 chars: lowercase a-z, 0-9, _ . -',
          error: true);
      return;
    }
    if (password.length < 6) {
      showMsg(context, 'Password must be at least 6 characters.', error: true);
      return;
    }
    setState(() => _adding = true);
    final ok = await guard(context, () async {
      await _api.createOrResetMember(username: username, password: password);
      return true;
    });
    if (!mounted) return;
    setState(() => _adding = false);
    if (ok != true) return;
    _userCtrl.clear();
    _passCtrl.clear();
    showMsg(context, 'Member added — private folder created.');
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
    final ok = await guard(context, () async {
      await _api.createOrResetMember(
          username: m.username, password: next, reset: true);
      return true;
    });
    if (!mounted || ok != true) return;
    showMsg(
        context, 'Password for "${m.username}" was reset. Their session is now invalid.');
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
    showMsg(context,
        disable ? '"${m.username}" disabled.' : '"${m.username}" enabled.');
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
                    labelText: 'Pool', hintText: 'auto, or a pool id'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save')),
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

  Future<void> _setMemberAvatar(TeamMember m) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) {
      if (mounted) {
        showMsg(context, 'Could not read the selected image.', error: true);
      }
      return;
    }
    late final String uploadPath;
    try {
      uploadPath = (await shrinkForAvatar(path)).path;
    } catch (_) {
      if (!mounted) return;
      showMsg(context, 'Could not process that image.', error: true);
      return;
    }
    if (!mounted) return;
    final ok = await ProgressDialog.show(context,
        title: 'Uploading avatar…',
        task: (_) => _api.uploadAvatar(localPath: uploadPath, user: m.username));
    if (!mounted || !ok) return;
    await guard(context, () => context.read<SessionProvider>().refreshDrive());
    if (!mounted) return;
    setState(() {});
    showMsg(context, 'Avatar updated for "${m.username}".');
  }

  void _openMemberFolder(TeamMember m) {
    final drive = context.read<SessionProvider>().drive;
    if (drive == null) {
      showMsg(context, 'Drive data not loaded yet.', error: true);
      return;
    }
    final files = drive.files.values
        .where((f) => f.folder == m.folder)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final night = context.read<ThemeProvider>().night;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text("${m.username}'s private folder",
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${files.length} files',
                    style: TextStyle(
                        fontSize: 12,
                        color: night
                            ? AppColors.nightMuted
                            : AppColors.dayMuted)),
              ]),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: files.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                            child: Text('No files yet.',
                                style: TextStyle(
                                    color: night
                                        ? AppColors.nightMuted
                                        : AppColors.dayMuted))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, i) {
                          final f = files[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.insert_drive_file_outlined,
                                size: 20),
                            title: Text(f.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                            trailing: Text(formatBytes(f.size),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: night
                                        ? AppColors.nightMuted
                                        : AppColors.dayMuted)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Default-limit picker mirroring the web's limitPicker (Custom /
  /// Unlimited / Upload off), saved to settings.defaultQuotaGB.
  Future<void> _changeDefaultLimit() async {
    final cur = _defaultGB;
    String mode = cur == -1 ? 'unl' : cur == 0 ? 'off' : 'custom';
    final numCtrl = TextEditingController(
        text: cur > 0
            ? (cur < 1 ? (cur * 1024).round().toString() : _trimNum(cur))
            : '500');
    String unit = (cur > 0 && cur < 1) ? 'MB' : 'GB';
    final night = context.read<ThemeProvider>().night;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('Default storage limit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('all members (jader custom limit nai)',
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          night ? AppColors.nightMuted : AppColors.dayMuted)),
              const SizedBox(height: 12),
              _limitOpt(
                  night: night,
                  selected: mode == 'custom',
                  icon: Icons.hard_drive_outlined,
                  title: 'Custom',
                  sub: 'Nijer moto MB / GB set korun',
                  onTap: () => setDlg(() => mode = 'custom'),
                  extra: mode == 'custom'
                      ? Row(children: [
                          Expanded(
                            child: TextField(
                              controller: numCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Amount'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: unit,
                            items: const [
                              DropdownMenuItem(
                                  value: 'MB', child: Text('MB')),
                              DropdownMenuItem(
                                  value: 'GB', child: Text('GB')),
                            ],
                            onChanged: (v) =>
                                setDlg(() => unit = v ?? 'MB'),
                          ),
                        ])
                      : null),
              _limitOpt(
                  night: night,
                  selected: mode == 'unl',
                  icon: Icons.all_inclusive,
                  title: 'Unlimited',
                  sub: 'Kono limit nai (R2 er total jayga porjonto)',
                  onTap: () => setDlg(() => mode = 'unl')),
              _limitOpt(
                  night: night,
                  selected: mode == 'off',
                  icon: Icons.block_outlined,
                  title: 'Upload off',
                  sub: 'Shudhu dekhte/download korte parbe',
                  onTap: () => setDlg(() => mode = 'off')),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final numText = numCtrl.text.trim();
    numCtrl.dispose();
    if (ok != true || !mounted) return;
    double q;
    if (mode == 'unl') {
      q = -1;
    } else if (mode == 'off') {
      q = 0;
    } else {
      final n = double.tryParse(numText);
      if (n == null || n <= 0) {
        showMsg(context, 'Enter a valid amount.', error: true);
        return;
      }
      q = unit == 'MB' ? n / 1024 : n;
    }
    final saved = await guard(context, () async {
      await _api.updateSettings({'defaultQuotaGB': q});
      return true;
    });
    if (!mounted || saved != true) return;
    showMsg(context, 'Default limit: ${_qLabel(q)}');
    _load();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final night = context.watch<ThemeProvider>().night;
    if (!session.isAdmin) {
      return const Scaffold(
        body: EmptyView(
            icon: Icons.lock_outline,
            message: 'Members is for admins only.'),
      );
    }
    final avatars = session.drive?.avatars ?? {};
    return Scaffold(
      body: _buildBody(avatars, night),
    );
  }

  Widget _buildBody(Map<String, String> avatars, bool night) {
    if (_loading) return const LoadingView(label: 'Loading members…');
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final members = (_members ?? []).toList()
      ..sort((a, b) => a.username.compareTo(b.username));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _headerRow(members.length, night),
          const SizedBox(height: 14),
          _infoBar(night),
          const SizedBox(height: 14),
          _addCard(night),
          _tableHeader(night),
          if (members.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: _cardDeco(night),
              child: Center(
                  child: Text('No members yet.',
                      style: TextStyle(
                          color: night
                              ? AppColors.nightMuted
                              : AppColors.dayMuted))),
            )
          else
            _rowsCard(members, avatars, night),
        ],
      ),
    );
  }

  Widget _headerRow(int count, bool night) => Row(
        children: [
          const Text('Members',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('$count members',
              style: TextStyle(
                  fontSize: 13,
                  color: night ? AppColors.nightMuted : AppColors.dayMuted)),
        ],
      );

  /// Pale blue-gray info bar (web .setbar): database tile, bold default
  /// limit, gray helper, white "Change" pill at right.
  Widget _infoBar(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: night ? const Color(0xFF232323) : const Color(0xFFFAFBFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: night
                  ? AppColors.nightBrandTint
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.storage_outlined, size: 17, color: brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Default storage limit per member: ${_qLabel(_defaultGB)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'Members nijer private folder e upload korte parbe ei limit porjonto. Kauke alada limit dite "Limit" button chapun.',
                    style: TextStyle(
                        fontSize: 12,
                        color: night
                            ? AppColors.nightMuted
                            : AppColors.dayMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _whitePill(
              label: 'Change',
              icon: Icons.edit_outlined,
              onTap: _changeDefaultLimit),
        ],
      ),
    );
  }

  /// Inline add-member card: stacked inputs + full-width solid blue button.
  Widget _addCard(bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(night),
      child: Column(
        children: [
          TextField(
            controller: _userCtrl,
            focusNode: _userFocus,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline),
              hintText: 'Username (a-z, 0-9, . _ -)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addMember(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.key_outlined),
              hintText: 'Password (min 6)',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _adding ? null : _addMember,
              style: ElevatedButton.styleFrom(
                backgroundColor: brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: brand.withOpacity(0.55),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('Add member',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(bool night) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8, left: 4),
        child: Text('MEMBER',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: night ? AppColors.nightMuted : AppColors.dayMuted)),
      );

  Widget _rowsCard(
      List<TeamMember> members, Map<String, String> avatars, bool night) {
    return Container(
      decoration: _cardDeco(night),
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  color: night
                      ? AppColors.nightLine2
                      : AppColors.dayLine),
            _memberRow(members[i], avatars, night),
          ],
        ],
      ),
    );
  }

  Widget _memberRow(TeamMember m, Map<String, String> avatars, bool night) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    final danger = night ? AppColors.dangerDark : AppColors.dangerLight;
    final buttons = <Widget>[
      _iconBtn(
          icon: Icons.folder_outlined,
          tip: 'Open private folder',
          night: night,
          bg: brand,
          fg: Colors.white,
          onTap: () => _openMemberFolder(m)),
      _iconBtn(
          icon: Icons.pie_chart_outline,
          tip: 'Storage limit',
          night: night,
          onTap: () => _setQuota(m)),
      _iconBtn(
          icon: Icons.key_outlined,
          tip: 'Reset password',
          night: night,
          onTap: () => _resetPassword(m)),
      _iconBtn(
          icon: Icons.person_off_outlined,
          tip: m.disabled ? 'Enable' : 'Disable',
          night: night,
          onTap: () => _toggleDisabled(m)),
      _iconBtn(
          icon: Icons.delete_outline,
          tip: 'Remove',
          night: night,
          fg: danger,
          onTap: () => _deleteMember(m)),
    ];
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(m.username,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            ),
            if (m.disabled) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Disabled',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: danger)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text(
              '${m.files} files · ${m.lastLogin > 0 ? 'Last login ${formatRelative(m.lastLogin)}' : 'Never logged in'}',
              style: TextStyle(
                  fontSize: 12,
                  color: night ? AppColors.nightMuted : AppColors.dayMuted)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: LayoutBuilder(builder: (c, cons) {
        final leading = Row(children: [
          _avatarWithCam(m, avatars, night),
          const SizedBox(width: 12),
          info,
        ]);
        final btnRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: _spaced(buttons, const SizedBox(width: 6)));
        if (cons.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(height: 10),
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [btnRow]),
            ],
          );
        }
        return Row(children: [
          Expanded(child: leading),
          const SizedBox(width: 8),
          btnRow,
        ]);
      }),
    );
  }

  Widget _avatarWithCam(
      TeamMember m, Map<String, String> avatars, bool night) {
    return GestureDetector(
      onTap: () => _setMemberAvatar(m),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarWidget(
                url: avatars[m.username], name: m.username, radius: 19),
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: night ? AppColors.brandDark : AppColors.brandLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color:
                          night ? AppColors.nightPanel : Colors.white,
                      width: 2),
                ),
                child: const Icon(Icons.camera_alt,
                    size: 9, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
      {required IconData icon,
      required String tip,
      required VoidCallback onTap,
      required bool night,
      Color? bg,
      Color? fg}) {
    final b = bg ??
        (night ? AppColors.nightSide2 : const Color(0xFFF1F5F9));
    final f = fg ?? (night ? AppColors.nightMuted : const Color(0xFF6B7280));
    return Tooltip(
      message: tip,
      child: Material(
        color: b,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 17, color: f)),
        ),
      ),
    );
  }

  Widget _whitePill(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFF555555)),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitOpt(
      {required bool night,
      required bool selected,
      required IconData icon,
      required String title,
      required String sub,
      required VoidCallback onTap,
      Widget? extra}) {
    final brand = night ? AppColors.brandDark : AppColors.brandLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected
                  ? brand
                  : (night ? AppColors.nightLine : AppColors.dayLine)),
          color: selected
              ? brand.withOpacity(0.08)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12,
                          color: night
                              ? AppColors.nightMuted
                              : AppColors.dayMuted)),
                  if (selected && extra != null) ...[
                    const SizedBox(height: 8),
                    extra,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- helpers ----------------

  BoxDecoration _cardDeco(bool night) => BoxDecoration(
        color: night ? AppColors.nightPanel : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: night ? AppColors.nightLine : AppColors.dayLine),
      );

  String _trimNum(double v) {
    var s = v.toStringAsFixed(2);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  String _qLabel(double g) {
    if (g == -1) return 'Unlimited';
    if (g == 0) return 'Upload off';
    if (g < 1) return '${(g * 1024).round()} MB';
    return '${_trimNum(g)} GB';
  }

  List<Widget> _spaced(List<Widget> ws, Widget sep) {
    final out = <Widget>[];
    for (var i = 0; i < ws.length; i++) {
      if (i > 0) out.add(sep);
      out.add(ws[i]);
    }
    return out;
  }
}
