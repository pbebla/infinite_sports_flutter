// Fresh reads, Task 3 — registration (survey list A #1, #2, #3, #5): money
// decisions never act on the phone's saved copy or on a failed read.
// Firebase-free: serverFirstValue is answered through
// FreshReads.serverFirstValueOverride, the uid through
// RegistrationService.uidOverride.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

const _openConfig = {
  'TargetType': 'league',
  'Sport': 'Futsal',
  'Season': '16',
  'Status': 'open',
  'Fee': 60,
};

void main() {
  /// path → the answer serverFirstValue gives (a throw = a failed read).
  late Map<String, FreshValue Function()> answers;

  setUp(() {
    answers = {};
    FreshReads.serverFirstValueOverride = (path) async {
      final a = answers[path];
      if (a == null) throw StateError('unexpected read of $path');
      return a();
    };
    RegistrationService.uidOverride = () => 'u1';
  });

  tearDown(() {
    FreshReads.serverFirstValueOverride = null;
    RegistrationService.uidOverride = null;
  });

  group('registrationRoute', () {
    final open = RegistrationConfig.fromFirebase(_openConfig);

    test('an unconfirmed config (old fee / closed?) is "couldn\'t check"', () {
      expect(
          registrationRoute(
              configChecked: false,
              config: open,
              submissionExists: false,
              submissionChecked: true),
          RegistrationRoute.couldNotCheck);
    });

    test('a confirmed closed registration is closed', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: null,
              submissionExists: false,
              submissionChecked: true),
          RegistrationRoute.closed);
    });

    test('an existing submission opens the status page', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: open,
              submissionExists: true,
              submissionChecked: true),
          RegistrationRoute.status);
    });

    test(
        'a stale "not registered" never sends a registered fan back into '
        'the form', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: open,
              submissionExists: false,
              submissionChecked: false),
          RegistrationRoute.couldNotCheck);
    });

    test('the server saying "none" opens the form', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: open,
              submissionExists: false,
              submissionChecked: true),
          RegistrationRoute.register);
    });
  });

  group('checkOpenRegistration (#72)', () {
    test('the server\'s config is checked', () async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: true);
      final r = await RegistrationService.checkOpenRegistration('r1');
      expect(r.checked, isTrue);
      expect(r.config!.fee, 60);
    });

    test('the saved copy is not checked', () async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: false);
      final r = await RegistrationService.checkOpenRegistration('r1');
      expect(r.checked, isFalse);
    });

    test('a failed read is not "closed"', () async {
      answers['RegistrationsPublic/r1'] = () => throw StateError('offline');
      final r = await RegistrationService.checkOpenRegistration('r1');
      expect(r.checked, isFalse);
    });
  });

  group('checkMySubmission (#74)', () {
    const path = 'Registrations/r1/Submissions/u1';

    test('an existing submission is a fact from any source', () async {
      answers[path] = () => const FreshValue(
          {'Path': 'individual', 'Paid': true},
          fromServer: false);
      final r = await RegistrationService.checkMySubmission('r1');
      expect(r.exists, isTrue);
      expect(r.checked, isTrue);
      expect(r.submission!.paid, isTrue);
    });

    test('a malformed node still counts as registered', () async {
      answers[path] = () => const FreshValue('junk', fromServer: true);
      final r = await RegistrationService.checkMySubmission('r1');
      expect(r.exists, isTrue);
    });

    test('"none" from the saved copy is not checked', () async {
      answers[path] = () => const FreshValue(null, fromServer: false);
      final r = await RegistrationService.checkMySubmission('r1');
      expect(r.exists, isFalse);
      expect(r.checked, isFalse);
    });

    test('"none" from the server is checked', () async {
      answers[path] = () => const FreshValue(null, fromServer: true);
      final r = await RegistrationService.checkMySubmission('r1');
      expect(r.checked, isTrue);
      expect(r.exists, isFalse);
    });

    test('a failed read is not "none"', () async {
      answers[path] = () => throw StateError('permission-denied');
      final r = await RegistrationService.checkMySubmission('r1');
      expect(r.checked, isFalse);
    });
  });

  group('guardNewSubmission (#74: a submit never overwrites)', () {
    const path = 'Registrations/r1/Submissions/u1';

    test('an existing (paid) submission refuses the write', () async {
      answers[path] = () => const FreshValue(
          {'Path': 'individual', 'Paid': true},
          fromServer: true);
      expect(await RegistrationService.guardNewSubmission('r1', 'u1'),
          SubmitOutcome.alreadyRegistered);
    });

    test('an existing submission in the saved copy refuses too', () async {
      answers[path] = () => const FreshValue(
          {'Path': 'individual', 'Paid': false},
          fromServer: false);
      expect(await RegistrationService.guardNewSubmission('r1', 'u1'),
          SubmitOutcome.alreadyRegistered);
    });

    test('"none" not confirmed by the server refuses', () async {
      answers[path] = () => const FreshValue(null, fromServer: false);
      expect(await RegistrationService.guardNewSubmission('r1', 'u1'),
          SubmitOutcome.couldNotCheck);
    });

    test('a failed read refuses', () async {
      answers[path] = () => throw StateError('offline');
      expect(await RegistrationService.guardNewSubmission('r1', 'u1'),
          SubmitOutcome.couldNotCheck);
    });

    test('"none" from the server lets the write go ahead', () async {
      answers[path] = () => const FreshValue(null, fromServer: true);
      expect(await RegistrationService.guardNewSubmission('r1', 'u1'),
          SubmitOutcome.ok);
    });
  });

  group('getPromo (#76)', () {
    const path = 'Registrations/r1/Promo';

    test('the server\'s promo is checked', () async {
      answers[path] = () =>
          const FreshValue({'Enabled': true, 'Percent': 20}, fromServer: true);
      final r = await RegistrationService.getPromo('r1');
      expect(r.checked, isTrue);
    });

    test('a saved-copy promo is not checked', () async {
      answers[path] = () =>
          const FreshValue({'Enabled': true, 'Percent': 20}, fromServer: false);
      expect((await RegistrationService.getPromo('r1')).checked, isFalse);
    });

    test('a failed read is not checked and disabled', () async {
      answers[path] = () => throw StateError('offline');
      final r = await RegistrationService.getPromo('r1');
      expect(r.checked, isFalse);
      expect(r.promo.enabled, isFalse);
    });
  });

  group('Stripe publishable key (#71)', () {
    const stripeConfig = RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: 60,
      paymentMode: 'perPlayer',
      stripe: true,
    );
    const unpaid = RegSubmission(path: 'individual', answers: {});

    Widget payment() => MaterialApp(
          home: PaymentScreen(
            regId: 'r1',
            config: stripeConfig,
            amount: 60,
            submissionStream: Stream.value(unpaid),
          ),
        );

    testWidgets('a key the server confirmed shows the card button',
        (tester) async {
      answers['AppConfig/StripePublishableKey'] =
          () => const FreshValue('pk_test_new', fromServer: true);
      await tester.pumpWidget(payment());
      await tester.pumpAndSettle();
      expect(find.text('Pay with card'), findsOneWidget);
    });

    testWidgets(
        'a saved-copy key (maybe rotated) starts no card payment: the '
        'existing "unavailable" line', (tester) async {
      answers['AppConfig/StripePublishableKey'] =
          () => const FreshValue('pk_test_old', fromServer: false);
      await tester.pumpWidget(payment());
      await tester.pumpAndSettle();
      expect(find.text('Pay with card'), findsNothing);
      expect(find.text('Card payments unavailable right now.'), findsOneWidget);
    });
  });
}
