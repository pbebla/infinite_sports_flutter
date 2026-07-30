// L6.2 Task 5: Player profile Stats tab icon mapping — basketball and flag
// football rows must resolve the SAME gold badge art (leagueStatIcon) the
// league screens use, including keys that previously had no icon at all
// (points/steals/blocks/turnovers). Futsal/soccer keys keep their line-art.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/profile/stats_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

Future<void> _pump(WidgetTester tester, CompetitionStats comp) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: StatsTab(competitions: [comp])),
  ));
  await tester.pump();
}

/// The [StatIcon] rendered in the same row as [label] (each stat row's
/// label is unique within one pumped CompetitionStats).
StatIcon _iconFor(WidgetTester tester, String label) {
  final row =
      find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
  return tester.widget<StatIcon>(
      find.descendant(of: row, matching: find.byType(StatIcon)));
}

void main() {
  group('Basketball — gold badges (previously-iconless keys included)', () {
    final comp = const CompetitionStats(
      label: 'Basketball · Season 5',
      sport: 'Basketball',
      position: 'Guard',
      stats: {
        'points': 22,
        'threePointers': 3,
        'twoPointers': 5,
        'freeThrows': 4,
        'rebounds': 9,
        'assists': 4,
        'steals': 2,
        'blocks': 1,
        'turnovers': 3,
      },
    );

    testWidgets('every basketball row gets its bball_*.png badge',
        (tester) async {
      await _pump(tester, comp);

      const expected = {
        'Points': 'assets/bball_points.png',
        '3-Pointers Made': 'assets/bball_three.png',
        '2-Pointers Made': 'assets/bball_two.png',
        'Free Throws Made': 'assets/bball_freethrow.png',
        'Rebounds': 'assets/bball_rebound.png',
        'Assists': 'assets/bball_assist.png',
        'Steals': 'assets/bball_steal.png',
        'Blocks': 'assets/bball_block.png',
        'Turnovers': 'assets/bball_turnover.png',
      };
      expected.forEach((label, asset) {
        final icon = _iconFor(tester, label);
        expect(icon.asset, asset, reason: label);
        expect(icon.badge, isTrue, reason: '$label should be a badge');
      });
    });
  });

  group('Flag Football — ff_*.png badges via the same leagueStatIcon tokens',
      () {
    final comp = const CompetitionStats(
      label: 'Flag Football · Season 3',
      sport: 'Flag Football',
      position: 'QB',
      stats: {
        'passTouchdowns': 5,
        'receivingTouchdowns': 2,
        'receptions': 7,
        'catchPercentage': 70,
        'interceptions': 1,
        'flagPulls': 3,
        'sacks': 2,
        'passBreakups': 1,
      },
    );

    testWidgets('FF keys resolve badge assets; Catch % row still renders',
        (tester) async {
      await _pump(tester, comp);

      const expected = {
        'Pass Touchdowns': 'assets/ff_pass_td.png',
        'Receiving Touchdowns': 'assets/ff_rec_td.png',
        'Receptions': 'assets/ff_rec.png',
        'Interceptions': 'assets/ff_int.png',
        'Flag Pulls': 'assets/ff_flag_pull.png',
        'Sacks': 'assets/ff_sack.png',
        'Pass Breakups': 'assets/ff_pbu.png',
      };
      expected.forEach((label, asset) {
        final icon = _iconFor(tester, label);
        expect(icon.asset, asset, reason: label);
        expect(icon.badge, isTrue, reason: '$label should be a badge');
      });

      // Catch % (L6.1) keeps working: row renders with its % suffix even
      // though it resolves no icon (leagueStatIcon has no 'catchPercentage'
      // token) — StatIcon just falls back to its neutral chip.
      expect(find.text('Catch %'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      final catchIcon = _iconFor(tester, 'Catch %');
      expect(catchIcon.badge, isFalse);
    });
  });

  group('Futsal — unchanged line-art on the white chip', () {
    testWidgets('goals/assists/saves/dpl keep their existing assets',
        (tester) async {
      await _pump(
        tester,
        const CompetitionStats(
          label: 'Futsal · Season 5',
          sport: 'Futsal',
          position: 'ATT',
          stats: {'goals': 7, 'assists': 2, 'saves': 0, 'dpl': 3},
        ),
      );
      expect(_iconFor(tester, 'Goals').asset, 'assets/goal.png');
      expect(_iconFor(tester, 'Goals').badge, isFalse);
      expect(_iconFor(tester, 'Assists').asset, 'assets/assist.png');
      expect(_iconFor(tester, 'Discipline (DPL)').asset, 'assets/dpl.png');
    });
  });
}
