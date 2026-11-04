// P6 — the match-page Fantasy tab's pure logic: tab gating, attendance
// composition (absent-only node parity with the Manager/functions), the
// per-game points list (market-only, absent omitted, zero-point split,
// ranking), the viewer earning-chip math (captain ×2 / tripleCaptain ×3,
// bench at face value), and the animate-on-genuine-increase session memory.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_logic.dart';

FantasyPlayer player(String name, FantasyPosition pos, {String team = 'Sharks'}) =>
    FantasyPlayer(
      name: name,
      position: pos,
      priceTenths: 60,
      eligible: true,
      teamName: team,
    );

/// A live 2–0 Sharks win in progress: Alex (ATT) goal+assist, Gale (GK) two
/// saves, Dana (DEF) a goal, Yara (DEF) only a yellow (nets 1-1=0 points),
/// Wren (ATT, Wolves) marked absent despite a goal event, Zed (DEF, Wolves)
/// rostered + present with no events.
Map gameNode() => {
      'team1': 'Sharks',
      'team2': 'Wolves',
      'team1score': 2,
      'team2score': 0,
      'status': 1,
      'team1activity': {
        "5'": [
          {'Goal': 'Alex'},
          {'Assist': 'Alex'},
        ],
        "9'": [
          {'Save': 'Gale'},
          {'Save': 'Gale'},
        ],
        "12'": [
          {'Goal': 'Dana'},
          {'Yellow': 'Yara'},
        ],
      },
      'team2activity': {
        "15'": [
          {'Goal': 'Wren'}, // recorded, but Wren is marked absent below
        ],
      },
      'team2attendance': {'Wren': false},
    };

Map<String, List<String>> rosters() => {
      'Sharks': ['Alex', 'Gale', 'Dana', 'Yara'],
      'Wolves': ['Wren', 'Zed'],
    };

List<FantasyPlayer> market() => [
      player('Alex', FantasyPosition.att),
      player('Gale', FantasyPosition.gk),
      player('Dana', FantasyPosition.def),
      player('Yara', FantasyPosition.def),
      player('Wren', FantasyPosition.att, team: 'Wolves'),
      player('Zed', FantasyPosition.def, team: 'Wolves'),
    ];

FantasySquad squad({String captain = 'Alex', String? chip}) => FantasySquad(
      picks: [
        const SquadPick(
            playerId: 'Gale', position: FantasyPosition.gk, priceTenths: 60),
        const SquadPick(
            playerId: 'Dana', position: FantasyPosition.def, priceTenths: 60),
        const SquadPick(
            playerId: 'Wren', position: FantasyPosition.att, priceTenths: 60),
        SquadPick(
            playerId: captain,
            position: FantasyPosition.att,
            priceTenths: 60),
        const SquadPick(
            playerId: 'Zed',
            position: FantasyPosition.def,
            priceTenths: 60,
            bench: true),
      ],
      captainId: captain,
      viceId: 'Gale',
      chip: chip,
    );

void main() {
  final cfg = FantasyConfig.futsalDefault();

  group('showMatchFantasyTab', () {
    test('config + league game -> shown; friendly or no config -> hidden', () {
      expect(showMatchFantasyTab(configExists: true, stage: 'league'), isTrue);
      expect(showMatchFantasyTab(configExists: true, stage: null), isTrue);
      expect(
          showMatchFantasyTab(configExists: true, stage: 'friendly'), isFalse);
      expect(
          showMatchFantasyTab(configExists: false, stage: 'league'), isFalse);
    });
  });

  group('matchStarted', () {
    test('0/absent/garbage = not started; 1 live and 2 final (String too)', () {
      expect(matchStarted(0), isFalse);
      expect(matchStarted(null), isFalse);
      expect(matchStarted('soon'), isFalse);
      expect(matchStarted(1), isTrue);
      expect(matchStarted('2'), isTrue);
    });
  });

  group('attendance composition', () {
    test('absent-only node: false and "false" count, true-ish keys do not', () {
      final absent = absentOnlyFromNode(
          {'Wren': false, 'Kit': 'false', 'Ada': true, 'Bo': 'present'});
      expect(absent, {'Wren': false, 'Kit': false});
    });

    test('list-coerced node tolerated; empty key skipped', () {
      expect(absentOnlyFromNode([false, null, 'false']),
          {'0': false, '2': false});
      expect(absentOnlyFromNode({'': false}), isEmpty);
    });

    test('composeAttendance: roster present by default, absents override, '
        'stray absents stay false', () {
      expect(
        composeAttendance(['Eli', 'Eva'], {'Eva': false, 'Gone': false}),
        {'Eli': true, 'Eva': false, 'Gone': false},
      );
    });
  });

  group('matchGamePoints', () {
    test('both teams scored; absent omitted despite events; present rostered '
        'zero-event player earns the appearance point', () {
      final points = matchGamePoints(
        gameNode: gameNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      // Alex (ATT): plays 1 + goal 4 + assist 3 + clean sheet 2 = 10.
      expect(points['Alex'], 10);
      // Gale (GK): plays 1 + clean sheet 8 + 2 saves 1 = 10.
      expect(points['Gale'], 10);
      // Dana (DEF): plays 1 + goal 6 + clean sheet 5 = 12.
      expect(points['Dana'], 12);
      // Yara (DEF): plays 1 + clean sheet 5 + yellow -1 = 5.
      expect(points['Yara'], 5);
      // Wren: goal event but marked ABSENT -> omitted entirely.
      expect(points.containsKey('Wren'), isFalse);
      // Zed: rostered, present, no events -> plays 1, conceded 2 -> -1 = 0.
      expect(points['Zed'], 0);
    });

    test('non-market players are skipped (no fantasy position to score)', () {
      final points = matchGamePoints(
        gameNode: gameNode(),
        rosterNamesByTeam: rosters(),
        players: market().where((p) => p.name != 'Alex').toList(),
        config: cfg,
      );
      expect(points.containsKey('Alex'), isFalse);
      expect(points['Dana'], 12);
    });
  });

  group('buildMatchFantasyRows', () {
    test('ranked desc with name tiebreak; zero-point present players land in '
        'scoreless; viewer picks highlighted; captain carries the multiplier',
        () {
      final rows = buildMatchFantasyRows(
        gameNode: gameNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
        squad: squad(),
      );
      // Alex and Gale tie on 10 — the name tiebreak puts Alex first.
      expect([for (final r in rows.scored) r.name],
          ['Dana', 'Alex', 'Gale', 'Yara']);
      expect([for (final r in rows.scoreless) r.name], ['Zed']);

      final alex = rows.scored.firstWhere((r) => r.name == 'Alex');
      expect(alex.isViewerPick, isTrue);
      expect(alex.isViewerCaptain, isTrue);
      expect(alex.captainMultiplier, 2);

      final yara = rows.scored.firstWhere((r) => r.name == 'Yara');
      expect(yara.isViewerPick, isFalse);
      expect(yara.captainMultiplier, 1);

      final zed = rows.scoreless.single;
      expect(zed.isViewerPick, isTrue); // bench pick still highlighted
    });

    test('no squad -> plain rows, nothing highlighted', () {
      final rows = buildMatchFantasyRows(
        gameNode: gameNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      expect(rows.scored.any((r) => r.isViewerPick), isFalse);
      expect(rows.scored.any((r) => r.isViewerCaptain), isFalse);
    });
  });

  group('viewerEarningPoints', () {
    Map<String, int> points() => matchGamePoints(
          gameNode: gameNode(),
          rosterNamesByTeam: rosters(),
          players: market(),
          config: cfg,
        );

    test('sums squad members present in the game, captain doubled, bench at '
        'face value, absent member contributes 0', () {
      // Gale 10 + Dana 12 + Wren absent (0) + Alex 10×2 + Zed bench 0 = 42.
      expect(
        viewerEarningPoints(
            gamePointsByName: points(), squad: squad(), config: cfg),
        42,
      );
    });

    test('tripleCaptain chip triples the captain', () {
      // Gale 10 + Dana 12 + Alex 10×3 = 52.
      expect(
        viewerEarningPoints(
            gamePointsByName: points(),
            squad: squad(chip: 'tripleCaptain'),
            config: cfg),
        52,
      );
    });

    test('absent captain contributes 0 — no vice promotion here (finalize '
        'owns it)', () {
      // Captain Wren is absent: only Gale 10 + Dana 12 + Zed 0 count — the
      // ×2 never lands on anyone else (vice Gale is NOT promoted here).
      expect(
        viewerEarningPoints(
            gamePointsByName: points(), squad: squad(captain: 'Wren'),
            config: cfg),
        22,
      );
    });

    test('no squad earns 0', () {
      expect(
        viewerEarningPoints(
            gamePointsByName: points(), squad: null, config: cfg),
        0,
      );
    });
  });

  group('stand-in goalkeeper (spec §7) — same engine path', () {
    test('a saving or marked outfielder scores the keeper lines at GK rates; '
        'goals/assists stay at his position', () {
      final node = gameNode()
        ..['team1keepers'] = {'Yara': true}
        ..['team1activity'] = {
          ...(gameNode()['team1activity'] as Map),
          "30'": [
            {'Save': 'Alex'},
          ],
        };
      final points = matchGamePoints(
        gameNode: node,
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      // Alex (ATT, 1 save -> in goal): plays 1 + goal 4 + assist 3 (ATT
      // rates) + clean sheet 8 (GK rate) = 16 (outfield: 10).
      expect(points['Alex'], 16);
      // Yara (DEF, marked in goal, 0 saves): plays 1 + clean sheet 8 (GK
      // rate) - yellow 1 = 8 (outfield: 5).
      expect(points['Yara'], 8);
      // The listed GK and an outfield DEF are unchanged.
      expect(points['Gale'], 10);
      expect(points['Dana'], 12);
    });
  });

  group('forfeits (spec §8a) — same engine path', () {
    /// Wolves forfeited after the timeline above was captured: 5–0 Sharks,
    /// status Final, forfeitedBy 2. Every recorded event is now stray.
    Map forfeitNode() => gameNode()
      ..['team1score'] = 5
      ..['team2score'] = 0
      ..['status'] = 2
      ..['forfeitedBy'] = 2;

    test('team that showed up: +1 per present rostered player (stray goals '
        'ignored, no clean sheet); forfeiting team omitted entirely', () {
      final points = matchGamePoints(
        gameNode: forfeitNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      // Sharks: Alex/Gale/Dana/Yara each +1 only. Wolves (Wren absent, Zed
      // present) forfeited: nobody listed.
      expect(points, {'Alex': 1, 'Gale': 1, 'Dana': 1, 'Yara': 1});
    });

    test('an absentee on the team that showed up gets nothing (omitted)', () {
      final node = forfeitNode()..['team1attendance'] = {'Yara': false};
      final points = matchGamePoints(
        gameNode: node,
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      expect(points, {'Alex': 1, 'Gale': 1, 'Dana': 1});
    });

    test('rows: "+1" scored rows, nothing scoreless; a forfeiting captain '
        'earns 0 for the viewer', () {
      final rows = buildMatchFantasyRows(
        gameNode: forfeitNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
        squad: squad(captain: 'Wren'),
      );
      expect([for (final r in rows.scored) r.name],
          ['Alex', 'Dana', 'Gale', 'Yara']);
      expect(rows.scored.every((r) => r.points == 1), isTrue);
      expect(rows.scoreless, isEmpty);

      final points = matchGamePoints(
        gameNode: forfeitNode(),
        rosterNamesByTeam: rosters(),
        players: market(),
        config: cfg,
      );
      // squad(captain: 'Wren') picks Gale, Dana, Wren (captain) and the
      // Zed bench: Gale 1 + Dana 1 + Wren (forfeiting team, omitted) 0 +
      // Zed (forfeiting team) 0 = 2 — the ×2 lands on nobody.
      expect(
        viewerEarningPoints(
            gamePointsByName: points,
            squad: squad(captain: 'Wren'),
            config: cfg),
        2,
      );
      // Captain Alex (showed up): Gale 1 + Dana 1 + Wren 0 + Alex 1×2 = 4.
      expect(
        viewerEarningPoints(
            gamePointsByName: points, squad: squad(), config: cfg),
        4,
      );
    });

    test('matchForfeitNote names who forfeited; null on a normal game', () {
      expect(matchForfeitNote(gameNode()), isNull);
      expect(
        matchForfeitNote(forfeitNode()),
        'Wolves forfeited. Sharks players present get +1 for the appearance '
        '— no other points or bonus from this game.',
      );
      expect(
        matchForfeitNote({'forfeitedBy': '1'}),
        'A team forfeited. Players who showed up get +1 for the appearance '
        '— no other points or bonus from this game.',
      );
    });
  });

  group('recordEarningValue (animate on genuine increase only)', () {
    test('first sight returns null; re-delivery of the same value returns it '
        'unchanged; an increase returns the lower previous value', () {
      final store = <String, int>{};
      expect(recordEarningValue(store, 'g1', 12), isNull); // first: no tween
      expect(recordEarningValue(store, 'g1', 12), 12); // reconnect: 12 -> 12
      expect(recordEarningValue(store, 'g1', 18), 12); // genuine increase
      expect(recordEarningValue(store, 'g1', 15), 18); // edit DOWN: no tween
      expect(store['g1'], 15);
      // Independent games never cross-talk.
      expect(recordEarningValue(store, 'g2', 5), isNull);
    });
  });

  // ── Live everywhere (Task 7) ─────────────────────────────────────────────

  group('matchPhase (the header: LIVE or FINAL from the game status)', () {
    test('1 is live, 2 is final, everything else has not started', () {
      expect(matchPhase(1), MatchPhase.live);
      expect(matchPhase(2), MatchPhase.finished);
      expect(matchPhase('1'), MatchPhase.live);
      expect(matchPhase(' 2 '), MatchPhase.finished);
      expect(matchPhase(2.0), MatchPhase.finished);
      expect(matchPhase(0), MatchPhase.notStarted);
      expect(matchPhase(null), MatchPhase.notStarted);
      expect(matchPhase('soon'), MatchPhase.notStarted);
    });

    test('agrees with matchStarted: started = live or final', () {
      for (final s in [0, 1, 2, null, 'x', '1', '2']) {
        expect(matchPhase(s) != MatchPhase.notStarted, matchStarted(s),
            reason: '$s');
      }
    });
  });

  group('gameweekForDate (which gameweek a game belongs to)', () {
    final gws = [
      for (var i = 1; i <= 3; i++)
        Gameweek(
          number: i,
          date: '0${i}152026',
          lockUtc: DateTime.utc(2026, i, 15, 17),
          opensUtc: null,
        ),
    ];

    test('the gameweek whose match day is the game\'s date', () {
      expect(gameweekForDate(gws, '02152026')!.number, 2);
      expect(gameweekForDate(gws, '01152026')!.number, 1);
    });

    test('a date that is not on the schedule belongs to no gameweek', () {
      expect(gameweekForDate(gws, '04152026'), isNull);
      expect(gameweekForDate(const [], '01152026'), isNull);
    });
  });

  group('matchViewerSquad (the squad this game is scored against)', () {
    // GW1 locks Jan 15 17:00 UTC; GW2 Feb 15; GW3 Mar 15.
    final gws = [
      for (var i = 1; i <= 3; i++)
        Gameweek(
          number: i,
          date: '0${i}152026',
          lockUtc: DateTime.utc(2026, i, 15, 17),
          opensUtc: null,
        ),
    ];
    final locked = squad(captain: 'Alex', chip: 'tripleCaptain');
    final saved = squad(captain: 'Dana');
    final earlier = squad(captain: 'Gale');

    MatchViewerSquad pick({
      required int week,
      DateTime? now,
      FantasyLockOverride override = FantasyLockOverride.auto,
      FantasySquad? published,
      HistoryWeek? history,
      FantasySquad? current,
    }) =>
        matchViewerSquad(
          gameweek: gws[week - 1],
          gameweeks: gws,
          lockOverride: override,
          nowUtc: now ?? DateTime.utc(2026, 2, 15, 20),
          published: published,
          history: history,
          current: current,
        );

    HistoryWeek historyOf(FantasySquad? s) =>
        HistoryWeek(slots: const [], squad: s);

    test('a past game uses the squad that was LOCKED that week, not the '
        'squad saved since (the regression)', () {
      final r = pick(week: 1, published: locked, current: saved);
      expect(r.source, MatchSquadSource.lockedSquad);
      expect(r.squad, same(locked));
      expect(r.squad!.captainId, 'Alex');
      expect(r.squad!.chip, 'tripleCaptain');
    });

    test('PublishedPicks wins; History is the fallback; each over the '
        'current squad', () {
      final both = pick(
          week: 1,
          published: locked,
          history: historyOf(earlier),
          current: saved);
      expect(both.squad, same(locked));

      final historyOnly =
          pick(week: 1, history: historyOf(earlier), current: saved);
      expect(historyOnly.source, MatchSquadSource.lockedSquad);
      expect(historyOnly.squad, same(earlier));
    });

    test('a locked week with no locked squad on record has NO viewer squad '
        '(never the current one)', () {
      final r = pick(week: 1, current: saved);
      expect(r.squad, isNull);
      expect(r.source, MatchSquadSource.none);
      // History with nothing readable in it is no squad either.
      expect(pick(week: 1, history: historyOf(null), current: saved).squad,
          isNull);
    });

    test('Squads/<uid> only for a week that has not locked yet', () {
      final r = pick(
          week: 3,
          now: DateTime.utc(2026, 2, 20),
          current: saved);
      expect(r.source, MatchSquadSource.currentSquad);
      expect(r.squad, same(saved));
      // Right up to the lock instant, and not a moment after.
      expect(
          pick(
                  week: 2,
                  now: DateTime.utc(2026, 2, 15, 16, 59),
                  current: saved)
              .source,
          MatchSquadSource.currentSquad);
      expect(
          pick(
                  week: 2,
                  now: DateTime.utc(2026, 2, 15, 17),
                  current: saved)
              .source,
          MatchSquadSource.none);
    });

    test('the owner\'s lock override: "locked" locks the CURRENT gameweek '
        'only', () {
      final now = DateTime.utc(2026, 2, 15, 12); // GW2 is current, unlocked
      expect(
          pick(
                  week: 2,
                  now: now,
                  override: FantasyLockOverride.locked,
                  current: saved)
              .source,
          MatchSquadSource.none);
      // Another, future gameweek is not the current one.
      expect(
          pick(
                  week: 3,
                  now: now,
                  override: FantasyLockOverride.locked,
                  current: saved)
              .source,
          MatchSquadSource.currentSquad);
    });

    test('an "open" override never makes a past week editable again — the '
        'locked squad still wins', () {
      final r = pick(
          week: 1,
          override: FantasyLockOverride.open,
          published: locked,
          current: saved);
      expect(r.squad, same(locked));
      // And with nothing locked on record it is still not the current one.
      expect(
          pick(week: 1, override: FantasyLockOverride.open, current: saved)
              .squad,
          isNull);
    });

    test('an unknown gameweek (not on the schedule) has no viewer squad',
        () {
      final r = matchViewerSquad(
        gameweek: null,
        gameweeks: gws,
        lockOverride: FantasyLockOverride.auto,
        nowUtc: DateTime.utc(2026, 2, 15, 20),
        published: locked,
        current: saved,
      );
      expect(r.squad, isNull);
      expect(r.source, MatchSquadSource.none);
    });
  });

  test('the footnote ends with the My Team sentence, verbatim', () {
    expect(kMatchFootnote,
        endsWith(' Bonus, captain and bench counting show on My Team.'));
    // The existing disclaimer is kept in full.
    expect(
        kMatchFootnote,
        startsWith('Raw game points, live from the capture. Bench weighting, '
            'auto-subs, vice-captain cover and the 3/2/1 bonus are applied '
            'when the gameweek is finalized — your counted week can '
            'differ.'));
  });
}
