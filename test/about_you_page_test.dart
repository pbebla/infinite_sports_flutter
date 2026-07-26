// Widget tests for the reusable "About You" profile step
// (lib/onboarding/about_you_page.dart). Firebase-free: a `writeOverride`
// seam replaces the real `Users/<uid>` RTDB write so this is testable under
// plain `flutter test`, matching the pattern in test/welcome_page_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/onboarding/about_you_page.dart';
import 'package:infinite_sports_flutter/onboarding/profile_completion.dart';

/// The page is a SingleChildScrollView taller than the default 800x600 test
/// surface, so widgets like the Continue button or later referral chips
/// start out below the fold. Scroll them into view before tapping.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  testWidgets('renders date of birth, city, ZIP, gender, and referral fields',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(onDone: () {}, writeOverride: (_) async {}),
    ));

    expect(find.text('About you'), findsOneWidget);
    expect(find.text('Date of birth'), findsOneWidget);
    expect(find.byKey(const ValueKey('about_you_dob_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_you_city_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('about_you_zip_field')), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('How did you hear about us?'), findsOneWidget);
    // No phone field unless askPhone is set.
    expect(
        find.byKey(const ValueKey('about_you_phone_field')), findsNothing);
  });

  testWidgets('shows a phone field and Step X of Y subtitle when requested',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(
        onDone: () {},
        askPhone: true,
        stepIndex: 2,
        stepCount: 3,
        writeOverride: (_) async {},
      ),
    ));

    expect(find.byKey(const ValueKey('about_you_phone_field')), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('omits the Step X of Y subtitle when not given', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(onDone: () {}, writeOverride: (_) async {}),
    ));

    expect(find.textContaining('Step'), findsNothing);
  });

  testWidgets('gender chips are exactly Male and Female', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(onDone: () {}, writeOverride: (_) async {}),
    ));

    expect(find.byKey(const ValueKey('gender_chip_Male')), findsOneWidget);
    expect(find.byKey(const ValueKey('gender_chip_Female')), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
  });

  testWidgets('referral options are exactly kReferralOptions', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(onDone: () {}, writeOverride: (_) async {}),
    ));

    for (final option in kReferralOptions) {
      expect(find.byKey(ValueKey('referral_chip_$option')), findsOneWidget,
          reason: 'missing referral chip for "$option"');
    }
    // Exactly this many chips, no extras: 2 gender chips (Male/Female) + 8
    // referral chips = 10 ChoiceChips total.
    expect(find.byType(ChoiceChip), findsNWidgets(kReferralOptions.length + 2));
  });

  testWidgets('Continue blocks when all fields are empty (no onDone call)',
      (tester) async {
    var done = false;
    var writeCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(
        onDone: () => done = true,
        writeOverride: (_) async => writeCalled = true,
      ),
    ));

    await _tapVisible(tester, find.byKey(const ValueKey('about_you_continue_button')));
    await tester.pump();

    expect(done, isFalse);
    expect(writeCalled, isFalse);
    // Validation errors for the required fields are now visible.
    expect(find.text('City is required'), findsOneWidget);
    expect(find.text('Select one'), findsNWidgets(2)); // gender + referral
  });

  testWidgets(
      'Continue blocks when phone is required (askPhone) but empty',
      (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(
        onDone: () => done = true,
        askPhone: true,
        writeOverride: (_) async {},
      ),
    ));

    await tester.enterText(
        find.byKey(const ValueKey('about_you_city_field')), 'San Jose');
    await tester.enterText(
        find.byKey(const ValueKey('about_you_zip_field')), '94088');
    await tester.tap(find.byKey(const ValueKey('gender_chip_Male')));
    await _tapVisible(tester, find.byKey(const ValueKey('referral_chip_Instagram')));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const ValueKey('about_you_continue_button')));
    await tester.pump();

    expect(done, isFalse);
    expect(find.text('Enter a valid 10-digit phone number'), findsOneWidget);
  });

  testWidgets(
      'filling every field and tapping Continue writes all keys and calls onDone',
      (tester) async {
    Map<String, Object?>? written;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(
        onDone: () => done = true,
        askPhone: true,
        writeOverride: (data) async => written = data,
      ),
    ));

    // Open the date picker and accept the initial date (2000-01-01) via OK.
    await tester.tap(find.byKey(const ValueKey('about_you_dob_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('about_you_city_field')), 'San Jose');
    await tester.enterText(
        find.byKey(const ValueKey('about_you_zip_field')), '94088');
    await tester.enterText(
        find.byKey(const ValueKey('about_you_phone_field')), '4085551234');
    await tester.tap(find.byKey(const ValueKey('gender_chip_Female')));
    await _tapVisible(tester, find.byKey(const ValueKey('referral_chip_TikTok')));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const ValueKey('about_you_continue_button')));
    await tester.pump();
    await tester.pump();

    expect(done, isTrue);
    expect(written, isNotNull);
    expect(written!['DOB'], '01/01/2000');
    expect(written!['City'], 'San Jose');
    expect(written!['Zip'], '94088');
    expect(written!['Gender'], 'Female');
    expect(written!['ReferralSource'], 'TikTok');
    expect(written!['ProfileCompleted'], true);
    // UsPhoneInputFormatter formats as the user types (F1 owner feedback) —
    // the stored value is the formatted display string, not raw digits.
    expect(written!['Phone Number'], '(408)555-1234');
  });

  testWidgets('does not write a Phone Number key when askPhone is false',
      (tester) async {
    Map<String, Object?>? written;
    await tester.pumpWidget(MaterialApp(
      home: AboutYouPage(
        onDone: () {},
        writeOverride: (data) async => written = data,
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('about_you_dob_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('about_you_city_field')), 'San Jose');
    await tester.enterText(
        find.byKey(const ValueKey('about_you_zip_field')), '94088');
    await tester.tap(find.byKey(const ValueKey('gender_chip_Male')));
    await _tapVisible(tester, find.byKey(const ValueKey('referral_chip_Other')));
    await tester.pump();

    await _tapVisible(tester, find.byKey(const ValueKey('about_you_continue_button')));
    await tester.pump();
    await tester.pump();

    expect(written, isNotNull);
    expect(written!.containsKey('Phone Number'), isFalse);
  });

  testWidgets('back gesture/button does not pop (mandatory, no skip)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Builder(builder: (innerContext) {
              return Center(
                child: TextButton(
                  child: const Text('push'),
                  onPressed: () => Navigator.push(
                    innerContext,
                    MaterialPageRoute(
                      builder: (_) =>
                          AboutYouPage(onDone: () {}, writeOverride: (_) async {}),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);

    // Simulate the system back gesture/button.
    final dynamic widgetsAppState =
        tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Still on AboutYouPage — canPop:false blocked the pop.
    expect(find.text('About you'), findsOneWidget);
  });
}
