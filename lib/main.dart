import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'config/build_config.dart';
import 'state/app_state.dart';
import 'state/nav.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(720, 520),
      center: true,
      title: 'Meta Hawladar · Zedge Content Studio',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  final profile = BuildProfile.byId(BuildProfile.compileTimeId);
  final app = AppState(profile);
  // ignore: unawaited_futures
  app.init();
  runApp(AutomationHubApp(app: app));
}

class AutomationHubApp extends StatelessWidget {
  const AutomationHubApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<NavState>(create: (_) => NavState()),
      ],
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final theme = buildAppTheme(state.palette);
          return MaterialApp(
            title: 'Meta Hawladar · ${state.profile.title}',
            debugShowCheckedModeBanner: false,
            theme: theme,
            darkTheme: theme,
            themeMode: ThemeMode.light,
            scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: true),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(state.palette.fontScale)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
