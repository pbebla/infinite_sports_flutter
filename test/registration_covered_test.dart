// "Owes money" must come from the SAME discounted total the payment screen
// shows (bestDiscountedTotal) — a registrant the admin comped to $0, or with
// a 100% discount, is covered, not "Payment pending". Firebase-free via the
// status page / payment screen stream seams.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

const RegistrationConfig _config = RegistrationConfig(
  targetType: 'league',
  sport: 'Futsal',
  season: '17',
  status: 'open',
  fee: 60,
  paymentMode: 'perPlayer',
  venmo: true,
  zelle: true,
);

const RegSubmission _unpaid =
    RegSubmission(path: 'individual', answers: {}, paid: false);

const RegSubmission _comped = RegSubmission(
    path: 'individual',
    answers: {},
    paid: false,
    adjustedFee: 0,
    discountSource: 'manual');

const RegSubmission _fullPromo = RegSubmission(
    path: 'individual',
    answers: {},
    paid: false,
    discountPct: 100,
    eligibleFee: 60,
    discountSource: 'first_timer_promo');

Widget _status(Stream<RegSubmission?> stream) => MaterialApp(
      home: RegistrationStatusPage(
        regId: 'Futsal-17',
        config: _config,
        submissionStream: stream,
        formFuture: Future.value(const <RegQuestion>[]),
      ),
    );

Widget _payment(Stream<RegSubmission?> stream,
        {Future<void> Function()? card, RegistrationConfig config = _config}) =>
    MaterialApp(
      home: PaymentScreen(
        regId: 'Futsal-17',
        config: config,
        amount: 60,
        submissionStream: stream,
        publishableKeyOverride: 'pk_test_x',
        cardPaymentOverride: card,
      ),
    );

void main() {
  group('discountedAmountOwed / paymentCovered', () {
    test('a normal unpaid registration owes the full fee', () {
      expect(discountedAmountOwed(config: _config, submission: _unpaid), 60);
      expect(paymentCovered(config: _config, submission: _unpaid), isFalse);
    });

    test('an admin comp to \$0 owes nothing and is covered', () {
      expect(discountedAmountOwed(config: _config, submission: _comped), 0);
      expect(paymentCovered(config: _config, submission: _comped), isTrue);
    });

    test('a 100% promo owes nothing and is covered', () {
      expect(discountedAmountOwed(config: _config, submission: _fullPromo), 0);
      expect(paymentCovered(config: _config, submission: _fullPromo), isTrue);
    });

    test('a partial discount still owes the discounted amount', () {
      const sub = RegSubmission(
          path: 'individual',
          answers: {},
          discountPct: 25,
          eligibleFee: 60,
          discountSource: 'insider_tier');
      expect(discountedAmountOwed(config: _config, submission: sub), 45);
      expect(paymentCovered(config: _config, submission: sub), isFalse);
    });

    test('nothing owed at all (paid / waived) is not "covered" and owes 0',
        () {
      const paid = RegSubmission(path: 'individual', answers: {}, paid: true);
      expect(discountedAmountOwed(config: _config, submission: paid), 0);
      expect(paymentCovered(config: _config, submission: paid), isFalse);
      // A stale adjustment on a submission that owes nothing never invents
      // a debt.
      const teamFeeOnly = RegistrationConfig(
          targetType: 'league',
          sport: 'Futsal',
          season: '17',
          fee: 60,
          paymentMode: 'teamFee');
      const adjusted = RegSubmission(
          path: 'individual',
          answers: {},
          adjustedFee: 30,
          discountSource: 'manual');
      expect(
          discountedAmountOwed(config: teamFeeOnly, submission: adjusted), 0);
    });
  });

  group('status page', () {
    testWidgets('a normal unpaid registration looks exactly as before',
        (tester) async {
      await tester.pumpWidget(_status(Stream.value(_unpaid)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Payment pending'), findsOneWidget);
      expect(find.text('Complete payment'), findsOneWidget);
      expect(find.textContaining("you're covered"), findsNothing);
    });

    testWidgets('a comped registration is covered: no pending, no button',
        (tester) async {
      await tester.pumpWidget(_status(Stream.value(_comped)));
      await tester.pump();
      await tester.pump();
      expect(find.text("Nothing to pay — you're covered"), findsOneWidget);
      expect(find.text('Payment pending'), findsNothing);
      expect(find.text('Complete payment'), findsNothing);
    });

    testWidgets('a 100% promo is covered too', (tester) async {
      await tester.pumpWidget(_status(Stream.value(_fullPromo)));
      await tester.pump();
      await tester.pump();
      expect(find.text("Nothing to pay — you're covered"), findsOneWidget);
      expect(find.text('Complete payment'), findsNothing);
    });

    testWidgets(
        'a FAILED read of my registration says so — never "No registration '
        'found"', (tester) async {
      await tester.pumpWidget(_status(
          Stream<RegSubmission?>.error(Exception('permission-denied'))));
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load your registration. Try again."),
          findsOneWidget);
      expect(find.text('No registration found for your account.'),
          findsNothing);
      expect(find.text('Complete payment'), findsNothing);
    });

    testWidgets('a genuinely missing registration still says none found',
        (tester) async {
      await tester.pumpWidget(_status(Stream<RegSubmission?>.value(null)));
      await tester.pump();
      await tester.pump();
      expect(find.text('No registration found for your account.'),
          findsOneWidget);
    });
  });

  group('payment screen', () {
    testWidgets('a normal unpaid registration shows the pay options',
        (tester) async {
      await tester.pumpWidget(_payment(Stream.value(_unpaid)));
      await tester.pump();
      expect(find.text('\$60'), findsOneWidget);
      expect(find.text('Pay with Venmo'), findsOneWidget);
      expect(find.text('Zelle'), findsOneWidget);
      expect(find.textContaining("you're covered"), findsNothing);
    });

    testWidgets('a \$0 total shows no pay buttons at all', (tester) async {
      await tester.pumpWidget(_payment(Stream.value(_comped),
          config: const RegistrationConfig(
              targetType: 'league',
              sport: 'Futsal',
              season: '17',
              fee: 60,
              paymentMode: 'perPlayer',
              venmo: true,
              zelle: true,
              stripe: true)));
      await tester.pump();
      expect(find.text("Nothing to pay — you're covered"), findsOneWidget);
      expect(find.text('Pay with Venmo'), findsNothing);
      expect(find.text('Pay with card'), findsNothing);
      expect(find.text('Zelle'), findsNothing);
      expect(find.text('View my registration'), findsOneWidget);
    });

    testWidgets(
        'a FAILED submission read shows an error, not the undiscounted fee',
        (tester) async {
      await tester.pumpWidget(_payment(
          Stream<RegSubmission?>.error(Exception('permission-denied'))));
      await tester.pump();
      expect(find.text("Couldn't load your registration. Try again."),
          findsOneWidget);
      expect(find.text('\$60'), findsNothing);
      expect(find.text('Pay with Venmo'), findsNothing);
    });
  });

  group('card payment (item 7)', () {
    const stripeConfig = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 60,
        paymentMode: 'perPlayer',
        stripe: true);

    test('already-paid refusal maps to a plain sentence', () {
      expect(
          cardPaymentErrorMessage(FirebaseFunctionsException(
              code: 'failed-precondition', message: 'Already paid.')),
          'This registration is already paid.');
    });

    test('anything else is the generic line, never raw text', () {
      final msg = cardPaymentErrorMessage(FirebaseFunctionsException(
          code: 'unavailable', message: 'internal blah'));
      expect(msg, "Card payment couldn't be started. Try again.");
      expect(cardPaymentErrorMessage(Exception('No client secret returned.')),
          "Card payment couldn't be started. Try again.");
    });

    testWidgets('a failed start shows the plain sentence in the snackbar',
        (tester) async {
      await tester.pumpWidget(_payment(Stream.value(_unpaid),
          config: stripeConfig,
          card: () async => throw FirebaseFunctionsException(
              code: 'failed-precondition', message: 'Already paid.')));
      await tester.pump();
      await tester.tap(find.text('Pay with card'));
      await tester.pump();
      await tester.pump();
      expect(find.text('This registration is already paid.'), findsOneWidget);
      expect(find.textContaining('firebase_functions'), findsNothing);
    });

    testWidgets(
        'no Paid confirmation within 60s: "went through" message, no pay '
        'buttons', (tester) async {
      final subs = StreamController<RegSubmission?>();
      addTearDown(subs.close);
      await tester.pumpWidget(_payment(subs.stream,
          config: stripeConfig, card: () async {}));
      subs.add(_unpaid);
      await tester.pump();
      await tester.tap(find.text('Pay with card'));
      await tester.pump();
      expect(find.text('Processing…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Processing…'), findsNothing);
      expect(
          find.text('Your payment went through. It can take a few minutes '
              "to show here — you don't need to pay again."),
          findsOneWidget);
      expect(find.text('Pay with card'), findsNothing);

      // A later re-emission of the unpaid node must not bring the card
      // button back.
      subs.add(_unpaid);
      await tester.pump();
      expect(find.text('Pay with card'), findsNothing);

      // And the Paid flip still wins.
      subs.add(const RegSubmission(
          path: 'individual', answers: {}, paid: true, paidVia: 'card'));
      await tester.pump();
      expect(find.text("Payment received — you're all set."), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // drain snackbars
    });
  });

  group('sub-cent balances round to whole cents everywhere', () {
    const fee255 = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 255,
        paymentMode: 'perPlayer',
        venmo: true,
        zelle: true,
        stripe: true);
    // 255 * (1 - 99.999/100) = 0.00255 -> rounds to $0.00.
    const tiny = RegSubmission(
        path: 'individual',
        answers: {},
        discountPct: 99.999,
        eligibleFee: 255,
        discountSource: 'manual');
    // adjustedFee 0.006 -> rounds to $0.01.
    const cent = RegSubmission(
        path: 'individual',
        answers: {},
        adjustedFee: 0.006,
        discountSource: 'manual');
    const plain = RegSubmission(path: 'individual', answers: {});

    Widget payment(RegSubmission sub) => MaterialApp(
          home: PaymentScreen(
            regId: 'Futsal-17',
            config: fee255,
            amount: 255,
            submissionStream: Stream.value(sub),
            publishableKeyOverride: 'pk_test_x',
          ),
        );
    Widget status(RegSubmission sub) => MaterialApp(
          home: RegistrationStatusPage(
            regId: 'Futsal-17',
            config: fee255,
            submissionStream: Stream.value(sub),
            formFuture: Future.value(const <RegQuestion>[]),
          ),
        );

    test('helpers agree on one rounded value', () {
      expect(discountedAmountOwed(config: fee255, submission: tiny), 0);
      expect(paymentCovered(config: fee255, submission: tiny), isTrue);
      expect(discountedAmountOwed(config: fee255, submission: cent), 0.01);
      expect(paymentCovered(config: fee255, submission: cent), isFalse);
      expect(discountedAmountOwed(config: fee255, submission: plain), 255);
      expect(roundToCents(0.00255), 0);
      expect(roundToCents(0.006), 0.01);
    });

    testWidgets('0.00255 is covered: status page has no pay button',
        (tester) async {
      await tester.pumpWidget(status(tiny));
      await tester.pump();
      await tester.pump();
      expect(find.text("Nothing to pay — you're covered"), findsOneWidget);
      expect(find.text('Complete payment'), findsNothing);
      expect(find.text('Payment pending'), findsNothing);
    });

    testWidgets('0.00255 is covered: payment screen has no pay buttons',
        (tester) async {
      await tester.pumpWidget(payment(tiny));
      await tester.pump();
      expect(find.text("Nothing to pay — you're covered"), findsOneWidget);
      expect(find.text('Pay with card'), findsNothing);
      expect(find.text('Pay with Venmo'), findsNothing);
    });

    testWidgets('0.006 owes \$0.01 on both screens', (tester) async {
      await tester.pumpWidget(status(cent));
      await tester.pump();
      await tester.pump();
      expect(find.text('Complete payment'), findsOneWidget);
      expect(find.textContaining("you're covered"), findsNothing);

      await tester.pumpWidget(payment(cent));
      await tester.pump();
      expect(find.text('\$0.01'), findsOneWidget);
      expect(find.text('Pay with card'), findsOneWidget);
      expect(find.textContaining("you're covered"), findsNothing);
    });

    testWidgets('an ordinary \$255 registration is unchanged', (tester) async {
      await tester.pumpWidget(status(plain));
      await tester.pump();
      await tester.pump();
      expect(find.text('Payment pending'), findsOneWidget);
      expect(find.text('Complete payment'), findsOneWidget);

      await tester.pumpWidget(payment(plain));
      await tester.pump();
      expect(find.text('\$255'), findsOneWidget);
      expect(find.text('Pay with card'), findsOneWidget);
    });
  });

  testWidgets('once Paid arrives, the processing timers stop',
      (tester) async {
    const stripeConfig = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 60,
        paymentMode: 'perPlayer',
        stripe: true);
    final subs = StreamController<RegSubmission?>();
    addTearDown(subs.close);
    await tester.pumpWidget(
        _payment(subs.stream, config: stripeConfig, card: () async {}));
    subs.add(_unpaid);
    await tester.pump();
    await tester.tap(find.text('Pay with card'));
    await tester.pump();
    expect(find.text('Processing…'), findsOneWidget);

    subs.add(const RegSubmission(
        path: 'individual', answers: {}, paid: true, paidVia: 'card'));
    await tester.pump();
    expect(find.text("Payment received — you're all set."), findsOneWidget);

    // Neither the 10s snackbar nor the 60s "went through" state may fire.
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.textContaining('Still processing'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(find.textContaining('Your payment went through'), findsNothing);
    expect(find.text("Payment received — you're all set."), findsOneWidget);
  });
}
