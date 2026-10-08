import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cloudinary_api.dart';
import '../distribute.dart';
import '../gemini_api.dart';
import '../gemini_web.dart';
import '../secure_store.dart';
import 'gemini_web_connect.dart';

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
  final _gemKeysCtrl = TextEditingController();
  final _gemModelsCtrl = TextEditingController();
  bool _obscure = true;
  bool _gemObscure = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _gemSaving = false;
  bool _gemTesting = false;
  List<String> _gemTestLines = [];
  bool _gemTestOk = false;
  String _metaProvider = 'api';
  bool _webConnected = false;
  bool _webBusy = false;
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
    _loadGemini();
    _loadWeb();
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

  Future<void> _loadWeb() async {
    try {
      final p = await GeminiWebPrefs.provider();
      final c = await GeminiWebPrefs.connected();
      if (!mounted) return;
      setState(() {
        _metaProvider = p;
        _webConnected = c;
      });
    } catch (_) {}
  }

  Future<void> _setProvider(String v) async {
    setState(() => _metaProvider = v);
    await GeminiWebPrefs.setProvider(v);
  }

  Future<void> _connectWeb() async {
    if (!GeminiWeb.isSupported) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const GeminiWebConnectPage()),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() => _webConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gemini Web connected.')));
    } else {
      final c = await GeminiWebPrefs.connected();
      if (mounted) setState(() => _webConnected = c);
    }
  }

  Future<void> _disconnectWeb() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect Gemini Web?'),
        content: const Text(
            'Your Google session will be removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _webBusy = true);
    try {
      // The Google session lives entirely in the WebView2 profile
      // folder - wiping it is a complete disconnect.
      await GeminiWebEnv.wipeProfile();
      await GeminiWebPrefs.setConnected(false);
    } finally {
      if (mounted) setState(() => _webBusy = false);
    }
    if (!mounted) return;
    setState(() => _webConnected = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini Web disconnected.')));
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

  /// Parse one-per-line keys / model ids, like the web studio.
  static List<String> _parseLines(String raw, {required bool model}) {
    final out = <String>[];
    final re = model
        ? RegExp(r'^[A-Za-z0-9._-]{3,80}$')
        : RegExp(r'^[A-Za-z0-9._-]{20,200}$');
    for (final line in raw.split('\n')) {
      var v = line.trim();
      if (model && v.toLowerCase().startsWith('models/')) {
        v = v.substring(7);
      }
      if (v.isNotEmpty && re.hasMatch(v) && !out.contains(v)) {
        out.add(v);
      }
    }
    return out;
  }

  Future<void> _loadGemini() async {
    try {
      final pool = await GeminiStore.load();
      if (!mounted) return;
      setState(() {
        _gemKeysCtrl.text = pool.keys.join('\n');
        _gemModelsCtrl.text = pool.models.join('\n');
      });
    } catch (_) {}
  }

  Future<void> _saveGemini() async {
    setState(() => _gemSaving = true);
    try {
      await GeminiStore.save(
        _parseLines(_gemKeysCtrl.text, model: false),
        _parseLines(_gemModelsCtrl.text, model: true),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _gemSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _gemSaving = false);
    // Refresh the fields with the cleaned values.
    _loadGemini();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini pool saved on this device.')));
  }

  Future<void> _testGemini() async {
    final keys = _parseLines(_gemKeysCtrl.text, model: false);
    final models = _parseLines(_gemModelsCtrl.text, model: true);
    if (keys.isEmpty) {
      setState(() {
        _gemTestOk = false;
        _gemTestLines = ['Add at least one Gemini API key first.'];
      });
      return;
    }
    setState(() {
      _gemTesting = true;
      _gemTestLines = [];
    });
    try {
      final (keyResults, modelResults) =
          await GeminiApi.testPool(keys, models);
      if (!mounted) return;
      final lines = <String>[];
      var allOk = true;
      for (final k in keyResults) {
        lines.add(
            'Key #${k.index}: ${k.ok ? 'OK' : 'FAIL'} (${k.status}, ${k.ms}ms via ${k.model})${k.ok ? '' : ' - ${k.message}'}');
        if (!k.ok) allOk = false;
      }
      for (final m in modelResults) {
        lines.add(
            'Model ${m.model}: ${m.ok ? 'OK' : 'FAIL'}${m.status > 0 ? ' (${m.status}, ${m.ms}ms)' : ''} - ${m.message}');
        if (!m.ok) allOk = false;
      }
      setState(() {
        _gemTesting = false;
        _gemTestOk = allOk;
        _gemTestLines = lines;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gemTesting = false;
        _gemTestOk = false;
        _gemTestLines = ['Test failed: $e'];
      });
    }
  }

  Future<void> _clearGemini() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Gemini pool?'),
        content: const Text(
            'Your Gemini API keys and model ids will be deleted from this device.'),
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
      await GeminiStore.clear();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _gemKeysCtrl.clear();
      _gemModelsCtrl.clear();
      _gemTestLines = [];
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Gemini pool removed.')));
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
            _metadataSourceCard(scheme),
            if (GeminiWeb.isSupported) ...[
              const SizedBox(height: 12),
              _geminiWebCard(scheme),
            ],
            const SizedBox(height: 12),
            _distributionCard(scheme),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(scheme, Icons.auto_awesome_outlined,
                        'Gemini AI metadata'),
                    const SizedBox(height: 8),
                    Text(
                      'Writes Zedge listing metadata (title, 10 tags, category, description) for each batch set from its prompt. Keys rotate automatically: rate limit (429) moves to the next key, an unknown model (404) moves to the next model.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _gemKeysCtrl,
                      obscureText: _gemObscure,
                      maxLines: 4,
                      minLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Gemini API keys (one per line)',
                        hintText: 'AIza...',
                        prefixIcon:
                            const Icon(Icons.vpn_key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_gemObscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _gemObscure = !_gemObscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _gemModelsCtrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Model ids (one per line)',
                        hintText:
                            'gemini-flash-latest\ngemini-2.5-flash',
                        prefixIcon:
                            Icon(Icons.smart_toy_outlined),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Empty model list uses gemini-flash-latest. Models are tried top-down.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _gemSaving ? null : _saveGemini,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                                _gemSaving ? 'Saving...' : 'Save'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _gemTesting ? null : _testGemini,
                            icon: const Icon(
                                Icons.wifi_tethering_outlined),
                            label: Text(_gemTesting
                                ? 'Testing...'
                                : 'Test pool'),
                          ),
                        ),
                      ],
                    ),
                    if (_gemTestLines.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_gemTestOk
                                  ? Colors.green
                                  : Theme.of(context)
                                      .colorScheme
                                      .error)
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            for (final line in _gemTestLines)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      line.contains('OK')
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      size: 16,
                                      color: line.contains('OK')
                                          ? Colors.green
                                          : Theme.of(context)
                                              .colorScheme
                                              .error,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(line,
                                          style:
                                              Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _clearGemini,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text(
                          'Remove Gemini pool from this device'),
                      style: TextButton.styleFrom(
                          foregroundColor: scheme.error),
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

  Widget _metadataSourceCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme, Icons.source_outlined, 'Metadata source'),
            const SizedBox(height: 4),
            RadioGroup<String>(
              groupValue: _metaProvider,
              onChanged: (v) {
                if (v == null) return;
                if (v == 'web' && !GeminiWeb.isSupported) return;
                _setProvider(v);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gemini API'),
                    subtitle: const Text(
                        'Your API keys. Fast, but rate-limited.'),
                    value: 'api',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gemini Web'),
                    subtitle: Text(GeminiWeb.isSupported
                        ? 'Your Google session in an embedded browser. No API key, no API rate limits.'
                        : 'Windows and Android apps only.'),
                    value: 'web',
                    enabled: GeminiWeb.isSupported,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _geminiWebCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme, Icons.language_outlined, 'Gemini Web'),
            const SizedBox(height: 8),
            Text(
              'Drives gemini.google.com in an embedded browser with your own Google session - the same approach as the Generator Hub workflow. '
              'No API key needed, so no API rate limits. Metadata is generated from the actual image (vision), plus a policy verdict per set.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _webConnected
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked_outlined,
                  color:
                      _webConnected ? scheme.primary : scheme.outline,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _webConnected ? 'Connected' : 'Not connected',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (_webConnected)
                  TextButton.icon(
                    onPressed: _webBusy ? null : _disconnectWeb,
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Disconnect'),
                    style: TextButton.styleFrom(
                        foregroundColor: scheme.error),
                  )
                else
                  FilledButton.icon(
                    onPressed: _connectWeb,
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Connect'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Note: this automates the Gemini website, which Google may throttle or restrict at any time.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cloudCtrl.dispose();
    _keyCtrl.dispose();
    _secretCtrl.dispose();
    _gemKeysCtrl.dispose();
    _gemModelsCtrl.dispose();
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
