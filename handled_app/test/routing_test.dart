// Startup routing.
//
// Regression this guards: while the initial auth check was in flight the app
// returned a plain MaterialApp with no route table, so on web any initial URL
// other than "/" threw "Could not navigate to initial route" and silently
// dumped the user at "/". A single router now lives for the whole session,
// with a /splash route covering the in-flight window.
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:handled_app/main.dart';
import 'package:handled_app/providers/auth_provider.dart';

Future<void> _boot(WidgetTester tester) async {
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => AuthProvider(),
    child: const HandledApp(),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('no stored token lands on login, without throwing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _boot(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Log in to your workspace'), findsOneWidget);
  });

  testWidgets('a stale token is discarded and lands on login, without throwing', (tester) async {
    // The token can't be verified (no backend in a widget test), which is the
    // same path as an expired one: clear it and show login rather than hang.
    SharedPreferences.setMockInitialValues({'jwt_token': 'stale-token'});
    await _boot(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Log in to your workspace'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('jwt_token'), isNull, reason: 'a rejected token should not be kept');
  });
}
