import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_playoffs_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';

void main() {
  testWidgets('no staged games → placeholder', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeaguePlayoffsTab(
          playoffs: null,
          matches: const [],
          teams: const {},
          season: '16',
          onMatchTap: (_) {},
        ),
      ),
    ));
    expect(find.text('Playoffs not yet available'), findsOneWidget);
  });

  testWidgets('bracket renders and the champion banner crowns the winner',
      (tester) async {
    final matches = leagueMatchesFromDateNode({
      '07132026': [
        {'team1': 'Nineveh', 'team2': 'Akkad', 'team1score': 4, 'team2score': 1, 'status': 2, 'Stage': 'semifinal'},
        {'team1': 'Babylon', 'team2': 'Ashur FC', 'team1score': 2, 'team2score': 3, 'status': 2, 'Stage': 'semifinal'},
      ],
      '07202026': [
        {'team1': 'Nineveh', 'team2': 'Ashur FC', 'team1score': 2, 'team2score': 1, 'status': 2, 'Stage': 'final'},
      ],
    });
    final playoffs = LeaguePlayoffs.fromNode({
      'Format': 4,
      'ThirdPlace': false,
      'Champion': 'Nineveh',
      'Slots': {
        'sf1': {'gameRef': {'date': '07132026', 'index': 0}},
        'sf2': {'gameRef': {'date': '07132026', 'index': 1}},
        'f1': {'gameRef': {'date': '07202026', 'index': 0}},
      },
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeaguePlayoffsTab(
          playoffs: playoffs,
          matches: matches,
          teams: const {},
          season: '16',
          onMatchTap: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('SEASON 16 CHAMPIONS'), findsOneWidget);
    expect(find.text('Nineveh'), findsWidgets); // banner + bracket
    expect(find.text('Semifinal'), findsWidgets); // round chip from KnockoutTab
  });
}
