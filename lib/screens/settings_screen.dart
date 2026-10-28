import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../cloudinary_api.dart';
import '../distribute.dart';
import '../android_gecko.dart';
import '../gemini_session_manager.dart';
import '../gemini_web.dart';
import '../keep_awake.dart';
import '../secure_store.dart';
import '../widgets/ui_kit.dart';

/// Editable row for one distribution account.
class _DistAccountEdit {
  final nameCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  final secretCtrl = TextEditingController();
  bool obscure = true;

  _DistAccountEdit();

  _DistAccountEdit.from(DistAccount a) {
    nameCtrl.text = a.name;
    urlCtrl.text = a.dbUrl;
    secretCtrl.text = a.secret;
  }

  void dispose() {
    nameCtrl.dispose();
    urlCtrl.dispose();
    secretCtrl.dispose();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cloudCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  // --- Gemini Web (cookie session) ---
  final _gemWebCtrl = TextEditingController();
  bool _gemWebObscure = true;
  bool _gemWebSaving = false;
  bool _gemWebTesting = false;
  bool _gemWebBrowserBusy = false;
  List<String> _gemWebLines = [];
  bool _gemWebOk = false;
  final _distR2Ctrl = TextEditingController();
  final _distQueueCtrl = TextEditingController();
  final List<_DistAccountEdit> _distAccounts = [];
  String _distDefaultTarget = 'spread';
  final Set<String> _distSpreadPool = {};
  bool _distSaving = false;
  bool _distTesting = false;
  String? _distTestResult;
  bool _distTestOk = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGeminiWeb();
    _loadDist();
    _loadBattery();
  }

  bool? _batteryOk;

  Future<void> _loadBattery() async {
    if (!KeepAwake.supported) return;
    final ok = await KeepAwake.batteryUnrestricted();
    if (mounted) setState(() => _batteryOk = ok);
  }

  Future<void> _askBattery() async {
    await KeepAwake.askBatteryUnrestricted();
    // The system dialog returns to the app; re-check a moment later.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _loadBattery();
  }

  /// Android: background running (screen off / sleep).
  Widget _backgroundCard(ColorScheme scheme) {
    final ok = _batteryOk == true;
    return SectionCard(
      icon: Icons.battery_charging_full_outlined,
      title: 'Background',
      subtitle: 'Runs with the screen off',
      trailing: StatusPill(label: ok ? 'Unrestricted' : 'Optimized',
          color: ok ? AppTheme.success : AppTheme.warning,
          icon: ok ? Icons.check_circle : Icons.warning_amber_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HintText(
              'A "Generating" notification keeps jobs alive while the phone '
              'sleeps. Some phones (Xiaomi, Oppo, Vivo, Samsung) also need '
              'battery restrictions turned off for long runs.'),
          if (!ok) ...[
            const SizedBox(height: 14),
            AppButton(
              label: 'Allow background running',
              icon: Icons.battery_full,
              onPressed: _askBattery,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadDist() async {
    try {
      final cfg = await DistributeStore.load();
      if (!mounted) return;
      setState(() {
        _distR2Ctrl.text = cfg.r2WorkerUrl;
        _distQueueCtrl.text = cfg.queuePath;
        _distAccounts
          ..clear()
          ..addAll(cfg.accounts.map((a) => _DistAccountEdit.from(a)));
        _distDefaultTarget = cfg.defaultTarget;
        _distSpreadPool
          ..clear()
          ..addAll(cfg.spreadPool);
      });
    } catch (_) {}
  }

  DistConfig _readDistConfig() {
    final accounts = _distAccounts
        .map((e) => DistAccount(
              name: e.nameCtrl.text.trim(),
              dbUrl: e.urlCtrl.text.trim(),
              secret: e.secretCtrl.text.trim(),
            ))
        .where((a) => a.name.isNotEmpty && a.dbUrl.isNotEmpty)
        .toList();
    var def = _distDefaultTarget;
    if (def != 'spread' && accounts.every((a) => a.name != def)) {
      def = 'spread';
    }
    final pool = _distSpreadPool
        .where((n) => accounts.any((a) => a.name == n))
        .toList();
    return DistConfig(
      r2WorkerUrl: _distR2Ctrl.text.trim(),
      queuePath: _distQueueCtrl.text.trim().isEmpty
          ? 'wallpaperQueue'
          : _distQueueCtrl.text.trim(),
      accounts: accounts,
      defaultTarget: def,
      spreadPool: pool,
    );
  }

  Future<void> _saveDist() async {
    setState(() => _distSaving = true);
    try {
      final cfg = _readDistConfig();
      if (cfg.accounts.isEmpty) {
        throw Exception('Add at least one account.');
      }
      if (cfg.r2WorkerUrl.isEmpty) {
        throw Exception('Enter the R2 worker URL.');
      }
      final names = cfg.accounts.map((a) => a.name).toList();
      if (names.toSet().length != names.length) {
        throw Exception('Account names must be unique.');
      }
      await DistributeStore.save(cfg);
      if (!mounted) return;
      setState(() {
        _distDefaultTarget = cfg.defaultTarget;
        _distSpreadPool
          ..clear()
          ..addAll(cfg.spreadPool);
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Distribution settings saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _distSaving = false);
    }
  }

  Future<void> _testDistAccount(DistAccount a) async {
    setState(() {
      _distTesting = true;
      _distTestResult = null;
    });
    try {
      await testDatabaseConnection(dbUrl: a.dbUrl, secret: a.secret);
      if (!mounted) return;
      setState(() {
        _distTestOk = true;
        _distTestResult =
            '${a.name}: reachable (read-only test, nothing written).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _distTestOk = false;
        _distTestResult = '${a.name}: failed - $e';
      });
    } finally {
      if (mounted) setState(() => _distTesting = false);
    }
  }





  Future<void> _load() async {
    CloudinaryCredentials c;
    try {
      c = await CredentialStore.load();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _cloudCtrl.text = c.cloudName;
      _keyCtrl.text = c.apiKey;
      _secretCtrl.text = c.apiSecret;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CredentialStore.save(CloudinaryCredentials(
        cloudName: _cloudCtrl.text,
        apiKey: _keyCtrl.text,
        apiSecret: _secretCtrl.text,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials saved on this device.')));
  }

  Future<void> _test() async {
    final creds = CloudinaryCredentials(
      cloudName: _cloudCtrl.text,
      apiKey: _keyCtrl.text,
      apiSecret: _secretCtrl.text,
    );
    if (!creds.isComplete) {
      setState(() {
        _testOk = false;
        _testResult = 'Fill in all three fields first.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await CloudinaryApi(creds).testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok
          ? 'Connection OK - Cloudinary accepted your credentials.'
          : 'Connection failed - check cloud name, API key and secret.';
    });
  }

  Future<void> _loadGeminiWeb() async {
    try {
      final web = await GeminiWebStore.load();
      if (!mounted) return;
      setState(() => _gemWebCtrl.text = web);
    } catch (_) {}
  }

  Future<void> _saveGeminiWeb() async {
    final raw = _gemWebCtrl.text.trim();
    setState(() {
      _gemWebSaving = true;
      _gemWebLines = [];
    });
    // Validate + normalize exactly like the workflow does before saving,
    // so a broken export is caught here and never mid-batch.
    if (raw.isNotEmpty) {
      try {
        final session = GeminiWebSession.parse(raw);
        setState(() {
          _gemWebOk = session.authCookies.isNotEmpty;
          _gemWebLines = [
            'Format detected: ${session.format}',
            session.summary,
            if (session.authCookies.isEmpty)
              'No Google auth cookie (SID / __Secure-1PSID ...) found - '
                  're-export while gemini.google.com is open.',
          ];
        });
      } on GeminiWebException catch (e) {
        setState(() {
          _gemWebSaving = false;
          _gemWebOk = false;
          _gemWebLines = [e.message];
        });
        return;
      }
    }
    try {
      await GeminiWebStore.save(raw);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gemWebSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _gemWebSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(raw.isEmpty
            ? 'Gemini web session cleared.'
            : 'Gemini web session saved on this device.')));
  }

  Future<void> _testGeminiWeb() async {
    final raw = _gemWebCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _gemWebOk = false;
        _gemWebLines = ['Paste your Gemini web session JSON first.'];
      });
      return;
    }
    setState(() {
      _gemWebTesting = true;
      _gemWebLines = [];
    });
    GeminiWebSession session;
    try {
      session = GeminiWebSession.parse(raw);
    } on GeminiWebException catch (e) {
      if (!mounted) return;
      setState(() {
        _gemWebTesting = false;
        _gemWebOk = false;
        _gemWebLines = [e.message];
      });
      return;
    }
    final result = await GeminiSessionManager.clientFor(session).test();
    // Renewed / browser-refreshed cookies were saved: show them.
    final stored = await GeminiWebStore.load();
    if (!mounted) return;
    setState(() {
      if (stored.trim().isNotEmpty) _gemWebCtrl.text = stored;
      _gemWebTesting = false;
      _gemWebOk = result.ok;
      _gemWebLines = [
        'Format detected: ${session.format}',
        result.summary,
        result.ok
            ? 'OK (${result.ms}ms) - ${result.message}'
            : 'FAIL - ${result.message}',
      ];
    });
  }

  Future<void> _clearGeminiWeb() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Gemini web session?'),
        content: const Text(
            'The pasted Gemini cookie session will be deleted from this '
            'device. Listing metadata and the AI Set Director will stop '
            'working until you paste a session again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await GeminiWebStore.clear();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _gemWebCtrl.clear();
      _gemWebLines = [];
      _gemWebOk = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini web session removed.')));
  }

  /// Windows: one-time Google sign-in in the app's own browser profile;
  /// afterwards cookies are refreshed from it automatically.
  Future<void> _gemWebFromBrowser({required bool signIn}) async {
    setState(() {
      _gemWebBrowserBusy = true;
      _gemWebLines = [
        signIn
            ? (AndroidGecko.supported
                ? 'Sign in to Google in the built-in browser. It closes by '
                    'itself when Gemini opens (or tap Done).'
                : 'Sign in to Google in the opened browser window. When '
                    'Gemini opens the window closes by itself and the '
                    'cookies are saved (a few seconds).')
            : 'Reading fresh cookies from the signed-in browser profile...',
      ];
      _gemWebOk = true;
    });
    GeminiWebSession? s;
    String? err;
    try {
      s = signIn
          ? await GeminiSessionManager.signInWithBrowser()
          : await GeminiSessionManager.refreshFromBrowser();
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    setState(() {
      _gemWebBrowserBusy = false;
      if (s != null) {
        _gemWebCtrl.text = s.toStorageJson();
        _gemWebOk = true;
        _gemWebLines = [
          'Cookies taken from the browser and saved.',
          s.summary,
          'They renew automatically. When Google ends the session the app '
              'refreshes them from this browser again - no new login.',
        ];
      } else {
        _gemWebOk = false;
        _gemWebLines = [
          err ??
              'The browser profile is not signed in to Google yet. Use '
                  '"Sign in with Google" first.',
        ];
      }
    });
  }

  Future<void> _copyGeminiWeb() async {
    final raw = _gemWebCtrl.text.trim().isNotEmpty
        ? _gemWebCtrl.text.trim()
        : await GeminiWebStore.load();
    if (!mounted) return;
    if (raw.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Gemini session saved yet.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Session JSON copied - paste it on the other device '
            '(Settings > Gemini web session > Save).')));
  }

  /// Gemini Web (cookie) card - the desktop twin of the workflow's
  /// GEMINI_SESSION input.
  Widget _geminiWebCard(ColorScheme scheme) {
    final hasBrowser = GeminiSessionManager.browserRefreshSupported;
    return SectionCard(
      icon: Icons.cookie_outlined,
      title: 'Gemini web session',
      subtitle: 'Metadata + AI Set Director, no API key',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBrowser) ...[
            HintText(AndroidGecko.supported
                ? 'Sign in once in the built-in browser. Cookies are filled '
                    'in and renewed automatically - no login again.'
                : 'Sign in once in the Chrome / Edge window that opens. '
                    'Cookies are filled in and renewed automatically.'),
            const SizedBox(height: 14),
            ButtonGroup(children: [
              AppButton(
                label: 'Sign in',
                icon: Icons.login,
                loading: _gemWebBrowserBusy,
                onPressed: () => _gemWebFromBrowser(signIn: true),
              ),
              AppButton(
                label: 'Refresh',
                icon: Icons.sync,
                kind: AppButtonKind.tonal,
                onPressed: _gemWebBrowserBusy
                    ? null
                    : () => _gemWebFromBrowser(signIn: false),
              ),
            ]),
            const SizedBox(height: 16),
          ] else ...[
            const HintText(
                'Paste a gemini.google.com cookie export (Playwright '
                'storageState or cookie-editor JSON). Each prompt starts a '
                'fresh chat.'),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _gemWebCtrl,
            obscureText: _gemWebObscure,
            maxLines: _gemWebObscure ? 1 : 5,
            minLines: 1,
            decoration: InputDecoration(
              labelText: 'Session JSON (cookies)',
              hintText: '{"cookies":[{"name":"__Secure-1PSID",...}]}',
              prefixIcon: const Icon(Icons.vpn_lock_outlined),
              suffixIcon: IconButton(
                tooltip: _gemWebObscure ? 'Show' : 'Hide',
                icon: Icon(_gemWebObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () =>
                    setState(() => _gemWebObscure = !_gemWebObscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ButtonGroup(children: [
            AppButton(
              label: 'Save',
              icon: Icons.save_outlined,
              kind: hasBrowser ? AppButtonKind.tonal : AppButtonKind.primary,
              loading: _gemWebSaving,
              onPressed: _saveGeminiWeb,
            ),
            AppButton(
              label: 'Test',
              icon: Icons.wifi_tethering_outlined,
              kind: AppButtonKind.outline,
              loading: _gemWebTesting,
              onPressed: _testGeminiWeb,
            ),
          ]),
          if (_gemWebLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_gemWebOk ? AppTheme.success : scheme.error)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: (_gemWebOk ? AppTheme.success : scheme.error)
                        .withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in _gemWebLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(line,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _copyGeminiWeb,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy JSON'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearGeminiWeb,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clear() async {    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove credentials?'),
        content: const Text(
            'Your Cloudinary cloud name, API key and secret will be deleted from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await CredentialStore.clear();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cloudCtrl.clear();
      _keyCtrl.clear();
      _secretCtrl.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Credentials removed.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/icon/app_icon.png',
                  width: 30, height: 30),
            ),
            const SizedBox(width: 10),
            const Text('Settings'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: screenScrollPadding(context, 16, 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              icon: Icons.key_outlined,
              title: 'Cloudinary',
              subtitle: 'Image generation credentials',
              trailing: _testResult == null
                  ? null
                  : StatusPill(
                      label: _testOk ? 'Connected' : 'Failed',
                      color: _testOk ? AppTheme.success : scheme.error,
                      icon: _testOk ? Icons.check_circle : Icons.error),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _cloudCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Cloud name',
                      hintText: 'e.g. my-cloud',
                      prefixIcon: Icon(Icons.cloud_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secretCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'API secret',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show' : 'Hide',
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ButtonGroup(children: [
                    AppButton(
                      label: 'Save',
                      icon: Icons.save_outlined,
                      loading: _saving,
                      onPressed: _save,
                    ),
                    AppButton(
                      label: 'Test',
                      icon: Icons.wifi_tethering_outlined,
                      kind: AppButtonKind.outline,
                      loading: _testing,
                      onPressed: _test,
                    ),
                  ]),
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    HintText(_testResult!,
                        icon: _testOk
                            ? Icons.check_circle_outline
                            : Icons.error_outline),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _distributionCard(scheme),
            const SizedBox(height: 12),
            _geminiWebCard(scheme),
            const SizedBox(height: 12),
            if (KeepAwake.supported) ...[
              _backgroundCard(scheme),
              const SizedBox(height: 12),
            ],
            const Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: IconBadge(icon: Icons.help_outline),
                title: Text('Where to find Cloudinary keys'),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepList([
                    'Cloudinary Console -> Settings -> Account: copy the Cloud name.',
                    'API Keys section: copy the API Key, then reveal and copy the API Secret.',
                    'The Image Generation add-on must be enabled on the account.',
                  ]),
                  SizedBox(height: 10),
                  HintText(
                      'Stored only in this device\'s secure storage and sent only to api.cloudinary.com.',
                      icon: Icons.lock_outline),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/icon/app_icon.png',
                      width: 40, height: 40),
                ),
                title: const Text('AI Image Studio'),
                subtitle: const Text('Version 1.10.0 - Cloudinary image generation'),
              ),
            ),
          ],
        ),
      ),
    );
  }



  /// Distribution: the user's own accounts + database targets,
  /// mirroring the Generator Hub workflow (one Firebase DB per
  /// account, R2 folder derived from the account name, spread or a
  /// fixed target per upload).
  Widget _distributionCard(ColorScheme scheme) {
    InputDecoration deco(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
        );
    final accountNames =
        _distAccounts.map((e) => e.nameCtrl.text.trim()).toList();
    return SectionCard(
      icon: Icons.cloud_upload_outlined,
      title: 'Distribution',
      subtitle: '${_distAccounts.length} account${_distAccounts.length == 1 ? '' : 's'} - R2 + Firebase queue',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HintText(
                'Finished sets upload files to your R2 worker and push a '
                'record to one account\'s Firebase queue.'),
            const SizedBox(height: 12),
            TextField(
              controller: _distR2Ctrl,
              decoration: deco('R2 worker URL',
                  'https://your-worker.workers.dev'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _distQueueCtrl,
              decoration: deco('Queue path', 'wallpaperQueue'),
            ),
            const SizedBox(height: 16),
            Text('Accounts (${_distAccounts.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (var i = 0; i < _distAccounts.length; i++) ...[
              _accountRow(i, deco),
              const SizedBox(height: 8),
            ],
            AppButton(
              label: 'Add account',
              icon: Icons.add,
              kind: AppButtonKind.outline,
              onPressed: () =>
                  setState(() => _distAccounts.add(_DistAccountEdit())),
            ),
            const SizedBox(height: 16),
            Text('Default target',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _distDefaultTarget,
              decoration: deco('Where new uploads go'),
              items: [
                const DropdownMenuItem(
                    value: 'spread',
                    child: Text('Spread (auto: rotate accounts)')),
                for (final n in accountNames)
                  if (n.isNotEmpty)
                    DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) =>
                  setState(() => _distDefaultTarget = v ?? 'spread'),
            ),
            const SizedBox(height: 12),
            Text('Spread across',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final n in accountNames)
                  if (n.isNotEmpty)
                    FilterChip(
                      label: Text(n),
                      selected: _distSpreadPool.contains(n),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _distSpreadPool.add(n);
                        } else {
                          _distSpreadPool.remove(n);
                        }
                      }),
                    ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Empty selection means all accounts.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Save distribution',
              icon: Icons.save_outlined,
              loading: _distSaving,
              onPressed: _saveDist,
            ),
            if (_distTestResult != null) ...[
              const SizedBox(height: 10),
              HintText(_distTestResult!,
                  icon: _distTestOk
                      ? Icons.check_circle_outline
                      : Icons.error_outline),
            ],
          ],
        ),
    );
  }

  Widget _accountRow(int i, InputDecoration Function(String, [String?]) deco) {
    final e = _distAccounts[i];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: e.nameCtrl,
                  decoration: deco('Name', 'zedge_1'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                tooltip: 'Test this database',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.wifi_find_outlined, size: 20),
                onPressed: _distTesting
                    ? null
                    : () => _testDistAccount(DistAccount(
                          name: e.nameCtrl.text.trim(),
                          dbUrl: e.urlCtrl.text.trim(),
                          secret: e.secretCtrl.text.trim(),
                        )),
              ),
              IconButton(
                tooltip: 'Remove account',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline,
                    size: 20, color: scheme.error),
                onPressed: () => setState(() {
                  _distAccounts.removeAt(i).dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: e.urlCtrl,
            decoration: deco('Database URL',
                'https://your-db.firebasedatabase.app'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: e.secretCtrl,
            obscureText: e.obscure,
            decoration: deco('Secret (optional)').copyWith(
              suffixIcon: IconButton(
                tooltip: e.obscure ? 'Show' : 'Hide',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                    e.obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20),
                onPressed: () =>
                    setState(() => e.obscure = !e.obscure),
              ),
            ),
          ),
        ],
      ),
    );
  }



  @override
  void dispose() {
    _cloudCtrl.dispose();
    _keyCtrl.dispose();
    _secretCtrl.dispose();
    _gemWebCtrl.dispose();
    _distR2Ctrl.dispose();
    _distQueueCtrl.dispose();
    for (final a in _distAccounts) {
      a.dispose();
    }
    super.dispose();
  }
}
