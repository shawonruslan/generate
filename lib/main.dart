import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'browser/chromium_browser.dart';
import 'screens/home_screen.dart';
import 'secure_store.dart';
import 'gemini_web.dart';
import 'gemini_image_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final p = await AppPrefs.prefs();
    GeminiWebClient.allowAppRotation =
        p.getBool('gemini_app_rotation') ?? false;
  } catch (_) {}
  await ImageEngine.load();
  // A hidden sign-in browser left over from the previous run is stopped.
  ChromiumBrowser.reapLeftover();
  runApp(const AiImageStudioApp());
}

class AiImageStudioApp extends StatefulWidget {
  const AiImageStudioApp({super.key});

  @override
  State<AiImageStudioApp> createState() => _AiImageStudioAppState();
}

class _AiImageStudioAppState extends State<AiImageStudioApp> {
  ThemeMode _mode = ThemeMode.system;
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    _load();
    // Closing the app also closes the hidden Gemini browser.
    _life = AppLifecycleListener(onExitRequested: () async {
      try {
        await ChromiumBrowser.closeBackground()
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    String saved;
    try {
      saved = await AppPrefs.themeMode();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
  }

  Future<void> _setMode(ThemeMode mode) async {
    setState(() => _mode = mode);
    try {
      await AppPrefs.setThemeMode(switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MH STUDIO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: HomeScreen(mode: _mode, onThemeChanged: _setMode),
    );
  }
}
