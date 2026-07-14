import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';

void main() {
  group('leagueGameId / parseLeagueGameId', () {
    test('round-trips date + index', () {
      final id = leagueGameId('06152026', 2);
      expect(id, '06152026#2');
      final parsed = parseLeagueGameId(id)!;
      expect(parsed.dateKey, '06152026');
      expect(parsed.index, 2);
    });

    test('rejects non-league ids', () {
      expect(parseLeagueGameId('m1'), isNull);
      expect(parseLeagueGameId('06152026#x'), isNull);
    });
  });

  group('leagueMatchFromGameMap', () {
    Map<dynamic, dynamic> baseGame() => {
          'team1': 'Nineveh',
          'team2': 'Babylon',
          'team1score': '3',
          'team2Score': 1,
          'status': 1,
          'Time': '19:30',
          'team1activity': {
            "7'": [
              {'Goal': 'Ashur'},
            ],
          },
          'Clock': {'StartedAt': 1000, 'PausedAccumMs': 0},
          'link': 'https://youtu.be/abc',
        };

    test('maps identity, teams, scores (string OR int), status, clock', () {
      final m = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: baseGame());
      expect(m.id, '06152026#0');
      expect(m.team1Id, 'Nineveh');
      expect(m.team2Id, 'Babylon');
      expect(m.team1Score, 3);
      expect(m.team2Score, 1);
      expect(m.status, 1);
      expect(m.matchStatus.isLive, isTrue);
      expect(m.clock, isNotNull);
      expect(m.clock!.startedAtMs, 1000);
      expect(m.link, 'https://youtu.be/abc');
      expect(m.team1Activity!["7'"], isNotNull);
      expect(m.date, '06152026');
    });

    test('stored Time renders 12h; missing Time falls back to legacy derived',
        () {
      final m = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: baseGame(), startHour: 6);
      expect(m.time, '7:30 PM');
      final legacy = baseGame()..remove('Time');
      final m2 = leagueMatchFromGameMap(
          dateKey: '06152026', index: 2, raw: legacy, startHour: 6);
      expect(m2.time, '8:00PM'); // startHour 6 + index 2, exact legacy text
    });

    test('regular-season games label as League; stages get display names', () {
      final m = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: baseGame());
      expect(m.stage, 'League');
      expect(m.label, 'League');

      final semi = baseGame()..['Stage'] = 'semifinal';
      final ms = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: semi);
      expect(ms.stage, 'semifinal');
      expect(ms.label, 'Semifinal');

      final friendly = baseGame()..['Stage'] = 'friendly';
      final mf = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: friendly);
      expect(mf.label, 'Friendly');

      final champ = baseGame()..['Stage'] = 'final';
      final mc = leagueMatchFromGameMap(
          dateKey: '06152026', index: 0, raw: champ);
      expect(mc.label, 'Championship');
    });

    test('keepers + index-keyed activity maps survive', () {
      final raw = baseGame()
        ..['team1keeper'] = 'Sargon'
        ..['team2activity'] = {
          "12'": {
            '0': {'Save': 'Sargon'},
            '1': {'DPL': 'Ramina'},
          },
        };
      final m =
          leagueMatchFromGameMap(dateKey: '06152026', index: 0, raw: raw);
      expect(m.team1Keeper, 'Sargon');
      expect(m.team2Activity!["12'"], isNotNull);
    });

    test('placeholder team names pass through for bracket rendering', () {
      final raw = baseGame()
        ..['team1'] = 'Winner of SF1'
        ..['team2'] = 'Winner of SF2'
        ..['Stage'] = 'final'
        ..['status'] = 0;
      final m =
          leagueMatchFromGameMap(dateKey: '07202026', index: 0, raw: raw);
      expect(m.team1Id, 'Winner of SF1');
      expect(m.team2Id, 'Winner of SF2');
    });
  });

  group('leagueMatchesFromDateNode', () {
    test('parses List-shaped dates and index-keyed Map dates, skips holes',
        () {
      final node = {
        '06152026': [
          {'team1': 'A', 'team2': 'B', 'team1score': 0, 'team2score': 0, 'status': 0},
          null,
          {'team1': 'C', 'team2': 'D', 'team1score': 0, 'team2score': 0, 'status': 0},
        ],
        '06222026': {
          '1': {'team1': 'E', 'team2': 'F', 'team1score': 0, 'team2score': 0, 'status': 0},
        },
      };
      final matches = leagueMatchesFromDateNode(node);
      expect(matches.length, 3);
      final ids = matches.map((m) => m.id).toSet();
      // Index = the real RTDB position, so the null hole is SKIPPED but the
      // surviving indexes stay addressable (06152026#2, not #1).
      expect(ids, {'06152026#0', '06152026#2', '06222026#1'});
    });

    test('garbage in, empty list out', () {
      expect(leagueMatchesFromDateNode(null), isEmpty);
      expect(leagueMatchesFromDateNode('nope'), isEmpty);
    });

    // watchDateGames (P2.1 day view) wraps ONE date's snapshot value as
    // {dateKey: value} and reuses this adapter — cover both wrapped shapes.
    test('single-date wrapper: list of games parses, missing node is empty',
        () {
      final matches = leagueMatchesFromDateNode({
        '06152026': [
          {'team1': 'A', 'team2': 'B', 'team1score': 1, 'team2score': 0, 'status': 1},
        ],
      });
      expect(matches.length, 1);
      expect(matches.first.id, '06152026#0');
      expect(matches.first.date, '06152026');
      // Date node absent -> snapshot value null -> no matches.
      expect(leagueMatchesFromDateNode({'06152026': null}), isEmpty);
    });
  });

  group('standings adapters', () {
    final teamsNode = {
      'Babylon': {'Wins': 5, 'Draws': 1, 'Losses': 2, 'GP': 8, 'GS': 20, 'GC': 10, 'GD': 10, 'Points': 16},
      'Nineveh': {'Wins': 5, 'Draws': 1, 'Losses': 2, 'GP': 8, 'GS': 25, 'GC': 12, 'GD': 13, 'Points': 16},
      'Ashur FC': {'Wins': 7, 'Draws': 0, 'Losses': 1, 'GP': 8, 'GS': 30, 'GC': 8, 'GD': 22, 'Points': 21},
    };

    test('parses rows + sorts Points desc, GD desc, GS desc', () {
      final rows = leagueStandingsFromTeamsNode(
          'Futsal', teamsNode, {'Ashur FC': 'http://logo/a.png'});
      expect(rows.map((t) => t.name).toList(),
          ['Ashur FC', 'Nineveh', 'Babylon']);
      expect(rows.first.logoUrl, 'http://logo/a.png');
      expect(rows.first.points, 21);
      expect(rows.first.gp, 8);
      expect(rows[1].gd, 13);
    });

    test('missing GP falls back to W+D+L; garbage in, empty out', () {
      final rows = leagueStandingsFromTeamsNode('Futsal', {
        'A': {'Wins': 2, 'Draws': 1, 'Losses': 1, 'GS': 5, 'GC': 3, 'GD': 2, 'Points': 7},
      }, const {});
      expect(rows.single.gp, 4);
      expect(leagueStandingsFromTeamsNode('Futsal', null, const {}), isEmpty);
    });

    test('leagueTeamsById covers standings + logo-only stubs', () {
      final rows = leagueStandingsFromTeamsNode('Futsal', teamsNode, const {});
      final byId = leagueTeamsById(
          rows, {'Akkad': 'http://logo/k.png', 'Babylon': 'http://logo/b.png'});
      expect(byId['Babylon']!.points, 16);
      expect(byId['Babylon']!.logoUrl, 'http://logo/b.png');
      expect(byId['Akkad']!.points, 0); // stub for a team missing from Teams
      expect(byId['Akkad']!.logoUrl, 'http://logo/k.png');
    });
  });

  group('roster adapters + leaders', () {
    final lineups = {
      'Nineveh': {
        'Ashur': {'Goals': 7, 'Assists': 2, 'number': '10', 'UID': 'uid-1'},
        'Sargon': {'Saves': 12, 'CleanSheets': 3, 'Yellow': 1, 'number': '1', 'UID': '0'},
      },
      'Babylon': {
        'Ninos': {'Goals': 7, 'DPL': 4, 'Red': 1, 'number': '7'},
      },
    };

    test('players map league stat keys onto TournamentPlayer.statByName', () {
      final rosters = leagueRostersFromLineupsNode('Futsal', lineups);
      final sargon =
          rosters['Nineveh']!.firstWhere((p) => p.name == 'Sargon');
      expect(sargon.statByName('saves'), 12);
      expect(sargon.statByName('cleanSheets'), 3);
      expect(sargon.statByName('yellowCards'), 1);
      expect(sargon.teamId, 'Nineveh');
      expect(sargon.teamName, 'Nineveh');
      final ninos = rosters['Babylon']!.single;
      expect(ninos.statByName('dpl'), 4);
      expect(ninos.statByName('redCards'), 1);
    });

    test("legacy UID '0' means unlinked -> uid null (profile stays limited)",
        () {
      final rosters = leagueRostersFromLineupsNode('Futsal', lineups);
      final sargon =
          rosters['Nineveh']!.firstWhere((p) => p.name == 'Sargon');
      expect(sargon.uid, isNull);
      final ashur = rosters['Nineveh']!.firstWhere((p) => p.name == 'Ashur');
      expect(ashur.uid, 'uid-1');
    });

    test('rosters sort by shirt number', () {
      final rosters = leagueRostersFromLineupsNode('Futsal', lineups);
      expect(rosters['Nineveh']!.first.name, 'Sargon'); // #1 before #10
    });

    test('sortedLeagueLeaders filters zeros, sorts desc, ties by name', () {
      final rosters = leagueRostersFromLineupsNode('Futsal', lineups);
      final leaders = sortedLeagueLeaders(rosters, 'goals');
      expect(leaders.length, 2);
      // Ashur and Ninos both have 7 -> alphabetical tie-break.
      expect(leaders[0].name, 'Ashur');
      expect(leaders[1].name, 'Ninos');
      expect(sortedLeagueLeaders(rosters, 'cleanSheets').single.name,
          'Sargon');
      expect(sortedLeagueLeaders(rosters, 'assists').single.name, 'Ashur');
    });
  });

  group('leagueTeamStub', () {
    test('carries name + logo with zeroed standings', () {
      final t = leagueTeamStub('Nineveh', 'http://logo/n.png');
      expect(t.id, 'Nineveh');
      expect(t.name, 'Nineveh');
      expect(t.logoUrl, 'http://logo/n.png');
      expect(t.points, 0);
      expect(t.homeColor, isNull);
      expect(t.coachName, isNull);
    });

    test('optionally carries color + coach (empty coach means unset)', () {
      final t = leagueTeamStub('Nineveh', null,
          color: const Color(0xFF1A237E), coach: 'Sargon');
      expect(t.homeColor, const Color(0xFF1A237E));
      expect(t.coachName, 'Sargon');
      expect(leagueTeamStub('Nineveh', null, coach: '  ').coachName, isNull);
    });
  });

  // P2.1 Task A3 read contract:
  // `{sport}/{season}/Teams/{team}/Captain|Color|Coach` — all optional
  // strings maintained by the Manager app.
  group('team metadata (Captain / Color / Coach)', () {
    test('parseLeagueTeamColor: tournament hex formats plus plain hex', () {
      expect(parseLeagueTeamColor('#D00000'), const Color(0xFFD00000));
      expect(parseLeagueTeamColor('D00000'), const Color(0xFFD00000));
      expect(parseLeagueTeamColor(' #1A237E '), const Color(0xFF1A237E));
      expect(parseLeagueTeamColor('801A237E'), const Color(0x801A237E));
      expect(parseLeagueTeamColor('0xFF1A237E'), const Color(0xFF1A237E));
    });

    test('parseLeagueTeamColor fails gracefully to null', () {
      expect(parseLeagueTeamColor(null), isNull);
      expect(parseLeagueTeamColor(''), isNull);
      expect(parseLeagueTeamColor('red'), isNull);
      expect(parseLeagueTeamColor('#12'), isNull);
      expect(parseLeagueTeamColor('#GGGGGG'), isNull);
      expect(parseLeagueTeamColor(12345), isNull);
    });

    test('standings rows carry optional Color + Coach', () {
      final rows = leagueStandingsFromTeamsNode('Futsal', {
        'Nineveh': {
          'Wins': 4, 'Draws': 0, 'Losses': 0, 'Points': 12,
          'Color': '#1A237E',
          'Coach': 'Sargon',
          'Captain': 'Ashur',
        },
        'Babylon': {'Wins': 1, 'Draws': 0, 'Losses': 3, 'Points': 3},
      }, const {});
      final nineveh = rows.firstWhere((t) => t.id == 'Nineveh');
      expect(nineveh.homeColor, const Color(0xFF1A237E));
      expect(nineveh.coachName, 'Sargon');
      final babylon = rows.firstWhere((t) => t.id == 'Babylon');
      expect(babylon.homeColor, isNull);
      expect(babylon.coachName, isNull);
    });

    test('invalid Color / empty Coach parse to null (row hidden in UI)', () {
      final rows = leagueStandingsFromTeamsNode('Futsal', {
        'Nineveh': {'Points': 12, 'Color': 'navy blue', 'Coach': ''},
      }, const {});
      expect(rows.single.homeColor, isNull);
      expect(rows.single.coachName, isNull);
    });

    test('leagueCaptainsFromTeamsNode: captain side-channel by team name',
        () {
      final captains = leagueCaptainsFromTeamsNode({
        'Nineveh': {'Points': 12, 'Captain': 'Ashur'},
        'Babylon': {'Points': 3}, // no captain -> absent
        'Akkad': {'Points': 1, 'Captain': '  '}, // blank -> absent
      });
      expect(captains, {'Nineveh': 'Ashur'});
    });

    test('leagueCaptainsFromTeamsNode: garbage in, empty out', () {
      expect(leagueCaptainsFromTeamsNode(null), isEmpty);
      expect(leagueCaptainsFromTeamsNode('nope'), isEmpty);
      expect(leagueCaptainsFromTeamsNode({'Nineveh': 'not-a-map'}), isEmpty);
    });
  });

  group('leaguePredictionMatchKey (P3)', () {
    test('is the path-safe twin of leagueGameId', () {
      expect(leaguePredictionMatchKey('05202026', 3), '05202026_3');
    });

    test('round-trips from a league match id', () {
      final ref = parseLeagueGameId(leagueGameId('11302026', 12))!;
      expect(leaguePredictionMatchKey(ref.dateKey, ref.index), '11302026_12');
    });
  });

  group('P4 — per-sport league engine', () {
    test('isLeagueEngineSport: the three league sports, not AFC/unknown',
        () {
      expect(isLeagueEngineSport('Futsal'), isTrue);
      expect(isLeagueEngineSport('Basketball'), isTrue);
      expect(isLeagueEngineSport('Flag Football'), isTrue);
      expect(isLeagueEngineSport('AFC San Jose'), isFalse);
      expect(isLeagueEngineSport('Cricket'), isFalse);
    });

    test('basketball roster: extraStats vocabulary + Total fallback', () {
      final p = leaguePlayerFromLineup(
        sport: 'Basketball',
        name: 'Sam',
        teamName: 'Eagles',
        raw: {
          'number': '7',
          'OnePoint': 2,
          'TwoPoints': 3,
          'ThreePoints': 1,
          'Misses': 4,
          'Rebounds': 5,
          'Assists': 6,
          'Steals': 2,
          'Blocks': 1,
          'Fouls': 3,
          'Turnovers': 2,
          // NO 'Total' -> fallback-computed 2 + 6 + 3 = 11
        },
      );
      expect(p.statByName('points'), 11);
      expect(p.statByName('freeThrows'), 2);
      expect(p.statByName('twoPointers'), 3);
      expect(p.statByName('threePointers'), 1);
      expect(p.statByName('misses'), 4);
      expect(p.statByName('rebounds'), 5);
      expect(p.statByName('assists'), 6); // core field, populated
      expect(p.statByName('steals'), 2);
      expect(p.statByName('blocks'), 1);
      expect(p.statByName('fouls'), 3);
      expect(p.statByName('turnovers'), 2);
      expect(p.statByName('goals'), 0); // futsal keys stay silent
    });

    test('basketball roster: stored Total wins over the fallback', () {
      final p = leaguePlayerFromLineup(
        sport: 'Basketball',
        name: 'Sam',
        teamName: 'Eagles',
        raw: {'OnePoint': 2, 'Total': 40},
      );
      expect(p.statByName('points'), 40);
    });

    test('flag football roster: extraStats vocabulary + touchdowns sum',
        () {
      final p = leaguePlayerFromLineup(
        sport: 'Flag Football',
        name: 'Sam',
        teamName: 'Eagles',
        raw: {
          'RECTD': 2,
          'RushTD': 1,
          'INTTD': 1,
          'PassTD': 5,
          'REC': 10,
          'INT': 3,
          'FP': 8,
          'Sack': 2,
          'PBU': 4,
        },
      );
      expect(p.statByName('touchdowns'), 4); // RECTD+RushTD+INTTD, NOT PassTD
      expect(p.statByName('receivingTouchdowns'), 2);
      expect(p.statByName('rushingTouchdowns'), 1);
      expect(p.statByName('interceptionTouchdowns'), 1);
      expect(p.statByName('passTouchdowns'), 5);
      expect(p.statByName('receptions'), 10);
      expect(p.statByName('interceptions'), 3);
      expect(p.statByName('flagPulls'), 8);
      expect(p.statByName('sacks'), 2);
      expect(p.statByName('passBreakups'), 4);
    });

    test('futsal roster parsing is unchanged by the sport param', () {
      final p = leaguePlayerFromLineup(
        sport: 'Futsal',
        name: 'Sam',
        teamName: 'Eagles',
        raw: {'Goals': 3, 'Assists': 2, 'Yellow': 1},
      );
      expect(p.statByName('goals'), 3);
      expect(p.statByName('assists'), 2);
      expect(p.statByName('yellowCards'), 1);
    });

    test('basketball standings: Teams keys parsed + seedOrder sort '
        '(Points desc, PD desc, PPG desc)', () {
      final rows = leagueStandingsFromTeamsNode(
        'Basketball',
        {
          'Low': {'GP': 2, 'Wins': 0, 'Losses': 2, 'Points': 0,
            'PPG': 30.0, 'PCPG': 40.0, 'PD': -10.0},
          'High': {'GP': 2, 'Wins': 2, 'Losses': 0, 'Points': 6,
            'PPG': 50.5, 'PCPG': 40.0, 'PD': 10.5},
          'Mid': {'GP': 2, 'Wins': 2, 'Losses': 0, 'Points': 6,
            'PPG': 45.0, 'PCPG': 40.0, 'PD': 5.0},
        },
        const {},
      );
      expect(rows.map((t) => t.name).toList(), ['High', 'Mid', 'Low']);
      expect(rows.first.gp, 2);
      expect(rows.first.wins, 2);
      expect(rows.first.points, 6);
      expect(rows.first.leagueStats['PPG'], 50.5);
      expect(rows.first.leagueStats['PCPG'], 40.0);
      expect(rows.first.leagueStats['PD'], 10.5);
    });

    test('flag football standings: Teams keys parsed + seedOrder sort '
        '(Wins desc, PF-PA desc, PF desc)', () {
      final rows = leagueStandingsFromTeamsNode(
        'Flag Football',
        {
          'B': {'Wins': 2, 'Losses': 1, 'PF': 40, 'PA': 30},
          'A': {'Wins': 2, 'Losses': 1, 'PF': 46, 'PA': 36},
          'C': {'Wins': 1, 'Losses': 2, 'PF': 60, 'PA': 20},
        },
        const {},
      );
      // A and B tie on Wins and on PF-PA (10) -> PF breaks it (46 > 40);
      // C's monster PD never matters: Wins first.
      expect(rows.map((t) => t.name).toList(), ['A', 'B', 'C']);
      expect(rows.first.wins, 2);
      expect(rows.first.leagueStats['PF'], 46);
      expect(rows.first.leagueStats['PA'], 36);
      expect(rows.first.leagueStats['PD'], 10);
    });

    test('futsal standings: parsing and Pts/GD/GS sort unchanged', () {
      final rows = leagueStandingsFromTeamsNode(
        'Futsal',
        {
          'Two': {'GP': 1, 'Wins': 0, 'Draws': 1, 'Losses': 0,
            'GS': 2, 'GC': 2, 'GD': 0, 'Points': 1},
          'One': {'GP': 1, 'Wins': 1, 'Draws': 0, 'Losses': 0,
            'GS': 3, 'GC': 1, 'GD': 2, 'Points': 3},
        },
        const {},
      );
      expect(rows.map((t) => t.name).toList(), ['One', 'Two']);
      expect(rows.first.gd, 2);
    });
  });
}
