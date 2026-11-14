// Fresh reads, Task 3 — registration (survey list A #1, #2, #3, #5): money
// decisions never act on the phone's saved copy or on a failed read.
// Firebase-free: serverFirstValue is answered through
// FreshReads.serverFirstValueOverride, the uid through
// RegistrationService.uidOverride.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/utility.dart' show signedIn;
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
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

  // Review fix (Important 2): the card option is NOT gated on a key read —
  // the payment-intent callable returns the key and is the authority; a key
  // that cannot be obtained at tap time is the existing plain error, and the
  // button stays for a retry on the same screen.
  group('Stripe card button (#71, review Important 2)', () {
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

    testWidgets('shows at once, with no key read and no server wait',
        (tester) async {
      // answers is empty: any server-first read would throw.
      await tester.pumpWidget(MaterialApp(
        home: PaymentScreen(
          regId: 'r1',
          config: stripeConfig,
          amount: 60,
          submissionStream: Stream.value(unpaid),
        ),
      ));
      await tester.pump();
      expect(find.text('Pay with card'), findsOneWidget);
      expect(find.text('Card payments unavailable right now.'), findsNothing);
    });

    testWidgets(
        'a card start that fails shows the plain error and can be retried '
        'without leaving', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(MaterialApp(
        home: PaymentScreen(
          regId: 'r1',
          config: stripeConfig,
          amount: 60,
          submissionStream: Stream.value(unpaid),
          cardPaymentOverride: () async {
            attempts++;
            if (attempts == 1) {
              throw Exception('No Stripe publishable key configured.');
            }
          },
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Pay with card'));
      await tester.pumpAndSettle();
      expect(find.text("Card payment couldn't be started. Try again."),
          findsOneWidget);
      expect(find.text('Pay with card'), findsOneWidget);
      await tester.tap(find.text('Pay with card'));
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('Processing…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
    });

    test("the key: the callable's first, then the saved one, else none", () {
      expect(cardPublishableKey(fromCallable: 'pk_new', saved: 'pk_old'),
          'pk_new');
      expect(cardPublishableKey(fromCallable: '', saved: 'pk_old'), 'pk_old');
      expect(cardPublishableKey(fromCallable: null, saved: null), '');
    });
  });

  // Task 4 (entry-page fee): the live list's first answer can be the saved
  // copy, so the config that reaches the form/payment is re-read
  // server-first when the tile is tapped.
  group("entry page passes the server's config", () {
    final savedCopy =
        RegistrationConfig.fromFirebase({..._openConfig, 'Fee': 50})!;

    Widget page() => MaterialApp(
          home: RegistrationEntryPage(
            openRegistrationsOverride: Stream.value({'r1': savedCopy}),
          ),
        );

    setUp(() => signedIn = true);
    tearDown(() => signedIn = false);

    testWidgets("the server's fee goes on, not the list's saved copy",
        (tester) async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: true);
      answers['Registrations/r1/Submissions/u1'] =
          () => const FreshValue(null, fromServer: true);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.textContaining('\$50'), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      final path = tester
          .widget<RegistrationPathPage>(find.byType(RegistrationPathPage));
      expect(path.config.fee, 60);
    });

    testWidgets('an unconfirmed config: could not check, no entry',
        (tester) async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: false);
      answers['Registrations/r1/Submissions/u1'] =
          () => const FreshValue(null, fromServer: true);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
      expect(find.byType(RegistrationPathPage), findsNothing);
    });

    testWidgets('closed on the server: "Registration is closed"',
        (tester) async {
      answers['RegistrationsPublic/r1'] = () =>
          FreshValue({..._openConfig, 'Status': 'closed'}, fromServer: true);
      answers['Registrations/r1/Submissions/u1'] =
          () => const FreshValue(null, fromServer: true);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.text('Registration is closed'), findsOneWidget);
    });
  });

  // Review fix Important 1: every entry (event page Register, the list from
  // the banner / the drawer) goes through checkEntry, which hands on ONLY a
  // server-confirmed config.
  group('checkEntry (every way in)', () {
    void server(Object? config, {bool fromServer = true, Object? mine}) {
      answers['RegistrationsPublic/r1'] =
          () => FreshValue(config, fromServer: fromServer);
      answers['Registrations/r1/Submissions/u1'] =
          () => FreshValue(mine, fromServer: true);
    }

    test('register with the server config', () async {
      server(_openConfig);
      final e = await RegistrationService.checkEntry('r1');
      expect(e.route, RegistrationRoute.register);
      expect(e.config!.fee, 60);
    });

    test(
        'a returning (half-paid) fan gets the status page with the server '
        'config', () async {
      server(_openConfig, mine: {'Path': 'individual', 'Paid': false});
      final e = await RegistrationService.checkEntry('r1');
      expect(e.route, RegistrationRoute.status);
      expect(e.config!.fee, 60);
    });

    test('an unconfirmed config hands nothing on', () async {
      server(_openConfig, fromServer: false);
      final e = await RegistrationService.checkEntry('r1');
      expect(e.route, RegistrationRoute.couldNotCheck);
      expect(e.config, isNull);
    });

    test('the two reads run together (one bound offline)', () async {
      final started = <String>[];
      FreshReads.serverFirstValueOverride = (path) async {
        started.add(path);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const FreshValue(null, fromServer: true);
      };
      final sw = Stopwatch()..start();
      await RegistrationService.checkEntry('r1');
      expect(started, hasLength(2));
      expect(sw.elapsedMilliseconds, lessThan(38));
    });
  });

  // Review fix Minor 1: a submit whose legacy dual-write failed is completed
  // on the retry / status-page open.
  group('legacy sign-up repair', () {
    const sub = 'Registrations/r1/Submissions/u1';
    const notPaid = 'Sign Ups/Futsal/16/NotPaid/u1';
    const paid = 'Sign Ups/Futsal/16/Paid/u1';
    final config = RegistrationConfig.fromFirebase(_openConfig)!;
    late List<String> writes;

    setUp(() {
      writes = [];
      RegistrationService.legacyWriteOverride =
          (path, value) async => writes.add('$path=$value');
    });
    tearDown(() => RegistrationService.legacyWriteOverride = null);

    void server(Object? submission,
        {Object? np, Object? p, bool fromServer = true}) {
      answers[sub] = () => FreshValue(submission, fromServer: fromServer);
      answers[notPaid] = () => FreshValue(np, fromServer: true);
      answers[paid] = () => FreshValue(p, fromServer: true);
    }

    test('a missing NotPaid entry for an unpaid submission is written',
        () async {
      server({'Path': 'individual', 'Paid': false});
      await RegistrationService.repairLegacySignUp('r1', config,
          displayName: 'Sam');
      expect(writes, ['$notPaid=Sam']);
    });

    test('an existing entry (either bucket) means nothing to do', () async {
      server({'Path': 'individual', 'Paid': false}, np: 'Sam');
      await RegistrationService.repairLegacySignUp('r1', config,
          displayName: 'Sam');
      server({'Path': 'individual', 'Paid': false}, p: 'Sam');
      await RegistrationService.repairLegacySignUp('r1', config,
          displayName: 'Sam');
      expect(writes, isEmpty);
    });

    test('never on an unconfirmed read', () async {
      server({'Path': 'individual', 'Paid': false}, fromServer: false);
      await RegistrationService.repairLegacySignUp('r1', config,
          displayName: 'Sam');
      expect(writes, isEmpty);
    });

    test('bucket rule', () {
      const unpaid = RegSubmission(path: 'individual', answers: {});
      const waived = RegSubmission(
          path: 'joiner', answers: {}, paid: true, paidVia: 'team code');
      const managerPaid = RegSubmission(
          path: 'individual', answers: {}, paid: true, paidVia: 'venmo');
      expect(
          legacyRepairBucket(
              submission: unpaid, notPaidExists: false, paidExists: false),
          'NotPaid');
      expect(
          legacyRepairBucket(
              submission: waived, notPaidExists: false, paidExists: false),
          'Paid');
      expect(
          legacyRepairBucket(
              submission: managerPaid, notPaidExists: false, paidExists: false),
          isNull);
      expect(
          legacyRepairBucket(
              submission: null, notPaidExists: false, paidExists: false),
          isNull);
    });
  });
}
