// Widget test for the league match page's tab structure (Match Box Score
// spec, 2026-07-28: Summary | <Team 1> | <Team 2> — the Lineup tab is
// hidden until the on-field lineup epic revives it).
//
// LeagueMatchDetailPage itself can't be pumped directly in a widget test:
// its State subscribes to LeagueService Firebase streams with no injection
// seam (the same constraint documented in league_team_detail_tabs_test.dart
// and league_tab_swap_test.dart for the sibling league pages). So this
// harness reproduces the exact DefaultTabController + TabBar([Summary,
// team1, team2]) + TabBarView([MatchFactsTab, TeamBoxScoreTab x2]) the
// page's build method wires, fed by the same Firebase-free adapters
// (leagueMatchFromGameMap / leagueTeamStub / leagueRostersFromLineupsNode /
// singleMatchPlayerTallies) LeagueMatchDetailPage itself uses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/match_tabs/box_score_columns.dart';
import 'package:infinite_sports_flutter/match_tabs/team_box_score_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';

Widget _harness({
  required TournamentMatch match,
  required TournamentTeam? team1,
  required TournamentTeam? team2,
  required List<TournamentPlayer> team1Players,
  required List<TournamentPlayer> team2Players,
  required String sport,
}) {
  final tallies = singleMatchPlayerTallies(match);
  final columns = boxScoreColumnsFor(sport);
  return MaterialApp(
    home: DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              expandedHeight: 196,
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                tabs: [
                  const Tab(text: 'Summary'),
                  Tab(text: team1?.name ?? match.team1Id ?? 'Team 1'),
                  Tab(text: team2?.name ?? match.team2Id ?? 'Team 2'),
                ],
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
              TeamBoxScoreTab(
                roster: team1Players,
                tallies: tallies,
                columns: columns,
              ),
              TeamBoxScoreTab(
                roster: team2Players,
                tallies: tallies,
                columns: columns,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'league match page shows Summary + one tab per team; a team tab '
      'renders that team\'s box score from the same rosters/activity the '
      'Summary tab uses', (tester) async {
    final match = leagueMatchFromGameMap(
      dateKey: '06152026',
      index: 0,
      raw: {
        'team1': 'Nineveh',
        'team2': 'Babylon',
        'team1score': 2,
        'team2score': 1,
        'status': 2,
        'team1activity': {
          "7'": [
            {'Goal': 'Ashur'},
          ],
        },
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

    // All three tab labels present; Summary is the initial view (no roster
    // rows rendered there — just the timeline/leaders/location). 'Ashur'
    // appears once in the Summary timeline for his goal.
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Nineveh'), findsOneWidget);
    expect(find.text('Babylon'), findsOneWidget);
    expect(find.text('#10'), findsNothing);

    await tester.tap(find.text('Nineveh'));
    await tester.pumpAndSettle();

    // Team tab renders the team's box score rows (name + number) with the
    // Goals column visible (recorded) and all-zero columns hidden.
    expect(find.text('Ashur'), findsOneWidget);
    expect(find.text('#10'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Saves'), findsNothing);

    // Other team's tab shows its own roster only.
    await tester.tap(find.text('Babylon'));
    await tester.pumpAndSettle();
    expect(find.text('Ninos'), findsOneWidget);
    expect(find.text('#9'), findsOneWidget);
    expect(find.text('Ashur'), findsNothing);
  });
}
