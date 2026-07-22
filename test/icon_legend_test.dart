import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/tournament_tabs/icon_legend.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';

TournamentMatch _upcomingMatch({String? team1, String? team2}) =>
    TournamentMatch(
      id: 'm1',
      stage: 'League',
      label: 'League',
      date: '07202026',
      team1Id: team1,
      team2Id: team2,
      team1Score: 0,
      team2Score: 0,
      status: 0, // pending / upcoming
      bracketPosition: 0,
    );

void main() {
  group('legendEntriesForSport', () {
    test('null (tournament) resolves the full soccer set, badge:false', () {
      final entries = legendEntriesForSport(null);
      expect(entries.map((e) => e.label), [
        'Goal', 'Own Goal', 'Penalty Goal', 'Penalty Missed',
        'Penalty Saved', 'Save', 'Assist', 'Substitution', 'Yellow Card',
        'Second Yellow', 'Red Card', 'Foul', 'DPL',
      ]);
      expect(entries.every((e) => e.badge == false), isTrue);
      expect(entries.every((e) => e.asset != null), isTrue);
      expect(entries.firstWhere((e) => e.label == 'Goal').asset,
          'assets/goal.png');
    });

    test('Futsal resolves the same soccer set as null/tournament', () {
      expect(legendEntriesForSport('Futsal'), legendEntriesForSport(null));
    });

    test('Soccer resolves the same soccer set as null/tournament', () {
      expect(legendEntriesForSport('Soccer'), legendEntriesForSport(null));
    });

    test('Basketball resolves the badge set ending in Foul (badge:false)',
        () {
      final entries = legendEntriesForSport('Basketball');
      expect(entries.map((e) => e.label), [
        'Free Throw Made', '2-Pointer', '3-Pointer', 'Rebound', 'Assist',
        'Steal', 'Block', 'Turnover', 'Foul',
      ]);
      // Every basketball entry is a gold badge (Foul included since L6.2).
      for (final e in entries) {
        expect(e.badge, isTrue, reason: '${e.label} should be a badge');
      }
      expect(entries.last.label, 'Foul');
      expect(entries.last.asset, 'assets/bball_foul.png');
      expect(entries.firstWhere((e) => e.label == 'Rebound').asset,
          'assets/bball_rebound.png');
    });

    test('Flag Football resolves all 16 entries in owner order, all badges',
        () {
      final entries = legendEntriesForSport('Flag Football');
      expect(entries.map((e) => e.label), [
        'Completion', 'Incompletion', 'Reception', 'Drop', 'Receiving TD',
        'Rushing TD', 'Pick-Six', 'Pass TD', 'Interception', 'Flag Pull',
        'Sack', 'Pass Breakup', 'PAT Made', 'PAT Missed', '2PT Made',
        '2PT Missed',
      ]);
      expect(entries.every((e) => e.badge == true), isTrue);
      expect(entries.every((e) => e.asset != null), isTrue);
      expect(entries.firstWhere((e) => e.label == 'Drop').asset,
          'assets/ff_rec_miss.png');
      expect(entries.firstWhere((e) => e.label == 'Pick-Six').asset,
          'assets/ff_int_td.png');
    });
  });

  group('IconLegend widget', () {
    testWidgets('renders the "Icons" card with every soccer label',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: IconLegend()),
      ));
      expect(find.text('Icons'), findsOneWidget);
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('DPL'), findsOneWidget);
      expect(find.byType(StatIcon), findsWidgets);
    });

    testWidgets('renders for Basketball with gold badge icons',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: IconLegend(leagueSportKey: 'Basketball')),
      ));
      expect(find.text('Icons'), findsOneWidget);
      expect(find.text('Free Throw Made'), findsOneWidget);
      expect(find.text('Turnover'), findsOneWidget);
    });
  });

  group('MatchFactsTab wires the legend into every state (L6.2 Task 2)', () {
    testWidgets('upcoming match, NO rosters at all (empty-state early '
        'return) still shows the Icons legend', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MatchFactsTab(
            match: _upcomingMatch(team1: 'A', team2: 'B'),
            team1: null,
            team2: null,
            team1Players: const [],
            team2Players: const [],
          ),
        ),
      ));
      expect(find.text('Match not started yet'), findsOneWidget);
      expect(find.text('Icons'), findsOneWidget);
    });

    testWidgets('upcoming match WITH rosters (main return path) still shows '
        'the Icons legend', (tester) async {
      final roster = [
        const TournamentPlayer(
          name: 'Sam', teamId: 'A', teamName: 'A',
          goals: 0, assists: 0, saves: 0, dpl: 0,
          cleanSheets: 0, yellowCards: 0, redCards: 0,
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MatchFactsTab(
            match: _upcomingMatch(team1: 'A', team2: 'B'),
            team1: null,
            team2: null,
            team1Players: roster,
            team2Players: const [],
          ),
        ),
      ));
      expect(find.text('No activity recorded yet'), findsOneWidget);
      expect(find.text('Icons'), findsOneWidget);
    });

    testWidgets('league (Basketball) upcoming match shows the badge legend',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MatchFactsTab(
            match: _upcomingMatch(team1: 'A', team2: 'B'),
            team1: null,
            team2: null,
            team1Players: const [],
            team2Players: const [],
            leagueSportKey: 'Basketball',
          ),
        ),
      ));
      expect(find.text('Icons'), findsOneWidget);
      expect(find.text('Free Throw Made'), findsOneWidget);
    });
  });
}
