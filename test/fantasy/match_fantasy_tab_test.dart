// P6 — the match-page Fantasy tab proved with fake streams (no Firebase):
// single fade reveal once game+players+squad land; the pre-kickoff face on
// an unstarted node; ranked "+N · Name (POS)" rows with the viewer's picks
// highlighted (YOURS) and the captain's ×2 math; "No returns yet" collapsed
// until tapped; the earning chip's counter animating ONLY on a genuine
// increase (re-mounts with the session store never replay the tween); the
// hub button seam; and (round 3) every points row opening the player's
// fantasy profile from outside the hub.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_tab.dart';

FantasyPlayer player(String name, FantasyPosition pos,
        {String team = 'Sharks'}) =>
    FantasyPlayer(
      name: name,
      position: pos,
      priceTenths: 60,
      eligible: true,
      teamName: team,
    );

/// The logic test's live 2–0 Sharks game: Alex 10, Gale 10, Dana 12, Yara 5,
/// Wren absent (omitted), Zed present on 0 ("No returns yet").
Map gameNode({int status = 1, int danaGoals = 1}) => {
      'team1': 'Sharks',
      'team2': 'Wolves',
      'team1score': 1 + danaGoals,
      'team2score': 0,
      'status': status,
      'team1activity': {
        "5'": [
          {'Goal': 'Alex'},
          {'Assist': 'Alex'},
        ],
        "9'": [
          {'Save': 'Gale'},
          {'Save': 'Gale'},
        ],
        "12'": [
          for (var i = 0; i < danaGoals; i++) {'Goal': 'Dana'},
          {'Yellow': 'Yara'},
        ],
      },
      'team2activity': {
        "15'": [
          {'Goal': 'Wren'},
        ],
      },
      'team2attendance': {'Wren': false},
    };

Map<String, List<String>> rosters() => {
      'Sharks': ['Alex', 'Gale', 'Dana', 'Yara'],
      'Wolves': ['Wren', 'Zed'],
    };

List<FantasyPlayer> market() => [
      player('Alex', FantasyPosition.att),
      player('Gale', FantasyPosition.gk),
      player('Dana', FantasyPosition.def),
      player('Yara', FantasyPosition.def),
      player('Wren', FantasyPosition.att, team: 'Wolves'),
      player('Zed', FantasyPosition.def, team: 'Wolves'),
    ];

FantasySquad squad() => const FantasySquad(
      picks: [
        SquadPick(
            playerId: 'Gale', position: FantasyPosition.gk, priceTenths: 60),
        SquadPick(
            playerId: 'Dana', position: FantasyPosition.def, priceTenths: 60),
        SquadPick(
            playerId: 'Alex', position: FantasyPosition.att, priceTenths: 60),
        SquadPick(
            playerId: 'Wren', position: FantasyPosition.att, priceTenths: 60),
        SquadPick(
            playerId: 'Zed',
            position: FantasyPosition.def,
            priceTenths: 60,
            bench: true),
      ],
      captainId: 'Alex',
      viceId: 'Gale',
    );

void main() {
  late StreamController<Object?> game;
  late StreamController<List<FantasyPlayer>> players;
  late StreamController<FantasySquad?> squads;
  late Map<String, int> store;
  late int hubOpens;
  late List<Map<String, Object?>> profileOpens;

  setUp(() {
    // sync: delivery lands inside the test body, so pump() frames sample the
    // tween at deterministic times.
    game = StreamController<Object?>.broadcast(sync: true);
    players = StreamController<List<FantasyPlayer>>.broadcast(sync: true);
    squads = StreamController<FantasySquad?>.broadcast(sync: true);
    store = {};
    hubOpens = 0;
    profileOpens = [];
  });

  tearDown(() {
    game.close();
    players.close();
    squads.close();
  });

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MatchFantasyTab(
          sport: 'Futsal',
          season: '15',
          dateKey: '06152026',
          gameIndex: 0,
          configState: FantasyConfigState(
            config: FantasyConfig.futsalDefault(),
            lockOverride: FantasyLockOverride.auto,
          ),
          rosterNamesByTeam: rosters(),
          gameNodeStates: game.stream,
          playersStates: players.stream,
          squadStates: squads.stream,
          onOpenHub: () => hubOpens++,
          earningStore: store,
          // Test seam for openFantasyPlayerProfile: records every argument.
          profileOpener: (context,
              {required sport,
              required season,
              required playerName,
              draft,
              fromOutsideHub = false}) async {
            profileOpens.add({
              'sport': sport,
              'season': season,
              'name': playerName,
              'draft': draft,
              'outside': fromOutsideHub,
            });
          },
        ),
      ),
    ));
  }

  Future<void> emitAll(
    WidgetTester tester, {
    Map? node,
    FantasySquad? viewerSquad,
  }) async {
    game.add(node ?? gameNode());
    players.add(market());
    squads.add(viewerSquad);
    await tester.pumpAndSettle();
  }

  testWidgets('skeleton until game+players+squad land, then ONE fade to the '
      'ranked rows', (tester) async {
    await pumpTab(tester);
    expect(find.byKey(const ValueKey('match_fantasy_skeleton')),
        findsOneWidget);

    game.add(gameNode());
    players.add(market());
    await tester.pump();
    // Two of three landed: still the skeleton.
    expect(find.byKey(const ValueKey('match_fantasy_skeleton')),
        findsOneWidget);

    squads.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('match_fantasy_ready')), findsOneWidget);
    expect(find.byKey(const ValueKey('match_fantasy_skeleton')), findsNothing);
  });

  testWidgets('pre-kickoff: no rows, the kickoff face + working hub button',
      (tester) async {
    await pumpTab(tester);
    await emitAll(tester, node: gameNode(status: 0));
    expect(find.byKey(const ValueKey('match_fantasy_prekickoff')),
        findsOneWidget);
    expect(find.text('Dana (DEF)'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('match_fantasy_open_hub')));
    expect(hubOpens, 1);
  });

  testWidgets('live game: ranked rows, absent omitted, scoreless collapsed '
      'until tapped, footnote present', (tester) async {
    await pumpTab(tester);
    await emitAll(tester);

    // Ranked: Dana 12, then the Alex/Gale tie at 10, Yara 5.
    expect(find.text('+12'), findsOneWidget);
    expect(find.text('Dana (DEF)'), findsOneWidget);
    expect(find.text('+10'), findsNWidgets(2));
    expect(find.text('Yara (DEF)'), findsOneWidget);
    // Wren is absent: omitted entirely despite the goal event.
    expect(find.textContaining('Wren'), findsNothing);
    // Zed (0 points) hides behind the collapsed "No returns yet".
    expect(find.text('No returns yet (1)'), findsOneWidget);
    expect(find.text('Zed (DEF)'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('match_fantasy_scoreless_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Zed (DEF)'), findsOneWidget);
    // The raw-points disclaimer is always on the tab.
    expect(find.byKey(const ValueKey('match_fantasy_footnote')),
        findsOneWidget);
    // Signed out / no squad: no earning chip, nothing highlighted.
    expect(find.byKey(const ValueKey('match_fantasy_earning_chip')),
        findsNothing);
    expect(find.textContaining('YOURS'), findsNothing);
  });

  testWidgets('viewer squad: YOURS highlights (bench pick too), captain ×2 '
      'math, earning chip sums captain-doubled', (tester) async {
    await pumpTab(tester);
    await emitAll(tester, viewerSquad: squad());

    // Gale + Dana + Alex scored rows highlighted; Zed highlighted inside
    // the expanded scoreless section.
    expect(find.textContaining('YOURS'), findsNWidgets(3));
    await tester
        .tap(find.byKey(const ValueKey('match_fantasy_scoreless_toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('YOURS'), findsNWidgets(4));

    // Captain Alex: the ×2 math is spelled out.
    expect(find.byKey(const ValueKey('captain_math_Alex')), findsOneWidget);
    expect(find.textContaining('×2 applied · +10 × 2 = +20 for you'),
        findsOneWidget);

    // Chip: Gale 10 + Dana 12 + Alex 10×2 = 42.
    expect(find.byKey(const ValueKey('match_fantasy_earning_chip')),
        findsOneWidget);
    expect(find.text('+42'), findsOneWidget);
  });

  testWidgets('forfeit (spec §8a): header note, the team that showed up as '
      '"+1" rows, the forfeiting team omitted', (tester) async {
    await pumpTab(tester);
    final node = gameNode(status: 2)
      ..['team1score'] = 5
      ..['team2score'] = 0
      ..['forfeitedBy'] = 2;
    await emitAll(tester, node: node, viewerSquad: squad());

    expect(find.byKey(const ValueKey('match_fantasy_forfeit_note')),
        findsOneWidget);
    expect(find.text('Forfeit'), findsOneWidget);
    expect(find.textContaining('Wolves forfeited.'), findsOneWidget);
    // Sharks: four present rostered players, +1 each, stray stats ignored.
    expect(find.text('+1'), findsNWidgets(4));
    for (final name in ['Alex (ATT)', 'Gale (GK)', 'Dana (DEF)', 'Yara (DEF)']) {
      expect(find.text(name), findsOneWidget);
    }
    // Wolves forfeited: no rows, no "No returns yet" for Zed.
    expect(find.textContaining('Zed'), findsNothing);
    expect(find.textContaining('Wren'), findsNothing);
    expect(find.byKey(const ValueKey('match_fantasy_scoreless_toggle')),
        findsNothing);
    // Viewer: Gale 1 + Dana 1 + Alex 1×2 = 4.
    expect(find.text('+4'), findsOneWidget);
  });

  testWidgets('no forfeit note on a normal game', (tester) async {
    await pumpTab(tester);
    await emitAll(tester);
    expect(find.byKey(const ValueKey('match_fantasy_forfeit_note')),
        findsNothing);
  });

  testWidgets('earning counter tweens on a genuine increase only: live goal '
      'animates; a re-mount with the session store repaints statically',
      (tester) async {
    await pumpTab(tester);
    await emitAll(tester, viewerSquad: squad());
    expect(find.text('+42'), findsOneWidget);

    // Dana scores again: 42 -> 48. Mid-tween (125ms of 250ms) the counter
    // reads the halfway value — the animation genuinely runs.
    game.add(gameNode(danaGoals: 2));
    await tester.pump(); // tween starts at its begin value
    expect(find.text('+42'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 125));
    expect(find.text('+45'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('+48'), findsOneWidget);
    expect(store.values.single, 48);

    // Leave and re-open the page (fresh State, SAME session store): the
    // chip must repaint at +48 immediately — no replayed tween.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await pumpTab(tester);
    game.add(gameNode(danaGoals: 2));
    players.add(market());
    squads.add(squad());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('+48'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('+48'), findsOneWidget);
  });

  group('round 3: a points row opens the fantasy player profile', () {
    Map<String, Object?> opened(String name) => {
          'sport': 'Futsal',
          'season': '15',
          'name': name,
          'draft': null,
          // The match page lives outside the hub: the profile's primary
          // button is "Open in Fantasy" and there is no shared draft.
          'outside': true,
        };

    testWidgets('tapping a ranked row opens THAT player (outside the hub, '
        'no draft)', (tester) async {
      await pumpTab(tester);
      await emitAll(tester);

      await tester.tap(find.text('Dana (DEF)'));
      await tester.pump();
      expect(profileOpens, [opened('Dana')]);

      await tester.tap(find.text('Yara (DEF)'));
      await tester.pump();
      expect(profileOpens, [opened('Dana'), opened('Yara')]);
    });

    testWidgets('the viewer highlighted rows (YOURS, captain math) open '
        'too, and so do rows in the expanded "No returns yet" section',
        (tester) async {
      await pumpTab(tester);
      await emitAll(tester, viewerSquad: squad());

      // Captain row (YOURS + the ×2 math line).
      await tester.tap(find.byKey(const ValueKey('captain_math_Alex')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('yours_tag_Gale')));
      await tester.pump();
      expect(profileOpens, [opened('Alex'), opened('Gale')]);

      await tester
          .tap(find.byKey(const ValueKey('match_fantasy_scoreless_toggle')));
      await tester.pumpAndSettle();
      // The toggle itself opens nothing.
      expect(profileOpens, hasLength(2));
      await tester.tap(find.text('Zed (DEF)'));
      await tester.pump();
      expect(profileOpens.last, opened('Zed'));
    });
  });
}
