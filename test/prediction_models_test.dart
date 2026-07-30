import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';

void main() {
  test('MatchPrediction round-trips (Pascal keys)', () {
    final p = MatchPrediction.fromFirebase(
        {'Team1': 2, 'Team2': 1, 'UpdatedAt': 1700000000000});
    expect(p!.team1, 2);
    expect(p.team2, 1);
    expect(p.updatedAt, 1700000000000);
    expect(p.toFirebase()['Team1'], 2);
  });

  test('PredictionConfig defaults when fields missing', () {
    final c = PredictionConfig.fromFirebase({});
    expect(c.open, true);
    expect(c.matchWinnerPoints, 1);
    expect(c.exactScorePoints, 3);
  });

  test('PredictionConfig reads Open + Scoring', () {
    final c = PredictionConfig.fromFirebase({
      'Open': false,
      'Scoring': {'MatchWinner': 2, 'ExactScoreBonus': 5},
    });
    expect(c.open, false);
    expect(c.matchWinnerPoints, 2);
    expect(c.exactScorePoints, 5);
  });

  test('LeaderboardEntry parse + sort (points desc, exact desc, name asc)', () {
    final a = LeaderboardEntry.fromFirebase(
        'u1', {'Name': 'Bea', 'Points': 10, 'Exact': 1});
    final b = LeaderboardEntry.fromFirebase(
        'u2', {'Name': 'Ann', 'Points': 10, 'Exact': 1});
    final c = LeaderboardEntry.fromFirebase(
        'u3', {'Name': 'Cy', 'Points': 12, 'Exact': 0});
    final list = [a, b, c]..sort(compareLeaderboard);
    expect(list.map((e) => e.uid).toList(), ['u3', 'u2', 'u1']);
  });
}
