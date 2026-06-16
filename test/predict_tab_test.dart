import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_tab.dart';

const _cfg = PredictionConfig(open: true, matchWinnerPoints: 1, exactScorePoints: 3);

void main() {
  testWidgets('PredictTab (signed out, no matches) shows the Matches empty state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PredictTab(
          matches: [], teams: {}, tournamentId: 't1',
          config: _cfg, currentUid: null,
        ),
      ),
    ));
    expect(find.text('Matches'), findsOneWidget); // segmented control
    expect(find.text('No matches to predict yet'), findsOneWidget);
  });
}
