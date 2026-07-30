import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

TournamentMatch match({
  required String id,
  required int status,
  String t1 = 'A',
  String t2 = 'B',
  int s1 = 0,
  int s2 = 0,
  Map<String, dynamic>? a1,
  Map<String, dynamic>? a2,
  String? k1,
  String? k2,
}) =>
    TournamentMatch(
      id: id, stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: t1, team2Id: t2, team1Score: s1, team2Score: s2, status: status,
      team1Activity: a1, team2Activity: a2, team1Keeper: k1, team2Keeper: k2,
      bracketPosition: 0,
    );

TournamentPlayer player(String name, String teamId) => TournamentPlayer(
      name: name, teamId: teamId, teamName: teamId,
      goals: 0, assists: 0, saves: 0, dpl: 0, cleanSheets: 0,
      yellowCards: 0, redCards: 0,
    );

void main() {
  final rosters = {
    'A': [player('Sam', 'A'), player('Kai', 'A')],
    'B': [player('Lee', 'B')],
  };

  test('finished match: standings from score, 3 pts to winner', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 2, s1: 2, s2: 1)], rosters: rosters);
    expect(r.standingFor('A').pts, 3);
    expect(r.standingFor('A').w, 1);
    expect(r.standingFor('A').gd, 1);
    expect(r.standingFor('B').l, 1);
    expect(r.standingFor('B').pts, 0);
  });

  test('LIVE match (status 1) ALSO counts toward standings', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 1, s1: 1, s2: 0)], rosters: rosters);
    expect(r.standingFor('A').pts, 3);
    expect(r.standingFor('A').gp, 1);
    expect(r.standingFor('B').gc, 1);
  });

  test('upcoming match (status 0) is ignored', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 0, s1: 5, s2: 5)], rosters: rosters);
    expect(r.standingFor('A').gp, 0);
    expect(r.standingFor('A').pts, 0);
  });

  test('draw gives 1 pt each', () {
    final r = computeTournamentStats(
        matches: [match(id: '1', status: 2, s1: 1, s2: 1)], rosters: rosters);
    expect(r.standingFor('A').pts, 1);
    expect(r.standingFor('B').pts, 1);
    expect(r.standingFor('A').d, 1);
  });

  test('player counters from activity (goal, assist) live', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 1, s1: 1, s2: 0, a1: {
        '12': [
          {'goal': 'Sam'},
          {'assist': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
    expect(r.statByName('A', 'Kai', 'assists'), 1);
  });

  test('activity bucket as index-keyed Map is tolerated', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '5': {
          '0': {'goal': 'Sam'},
        },
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
  });

  test('penalty goal counts as a goal; red/second-yellow as red card', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '1': [
          {'penalty goal': 'Sam'},
          {'second yellow': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 1);
    expect(r.statByName('A', 'Kai', 'redCards'), 1);
  });

  test('clean sheet credited to keeper of team that conceded zero', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 3, s2: 0, k1: 'Sam')
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'cleanSheets'), 1);
  });

  test('substitution and foul produce no counter', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 0, s2: 0, a1: {
        '1': [
          {'substitution': 'Sam'},
          {'foul': 'Kai'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goals'), 0);
    expect(r.statByName('A', 'Kai', 'goals'), 0);
  });

  test('standingFor unknown team returns a zero row', () {
    final r = computeTournamentStats(matches: const [], rosters: rosters);
    expect(r.standingFor('Z').pts, 0);
    expect(r.standingFor('Z').gp, 0);
  });

  test('statByName goalsAndAssists sums both', () {
    final r = computeTournamentStats(matches: [
      match(id: '1', status: 2, s1: 1, s2: 0, a1: {
        '1': [
          {'goal': 'Sam'},
          {'assist': 'Sam'},
        ],
      })
    ], rosters: rosters);
    expect(r.statByName('A', 'Sam', 'goalsAndAssists'), 2);
  });

  group('P1 regression lock — historical soccer tournament replay', () {
    // A 2-match group-stage tournament exercising every legacy event
    // spelling AND both a keeper clean sheet and a decided draw — the
    // shapes real historical soccer tournament data takes.
    final matches = [
      match(
        id: 'm1',
        t1: 'alpha',
        t2: 'bravo',
        s1: 2,
        s2: 0,
        status: 2,
        a1: {
          '10': [
            {'goal': 'Ann'}
          ],
          '11': [
            {'assist': 'Amy'}
          ],
          '40': [
            {'penalty goal': 'Ann'}
          ],
          '55': [
            {'yellow card': 'Ann'}
          ],
        },
        a2: {
          '70': [
            {'yellow card': 'Bob'}
          ],
          '80': [
            {'second yellow': 'Bob'}
          ],
        },
        k1: 'Gina',
      ),
      match(
        id: 'm2',
        t1: 'alpha',
        t2: 'bravo',
        s1: 1,
        s2: 1,
        status: 2,
        a1: {
          '30': [
            {'own goal': 'Ann'}
          ],
        },
        a2: {
          '60': [
            {'goal': 'Bob'}
          ],
          '65': [
            {'dpl': 'Bea'}
          ],
        },
      ),
    ];
    final rosters2 = {
      'alpha': [
        player('Ann', 'alpha'),
        player('Amy', 'alpha'),
        player('Gina', 'alpha'),
      ],
      'bravo': [player('Bob', 'bravo'), player('Bea', 'bravo')],
    };

    test('standings unchanged: 1 win + 1 draw for alpha, 1 loss + 1 draw for bravo', () {
      final result =
          computeTournamentStats(matches: matches, rosters: rosters2);
      final a = result.standings['alpha']!;
      final b = result.standings['bravo']!;
      expect(a.gp, 2);
      expect(a.w, 1);
      expect(a.d, 1);
      expect(a.l, 0);
      expect(a.pts, 4);
      expect(a.gs, 3);
      expect(a.gc, 1);
      expect(b.gp, 2);
      expect(b.w, 0);
      expect(b.d, 1);
      expect(b.l, 1);
      expect(b.pts, 1);
    });

    test('player counters unchanged for every legacy spelling', () {
      final result =
          computeTournamentStats(matches: matches, rosters: rosters2);
      final ann = result.players['alpha']!['Ann']!;
      final amy = result.players['alpha']!['Amy']!;
      final gina = result.players['alpha']!['Gina']!;
      final bob = result.players['bravo']!['Bob']!;
      final bea = result.players['bravo']!['Bea']!;

      // Ann: 1 goal + 1 penalty goal = 2 goals; 1 own goal (timeline-only,
      // no counter); 1 yellow card.
      expect(ann.goals, 2);
      expect(ann.yellowCards, 1);
      // Amy: 1 assist.
      expect(amy.assists, 1);
      // Gina: clean sheet in m1 (bravo scored 0).
      expect(gina.cleanSheets, 1);
      // Bob: 1 goal; today's engine bumps redCards for the second yellow
      // WITHOUT clearing the earlier yellowCards bump (same baseline as
      // the Manager engine's identical applyEvent logic).
      expect(bob.goals, 1);
      expect(bob.redCards, 1);
      expect(bob.yellowCards, 1);
      // Bea: 1 DPL.
      expect(bea.dpl, 1);
    });
  });

  group('P1 — Basketball counters (config-driven)', () {
    test('scoring events increment the right catalog keys', () {
      final result = computeTournamentStats(
        sport: 'Basketball',
        matches: [
          match(
            id: 'b1',
            t1: 'alpha',
            t2: 'bravo',
            s1: 10,
            s2: 6,
            status: 2,
            a1: {
              '1': [
                {'OnePointer': 'Ann'}
              ],
              '2': [
                {'TwoPointer': 'Ann'}
              ],
              '3': [
                {'ThreePointer': 'Amy'}
              ],
              '4': [
                {'Rebound': 'Amy'}
              ],
              '5': [
                {'Steal': 'Ann'}
              ],
              '6': [
                {'Block': 'Amy'}
              ],
              '7': [
                {'Miss': 'Ann'}
              ],
            },
          ),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha'), player('Amy', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      final ann = result.players['alpha']!['Ann']!;
      final amy = result.players['alpha']!['Amy']!;
      expect(ann.byKey('OnePoint'), 1);
      expect(ann.byKey('TwoPoints'), 1);
      expect(ann.byKey('Steals'), 1);
      expect(ann.byKey('Misses'), 1);
      expect(amy.byKey('ThreePoints'), 1);
      expect(amy.byKey('Rebounds'), 1);
      expect(amy.byKey('Blocks'), 1);
    });

    test('unrostered player is reported unknown, never crashes', () {
      final result = computeTournamentStats(
        sport: 'Basketball',
        matches: [
          match(id: 'b1', t1: 'alpha', t2: 'bravo', s1: 2, s2: 0, status: 2, a1: {
            '1': [
              {'TwoPointer': 'Ghost'}
            ]
          }),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      expect(result.unknownPlayers, contains('alpha/Ghost'));
    });

    test('basketball has no clean-sheet concept — keeper field is ignored', () {
      final result = computeTournamentStats(
        sport: 'Basketball',
        matches: [
          match(
              id: 'b1',
              t1: 'alpha',
              t2: 'bravo',
              s1: 10,
              s2: 0,
              status: 2,
              k1: 'Ann'),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      expect(result.players['alpha']!['Ann']!.cleanSheets, 0);
    });
  });

  group('P1 — Flag Football counters (config-driven)', () {
    test('scored TDs, receptions, defense all land on their catalog keys', () {
      final result = computeTournamentStats(
        sport: 'Flag Football',
        matches: [
          match(
            id: 'f1',
            t1: 'alpha',
            t2: 'bravo',
            s1: 6,
            s2: 0,
            status: 2,
            a1: {
              '1': [
                {'REC': 'Ann'}
              ],
              '2': [
                {'Receiving TD': 'Ann'}
              ],
              '3': [
                {'Pass TD': 'Amy'}
              ],
              '4': [
                {'Sack': 'Bea'}
              ],
            },
            a2: {
              '5': [
                {'Interception': 'Bob'}
              ],
            },
          ),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha'), player('Amy', 'alpha')],
          'bravo': [player('Bob', 'bravo'), player('Bea', 'bravo')],
        },
      );
      final ann = result.players['alpha']!['Ann']!;
      final amy = result.players['alpha']!['Amy']!;
      final bob = result.players['bravo']!['Bob']!;
      expect(ann.byKey('REC'), 1);
      expect(ann.byKey('RECTD'), 1);
      expect(amy.byKey('PassTD'), 1);
      expect(bob.byKey('INT'), 1);
    });
  });

  group('P1 — canonical spelling bridge inside the engine', () {
    test('legacy spaced spellings still increment the right soccer counters', () {
      final result = computeTournamentStats(
        matches: [
          match(id: 's1', t1: 'alpha', t2: 'bravo', s1: 1, s2: 0, status: 2, a1: {
            '10': [
              {'penalty goal': 'Ann'}
            ],
          }),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      expect(result.players['alpha']!['Ann']!.goals, 1);
    });

    test('new canonical spelling produces the same result as the legacy one', () {
      final legacy = computeTournamentStats(
        matches: [
          match(id: 's1', t1: 'alpha', t2: 'bravo', s1: 1, s2: 0, status: 2, a1: {
            '10': [
              {'penalty goal': 'Ann'}
            ],
          }),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      final canonical = computeTournamentStats(
        matches: [
          match(id: 's1', t1: 'alpha', t2: 'bravo', s1: 1, s2: 0, status: 2, a1: {
            '10': [
              {'PenGoal': 'Ann'}
            ],
          }),
        ],
        rosters: {
          'alpha': [player('Ann', 'alpha')],
          'bravo': [player('Bob', 'bravo')],
        },
      );
      expect(canonical.players['alpha']!['Ann']!.goals,
          legacy.players['alpha']!['Ann']!.goals);
    });
  });

  test('P1: LIVE basketball matches DO count (fan-only divergence)', () {
    final result = computeTournamentStats(
      sport: 'Basketball',
      matches: [
        match(id: 'b1', t1: 'alpha', t2: 'bravo', s1: 2, s2: 0, status: 1, a1: {
          '1': [
            {'TwoPointer': 'Ann'}
          ]
        }),
      ],
      rosters: {
        'alpha': [player('Ann', 'alpha')],
        'bravo': [player('Bob', 'bravo')],
      },
    );
    expect(result.players['alpha']!['Ann']!.byKey('TwoPoints'), 1);
    expect(result.standings['alpha']!.gp, 1);
  });

  group('standingsModeFor (P1)', () {
    test('soccer and futsal allow draws', () {
      expect(standingsModeFor('Soccer'), 'drawsAllowed');
      expect(standingsModeFor('Futsal'), 'drawsAllowed');
    });

    test('basketball and flag football have no draws', () {
      expect(standingsModeFor('Basketball'), 'winsOnly');
      expect(standingsModeFor('Flag Football'), 'winsOnly');
    });

    test('an unknown future sport defaults to winsOnly (safer default)', () {
      expect(standingsModeFor('Volleyball'), 'winsOnly');
    });
  });
}
