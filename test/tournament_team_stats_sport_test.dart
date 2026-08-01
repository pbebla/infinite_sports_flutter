// PR #11 review guard: the team page's Stats tab must aggregate with the
// tournament's OWN sport. Before the fix tournamentteamdetail.dart called
// computeTournamentStats without `sport`, so it fell back to Soccer keys —
// a basketball team's Stats tab found no points/rebounds and rendered
// completely blank. Fixture style mirrors tournament_stats_engine_test.dart
// (direct constructor, status 2 = finished).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

TournamentPlayer _player(String name, String teamId) => TournamentPlayer(
      name: name, teamId: teamId, teamName: teamId,
      goals: 0, assists: 0, saves: 0, dpl: 0, cleanSheets: 0,
      yellowCards: 0, redCards: 0,
    );

TournamentMatch _basketballMatch() => TournamentMatch(
      id: 'm1', stage: 'Group Stage', label: 'Group Stage', date: '08272026',
      team1Id: 'akkad01', team2Id: 'ashur01',
      team1Score: 5, team2Score: 0, status: 2,
      team1Activity: {
        '5': [
          {'TwoPointer': 'Ann'},
          {'ThreePointer': 'Ann'},
          {'Rebound': 'Ann'},
        ],
      },
      bracketPosition: 0,
    );

void main() {
  final rosters = {
    'akkad01': [_player('Ann', 'akkad01')],
    'ashur01': [_player('Bob', 'ashur01')],
  };

  test('basketball counters populate when the sport is passed', () {
    final stats = computeTournamentStats(
      matches: [_basketballMatch()],
      rosters: rosters,
      sport: 'Basketball',
    );
    expect(stats.statByName('akkad01', 'Ann', 'twoPointers'), 1);
    expect(stats.statByName('akkad01', 'Ann', 'threePointers'), 1);
    expect(stats.statByName('akkad01', 'Ann', 'rebounds'), 1);
    expect(stats.statByName('akkad01', 'Ann', 'points'), 5);
  });

  test('omitting the sport yields no basketball counters (the fixed bug)', () {
    final stats = computeTournamentStats(
      matches: [_basketballMatch()],
      rosters: rosters,
    );
    expect(stats.statByName('akkad01', 'Ann', 'points'), 0);
  });
}
