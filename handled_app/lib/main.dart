import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/dashboard_shell.dart';
import 'screens/approval_queue_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const HandledApp(),
    ),
  );
}

class HandledApp extends StatelessWidget {
  const HandledApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final isAuth = authProvider.isAuthenticated;
        final isGoingToLogin = state.matchedLocation == '/login';
        final isGoingToSignup = state.matchedLocation == '/signup';

        if (authProvider.isLoading) return null; // Wait for initial check

        if (!isAuth && !isGoingToLogin && !isGoingToSignup) {
          return '/login';
        }
        if (isAuth && (isGoingToLogin || isGoingToSignup)) {
          return '/';
        }
        return null;
      },
      routes: [
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
              path: '/approvals',
              builder: (context, state) => const ApprovalQueueScreen(),
            ),
          ],
        ),
      ],
    );

    if (authProvider.isLoading) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: 'Handled.ai',
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
