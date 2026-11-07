// P3d — pure parser coverage for the new Fantasy read shapes: the PINNED
// Leaderboards contract (Overall/<uid> {points, rank, movement};
// Gameweek/<gw>/<uid> {points, rank} — P4 implements to THIS), the whole
// Managers map, MiniLeagues and the published News feed — each with the usual
// RTDB Map/List-coercion tolerance.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';

void main() {
  group('leaderboardEntriesFromNode', () {
    test('parses points/rank/movement and sorts by rank asc', () {
      final entries = leaderboardEntriesFromNode({
        'u3': {'points': 10, 'rank': 3, 'movement': -1},
        'u1': {'points': 30, 'rank': 1, 'movement': 2},
        'u2': {'points': 20, 'rank': 2},
      });
      expect(entries.map((e) => e.uid), ['u1', 'u2', 'u3']);
      expect(entries[0].points, 30);
      expect(entries[0].movement, 2);
      expect(entries[1].movement, isNull);
      expect(entries[2].movement, -1);
    });

    test('missing ranks sort last by points desc, ties by uid', () {
      final entries = leaderboardEntriesFromNode({
        'b': {'points': 5},
        'a': {'points': 5},
        'c': {'points': 9},
        'ranked': {'points': 1, 'rank': 1},
      });
      expect(entries.map((e) => e.uid), ['ranked', 'c', 'a', 'b']);
      expect(entries[1].rank, isNull);
    });

    test('display values tolerate string numbers; junk children skipped', () {
      final entries = leaderboardEntriesFromNode({
        'u1': {'points': '12', 'rank': '1', 'movement': '-2'},
        'junk': 'not-a-map',
        'u2': null,
      });
      expect(entries, hasLength(1));
      expect(entries.single.points, 12);
      expect(entries.single.rank, 1);
      expect(entries.single.movement, -2);
    });

    test('non-map node parses empty', () {
      expect(leaderboardEntriesFromNode(null), isEmpty);
      expect(leaderboardEntriesFromNode('x'), isEmpty);
      expect(leaderboardEntriesFromNode([1, 2]), isEmpty);
    });
  });

  group('leaderboardsFromNode', () {
    test('absent node is the empty board (friendly empty state)', () {
      final boards = leaderboardsFromNode(null);
      expect(boards.isEmpty, isTrue);
      expect(boards.overall, isEmpty);
      expect(boards.byWeek, isEmpty);
    });

    test('parses Overall and Gameweek maps', () {
      final boards = leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 40, 'rank': 1, 'movement': 0},
        },
        'Gameweek': {
          '1': {
            'u1': {'points': 40, 'rank': 1},
          },
          '2': {
            'u1': {'points': 12, 'rank': 1},
          },
        },
      });
      expect(boards.overall.single.points, 40);
      expect(boards.byWeek.keys, unorderedEquals([1, 2]));
      expect(boards.byWeek[2]!.single.points, 12);
    });

    test('tolerates the LIST-coerced Gameweek node (small int keys): index '
        'is the week number', () {
      final boards = leaderboardsFromNode({
        'Gameweek': [
          null, // gw 0 never exists
          {
            'u1': {'points': 7, 'rank': 1},
          },
          {
            'u1': {'points': 9, 'rank': 1},
          },
        ],
      });
      expect(boards.overall, isEmpty);
      expect(boards.byWeek.keys, unorderedEquals([1, 2]));
      expect(boards.byWeek[1]!.single.points, 7);
    });

    test('weeks with no usable entries are dropped', () {
      final boards = leaderboardsFromNode({
        'Gameweek': {
          '1': 'junk',
          '2': {
            'u1': {'points': 3},
          },
        },
      });
      expect(boards.byWeek.keys, [2]);
    });
  });

  // Leaderboard extras: Leaderboards/RankHistory/<uid> = {"<gw>": rank} —
  // each manager's Overall rank after every finalized week (the fan's "Your
  // rank this season" line). Small int keys, so RTDB may list-coerce a uid's
  // map.
  group('RankHistory', () {
    test('parses uid -> {gameweek: rank}; Overall and Gameweek are unchanged '
        'by the new key', () {
      final boards = leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 30, 'rank': 1, 'movement': 2},
        },
        'Gameweek': {
          '1': {
            'u1': {'points': 30, 'rank': 1},
          },
        },
        'RankHistory': {
          'u1': {'1': 3, '2': 1},
          'u2': {'2': 4},
        },
      });
      expect(boards.overall.single.uid, 'u1');
      expect(boards.overall.single.movement, 2);
      expect(boards.byWeek.keys, [1]);
      expect(boards.rankHistory, {
        'u1': {1: 3, 2: 1},
        'u2': {2: 4},
      });
    });

    test("tolerates a uid's LIST-coerced history: index is the gameweek", () {
      final boards = leaderboardsFromNode({
        'RankHistory': {
          'u1': [null, 5, 3, 2],
          'u2': [null, null, null, 7],
        },
      });
      expect(boards.rankHistory, {
        'u1': {1: 5, 2: 3, 3: 2},
        'u2': {3: 7},
      });
    });

    test('string numbers accepted; junk weeks/ranks/children skipped; empty '
        'histories dropped', () {
      final boards = leaderboardsFromNode({
        'RankHistory': {
          'u1': {'1': '4', '2': 'x', 'gw': 2, '3': 0, '4': -1, '5': 2},
          'u2': 'junk',
          'u3': <String, Object?>{},
          'u4': {'1': null},
        },
      });
      expect(boards.rankHistory, {
        'u1': {1: 4, 5: 2},
      });
    });

    test('absent / non-map RankHistory = no history; the board still parses '
        'and RankHistory alone never makes it non-empty', () {
      expect(FantasyLeaderboards.empty.rankHistory, isEmpty);
      final plain = leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 3, 'rank': 1},
        },
      });
      expect(plain.rankHistory, isEmpty);
      expect(plain.overall.single.points, 3);
      final junk = leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 3, 'rank': 1},
        },
        'RankHistory': 'junk',
      });
      expect(junk.rankHistory, isEmpty);
      expect(junk.overall.single.points, 3);
      expect(
          leaderboardsFromNode({
            'RankHistory': {
              'u1': {'1': 1},
            },
          }).isEmpty,
          isTrue);
    });
  });

  group('live flags (live everywhere, Task 4)', () {
    test('parsed entries are official: live false, no live rank points', () {
      final boards = leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 40, 'rank': 1},
        },
        'Gameweek': {
          '1': {
            'u1': {'points': 40, 'rank': 1},
          },
        },
        'RankHistory': {
          'u1': {'1': 1},
        },
      });
      expect(boards.overall.single.live, isFalse);
      expect(boards.byWeek[1]!.single.live, isFalse);
      expect(boards.isLiveRankPoint('u1', 1), isFalse);
      expect(boards.liveRankPoints, isEmpty);
      expect(FantasyLeaderboards.empty.liveRankPoints, isEmpty);
    });
  });

  group('managersFromNode', () {
    test('parses the whole node, skipping unusable children', () {
      final managers = managersFromNode({
        'u1': {'TeamName': 'Gold Rush', 'NameFlagged': false},
        'u2': {'TeamName': 'Flagged FC', 'NameFlagged': true},
        'u3': {'TeamName': ''},
        'u4': 'junk',
      });
      expect(managers.keys, unorderedEquals(['u1', 'u2']));
      expect(managers['u1']!.teamName, 'Gold Rush');
      expect(managers['u2']!.nameFlagged, isTrue);
    });

    test('non-map parses empty', () {
      expect(managersFromNode(null), isEmpty);
      expect(managersFromNode([1]), isEmpty);
    });
  });

  group('miniLeaguesFromNode', () {
    test('parses leagues with members, sorted by name then id', () {
      final leagues = miniLeaguesFromNode({
        'idB': {
          'Name': 'zeta club',
          'Code': 'abc234',
          'Owner': 'u1',
          'CreatedAt': 5,
          'Members': {'u1': true, 'u2': true, 'gone': false},
        },
        'idA': {
          'Name': 'Alpha',
          'Code': 'XYZ789',
          'Owner': 'u2',
          'Members': {'u2': true},
        },
      });
      expect(leagues.map((l) => l.id), ['idA', 'idB']);
      final zeta = leagues[1];
      // Codes normalize upper-case at parse so matching is uniform.
      expect(zeta.code, 'ABC234');
      expect(zeta.memberUids, unorderedEquals(['u1', 'u2']));
      expect(zeta.memberCount, 2);
      expect(zeta.hasMember('gone'), isFalse);
      expect(zeta.createdAtMs, 5);
      expect(leagues[0].createdAtMs, isNull);
    });

    test('children without a Name or Code are skipped', () {
      final leagues = miniLeaguesFromNode({
        'a': {'Name': '', 'Code': 'ABC234'},
        'b': {'Name': 'No Code'},
        'c': 'junk',
        'ok': {'Name': 'Fine', 'Code': 'ABC234', 'Owner': 'u1'},
      });
      expect(leagues.single.id, 'ok');
      expect(leagues.single.memberUids, isEmpty);
    });

    test('non-map parses empty', () {
      expect(miniLeaguesFromNode(null), isEmpty);
      expect(miniLeaguesFromNode('x'), isEmpty);
    });
  });

  group('newsPostsFromNode', () {
    test('sorts newest first (At desc, ties by id desc)', () {
      final posts = newsPostsFromNode({
        'a': {'Title': 'Oldest', 'Body': 'b1', 'At': 100},
        'b': {'Title': 'Newest', 'Body': 'b2', 'At': 300, 'PhotoUrl': 'u'},
        // Push ids sort chronologically: on an At tie the LARGER id ('d')
        // is the newer post and lists first.
        'c': {'Title': 'Tie-old', 'Body': 'b3', 'At': 200},
        'd': {'Title': 'Tie-new', 'Body': 'b4', 'At': 200},
      });
      expect(posts.map((p) => p.title), ['Newest', 'Tie-new', 'Tie-old', 'Oldest']);
      expect(posts.first.photoUrl, 'u');
      expect(posts.last.photoUrl, isNull);
    });

    test('tolerates string At; untitled/junk children skipped; empty '
        'PhotoUrl is null', () {
      final posts = newsPostsFromNode({
        'a': {'Title': 'Post', 'At': '50', 'PhotoUrl': ' '},
        'b': {'Body': 'no title'},
        'c': 'junk',
      });
      expect(posts.single.atMs, 50);
      expect(posts.single.photoUrl, isNull);
      expect(posts.single.body, '');
    });

    test('non-map parses empty', () {
      expect(newsPostsFromNode(null), isEmpty);
    });
  });
}
