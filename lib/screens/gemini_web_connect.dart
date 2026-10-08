import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../gemini_web.dart';

/// Manual Google sign-in for the Gemini Web provider.
///
/// The page stays open in the embedded browser; the user completes the
/// Google sign-in there by hand (mouse works - click through the flow),
/// then taps "Verify connection". No credentials are typed into the app
/// and nothing is stored - only the browser profile keeps the session.
class GeminiWebConnectPage extends StatefulWidget {
  const GeminiWebConnectPage({super.key});

  @override
  State<GeminiWebConnectPage> createState() => _GeminiWebConnectPageState();
}

class _GeminiWebConnectPageState extends State<GeminiWebConnectPage> {
  final WebviewController _controller = WebviewController();
  bool _ready = false;
  bool _busy = false;
  String _status = 'Opening Gemini...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await GeminiWebEnv.ensure();
      await _controller.initialize();
      await _controller.loadUrl('https://gemini.google.com/app');
      if (!mounted) return;
      setState(() {
        _ready = true;
        _status =
            'Sign in to Google in the browser above (click "Sign in" if you see it), then tap Verify connection.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not start the browser: $e');
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<dynamic> _js(String script) async {
    final raw = await _controller.executeScript(script);
    if (raw == null) throw Exception('No response from the browser.');
    return jsonDecode(raw);
  }

  /// Verifies a real logged-in Gemini session: the check requires the
  /// gemini.google.com host, the actual chat editor, and no visible
  /// "Sign in" entry point.
  Future<void> _verify() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    _setStatus('Verifying the Gemini session...');
    try {
      final ok = await _js(GeminiWebJs.loggedIn).catchError((_) => false);
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok == true) {
        await GeminiWebPrefs.setConnected(true);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        _setStatus(
            'Not signed in yet. Finish the Google sign-in in the browser above, then tap Verify connection again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus('Verification failed: $e');
    }
  }

  Future<void> _reload() async {
    if (_busy || !_ready) return;
    try {
      await _controller.loadUrl('https://gemini.google.com/app');
      _setStatus(
          'Page reloaded. Sign in above if needed, then tap Verify connection.');
    } catch (e) {
      _setStatus('Reload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Gemini Web')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_ready)
            SizedBox(
              height: 480,
              child: Webview(_controller),
            )
          else
            const SizedBox(
              height: 480,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_ready && !_busy) ? _verify : null,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(_busy ? 'Verifying...' : 'Verify connection'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_ready && !_busy) ? _reload : null,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Reload'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: type with the Windows on-screen keyboard (Win + Ctrl + O), '
            'or copy text from elsewhere and right-click inside the page to paste. '
            'The app never sees or stores your Google credentials - the session '
            'stays in the app\'s private browser profile until you disconnect.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
