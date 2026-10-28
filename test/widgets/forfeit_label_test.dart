// Spec §8a — fan match displays label a forfeited league game
// "5 - 0 · Forfeit": the match list cards (FixturesTab, shared with
// tournaments — which never carry forfeitedBy), the team page rows, and the
// shared ForfeitChip's theme-safe colors in both modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/widgets/forfeit_chip.dart';

/// A Final league game the Manager marked forfeited by team 2 (5–0).
TournamentMatch forfeitedLeagueGame() => leagueMatchFromGameMap(
      dateKey: '10252026',
      index: 0,
      raw: {
        'team1': 'Lions',
        'team2': 'Tigers',
        'team1score': 5,
        'team2score': 0,
        'status': 2,
        'forfeitedBy': 2,
      },
    );

const tournamentFinal = TournamentMatch(
  id: 'm1',
  stage: 'Group Stage',
  label: 'Group Stage',
  date: '10252026',
  team1Id: 'Ann',
  team2Id: 'Bob',
  team1Score: 5,
  team2Score: 0,
  status: 2,
  bracketPosition: 0,
);

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? lightMode,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('match list card: a forfeited league game reads "5 - 0" + '
      'Forfeit; a tournament 5–0 never does', (tester) async {
    final forfeit = forfeitedLeagueGame();
    await tester.pumpWidget(host(FixturesTab(
      matches: [forfeit, tournamentFinal],
      teams: const {},
      rosters: const {},
      tournamentId: '',
      sport: 'Futsal',
    )));
    await tester.pumpAndSettle();

    expect(find.text('5 - 0'), findsNWidgets(2));
    expect(find.text('Forfeit'), findsOneWidget);
    expect(find.byKey(ValueKey('forfeit_score_${forfeit.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('forfeit_score_m1')), findsNothing);
  });

  testWidgets('team page row: "Forfeit" joins the subtitle', (tester) async {
    await tester.pumpWidget(host(LeagueTeamMatchRow(
      teamName: 'Lions',
      match: forfeitedLeagueGame(),
      onTap: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Forfeit'), findsOneWidget);
    expect(find.text('5 - 0'), findsOneWidget);
  });

  testWidgets('ForfeitChip is colorScheme-only in light AND dark',
      (tester) async {
    for (final theme in [lightMode, darkMode]) {
      await tester.pumpWidget(host(const Center(child: ForfeitChip()),
          theme: theme));
      await tester.pumpAndSettle(); // let the theme cross-fade finish
      final text = tester.widget<Text>(find.text('Forfeit'));
      expect(text.style?.color, theme.colorScheme.onTertiaryContainer);
      final box = tester.widget<Container>(find.ancestor(
          of: find.text('Forfeit'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          theme.colorScheme.tertiaryContainer);
      expect(text.style?.decoration ?? TextDecoration.none,
          TextDecoration.none);
    }
  });
}
