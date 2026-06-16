import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/tournament_tabs/prediction_question_card.dart';

PredictionQuestion _q(QuestionType t,
        {List<QuestionOption> opts = const [], double? line}) =>
    PredictionQuestion(
        id: 'q',
        text: 'Q',
        type: t,
        points: t == QuestionType.correctScore ? 3 : 1,
        order: 0,
        options: opts,
        line: line);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('matchWinner shows three options', (tester) async {
    await tester.pumpWidget(_host(PredictionQuestionCard(
        question: _q(QuestionType.matchWinner),
        answer: null,
        customResult: null,
        locked: false,
        finished: false,
        isSignedIn: true,
        finalTeam1: 0,
        finalTeam2: 0,
        team1Name: 'Eagles',
        team2Name: 'Lions',
        onAnswer: (_) {})));
    expect(find.text('Eagles'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Lions'), findsOneWidget);
  });

  testWidgets('custom shows its options', (tester) async {
    await tester.pumpWidget(_host(PredictionQuestionCard(
        question: _q(QuestionType.custom,
            opts: const [
              QuestionOption('o1', 'Yes'),
              QuestionOption('o2', 'No')
            ]),
        answer: null,
        customResult: null,
        locked: false,
        finished: false,
        isSignedIn: true,
        finalTeam1: 0,
        finalTeam2: 0,
        team1Name: 'E',
        team2Name: 'L',
        onAnswer: (_) {})));
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
  });

  testWidgets('finished correctScore exact shows +3', (tester) async {
    await tester.pumpWidget(_host(PredictionQuestionCard(
        question: _q(QuestionType.correctScore),
        answer: '2-1',
        customResult: null,
        locked: true,
        finished: true,
        isSignedIn: true,
        finalTeam1: 2,
        finalTeam2: 1,
        team1Name: 'E',
        team2Name: 'L',
        onAnswer: (_) {})));
    expect(find.textContaining('+3'), findsOneWidget);
  });
}
