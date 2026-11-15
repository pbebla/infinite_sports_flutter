// Card-tap rule (owner, 2026-11-14): on a game card, a tap ANYWHERE — team
// names and logos included — opens that game. Team pages open only from
// inside the game's detail page (FotMob behaviour). See
// lib/tournament_tabs/fixtures_tab.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

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

class _PushRecorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  final resolvedTeams = <String, TournamentTeam>{
    'Babylon': leagueTeamStub('Babylon', null),
    'Nineveh': leagueTeamStub('Nineveh', null),
  };

  Widget host({
    required Map<String, TournamentTeam> teams,
    String tournamentId = '',
    void Function(TournamentMatch match)? onMatchTap,
    NavigatorObserver? observer,
  }) =>
      MaterialApp(
        navigatorObservers: [if (observer != null) observer],
        home: Scaffold(
          body: FixturesTab(
            matches: const [_match],
            teams: teams,
            rosters: const {},
            tournamentId: tournamentId,
            sport: 'Futsal',
            onMatchTap: onMatchTap,
          ),
        ),
      );

  for (final tournamentId in ['', 't1']) {
    final kind = tournamentId.isEmpty ? 'league host' : 'tournament host';

    testWidgets('$kind: tapping a team name opens the match, no team page',
        (tester) async {
      final matchTaps = <String>[];
      final recorder = _PushRecorder();
      await tester.pumpWidget(host(
        teams: resolvedTeams,
        tournamentId: tournamentId,
        onMatchTap: (match) => matchTaps.add(match.id),
        observer: recorder,
      ));
      recorder.pushed.clear();
      await tester.tap(find.text('Babylon'));
      await tester.tap(find.text('Nineveh'));
      await tester.pump();
      expect(matchTaps, ['m1', 'm1']);
      expect(recorder.pushed, isEmpty,
          reason: 'a team name on a game card must never open a team page');
    });

    testWidgets('$kind: tapping a team logo opens the match, no team page',
        (tester) async {
      final matchTaps = <String>[];
      final recorder = _PushRecorder();
      await tester.pumpWidget(host(
        teams: resolvedTeams,
        tournamentId: tournamentId,
        onMatchTap: (match) => matchTaps.add(match.id),
        observer: recorder,
      ));
      recorder.pushed.clear();
      final logos = find.byType(TeamLogo);
      expect(logos, findsNWidgets(2));
      await tester.tap(logos.at(0));
      await tester.tap(logos.at(1));
      await tester.pump();
      expect(matchTaps, ['m1', 'm1']);
      expect(recorder.pushed, isEmpty);
    });
  }

  testWidgets('the center of the card still opens the match', (tester) async {
    final matchTaps = <String>[];
    await tester.pumpWidget(host(
      teams: resolvedTeams,
      onMatchTap: (match) => matchTaps.add(match.id),
    ));
    await tester.tap(find.text('7:00PM'));
    await tester.pump();
    expect(matchTaps, ['m1']);
  });

  testWidgets('unresolved team labels also open the match', (tester) async {
    final matchTaps = <String>[];
    await tester.pumpWidget(host(
      teams: const {},
      onMatchTap: (match) => matchTaps.add(match.id),
    ));
    await tester.tap(find.text('Babylon'));
    await tester.pump();
    expect(matchTaps, ['m1']);
  });
}
