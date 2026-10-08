import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'secure_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiImageStudioApp());
}

class AiImageStudioApp extends StatefulWidget {
  const AiImageStudioApp({super.key});

  @override
  State<AiImageStudioApp> createState() => _AiImageStudioAppState();
}

class _AiImageStudioAppState extends State<AiImageStudioApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _load();
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
      title: 'AI Image Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: HomeScreen(mode: _mode, onThemeChanged: _setMode),
    );
  }
}
