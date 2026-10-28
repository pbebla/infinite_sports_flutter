// Widget tests for the Search hub's "Infinite Insiders" card (Task F6).
// Firebase-free: `insidersLeaderboardPageBuilder` is a test seam (mirrors
// insiders_info_page.dart's `dashboardPageBuilder`) so this test never
// constructs the real InsidersLeaderboardPage — which, unwrapped, reaches
// for InsiderService's live Firebase streams in its own default wiring.
//
// SearchHubPage's hub view (`_hub()`) renders unconditionally on the empty
// query, regardless of the FutureBuilder's search-index snapshot state, so
// no Firebase mocking is needed to see it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/search_hub_page.dart';

void main() {
  testWidgets('the hub shows an Infinite Insiders card alongside Around You',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchHubPage()));
    await tester.pump();

    expect(find.text('Around You'), findsOneWidget);
    expect(find.text('Infinite Insiders'), findsOneWidget);
  });

  testWidgets('tapping the Infinite Insiders card pushes the leaderboard page',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SearchHubPage(
        insidersLeaderboardPageBuilder: () =>
            const Scaffold(body: Center(child: Text('stub leaderboard'))),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Infinite Insiders'));
    await tester.pumpAndSettle();

    expect(find.text('stub leaderboard'), findsOneWidget);
  });

  group('Infinite Fantasy card (P3a feedback)', () {
    testWidgets('appears while the gate emits a live season, hides on null',
        (tester) async {
      final gate = StreamController<(String, String)?>.broadcast();
      addTearDown(gate.close);
      await tester.pumpWidget(MaterialApp(
        home: SearchHubPage(fantasyGateOverride: gate.stream),
      ));
      await tester.pump();

      // No Config node → no card, the other cards unaffected.
      expect(find.text('Infinite Fantasy'), findsNothing);
      expect(find.text('Around You'), findsOneWidget);

      gate.add(('Futsal', '15'));
      await tester.pump();
      expect(find.text('Infinite Fantasy'), findsOneWidget);
      expect(find.textContaining('Futsal Season 15'), findsOneWidget);

      // Config removed live → the card goes with it.
      gate.add(null);
      await tester.pump();
      expect(find.text('Infinite Fantasy'), findsNothing);
    });

    testWidgets('tapping the card opens the hub for that sport/season',
        (tester) async {
      final gate = StreamController<(String, String)?>.broadcast();
      addTearDown(gate.close);
      await tester.pumpWidget(MaterialApp(
        home: SearchHubPage(
          fantasyGateOverride: gate.stream,
          fantasyHubPageBuilder: (sport, season) =>
              Scaffold(body: Center(child: Text('stub hub $sport $season'))),
        ),
      ));
      await tester.pump();
      gate.add(('Futsal', '15'));
      await tester.pump();

      await tester
          .tap(find.byKey(const ValueKey('search_hub_fantasy_card')));
      await tester.pumpAndSettle();
      expect(find.text('stub hub Futsal 15'), findsOneWidget);
    });
  });
}
