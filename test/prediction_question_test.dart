import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';

void main() {
  group('PredictionQuestion.fromFirebase', () {
    test('matchWinner parses with points/order', () {
      final q = PredictionQuestion.fromFirebase('q_winner',
          {'Text': 'Who will win?', 'Type': 'matchWinner', 'Points': 1, 'Order': 0});
      expect(q.type, QuestionType.matchWinner);
      expect(q.points, 1);
      expect(q.order, 0);
    });
    test('totalGoals parses Line', () {
      final q = PredictionQuestion.fromFirebase('q_tg',
          {'Text': 'Total goals', 'Type': 'totalGoals', 'Points': 2, 'Line': 2.5, 'Order': 2});
      expect(q.type, QuestionType.totalGoals);
      expect(q.line, 2.5);
    });
    test('custom parses Options', () {
      final q = PredictionQuestion.fromFirebase('q_c', {
        'Text': 'Who scores first?', 'Type': 'custom', 'Points': 2, 'Order': 3,
        'Options': {'o1': {'Label': 'Eagles'}, 'o2': {'Label': 'Lions'}},
      });
      expect(q.type, QuestionType.custom);
      expect(q.options.length, 2);
      expect(q.options.map((o) => o.label), containsAll(['Eagles', 'Lions']));
    });
    test('unknown type falls back to custom (no crash)', () {
      final q = PredictionQuestion.fromFirebase('q_x', {'Type': 'weird', 'Points': 1});
      expect(q.type, QuestionType.custom);
    });
  });

  group('questionPoints', () {
    PredictionQuestion winner(int pts) => PredictionQuestion(
        id: 'w', text: 'Who will win?', type: QuestionType.matchWinner,
        points: pts, order: 0, options: const [], line: null);
    test('matchWinner correct', () {
      final r = questionPoints(question: winner(1), answer: 'team1',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, true); expect(r.points, 1); expect(r.isExactScore, false);
    });
    test('matchWinner wrong', () {
      final r = questionPoints(question: winner(1), answer: 'draw',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, false); expect(r.points, 0);
    });
    test('correctScore exact gives points + isExactScore', () {
      final q = PredictionQuestion(id: 's', text: 'Score', type: QuestionType.correctScore,
          points: 3, order: 1, options: const [], line: null);
      final r = questionPoints(question: q, answer: '2-1',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, true); expect(r.points, 3); expect(r.isExactScore, true);
    });
    test('totalGoals over/under (on-the-line counts as under)', () {
      final q = PredictionQuestion(id: 't', text: 'TG', type: QuestionType.totalGoals,
          points: 2, order: 2, options: const [], line: 2.5);
      expect(questionPoints(question: q, answer: 'over', finalTeam1: 2, finalTeam2: 1, customResult: null).correct, true);
      expect(questionPoints(question: q, answer: 'under', finalTeam1: 1, finalTeam2: 1, customResult: null).correct, true);
      final q3 = PredictionQuestion(id: 't', text: 'TG', type: QuestionType.totalGoals,
          points: 2, order: 2, options: const [], line: 3.0);
      // total 3, line 3.0 -> under
      expect(questionPoints(question: q3, answer: 'under', finalTeam1: 2, finalTeam2: 1, customResult: null).correct, true);
    });
    test('custom matches owner-set result; unresolved => not correct', () {
      final q = PredictionQuestion(id: 'c', text: 'First?', type: QuestionType.custom,
          points: 2, order: 3, options: const [QuestionOption('o1','Eagles'), QuestionOption('o2','Lions')], line: null);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: 'o1').points, 2);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: null).points, 0);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: 'o2').points, 0);
    });
  });
}
