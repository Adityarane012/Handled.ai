// Smoke test: an unauthenticated launch lands on the login screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:handled_app/main.dart';
import 'package:handled_app/providers/auth_provider.dart';

void main() {
  testWidgets('unauthenticated app shows the login screen', (tester) async {
    SharedPreferences.setMockInitialValues({}); // no JWT stored

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const HandledApp(),
      ),
    );

    // First frame is the loading spinner; let the async auth check resolve.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Log in to your workspace'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
