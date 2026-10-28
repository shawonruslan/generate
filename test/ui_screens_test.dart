// Screenshot rig for the UI (not part of the normal test run).
// Run: AIS_SHOTS=1 flutter test test/ui_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_image_studio/app_theme.dart';
import 'package:ai_image_studio/browser/image_prompt_service.dart';
import 'package:ai_image_studio/platform_ui.dart';
import 'package:ai_image_studio/screens/batch_screen.dart';
import 'package:ai_image_studio/screens/browser_screen.dart';
import 'package:ai_image_studio/screens/home_screen.dart';
import 'package:ai_image_studio/screens/settings_screen.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final on = Platform.environment['AIS_SHOTS'] != null;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!on) return;
    await _font('Inter', [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ]);
    await _font('MaterialIcons', [
      '/data/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    ]);
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'ais/gecko',
      'ais/keepawake',
      'plugins.flutter.io/path_provider',
    ]) {
      m.setMockMethodCallHandler(MethodChannel(ch), (c) async {
        if (c.method == 'batteryOk') return false;
        if (c.method == 'readAll') return <String, String>{};
        return null;
      });
    }
    debugForceAndroid = true;
    final s = ImagePromptService.instance;
    s.items.addAll([
      ImagePromptItem(
          id: '1',
          src: 'data:,',
          pageUrl: 'https://pinterest.com/pin/1',
          pageTitle: 'Desert canyon wallpaper - Pinterest',
          state: ImagePromptState.done,
          prompt:
              'A breathtaking panoramic view of a red rock canyon at golden hour, layered sandstone cliffs glowing orange, a winding river below, soft haze, ultra detailed, cinematic wide-angle lens.'),
      ImagePromptItem(
          id: '2',
          src: 'data:,',
          pageUrl: 'https://pinterest.com/pin/2',
          pageTitle: 'Neon city',
          state: ImagePromptState.running),
      ImagePromptItem(
          id: '3',
          src: 'data:,',
          pageUrl: 'https://pinterest.com/pin/3',
          state: ImagePromptState.error,
          error: 'Gemini session expired'),
    ]);
  });

  Future<void> shot(WidgetTester t, Widget screen, String name,
      {double h = 2600}) async {
    t.view.physicalSize = Size(390 * 2, h * 2);
    t.view.devicePixelRatio = 2;
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: screen,
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    t.view.reset();
  }

  testWidgets('browser', (t) async {
    await shot(t, const BrowserScreen(), 'browser');
  }, skip: !on);
  testWidgets('settings', (t) async {
    await shot(t, const SettingsScreen(), 'settings', h: 3200);
  }, skip: !on);
  testWidgets('home', (t) async {
    await shot(
        t,
        HomeScreen(mode: ThemeMode.dark, onThemeChanged: (_) {}),
        'home');
  }, skip: !on);
  testWidgets('batch', (t) async {
    await shot(t, const BatchScreen(), 'batch', h: 3200);
  }, skip: !on);
}
