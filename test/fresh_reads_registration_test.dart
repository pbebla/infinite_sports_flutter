import 'dart:async';
import 'dart:io';

// Fresh reads, Task 3 — registration (survey list A #1, #2, #3, #5): money
// decisions never act on the phone's saved copy or on a failed read.
// Firebase-free: serverFirstValue is answered through
// FreshReads.serverFirstValueOverride, the uid through
// RegistrationService.uidOverride.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';
import 'package:infinite_sports_flutter/misc/utility.dart' show signedIn;
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

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

    final closed =
        RegistrationConfig.fromFirebase({..._openConfig, 'Status': 'closed'});

    test('way back: a closed registration with NO submission is closed', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: closed,
              submissionExists: false,
              submissionChecked: true),
          RegistrationRoute.closed);
    });

    test(
        'way back: a closed registration WITH a submission opens the status '
        'page (the fan can still see it and pay)', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: closed,
              submissionExists: true,
              submissionChecked: true),
          RegistrationRoute.status);
    });

    test(
        'way back: a removed registration is unavailable, with or without '
        'a submission', () {
      for (final exists in [true, false]) {
        expect(
            registrationRoute(
                configChecked: true,
                config: null,
                submissionExists: exists,
                submissionChecked: true),
            RegistrationRoute.unavailable);
      }
    });

    test(
        'way back: a closed registration whose "no submission" is not '
        'confirmed is couldn\'t-check, never closed as a guess', () {
      expect(
          registrationRoute(
              configChecked: true,
              config: closed,
              submissionExists: false,
              submissionChecked: false),
          RegistrationRoute.couldNotCheck);
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

  group('checkRegistration (#72, way back)', () {
    test('the server\'s config is checked', () async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: true);
      final r = await RegistrationService.checkRegistration('r1');
      expect(r.checked, isTrue);
      expect(r.config!.fee, 60);
    });

    test('a closed registration keeps its config (way back)', () async {
      answers['RegistrationsPublic/r1'] = () => FreshValue(
          {..._openConfig, 'Status': 'closed'},
          fromServer: true);
      final r = await RegistrationService.checkRegistration('r1');
      expect(r.checked, isTrue);
      expect(r.config!.isOpen, isFalse);
    });

    test('the saved copy is not checked', () async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(_openConfig, fromServer: false);
      final r = await RegistrationService.checkRegistration('r1');
      expect(r.checked, isFalse);
    });

    test('a failed read is not "closed"', () async {
      answers['RegistrationsPublic/r1'] = () => throw StateError('offline');
      final r = await RegistrationService.checkRegistration('r1');
      expect(r.checked, isFalse);
    });
  });

  group('checkEntry way back', () {
    test('closed + my submission -> status page with the config', () async {
      answers['RegistrationsPublic/r1'] = () => FreshValue(
          {..._openConfig, 'Status': 'closed'},
          fromServer: true);
      answers['Registrations/r1/Submissions/u1'] = () => const FreshValue(
          {'Path': 'individual', 'Paid': false},
          fromServer: true);
      final e = await RegistrationService.checkEntry('r1');
      expect(e.route, RegistrationRoute.status);
      expect(e.config!.isOpen, isFalse);
    });

    test('removed -> unavailable', () async {
      answers['RegistrationsPublic/r1'] =
          () => const FreshValue(null, fromServer: true);
      answers['Registrations/r1/Submissions/u1'] = () => const FreshValue(
          {'Path': 'individual', 'Paid': false},
          fromServer: true);
      final e = await RegistrationService.checkEntry('r1');
      expect(e.route, RegistrationRoute.unavailable);
      expect(e.config, isNull);
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
          configStream: Stream.value(stripeConfig),
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
          configStream: Stream.value(stripeConfig),
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

  // Second review, Minor 3: the "already registered" submit path opens the
  // status page at once; the status page runs the legacy repair itself
  // (not awaited). A source check: the form page has no harness.
  test('the form page never awaits the legacy repair', () {
    final src =
        File('lib/registration/registration_form_page.dart').readAsStringSync();
    expect(
        src.contains('await RegistrationService.repairLegacySignUp'), isFalse);
    final status = File('lib/registration/registration_status_page.dart')
        .readAsStringSync();
    expect(
        RegExp(r'unawaited\(\s*RegistrationService\.repairLegacySignUp')
            .hasMatch(status),
        isTrue);
  });

  // Second review, Important 2: the payment screen watches the registration's
  // config live; every amount follows the latest value.
  group('payment screen follows the live config', () {
    const base = RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: 60,
      paymentMode: 'perPlayer',
      venmo: true,
      stripe: true,
    );
    const unpaid = RegSubmission(path: 'individual', answers: {});

    Future<({StreamController<RegistrationConfig?> config, List<Uri> launched})>
        pump(WidgetTester tester) async {
      final config = StreamController<RegistrationConfig?>();
      final launched = <Uri>[];
      await tester.pumpWidget(MaterialApp(
        home: PaymentScreen(
          regId: 'r1',
          config: base,
          amount: 60,
          amountFor: (c) => amountOwed(config: c, submission: unpaid),
          submissionStream: Stream.value(unpaid),
          configStream: config.stream,
          launchOverride: (uri) async => launched.add(uri),
        ),
      ));
      await tester.pump();
      return (config: config, launched: launched);
    }

    testWidgets(
        'a fee change updates the amount and the Venmo link, with '
        'the notice', (tester) async {
      final h = await pump(tester);
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text(kRegistrationFeeChanged), findsNothing);
      h.config.add(base.copyWithForTest(fee: 75));
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$75'), findsOneWidget);
      expect(find.text(r'$60'), findsNothing);
      expect(find.text(kRegistrationFeeChanged), findsOneWidget);
      await tester.tap(find.text('Pay with Venmo'));
      await tester.pump();
      expect(h.launched.single.queryParameters['amount'], contains('75'));
      await h.config.close();
    });

    testWidgets(
        'a live read error: pay actions show could-not-check, last '
        'amount kept', (tester) async {
      final h = await pump(tester);
      h.config.addError(StateError('permission-denied'));
      await tester.pump();
      await tester.pump();
      expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
      expect(find.text('Pay with card'), findsNothing);
      expect(find.text('Pay with Venmo'), findsNothing);
      expect(find.text(r'$60'), findsOneWidget);
      unawaited(h.config.close()); // the listener is gone after the error
    });

    testWidgets(
        'correction: closed (sign-ups closed) keeps the pay actions for '
        'an unpaid registrant, amounts still live', (tester) async {
      final h = await pump(tester);
      h.config.add(base.copyWithForTest(status: 'closed', fee: 70));
      await tester.pump();
      await tester.pump();
      expect(find.text('Registration is closed'), findsNothing);
      expect(find.text('Pay with card'), findsOneWidget);
      expect(find.text('Pay with Venmo'), findsOneWidget);
      expect(find.text(r'$70'), findsOneWidget);
      await tester.tap(find.text('Pay with Venmo'));
      await tester.pump();
      expect(h.launched.single.queryParameters['amount'], contains('70'));
      await h.config.close();
    });

    testWidgets(
        'correction: removed registration: no payable amount, the '
        'unavailable message', (tester) async {
      final h = await pump(tester);
      h.config.add(null);
      await tester.pump();
      await tester.pump();
      expect(find.text(kRegistrationUnavailable), findsOneWidget);
      expect(find.text('Pay with card'), findsNothing);
      expect(find.text('Pay with Venmo'), findsNothing);
      expect(find.text(r'$60'), findsNothing);
      await h.config.close();
    });

    testWidgets('correction: open stays as it was', (tester) async {
      final h = await pump(tester);
      h.config.add(base);
      await tester.pump();
      await tester.pump();
      expect(find.text('Pay with card'), findsOneWidget);
      expect(find.text(r'$60'), findsOneWidget);
      expect(find.text(kRegistrationFeeChanged), findsNothing);
      await h.config.close();
    });
  });

  // Final round, item 3: after "Try again" the pay actions stay in the
  // couldn't-check state until a confirmed config event arrives.
  testWidgets("Try again keeps couldn't-check until a confirmed event",
      (tester) async {
    const config = RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: 60,
      paymentMode: 'perPlayer',
      venmo: true,
      stripe: true,
    );
    final live = StreamController<RegistrationConfig?>.broadcast();
    addTearDown(live.close);
    await tester.pumpWidget(MaterialApp(
      home: PaymentScreen(
        regId: 'r1',
        config: config,
        amount: 60,
        submissionStream:
            Stream.value(const RegSubmission(path: 'individual', answers: {})),
        configStream: live.stream,
      ),
    ));
    await tester.pump();
    live.addError(StateError('denied'));
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget,
        reason: 'nothing confirmed yet');
    expect(find.text('Pay with card'), findsNothing);
    expect(find.text('Pay with Venmo'), findsNothing);
    live.add(config);
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationCouldNotCheck), findsNothing);
    expect(find.text('Pay with card'), findsOneWidget);
  });

  // Final round, item 4: a removed registration shows only the unavailable
  // message — never the fee-changed notice above it.
  testWidgets('removed after a fee change: only the unavailable message',
      (tester) async {
    const config = RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: 60,
      paymentMode: 'perPlayer',
      venmo: true,
    );
    const sub = RegSubmission(path: 'individual', answers: {});
    final live = StreamController<RegistrationConfig?>();
    await tester.pumpWidget(MaterialApp(
      home: PaymentScreen(
        regId: 'r1',
        config: config,
        amount: 60,
        amountFor: (c) => amountOwed(config: c, submission: sub),
        submissionStream: Stream.value(sub),
        configStream: live.stream,
      ),
    ));
    await tester.pump();
    live.add(config.copyWithForTest(fee: 75));
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationFeeChanged), findsOneWidget);
    live.add(null);
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationUnavailable), findsOneWidget);
    expect(find.text(kRegistrationFeeChanged), findsNothing);
    await live.close();
  });

  group('status page follows the live config', _statusPageLiveConfigTests);
}

// Second review, Important 2: the status page follows the live config too.
void _statusPageLiveConfigTests() {
  const base = RegistrationConfig(
    targetType: 'league',
    sport: 'Futsal',
    season: '16',
    status: 'open',
    fee: 60,
    paymentMode: 'perPlayer',
    venmo: true,
  );
  const unpaid = RegSubmission(path: 'individual', answers: {});

  Future<StreamController<RegistrationConfig?>> pump(
      WidgetTester tester) async {
    final config = StreamController<RegistrationConfig?>();
    await tester.pumpWidget(MaterialApp(
      home: RegistrationStatusPage(
        regId: 'r1',
        config: base,
        submissionStream: Stream.value(unpaid),
        formFuture: Future.value(const <RegQuestion>[]),
        configStream: config.stream,
      ),
    ));
    await tester.pump();
    await tester.pump();
    return config;
  }

  testWidgets(
      'status page: a fee change shows the notice; closed keeps Complete '
      'payment; removed shows the unavailable message', (tester) async {
    final config = await pump(tester);
    expect(find.text('Complete payment'), findsOneWidget);
    config.add(base.copyWithForTest(fee: 80));
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationFeeChanged), findsOneWidget);
    config.add(base.copyWithForTest(status: 'closed', fee: 80));
    await tester.pump();
    await tester.pump();
    expect(find.text('Complete payment'), findsOneWidget,
        reason: 'an unpaid registrant still pays after sign-ups close');
    expect(find.text('Registration is closed'), findsNothing);
    config.add(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Complete payment'), findsNothing);
    expect(find.text(kRegistrationUnavailable), findsOneWidget);
    await config.close();
  });

  testWidgets(
      'status page: a live read error shows could-not-check instead '
      'of Complete payment', (tester) async {
    final config = await pump(tester);
    config.addError(StateError('denied'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Complete payment'), findsNothing);
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    unawaited(config.close());
  });
}

extension on RegistrationConfig {
  RegistrationConfig copyWithForTest({num? fee, String? status}) =>
      RegistrationConfig(
        targetType: targetType,
        sport: sport,
        season: season,
        status: status ?? this.status,
        fee: fee ?? this.fee,
        paymentMode: paymentMode,
        venmo: venmo,
        stripe: stripe,
      );
}
