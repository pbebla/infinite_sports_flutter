import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

/// A fan's predicted score for one match.
class MatchPrediction {
  final int team1;
  final int team2;
  final int updatedAt; // ms epoch

  const MatchPrediction({
    required this.team1,
    required this.team2,
    required this.updatedAt,
  });

  static MatchPrediction? fromFirebase(dynamic raw) {
    if (raw is! Map) return null;
    return MatchPrediction(
      team1: parseInt(firstNonNull(raw, ['Team1', 'team1'])),
      team2: parseInt(firstNonNull(raw, ['Team2', 'team2'])),
      updatedAt: parseInt(firstNonNull(raw, ['UpdatedAt', 'updatedAt'])),
    );
  }

  Map<String, dynamic> toFirebase() => {
        'Team1': team1,
        'Team2': team2,
        'UpdatedAt': updatedAt,
      };
}

class QuestionAnswer {
  final String value; // see questionPoints encodings
  final int updatedAt;
  const QuestionAnswer({required this.value, required this.updatedAt});

  static QuestionAnswer? fromFirebase(dynamic raw) {
    if (raw is! Map) return null;
    final v = (raw['Answer'] ?? raw['answer']);
    if (v == null) return null;
    return QuestionAnswer(
      value: v.toString(),
      updatedAt: parseInt(raw['UpdatedAt'] ?? raw['updatedAt']),
    );
  }

  Map<String, dynamic> toFirebase() => {'Answer': value, 'UpdatedAt': updatedAt};
}
