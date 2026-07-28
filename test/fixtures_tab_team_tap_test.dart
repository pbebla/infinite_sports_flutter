// Team-tap audit (PR feedback): a match card's team name/logo is its own
// tap target opening the team page, while the card itself still opens the
// match. Only RESOLVED teams (present in the teams map) get a tap target —
// 'Seed #4'/'TBD'/unresolved ids have no team page, so their labels fall
// through to the card tap. See lib/tournament_tabs/fixtures_tab.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';

const _match = TournamentMatch(
  id: 'm1',
  stage: 'Group Stage',
  label: 'Group Stage',
  date: '07242026',
  time: '7:00PM',
  team1Id: 'Babylon',
  team2Id: 'Nineveh',
  team1Score: 0,
  team2Score: 0,
  status: 0,
  bracketPosition: 0,
);

void main() {
  final resolvedTeams = <String, TournamentTeam>{
    'Babylon': leagueTeamStub('Babylon', null),
    'Nineveh': leagueTeamStub('Nineveh', null),
  };

  Widget host({
    required Map<String, TournamentTeam> teams,
    void Function(TournamentTeam team)? onTeamTap,
    void Function(TournamentMatch match)? onMatchTap,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: FixturesTab(
            matches: const [_match],
            teams: teams,
            rosters: const {},
            tournamentId: '',
            sport: 'Futsal',
            onMatchTap: onMatchTap,
            onTeamTap: onTeamTap,
          ),
        ),
      );

  testWidgets('tapping a team name reports that team via onTeamTap, '
      'without also firing the card tap', (tester) async {
    final teamTaps = <String>[];
    final matchTaps = <String>[];
    await tester.pumpWidget(host(
      teams: resolvedTeams,
      onTeamTap: (team) => teamTaps.add(team.id),
      onMatchTap: (match) => matchTaps.add(match.id),
    ));
    await tester.tap(find.text('Babylon'));
    await tester.pump();
    expect(teamTaps, ['Babylon']);
    expect(matchTaps, isEmpty,
        reason: 'a team tap must not double as a card (match) tap');
  });

  testWidgets('both sides get their own tap target', (tester) async {
    final teamTaps = <String>[];
    await tester.pumpWidget(host(
      teams: resolvedTeams,
      onTeamTap: (team) => teamTaps.add(team.id),
    ));
    await tester.tap(find.text('Babylon'));
    await tester.tap(find.text('Nineveh'));
    await tester.pump();
    expect(teamTaps, ['Babylon', 'Nineveh']);
  });

  testWidgets('the card tap still opens the match (center tap)',
      (tester) async {
    final matchTaps = <String>[];
    await tester.pumpWidget(host(
      teams: resolvedTeams,
      onTeamTap: (_) => fail('center tap must not resolve as a team tap'),
      onMatchTap: (match) => matchTaps.add(match.id),
    ));
    await tester.tap(find.text('7:00PM')); // score/time column between teams
    await tester.pump();
    expect(matchTaps, ['m1']);
  });

  testWidgets('unresolved team labels stay card-tap only', (tester) async {
    final teamTaps = <String>[];
    final matchTaps = <String>[];
    await tester.pumpWidget(host(
      teams: const {}, // nothing resolves -> no team pages to open
      onTeamTap: (team) => teamTaps.add(team.id),
      onMatchTap: (match) => matchTaps.add(match.id),
    ));
    await tester.tap(find.text('Babylon')); // raw id label, no team page
    await tester.pump();
    expect(teamTaps, isEmpty);
    expect(matchTaps, ['m1'],
        reason: 'the label tap falls through to the card (match) tap');
  });
}
