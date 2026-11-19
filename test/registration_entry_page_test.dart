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

  testWidgets(
      'fix round Minor 1: a free registration shows the status page chip '
      'chip (No charge), never a green Covered', (tester) async {
    final free = _config('Futsal', 'open', fee: 0);
    await pump(
        tester,
        Stream.value(MyRegistrations(mine: [
          MyRegistration(
              regId: 'free',
              config: free,
              submission: const RegSubmission(path: 'individual', answers: {})),
        ], openForSignUp: const {})));
    expect(find.text('No charge'), findsOneWidget);
    expect(find.text('Payment pending'), findsNothing);
    expect(find.text('Covered'), findsNothing);
  });

  // Way back fix round, Minor 4: the old sign-up page stays reachable from
  // the registration list (the drawer passes it when a legacy sign-up is
  // open and no new-style registration is).
  group('the old sign-up page', () {
    MyRegistrations onlyMine() => MyRegistrations(mine: [
          MyRegistration(
              regId: 'futsal', config: closedMine, submission: _promoUnpaid),
        ], openForSignUp: const {});

    Future<void> pumpLegacy(WidgetTester tester,
        {required ({String detail, WidgetBuilder page})? legacy,
        ThemeMode mode = ThemeMode.light}) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: mode,
        home: RegistrationEntryPage(
          registrationsOverride: () => Stream.value(onlyMine()),
          legacySignUp: legacy,
        ),
      ));
      await tester.pump();
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('${mode.name} 360 px: a Sign Up List row opens it',
          (tester) async {
        await pumpLegacy(tester, mode: mode, legacy: (
          detail: 'Sign Up for Futsal Season 17',
          page: (_) => const Scaffold(body: Text('old sign-up page')),
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('Sign Up List'), findsOneWidget);
        expect(find.text('Sign Up for Futsal Season 17'), findsOneWidget);
        expect(tester.getTopLeft(find.text(closedMine.label)).dy,
            lessThan(tester.getTopLeft(find.text('Sign Up List')).dy),
            reason: 'below my registrations');
        await tester.tap(find.text('Sign Up List'));
        await tester.pumpAndSettle();
        expect(find.text('old sign-up page'), findsOneWidget);
      });
    }

    testWidgets('not offered: no Sign Up List row', (tester) async {
      await pumpLegacy(tester, legacy: null);
      expect(find.text('Sign Up List'), findsNothing);
    });
  });

  // Final small round, N2: "Try again" on a row shows the row's spinner and
  // keeps the one-tap guard — a second tap meanwhile starts no second check
  // and only one status page opens.
  testWidgets('Try again keeps the spinner and the one-tap guard',
      (tester) async {
    final opened = await pump(tester, Stream.value(data()));
    final slow =
        Completer<({RegistrationRoute route, RegistrationConfig? config})>();
    var calls = 0;
    RegistrationOpen.checkOverride = (regId) {
      calls++;
      opened.add('checked:$regId');
      if (calls == 1) {
        return Future.value(
            (route: RegistrationRoute.couldNotCheck, config: null));
      }
      return slow.future;
    };
    await tester.tap(find.text(closedMine.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the retry shows the row spinner');
    await tester.tap(find.text(closedMine.label)); // impatient second tap
    await tester.pump();
    expect(calls, 2, reason: 'no second check while one runs');
    slow.complete((route: RegistrationRoute.status, config: closedMine));
    await tester.pumpAndSettle();
    expect(opened.where((o) => o.startsWith('status:')), ['status:futsal']);
  });

  // Final small round, N3: once the list has shown data, a later error
  // keeps the last good list (with a small "couldn't refresh" line); the
  // full "Couldn't load" only when nothing was ever shown.
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} 360 px: an error after data keeps the list',
        (tester) async {
      final c = StreamController<MyRegistrations>();
      addTearDown(c.close);
      await pump(tester, c.stream, mode: mode);
      c.add(data());
      await tester.pump();
      expect(find.text(closedMine.label), findsOneWidget);
      c.addError(StateError('later read failed'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(closedMine.label), findsOneWidget,
          reason: 'the last good list stays');
      expect(find.text(kRegistrationsCouldNotLoad), findsNothing);
      expect(find.text(kRegistrationsCouldNotRefresh), findsOneWidget);
      c.add(data()); // the stream recovers
      await tester.pump();
      expect(find.text(kRegistrationsCouldNotRefresh), findsNothing);
      expect(find.text(closedMine.label), findsOneWidget);
    });
  }
}
