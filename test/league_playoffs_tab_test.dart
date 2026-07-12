import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_playoffs_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

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

  // P2.2 owner item 1 regression: EVERY bracket box with a real underlying
  // game — semifinal card, final hero AND bronze — must fire onMatchTap
  // with that game's id (the league page routes it to the MATCH page,
  // never a team page; team taps live inside the match page's header).
  testWidgets('semifinal card, final hero and bronze taps all open the match',
      (tester) async {
    final matches = leagueMatchesFromDateNode({
      '07132026': [
        {'team1': 'AFC', 'team2': 'Lamassu', 'team1score': 4, 'team2score': 1, 'status': 2, 'Stage': 'semifinal'},
        {'team1': 'Urmi', 'team2': 'Hakkari', 'team1score': 2, 'team2score': 3, 'status': 2, 'Stage': 'semifinal'},
      ],
      '07202026': [
        {'team1': 'AFC', 'team2': 'Hakkari', 'team1score': 3, 'team2score': 1, 'status': 2, 'Stage': 'final'},
        {'team1': 'Lamassu', 'team2': 'Urmi', 'team1score': 2, 'team2score': 0, 'status': 2, 'Stage': 'third place'},
      ],
    });
    final playoffs = LeaguePlayoffs.fromNode({
      'Format': 4,
      'ThirdPlace': true,
      'Champion': 'AFC',
      'Slots': {
        'sf1': {'gameRef': {'date': '07132026', 'index': 0}},
        'sf2': {'gameRef': {'date': '07132026', 'index': 1}},
        'f1': {'gameRef': {'date': '07202026', 'index': 0}},
        'tp1': {'gameRef': {'date': '07202026', 'index': 1}},
      },
    });
    final teams = {
      for (final n in ['AFC', 'Hakkari', 'Urmi', 'Lamassu'])
        n: leagueTeamStub(n, null),
    };
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeaguePlayoffsTab(
          playoffs: playoffs,
          matches: matches,
          teams: teams,
          season: '16',
          onMatchTap: (TournamentMatch m) => tapped.add(m.id),
        ),
      ),
    ));
    await tester.pump();

    // Semifinal card (SF1 'AFC vs Lamassu').
    await tester.tap(find.text('Lamassu').first, warnIfMissed: false);
    // Final hero: its team texts render AFTER the round-0 cards in the
    // bracket Stack, so .last of 'Hakkari' is the hero's team2 column.
    await tester.tap(find.text('Hakkari').last, warnIfMissed: false);
    // Bronze card sits beneath the hero — its 'Lamassu' text is last.
    await tester.tap(find.text('Lamassu').last, warnIfMissed: false);
    await tester.pump();

    expect(tapped, ['07132026#0', '07202026#0', '07202026#1']);
  });

  testWidgets('unresolved final hero (empty team slots) does not open a match',
      (tester) async {
    // League adapter yields '' (never null) for unset team1/team2 — the
    // hero must stay un-tappable until the manager resolves the final.
    final matches = leagueMatchesFromDateNode({
      '07202026': [
        {'team1': '', 'team2': '', 'status': 0, 'Stage': 'final'},
      ],
    });
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeaguePlayoffsTab(
          playoffs: null,
          matches: matches,
          teams: const {},
          season: '16',
          onMatchTap: (_) => taps++,
        ),
      ),
    ));
    await tester.pump();
    // Both hero slots render TBD; tapping does nothing.
    await tester.tap(find.text('TBD').first, warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
  });
}
