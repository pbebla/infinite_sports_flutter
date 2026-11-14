import 'dart:async';

// "My registration" way back: the home banner. A registration the fan still
// owes money on (open OR closed) takes priority: "Finish your payment: …"
// with the amount, opening that status page. Otherwise today's banner.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/frontpage.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

RegistrationConfig _config(String sport, String status, {num fee = 60}) =>
    RegistrationConfig(
      targetType: 'league',
      sport: sport,
      season: '16',
      status: status,
      fee: fee,
      paymentMode: 'perPlayer',
    );

void main() {
  final closedOwing = _config('Futsal', 'closed', fee: 80);
  final open17 = _config('Basketball', 'open');

  MyRegistrations mine(
          {required bool paid,
          Map<String, RegistrationConfig> openForSignUp = const {}}) =>
      MyRegistrations(mine: [
        MyRegistration(
            regId: 'futsal',
            config: closedOwing,
            submission: RegSubmission(
                path: 'individual', answers: const {}, paid: paid)),
      ], openForSignUp: openForSignUp);

  test('owing (closed registration) wins over an open registration', () {
    final b = homeRegistrationBanner(
        seasonPointer: (_) => '16',
        mine: mine(paid: false),
        open: {'basket': open17})!;
    expect(b.title, 'Finish your payment: ${closedOwing.label}');
    expect(b.subtitle, 'You owe ${formatOwed(80)} — tap to pay');
    expect(b.owing!.regId, 'futsal');
  });

  test('paid up: today\'s banner', () {
    final b = homeRegistrationBanner(
        seasonPointer: (_) => '16',
        mine: mine(paid: true, openForSignUp: {'basket': open17}),
        open: {'basket': open17})!;
    expect(b.title, 'Registration open: ${open17.label}');
    expect(b.subtitle, 'Tap to sign up');
    expect(b.owing, isNull);
  });

  test('two open registrations: today\'s plural banner', () {
    final b = homeRegistrationBanner(
        seasonPointer: (_) => '16',
        mine: null,
        open: {'a': open17, 'b': _config('Futsal', 'open')})!;
    expect(b.title, 'Registrations are open');
  });

  test('nothing owed, nothing open: no banner', () {
    expect(
        homeRegistrationBanner(mine: mine(paid: true), open: const {}), isNull);
    expect(homeRegistrationBanner(mine: null, open: const {}), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('${mode.name} 360 px: the owing banner fits and taps',
        (tester) async {
      tester.view.physicalSize = const Size(360, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var tapped = 0;
      final b = homeRegistrationBanner(
          seasonPointer: (_) => '16', mine: mine(paid: false), open: const {})!;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: mode,
        home: Scaffold(
            body: HomeRegistrationBanner(banner: b, onTap: () => tapped++)),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text(b.title), findsOneWidget);
      expect(find.text(b.subtitle), findsOneWidget);
      await tester.tap(find.text(b.title));
      expect(tapped, 1);
    });
  }

  // Way back fix round, Important 3: the fan's registrations are part of the
  // home screen's first-paint wait (bounded at 3 s, skipped signed out), so
  // the banner is in the first painted frame instead of popping in.
  group('bannerDataWait', () {
    test('signed out: no wait at all', () async {
      final never = Completer<void>().future;
      final sw = Stopwatch()..start();
      await bannerDataWait(never, signedIn: false);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('an answer already there (saved copy): no extra wait', () async {
      final sw = Stopwatch()..start();
      await bannerDataWait(Future<void>.value(), signedIn: true);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('the first paint waits for an answer that arrives in time', () async {
      final first = Completer<void>();
      var done = false;
      final wait = bannerDataWait(first.future,
              signedIn: true, bound: const Duration(seconds: 1))
          .then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse, reason: 'holding the first paint for it');
      first.complete();
      await wait;
      expect(done, isTrue);
    });

    test('never answers: the home screen still paints after the bound',
        () async {
      final sw = Stopwatch()..start();
      await bannerDataWait(Completer<void>().future,
          signedIn: true, bound: const Duration(milliseconds: 40));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(35));
    });

    test('a failed read never blocks the first paint', () async {
      await bannerDataWait(Future<void>.error(StateError('denied')),
          signedIn: true);
    });

    test('the production bound is 3 s', () {
      expect(kBannerFirstPaintBound, const Duration(seconds: 3));
    });
  });

  test('fix round Important 4: an old owing registration never nags', () {
    // Futsal 16 closed, the league has moved to 17: silent.
    expect(
        homeRegistrationBanner(
            seasonPointer: (_) => '17',
            mine: mine(paid: false),
            open: const {}),
        isNull);
    // Pointer not known yet: silent (never nag on a guess).
    expect(
        homeRegistrationBanner(
            seasonPointer: (_) => null,
            mine: mine(paid: false),
            open: const {}),
        isNull);
  });

  // Way back fix round, Minor 3: once the fan's registrations are known, the
  // "Registration open" banner only offers what they have NOT registered for
  // (MyRegistrations.openForSignUp), never "Tap to sign up" for their own.
  group('the open banner skips registrations the fan already has', () {
    final futsalOpen = _config('Futsal', 'open');

    test('registered for the only open one: no "sign up" banner', () {
      final known = MyRegistrations(mine: [
        MyRegistration(
            regId: 'futsal',
            config: futsalOpen,
            submission: const RegSubmission(
                path: 'individual', answers: {}, paid: true)),
      ], openForSignUp: const {});
      expect(
          homeRegistrationBanner(
              seasonPointer: (_) => '16',
              mine: known,
              open: {'futsal': futsalOpen}),
          isNull);
    });

    test('registered for one of two: the singular banner for the other', () {
      final known = MyRegistrations(mine: [
        MyRegistration(
            regId: 'futsal',
            config: futsalOpen,
            submission: const RegSubmission(
                path: 'individual', answers: {}, paid: true)),
      ], openForSignUp: {
        'basket': open17
      });
      final b = homeRegistrationBanner(
          seasonPointer: (_) => '16',
          mine: known,
          open: {'futsal': futsalOpen, 'basket': open17})!;
      expect(b.title, 'Registration open: ${open17.label}');
    });

    test('registrations not known yet (signed out / loading): every open one',
        () {
      final b =
          homeRegistrationBanner(mine: null, open: {'futsal': futsalOpen})!;
      expect(b.title, 'Registration open: ${futsalOpen.label}');
    });
  });
}
