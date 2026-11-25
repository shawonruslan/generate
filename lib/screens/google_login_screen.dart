import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../gemini_accounts.dart';
import '../gemini_web.dart';
import '../secure_store.dart';

/// In-app Google sign-in for Gemini — the app version of Gemini HD
/// Studio's "+ Add Gmail" (accounts.google.com/AddSession -> gemini.google.com).
/// When Gemini opens, the Google cookies of this login are saved as the
/// Gemini session (no manual cookie export) and the accounts are scanned.
/// Opening it again adds another Gmail to the same login (u/1, u/2, ...).
class GoogleLoginScreen extends StatefulWidget {
  const GoogleLoginScreen({super.key, this.addAccount = false});

  /// true = AddSession (another Gmail); false = normal sign-in / re-sync.
  final bool addAccount;

  @override
  State<GoogleLoginScreen> createState() => _GoogleLoginScreenState();
}

class _GoogleLoginScreenState extends State<GoogleLoginScreen> {
  static const _continue = 'https%3A%2F%2Fgemini.google.com%2Fapp';
  bool _saving = false;
  bool _done = false;
  String _status = 'Sign in to your Google account.';

  String get _startUrl => widget.addAccount
      ? 'https://accounts.google.com/AddSession?hl=en&continue=$_continue'
      : 'https://accounts.google.com/ServiceLogin?hl=en&continue=$_continue';

  static bool _isGeminiApp(WebUri? u) =>
      u != null && u.host == 'gemini.google.com' && u.path.contains('/app');

  Future<void> _capture() async {
    if (_saving || _done) return;
    setState(() {
      _saving = true;
      _status = 'Signed in — saving Gemini session...';
    });
    try {
      final cm = CookieManager.instance();
      final byKey = <String, Map<String, dynamic>>{};
      for (final url in const [
        'https://gemini.google.com',
        'https://www.google.com',
        'https://accounts.google.com',
      ]) {
        for (final c in await cm.getCookies(url: WebUri(url))) {
          final domain = (c.domain == null || c.domain!.isEmpty)
              ? '.google.com'
              : c.domain!;
          if (!domain.contains('google.com')) continue;
          final expires = c.expiresDate == null ? -1 : c.expiresDate! ~/ 1000;
          byKey['${c.name}|$domain'] = {
            'name': c.name,
            'value': '${c.value}',
            'domain': domain,
            'path': c.path ?? '/',
            'expires': expires,
            'httpOnly': c.isHttpOnly ?? false,
            'secure': c.isSecure ?? true,
            'sameSite': c.sameSite?.toNativeValue() ?? 'None',
          };
        }
      }
      final json = jsonEncode({'cookies': byKey.values.toList()});
      final session = GeminiWebSession.parse(json);
      if (session.authCookies.isEmpty) {
        throw GeminiWebException(
            'Google login cookies were not found. Finish signing in, then '
            'wait for Gemini to open.');
      }
      await GeminiWebStore.save(json);
      setState(() => _status = 'Saved. Scanning signed-in Gmail accounts...');
      final accounts = await GeminiAccounts.scan();
      _done = true;
      if (!mounted) return;
      Navigator.of(context).pop(accounts.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = e is GeminiWebException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.addAccount ? 'Add Gmail account' : 'Sign in with Google'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _capture,
            child: const Text('I am signed in'),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                Expanded(child: Text(_status)),
              ]),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_startUrl)),
              initialSettings: InAppWebViewSettings(
                // Desktop Chrome UA, same as the Gemini client: Google
                // refuses sign-in from UAs that look like an embedded view.
                userAgent: geminiWebUserAgent,
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                incognito: false,
                cacheEnabled: true,
              ),
              onLoadStop: (controller, url) async {
                if (_isGeminiApp(url)) await _capture();
              },
              onUpdateVisitedHistory: (controller, url, _) async {
                if (_isGeminiApp(url)) await _capture();
              },
            ),
          ),
        ],
      ),
    );
  }
}
