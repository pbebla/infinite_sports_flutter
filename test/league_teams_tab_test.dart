import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_teams_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';

void main() {
  testWidgets('renders standings-ordered team cards with record + form',
      (tester) async {
    final standings = leagueStandingsFromTeamsNode('Futsal', {
      'Babylon': {'Wins': 1, 'Draws': 0, 'Losses': 3, 'GP': 4, 'GS': 3, 'GC': 9, 'GD': -6, 'Points': 3},
      'Nineveh': {'Wins': 4, 'Draws': 0, 'Losses': 0, 'GP': 4, 'GS': 12, 'GC': 2, 'GD': 10, 'Points': 12},
    }, const {});
    final matches = leagueMatchesFromDateNode({
      '06152026': [
        {'team1': 'Nineveh', 'team2': 'Babylon', 'team1score': 3, 'team2score': 0, 'status': 2},
      ],
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeagueTeamsTab(
          sport: 'Futsal',
          season: '16',
          standings: standings,
          matches: matches,
        ),
      ),
    ));
    expect(find.text('Nineveh'), findsOneWidget);
    expect(find.text('W4 D0 L0 · 12 pts'), findsOneWidget);
    expect(find.text('W'), findsOneWidget); // Nineveh's form chip
    expect(find.text('L'), findsOneWidget); // Babylon's form chip
    // Standings order: Nineveh card above Babylon.
    final nY = tester.getTopLeft(find.text('Nineveh')).dy;
    final bY = tester.getTopLeft(find.text('Babylon')).dy;
    expect(nY, lessThan(bY));
  });

  testWidgets('empty standings show the placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LeagueTeamsTab(
            sport: 'Futsal', season: '16', standings: [], matches: []),
      ),
    ));
    expect(find.text('No teams available'), findsOneWidget);
  });
}
