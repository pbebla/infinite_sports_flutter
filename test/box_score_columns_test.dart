// Unit tests for the pure box-score column layer (Match Box Score spec,
// 2026-07-28): per-sport column sets, the auto-hide filter, derived PTS /
// Catch %, and the sort helper. Firebase-free by construction.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/match_tabs/box_score_columns.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

MatchPlayerTally _t({
  int goals = 0,
  int assists = 0,
  int saves = 0,
  int dpl = 0,
  Map<String, int> counts = const {},
}) {
  final t = MatchPlayerTally()
    ..goals = goals
    ..assists = assists
    ..saves = saves
    ..dpl = dpl;
  t.counts.addAll(counts);
  return t;
}

TournamentPlayer _p(String name) => TournamentPlayer(
      name: name,
      teamId: 'T',
      teamName: 'T',
      goals: 0,
      assists: 0,
      saves: 0,
      dpl: 0,
      cleanSheets: 0,
      yellowCards: 0,
      redCards: 0,
    );

List<String> _keys(String sport) =>
    boxScoreColumnsFor(sport).map((c) => c.key).toList();

BoxScoreColumn _col(String sport, String key) =>
    boxScoreColumnsFor(sport).firstWhere((c) => c.key == key);

void main() {
  group('per-sport column sets (spec table, importance order)', () {
    test('soccer/futsal: Goals first; Fouls defined (capture records Foul)',
        () {
      const expected = [
        'goals', 'assists', 'dpl', 'saves', 'fouls', 'yellowCards', 'redCards',
      ];
      expect(_keys('Futsal'), expected);
      // Soccer shares futsal's set — and the same instance, so widget-level
      // identity caching holds.
      expect(identical(boxScoreColumnsFor('Soccer'), boxScoreColumnsFor('Futsal')),
          isTrue);
    });

    test('basketball: PTS first; Fouls defined (capture records Foul)', () {
      expect(_keys('Basketball'), [
        'points', 'rebounds', 'assists', 'threePointers', 'twoPointers',
        'freeThrows', 'steals', 'blocks', 'turnovers', 'fouls',
      ]);
    });

    test('flag football: NO fouls column — its capture records no foul events',
        () {
      expect(_keys('Flag Football'), [
        'touchdowns', 'passTouchdowns', 'receptions', 'interceptions',
        'flagPulls', 'sacks', 'catchPercentage',
      ]);
      expect(_keys('Flag Football'), isNot(contains('fouls')));
    });

    test('unknown sport falls back to the soccer/futsal set', () {
      expect(identical(boxScoreColumnsFor('Volleyball'),
          boxScoreColumnsFor('Futsal')), isTrue);
    });
  });

  group('derived values', () {
    test('PTS = FT + 2x2PT + 3x3PT from the made-shot buckets', () {
      final pts = _col('Basketball', 'points');
      expect(
          pts.valueOf(_t(counts: {
            'freeThrows': 2,
            'twoPointers': 3,
            'threePointers': 1,
          })),
          11);
      expect(pts.valueOf(null), 0);
    });

    test('Catch % is ungated: real rate with any targets, null without', () {
      final pct = _col('Flag Football', 'catchPercentage');
      expect(pct.valueOf(_t(counts: {'receptions': 3, 'recMisses': 1})), 75);
      // 1/1 shows 100% here (Match Leaders gates this to >=3 targets; the
      // box score shows the player's real rate).
      expect(pct.valueOf(_t(counts: {'receptions': 1})), 100);
      expect(pct.valueOf(_t()), isNull); // no targets = no data, not 0%
      expect(pct.valueOf(null), isNull);
      expect(pct.suffix, '%');
    });
  });

  group('visibleColumns (auto-hide)', () {
    test('keeps only columns some player recorded', () {
      final visible = visibleColumns(
        boxScoreColumnsFor('Futsal'),
        [_t(goals: 2), _t(assists: 1), _t()],
      );
      expect(visible.map((c) => c.key), ['goals', 'assists']);
    });

    test('empty match (no tallies) hides every column', () {
      expect(visibleColumns(boxScoreColumnsFor('Futsal'), const []), isEmpty);
      expect(visibleColumns(boxScoreColumnsFor('Basketball'), [_t(), _t()]),
          isEmpty);
    });

    test('Catch % stays hidden when no one has targets', () {
      final visible = visibleColumns(
        boxScoreColumnsFor('Flag Football'),
        [_t(counts: {'touchdowns': 1})],
      );
      expect(visible.map((c) => c.key), ['touchdowns']);
    });
  });

  group('sortedBoxScoreRows', () {
    final roster = [_p('Ashur'), _p('Ninos'), _p('Sargon')];
    final tallies = {
      'Ashur': _t(goals: 1),
      'Ninos': _t(goals: 3),
      // Sargon: no events this match (null tally).
    };
    final goals = _col('Futsal', 'goals');

    test('descending = best first; no-event players sink last', () {
      final rows = sortedBoxScoreRows(roster, tallies,
          column: goals, ascending: false);
      expect(rows.map((p) => p.name), ['Ninos', 'Ashur', 'Sargon']);
    });

    test('ascending toggles the order', () {
      final rows =
          sortedBoxScoreRows(roster, tallies, column: goals, ascending: true);
      expect(rows.map((p) => p.name), ['Sargon', 'Ashur', 'Ninos']);
    });

    test('name sort: A-Z and Z-A', () {
      expect(
        sortedBoxScoreRows(roster, tallies, column: null, ascending: true)
            .map((p) => p.name),
        ['Ashur', 'Ninos', 'Sargon'],
      );
      expect(
        sortedBoxScoreRows(roster, tallies, column: null, ascending: false)
            .map((p) => p.name),
        ['Sargon', 'Ninos', 'Ashur'],
      );
    });

    test('stat ties always break A-Z, either direction', () {
      final tied = {'Ninos': _t(goals: 2), 'Ashur': _t(goals: 2)};
      for (final asc in [true, false]) {
        final rows = sortedBoxScoreRows([_p('Ninos'), _p('Ashur')], tied,
            column: goals, ascending: asc);
        expect(rows.map((p) => p.name), ['Ashur', 'Ninos']);
      }
    });

    test('null Catch % ("no data") sorts below a real 0-adjacent value', () {
      final pct = _col('Flag Football', 'catchPercentage');
      final rows = sortedBoxScoreRows(
        [_p('NoTargets'), _p('Receiver')],
        {
          'Receiver': _t(counts: {'receptions': 0, 'recMisses': 2}), // 0%
        },
        column: pct,
        ascending: false,
      );
      expect(rows.map((p) => p.name), ['Receiver', 'NoTargets']);
    });
  });
}
