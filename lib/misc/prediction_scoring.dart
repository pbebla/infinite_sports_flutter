import 'package:infinite_sports_flutter/model/prediction_question.dart';

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

class QuestionScore {
  final bool correct;
  final int points;
  final bool isExactScore;
  const QuestionScore(
      {required this.correct, required this.points, required this.isExactScore});
}

/// Pure scoring for ONE answer to ONE question. Mirrors functions/src/lib/predict.ts.
/// `answer` encodings: matchWinner -> 'team1'|'draw'|'team2'; totalGoals -> 'over'|'under';
/// correctScore -> 'T1-T2' (e.g. '2-1'); custom -> the chosen option id.
/// `customResult` is the owner-set winning option id for custom questions (null = unresolved).
QuestionScore questionPoints({
  required PredictionQuestion question,
  required String answer,
  required int finalTeam1,
  required int finalTeam2,
  required String? customResult,
}) {
  bool correct = false;
  bool exact = false;
  switch (question.type) {
    case QuestionType.matchWinner:
      final res = finalTeam1 > finalTeam2
          ? 'team1'
          : (finalTeam1 < finalTeam2 ? 'team2' : 'draw');
      correct = answer == res;
      break;
    case QuestionType.correctScore:
      correct = answer == '$finalTeam1-$finalTeam2';
      exact = correct;
      break;
    case QuestionType.totalGoals:
      final line = question.line ?? 2.5;
      final over = (finalTeam1 + finalTeam2) > line;
      correct = answer == (over ? 'over' : 'under');
      break;
    case QuestionType.custom:
      correct = customResult != null && answer == customResult;
      break;
    case QuestionType.playerAward:
      // Resolved externally via matchStatLeaders; customResult carries the
      // winning player name when set by the resolution trigger.
      correct = customResult != null && answer == customResult;
      break;
  }
  return QuestionScore(
      correct: correct, points: correct ? question.points : 0, isExactScore: exact);
}
