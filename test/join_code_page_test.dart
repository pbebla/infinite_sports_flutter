// Widget tests for the joiner-path code entry page
// (lib/registration/join_code_page.dart) after lockdown B4 moved the match
// server-side. Firebase-free: `resolveOverride` replaces the real
// resolveJoinCode callable round trip (mirrors the injectable-override
// seams in insider_promo_field.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/registration/join_code_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

const RegistrationConfig _config = RegistrationConfig(
  targetType: 'league',
  sport: 'Futsal',
  season: '17',
  status: 'open',
  fee: 60,
);

JoinCodePage _page(
    Future<JoinCodeMatch> Function({required String regId, required String code})
        resolve) {
  return JoinCodePage(
      regId: 'Futsal-17', config: _config, resolveOverride: resolve);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextFormField), code);
  // Let the 350ms lookup debounce elapse, then the async resolve + its
  // setState land. Fixed pumps, not pumpAndSettle — PinCodeTextField runs
  // a persistent cursor animation that never settles.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('an approved code shows "Joining {team}" + Continue',
      (tester) async {
    String? resolvedCode;
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async {
      resolvedCode = code;
      return const JoinCodeMatch(
          'ok',
          RegTeam(
              id: 't1',
              name: 'The Boys',
              captainUid: '',
              status: 'approved',
              codeWaivesPayment: true));
    })));

    await _enterCode(tester, 'ABC234');

    expect(resolvedCode, 'ABC234');
    expect(find.text('Joining The Boys'), findsOneWidget);
    expect(find.textContaining('no payment needed'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets("a pending team's code shows the awaiting-approval message",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async =>
            const JoinCodeMatch('notApproved'))));

    await _enterCode(tester, 'ABC234');

    expect(
        find.text(
            'That team is still awaiting approval — ask your captain to check back soon.'),
        findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('an unknown 6-char code shows the no-match error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async =>
            const JoinCodeMatch('notFound'))));

    await _enterCode(tester, 'ZZZ999');

    expect(
        find.text("That code doesn't match any team in this registration."),
        findsOneWidget);
  });

  testWidgets(
      'a lookup that FAILS says it could not check, never "no match"',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async =>
            const JoinCodeMatch('error'))));

    await _enterCode(tester, 'ABC234');

    expect(
        find.text(
            "Couldn't check the code. Check your connection and try again."),
        findsOneWidget);
    expect(find.textContaining("doesn't match"), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('short partial input stays quiet (no error, no lookup spam)',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async {
      calls++;
      return const JoinCodeMatch('notFound');
    })));

    await _enterCode(tester, 'AB'); // below the 4-char code minimum

    expect(calls, 0);
    expect(find.textContaining("doesn't match"), findsNothing);
    expect(find.textContaining('awaiting approval'), findsNothing);
  });

  testWidgets('an admin-edited 4-char code still matches', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: _page(({required regId, required code}) async => code == 'AB23'
            ? const JoinCodeMatch(
                'ok',
                RegTeam(
                    id: 't2',
                    name: 'Short Coders',
                    captainUid: '',
                    status: 'approved'))
            : const JoinCodeMatch('notFound'))));

    await _enterCode(tester, 'AB23');

    expect(find.text('Joining Short Coders'), findsOneWidget);
    // Not waived: the player-fee line renders instead.
    expect(find.textContaining('player fee after registering'),
        findsOneWidget);
  });
}
