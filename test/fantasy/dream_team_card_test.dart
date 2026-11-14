// P6 — the Dream Team card itself: read-only mini court (no bench surface,
// no prices, nothing editable), points under names, photo lookup from the
// market, short positions leaving quiet empty slots, and the latest-week
// default with session persistence. Round 3: a chip tap opens the player's
// profile through the hub callback (inert without one). Opus audit item 7:
// long names + many week chips + the share button at 360 px in light AND
// dark, scrolled through with no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

void main() {
  setUp(() {
    DreamTeamCard.sessionWeek = null;
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required Map<int, FantasyDreamTeam> teams,
    List<FantasyPlayer> players = const [],
    void Function(String playerName)? onOpenPlayer,
    Size size = const Size(420, 1200),
    Brightness brightness = Brightness.light,
    String? seasonLabel,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DreamTeamCard(
            teams: teams,
            config: FantasyConfig.futsalDefault(),
            players: players,
            onOpenPlayer: onOpenPlayer,
            seasonLabel: seasonLabel,
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
    // Without an opener (standalone card) no chip reacts to taps.
    final chip = tester
        .widget<FantasyPlayerChip>(find.byKey(const ValueKey('squad_chip_Gale')));
    expect(chip.onTap, isNull);
    // One selectable week: no week chips at all.
    expect(find.byKey(const ValueKey('dream_week_3')), findsNothing);
  });

  test('resolveWeek: the session pick while that week exists, else the '
      'latest (the one rule the card and the Leaderboards week-sync share)',
      () {
    expect(DreamTeamCard.resolveWeek([1, 2, 3]), 3);
    DreamTeamCard.sessionWeek = 2;
    expect(DreamTeamCard.resolveWeek([1, 2, 3]), 2);
    expect(DreamTeamCard.resolveWeek([3, 1, 2]), 2); // order-independent
    DreamTeamCard.sessionWeek = 9; // stale: no such week any more
    expect(DreamTeamCard.resolveWeek([1, 2, 3]), 3);
    expect(DreamTeamCard.resolveWeek([7]), 7);
  });

  testWidgets('round 3: tapping a Team of the Week player opens his profile; '
      'an empty slot stays inert', (tester) async {
    final teams = dreamTeamsFromNode({
      '3': {
        'Players': [
          {'name': 'Gale', 'position': 'GK', 'points': 14},
          {'name': 'Dana', 'position': 'DEF', 'points': 12},
          // One DEF short: the second DEF slot is an empty affordance.
          {'name': 'Alex', 'position': 'ATT', 'points': 11},
          {'name': 'Bo', 'position': 'ATT', 'points': 8},
        ],
      },
    });
    final opened = <String>[];
    await pumpCard(tester, teams: teams, onOpenPlayer: opened.add);

    for (final name in ['Gale', 'Alex', 'Bo']) {
      await tester.tap(find.byKey(ValueKey('squad_chip_$name')));
      await tester.pumpAndSettle();
    }
    expect(opened, ['Gale', 'Alex', 'Bo']);

    await tester.tap(find.text('+ DEF'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(3));
  });

  // Release report #10: at phone width the name boxes of one row crowded
  // into the photos of the row below. In the hub the card sits inside 12 px
  // page padding, so the court is ~308 px wide at a 360 px screen.
  for (final brightness in Brightness.values) {
    testWidgets('360 px ($brightness): no row chip (photo + 2-line name '
        'box + points) overlaps the next row', (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Two-line names everywhere: the tallest nameplates.
      const gk = 'Anthony Memon Longname';
      const defs = ['Demsin Bet varda', 'Pedro Siva Longname'];
      const atts = ['Eli Derazizyan Long', 'Bruno Siva Longname'];
      final teams = dreamTeamsFromNode({
        '12': {
          'Players': [
            {'name': gk, 'position': 'GK', 'points': -2},
            for (final n in defs) {'name': n, 'position': 'DEF', 'points': 16},
            for (final n in atts) {'name': n, 'position': 'ATT', 'points': 11},
          ],
        },
      });
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DreamTeamCard(
                teams: teams,
                config: FantasyConfig.futsalDefault(),
                players: const [],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Rect chip(String n) =>
          tester.getRect(find.byKey(ValueKey('squad_chip_$n')));
      for (final d in defs) {
        expect(chip(gk).bottom, lessThanOrEqualTo(chip(d).top),
            reason: 'GK name box runs into $d');
        for (final a in atts) {
          expect(chip(d).bottom, lessThanOrEqualTo(chip(a).top),
              reason: '$d name box runs into $a');
        }
      }
    });
  }

  // Opus audit item 7: 360 px in light AND dark.
  for (final brightness in Brightness.values) {
    testWidgets('360 px: long names, twelve week chips and the share button '
        'fit — no overflow when scrolled through — $brightness',
        (tester) async {
      const longGk = 'Maximiliano Bartholomew Featherstonehaugh-Smythe';
      const longAtt = 'Alessandro Von Grünewald-Montgomery';
      final teams = dreamTeamsFromNode({
        for (var w = 1; w <= 12; w++)
          '$w': {
            'Players': [
              {'name': longGk, 'position': 'GK', 'points': 140 + w},
              {'name': 'Dana Wall', 'position': 'DEF', 'points': 12},
              {'name': 'Yara Stone', 'position': 'DEF', 'points': 9},
              {'name': longAtt, 'position': 'ATT', 'points': 11},
              {'name': 'Bo', 'position': 'ATT', 'points': 8},
            ],
          },
      });
      await pumpCard(tester,
          teams: teams,
          size: const Size(360, 640),
          brightness: brightness,
          seasonLabel: 'Futsal Season 15');
      expect(tester.takeException(), isNull);
      for (final key in ['dream_team_card', 'dream_team_title',
          'dream_team_share']) {
        final r = tester.getRect(find.byKey(ValueKey(key)));
        expect(r.left, greaterThanOrEqualTo(0), reason: key);
        expect(r.right, lessThanOrEqualTo(360), reason: key);
      }

      // Through the week chips (their own horizontal strip) and down the
      // court to the last chip.
      final strip = find.ancestor(
          of: find.byKey(const ValueKey('dream_week_1')),
          matching: find.byType(Scrollable));
      await tester.drag(strip.first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
          find.byKey(const ValueKey('squad_chip_Bo')),
          find.byType(Scrollable).first,
          const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style?.decoration, isNot(TextDecoration.underline),
            reason: t.data);
      }
    });
  }

  // ── Live everywhere (Task 6) ─────────────────────────────────────────────
  group('live Team of the Week', () {
    const subline = 'Can still change until the last game ends.';

    Map<int, FantasyDreamTeam> teamWeek(int gw, {required bool live}) {
      final official = dreamTeamsFromNode({
        '$gw': {
          'Players': [
            {'name': 'Gale', 'position': 'GK', 'points': 14},
            {'name': 'Dana', 'position': 'DEF', 'points': 12},
            {'name': 'Yara', 'position': 'DEF', 'points': 9},
            {'name': 'Alex', 'position': 'ATT', 'points': 11},
            {'name': 'Bo', 'position': 'ATT', 'points': 8},
          ],
        },
      })[gw]!;
      return {
        gw: FantasyDreamTeam(players: official.players, live: live),
      };
    }

    // The pill pulses forever, so pump fixed durations (never pumpAndSettle)
    // unless reduced motion holds it still.
    Future<void> pumpLive(
      WidgetTester tester, {
      required Map<int, FantasyDreamTeam> teams,
      Size size = const Size(420, 1200),
      Brightness brightness = Brightness.light,
      bool reduceMotion = false,
      String? seasonLabel,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DreamTeamCard(
              teams: teams,
              config: FantasyConfig.futsalDefault(),
              players: const [],
              seasonLabel: seasonLabel,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a live week shows the pill and the "can still change" '
        'subline; the same week once official shows neither', (tester) async {
      await pumpLive(tester, teams: teamWeek(3, live: true));
      expect(find.text('Team of the Week · GW3'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('dream_team_card')),
              matching: find.byType(FantasyLivePill)),
          findsOneWidget);
      expect(find.text(subline), findsOneWidget);
      // The pill sits with the title; the subline UNDER it.
      expect(tester.getTopLeft(find.text(subline)).dy,
          greaterThan(tester.getBottomLeft(
                  find.byKey(const ValueKey('dream_team_title'))).dy -
              0.5));

      await pumpLive(tester, teams: teamWeek(3, live: false));
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(find.text(subline), findsNothing);
    });

    testWidgets('stepping back to a settled week drops the pill and the '
        'subline; the live week brings them back', (tester) async {
      final teams = {
        ...teamWeek(2, live: false),
        ...teamWeek(3, live: true),
      };
      await pumpLive(tester, teams: teams);
      expect(find.text(subline), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dream_week_2')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Team of the Week · GW2'), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(find.text(subline), findsNothing);

      await tester.tap(find.byKey(const ValueKey('dream_week_3')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FantasyLivePill), findsOneWidget);
      expect(find.text(subline), findsOneWidget);
    });

    testWidgets('reduced motion holds the pill still (nothing keeps '
        'scheduling frames)', (tester) async {
      await pumpLive(tester,
          teams: teamWeek(3, live: true), reduceMotion: true);
      await tester.pumpAndSettle();
      expect(find.byType(FantasyLivePill), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: pill + subline + week chips + share button fit '
          '— $brightness', (tester) async {
        final teams = <int, FantasyDreamTeam>{
          for (var w = 1; w <= 11; w++) ...teamWeek(w, live: false),
          ...teamWeek(12, live: true),
        };
        await pumpLive(tester,
            teams: teams,
            size: const Size(360, 640),
            brightness: brightness,
            seasonLabel: 'Futsal Season 15');
        expect(tester.takeException(), isNull);
        for (final finder in [
          find.byKey(const ValueKey('dream_team_card')),
          find.byKey(const ValueKey('dream_team_title')),
          find.byKey(const ValueKey('dream_team_share')),
          find.byType(FantasyLivePill),
          find.text(subline),
        ]) {
          final r = tester.getRect(finder);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$finder');
          expect(r.right, lessThanOrEqualTo(360), reason: '$finder');
        }
        final note = tester.widget<Text>(find.text(subline));
        expect(note.overflow, isNot(TextOverflow.ellipsis));
        expect(note.style?.decoration, isNot(TextDecoration.underline));
      });
    }
  });
}
