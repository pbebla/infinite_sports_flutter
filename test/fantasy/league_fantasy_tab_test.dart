// P3a Task 5 — the league page's Fantasy entry: tab-row gating (pure) and
// the hub entry card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_detail_page.dart';
import 'package:infinite_sports_flutter/league_tabs/league_fantasy_tab.dart';

void main() {
  group('leagueSeasonTabs gating', () {
    List<String?> labels({required bool predict, required bool fantasy}) =>
        leagueSeasonTabs(predictOpen: predict, fantasyOpen: fantasy)
            .map((t) => t.text)
            .toList();

    test('base row without optional tabs', () {
      expect(labels(predict: false, fantasy: false),
          ['Fixtures', 'Table', 'Playoffs', 'Player Stats', 'Teams']);
    });
    test('Fantasy appends when the config node exists', () {
      expect(labels(predict: false, fantasy: true), [
        'Fixtures', 'Table', 'Playoffs', 'Player Stats', 'Teams', 'Fantasy',
      ]);
    });
    test('fixed order with Predict open too: Predict then Fantasy', () {
      expect(labels(predict: true, fantasy: true), [
        'Fixtures', 'Table', 'Playoffs', 'Player Stats', 'Teams',
        'Predict', 'Fantasy',
      ]);
      // Predict's fixed index (base length) is unaffected by Fantasy.
      expect(labels(predict: true, fantasy: true)[5], 'Predict');
    });
  });

  group('LeagueFantasyTab entry card', () {
    testWidgets('shows the banner copy and opens the hub on tap',
        (tester) async {
      var entered = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeagueFantasyTab(
            sport: 'Futsal',
            season: '15',
            onEnter: () => entered++,
          ),
        ),
      ));
      expect(
        find.textContaining('Fantasy is live for Futsal Season 15'),
        findsOneWidget,
      );
      expect(find.text('Build your seven'), findsOneWidget);
      await tester.tap(find.text('Enter Infinite Fantasy'));
      expect(entered, 1);
    });

    testWidgets('no underlined tappable text (house rule)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeagueFantasyTab(
            sport: 'Futsal',
            season: '15',
            onEnter: () {},
          ),
        ),
      ));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style?.decoration ?? TextDecoration.none,
            TextDecoration.none,
            reason: '"${t.data}" must not be underlined');
      }
    });
  });
}
