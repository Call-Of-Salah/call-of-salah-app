import 'package:flutter_test/flutter_test.dart';

import 'package:callofsalah/main.dart';

void main() {
  testWidgets('App shows the sign-in screen when signed out',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    // Auth isn't configured in tests, so the gate shows the login screen.
    expect(find.text('Sign In'), findsWidgets);
  });
}
