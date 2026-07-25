// Widget tests for the auth-wall welcome page (lib/onboarding/welcome_page.dart).
//
// WelcomePage is Firebase-free (its buttons just navigate to LoginPage /
// CreateAccountPage or fire optional callbacks), so it's fully testable
// standalone under plain `flutter test` — unlike MyApp/MyHomePage, which
// touch FirebaseAuth/RTDB in initState (see test/widget_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/onboarding/welcome_page.dart';

void main() {
  testWidgets('renders the headline, email signup, and log in buttons',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    expect(find.text('GET IN THE GAME.'), findsOneWidget);
    expect(find.text('Sign up with Email'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Sign up with Google'), findsOneWidget);
  });

  testWidgets('hides the Apple button on a non-iOS test host', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    // `flutter test` runs on the host OS (Windows/Linux/macOS CI), never
    // iOS, so Platform.isIOS is false here — the Apple button must not
    // render, matching the spec's `Platform.isIOS`-gated button.
    expect(find.text('Sign up with Apple'), findsNothing);
  });

  testWidgets('tapping "Sign up with Google" invokes onGoogle', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: WelcomePage(onGoogle: () => tapped = true),
    ));

    await tester.tap(find.text('Sign up with Google'));
    expect(tapped, isTrue);
  });

  testWidgets(
      'tapping "Sign up with Google" without a callback shows a placeholder SnackBar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    await tester.tap(find.text('Sign up with Google'));
    await tester.pump(); // let the SnackBar animate in

    expect(
        find.text('Google sign-in coming in the next build'), findsOneWidget);
  });

  testWidgets('tapping "Sign up with Email" pushes CreateAccountPage',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    await tester.tap(find.text('Sign up with Email'));
    await tester.pumpAndSettle();

    expect(find.text('Sign Up'), findsOneWidget); // CreateAccountPage's AppBar
  });

  testWidgets('tapping "Log In" pushes LoginPage', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Login or Sign Up'), findsOneWidget); // LoginPage's AppBar
  });
}
