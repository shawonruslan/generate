import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionProvider();
  final theme = ThemeProvider();
  await session.restore();
  runApp(TeamDriveApp(session: session, theme: theme));
}

class TeamDriveApp extends StatelessWidget {
  final SessionProvider session;
  final ThemeProvider theme;
  const TeamDriveApp({super.key, required this.session, required this.theme});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: theme),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, t, _) => MaterialApp(
          title: 'Team Drive',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.day(),
          darkTheme: AppTheme.night(),
          themeMode: t.night ? ThemeMode.dark : ThemeMode.light,
          home: Consumer<SessionProvider>(
            builder: (context, s, _) {
              if (!s.ready) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              return s.isLoggedIn
                  ? const HomeScreen()
                  : const LoginScreen();
            },
          ),
        ),
      ),
    );
  }
}
