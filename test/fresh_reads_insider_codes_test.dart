// Fresh reads, Task 3 — Insider code checks (survey list A #4: #15
// InsiderCodes/<code>, #16 Insiders/<owner>/Status, #17 ReferredUsers/<me>).
// A revoked/suspended code must not discount on the phone's saved copy, a
// failed read must not say "Invalid code", and an already-referred fan must
// not get a second referral on a stale "not referred": an answer the server
// did not confirm is "couldn't check the code" and stamps nothing.

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/registration/insider_promo_field.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';

void main() {
  late Map<String, FreshValue Function()> answers;

  setUp(() {
    answers = {};
    FreshReads.serverFirstValueOverride = (path) async {
      final a = answers[path];
      if (a == null) throw StateError('unexpected read of $path');
      return a();
    };
  });

  tearDown(() => FreshReads.serverFirstValueOverride = null);

  group('InsiderService checks are server-first', () {
    test('lookupCode: the server\'s owner', () async {
      answers['InsiderCodes/SARA123'] =
          () => const FreshValue('owner1', fromServer: true);
      expect(await InsiderService.lookupCode('sara123'), 'owner1');
    });

    test('lookupCode: a real "no such code" from the server is null', () async {
      answers['InsiderCodes/NOSUCH1'] =
          () => const FreshValue(null, fromServer: true);
      expect(await InsiderService.lookupCode('NOSUCH1'), isNull);
    });

    test('lookupCode: a saved-copy owner (maybe revoked) cannot be checked',
        () async {
      answers['InsiderCodes/SARA123'] =
          () => const FreshValue('owner1', fromServer: false);
      expect(InsiderService.lookupCode('SARA123'),
          throwsA(isA<InsiderCheckUnavailable>()));
    });

    test('lookupCode: a failed read is not "invalid"', () async {
      answers['InsiderCodes/SARA123'] = () => throw StateError('offline');
      expect(InsiderService.lookupCode('SARA123'),
          throwsA(isA<InsiderCheckUnavailable>()));
    });

    test('insiderStatus: a saved-copy "active" cannot be checked', () async {
      answers['Insiders/owner1/Status'] =
          () => const FreshValue('active', fromServer: false);
      expect(InsiderService.insiderStatus('owner1'),
          throwsA(isA<InsiderCheckUnavailable>()));
      answers['Insiders/owner1/Status'] =
          () => const FreshValue('suspended', fromServer: true);
      expect(await InsiderService.insiderStatus('owner1'), 'suspended');
    });

    test('alreadyReferred: a stale or failed "not referred" cannot be checked',
        () async {
      answers['ReferredUsers/me'] =
          () => const FreshValue(null, fromServer: false);
      expect(InsiderService.alreadyReferred('me'),
          throwsA(isA<InsiderCheckUnavailable>()));
      answers['ReferredUsers/me'] = () => throw StateError('denied');
      expect(InsiderService.alreadyReferred('me'),
          throwsA(isA<InsiderCheckUnavailable>()));
      answers['ReferredUsers/me'] =
          () => const FreshValue({'InsiderUid': 'x'}, fromServer: true);
      expect(await InsiderService.alreadyReferred('me'), isTrue);
    });
  });

  group('the promo field', () {
    final formKey = GlobalKey<FormBuilderState>();

    Widget wrap(InsiderPromoCodeField field) => MaterialApp(
          home: Scaffold(
            body: FormBuilder(
              key: formKey,
              child: Column(children: [
                field,
                ElevatedButton(
                  onPressed: () => formKey.currentState?.saveAndValidate(),
                  child: const Text('Submit'),
                ),
              ]),
            ),
          ),
        );

    Future<void> enter(WidgetTester tester, String code) async {
      await tester.enterText(
          find.byKey(const ValueKey('insider_promo_code_field')), code);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }

    Never unavailable() => throw const InsiderCheckUnavailable();

    for (final which in ['code', 'status', 'referred']) {
      testWidgets(
          'an unconfirmed $which answer: "couldn\'t check the code", '
          'nothing stamped, the form cannot submit with it', (tester) async {
        await tester.pumpWidget(wrap(InsiderPromoCodeField(
          eligibleFee: 60,
          promo: const RegPromo(enabled: true, percent: 15),
          lookupCodeOverride: (_) async =>
              which == 'code' ? unavailable() : 'owner1',
          insiderStatusOverride: (_) async =>
              which == 'status' ? unavailable() : 'active',
          alreadyReferredOverride: (_) async =>
              which == 'referred' ? unavailable() : false,
          insiderNameOverride: (_) async => 'Sara',
          myUidOverride: 'me',
        )));
        await tester.pump();
        await enter(tester, 'SARA123');
        expect(find.text(kInsiderCodeCouldNotCheck), findsOneWidget);
        expect(find.textContaining('Code accepted'), findsNothing);
        expect(find.text('Invalid code'), findsNothing);
        expect(formKey.currentState!.validate(), isFalse);
      });
    }

    testWidgets('the same code is checked again on the next try',
        (tester) async {
      var online = false;
      await tester.pumpWidget(wrap(InsiderPromoCodeField(
        eligibleFee: 60,
        promo: const RegPromo(enabled: true, percent: 15),
        lookupCodeOverride: (_) async => online ? 'owner1' : unavailable(),
        insiderStatusOverride: (_) async => 'active',
        alreadyReferredOverride: (_) async => false,
        insiderNameOverride: (_) async => 'Sara',
        myUidOverride: 'me',
      )));
      await tester.pump();
      await enter(tester, 'SARA123');
      expect(find.text(kInsiderCodeCouldNotCheck), findsOneWidget);
      online = true;
      await enter(tester, 'SARA123');
      expect(find.textContaining('Code accepted'), findsOneWidget);
    });
  });

  // Task 4 (#14, OWN-WRITE treated as a decision): apply() writes only when
  // there is no application or it was declined. A pending/active/suspended
  // record counts from any source (never clobbered); "absent/declined" only
  // counts when the server said so.
  group('insiderApplyDecision (#14)', () {
    test('an existing application from any source: no write', () {
      for (final fromServer in [true, false]) {
        expect(
            insiderApplyDecision({'Status': 'pending'}, 'u1',
                fromServer: fromServer),
            InsiderApplyDecision.alreadyApplied);
      }
    });

    test('absent or declined from the server: write', () {
      expect(insiderApplyDecision(null, 'u1', fromServer: true),
          InsiderApplyDecision.write);
      expect(
          insiderApplyDecision({'Status': 'declined'}, 'u1', fromServer: true),
          InsiderApplyDecision.write);
    });

    test('absent or declined from the saved copy: could not check', () {
      expect(insiderApplyDecision(null, 'u1', fromServer: false),
          InsiderApplyDecision.couldNotCheck);
      expect(
          insiderApplyDecision({'Status': 'declined'}, 'u1',
              fromServer: false),
          InsiderApplyDecision.couldNotCheck);
    });
  });
}
