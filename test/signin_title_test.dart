import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/browser/chromium_browser.dart';

void main() {
  test('Gemini window title detection', () {
    expect(ChromiumBrowser.isGeminiAppTitle('Google Gemini - Google Chrome'), isTrue);
    expect(ChromiumBrowser.isGeminiAppTitle('Google Gemini and 1 more page - Personal - Microsoft\u200b Edge'), isTrue);
    expect(ChromiumBrowser.isGeminiAppTitle('Sign in - Google Accounts - Google Chrome'), isFalse);
    expect(ChromiumBrowser.isGeminiAppTitle(''), isFalse);
  });
}
