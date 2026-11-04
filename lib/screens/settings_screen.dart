import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../providers/app_state.dart';
import '../utils/images.dart';
import '../widgets/app_widgets.dart';

/// Profile + app settings for all users. Opened from the profile menu.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  String? _workerVersion;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = context.read<SessionProvider>().api.baseUrl;
    _loadWorkerVersion();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  SessionProvider get _session => context.read<SessionProvider>();
  ApiClient get _api => _session.api;

  Future<void> _loadWorkerVersion() async {
    final v = await guard(context, () => _api.getWorkerVersion());
    if (!mounted) return;
    setState(() => _workerVersion = v);
  }

  // ---------------- account ----------------

  Future<void> _changeAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      showMsg(context, 'Could not read the selected image.', error: true);
      return;
    }
    // Mirror the web app: shrink/crop client-side to a 256×256 square.
    late final String uploadPath;
    try {
      uploadPath = (await shrinkForAvatar(path)).path;
    } catch (e) {
      if (!mounted) return;
      showMsg(context, 'Could not process that image.', error: true);
      return;
    }
    if (!mounted) return;
    final ok = await ProgressDialog.show(context,
        title: 'Uploading avatar…',
        task: (_) => _api.uploadAvatar(localPath: uploadPath));
    if (!mounted || !ok) return;
    await guard(context, () => _session.refreshDrive());
    if (!mounted) return;
    setState(() {}); // refresh avatar widget from session.drive
    showMsg(context, 'Avatar updated.');
  }

  Future<void> _removeAvatar() async {
    final ok = await confirmDialog(context,
        title: 'Remove avatar',
        message: 'Remove your profile picture?',
        okLabel: 'Remove');
    if (!ok || !mounted) return;
    final ok2 = await guard(context, () async {
      await _api.deleteAvatar();
      return true;
    });
    if (!mounted || ok2 != true) return;
    await guard(context, () => _session.refreshDrive());
    if (!mounted) return;
    setState(() {});
    showMsg(context, 'Avatar removed.');
  }

  Future<void> _changePassword() async {
    final current = await promptDialog(context,
        title: 'Change password',
        hint: 'Current password',
        obscure: true,
        okLabel: 'Next');
    if (current == null || current.isEmpty || !mounted) return;
    final next = await promptDialog(context,
        title: 'Change password',
        hint: 'New password (min 6 chars)',
        obscure: true,
        okLabel: 'Change');
    if (next == null || !mounted) return;
    if (next.length < 6) {
      showMsg(context, 'New password must be at least 6 characters.',
          error: true);
      return;
    }
    // The worker answers 400 for admins ("admin must change it in worker
    // code") — guard() surfaces the worker's own message.
    final ok2 = await guard(context, () async {
      await _api.changePassword(current: current, next: next);
      return true;
    });
    if (!mounted || ok2 != true) return;
    showMsg(context, 'Password changed.');
  }

  // ---------------- app ----------------

  Future<void> _saveWorkerUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      showMsg(context, 'Enter a worker URL.', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Change worker URL',
        message:
            'Your session token is signed by this worker, so it will stop working. You will be logged out and need to log in again with the new URL. Continue?',
        okLabel: 'Change & log out');
    if (!ok || !mounted) return;
    await _session.setWorkerUrl(url);
    if (!mounted) return;
    showMsg(context, 'Worker URL saved. Please log in again.');
    await _session.logout();
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(context,
        title: 'Log out',
        message: 'Log out of Team Drive on this device?',
        okLabel: 'Log out');
    if (!ok || !mounted) return;
    await _session.logout();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final user = session.user;
    final avatarUrl =
        user != null ? (session.drive?.avatars[user.username]) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _section('Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AvatarWidget(
                      url: avatarUrl,
                      name: user?.username ?? '?',
                      radius: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.username ?? '—',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 17)),
                        const SizedBox(height: 2),
                        Text(user?.role ?? '—',
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color)),
                      ],
                    ),
                  ),
                  TextButton(
                      onPressed: _changeAvatar, child: const Text('Change')),
                  if (avatarUrl != null && avatarUrl.isNotEmpty)
                    TextButton(
                        onPressed: _removeAvatar,
                        child: const Text('Remove')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Change password'),
              subtitle: const Text('Members only — admins get a worker message'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePassword,
            ),
          ),
          const SizedBox(height: 20),
          _section('App'),
          Card(
            child: Consumer<ThemeProvider>(
              builder: (c, theme, _) => SwitchListTile(
                title: const Text('Night mode'),
                secondary: const Icon(Icons.dark_mode_outlined),
                value: theme.night,
                onChanged: (v) => theme.setNight(v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Worker URL',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        hintText: 'https://your-worker.workers.dev'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      'Takes effect on next login — your token is signed by the current worker.',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _saveWorkerUrl,
                      child: const Text('Save & log out')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _section('About'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('App version'),
                  trailing: Text('1.0.0'),
                  dense: true,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Worker version'),
                  trailing: Text(_workerVersion ?? '…'),
                  dense: true,
                  onTap: _loadWorkerVersion,
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.flutter_dash),
                  title: Text('Flutter native'),
                  subtitle: Text('No WebView'),
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );
}
