import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_player_stats_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';

void main() {
  final rosters = leagueRostersFromLineupsNode('Futsal', {
    'Nineveh': {
      'Ashur': {'Goals': 9, 'Assists': 3, 'number': '10'},
      'Sargon': {'Saves': 20, 'CleanSheets': 4, 'number': '1'},
    },
    'Babylon': {
      'Ninos': {'Goals': 6, 'DPL': 5, 'number': '7'},
    },
  });

  testWidgets('renders leader categories with the top scorer first',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeaguePlayerStatsTab(rosters: rosters, teams: const {}),
      ),
    ));
    expect(find.text('Top Scorer'), findsOneWidget);
    // 'Saves' is safely inside the 600px test viewport; lower cards (Clean
    // Sheets) can sit below the lazy ListView fold — don't assert on them.
    expect(find.text('Saves'), findsOneWidget);
    expect(find.text('Ashur'), findsWidgets);
    // Categories with no counts stay hidden.
    expect(find.text('Red Cards'), findsNothing);
    // Ashur (9 goals) ranks above Ninos (6) in the Top Scorer card.
    final ashurY = tester.getTopLeft(find.text('Ashur').first).dy;
    final ninosY = tester.getTopLeft(find.text('Ninos').first).dy;
    expect(ashurY, lessThan(ninosY));
  });

  testWidgets('empty rosters show the placeholder', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LeaguePlayerStatsTab(rosters: {}, teams: {}),
      ),
    ));
    expect(find.text('No player stats yet'), findsOneWidget);
  });
}
