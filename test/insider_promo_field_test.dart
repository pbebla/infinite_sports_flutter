// Widget tests for the Insider promo-code entry field
// (lib/registration/insider_promo_field.dart, Task F3). Firebase-free: every
// lookup InsiderPromoCodeField needs is replaced by an injectable override
// (lookupCodeOverride/insiderStatusOverride/alreadyReferredOverride/
// insiderNameOverride/myUidOverride/nowOverride) — mirrors the
// applyOverride/insiderStream seams in lib/insiders/insiders_info_page.dart.
//
// The field is a FormBuilderField, so it must live inside a FormBuilder to
// participate in saveAndValidate() — [_wrap] below reproduces the minimal
// harness dynamic_form.dart's DynamicRegistrationForm provides in
// production, with a Submit button that captures the field's resolved value.

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/registration/insider_promo_field.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';

void main() {
  final formKey = GlobalKey<FormBuilderState>();

  Widget wrap(InsiderPromoCodeField field) {
    return MaterialApp(
      home: Scaffold(
        body: FormBuilder(
          key: formKey,
          child: Column(
            children: [
              field,
              ElevatedButton(
                onPressed: () => formKey.currentState?.saveAndValidate(),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> enterAndSubmitCode(WidgetTester tester, String code) async {
    await tester.enterText(
        find.byKey(const ValueKey('insider_promo_code_field')), code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('a blank code has no error and stamps nothing', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      lookupCodeOverride: (_) async => null,
      insiderStatusOverride: (_) async => '',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => '',
      myUidOverride: 'me',
    )));
    await tester.pump();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid code'), findsNothing);
    expect(formKey.currentState!.value[kInsiderPromoAnswerKey], isNull);
  });

  testWidgets('a code that resolves to nothing shows "Invalid code"',
      (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      lookupCodeOverride: (_) async => null,
      insiderStatusOverride: (_) async => '',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => '',
      myUidOverride: 'me',
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'NOSUCH1');

    expect(find.text('Invalid code'), findsOneWidget);
    expect(formKey.currentState!.value[kInsiderPromoAnswerKey], isNull);
  });

  testWidgets('a suspended owner shows the suspended message', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      lookupCodeOverride: (_) async => 'owner1',
      insiderStatusOverride: (_) async => 'suspended',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => 'Sara',
      myUidOverride: 'me',
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'SARA123');

    expect(find.text('This code is not active right now'), findsOneWidget);
  });

  testWidgets('your own code shows the self-referral message', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      lookupCodeOverride: (_) async => 'me',
      insiderStatusOverride: (_) async => 'active',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => 'Me',
      myUidOverride: 'me',
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'MYCODE1');

    expect(find.text("You can't use your own code"), findsOneWidget);
  });

  testWidgets(
      'an already-referred account shows the once-ever guard message',
      (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      lookupCodeOverride: (_) async => 'owner1',
      insiderStatusOverride: (_) async => 'active',
      alreadyReferredOverride: (_) async => true,
      insiderNameOverride: (_) async => 'Sara',
      myUidOverride: 'me',
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'SARA123');

    expect(
        find.text('A referral code has already been used on this account.'),
        findsOneWidget);
  });

  testWidgets(
      'a valid code for a first-timer with an active promo shows acceptance '
      '+ the discount line and stamps the full outcome', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      priorSubmissions: const [],
      myEmail: 'new@example.com',
      myPhone: '4085551212',
      lookupCodeOverride: (_) async => 'owner1',
      insiderStatusOverride: (_) async => 'active',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => 'Sara',
      myUidOverride: 'me',
      nowOverride: DateTime(2026, 7, 27),
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'sara123');

    expect(find.text("Code accepted — Sara's referral"), findsOneWidget);
    expect(find.text('15% first-time player discount will be applied at '
        'checkout!'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    final outcome = formKey.currentState!.value[kInsiderPromoAnswerKey]
        as InsiderPromoOutcome?;
    expect(outcome, isNotNull);
    expect(outcome!.insiderCode, 'SARA123');
    expect(outcome.firstTimer, isTrue);
    expect(outcome.discountSource, 'first_timer_promo');
    expect(outcome.discountPct, 15.0);
    expect(outcome.eligibleFee, 60.0);
  });

  testWidgets(
      'a valid code for an existing player with an active promo shows the '
      'friendly no-discount copy and stamps FirstTimer=false with no '
      'discount', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: true, percent: 15),
      priorSubmissions: const [
        {'email': 'old@example.com', 'phone': '4085551212'},
      ],
      myEmail: 'old@example.com',
      myPhone: '4085551212',
      lookupCodeOverride: (_) async => 'owner1',
      insiderStatusOverride: (_) async => 'active',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => 'Sara',
      myUidOverride: 'me',
      nowOverride: DateTime(2026, 7, 27),
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'sara123');

    expect(find.text("Code accepted — Sara's referral"), findsOneWidget);
    expect(
        find.textContaining("Welcome back! This promo is for first-time "
            "players"),
        findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    final outcome = formKey.currentState!.value[kInsiderPromoAnswerKey]
        as InsiderPromoOutcome?;
    expect(outcome, isNotNull);
    expect(outcome!.firstTimer, isFalse);
    expect(outcome.discountSource, '');
    expect(outcome.discountPct, isNull);
  });

  testWidgets(
      'a valid code with the promo OFF stamps the code + FirstTimer with no '
      'discount and no friendly/discount line', (tester) async {
    await tester.pumpWidget(wrap(InsiderPromoCodeField(
      eligibleFee: 60,
      promo: const RegPromo(enabled: false, percent: 15),
      priorSubmissions: const [],
      myEmail: 'new@example.com',
      myPhone: '4085551212',
      lookupCodeOverride: (_) async => 'owner1',
      insiderStatusOverride: (_) async => 'active',
      alreadyReferredOverride: (_) async => false,
      insiderNameOverride: (_) async => 'Sara',
      myUidOverride: 'me',
      nowOverride: DateTime(2026, 7, 27),
    )));
    await tester.pump();

    await enterAndSubmitCode(tester, 'sara123');

    expect(find.text("Code accepted — Sara's referral"), findsOneWidget);
    expect(find.textContaining('Welcome back!'), findsNothing);
    expect(find.textContaining('discount will be applied'), findsNothing);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    final outcome = formKey.currentState!.value[kInsiderPromoAnswerKey]
        as InsiderPromoOutcome?;
    expect(outcome, isNotNull);
    expect(outcome!.firstTimer, isTrue);
    expect(outcome.discountSource, '');
  });
}
