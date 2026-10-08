import 'package:webview_flutter/webview_flutter.dart' as wf;

import 'gemini_web.dart';

/// Desktop Chrome user-agent: with this, gemini.google.com serves the
/// desktop DOM, so the same [GeminiWebJs] automation works on the phone.
const androidDesktopUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

/// [GeminiWebDriver] over a webview_flutter [WebViewController].
/// `runJavaScriptReturningResult` already converts JS primitives to
/// Dart values, so no extra decoding is needed.
class AndroidGeminiWebDriver implements GeminiWebDriver {
  final wf.WebViewController controller;
  AndroidGeminiWebDriver(this.controller);

  @override
  Future<dynamic> js(String script) =>
      controller.runJavaScriptReturningResult(script);

  @override
  Future<void> loadUrl(String url) =>
      controller.loadRequest(Uri.parse(url));
}

/// Builds a Gemini-ready Android WebView controller: JavaScript on,
/// desktop user-agent, pointed at the Gemini app. Call only on Android.
wf.WebViewController newAndroidGeminiController() {
  return wf.WebViewController()
    ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
    ..setUserAgent(androidDesktopUserAgent)
    ..setNavigationDelegate(
      wf.NavigationDelegate(
        onWebResourceError: (_) {},
      ),
    );
}
