import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';

void main() {
  PredictionResult score(int p1, int p2, int a1, int a2) => predictionPoints(
        predTeam1: p1, predTeam2: p2, actualTeam1: a1, actualTeam2: a2,
        matchWinnerPoints: 1, exactScorePoints: 3,
      );

  test('exact score: result + exact bonus', () {
    final r = score(2, 1, 2, 1);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, true);
    expect(r.points, 4);
  });
  test('right winner, wrong score: result only', () {
    final r = score(2, 1, 3, 0);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, false);
    expect(r.points, 1);
  });
  test('wrong winner: zero', () {
    final r = score(2, 1, 0, 1);
    expect(r.resultCorrect, false);
    expect(r.exactCorrect, false);
    expect(r.points, 0);
  });
  test('correct draw, wrong score: result only', () {
    final r = score(1, 1, 2, 2);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, false);
    expect(r.points, 1);
  });
  test('exact draw: result + exact', () {
    final r = score(0, 0, 0, 0);
    expect(r.points, 4);
  });
  test('predicted draw, actual not draw: zero', () {
    expect(score(1, 1, 2, 1).points, 0);
  });
}
