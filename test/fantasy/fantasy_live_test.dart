// Live everywhere, Task 4 — the fan's live data layer (fantasy_live.dart):
// the parsers for every child of `Fantasy/<sport>/<season>/Live` (shape pinned
// by functions/src/lib/fantasy/live_core.ts, NODE SHAPES), the ONE overlay
// rule `liveAppliesTo`, the pure `mergeLive…` overlays, the four-child feed
// (never the whole Live node) and its sign-out hygiene.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_session.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

// ── Fixtures: the server's shapes, as RTDB hands them back ─────────────────

Map<String, Object?> liveMetaNode({int gw = 2, String state = 'live'}) => {
      'Gw': gw,
      'State': state,
      'ReadAt': 1000,
      'UpdatedAt': 2000,
      'Games': {
        '0': {'S': 2, 'T1': 'Nimrod', 'T2': 'Kings'},
        '1': {'S': 1, 'T1': 'Lions', 'T2': 'Bears'},
      },
    };

/// The tombstone finalize leaves: `Live` = { Meta: { Gw, State, UpdatedAt } }.
Map<String, Object?> tombstoneMetaNode({int gw = 2}) =>
    {'Gw': gw, 'State': 'settled', 'UpdatedAt': 3000};

Map<String, Object?> playerNode({
  int pts = 7,
  String st = 'done',
  int total = 40,
  int form = 55,
  int ppg = 50,
  int games = 8,
  int own = 31,
  Map<String, Object?>? lines,
  bool bonusProv = false,
}) =>
    {
      'Pts': pts,
      'St': st,
      'Total': total,
      'Form': form,
      'Ppg': ppg,
      'Games': games,
      'Own': own,
      if (lines != null) 'Lines': lines,
      if (bonusProv) 'BonusProv': true,
    };

const _liveMeta = LiveMeta(gw: 2, state: LiveState.live);
const _settledMeta = LiveMeta(gw: 2, state: LiveState.settled);

FantasyLiveState liveStateOf({
  LiveMeta? meta = _liveMeta,
  Map<String, LiveBoardRow> board = const {},
  Map<String, LivePlayer> players = const {},
  FantasyDreamTeam? teamOfWeek,
}) =>
    FantasyLiveState(
        meta: meta, board: board, players: players, teamOfWeek: teamOfWeek);

LivePlayer livePlayer({
  int pts = 0,
  LivePlayerStatus st = LivePlayerStatus.done,
  Map<String, ({int n, int p})> lines = const {},
  bool bonusProv = false,
  int total = 0,
  int form = 0,
  int ppg = 0,
  int games = 0,
  int own = 0,
}) =>
    LivePlayer(
      pts: pts,
      st: st,
      lines: lines,
      bonusProv: bonusProv,
      total: total,
      form: form,
      ppg: ppg,
      games: games,
      own: own,
    );

FantasyLeaderboards officialBoards() => const FantasyLeaderboards(
      overall: [
        FantasyLeaderboardEntry(uid: 'u1', points: 30, rank: 1, movement: 2),
        FantasyLeaderboardEntry(uid: 'u2', points: 20, rank: 2, movement: 0),
      ],
      byWeek: {
        1: [
          FantasyLeaderboardEntry(uid: 'u1', points: 30, rank: 1),
          FantasyLeaderboardEntry(uid: 'u2', points: 20, rank: 2),
        ],
      },
      rankHistory: {
        'u1': {1: 1},
        'u2': {1: 2},
      },
    );

const _board = {
  'u1': LiveBoardRow(o: 40, r: 2, m: -1, w: 10, wr: 2),
  'u2': LiveBoardRow(o: 45, r: 1, m: 1, w: 25, wr: 1),
  // A manager new this week: no movement (not in the base).
  'u3': LiveBoardRow(o: 5, r: 3, w: 5, wr: 3),
};

void main() {
  setUp(FantasyLiveFeed.clearSessionCache);

  // ── THE overlay rule ─────────────────────────────────────────────────────

  group('liveAppliesTo (the one overlay rule)', () {
    test('no Live meta at all → official', () {
      expect(liveAppliesTo(meta: null, week: 2), isFalse);
    });

    test('another gameweek → official', () {
      expect(liveAppliesTo(meta: _liveMeta, week: 1), isFalse);
      expect(liveAppliesTo(meta: _liveMeta, week: 3), isFalse);
    });

    test('the same gameweek, live → overlays', () {
      expect(liveAppliesTo(meta: _liveMeta, week: 2), isTrue);
    });

    test('the same gameweek, settled tombstone → official', () {
      expect(liveAppliesTo(meta: _settledMeta, week: 2), isFalse);
    });

    test('liveWeekOf is the rule applied to the meta\'s own week', () {
      expect(liveWeekOf(_liveMeta), 2);
      expect(liveWeekOf(_settledMeta), isNull);
      expect(liveWeekOf(null), isNull);
    });
  });

  // ── Parsers ──────────────────────────────────────────────────────────────

  group('liveMetaFromNode', () {
    test('round-trips a live meta with its games', () {
      final meta = liveMetaFromNode(liveMetaNode())!;
      expect(meta.gw, 2);
      expect(meta.state, LiveState.live);
      expect(meta.readAt, 1000);
      expect(meta.updatedAt, 2000);
      expect(meta.games.keys, unorderedEquals(['0', '1']));
      expect(meta.games['0']!.status, 2);
      expect(meta.games['0']!.team1, 'Nimrod');
      expect(meta.games['0']!.team2, 'Kings');
      expect(meta.games['1']!.status, 1);
    });

    test('Games arrives list-coerced (index-keyed map RTDB hands back as a '
        'list, holes null)', () {
      final node = liveMetaNode()
        ..['Games'] = [
          {'S': 2, 'T1': 'Nimrod', 'T2': 'Kings'},
          null,
          {'S': 0, 'T1': 'Lions', 'T2': 'Bears'},
        ];
      final meta = liveMetaFromNode(node)!;
      expect(meta.games.keys, unorderedEquals(['0', '2']));
      expect(meta.games['2']!.status, 0);
      expect(meta.games['2']!.team1, 'Lions');
    });

    test('a missing Games (RTDB drops empty maps) is no games', () {
      final node = liveMetaNode()..remove('Games');
      expect(liveMetaFromNode(node)!.games, isEmpty);
    });

    test('the settled tombstone parses (Gw, State, UpdatedAt only)', () {
      final meta = liveMetaFromNode(tombstoneMetaNode())!;
      expect(meta.gw, 2);
      expect(meta.state, LiveState.settled);
      expect(meta.updatedAt, 3000);
      expect(meta.readAt, 0);
      expect(meta.games, isEmpty);
    });

    test('unusable metas are no meta (never a fake live)', () {
      expect(liveMetaFromNode(null), isNull);
      expect(liveMetaFromNode('live'), isNull);
      expect(liveMetaFromNode({'State': 'live'}), isNull); // no Gw
      expect(liveMetaFromNode({'Gw': 2}), isNull); // no State
      expect(liveMetaFromNode({'Gw': 2, 'State': 'finished'}), isNull);
      expect(liveMetaFromNode({'Gw': 0, 'State': 'live'}), isNull);
    });
  });

  group('liveBoardFromNode', () {
    test('round-trips rows; optional M/W/WR omitted stay null, zeros stay '
        'zeros', () {
      final board = liveBoardFromNode({
        'u1': {'O': 40, 'R': 2, 'M': -1, 'W': 10, 'WR': 2},
        'u2': {'O': 45, 'R': 1, 'M': 0, 'W': 0, 'WR': 5},
        'u3': {'O': 5, 'R': 3}, // new manager, not scored this week
      });
      expect(board.keys, unorderedEquals(['u1', 'u2', 'u3']));
      expect((board['u1']!.o, board['u1']!.r, board['u1']!.m), (40, 2, -1));
      expect((board['u1']!.w, board['u1']!.wr), (10, 2));
      expect((board['u2']!.m, board['u2']!.w, board['u2']!.wr), (0, 0, 5));
      expect((board['u3']!.m, board['u3']!.w, board['u3']!.wr),
          (null, null, null));
    });

    test('malformed rows are skipped, never crash; non-maps are empty', () {
      final board = liveBoardFromNode({
        'ok': {'O': 1, 'R': 1},
        'noRank': {'O': 1},
        'noPoints': {'R': 1},
        'junk': 'x',
        'nothing': null,
      });
      expect(board.keys, ['ok']);
      expect(liveBoardFromNode(null), isEmpty);
      expect(liveBoardFromNode([1, 2]), isEmpty);
    });
  });

  group('livePlayersFromNode', () {
    test('round-trips a full player with lines and provisional bonus', () {
      final players = livePlayersFromNode({
        'Ava Striker': playerNode(
          pts: 12,
          st: 'live',
          lines: {
            'plays': {'N': 1, 'P': 2},
            'goals': {'N': 2, 'P': 8},
            'bonus': {'N': 2, 'P': 2},
          },
          bonusProv: true,
        ),
      });
      final ava = players['Ava Striker']!;
      expect(ava.pts, 12);
      expect(ava.st, LivePlayerStatus.live);
      expect(ava.lines['goals'], (n: 2, p: 8));
      expect(ava.lines['plays'], (n: 1, p: 2));
      expect(ava.bonusProv, isTrue);
      expect(ava.total, 40);
      expect(ava.form, 55);
      expect(ava.ppg, 50);
      expect(ava.games, 8);
      expect(ava.own, 31);
    });

    test('every status parses; Lines/BonusProv omitted → empty/false', () {
      final players = livePlayersFromNode({
        'a': playerNode(st: 'pending', pts: 0),
        'b': playerNode(st: 'live'),
        'c': playerNode(st: 'done'),
        'd': playerNode(st: 'out', pts: 0),
      });
      expect(players['a']!.st, LivePlayerStatus.pending);
      expect(players['b']!.st, LivePlayerStatus.live);
      expect(players['c']!.st, LivePlayerStatus.done);
      expect(players['d']!.st, LivePlayerStatus.out);
      expect(players['a']!.lines, isEmpty);
      expect(players['a']!.bonusProv, isFalse);
    });

    test('a player the server could not fully describe is skipped (the '
        'official numbers keep showing), never defaulted to 0', () {
      final noTotal = playerNode()..remove('Total');
      final badStatus = playerNode(st: 'warming-up');
      final players = livePlayersFromNode({
        'ok': playerNode(),
        'noTotal': noTotal,
        'badStatus': badStatus,
        'junk': 5,
      });
      expect(players.keys, ['ok']);
      expect(livePlayersFromNode(null), isEmpty);
    });

    test('string numbers tolerated; junk lines skipped', () {
      final players = livePlayersFromNode({
        'a': playerNode(lines: {
          'goals': {'N': '2', 'P': '8'},
          'bad': 'nope',
        }),
      });
      expect(players['a']!.lines.keys, ['goals']);
      expect(players['a']!.lines['goals'], (n: 2, p: 8));
    });
  });

  group('liveTeamOfWeekFromNode', () {
    test('parses the list, GK then DEF then ATT order kept', () {
      final team = liveTeamOfWeekFromNode([
        {'name': 'Gus Keeper', 'position': 'GK', 'points': 9},
        {'name': 'Deb Rock', 'position': 'DEF', 'points': 7},
        {'name': 'Ava Striker', 'position': 'ATT', 'points': 14},
      ])!;
      expect(team.players.map((p) => p.name),
          ['Gus Keeper', 'Deb Rock', 'Ava Striker']);
      expect(team.players.first.position, FantasyPosition.gk);
      expect(team.players.last.points, 14);
    });

    test('an index-keyed map is tolerated; empty / absent → null', () {
      final team = liveTeamOfWeekFromNode({
        '0': {'name': 'Gus Keeper', 'position': 'GK', 'points': 9},
        '1': {'name': 'Ava Striker', 'position': 'ATT', 'points': 14},
      })!;
      expect(team.players, hasLength(2));
      expect(liveTeamOfWeekFromNode(null), isNull);
      expect(liveTeamOfWeekFromNode([]), isNull);
      expect(liveTeamOfWeekFromNode('nope'), isNull);
    });
  });

  group('liveSquadFromNode', () {
    test('round-trips T, W and the slots in pick order (s only when '
        'auto-subbed in)', () {
      final squad = liveSquadFromNode({
        'T': 123,
        'W': 12,
        'Slots': [
          {'p': 'Ava Striker', 'c': 80, 'x': 2},
          {'p': 'Deb Rock', 'c': 30, 'x': 1, 's': true},
        ],
      })!;
      expect(squad.totalTenths, 123);
      expect(squad.week, 12);
      expect(squad.slots, hasLength(2));
      expect(squad.slots[0].playerId, 'Ava Striker');
      expect(squad.slots[0].countedTenths, 80);
      expect(squad.slots[0].multiplier, 2);
      expect(squad.slots[0].autoSubbedIn, isFalse);
      expect(squad.slots[1].autoSubbedIn, isTrue);
    });

    test('Slots as an index-keyed map; an invalid squad has no Slots', () {
      final coerced = liveSquadFromNode({
        'T': 10,
        'W': 1,
        'Slots': {
          '0': {'p': 'A', 'c': 10, 'x': 1},
          '1': {'p': 'B', 'c': 0, 'x': 0},
        },
      })!;
      expect(coerced.slots.map((s) => s.playerId), ['A', 'B']);
      expect(coerced.slots[1].multiplier, 0);

      // RTDB drops the empty list: readers default it.
      final invalid = liveSquadFromNode({'T': 0, 'W': 0})!;
      expect(invalid.slots, isEmpty);
      expect((invalid.totalTenths, invalid.week), (0, 0));
    });

    test('negative net tenths (transfer hits) round-trip; a squad with no '
        'total is no squad; malformed slots are skipped', () {
      final hit = liveSquadFromNode({
        'T': -40,
        'W': -4,
        'Slots': [
          {'p': 'A', 'c': 20, 'x': 1},
          {'c': 20, 'x': 1}, // no player
          {'p': 'B', 'x': 1}, // no counted tenths
          'junk',
        ],
      })!;
      expect(hit.totalTenths, -40);
      expect(hit.week, -4);
      expect(hit.slots.map((s) => s.playerId), ['A']);
      expect(liveSquadFromNode(null), isNull);
      expect(liveSquadFromNode({'W': 1}), isNull);
      expect(liveSquadFromNode('x'), isNull);
    });
  });

  group('the tombstone', () {
    test('Meta only, no Board/Players/TeamOfWeek, parses and overlays '
        'nothing', () {
      final live = liveStateFromNodes(
        meta: tombstoneMetaNode(),
        board: null,
        players: null,
        teamOfWeek: null,
      );
      expect(live.meta!.state, LiveState.settled);
      expect(live.board, isEmpty);
      expect(live.players, isEmpty);
      expect(live.teamOfWeek, isNull);
      expect(live.liveWeek, isNull);

      final boards = officialBoards();
      expect(identical(mergeLiveLeaderboards(boards, live), boards), isTrue);
      const totals = {'Ava': FantasyPlayerTotals(points: 9)};
      expect(identical(mergeLivePlayerTotals(totals, live), totals), isTrue);
      const teams = <int, FantasyDreamTeam>{};
      expect(identical(mergeLiveDreamTeams(teams, live), teams), isTrue);
      const weeks = <int, PlayerWeekStats>{};
      expect(
          identical(
              mergeLivePlayerWeekStats(weeks, live, name: 'Ava', weeks: [2]),
              weeks),
          isTrue);
    });

    test('even a stale board under a settled meta overlays nothing', () {
      final live = liveStateOf(
        meta: _settledMeta,
        board: _board,
        players: {'Ava': livePlayer(total: 99)},
      );
      final boards = officialBoards();
      expect(identical(mergeLiveLeaderboards(boards, live), boards), isTrue);
      const totals = {'Ava': FantasyPlayerTotals(points: 9)};
      expect(identical(mergeLivePlayerTotals(totals, live), totals), isTrue);
    });
  });

  // ── Overlays ─────────────────────────────────────────────────────────────

  group('mergeLiveLeaderboards', () {
    test('Overall rows are replaced by the live board (o/r/m, live:true), '
        'sorted by rank', () {
      final merged = mergeLiveLeaderboards(
          officialBoards(), liveStateOf(board: _board));
      expect(merged.overall.map((e) => e.uid), ['u2', 'u1', 'u3']);
      final u2 = merged.overall.first;
      expect((u2.points, u2.rank, u2.movement, u2.live), (45, 1, 1, true));
      final u1 = merged.overall[1];
      expect((u1.points, u1.rank, u1.movement, u1.live), (40, 2, -1, true));
      final u3 = merged.overall[2];
      expect((u3.points, u3.rank, u3.movement), (5, 3, null));
      expect(merged.overall.every((e) => e.live), isTrue);
    });

    test('the live gameweek row set is w/wr, live:true; other weeks are '
        'untouched and not live', () {
      final merged = mergeLiveLeaderboards(
          officialBoards(), liveStateOf(board: _board));
      expect(merged.byWeek.keys, unorderedEquals([1, 2]));
      final live = merged.byWeek[2]!;
      expect(live.map((e) => e.uid), ['u2', 'u1', 'u3']);
      expect((live[0].points, live[0].rank, live[0].live), (25, 1, true));
      expect((live[1].points, live[1].rank), (10, 2));
      expect(live[0].movement, isNull);
      // Week 1 is the official list, byte for byte.
      final official = officialBoards();
      expect(identical(merged.byWeek[1], official.byWeek[1]), isTrue);
      expect(merged.byWeek[1]!.every((e) => !e.live), isTrue);
    });

    test('a manager with no W/WR (not scored this week) is left off the '
        'gameweek rows', () {
      final merged = mergeLiveLeaderboards(
        officialBoards(),
        liveStateOf(board: const {
          'u1': LiveBoardRow(o: 40, r: 1, w: 10, wr: 1),
          'u9': LiveBoardRow(o: 3, r: 2), // joined nothing this week
        }),
      );
      expect(merged.byWeek[2]!.map((e) => e.uid), ['u1']);
      expect(merged.overall.map((e) => e.uid), ['u1', 'u9']);
    });

    test('rankHistory[uid][gw] = r with a live flag on that point only', () {
      final merged = mergeLiveLeaderboards(
          officialBoards(), liveStateOf(board: _board));
      expect(merged.rankHistory['u1'], {1: 1, 2: 2});
      expect(merged.rankHistory['u2'], {1: 2, 2: 1});
      expect(merged.rankHistory['u3'], {2: 3}); // brand-new manager
      expect(merged.isLiveRankPoint('u1', 2), isTrue);
      expect(merged.isLiveRankPoint('u1', 1), isFalse);
      expect(merged.isLiveRankPoint('u3', 2), isTrue);
      expect(merged.isLiveRankPoint('nobody', 2), isFalse);
      // The official map is not mutated.
      expect(officialBoards().rankHistory['u1'], {1: 1});
    });

    test('an empty live board overlays nothing (the official board keeps '
        'showing)', () {
      final boards = officialBoards();
      expect(
          identical(mergeLiveLeaderboards(boards, liveStateOf()), boards),
          isTrue);
    });

    test('the first live week of a season: no official board at all, the '
        'live board stands alone', () {
      final merged = mergeLiveLeaderboards(
          FantasyLeaderboards.empty, liveStateOf(board: _board));
      expect(merged.isEmpty, isFalse);
      expect(merged.overall, hasLength(3));
      expect(merged.byWeek.keys, [2]);
    });

    test('the official entries default to live:false and no live rank '
        'points', () {
      final boards = officialBoards();
      expect(boards.overall.every((e) => !e.live), isTrue);
      expect(boards.isLiveRankPoint('u1', 1), isFalse);
    });
  });

  group('mergeLivePlayerTotals', () {
    test('live players replace points/form/ppg/games/ownership with '
        'live:true; the rest keep the official row', () {
      final official = {
        'Ava': const FantasyPlayerTotals(
            points: 30,
            ownershipPct: 20,
            formTenths: 40,
            ppgTenths: 35,
            games: 6),
        'Deb': const FantasyPlayerTotals(points: 10, ownershipPct: 5),
      };
      final merged = mergeLivePlayerTotals(
        official,
        liveStateOf(players: {
          'Ava': livePlayer(
              total: 42, form: 63, ppg: 52, games: 7, own: 33, pts: 12),
        }),
      )!;
      final ava = merged['Ava']!;
      expect(ava.points, 42);
      expect(ava.formTenths, 63);
      expect(ava.ppgTenths, 52);
      expect(ava.games, 7);
      expect(ava.ownershipPct, 33.0);
      expect(ava.live, isTrue);
      // Deb is not on the live feed: the official row, untouched.
      expect(identical(merged['Deb'], official['Deb']), isTrue);
      expect(merged['Deb']!.live, isFalse);
      // The official map is not mutated.
      expect(official['Ava']!.points, 30);
    });

    test('a first live week with no official totals yet shows the live '
        'ones (null → map)', () {
      final merged = mergeLivePlayerTotals(
        null,
        liveStateOf(players: {'Ava': livePlayer(total: 12, games: 1)}),
      )!;
      expect(merged['Ava']!.points, 12);
      expect(merged['Ava']!.live, isTrue);
    });

    test('no live players → the official map, even null', () {
      expect(mergeLivePlayerTotals(null, liveStateOf()), isNull);
      const official = {'Ava': FantasyPlayerTotals(points: 9)};
      expect(
          identical(mergeLivePlayerTotals(official, liveStateOf()), official),
          isTrue);
    });
  });

  group('mergeLiveDreamTeams', () {
    final live = FantasyDreamTeam(players: const [
      FantasyDreamTeamPlayer(
          name: 'Ava', position: FantasyPosition.att, points: 14),
    ]);

    test('[gw] = the live Team of the Week (live:true); other weeks '
        'untouched', () {
      final official = {
        1: const FantasyDreamTeam(players: [
          FantasyDreamTeamPlayer(
              name: 'Old', position: FantasyPosition.gk, points: 5),
        ]),
        2: const FantasyDreamTeam(players: [
          FantasyDreamTeamPlayer(
              name: 'Stale', position: FantasyPosition.gk, points: 1),
        ]),
      };
      final merged = mergeLiveDreamTeams(
          official, liveStateOf(teamOfWeek: live));
      expect(merged[2]!.players.single.name, 'Ava');
      expect(merged[2]!.live, isTrue);
      expect(merged[2]!.computedAtMs, 0); // the meta's UpdatedAt (default 0)
      expect(identical(merged[1], official[1]), isTrue);
      expect(merged[1]!.live, isFalse);
      expect(official[2]!.players.single.name, 'Stale'); // not mutated
    });

    test('ComputedAt follows the live meta\'s UpdatedAt', () {
      final merged = mergeLiveDreamTeams(
        const {},
        liveStateOf(
          meta: const LiveMeta(
              gw: 3, state: LiveState.live, updatedAt: 1234),
          teamOfWeek: live,
        ),
      );
      expect(merged.keys, [3]);
      expect(merged[3]!.computedAtMs, 1234);
    });

    test('no live team (voided week / nobody played) → the official map',
        () {
      final official = {
        2: const FantasyDreamTeam(players: [
          FantasyDreamTeamPlayer(
              name: 'Keep', position: FantasyPosition.gk, points: 1),
        ]),
      };
      expect(identical(mergeLiveDreamTeams(official, liveStateOf()), official),
          isTrue);
    });
  });

  group('mergeLivePlayerWeekStats', () {
    final ava = livePlayer(
      pts: 12,
      st: LivePlayerStatus.live,
      lines: {
        'plays': (n: 1, p: 2),
        'goals': (n: 2, p: 8),
        'bonus': (n: 2, p: 2),
      },
      bonusProv: true,
    );

    test('the live gameweek: Pts, Lines, GP (= plays.n), Played, live:true, '
        'bonusProvisional', () {
      final merged = mergeLivePlayerWeekStats(
        const {},
        liveStateOf(players: {'Ava': ava}),
        name: 'Ava',
        weeks: [1, 2],
      );
      final w2 = merged[2]!;
      expect(w2.points, 12);
      expect(w2.gamesPlayed, 1);
      expect(w2.played, isTrue);
      expect(w2.live, isTrue);
      expect(w2.bonusProvisional, isTrue);
      expect(w2.voided, isFalse);
      expect(w2.games, isEmpty);
      expect(w2.lines['goals']!.count, 2);
      expect(w2.lines['goals']!.points, 8);
      expect(w2.lines['plays']!.count, 1);
      expect(merged.containsKey(1), isFalse);
    });

    test('Played = done or live: pending and out are not', () {
      for (final (st, played) in [
        (LivePlayerStatus.pending, false),
        (LivePlayerStatus.live, true),
        (LivePlayerStatus.done, true),
        (LivePlayerStatus.out, false),
      ]) {
        final merged = mergeLivePlayerWeekStats(
          const {},
          liveStateOf(players: {'Ava': livePlayer(st: st)}),
          name: 'Ava',
          weeks: [2],
        );
        expect(merged[2]!.played, played, reason: '$st');
        expect(merged[2]!.gamesPlayed, 0, reason: '$st (no plays line)');
        expect(merged[2]!.bonusProvisional, isFalse);
      }
    });

    test('other gameweeks stay official; a week the caller did not ask for '
        'is not added', () {
      const official = {
        1: PlayerWeekStats(
            points: 5,
            played: true,
            gamesPlayed: 1,
            games: [],
            lines: {},
            voided: false),
      };
      final merged = mergeLivePlayerWeekStats(
        official,
        liveStateOf(players: {'Ava': ava}),
        name: 'Ava',
        weeks: [1], // live week 2 not requested
      );
      expect(identical(merged, official), isTrue);
      expect(merged[1]!.live, isFalse);
    });

    test('a live record over an official one keeps its schedule and '
        'voided flag', () {
      final official = {
        2: const PlayerWeekStats(
            points: 3,
            played: true,
            gamesPlayed: 1,
            games: [PlayerWeekGame(vs: 'Kings', goalsFor: 2, goalsAgainst: 1)],
            lines: {},
            voided: true),
      };
      final merged = mergeLivePlayerWeekStats(
        official,
        liveStateOf(players: {'Ava': ava}),
        name: 'Ava',
        weeks: [2],
      );
      expect(merged[2]!.points, 12);
      expect(merged[2]!.games.single.vs, 'Kings');
      expect(merged[2]!.voided, isTrue);
      expect(official[2]!.points, 3); // not mutated
    });

    test('a player the live feed does not carry → official', () {
      const official = <int, PlayerWeekStats>{};
      final merged = mergeLivePlayerWeekStats(
        official,
        liveStateOf(players: {'Ava': ava}),
        name: 'Somebody Else',
        weeks: [2],
      );
      expect(identical(merged, official), isTrue);
    });

    test('official records default to live:false, bonusProvisional:false',
        () {
      final stats = playerWeekStatsFromNode({'Pts': 3})!;
      expect(stats.live, isFalse);
      expect(stats.bonusProvisional, isFalse);
    });
  });

  // ── The feed ─────────────────────────────────────────────────────────────

  group('FantasyLiveFeed.watch', () {
    late Map<String, StreamController<Object?>> children;
    late List<String> asked;
    late List<FantasyLiveState> out;
    StreamSubscription<FantasyLiveState>? sub;

    Stream<Object?> childStream(String child) {
      asked.add(child);
      return children[child]!.stream;
    }

    setUp(() {
      children = {
        for (final c in const ['Meta', 'Board', 'Players', 'TeamOfWeek'])
          c: StreamController<Object?>.broadcast(),
      };
      asked = [];
      out = [];
      sub = null;
    });

    tearDown(() async {
      await sub?.cancel();
      for (final c in children.values) {
        await c.close();
      }
    });

    Future<void> listen(String sport, String season) async {
      sub = FantasyLiveFeed.watch(sport, season, childStream: childStream)
          .listen(out.add);
      await pumpEventQueue();
    }

    test('streams exactly four children — never the whole Live node (the '
        'phone must not download every manager\'s Squads)', () async {
      await listen('Futsal', 'F-4children');
      expect(asked,
          unorderedEquals(['Meta', 'Board', 'Players', 'TeamOfWeek']));
      expect(asked, isNot(contains('Squads')));
      expect(asked, isNot(contains('')));
    });

    test('nothing is emitted until all four children answered (no empty '
        'board, no piecemeal frame), then a full state', () async {
      await listen('Futsal', 'F-gate');
      children['Meta']!.add(liveMetaNode());
      children['Board']!.add({
        'u1': {'O': 40, 'R': 1, 'W': 10, 'WR': 1},
      });
      children['Players']!.add({'Ava': playerNode()});
      await pumpEventQueue();
      expect(out, isEmpty);

      children['TeamOfWeek']!.add([
        {'name': 'Ava', 'position': 'ATT', 'points': 14},
      ]);
      await pumpEventQueue();
      expect(out, hasLength(1));
      final live = out.single;
      expect(live.meta!.gw, 2);
      expect(live.liveWeek, 2);
      expect(live.board['u1']!.o, 40);
      expect(live.players['Ava']!.total, 40);
      expect(live.teamOfWeek!.players.single.name, 'Ava');
    });

    test('an absent Live node answers four nulls: a state with no live '
        'week', () async {
      await listen('Futsal', 'F-absent');
      for (final c in children.values) {
        c.add(null);
      }
      await pumpEventQueue();
      expect(out, hasLength(1));
      expect(out.single.meta, isNull);
      expect(out.single.liveWeek, isNull);
      expect(out.single.board, isEmpty);
    });

    test('the tombstone arrives as Meta only (Board/Players null) and the '
        'state overlays nothing', () async {
      await listen('Futsal', 'F-tomb');
      children['Meta']!.add(tombstoneMetaNode());
      children['Board']!.add(null);
      children['Players']!.add(null);
      children['TeamOfWeek']!.add(null);
      await pumpEventQueue();
      expect(out.single.meta!.state, LiveState.settled);
      expect(out.single.liveWeek, isNull);
    });

    test('each later change re-emits the combined state (live → settled '
        'hand-over)', () async {
      await listen('Futsal', 'F-handover');
      children['Meta']!.add(liveMetaNode());
      children['Board']!.add({
        'u1': {'O': 40, 'R': 1},
      });
      children['Players']!.add(null);
      children['TeamOfWeek']!.add(null);
      await pumpEventQueue();
      expect(out.last.liveWeek, 2);

      // Finalize tombstones the node: Meta replaced, the rest removed.
      children['Meta']!.add(tombstoneMetaNode());
      await pumpEventQueue();
      expect(out.last.liveWeek, isNull);
      children['Board']!.add(null);
      await pumpEventQueue();
      expect(out.last.board, isEmpty);
      expect(out.last.liveWeek, isNull);
    });

    test('a stream error means NO live (never an empty board or a fake '
        'value), and the dead feed stays quiet', () async {
      await listen('Futsal', 'F-error');
      children['Meta']!.add(liveMetaNode());
      children['Board']!.add({
        'u1': {'O': 40, 'R': 1},
      });
      children['Players']!.add(null);
      children['TeamOfWeek']!.add(null);
      await pumpEventQueue();
      expect(out.last.liveWeek, 2);

      children['Players']!.addError(StateError('permission-denied'));
      await pumpEventQueue();
      expect(out.last.meta, isNull);
      expect(out.last.liveWeek, isNull);
      expect(out.last.board, isEmpty);
      expect(out.last.players, isEmpty);
      final frames = out.length;

      // Late data from the surviving children changes nothing.
      children['Meta']!.add(liveMetaNode(gw: 3));
      await pumpEventQueue();
      expect(out, hasLength(frames));
      // ...and a failed feed never seeds the next visit.
      expect(FantasyLiveFeed.cachedState('Futsal', 'F-error'), isNull);
    });

    test('an error before the first answer is "no live" as well', () async {
      await listen('Futsal', 'F-error-first');
      children['Meta']!.addError(StateError('denied'));
      await pumpEventQueue();
      expect(out, hasLength(1));
      expect(out.single.liveWeek, isNull);
    });

    test('a feed that cannot even be created (no Firebase app) is "no '
        'live", not a throw', () async {
      sub = FantasyLiveFeed.watch('Futsal', 'F-throws',
          childStream: (_) => throw StateError('no app')).listen(out.add);
      await pumpEventQueue();
      expect(out, hasLength(1));
      expect(out.single.liveWeek, isNull);
    });

    test('the last real state seeds a revisit before anything answers',
        () async {
      await listen('Futsal', 'F-seed');
      children['Meta']!.add(liveMetaNode());
      for (final c in ['Board', 'Players', 'TeamOfWeek']) {
        children[c]!.add(null);
      }
      await pumpEventQueue();
      expect(FantasyLiveFeed.cachedState('Futsal', 'F-seed'), isNotNull);
      await sub!.cancel();

      final again = <FantasyLiveState>[];
      final fresh = StreamController<Object?>.broadcast();
      final sub2 = FantasyLiveFeed.watch('Futsal', 'F-seed',
          childStream: (_) => fresh.stream).listen(again.add);
      await pumpEventQueue();
      expect(again, hasLength(1), reason: 'the seed, instantly');
      expect(again.single.liveWeek, 2);
      await sub2.cancel();
      await fresh.close();
    });

    test('cancelling the stream cancels the four child listeners', () async {
      await listen('Futsal', 'F-cancel');
      expect(children.values.every((c) => c.hasListener), isTrue);
      await sub!.cancel();
      expect(children.values.any((c) => c.hasListener), isFalse);
    });

    test('sign-out clears the live cache', () async {
      await listen('Futsal', 'F-signout');
      for (final c in children.values) {
        c.add(null);
      }
      await pumpEventQueue();
      expect(FantasyLiveFeed.cachedState('Futsal', 'F-signout'), isNotNull);

      clearFantasySessionState();

      expect(FantasyLiveFeed.cachedState('Futsal', 'F-signout'), isNull);
    });
  });

  // ── combineLatest2 (the wrappers' join of official ⊕ live) ───────────────

  group('combineLatest2', () {
    test('emits only once BOTH sides answered, then on every change of '
        'either (no pop of official-then-live)', () async {
      final a = StreamController<int>();
      final b = StreamController<String>();
      final out = <String>[];
      final sub = combineLatest2<int, String, String>(
          a.stream, b.stream, (x, y) => '$x$y').listen(out.add);

      a.add(1);
      await pumpEventQueue();
      expect(out, isEmpty);
      b.add('x');
      await pumpEventQueue();
      expect(out, ['1x']);
      a.add(2);
      b.add('y');
      await pumpEventQueue();
      expect(out, ['1x', '2x', '2y']);
      await sub.cancel();
    });

    test('errors are forwarded; cancel cancels both sides; completes when '
        'both complete', () async {
      final a = StreamController<int>();
      final b = StreamController<int>();
      final out = <int>[];
      final errors = <Object>[];
      var done = false;
      final sub = combineLatest2<int, int, int>(
              a.stream, b.stream, (x, y) => x + y)
          .listen(out.add, onError: errors.add, onDone: () => done = true);
      a.add(1);
      b.add(2);
      a.addError(StateError('official failed'));
      await pumpEventQueue();
      expect(out, [3]);
      expect(errors, hasLength(1));

      await a.close();
      await pumpEventQueue();
      expect(done, isFalse);
      await b.close();
      await pumpEventQueue();
      expect(done, isTrue);
      await sub.cancel();

      final c = StreamController<int>();
      final d = StreamController<int>();
      final sub2 =
          combineLatest2<int, int, int>(c.stream, d.stream, (x, y) => x)
              .listen((_) {});
      await pumpEventQueue();
      expect(c.hasListener && d.hasListener, isTrue);
      await sub2.cancel();
      expect(c.hasListener || d.hasListener, isFalse);
    });
  });
}
