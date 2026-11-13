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

import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
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
    // Release report #16: the card said "Futsal Season 15 is live" after the
    // season had ended. It now shares the home banner's season-over decision
    // (FantasySeasonFinishedFeed on the league's Finished flag).
    group('season over (release report #16)', () {
      setUp(FantasySeasonFinishedFeed.clearSessionCache);

      Future<StreamController<bool>> pumpHub(WidgetTester tester) async {
        final gate = StreamController<(String, String)?>.broadcast();
        final finished = StreamController<bool>.broadcast();
        addTearDown(gate.close);
        addTearDown(finished.close);
        final asked = <String>[];
        await tester.pumpWidget(MaterialApp(
          home: SearchHubPage(
            fantasyGateOverride: gate.stream,
            fantasyFinishedStates: (sport, season) {
              asked.add('$sport|$season');
              return finished.stream;
            },
          ),
        ));
        await tester.pump();
        gate.add(('Futsal', '15'));
        await tester.pump();
        expect(asked, ['Futsal|15']);
        return finished;
      }

      testWidgets('waits for the flag (no live-then-over flip), then reads '
          '"is over — see the final standings"', (tester) async {
        final finished = await pumpHub(tester);
        expect(find.text('Infinite Fantasy'), findsNothing);
        finished.add(true);
        await tester.pump();
        expect(find.text('Infinite Fantasy'), findsOneWidget);
        expect(
            find.text('Futsal Season 15 is over — see the final standings'),
            findsOneWidget);
        expect(find.textContaining('is live'), findsNothing);
      });

      testWidgets('"is live" only while the season is running; the card '
          'follows the flag live', (tester) async {
        final finished = await pumpHub(tester);
        finished.add(false);
        await tester.pump();
        expect(find.text('Pick your seven — Futsal Season 15 is live'),
            findsOneWidget);
        finished.add(true);
        await tester.pump();
        expect(
            find.text('Futsal Season 15 is over — see the final standings'),
            findsOneWidget);
      });

      testWidgets('a failing flag feed reads as not finished (house rule: '
          'the same fallback as the banner)', (tester) async {
        final finished = await pumpHub(tester);
        finished.addError(StateError('offline'));
        await tester.pump();
        expect(find.text('Pick your seven — Futsal Season 15 is live'),
            findsOneWidget);
      });
    });
  });
}
