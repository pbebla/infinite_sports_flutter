import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

enum QuestionType { matchWinner, correctScore, totalGoals, custom }

QuestionType questionTypeFromString(String? s) {
  switch ((s ?? '').toString()) {
    case 'matchWinner':
      return QuestionType.matchWinner;
    case 'correctScore':
      return QuestionType.correctScore;
    case 'totalGoals':
      return QuestionType.totalGoals;
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

  const PredictionQuestion({
    required this.id,
    required this.text,
    required this.type,
    required this.points,
    required this.order,
    required this.options,
    required this.line,
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
    );
  }

  Map<String, dynamic> toFirebase() => {
        'Text': text,
        'Type': questionTypeToString(type),
        'Points': points,
        'Order': order,
        if (line != null) 'Line': line,
        if (options.isNotEmpty)
          'Options': {for (final o in options) o.id: {'Label': o.label}},
      };
}
