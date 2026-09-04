import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_shell.dart';
import 'services/holiday_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop only: give the app a proper resizable window with a sane minimum.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(1400, 920),
      minimumSize: Size(1024, 680),
      center: true,
      title: 'Zedge Studio',
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final AppState state = AppState(holidays: HolidayService());
  runApp(ZedgeStudioApp(state: state));
  state.boot();
}

class ZedgeStudioApp extends StatelessWidget {
  const ZedgeStudioApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        title: 'Zedge Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const HomeShell(),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: true,
        ),
      ),
    );
  }
}
