// Fantasy round 3, Task 4 — PlayerWeekStats parser + score-source labels.
// The server (finalize_core.ts) writes
// `PlayerWeekStats/<gw>/<name>` = {Pts, Played, GP, Games:[{Vs,For,Against,
// Forfeit?}], Lines?:{<key>:{N,P}}, Voided?}. RTDB DROPS empty arrays/objects,
// so a missing Games means [] and a missing Lines means {}.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';

void main() {
  group('playerWeekStatsFromNode', () {
    test('round-trips a full played week (two games, lines, forfeit)', () {
      final stats = playerWeekStatsFromNode({
        'Pts': 17,
        'Played': true,
        'GP': 2,
        'Games': [
          {'Vs': 'Nimrod', 'For': 4, 'Against': 1},
          {'Vs': 'Kings', 'For': 5, 'Against': 0, 'Forfeit': 'won'},
        ],
        'Lines': {
          'plays': {'N': 2, 'P': 2},
          'goals': {'N': 3, 'P': 12},
          'bonus': {'N': 3, 'P': 3},
        },
      })!;
      expect(stats.points, 17);
      expect(stats.played, isTrue);
      expect(stats.gamesPlayed, 2);
      expect(stats.voided, isFalse);
      expect(stats.games, hasLength(2));
      expect(stats.games[0].vs, 'Nimrod');
      expect(stats.games[0].goalsFor, 4);
      expect(stats.games[0].goalsAgainst, 1);
      expect(stats.games[0].forfeit, isNull);
      expect(stats.games[1].vs, 'Kings');
      expect(stats.games[1].forfeit, 'won');
      expect(stats.lines.keys, containsAll(['plays', 'goals', 'bonus']));
      expect(stats.lines['goals']!.count, 3);
      expect(stats.lines['goals']!.points, 12);
      expect(stats.lines['bonus']!.points, 3);
    });

    test('voided week: Pts 0, Voided true, no Lines, real court record kept',
        () {
      final stats = playerWeekStatsFromNode({
        'Pts': 0,
        'Played': true,
        'GP': 1,
        'Games': [
          {'Vs': 'Nimrod', 'For': 3, 'Against': 2},
        ],
        'Voided': true,
      })!;
      expect(stats.voided, isTrue);
      expect(stats.points, 0);
      expect(stats.played, isTrue);
      expect(stats.gamesPlayed, 1);
      expect(stats.games, hasLength(1));
      expect(stats.lines, isEmpty);
    });

    test('missing Lines → {} and missing Games → [] (RTDB drops empties)', () {
      final stats =
          playerWeekStatsFromNode({'Pts': 0, 'Played': false, 'GP': 0})!;
      expect(stats.lines, isEmpty);
      expect(stats.games, isEmpty);
      expect(stats.played, isFalse);
      expect(stats.gamesPlayed, 0);
      expect(stats.points, 0);
      expect(stats.voided, isFalse);
    });

    test('games.length and gamesPlayed are independent (guests / team moves)',
        () {
      // Team schedule says 2 games, stats-by-name say he played 1.
      final stats = playerWeekStatsFromNode({
        'Pts': 4,
        'Played': true,
        'GP': 1,
        'Games': [
          {'Vs': 'A', 'For': 1, 'Against': 0},
          {'Vs': 'B', 'For': 2, 'Against': 2},
        ],
      })!;
      expect(stats.games, hasLength(2));
      expect(stats.gamesPlayed, 1);
      // And the other way: stats say 2 games but the team list is absent.
      final other =
          playerWeekStatsFromNode({'Pts': 6, 'Played': true, 'GP': 2})!;
      expect(other.games, isEmpty);
      expect(other.gamesPlayed, 2);
    });

    test('GP missing → falls back to Lines.plays.N, else 0', () {
      final fromLines = playerWeekStatsFromNode({
        'Pts': 3,
        'Played': true,
        'Lines': {
          'plays': {'N': 2, 'P': 2},
          'goals': {'N': 1, 'P': 4},
        },
      })!;
      expect(fromLines.gamesPlayed, 2);
      final none = playerWeekStatsFromNode({'Pts': 3, 'Played': true})!;
      expect(none.gamesPlayed, 0);
    });

    test('Played missing → derived from games played', () {
      expect(playerWeekStatsFromNode({'Pts': 1, 'GP': 1})!.played, isTrue);
      expect(playerWeekStatsFromNode({'Pts': 0, 'GP': 0})!.played, isFalse);
    });

    test('tolerates list/map coercion, string numbers and junk children', () {
      final stats = playerWeekStatsFromNode({
        'Pts': '9', // string-coerced numbers happen in RTDB
        'Played': true,
        'GP': '1',
        // An index-keyed Map with a hole instead of a List.
        'Games': {
          '1': {'Vs': 'Second', 'For': '2', 'Against': 1},
          '0': {'Vs': 'First', 'For': 0, 'Against': '0'},
          '2': 'garbage',
        },
        'Lines': {
          'goals': {'N': '2', 'P': 8},
          'weird': 'nope',
          'saves': null,
        },
      })!;
      expect(stats.points, 9);
      expect(stats.gamesPlayed, 1);
      expect(stats.games.map((g) => g.vs), ['First', 'Second']);
      expect(stats.games[1].goalsFor, 2);
      expect(stats.lines.keys, ['goals']);
      expect(stats.lines['goals']!.count, 2);
    });

    test('a Games List with null holes and malformed rows skips them', () {
      final stats = playerWeekStatsFromNode({
        'Pts': 2,
        'Played': true,
        'GP': 2,
        'Games': [
          null,
          {'Vs': 'Real', 'For': 1, 'Against': 0},
          {'For': 1, 'Against': 0}, // no opponent: unusable
          'junk',
        ],
      })!;
      expect(stats.games.map((g) => g.vs), ['Real']);
    });

    test('an unknown Forfeit value is dropped', () {
      final stats = playerWeekStatsFromNode({
        'Pts': 1,
        'Played': true,
        'GP': 1,
        'Games': [
          {'Vs': 'X', 'For': 5, 'Against': 0, 'Forfeit': 'maybe'},
          {'Vs': 'Y', 'For': 0, 'Against': 5, 'Forfeit': 'lost'},
        ],
      })!;
      expect(stats.games[0].forfeit, isNull);
      expect(stats.games[1].forfeit, 'lost');
    });

    test('absent / non-map / Pts-less nodes → null (no record)', () {
      expect(playerWeekStatsFromNode(null), isNull);
      expect(playerWeekStatsFromNode('nope'), isNull);
      expect(playerWeekStatsFromNode(7), isNull);
      expect(playerWeekStatsFromNode([1, 2]), isNull);
      expect(playerWeekStatsFromNode({'Played': true}), isNull);
    });
  });

  group('scoreSourceLabel', () {
    test('every server line key has its label', () {
      const table = {
        'plays': 'Played',
        'goals': 'Goals',
        'assists': 'Assists',
        'cleanSheet': 'Clean sheets',
        'saves': 'Saves',
        'penSaved': 'Penalty saves',
        'penMissed': 'Penalty misses',
        'conceded': 'Goals conceded',
        'dpl': 'Defensive plays',
        'yellow': 'Yellow cards',
        'red': 'Red cards',
        'ownGoals': 'Own goals',
        'bonus': 'Bonus',
      };
      table.forEach((key, label) {
        expect(scoreSourceLabel(key), label, reason: key);
      });
    });

    test('an unknown key falls back to the key itself', () {
      expect(scoreSourceLabel('hatTrick'), 'hatTrick');
      expect(scoreSourceLabel(''), '');
    });
  });
}
