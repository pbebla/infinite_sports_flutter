// Widget tests for the auth-wall welcome page (lib/onboarding/welcome_page.dart).
//
// WelcomePage is Firebase-free (its buttons just navigate to LoginPage /
// CreateAccountPage or fire optional callbacks), so it's fully testable
// standalone under plain `flutter test` — unlike MyApp/MyHomePage, which
// touch FirebaseAuth/RTDB in initState (see test/widget_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/onboarding/welcome_page.dart';

void main() {
  testWidgets(
      'initState resets a stale onboardingFlowActive flag (auth-wall F2 fix)',
      (tester) async {
    // Simulates a user who backed out of an in-flight signup flow before it
    // finished and landed back on the wall signed-out — the flag must not
    // stay stuck true, or the main gate would wrongly skip itself on their
    // next sign-in.
    onboardingFlowActive = true;
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    expect(onboardingFlowActive, isFalse);
  });

  testWidgets('renders the headline, email signup, and log in buttons',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    expect(find.text('GET IN THE GAME.'), findsOneWidget);
    expect(find.text('Sign up with Email'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets(
      'social sign-in buttons are hidden while kSocialSignInEnabled is false '
      '(owner decision 2026-07-26 — flows kept dormant for a possible future)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

    expect(kSocialSignInEnabled, isFalse,
        reason: 'flip the flag in welcome_page.dart to re-enable social '
            'sign-in; then restore the Google button tests from git history');
    expect(find.text('Sign up with Google'), findsNothing);
    expect(find.text('Sign up with Apple'), findsNothing);
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
