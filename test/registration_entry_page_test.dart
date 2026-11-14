// "My registration" way back: the registration list (home banner / drawer)
// shows "My registrations" first — every existing registration the fan has
// a submission in, open OR closed, with a Paid / "You owe $X" chip computed
// through the one discountedAmountOwed path — then "Open for sign-up".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/utility.dart' show signedIn;
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_open.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

RegistrationConfig _config(String sport, String status, {num fee = 60}) =>
    RegistrationConfig(
      targetType: 'league',
      sport: sport,
      season: '16',
      status: status,
      fee: fee,
      paymentMode: 'perPlayer',
    );

const _promoUnpaid = RegSubmission(
    path: 'individual',
    answers: {},
    discountPct: 10,
    eligibleFee: 60,
    discountSource: 'first_timer_promo');

void main() {
  setUp(() => signedIn = true);
  tearDown(() => signedIn = false);

  final closedMine = _config('Futsal', 'closed');
  final paidMine = _config('Basketball', 'open');
  final openOther = _config('Flag Football', 'open');

  MyRegistrations data() => MyRegistrations(mine: [
        MyRegistration(
            regId: 'futsal', config: closedMine, submission: _promoUnpaid),
        MyRegistration(
            regId: 'basket',
            config: paidMine,
            submission:
                const RegSubmission(path: 'captain', answers: {}, paid: true)),
      ], openForSignUp: {
        'flag': openOther
      });

  Future<List<String>> pump(WidgetTester tester, Stream<MyRegistrations> s,
      {ThemeMode mode = ThemeMode.light}) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    // The real tap path: RegistrationOpen.open -> the (seamed) server check
    // -> the (seamed) status page. Only what the CHECK returns can open it.
    RegistrationOpen.checkOverride = (regId) async {
      opened.add('checked:$regId');
      return (route: RegistrationRoute.status, config: closedMine);
    };
    RegistrationOpen.statusPageOverride = (regId, config) {
      opened.add('status:$regId');
      return const Scaffold(body: Text('status page'));
    };
    addTearDown(() {
      RegistrationOpen.checkOverride = null;
      RegistrationOpen.statusPageOverride = null;
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: mode,
      home: RegistrationEntryPage(
        registrationsOverride: () => s,
      ),
    ));
    await tester.pump();
    return opened;
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        '${mode.name} 360 px: my registrations first, then open for '
        'sign-up', (tester) async {
      await pump(tester, Stream.value(data()), mode: mode);
      expect(tester.takeException(), isNull);
      final mineHeader = tester.getTopLeft(find.text('My registrations'));
      final openHeader = tester.getTopLeft(find.text('Open for sign-up'));
      expect(mineHeader.dy, lessThan(openHeader.dy));
      expect(find.text(closedMine.label), findsOneWidget,
          reason: 'a CLOSED registration of mine is listed');
      expect(find.text('Registered as: Individual'), findsOneWidget);
      expect(find.text('Registered as: Team captain'), findsOneWidget);
      expect(find.text(openOther.label), findsOneWidget);
    });
  }

  testWidgets('the owed chip is the status page\'s amount; paid shows Paid',
      (tester) async {
    await pump(tester, Stream.value(data()));
    final owed =
        discountedAmountOwed(config: closedMine, submission: _promoUnpaid);
    expect(owed, 54);
    expect(find.text('You owe ${formatOwed(owed)}'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets(
      'tapping my registration checks with the server first, then '
      'opens its status page', (tester) async {
    final opened = await pump(tester, Stream.value(data()));
    await tester.tap(find.text(closedMine.label));
    await tester.pumpAndSettle();
    expect(opened, ['checked:futsal', 'status:futsal']);
  });

  testWidgets(
      'a check that cannot reach the server never opens the status '
      'page', (tester) async {
    final opened = await pump(tester, Stream.value(data()));
    RegistrationOpen.checkOverride = (regId) async {
      opened.add('checked:$regId');
      return (route: RegistrationRoute.couldNotCheck, config: null);
    };
    await tester.tap(find.text(closedMine.label));
    await tester.pumpAndSettle();
    expect(opened, ['checked:futsal']);
    expect(find.text(kRegistrationCouldNotCheck), findsOneWidget);
  });

  testWidgets('one loading state, then the list (no pop-in)', (tester) async {
    final c = StreamController<MyRegistrations>();
    await pump(tester, c.stream);
    expect(find.text('My registrations'), findsNothing);
    c.add(data());
    await tester.pump();
    expect(find.text('My registrations'), findsOneWidget);
    await c.close();
  });

  testWidgets('a failed read is couldn\'t-load with retry', (tester) async {
    var attempts = 0;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: RegistrationEntryPage(
        registrationsOverride: () {
          attempts++;
          return attempts == 1
              ? Stream<MyRegistrations>.error(StateError('denied'))
              : Stream.value(data());
        },
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text(kRegistrationsCouldNotLoad), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('My registrations'), findsOneWidget);
  });

  testWidgets('nothing at all: today\'s empty message', (tester) async {
    await pump(tester, Stream.value(MyRegistrations.empty));
    expect(find.text('No registrations are open right now.'), findsOneWidget);
  });

  testWidgets(
      'no first answer in time: could-not-load, and a late answer then '
      'replaces it in place (still listening)', (tester) async {
    final c = StreamController<MyRegistrations>();
    await pump(tester, c.stream);
    c.addError(TimeoutException('no answer'));
    await tester.pump();
    expect(find.text(kRegistrationsCouldNotLoad), findsOneWidget);
    c.add(data());
    await tester.pump();
    expect(find.text(kRegistrationsCouldNotLoad), findsNothing);
    expect(find.text('My registrations'), findsOneWidget);
    await c.close();
  });
}
