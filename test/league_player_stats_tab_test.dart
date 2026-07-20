import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/league_tabs/league_player_stats_tab.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

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
        body: LeaguePlayerStatsTab(
            sport: 'Futsal', rosters: rosters, teams: const {}),
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
        body: LeaguePlayerStatsTab(sport: 'Futsal', rosters: {}, teams: {}),
      ),
    ));
    expect(find.text('No player stats yet'), findsOneWidget);
  });

  group('P4 — per-sport leader categories', () {
    TournamentPlayer bballer(String name, Map<String, int> extra) =>
        TournamentPlayer(
          name: name, teamId: 'T', teamName: 'T',
          goals: 0, assists: extra['assists'] ?? 0, saves: 0, dpl: 0,
          cleanSheets: 0, yellowCards: 0, redCards: 0,
          extraStats: extra,
        );

    testWidgets('basketball renders Points/Rebounds/Assists/3-Pointers/'
        'Steals/Blocks cards', (tester) async {
      // Six single-player cards overflow the default 600px test viewport
      // before the lazy ListView builds the last one (the same "below the
      // fold" caveat as the futsal test above) — grow the surface so every
      // category actually builds and the label assertions are meaningful.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rosters = {
        'T': [
          bballer('Sam', {'points': 22, 'rebounds': 9, 'assists': 4,
            'threePointers': 3, 'steals': 2, 'blocks': 1}),
        ],
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeaguePlayerStatsTab(
              sport: 'Basketball', rosters: rosters, teams: const {}),
        ),
      ));
      await tester.pump();
      for (final label in [
        'Points', 'Rebounds', 'Assists', '3-Pointers', 'Steals', 'Blocks',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Top Scorer'), findsNothing); // futsal list absent
    });

    testWidgets('flag football renders the Catch % category with a % value '
        '(L6.1)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rosters = {
        'T': [
          bballer('Sam', {'receptions': 7, 'catchPercentage': 70}),
          // Gated player (adapter emitted 0 for a <3-target sample):
          // excluded from the Catch % card by the "> 0" leaders filter.
          bballer('Tiny', {'receptions': 1, 'catchPercentage': 0}),
        ],
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeaguePlayerStatsTab(
              sport: 'Flag Football', rosters: rosters, teams: const {}),
        ),
      ));
      await tester.pump();
      expect(find.text('Catch %'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      // Receptions card still shows plain counts (no suffix).
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('futsal categories unchanged', (tester) async {
      final rosters = {
        'T': [
          const TournamentPlayer(
            name: 'Sam', teamId: 'T', teamName: 'T',
            goals: 5, assists: 0, saves: 0, dpl: 0,
            cleanSheets: 0, yellowCards: 0, redCards: 0,
          ),
        ],
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeaguePlayerStatsTab(
              sport: 'Futsal', rosters: rosters, teams: const {}),
        ),
      ));
      await tester.pump();
      expect(find.text('Top Scorer'), findsOneWidget);
    });
  });
}
