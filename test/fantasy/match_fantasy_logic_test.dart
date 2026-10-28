// P6 — the match-page Fantasy tab's pure logic: tab gating, attendance
// composition (absent-only node parity with the Manager/functions), the
// per-game points list (market-only, absent omitted, zero-point split,
// ranking), the viewer earning-chip math (captain ×2 / tripleCaptain ×3,
// bench at face value), and the animate-on-genuine-increase session memory.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
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
}
