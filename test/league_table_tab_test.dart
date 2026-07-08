import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_table_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';

void main() {
  testWidgets('renders futsal columns + rows in given order',
      (tester) async {
    final standings = leagueStandingsFromTeamsNode({
      'Babylon': {'Wins': 3, 'Draws': 0, 'Losses': 5, 'GP': 8, 'GS': 9, 'GC': 20, 'GD': -11, 'Points': 9},
      'Nineveh': {'Wins': 7, 'Draws': 1, 'Losses': 0, 'GP': 8, 'GS': 30, 'GC': 5, 'GD': 25, 'Points': 22},
    }, const {});
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LeagueTableTab(standings: standings))));
    for (final col in ['Team', 'GP', 'W', 'D', 'L', 'GF', 'GA', 'GD', 'P']) {
      expect(find.text(col), findsOneWidget);
    }
    expect(find.text('Nineveh'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    // Sorted: Nineveh (22 pts) above Babylon (9 pts).
    final nY = tester.getTopLeft(find.text('Nineveh')).dy;
    final bY = tester.getTopLeft(find.text('Babylon')).dy;
    expect(nY, lessThan(bY));
  });

  testWidgets('empty standings show the placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LeagueTableTab(standings: []))));
    expect(find.text('Table not yet available'), findsOneWidget);
  });
}
