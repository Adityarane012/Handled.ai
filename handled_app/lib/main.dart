import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/dashboard_shell.dart';
import 'screens/approval_queue_screen.dart';
import 'screens/ops_tools_screen.dart';
import 'screens/history_screen.dart';
import 'screens/team_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const HandledApp(),
    ),
  );
}

class HandledApp extends StatefulWidget {
  const HandledApp({super.key});

  @override
  State<HandledApp> createState() => _HandledAppState();
}

class _HandledAppState extends State<HandledApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();

    // Built once, not per build. Previously a new GoRouter was constructed on
    // every rebuild, and while the initial auth check was in flight the app
    // returned a plain MaterialApp with no route table at all — so on web,
    // opening any URL other than "/" (a bookmarked /history, or a browser
    // that remembered /login) threw "no corresponding route" on startup and
    // silently dumped the user at "/". The splash route below keeps a single
    // router alive for the whole lifetime instead.
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: auth, // re-evaluate redirects when auth state changes
      redirect: (context, state) {
        final loc = state.matchedLocation;

        if (auth.isLoading) return loc == '/splash' ? null : '/splash';
        if (loc == '/splash') return auth.isAuthenticated ? '/' : '/login';

        final onAuthScreen = loc == '/login' || loc == '/signup';
        if (!auth.isAuthenticated && !onAuthScreen) return '/login';
        if (auth.isAuthenticated && onAuthScreen) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => DashboardShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardPlaceholder(),
            ),
            GoRoute(
              path: '/ops',
              builder: (context, state) => const OpsToolsScreen(),
            ),
            GoRoute(
              path: '/approvals',
              builder: (context, state) => const ApprovalQueueScreen(),
            ),
            GoRoute(
              path: '/history',
              builder: (context, state) => const HistoryScreen(),
            ),
            GoRoute(
              path: '/team',
              builder: (context, state) => const TeamScreen(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Handled.ai',
      theme: AppTheme.darkTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
