import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../gemini_web.dart';

/// One-time Google sign-in inside the embedded Edge WebView2.
///
/// The plugin forwards mouse but not keyboard, so the credentials are
/// collected in native fields and filled into Google's form via JS.
/// They live in memory only - never written to disk. The session
/// cookies persist in the WebView2 profile folder, so this is needed
/// once until Disconnect.
class GeminiWebConnectPage extends StatefulWidget {
  const GeminiWebConnectPage({super.key});

  @override
  State<GeminiWebConnectPage> createState() =>
      _GeminiWebConnectPageState();
}

class _GeminiWebConnectPageState extends State<GeminiWebConnectPage> {
  final _controller = WebviewController();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _codeCtl = TextEditingController();

  bool _ready = false;
  bool _busy = false;
  String _stage = 'email'; // email -> password -> totp -> done
  String _status = 'Loading Google sign-in...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await GeminiWebEnv.ensure();
      await _controller.initialize();
      // Start at Gemini itself: an existing session lands straight in
      // the chat, otherwise Google redirects to sign-in.
      await _controller.loadUrl('https://gemini.google.com/app');
      if (!mounted) return;
      setState(() {
        _ready = true;
        _status = 'Checking the session...';
      });
      if (await _waitFor(GeminiWebJs.loggedIn,
          timeout: const Duration(seconds: 15))) {
        await _finish();
        return;
      }
      if (!mounted) return;
      final kind =
          await _js('(${GeminiWebJs.loginFieldKind})()').catchError((_) => 'none');
      if (kind == 'password') {
        setState(() {
          _stage = 'password';
          _status = 'Enter your Google password.';
        });
      } else if (kind == 'email') {
        // Clean dedicated sign-in page for the email step.
        await _controller.loadUrl('https://accounts.google.com/');
        if (!mounted) return;
        setState(() {
          _stage = 'email';
          _status = 'Enter your Google email below.';
        });
      } else {
        setState(() {
          _stage = 'manual';
          _status =
              'Complete the sign-in in the browser above, then tap Check.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not start the browser: $e');
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<dynamic> _js(String script) =>
      _controller.executeScript(script);

  /// Waits until [jsCondition] is true (or timeout).
  Future<bool> _waitFor(String jsCondition,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await _js(jsCondition) == true) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<void> _submitEmail() async {
    final email = _emailCtl.text.trim();
    if (email.isEmpty || _busy) return;
    setState(() => _busy = true);
    _setStatus('Submitting email...');
    try {
      // Wait for the field - the page may still be rendering.
      final found = await _waitFor(
          "(${GeminiWebJs.loginFieldKind})() === 'email'",
          timeout: const Duration(seconds: 15));
      if (!found) throw Exception('Email field not found.');
      final r = await _js(GeminiWebJs.submitLogin(email));
      if (r != 'submitted' && r != 'filled-no-button') {
        throw Exception('Email field not found.');
      }
      // Wait for the password step (or an already-logged-in redirect).
      final outcome = await _waitLoginOutcome();
      if (!mounted) return;
      setState(() => _busy = false);
      _applyOutcome(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus('Email step failed: $e');
    }
  }

  /// After a submit, waits for: chat (done), password/totp (next
  /// step) or timeout.
  Future<String> _waitLoginOutcome() async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await _js(GeminiWebJs.loggedIn) == true) return 'done';
        final kind = await _js('(${GeminiWebJs.loginFieldKind})()')
            .catchError((_) => 'none');
        if (kind == 'password' || kind == 'totp') return kind;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
    return 'timeout';
  }

  void _applyOutcome(String outcome) {
    if (outcome == 'done') {
      _finish();
    } else if (outcome == 'password') {
      setState(() {
        _stage = 'password';
        _status = 'Enter your Google password.';
      });
    } else if (outcome == 'totp') {
      setState(() {
        _stage = 'totp';
        _status =
            'Google asks for a verification code. Enter it below (or approve the prompt on your phone, then tap Check).';
      });
    } else {
      setState(() {
        _stage = 'manual';
        _status =
            'Still not signed in. Finish any remaining step in the browser above (e.g. approve on your phone), then tap Check.';
      });
    }
  }

  Future<void> _submitPassword() async {
    final pw = _passCtl.text;
    if (pw.isEmpty || _busy) return;
    // Drop the password from memory as soon as it is used.
    final pwCopy = pw;
    _passCtl.clear();
    setState(() => _busy = true);
    _setStatus('Signing in...');
    try {
      final found = await _waitFor(
          "(${GeminiWebJs.loginFieldKind})() === 'password'",
          timeout: const Duration(seconds: 15));
      if (!found) throw Exception('Password field not found.');
      final r = await _js(GeminiWebJs.submitLogin(pwCopy));
      if (r != 'submitted' && r != 'filled-no-button') {
        throw Exception('Password field not found.');
      }
      final outcome = await _waitLoginOutcome();
      if (!mounted) return;
      setState(() => _busy = false);
      _applyOutcome(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus('Sign-in failed: $e');
    }
  }

  Future<void> _submitTotp() async {
    final code = _codeCtl.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    _setStatus('Verifying code...');
    try {
      final found = await _waitFor(
          "(${GeminiWebJs.loginFieldKind})() === 'totp'",
          timeout: const Duration(seconds: 15));
      if (!found) throw Exception('Verification field not found.');
      await _js(GeminiWebJs.submitLogin(code));
      final ok = await _waitFor(GeminiWebJs.loggedIn,
          timeout: const Duration(seconds: 25));
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        await _finish();
      } else {
        _setStatus('Code not accepted. Try again or tap Check.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus('Verification failed: $e');
    }
  }


  Future<void> _check() async {
    setState(() => _busy = true);
    _setStatus('Checking the Gemini session...');
    try {
      // Make sure we are on Gemini itself for the check.
      await _controller.loadUrl('https://gemini.google.com/app');
      final ok =
          await _waitFor(GeminiWebJs.loggedIn, timeout: const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _busy = false);
      if (ok) {
        await _finish();
      } else {
        _setStatus(
            'Not signed into Gemini yet. Complete the sign-in in the browser above, then tap Check again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _setStatus('Check failed: $e');
    }
  }

  Future<void> _finish() async {
    await GeminiWebPrefs.setConnected(true);
    _setStatus('Connected! You can close this page.');
    if (!mounted) return;
    setState(() {
      _stage = 'done';
      _busy = false;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Gemini Web')),
      body: Column(
        children: [
          if (_ready)
            SizedBox(
              height: 400,
              child: Webview(_controller),
            )
          else
            const SizedBox(
              height: 400,
              child: Center(child: CircularProgressIndicator()),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_status,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  if (_stage == 'email') ...[
                    TextField(
                      controller: _emailCtl,
                      decoration: const InputDecoration(
                        labelText: 'Google email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _submitEmail(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submitEmail,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Continue'),
                    ),
                  ],
                  if (_stage == 'password') ...[
                    TextField(
                      controller: _passCtl,
                      decoration: const InputDecoration(
                        labelText: 'Google password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => _submitPassword(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submitPassword,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                  ],
                  if (_stage == 'totp') ...[
                    TextField(
                      controller: _codeCtl,
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _submitTotp(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submitTotp,
                      child: const Text('Verify'),
                    ),
                  ],
                  if (_stage == 'manual' || _stage == 'totp') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _check,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Check connection'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Your password is only used to fill Google\u2019s own sign-in form and is never stored on this device. '
                    'The Google session stays in the app\u2019s private browser profile until you disconnect.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
