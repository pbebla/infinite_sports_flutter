/// Pure scoring rule for a single match prediction.
/// Mirrors functions/src/lib/predict.ts predictionPoints — keep both in sync.
class PredictionResult {
  final bool resultCorrect;
  final bool exactCorrect;
  final int points;
  const PredictionResult({
    required this.resultCorrect,
    required this.exactCorrect,
    required this.points,
  });
}

PredictionResult predictionPoints({
  required int predTeam1,
  required int predTeam2,
  required int actualTeam1,
  required int actualTeam2,
  required int matchWinnerPoints,
  required int exactScorePoints,
}) {
  final resultCorrect =
      (predTeam1 - predTeam2).sign == (actualTeam1 - actualTeam2).sign;
  final exactCorrect = predTeam1 == actualTeam1 && predTeam2 == actualTeam2;
  final points = (resultCorrect ? matchWinnerPoints : 0) +
      (exactCorrect ? exactScorePoints : 0);
  return PredictionResult(
    resultCorrect: resultCorrect,
    exactCorrect: exactCorrect,
    points: points,
  );
}
