import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'browser/chromium_browser.dart';
import 'cloud_sync.dart';
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
    // Cloud sync: pull newer cloud state / push local state in the
    // background when signed in (no-op when signed out).
    unawaited(CloudSync.autoSyncOnStart());
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
      home: _Gate(mode: _mode, onThemeChanged: _setMode),
    );
  }
}

/// Login gate (v1.22.0, his rule): the app ALWAYS opens on the
/// login screen. The main interface (HomeScreen) is built only
/// after a stored session is restored or the user signs in -
/// there is no path to the interface without an account.
class _Gate extends StatefulWidget {
  const _Gate({required this.mode, required this.onThemeChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  late final Future<bool> _restore = CloudSync.restoreSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _restore,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon/app_icon.png',
                        width: 72, height: 72),
                  ),
                  const SizedBox(height: 18),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }
        return ValueListenableBuilder<bool>(
          valueListenable: CloudSync.authState,
          builder: (context, signedIn, _) => signedIn
              ? HomeScreen(
                  mode: widget.mode, onThemeChanged: widget.onThemeChanged)
              : const LoginScreen(),
        );
      },
    );
  }
}
