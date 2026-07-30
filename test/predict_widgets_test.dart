import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_card.dart';

TournamentMatch _m({required int status, int s1 = 0, int s2 = 0}) =>
    TournamentMatch(
      id: 'm1', stage: 'Group Stage', label: 'Group A', date: '08272026',
      time: '6:00 PM', team1Id: 'A', team2Id: 'B',
      team1Score: s1, team2Score: s2, status: status, bracketPosition: 0,
    );

const _cfg = PredictionConfig(open: true, matchWinnerPoints: 1, exactScorePoints: 3);

void main() {
  testWidgets('signed-out shows sign-in CTA', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 0), team1: null, team2: null, config: _cfg,
          myPrediction: null, isSignedIn: false,
          onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.text('Sign in to predict'), findsOneWidget);
  });

  testWidgets('scheduled + signed-in shows Lock prediction', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 0), team1: null, team2: null, config: _cfg,
          myPrediction: null, isSignedIn: true,
          onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.text('Lock prediction'), findsOneWidget);
  });

  testWidgets('finished shows earned points for an exact pick', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 2, s1: 2, s2: 1), team1: null, team2: null,
          config: _cfg,
          myPrediction: const MatchPrediction(team1: 2, team2: 1, updatedAt: 1),
          isSignedIn: true, onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.textContaining('Exact! +4'), findsOneWidget);
  });
}
