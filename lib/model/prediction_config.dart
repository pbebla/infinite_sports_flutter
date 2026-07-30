import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

/// Fan-side view of Tournaments/{tid}/PredictionConfig (Phase 1 fields only).
class PredictionConfig {
  final bool open;
  final int matchWinnerPoints;
  final int exactScorePoints;

  const PredictionConfig({
    required this.open,
    required this.matchWinnerPoints,
    required this.exactScorePoints,
  });

  factory PredictionConfig.fromFirebase(dynamic raw) {
    final data = (raw is Map) ? raw : const <dynamic, dynamic>{};
    final open = firstNonNull(data, ['Open', 'open']);
    final scoring = firstNonNull(data, ['Scoring', 'scoring']);
    int score(String pascal, String camel, int dflt) {
      if (scoring is Map) {
        final v = firstNonNull(scoring, [pascal, camel]);
        if (v != null) return parseInt(v);
      }
      return dflt;
    }
    return PredictionConfig(
      open: open is bool ? open : (open == null ? true : open.toString() == 'true'),
      matchWinnerPoints: score('MatchWinner', 'matchWinner', 1),
      exactScorePoints: score('ExactScoreBonus', 'exactScoreBonus', 3),
    );
  }
}
