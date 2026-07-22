// Widget test for the league match page's Facts/Lineup tab structure
// (L6.2 Task 1: parity with TournamentMatchDetailPage).
//
// LeagueMatchDetailPage itself can't be pumped directly in a widget test:
// its State subscribes to LeagueService Firebase streams with no injection
// seam (the same constraint documented in league_team_detail_tabs_test.dart
// and league_tab_swap_test.dart for the sibling league pages). So this
// harness reproduces the exact DefaultTabController + TabBar([Facts,
// Lineup]) + TabBarView([MatchFactsTab, MatchLineupTab]) the page's build
// method wires, fed by the same Firebase-free adapters
// (leagueMatchFromGameMap / leagueTeamStub / leagueRostersFromLineupsNode)
// LeagueMatchDetailPage itself uses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_lineup_tab.dart';

Widget _harness({
  required TournamentMatch match,
  required TournamentTeam? team1,
  required TournamentTeam? team2,
  required List<TournamentPlayer> team1Players,
  required List<TournamentPlayer> team2Players,
  required String sport,
}) {
  return MaterialApp(
    home: DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 196,
              bottom: const TabBar(
                tabs: [Tab(text: 'Facts'), Tab(text: 'Lineup')],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              MatchFactsTab(
                match: match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                leagueSportKey: sport,
              ),
              MatchLineupTab(
                match: match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                sport: sport,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('league match page shows both Facts and Lineup tabs; Lineup '
      'renders the same rosters the Facts tab uses', (tester) async {
    final match = leagueMatchFromGameMap(
      dateKey: '06152026',
      index: 0,
      raw: {
        'team1': 'Nineveh',
        'team2': 'Babylon',
        'team1score': 2,
        'team2score': 1,
        'status': 2,
      },
    );
    final rosters = leagueRostersFromLineupsNode('Futsal', {
      'Nineveh': {
        'Ashur': {'Goals': 2, 'number': '10'},
      },
      'Babylon': {
        'Ninos': {'Goals': 1, 'number': '9'},
      },
    });

    await tester.pumpWidget(_harness(
      match: match,
      team1: leagueTeamStub('Nineveh', null),
      team2: leagueTeamStub('Babylon', null),
      team1Players: rosters['Nineveh']!,
      team2Players: rosters['Babylon']!,
      sport: 'Futsal',
    ));

    // Both tab labels present; Facts is the initial view (no roster names
    // rendered directly there — just the timeline/leaders/location).
    expect(find.text('Facts'), findsOneWidget);
    expect(find.text('Lineup'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);

    await tester.tap(find.text('Lineup'));
    await tester.pumpAndSettle();

    // Lineup tab renders both team rosters (same players fed to Facts).
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('Ninos'), findsOneWidget);
  });
}
