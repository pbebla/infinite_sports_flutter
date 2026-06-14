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
}
