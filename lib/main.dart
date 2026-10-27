import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'secure_store.dart';

/// Writes uncaught Dart errors to <app support>/crash_log.txt so a crash
/// can be diagnosed (Settings shows nothing once the window is gone).
Future<void> _logCrash(Object e, StackTrace? st) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}crash_log.txt');
    await f.writeAsString('[${DateTime.now().toIso8601String()}] $e\n$st\n\n',
        mode: FileMode.append, flush: true);
  } catch (_) {}
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      _logCrash(d.exception, d.stack);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      _logCrash(e, st);
      return true; // handled: keep the app alive
    };
    runApp(const AiImageStudioApp());
  }, (e, st) => _logCrash(e, st));
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
