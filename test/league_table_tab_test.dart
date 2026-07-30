import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_table_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

void main() {
  testWidgets('renders futsal columns + rows in given order',
      (tester) async {
    final standings = leagueStandingsFromTeamsNode('Futsal', {
      'Babylon': {'Wins': 3, 'Draws': 0, 'Losses': 5, 'GP': 8, 'GS': 9, 'GC': 20, 'GD': -11, 'Points': 9},
      'Nineveh': {'Wins': 7, 'Draws': 1, 'Losses': 0, 'GP': 8, 'GS': 30, 'GC': 5, 'GD': 25, 'Points': 22},
    }, const {});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LeagueTableTab(sport: 'Futsal', standings: standings))));
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
        home: Scaffold(
            body: LeagueTableTab(sport: 'Futsal', standings: []))));
    expect(find.text('Table not yet available'), findsOneWidget);
  });

  testWidgets('tapping a row reports that team via onOpenTeam',
      (tester) async {
    final standings = leagueStandingsFromTeamsNode('Futsal', {
      'Babylon': {'Wins': 3, 'Draws': 0, 'Losses': 5, 'GP': 8, 'GS': 9, 'GC': 20, 'GD': -11, 'Points': 9},
      'Nineveh': {'Wins': 7, 'Draws': 1, 'Losses': 0, 'GP': 8, 'GS': 30, 'GC': 5, 'GD': 25, 'Points': 22},
    }, const {});
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LeagueTableTab(
      sport: 'Futsal',
      standings: standings,
      onOpenTeam: opened.add,
    ))));
    await tester.tap(find.text('Babylon'));
    await tester.pump();
    expect(opened, ['Babylon']);
  });

  group('P4 — per-sport columns', () {
    testWidgets('basketball shows GP W L PPG PCPG PD Pts', (tester) async {
      final rows = [
        const TournamentTeam(
          id: 'High', name: 'High', qualification: '',
          gp: 2, wins: 2, draws: 0, losses: 0,
          gs: 0, gc: 0, gd: 0, points: 6,
          leagueStats: {'PPG': 50.5, 'PCPG': 40.0, 'PD': 10.5},
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeagueTableTab(sport: 'Basketball', standings: rows),
        ),
      ));
      for (final h in ['GP', 'W', 'L', 'PPG', 'PCPG', 'PD', 'Pts']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('D'), findsNothing); // no draws column
      expect(find.text('50.5'), findsOneWidget);
      expect(find.text('10.5'), findsOneWidget);
      expect(find.text('6'), findsOneWidget); // Pts
    });

    testWidgets('flag football shows W L PF PA PD', (tester) async {
      final rows = [
        const TournamentTeam(
          id: 'A', name: 'A', qualification: '',
          gp: 3, wins: 2, draws: 0, losses: 1,
          gs: 0, gc: 0, gd: 0, points: 0,
          leagueStats: {'PF': 46, 'PA': 36, 'PD': 10},
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeagueTableTab(sport: 'Flag Football', standings: rows),
        ),
      ));
      for (final h in ['W', 'L', 'PF', 'PA', 'PD']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('GP'), findsNothing);
      expect(find.text('46'), findsOneWidget);
    });

    testWidgets('futsal keeps the classic columns', (tester) async {
      final rows = [
        const TournamentTeam(
          id: 'One', name: 'One', qualification: '',
          gp: 1, wins: 1, draws: 0, losses: 0,
          gs: 3, gc: 1, gd: 2, points: 3,
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeagueTableTab(sport: 'Futsal', standings: rows),
        ),
      ));
      for (final h in ['GP', 'W', 'D', 'L', 'GF', 'GA', 'GD', 'P']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
    });
  });
}
