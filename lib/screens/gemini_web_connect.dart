import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../gemini_web.dart';
import '../gemini_web_android.dart';

/// Manual Google sign-in for the Gemini Web provider.
///
/// The page stays open in the embedded browser; the user completes the
/// Google sign-in there by hand, then taps "Verify connection".
///  - Windows: Edge WebView2 (mouse only - use the on-screen keyboard
///    or right-click paste to type).
///  - Android: system WebView in desktop mode - the normal keyboard
///    works, just type.
/// No credentials are typed into the app and nothing is stored - only
/// the browser keeps the session.
class GeminiWebConnectPage extends StatefulWidget {
  const GeminiWebConnectPage({super.key});

  @override
  State<GeminiWebConnectPage> createState() => _GeminiWebConnectPageState();
}

class _GeminiWebConnectPageState extends State<GeminiWebConnectPage> {
  ww.WebviewController? _winController;
  wf.WebViewController? _androidController;
  GeminiWebDriver? _driver;
  bool _ready = false;
  bool _busy = false;
  String _status = 'Opening Gemini...';

  bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _winController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await GeminiWebEnv.ensure();
      if (_isWindows) {
        final c = ww.WebviewController();
        await c.initialize();
        _winController = c;
        _driver = WindowsGeminiWebDriver(c);
      } else {
        final c = newAndroidGeminiController();
        _androidController = c;
        _driver = AndroidGeminiWebDriver(c);
      }
      await _driver!.loadUrl('https://gemini.google.com/app');
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

  /// Verifies a real logged-in Gemini session: the page shows the
  /// signed-in Google profile avatar, which only renders when logged
  /// in.
  Future<void> _verify() async {
    final driver = _driver;
    if (_busy || !_ready || driver == null) return;
    setState(() => _busy = true);
    _setStatus('Verifying the Gemini session...');
    try {
      final ok = await driver.js(GeminiWebJs.loggedIn).catchError((_) => false);
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
    final driver = _driver;
    if (_busy || !_ready || driver == null) return;
    try {
      await driver.loadUrl('https://gemini.google.com/app');
      _setStatus(
          'Page reloaded. Sign in above if needed, then tap Verify connection.');
    } catch (e) {
      _setStatus('Reload failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final webview = _ready
        ? (_isWindows
            ? ww.Webview(_winController!)
            : wf.WebViewWidget(controller: _androidController!))
        : const Center(child: CircularProgressIndicator());
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Gemini Web')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 480, child: webview),
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
            _isWindows
                ? 'Tip: type with the Windows on-screen keyboard (Win + Ctrl + O), '
                    'or copy text from elsewhere and right-click inside the page to paste. '
                    'The app never sees or stores your Google credentials - the session '
                    'stays in the app\'s private browser profile until you disconnect.'
                : 'The app never sees or stores your Google credentials - the session '
                    'stays in the WebView until you disconnect.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
