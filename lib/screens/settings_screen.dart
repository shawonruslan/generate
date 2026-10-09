import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cloudinary_api.dart';
import '../distribute.dart';
import '../gemini_web.dart';
import '../secure_store.dart';

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
    final result = await GeminiWebClient(session).test();
    if (!mounted) return;
    setState(() {
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

  /// Gemini Web (cookie) card - the desktop twin of the workflow's
  /// GEMINI_SESSION input.
  Widget _geminiWebCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme, Icons.cookie_outlined,
                'Gemini web session (cookies)'),
            const SizedBox(height: 8),
            Text(
              'Same path as the Generator Hub workflow: paste your '
              'gemini.google.com cookie export and all AI work (listing '
              'metadata + the AI Set Director) runs through the Gemini web '
              'session - no API key, no model pool, no rate limits. '
              'Accepts a Playwright storageState JSON or a cookie-editor '
              'export array. Every prompt starts a fresh chat, and an '
              'expired session is reported instead of silently skipped.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gemWebCtrl,
              obscureText: _gemWebObscure,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                labelText: 'Gemini session JSON (cookies)',
                hintText: '{"cookies":[{"name":"__Secure-1PSID",...}]}',
                prefixIcon: const Icon(Icons.vpn_lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_gemWebObscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _gemWebObscure = !_gemWebObscure),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _gemWebSaving ? null : _saveGeminiWeb,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_gemWebSaving ? 'Saving...' : 'Save session'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _gemWebTesting ? null : _testGeminiWeb,
                    icon: const Icon(Icons.wifi_tethering_outlined),
                    label:
                        Text(_gemWebTesting ? 'Testing...' : 'Test session'),
                  ),
                ),
              ],
            ),
            if (_gemWebLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_gemWebOk ? Colors.green : scheme.error)
                      .withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in _gemWebLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(line,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearGeminiWeb,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove Gemini web session'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
            ),
          ],
        ),
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
        padding: screenScrollPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(scheme, Icons.key_outlined,
                        'Cloudinary credentials'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cloudCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cloud name',
                        hintText: 'e.g. my-cloud',
                        prefixIcon: Icon(Icons.cloud_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyCtrl,
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
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving...' : 'Save'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _testing ? null : _test,
                            icon: const Icon(Icons.wifi_tethering_outlined),
                            label:
                                Text(_testing ? 'Testing...' : 'Test connection'),
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                              _testOk
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: _testOk ? Colors.green : scheme.error,
                              size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_testResult!)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(
                          'Remove credentials from this device'),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _distributionCard(scheme),
            const SizedBox(height: 12),
            _geminiWebCard(scheme),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(scheme, Icons.help_outline, 'Where to find these'),
                    const SizedBox(height: 8),
                    const _Bullet(
                        'Cloudinary Console -> Settings (gear icon) -> Account: copy the Cloud name.'),
                    const _Bullet(
                        'Same page, API Keys section: copy the API Key, then reveal and copy the API Secret.'),
                    const _Bullet(
                        'The Image Generation add-on must be enabled on your Cloudinary account, otherwise requests return an error.'),
                    const SizedBox(height: 8),
                    Text(
                      'Credentials are stored only in this device\'s secure storage and are sent solely to api.cloudinary.com when you generate.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(scheme, Icons.info_outline, 'About'),
                    const SizedBox(height: 8),
                    const Text('AI Image Studio 1.0.0'),
                    const Text(
                        'Text-to-image and image-to-image generation powered by the Cloudinary Image Generation API.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
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
          border: const OutlineInputBorder(),
          isDense: true,
        );
    final accountNames =
        _distAccounts.map((e) => e.nameCtrl.text.trim()).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
                scheme, Icons.cloud_upload_outlined, 'Distribution'),
            const SizedBox(height: 8),
            Text(
              'Your own accounts, like the Generator Hub workflow: finished sets upload their files to your R2 (via your worker) and push a record with files + metadata to the account\'s Firebase queue. Add as many accounts as you have - each set goes to exactly one account.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
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
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _distAccounts.add(_DistAccountEdit())),
              icon: const Icon(Icons.add_outlined),
              label: const Text('Add account'),
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
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _distSaving ? null : _saveDist,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_distSaving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
            if (_distTestResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _distTestResult!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _distTestOk ? scheme.primary : scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _accountRow(int i, InputDecoration Function(String, [String?]) deco) {
    final e = _distAccounts[i];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
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

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('-  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
