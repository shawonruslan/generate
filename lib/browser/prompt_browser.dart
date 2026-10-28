import 'dart:typed_data';

import 'chromium_browser.dart';

/// What the Image to Prompt service needs from a browser: the controlled
/// Chromium window on Windows ([ChromiumBrowser]) or the built-in Firefox
/// engine on Android (`GeckoPromptBrowser`).
abstract class PromptBrowser {
  /// Human name for the status line ("Google Chrome", "Built-in browser").
  String get displayName;
  bool get isConnected;
  int get tabCount;
  Stream<WebImageRequest> get requests;
  Stream<void> get changes;

  Future<void> openTab(String url);
  void setBasket(List<String> srcs, int pages);
  Future<void> notifyPage(String sessionId, String src, String state,
      [String message = '']);
  Future<FetchedImage> fetchImage(String src,
      {String sessionId = '', String pageUrl = ''});
  Future<Uint8List?> rasterizeInPage(String src, String sessionId);

  /// PNG of a visible page area (see `WebImageRef.meta`), null on failure.
  Future<Uint8List?> captureRegion(String sessionId, Map<String, dynamic> meta);

  /// Scrolls the picture [src] into view and screenshots it (pictures that
  /// cannot be downloaded). Null when not supported / not found.
  Future<Uint8List?> captureElement(String src, String sessionId);

  /// Gemini / Google session cookies of the browser profile.
  Future<List<Map<String, dynamic>>> googleCookies();
  Future<List<Map<String, dynamic>>> refreshGoogleCookies();
  Future<void> closeBrowser();
}
