// TDD tests for the "player's 3 strongest stats" helper (League Experience
// P2.2, owner item 4): top-3 by value desc, ties stable in the sport's
// candidate order, and fewer-than-3 non-zero fills from the sport's
// fallback list IN ORDER (futsal: Goals, Assists, DPL) including zeros.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/top_stats.dart';

void main() {
  group('topThreeStats', () {
    test('three-plus non-zero stats: top 3 sorted by value descending', () {
      final top = topThreeStats(
        {'goals': 2, 'assists': 5, 'saves': 9, 'dpl': 1, 'cleanSheets': 3},
        'Futsal',
      );
      expect(top.map((s) => s.stat).toList(), ['saves', 'assists', 'cleanSheets']);
      expect(top.map((s) => s.value).toList(), [9, 5, 3]);
    });

    test('ties break by the sport order (goals before assists before dpl)',
        () {
      final top = topThreeStats(
        {'goals': 4, 'assists': 4, 'dpl': 4, 'saves': 4},
        'Futsal',
      );
      expect(top.map((s) => s.stat).toList(), ['goals', 'assists', 'dpl']);
    });

    test('two non-zero stats fill the third slot from the fallback with 0',
        () {
      // Owner example: "player B has saves clean sheet or something" ->
      // saves, cleanSheets, then Goals (0) from the fallback.
      final top = topThreeStats(
        {'saves': 12, 'cleanSheets': 3},
        'Futsal',
      );
      expect(top.map((s) => s.stat).toList(), ['saves', 'cleanSheets', 'goals']);
      expect(top.last.value, 0);
    });

    test('one non-zero stat fills two slots from the fallback in order', () {
      final top = topThreeStats({'dpl': 2}, 'Futsal');
      expect(top.map((s) => s.stat).toList(), ['dpl', 'goals', 'assists']);
      expect(top.map((s) => s.value).toList(), [2, 0, 0]);
    });

    test('all-zero player gets the full fallback (Goals, Assists, DPL) at 0',
        () {
      final top = topThreeStats(const {}, 'Futsal');
      expect(top.map((s) => s.stat).toList(), ['goals', 'assists', 'dpl']);
      expect(top.map((s) => s.value).toList(), [0, 0, 0]);
    });

    test('fallback never duplicates a stat already in the top', () {
      final top = topThreeStats({'goals': 6, 'assists': 1}, 'Futsal');
      expect(top.map((s) => s.stat).toList(), ['goals', 'assists', 'dpl']);
      expect(top.map((s) => s.value).toList(), [6, 1, 0]);
    });

    test('cards are not "strongest stat" candidates', () {
      final top = topThreeStats(
        {'yellowCards': 9, 'redCards': 4, 'goals': 1},
        'Futsal',
      );
      expect(top.map((s) => s.stat).toList(), ['goals', 'assists', 'dpl']);
    });

    test('unknown sport falls back to the futsal config (P4 adds others)',
        () {
      final top = topThreeStats({'goals': 2}, 'Cricket');
      expect(top.map((s) => s.stat).toList(), ['goals', 'assists', 'dpl']);
    });
  });

  group('topThreeStatsForPlayer', () {
    test('reads the candidate stats off a TournamentPlayer via statByName',
        () {
      final player = leaguePlayerFromLineup(
        sport: 'Futsal',
        name: 'Sargon',
        teamName: 'Nineveh',
        raw: {'Saves': 12, 'CleanSheets': 3, 'number': '1'},
      );
      final top = topThreeStatsForPlayer(player, 'Futsal');
      expect(top.map((s) => s.stat).toList(), ['saves', 'cleanSheets', 'goals']);
      expect(top.map((s) => s.value).toList(), [12, 3, 0]);
    });
  });

  group('leagueTopStatIconKey', () {
    test('maps candidate stats to the player-stats-tab icon vocabulary', () {
      expect(leagueTopStatIconKey('goals'), 'goal');
      expect(leagueTopStatIconKey('assists'), 'assist');
      expect(leagueTopStatIconKey('saves'), 'save');
      expect(leagueTopStatIconKey('dpl'), 'dpl');
      // Clean sheets has no custom asset (matches the tournament/player
      // stats tabs) -> empty key, StatIcon renders its neutral fallback.
      expect(leagueTopStatIconKey('cleanSheets'), '');
    });
  });

  group('P4 — basketball/flag football top stats', () {
    test('basketball candidates + fallbacks are registered', () {
      expect(leagueTopStatCandidates['Basketball'],
          ['points', 'rebounds', 'assists', 'threePointers', 'steals', 'blocks']);
      expect(leagueTopStatFallbacks['Basketball'],
          ['points', 'rebounds', 'assists']);
    });

    test('flag football candidates + fallbacks are registered', () {
      expect(leagueTopStatCandidates['Flag Football'],
          ['touchdowns', 'receptions', 'flagPulls', 'interceptions', 'sacks', 'passTouchdowns']);
      expect(leagueTopStatFallbacks['Flag Football'],
          ['touchdowns', 'receptions', 'flagPulls']);
    });

    test('basketball: three non-zero candidates win; zero pads from '
        'fallback', () {
      final top = topThreeStats(
          {'points': 22, 'blocks': 3, 'steals': 0, 'rebounds': 0},
          'Basketball');
      expect(top.map((t) => t.stat).toList(),
          ['points', 'blocks', 'rebounds']); // rebounds padded at 0
      expect(top[2].value, 0);
    });

    test('icon keys: rebounds/threePointers have art; the rest are '
        'icon-less until L6', () {
      expect(leagueTopStatIconKey('rebounds'), 'rebound');
      expect(leagueTopStatIconKey('threePointers'), 'threepointer');
      expect(leagueTopStatIconKey('assists'), 'assist');
      expect(leagueTopStatIconKey('points'), '');
      expect(leagueTopStatIconKey('touchdowns'), '');
      expect(leagueTopStatIconKey('flagPulls'), '');
    });
  });
}
