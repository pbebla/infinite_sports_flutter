// P3d — pure logic behind the Leaderboards tab, mini-leagues and the squad
// viewer: row composition with the Managers → PublicProfiles name fallback
// (flagged names never shown), movement arrows, code generation/normalizing/
// matching, member ranking with absent totals, and the published-vs-history
// week fallback (spec §9).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';

FantasyLeaderboardEntry entry(String uid, int points,
        {int? rank, int? movement}) =>
    FantasyLeaderboardEntry(
        uid: uid, points: points, rank: rank, movement: movement);

FantasyManager manager(String name, {bool flagged = false}) =>
    FantasyManager(teamName: name, nameFlagged: flagged);

PublicProfile profile(String uid, String first, String last, {String url = ''}) =>
    PublicProfile(uid: uid, firstName: first, lastName: last, profileUrl: url);

FantasyMiniLeague league({
  String id = 'L1',
  String name = 'The League',
  String code = 'ABC234',
  String owner = 'u1',
  Set<String> members = const {'u1'},
}) =>
    FantasyMiniLeague(
        id: id, name: name, code: code, ownerUid: owner, memberUids: members);

FantasySquad squad(String gk) => FantasySquad(
      picks: [
        SquadPick(playerId: gk, position: FantasyPosition.gk, priceTenths: 50),
      ],
      captainId: gk,
      viceId: gk,
    );

void main() {
  group('managerDisplayName', () {
    final managers = {
      'named': manager('Gold Rush'),
      'flagged': manager('Rude FC', flagged: true),
      'both': manager('Top Cats'),
    };
    final profiles = {
      'flagged': profile('flagged', 'Pat', 'Lee'),
      'profiled': profile('profiled', 'Sam', 'Cruz'),
      'both': profile('both', 'Zoe', 'Park'),
    };

    test('no real name available → the team name alone', () {
      expect(
          managerDisplayName(
              uid: 'named', managers: managers, profiles: profiles),
          'Gold Rush');
    });

    test('round 3: the manager\'s REAL name is the primary line when known',
        () {
      expect(
          managerDisplayName(
              uid: 'both', managers: managers, profiles: profiles),
          'Zoe Park');
    });

    test('a FLAGGED name is never shown — profile name instead', () {
      expect(
          managerDisplayName(
              uid: 'flagged', managers: managers, profiles: profiles),
          'Pat Lee');
    });

    test('no manager entry falls back to the profile, then the neutral '
        'label', () {
      expect(
          managerDisplayName(
              uid: 'profiled', managers: managers, profiles: profiles),
          'Sam Cruz');
      expect(
          managerDisplayName(uid: 'ghost', managers: managers, profiles: profiles),
          'Unnamed manager');
    });
  });

  group('managerNames (round 3 — two-line cell data)', () {
    test('real name + clean team name: both resolved', () {
      final names = managerNames(
        uid: 'u1',
        managers: {'u1': manager('Top Cats')},
        profiles: {'u1': profile('u1', 'Zoe', 'Park')},
      );
      expect(names.realName, 'Zoe Park');
      expect(names.teamName, 'Top Cats');
    });

    test('Review Focus 5: a manager with no PublicProfiles entry (the fake '
        'test managers) → team name only', () {
      final names = managerNames(
        uid: 'test-01',
        managers: {'test-01': manager('Fake FC 1')},
        profiles: const {},
      );
      expect(names.realName, isNull);
      expect(names.teamName, 'Fake FC 1');
    });

    test('a half-known real name still counts; a blank one does not', () {
      final first = managerNames(
        uid: 'u1',
        managers: const {},
        profiles: {'u1': profile('u1', 'Zoe', '')},
      );
      expect(first.realName, 'Zoe');
      final blank = managerNames(
        uid: 'u1',
        managers: const {},
        profiles: {'u1': profile('u1', ' ', '')},
      );
      expect(blank.realName, isNull);
    });

    test('FLAGGED team name is dropped, the real name stays', () {
      final names = managerNames(
        uid: 'u1',
        managers: {'u1': manager('Rude FC', flagged: true)},
        profiles: {'u1': profile('u1', 'Pat', 'Lee')},
      );
      expect(names.realName, 'Pat Lee');
      expect(names.teamName, isNull);
    });

    test('flagged AND no profile, or nothing at all → neither name', () {
      final flagged = managerNames(
        uid: 'u1',
        managers: {'u1': manager('Rude FC', flagged: true)},
        profiles: const {},
      );
      expect(flagged.realName, isNull);
      expect(flagged.teamName, isNull);
      final ghost =
          managerNames(uid: 'ghost', managers: const {}, profiles: const {});
      expect(ghost.realName, isNull);
      expect(ghost.teamName, isNull);
    });
  });

  group('composeLeaderboardRows', () {
    test('resolves names/photos, marks self, keeps parser order', () {
      final rows = composeLeaderboardRows(
        entries: [
          entry('u1', 40, rank: 1, movement: 2),
          entry('u2', 30, rank: 2, movement: 0),
          entry('u3', 20),
        ],
        managers: {'u1': manager('Top Team'), 'u2': manager('Chasers')},
        profiles: {'u3': profile('u3', 'Ada', 'Ng', url: 'http://p/3.jpg')},
        selfUid: 'u2',
      );
      expect(rows.map((r) => r.name), ['Top Team', 'Chasers', 'Ada Ng']);
      expect(rows.map((r) => r.displayRank), [1, 2, 3]);
      expect(rows[0].movement, 2);
      expect(rows[1].isSelf, isTrue);
      expect(rows[2].isSelf, isFalse);
      expect(rows[2].photoUrl, 'http://p/3.jpg');
      expect(rows[0].photoUrl, isNull);
    });

    test('showMovement false drops arrows (the Gameweek scope)', () {
      final rows = composeLeaderboardRows(
        entries: [entry('u1', 10, rank: 1, movement: 3)],
        managers: const {},
        profiles: const {},
        selfUid: '',
        showMovement: false,
      );
      expect(rows.single.movement, isNull);
      expect(rows.single.isSelf, isFalse);
    });

    test('round 3: rows carry the real name (primary) with the team name '
        'under it; no real name → team name alone; neither → "Unnamed '
        'manager"; flagged team names never reach a row', () {
      final rows = composeLeaderboardRows(
        entries: [
          entry('both', 50, rank: 1),
          entry('test-01', 40, rank: 2),
          entry('flagged', 30, rank: 3),
          entry('ghost', 20, rank: 4),
        ],
        managers: {
          'both': manager('Top Cats'),
          'test-01': manager('Fake FC 1'),
          'flagged': manager('Rude FC', flagged: true),
        },
        profiles: {
          'both': profile('both', 'Zoe', 'Park'),
          'flagged': profile('flagged', 'Pat', 'Lee'),
        },
        selfUid: '',
      );
      expect(rows.map((r) => r.name),
          ['Zoe Park', 'Fake FC 1', 'Pat Lee', 'Unnamed manager']);
      expect(rows.map((r) => r.realName), ['Zoe Park', null, 'Pat Lee', null]);
      expect(rows.map((r) => r.teamName), ['Top Cats', 'Fake FC 1', null, null]);
      // The second line: the team name, only UNDER a real name.
      expect(rows.map((r) => r.secondaryName),
          ['Top Cats', null, null, null]);
      // The squad viewer keeps titling itself by the TEAM name (its contract),
      // falling back like the primary line does.
      expect(rows.map((r) => r.viewerTitle),
          ['Top Cats', 'Fake FC 1', 'Pat Lee', 'Unnamed manager']);
    });

    test(
        'a team named exactly like its manager (any case, stray spaces) '
        'shows ONE line, never the name twice', () {
      final rows = composeLeaderboardRows(
        entries: [
          entry('same', 50, rank: 1),
          entry('cased', 40, rank: 2),
          entry('spaced', 30, rank: 3),
          entry('close', 20, rank: 4),
        ],
        managers: {
          'same': manager('Zoe Park'),
          'cased': manager('ADA NG'),
          'spaced': manager('  pat lee  '),
          'close': manager('Sam Fox FC'),
        },
        profiles: {
          'same': profile('same', 'Zoe', 'Park'),
          'cased': profile('cased', 'Ada', 'Ng'),
          'spaced': profile('spaced', 'Pat', 'Lee'),
          'close': profile('close', 'Sam', 'Fox'),
        },
        selfUid: '',
      );
      expect(rows.map((r) => r.name),
          ['Zoe Park', 'Ada Ng', 'Pat Lee', 'Sam Fox']);
      expect(rows.map((r) => r.secondaryName), [null, null, null, 'Sam Fox FC']);
      // The team name itself is untouched (the viewer still titles by it).
      expect(rows.map((r) => r.viewerTitle),
          ['Zoe Park', 'ADA NG', 'pat lee', 'Sam Fox FC']);
    });
  });

  group('movement', () {
    test('direction and glyphs', () {
      expect(movementDirection(2), MovementDirection.up);
      expect(movementDirection(-1), MovementDirection.down);
      expect(movementDirection(0), MovementDirection.none);
      expect(movementDirection(null), MovementDirection.none);
      expect(movementGlyph(MovementDirection.up), '▲');
      expect(movementGlyph(MovementDirection.down), '▼');
      expect(movementGlyph(MovementDirection.none), '—');
    });

    test('round 3: the cell label is the arrow + the places moved; absent or '
        '0 → a bare dash', () {
      expect(movementLabel(2), '▲2');
      expect(movementLabel(12), '▲12');
      expect(movementLabel(-1), '▼1');
      expect(movementLabel(-10), '▼10');
      expect(movementLabel(0), '—');
      expect(movementLabel(null), '—');
    });
  });

  // ── Leaderboard extras (follow-up) ──────────────────────────────────────

  LeaderboardRowData row(
    String uid, {
    int points = 0,
    int? movement,
    String? real,
    String? team,
    bool self = false,
    int rank = 1,
  }) =>
      LeaderboardRowData(
        uid: uid,
        realName: real,
        teamName: team,
        points: points,
        displayRank: rank,
        movement: movement,
        isSelf: self,
      );

  group('rank over the season (RankHistory)', () {
    test('rankSeries orders by gameweek; null/empty history → no points', () {
      expect(rankSeries({3: 2, 1: 14, 2: 9}), [
        (gameweek: 1, rank: 14, live: false),
        (gameweek: 2, rank: 9, live: false),
        (gameweek: 3, rank: 2, live: false),
      ]);
      expect(rankSeries(null), isEmpty);
      expect(rankSeries(const {}), isEmpty);
    });

    test('journey label "#start → #now"; none under two weeks', () {
      expect(kRankChartMinWeeks, 2);
      expect(rankJourneyLabel(rankSeries({1: 14, 5: 12, 8: 10})), '#14 → #10');
      expect(rankJourneyLabel(rankSeries({1: 3, 2: 7})), '#3 → #7');
      expect(rankJourneyLabel(rankSeries({4: 3})), isNull);
      expect(rankJourneyLabel(const []), isNull);
    });

    test('screen-reader text lists every week', () {
      expect(rankSeriesSemantics(rankSeries({2: 10, 1: 14})),
          'Your rank by gameweek: GW1 #14, GW2 #10');
    });

    test("a live gameweek's point is flagged live; the others never are", () {
      expect(rankSeries({1: 14, 2: 9, 3: 2}, liveWeeks: {3}), [
        (gameweek: 1, rank: 14, live: false),
        (gameweek: 2, rank: 9, live: false),
        (gameweek: 3, rank: 2, live: true),
      ]);
      // A live week the history does not carry adds no point.
      expect(rankSeries({1: 14}, liveWeeks: {5}), [
        (gameweek: 1, rank: 14, live: false),
      ]);
    });

    test('the journey label uses the live end point as "#now"', () {
      final series = rankSeries({1: 14, 2: 9, 3: 2}, liveWeeks: {3});
      expect(rankJourneyLabel(series), '#14 → #2');
    });

    test("rankSeriesFor reads one manager's line + live flags from the "
        'boards', () {
      const boards = FantasyLeaderboards(
        overall: [],
        byWeek: {},
        rankHistory: {
          'u1': {1: 4, 2: 3},
          'u2': {1: 1, 2: 2},
        },
        liveRankPoints: {
          'u1': {2},
        },
      );
      expect(rankSeriesFor(boards, 'u1'), [
        (gameweek: 1, rank: 4, live: false),
        (gameweek: 2, rank: 3, live: true),
      ]);
      expect(rankSeriesFor(boards, 'u2'), [
        (gameweek: 1, rank: 1, live: false),
        (gameweek: 2, rank: 2, live: false),
      ]);
      expect(rankSeriesFor(boards, 'nobody'), isEmpty);
    });
  });

  group('live boards and moved rows', () {
    test('entriesAreLive: only a live-merged board counts', () {
      expect(entriesAreLive(const []), isFalse);
      expect(entriesAreLive([entry('a', 5, rank: 1)]), isFalse);
      expect(
          entriesAreLive(const [
            FantasyLeaderboardEntry(uid: 'a', points: 5, rank: 1, live: true),
          ]),
          isTrue);
    });

    LeaderboardRowData ranked(String uid, int rank) => LeaderboardRowData(
        uid: uid, points: 10, displayRank: rank, isSelf: false);

    test('a rank number that improved is "up", one that fell is "down"; a '
        'row that held its number is not moved', () {
      final moved = movedRows(
        before: [ranked('a', 1), ranked('b', 2), ranked('c', 3)],
        after: [ranked('a', 2), ranked('b', 1), ranked('c', 3)],
        beforeOrder: const ['a', 'b', 'c'],
        afterOrder: const ['a', 'b', 'c'],
      );
      expect(moved, {
        'a': MovementDirection.down,
        'b': MovementDirection.up,
      });
    });

    test('a re-order (the fan refreshed) moves the rows that changed place, '
        'even though their rank numbers were already updated', () {
      final rows = [ranked('b', 1), ranked('a', 2), ranked('c', 3)];
      final moved = movedRows(
        before: rows,
        after: rows,
        beforeOrder: const ['a', 'b', 'c'],
        afterOrder: const ['b', 'a', 'c'],
      );
      expect(moved, {
        'b': MovementDirection.up,
        'a': MovementDirection.down,
      });
    });

    test('the rank change wins over the place change for the same row', () {
      final moved = movedRows(
        before: [ranked('a', 1), ranked('b', 2)],
        after: [ranked('a', 3), ranked('b', 1)],
        beforeOrder: const ['a', 'b'],
        afterOrder: const ['b', 'a'],
      );
      expect(moved['a'], MovementDirection.down);
      expect(moved['b'], MovementDirection.up);
    });

    test('a first sighting and an unchanged board move nobody', () {
      final rows = [ranked('a', 1), ranked('b', 2)];
      expect(
          movedRows(
              before: const [],
              after: rows,
              beforeOrder: const [],
              afterOrder: const ['a', 'b']),
          isEmpty);
      expect(
          movedRows(
              before: rows,
              after: rows,
              beforeOrder: const ['a', 'b'],
              afterOrder: const ['a', 'b']),
          isEmpty);
    });

    test('a newcomer above shifts the rows below it down by RANK (their '
        'numbers did change) but is not itself "moved"', () {
      final moved = movedRows(
        before: [ranked('a', 1), ranked('b', 2)],
        after: [ranked('n', 1), ranked('a', 2), ranked('b', 3)],
        beforeOrder: const ['a', 'b'],
        afterOrder: const ['n', 'a', 'b'],
      );
      expect(moved, {
        'a': MovementDirection.down,
        'b': MovementDirection.down,
      });
    });
  });

  group('weekly movers (biggest climber / biggest drop)', () {
    test('the largest climb gets the flame, the largest drop the down badge; '
        'nobody else', () {
      final movers = weeklyMovers([
        row('a', movement: 3),
        row('b', movement: 1),
        row('c', movement: -2),
        row('d', movement: -5),
        row('e'),
        row('f', movement: 0),
      ]);
      expect(movers, {
        'a': const WeeklyMover(MoverKind.climber, 3),
        'd': const WeeklyMover(MoverKind.faller, 5),
      });
    });

    test('ties: every tied manager gets the badge', () {
      final movers = weeklyMovers([
        row('a', movement: 4),
        row('b', movement: 4),
        row('c', movement: 2),
        row('d', movement: -3),
        row('e', movement: -3),
      ]);
      expect(movers.keys.toSet(), {'a', 'b', 'd', 'e'});
      expect(movers['a'], const WeeklyMover(MoverKind.climber, 4));
      expect(movers['b'], const WeeklyMover(MoverKind.climber, 4));
      expect(movers['d'], const WeeklyMover(MoverKind.faller, 3));
      expect(movers['e'], const WeeklyMover(MoverKind.faller, 3));
    });

    test('no climb (max ≤ 0) → no flame; no drop (min ≥ 0) → no down badge',
        () {
      // Nobody moved (0 / absent — the first week): no badges at all.
      expect(
          weeklyMovers([row('a', movement: 0), row('b'), row('c')]), isEmpty);
      expect(weeklyMovers(const []), isEmpty);
      // Only drops: just the faller.
      expect(weeklyMovers([row('a', movement: -1), row('b', movement: 0)]),
          {'a': const WeeklyMover(MoverKind.faller, 1)});
      // Only climbs: just the climber.
      expect(weeklyMovers([row('a', movement: 2), row('b', movement: 0)]),
          {'a': const WeeklyMover(MoverKind.climber, 2)});
    });

    test('tooltip / semantics text', () {
      expect(moverLabel(const WeeklyMover(MoverKind.climber, 3)),
          'Biggest climber this week (▲3)');
      expect(moverLabel(const WeeklyMover(MoverKind.faller, 12)),
          'Biggest drop this week (▼12)');
    });
  });

  group('gameweek summary', () {
    test('average (whole) · highest with the top name · you', () {
      // 96 + 45 + 52 + 0 = 193 / 4 = 48.25 -> 48.
      final summary = gameweekSummary([
        row('a', points: 96, team: 'Sweeper Keepers'),
        row('b', points: 45, team: 'Mid Table Mafia'),
        row('me', points: 52, team: 'My Team', self: true),
        row('d', points: 0, team: 'Bench Warmers United'),
      ])!;
      expect(summary.average, 48);
      expect(summary.highest, 96);
      expect(summary.topNames, ['Sweeper Keepers']);
      expect(summary.you, 52);
      expect(summary.label,
          'Average 48 pts · Highest 96 (Sweeper Keepers) · You 52');
    });

    test('the name follows the row rule: real name first, else team name',
        () {
      final summary = gameweekSummary([
        row('a', points: 11, real: 'Zoe Park', team: 'Top Cats'),
        row('b', points: 10, team: 'Others'),
      ])!;
      expect(summary.topNames, ['Zoe Park']);
      // 10.5 rounds half away from zero -> 11.
      expect(summary.average, 11);
      expect(summary.you, isNull);
      expect(summary.label, 'Average 11 pts · Highest 11 (Zoe Park)');
    });

    test('a tie for highest → "(N managers)"', () {
      final summary = gameweekSummary([
        row('a', points: 30, team: 'A'),
        row('b', points: 30, team: 'B'),
        row('c', points: 12, team: 'C'),
      ])!;
      expect(summary.topNames, ['A', 'B']);
      expect(summary.label, 'Average 24 pts · Highest 30 (2 managers)');
    });

    test('negative and voided (all-zero) weeks', () {
      // -3 + -4 = -7 / 2 = -3.5 -> -4 (half away from zero).
      final negative = gameweekSummary([
        row('a', points: -3, team: 'A'),
        row('me', points: -4, team: 'Me', self: true),
      ])!;
      expect(negative.average, -4);
      expect(negative.highest, -3);
      expect(negative.label, 'Average -4 pts · Highest -3 (A) · You -4');
      final voided = gameweekSummary([
        row('a', team: 'A'),
        row('b', team: 'B'),
      ])!;
      expect(voided.label, 'Average 0 pts · Highest 0 (2 managers)');
    });

    test('no rows → no summary', () {
      expect(gameweekSummary(const []), isNull);
    });
  });

  group('mini-league codes', () {
    test('generates 6 chars from the unambiguous A-Z0-9 subset', () {
      final rng = math.Random(7);
      for (var i = 0; i < 50; i++) {
        final code = generateMiniLeagueCode(rng);
        expect(code, hasLength(6));
        expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(code), isTrue,
            reason: '$code must satisfy the rules validation');
        for (final c in code.split('')) {
          expect(miniLeagueCodeAlphabet.contains(c), isTrue);
        }
      }
    });

    test('normalize uppercases and strips spaces/dashes', () {
      expect(normalizeMiniLeagueCode(' ab c-23 4 '), 'ABC234');
    });

    test('completeness check', () {
      expect(isCompleteMiniLeagueCode('abc234'), isTrue);
      expect(isCompleteMiniLeagueCode('AB C-23 4'), isTrue);
      expect(isCompleteMiniLeagueCode('abc23'), isFalse);
      expect(isCompleteMiniLeagueCode('abc2345'), isFalse);
      expect(isCompleteMiniLeagueCode('abc23!'), isFalse);
    });

    test('findMiniLeagueByCode matches case/format-insensitively', () {
      final leagues = [
        league(id: 'a', code: 'ABC234'),
        league(id: 'b', code: 'XYZ789'),
      ];
      expect(findMiniLeagueByCode(leagues, 'xyz 789')!.id, 'b');
      expect(findMiniLeagueByCode(leagues, 'abc-234')!.id, 'a');
      expect(findMiniLeagueByCode(leagues, 'NOPE11'), isNull);
      expect(findMiniLeagueByCode(leagues, ''), isNull);
    });
  });

  group('leaguesForMember', () {
    test('filters to membership, keeps order; empty uid gets none', () {
      final leagues = [
        league(id: 'a', members: {'me', 'u2'}),
        league(id: 'b', members: {'u2'}),
        league(id: 'c', members: {'me'}),
      ];
      expect(leaguesForMember(leagues, 'me').map((l) => l.id), ['a', 'c']);
      expect(leaguesForMember(leagues, ''), isEmpty);
    });
  });

  group('composeMiniLeagueRows', () {
    test('members with totals rank first in Overall order; the rest by '
        'name with 0 pts; local ranks renumber', () {
      final rows = composeMiniLeagueRows(
        league: league(members: {'u1', 'u3', 'zed', 'ann'}),
        overall: [
          entry('u2', 50, rank: 1), // not a member — skipped
          entry('u3', 30, rank: 2, movement: 1),
          entry('u1', 10, rank: 5),
        ],
        managers: {
          'u1': manager('Alpha'),
          'u3': manager('Bravo'),
          'zed': manager('Zed FC'),
          'ann': manager('Ann United'),
        },
        profiles: const {},
        selfUid: 'u1',
      );
      expect(rows.map((r) => r.uid), ['u3', 'u1', 'ann', 'zed']);
      expect(rows.map((r) => r.displayRank), [1, 2, 3, 4]);
      expect(rows.map((r) => r.points), [30, 10, 0, 0]);
      // Movement never shows inside a league.
      expect(rows.map((r) => r.movement), everyElement(isNull));
      expect(rows[1].isSelf, isTrue);
      expect(miniLeagueRankOf('u1', rows), 2);
      expect(miniLeagueRankOf('ghost', rows), isNull);
    });

    test('no Overall totals at all → everyone ranked by name with 0 pts', () {
      final rows = composeMiniLeagueRows(
        league: league(members: {'b', 'a'}),
        overall: const [],
        managers: {'a': manager('Aces'), 'b': manager('Bolts')},
        profiles: const {},
        selfUid: '',
      );
      expect(rows.map((r) => r.name), ['Aces', 'Bolts']);
      expect(rows.map((r) => r.points), [0, 0]);
      expect(rows.map((r) => r.displayRank), [1, 2]);
    });
  });

  group('squad viewer weeks (spec §9)', () {
    test('merge: published overrides history on the same week', () {
      final merged = mergeManagerWeeks(
        history: {1: squad('Hist1'), 2: squad('Hist2')},
        published: {2: squad('Pub2'), 3: squad('Pub3')},
      );
      expect(merged.keys, unorderedEquals([1, 2, 3]));
      expect(merged[2]!.picks.single.playerId, 'Pub2');
    });

    test('default week: current when available, else latest, else null', () {
      expect(defaultViewerWeek(weeks: {1, 2, 3}, currentGw: 3), 3);
      expect(defaultViewerWeek(weeks: {1, 2}, currentGw: 3), 2);
      expect(defaultViewerWeek(weeks: {1, 2}, currentGw: null), 2);
      expect(defaultViewerWeek(weeks: {}, currentGw: 3), isNull);
    });
  });

  group('chipLabel', () {
    test('maps engine ids, null for none/unknown', () {
      expect(chipLabel('tripleCaptain'), 'Triple Captain');
      expect(chipLabel('benchBoost'), 'Bench Boost');
      expect(chipLabel('wildcard'), 'Wildcard');
      expect(chipLabel('freeHit'), 'Free Hit');
      expect(chipLabel(null), isNull);
      expect(chipLabel('??'), isNull);
    });
  });
}
