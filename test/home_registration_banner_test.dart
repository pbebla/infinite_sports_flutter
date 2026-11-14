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

  MyRegistrations mine({required bool paid}) => MyRegistrations(mine: [
        MyRegistration(
            regId: 'futsal',
            config: closedOwing,
            submission: RegSubmission(
                path: 'individual', answers: const {}, paid: paid)),
      ], openForSignUp: const {});

  test('owing (closed registration) wins over an open registration', () {
    final b = homeRegistrationBanner(
        mine: mine(paid: false), open: {'basket': open17})!;
    expect(b.title, 'Finish your payment: ${closedOwing.label}');
    expect(b.subtitle, 'You owe ${formatOwed(80)} — tap to pay');
    expect(b.owing!.regId, 'futsal');
  });

  test('paid up: today\'s banner', () {
    final b = homeRegistrationBanner(
        mine: mine(paid: true), open: {'basket': open17})!;
    expect(b.title, 'Registration open: ${open17.label}');
    expect(b.subtitle, 'Tap to sign up');
    expect(b.owing, isNull);
  });

  test('two open registrations: today\'s plural banner', () {
    final b = homeRegistrationBanner(
        mine: null, open: {'a': open17, 'b': _config('Futsal', 'open')})!;
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
      final b =
          homeRegistrationBanner(mine: mine(paid: false), open: const {})!;
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
}
