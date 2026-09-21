// A failed login has to leave the user looking at the reason it failed.
//
// Regression this guards: AuthProvider.login() used to set the global
// `_isLoading`, which the router treats as "initial auth check in flight" and
// redirects to /splash. Pressing Login therefore navigated away from the login
// screen mid-request and destroyed it; on failure the user came back to a
// fresh screen with the error discarded and the fields cleared. A wrong
// password looked exactly like the button doing nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:handled_app/main.dart';
import 'package:handled_app/providers/auth_provider.dart';

void main() {
  testWidgets('a failed login keeps the screen and shows why', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: const HandledApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Log in to your workspace'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'nobody@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');

    // There is no backend in a widget test, so the request fails — the same
    // code path as a 401.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull, reason: 'must not setState after dispose');

    // Still on login — not bounced to a splash and back.
    expect(find.text('Log in to your workspace'), findsOneWidget);
    // And a reason is on screen rather than silently swallowed. The exact
    // wording isn't asserted: under TestWidgetsFlutterBinding every HTTP call
    // returns 400 rather than a real connection failure, so the message here
    // is not the one a browser would show. What matters is that the failure
    // surfaces at all — previously the screen was rebuilt and it vanished.
    expect(find.byKey(const Key('login-error')), findsOneWidget);
  });

  testWidgets('an in-flight login does not trigger the global splash redirect',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: auth,
      child: const HandledApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // isLoading means *initial check only*. A login attempt must not set it,
    // or the router will navigate away from the form underneath the user.
    // Handler attached immediately — an unawaited rejection would otherwise
    // surface as an unhandled async error before the pump below.
    final attempt = auth.login('nobody@example.com', 'wrong-password')
        .catchError((Object _) {});
    await tester.pump();
    expect(auth.isLoading, isFalse,
        reason: 'login must not flip the global initial-check flag');

    await attempt;
    await tester.pump(const Duration(seconds: 1));
  });
}
