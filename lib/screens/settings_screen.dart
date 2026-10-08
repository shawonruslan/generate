import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../cloudinary_api.dart';
import '../gemini_api.dart';
import '../gemini_web.dart';
import '../secure_store.dart';
import 'gemini_web_connect.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
    _loadGemini();
    _loadWeb();
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

  Widget _metadataSourceCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(scheme, Icons.source_outlined, 'Metadata source'),
            const SizedBox(height: 4),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gemini API'),
              subtitle:
                  const Text('Your API keys. Fast, but rate-limited.'),
              value: 'api',
              groupValue: _metaProvider,
              onChanged: (v) => v == null ? null : _setProvider(v),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gemini Web'),
              subtitle: Text(GeminiWeb.isSupported
                  ? 'Your Google session in an embedded browser. No API key, no API rate limits.'
                  : 'Windows desktop app only.'),
              value: 'web',
              groupValue: _metaProvider,
              onChanged: GeminiWeb.isSupported
                  ? (v) => v == null ? null : _setProvider(v)
                  : null,
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
