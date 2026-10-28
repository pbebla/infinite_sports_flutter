// P6 — the Dream Team card itself: read-only mini court (no bench surface,
// no prices, nothing tappable), points under names, photo lookup from the
// market, short positions leaving quiet empty slots, and the latest-week
// default with session persistence.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

void main() {
  setUp(() {
    DreamTeamCard.sessionWeek = null;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required Map<int, FantasyDreamTeam> teams,
    List<FantasyPlayer> players = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DreamTeamCard(
            teams: teams,
            config: FantasyConfig.futsalDefault(),
            players: players,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the five slots with points, no prices, no bench, '
      'nothing tappable; a short position leaves a quiet empty slot',
      (tester) async {
    final teams = dreamTeamsFromNode({
      '3': {
        'Players': [
          {'name': 'Gale', 'position': 'GK', 'points': 14},
          {'name': 'Dana', 'position': 'DEF', 'points': 12},
          // Only ONE DEF this week (tiny market): the second DEF slot stays
          // an empty affordance.
          {'name': 'Alex', 'position': 'ATT', 'points': 11},
          {'name': 'Bo', 'position': 'ATT', 'points': 8},
        ],
      },
    });
    await pumpCard(tester, teams: teams, players: [
      const FantasyPlayer(
        name: 'Gale',
        position: FantasyPosition.gk,
        priceTenths: 85,
        eligible: true,
        teamName: 'Sharks',
      ),
    ]);

    expect(find.text('Team of the Week · GW3'), findsOneWidget);
    for (final name in ['Gale', 'Dana', 'Alex', 'Bo']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('14 pts'), findsOneWidget);
    expect(find.text('8 pts'), findsOneWidget);
    // Prices stay OFF the nameplates (the market's $8.5M never shows).
    expect(find.textContaining('\$'), findsNothing);
    // The unfilled DEF slot renders its quiet affordance; the bench surface
    // doesn't exist at all in the 5-starter mini mode.
    expect(find.text('+ DEF'), findsOneWidget);
    expect(find.textContaining('Bench ·'), findsNothing);
    // Read-only: no chip reacts to taps.
    final chip = tester
        .widget<FantasyPlayerChip>(find.byKey(const ValueKey('squad_chip_Gale')));
    expect(chip.onTap, isNull);
    // One selectable week: no week chips at all.
    expect(find.byKey(const ValueKey('dream_week_3')), findsNothing);
  });
}
