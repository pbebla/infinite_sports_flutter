import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

void main() {
  test('parses Team1Keeper / Team2Keeper when present', () {
    final m = TournamentMatch.fromFirebase('M1', {
      'Team1Id': 'a', 'Team2Id': 'b',
      'Team1Score': 1, 'Team2Score': 0, 'Status': 2,
      'Team1Keeper': 'Sam Keeper', 'Team2Keeper': 'Lee Keeper',
    });
    expect(m.team1Keeper, 'Sam Keeper');
    expect(m.team2Keeper, 'Lee Keeper');
  });

  test('keepers are null when absent', () {
    final m = TournamentMatch.fromFirebase('M2', {
      'Team1Id': 'a', 'Team2Id': 'b',
      'Team1Score': 0, 'Team2Score': 0, 'Status': 0,
    });
    expect(m.team1Keeper, isNull);
    expect(m.team2Keeper, isNull);
  });
}
