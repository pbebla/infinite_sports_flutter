import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

enum QuestionType { matchWinner, correctScore, totalGoals, custom, playerAward }

QuestionType questionTypeFromString(String? s) {
  switch ((s ?? '').toString()) {
    case 'matchWinner':
      return QuestionType.matchWinner;
    case 'correctScore':
      return QuestionType.correctScore;
    case 'totalGoals':
      return QuestionType.totalGoals;
    case 'playerAward':
      return QuestionType.playerAward;
    default:
      return QuestionType.custom;
  }
}

String questionTypeToString(QuestionType t) => t.name;

class QuestionOption {
  final String id;
  final String label;
  const QuestionOption(this.id, this.label);
}

class PredictionQuestion {
  final String id;
  final String text;
  final QuestionType type;
  final int points;
  final int order;
  final List<QuestionOption> options; // custom only
  final double? line; // totalGoals only
  final String? stat; // playerAward only ('goals'|'assists'|'saves'|'dpl')

  const PredictionQuestion({
    required this.id,
    required this.text,
    required this.type,
    required this.points,
    required this.order,
    required this.options,
    required this.line,
    this.stat,
  });

  factory PredictionQuestion.fromFirebase(String id, dynamic raw) {
    final data = (raw is Map) ? raw : const {};
    final optsRaw = firstNonNull(data, ['Options', 'options']);
    final options = <QuestionOption>[];
    if (optsRaw is Map) {
      optsRaw.forEach((oid, ov) {
        final label = (ov is Map)
            ? (firstNonNull(ov, ['Label', 'label'])?.toString() ?? oid.toString())
            : ov.toString();
        options.add(QuestionOption(oid.toString(), label));
      });
    }
    final lineRaw = firstNonNull(data, ['Line', 'line']);
    return PredictionQuestion(
      id: id,
      text: firstNonNull(data, ['Text', 'text'])?.toString() ?? '',
      type: questionTypeFromString(firstNonNull(data, ['Type', 'type'])?.toString()),
      points: parseInt(firstNonNull(data, ['Points', 'points'])),
      order: parseInt(firstNonNull(data, ['Order', 'order'])),
      options: options,
      line: lineRaw == null ? null : double.tryParse(lineRaw.toString()),
      stat: firstNonNull(data, ['Stat', 'stat'])?.toString(),
    );
  }

  Map<String, dynamic> toFirebase() => {
        'Text': text,
        'Type': questionTypeToString(type),
        'Points': points,
        'Order': order,
        if (line != null) 'Line': line,
        if (stat != null) 'Stat': stat,
        if (options.isNotEmpty)
          'Options': {for (final o in options) o.id: {'Label': o.label}},
      };
}

/// Display text for a question — nice, consistent wording for the auto types;
/// the stored text for custom (owner-authored) questions.
String questionDisplayText(PredictionQuestion q) {
  switch (q.type) {
    case QuestionType.matchWinner:
      return 'Who will win?';
    case QuestionType.correctScore:
      return 'What will the final score be?';
    case QuestionType.totalGoals:
      final l = q.line ?? 2.5;
      final ls = l == l.roundToDouble() ? l.toStringAsFixed(0) : l.toString();
      return 'Over or under $ls goals?';
    case QuestionType.playerAward:
      switch (q.stat) {
        case 'assists':
          return 'Who will provide the most assists?';
        case 'saves':
          return 'Who will make the most saves?';
        case 'dpl':
          return 'Who will be the best defender?';
        case 'goals':
        default:
          return 'Who will score the most goals?';
      }
    case QuestionType.custom:
      return q.text;
  }
}
