// P6 — the match-page Fantasy tab proved with fake streams (no Firebase):
// single fade reveal once game+players+squad land; the pre-kickoff face on
// an unstarted node; ranked "+N · Name (POS)" rows with the viewer's picks
// highlighted (YOURS) and the captain's ×2 math; "No returns yet" collapsed
// until tapped; the earning chip's counter animating ONLY on a genuine
// increase (re-mounts with the session store never replay the tween); the
// hub button seam; (round 3) every points row opening the player's
// fantasy profile from outside the hub; and (Opus audit item 7) the forfeit
// note row with long team names at 360 px in light AND dark, scrolled end to
// end with no overflow.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_logic.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_tab.dart';

/// Lets the feeds land and the fades finish with FIXED frames: a LIVE game
/// carries the pulsing LIVE pill, which never lets pumpAndSettle return.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The test game is played on 06/15/2026 — gameweek 1 of this schedule, which
/// locks at 17:00 UTC that day (the tests' clock is [kBeforeLock] unless a
/// test says otherwise).
const String kGameDate = '06152026';
final DateTime kBeforeLock = DateTime.utc(2026, 6, 15, 12);
final DateTime kAfterLock = DateTime.utc(2026, 6, 15, 20);

List<Gameweek> schedule() => [
      Gameweek(
        number: 1,
        date: kGameDate,
        lockUtc: DateTime.utc(2026, 6, 15, 17),
        opensUtc: null,
      ),
      Gameweek(
        number: 2,
        date: '06222026',
        lockUtc: DateTime.utc(2026, 6, 22, 17),
        opensUtc: DateTime.utc(2026, 6, 16),
      ),
    ];

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

  Future<void> pumpTab(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    Brightness brightness = Brightness.light,
    Map<String, List<String>>? rosterNames,
    // Live everywhere (Task 7) — each defaults to "answered at once, nothing
    // there" (a cache-seeded feed); a test drives one by passing its own.
    Stream<List<Gameweek>>? gameweekStates,
    Stream<FantasySquad?> Function(int week)? publishedPicksFor,
    Stream<HistoryWeek?> Function(int week)? historyWeekFor,
    Stream<FantasyLiveState>? liveStates,
    Stream<Set<int>>? voidedStates,
    DateTime? now,
    String selfUid = 'me',
    Duration liveWait = kLiveJoinWait,
    FantasyLockOverride lockOverride = FantasyLockOverride.auto,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: MatchFantasyTab(
          sport: 'Futsal',
          season: '15',
          dateKey: kGameDate,
          gameIndex: 0,
          configState: FantasyConfigState(
            config: FantasyConfig.futsalDefault(),
            lockOverride: lockOverride,
          ),
          rosterNamesByTeam: rosterNames ?? rosters(),
          gameNodeStates: game.stream,
          playersStates: players.stream,
          squadStates: squads.stream,
          gameweekStates: gameweekStates ?? Stream.value(schedule()),
          publishedPicksFor:
              publishedPicksFor ?? (_) => Stream<FantasySquad?>.value(null),
          historyWeekFor:
              historyWeekFor ?? (_) => Stream<HistoryWeek?>.value(null),
          liveStates: liveStates ?? Stream.value(FantasyLiveState.none),
          voidedStates: voidedStates ?? Stream.value(const <int>{}),
          selfUidOverride: selfUid,
          nowUtc: () => now ?? kBeforeLock,
          liveWait: liveWait,
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
    await settle(tester);
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
    await settle(tester);
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
    await settle(tester);
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
    await settle(tester);
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

  // Opus audit item 7: the forfeit note row (long team names) at 360 px in
  // both themes, scrolled end to end.
  for (final brightness in Brightness.values) {
    testWidgets('360 px: the forfeit note with long team names wraps, no '
        'overflow when scrolled through — $brightness', (tester) async {
      const home = 'The Extraordinarily Long-Named Assyrian Futsal Club';
      const away = 'The Wolves Of The Never Ending Night Futsal Club';
      await pumpTab(
        tester,
        size: const Size(360, 640),
        brightness: brightness,
        rosterNames: {
          home: ['Alex', 'Gale', 'Dana', 'Yara'],
          away: ['Wren', 'Zed'],
        },
      );
      final node = gameNode(status: 2)
        ..['team1'] = home
        ..['team2'] = away
        ..['team1score'] = 5
        ..['team2score'] = 0
        ..['forfeitedBy'] = 2;
      await emitAll(tester, node: node, viewerSquad: squad());
      expect(tester.takeException(), isNull);
      final note = find.byKey(const ValueKey('match_fantasy_forfeit_note'));
      expect(note, findsOneWidget);
      expect(find.textContaining('$away forfeited.'), findsOneWidget);
      final r = tester.getRect(note);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));

      final scrollable = find.byType(Scrollable).first;
      await tester.dragUntilVisible(
          find.byKey(const ValueKey('match_fantasy_footnote')),
          scrollable,
          const Offset(0, -200));
      await settle(tester);
      expect(tester.takeException(), isNull);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.overflow, isNot(TextOverflow.ellipsis), reason: t.data);
      }
    });
  }

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
    await settle(tester);
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
    await settle(tester);
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
      await settle(tester);
      // The toggle itself opens nothing.
      expect(profileOpens, hasLength(2));
      await tester.tap(find.text('Zed (DEF)'));
      await tester.pump();
      expect(profileOpens.last, opened('Zed'));
    });
  });

  // ── Live everywhere (Task 7) ─────────────────────────────────────────────
  //
  // (a) the header says LIVE (the shared pill) or FINAL from the game status;
  // (b) the viewer's squad for a game is the squad that was LOCKED for its
  //     gameweek (PublishedPicks, else History) — Squads/<uid> only for a week
  //     that has not locked; (c) a strip while the gameweek is live: `Your
  //     gameweek so far: {W} pts · #{R}`; (d) the footnote gains the My Team
  //     sentence. All of it inside the tab's single reveal.
  group('live everywhere (Task 7)', () {
    // The squad that was locked for GW1: Yara in, Wren and Zed out, a Triple
    // Captain on Alex. Squads/<uid> (what he saved SINCE) is `squad()`.
    FantasySquad lockedSquad({String? chip = 'tripleCaptain'}) => FantasySquad(
          picks: const [
            SquadPick(
                playerId: 'Gale',
                position: FantasyPosition.gk,
                priceTenths: 60),
            SquadPick(
                playerId: 'Dana',
                position: FantasyPosition.def,
                priceTenths: 60),
            SquadPick(
                playerId: 'Yara',
                position: FantasyPosition.def,
                priceTenths: 60),
            SquadPick(
                playerId: 'Alex',
                position: FantasyPosition.att,
                priceTenths: 60),
          ],
          captainId: 'Alex',
          viceId: 'Gale',
          chip: chip,
        );

    HistoryWeek historyOf(FantasySquad? s) =>
        HistoryWeek(slots: const [], squad: s);

    FantasyLiveState liveGw1({
      int week = 1,
      LiveState state = LiveState.live,
      Map<String, LiveBoardRow>? board,
    }) =>
        FantasyLiveState(
          meta: LiveMeta(gw: week, state: state),
          board: board ??
              const {'me': LiveBoardRow(o: 120, r: 5, m: 2, w: 34, wr: 4)},
        );

    Finder byKey(String k) => find.byKey(ValueKey(k));
    Finder livePill() => byKey('match_fantasy_live_pill');
    Finder finalLabel() => byKey('match_fantasy_final');
    Finder strip() => byKey('match_fantasy_week_strip');
    String stripText(WidgetTester tester) =>
        tester.widget<Text>(byKey('match_fantasy_week_strip_text')).data!;

    group('(a) the header: LIVE or FINAL from the game status', () {
      testWidgets('a game being played says LIVE (the shared pill), not '
          'FINAL', (tester) async {
        await pumpTab(tester);
        await emitAll(tester, node: gameNode(status: 1));
        expect(livePill(), findsOneWidget);
        expect(tester.widget<FantasyLivePill>(livePill()), isNotNull);
        expect(find.text('LIVE'), findsOneWidget);
        expect(finalLabel(), findsNothing);
        expect(find.text('FINAL'), findsNothing);
      });

      testWidgets('a finished game says FINAL, no pill', (tester) async {
        await pumpTab(tester);
        await emitAll(tester, node: gameNode(status: 2));
        expect(finalLabel(), findsOneWidget);
        expect(find.text('FINAL'), findsOneWidget);
        expect(livePill(), findsNothing);
        expect(find.byType(FantasyLivePill), findsNothing);
      });

      testWidgets('live and final no longer render identically',
          (tester) async {
        await pumpTab(tester);
        await emitAll(tester, node: gameNode(status: 1));
        final live = find.byType(ListView);
        expect(find.descendant(of: live, matching: find.text('LIVE')),
            findsOneWidget);
        game.add(gameNode(status: 2));
        await settle(tester);
        expect(find.text('LIVE'), findsNothing);
        expect(find.text('FINAL'), findsOneWidget);
      });

      testWidgets('before kickoff neither shows (the kickoff face)',
          (tester) async {
        await pumpTab(tester);
        await emitAll(tester, node: gameNode(status: 0));
        expect(find.text('LIVE'), findsNothing);
        expect(find.text('FINAL'), findsNothing);
      });

      testWidgets('the header leads the list, above the rows',
          (tester) async {
        await pumpTab(tester);
        await emitAll(tester, node: gameNode(status: 1));
        final header = tester.getRect(livePill());
        expect(header.top,
            lessThan(tester.getTopLeft(byKey('points_row_Dana')).dy));
      });
    });

    group('(d) the footnote', () {
      testWidgets('gains the My Team sentence, verbatim — and keeps the '
          'rest', (tester) async {
        await pumpTab(tester);
        await emitAll(tester);
        final text =
            tester.widget<Text>(byKey('match_fantasy_footnote')).data!;
        expect(text,
            endsWith(' Bonus, captain and bench counting show on My Team.'));
        expect(text, startsWith('Raw game points, live from the capture.'));
        expect(text, contains('the 3/2/1 bonus are applied when the '
            'gameweek is finalized — your counted week can differ.'));
        expect(text, kMatchFootnote);
      });
    });

    group('(c) the week strip', () {
      testWidgets('verbatim, under the header and above everything else, '
          'while the gameweek is live', (tester) async {
        await pumpTab(tester,
            now: kAfterLock, liveStates: Stream.value(liveGw1()));
        await emitAll(tester, viewerSquad: null);

        expect(stripText(tester), 'Your gameweek so far: 34 pts · #5');
        final header = tester.getRect(livePill());
        final s = tester.getRect(strip());
        expect(s.top, greaterThanOrEqualTo(header.bottom));
        expect(s.top, lessThan(tester.getTopLeft(byKey('points_row_Dana')).dy));
      });

      testWidgets('a FINAL game of a gameweek that is still live shows it '
          'too (the strip is about the gameweek, not the game)',
          (tester) async {
        await pumpTab(tester,
            now: kAfterLock, liveStates: Stream.value(liveGw1()));
        await emitAll(tester, node: gameNode(status: 2));
        expect(find.text('FINAL'), findsOneWidget);
        expect(stripText(tester), 'Your gameweek so far: 34 pts · #5');
      });

      testWidgets('the numbers move in place with the live feed',
          (tester) async {
        final live = StreamController<FantasyLiveState>.broadcast();
        addTearDown(live.close);
        await pumpTab(tester, now: kAfterLock, liveStates: live.stream);
        live.add(liveGw1());
        await emitAll(tester);
        expect(stripText(tester), 'Your gameweek so far: 34 pts · #5');

        live.add(liveGw1(board: const {
          'me': LiveBoardRow(o: 130, r: 3, m: 4, w: 44, wr: 2)
        }));
        await settle(tester);
        expect(stripText(tester), 'Your gameweek so far: 44 pts · #3');
      });

      for (final (label, l) in [
        ('the week is settled (the tombstone)',
            liveGw1(state: LiveState.settled)),
        ('the live week is another one', liveGw1(week: 2)),
        ('there is no live node', FantasyLiveState.none),
      ]) {
        testWidgets('no strip when $label', (tester) async {
          await pumpTab(tester, now: kAfterLock, liveStates: Stream.value(l));
          await emitAll(tester);
          expect(strip(), findsNothing);
          expect(find.textContaining('so far'), findsNothing);
        });
      }

      testWidgets('no strip with no row for him or no points this week',
          (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            liveStates: Stream.value(liveGw1(
                board: const {'other': LiveBoardRow(o: 1, r: 1, w: 3)})));
        await emitAll(tester);
        expect(strip(), findsNothing);
      });

      testWidgets('a VOIDED week (the Voided set) has no strip — never '
          '"0 pts · #1"', (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            liveStates: Stream.value(liveGw1(board: const {
              'me': LiveBoardRow(o: 7, r: 1, w: 0, wr: 1)
            })),
            voidedStates: Stream.value(const {1}));
        await emitAll(tester);
        expect(strip(), findsNothing);
        expect(find.textContaining('so far'), findsNothing);
      });

      testWidgets('a failed Voided feed is unknown: no strip',
          (tester) async {
        final voided = StreamController<Set<int>>.broadcast();
        addTearDown(voided.close);
        await pumpTab(tester,
            now: kAfterLock,
            liveStates: Stream.value(liveGw1()),
            voidedStates: voided.stream);
        voided.addError(StateError('rules'));
        await emitAll(tester);
        expect(find.byKey(const ValueKey('match_fantasy_ready')),
            findsOneWidget);
        expect(strip(), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('signed out: no strip and nothing subscribed for him',
          (tester) async {
        final asked = <int>[];
        await pumpTab(tester,
            selfUid: '',
            now: kAfterLock,
            liveStates: Stream.value(liveGw1()),
            publishedPicksFor: (w) {
              asked.add(w);
              return Stream.value(lockedSquad());
            });
        await emitAll(tester);
        expect(strip(), findsNothing);
        expect(asked, isEmpty);
        expect(find.textContaining('YOURS'), findsNothing);
        expect(find.byKey(const ValueKey('match_fantasy_ready')),
            findsOneWidget);
      });
    });

    group('(b) the viewer\'s squad is the one that was LOCKED', () {
      testWidgets(
          'a PAST game: the locked squad, not the squad saved since (Yara '
          'is his, Wren and Zed are not; Triple Captain ×3)', (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            publishedPicksFor: (_) => Stream.value(lockedSquad()));
        // Squads/<uid> — what he saved since — is a different squad.
        await emitAll(tester, node: gameNode(status: 2), viewerSquad: squad());

        expect(byKey('yours_tag_Yara'), findsOneWidget);
        expect(byKey('yours_tag_Gale'), findsOneWidget);
        expect(byKey('yours_tag_Dana'), findsOneWidget);
        expect(byKey('yours_tag_Alex'), findsOneWidget);
        // Wren was absent (omitted); Zed (in the CURRENT squad) was not his.
        await tester
            .tap(find.byKey(const ValueKey('match_fantasy_scoreless_toggle')));
        await settle(tester);
        expect(byKey('yours_tag_Zed'), findsNothing);
        // The armband's real multiplier from the locked squad's chip.
        expect(find.textContaining('Captain ×3 applied · +10 × 3 = +30 for you'),
            findsOneWidget);
        // Gale 10 + Dana 12 + Yara 5 + Alex 10×3.
        expect(find.text('+57'), findsOneWidget);
      });

      testWidgets('History is the fallback when PublishedPicks has none',
          (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            historyWeekFor: (_) => Stream.value(historyOf(lockedSquad())));
        await emitAll(tester, node: gameNode(status: 2), viewerSquad: squad());
        expect(byKey('yours_tag_Yara'), findsOneWidget);
        expect(find.text('+57'), findsOneWidget);
      });

      testWidgets('PublishedPicks wins over a differing History',
          (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            publishedPicksFor: (_) => Stream.value(lockedSquad()),
            historyWeekFor: (_) =>
                Stream.value(historyOf(squad())));
        await emitAll(tester, node: gameNode(status: 2));
        expect(byKey('yours_tag_Yara'), findsOneWidget);
        expect(find.text('+57'), findsOneWidget);
      });

      testWidgets('a locked week with no locked squad on record: no viewer '
          'layer at all, whatever he has saved since', (tester) async {
        await pumpTab(tester, now: kAfterLock);
        await emitAll(tester, node: gameNode(status: 2), viewerSquad: squad());
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
        expect(find.textContaining('YOURS'), findsNothing);
        expect(byKey('captain_math_Alex'), findsNothing);
      });

      testWidgets('Squads/<uid> only for a week that has not locked: before '
          'the lock the saved squad is his', (tester) async {
        await pumpTab(tester,
            now: kBeforeLock,
            // Even a published copy would not be asked about before the lock
            // in production; the saved squad is what counts here.
            publishedPicksFor: (_) => Stream.value(null));
        await emitAll(tester, viewerSquad: squad());
        expect(byKey('yours_tag_Gale'), findsOneWidget);
        expect(byKey('yours_tag_Yara'), findsNothing);
        expect(find.text('+42'), findsOneWidget);
      });

      testWidgets('the owner\'s "locked" override locks the current '
          'gameweek: the saved squad is not used', (tester) async {
        await pumpTab(tester,
            now: kBeforeLock, lockOverride: FantasyLockOverride.locked);
        await emitAll(tester, viewerSquad: squad());
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
        expect(find.textContaining('YOURS'), findsNothing);
      });

      testWidgets('only the game\'s own week is asked for, one small node '
          'each — never the whole PublishedPicks / History', (tester) async {
        final published = <int>[];
        final history = <int>[];
        await pumpTab(tester,
            now: kAfterLock,
            publishedPicksFor: (w) {
              published.add(w);
              return Stream.value(lockedSquad());
            },
            historyWeekFor: (w) {
              history.add(w);
              return Stream.value(null);
            });
        await emitAll(tester, node: gameNode(status: 2));
        expect(published, [1]);
        expect(history, [1]);
      });

      testWidgets('a game whose date is not on the schedule has no viewer '
          'layer (the week is unknown) but the tab still reveals',
          (tester) async {
        final asked = <int>[];
        await pumpTab(tester,
            now: kAfterLock,
            gameweekStates: Stream.value([
              Gameweek(
                  number: 1,
                  date: '01012026',
                  lockUtc: DateTime.utc(2026, 1, 1, 17),
                  opensUtc: null),
            ]),
            publishedPicksFor: (w) {
              asked.add(w);
              return Stream.value(lockedSquad());
            });
        await emitAll(tester, viewerSquad: squad());
        expect(byKey('match_fantasy_ready'), findsOneWidget);
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
        expect(find.textContaining('YOURS'), findsNothing);
        expect(asked, isEmpty);
      });

      testWidgets('a failing schedule feed degrades the same way (no '
          'viewer layer, no skeleton hold)', (tester) async {
        final sched = StreamController<List<Gameweek>>.broadcast();
        addTearDown(sched.close);
        await pumpTab(tester, now: kAfterLock, gameweekStates: sched.stream);
        sched.addError(StateError('offline'));
        await emitAll(tester, viewerSquad: squad());
        expect(byKey('match_fantasy_ready'), findsOneWidget);
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a published squad that fails to load never shows the '
          'saved squad in its place', (tester) async {
        await pumpTab(tester,
            now: kAfterLock,
            publishedPicksFor: (_) =>
                Stream<FantasySquad?>.error(StateError('rules')));
        await emitAll(tester, node: gameNode(status: 2), viewerSquad: squad());
        expect(byKey('match_fantasy_ready'), findsOneWidget);
        expect(find.textContaining('YOURS'), findsNothing);
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
      });
    });

    group('one reveal: the new feeds join the tab\'s gate', () {
      late StreamController<List<Gameweek>> weeks;
      late StreamController<FantasySquad?> published;
      late StreamController<HistoryWeek?> history;
      late StreamController<FantasyLiveState> live;
      late StreamController<Set<int>> voided;

      setUp(() {
        weeks = StreamController<List<Gameweek>>.broadcast();
        published = StreamController<FantasySquad?>.broadcast();
        history = StreamController<HistoryWeek?>.broadcast();
        live = StreamController<FantasyLiveState>.broadcast();
        voided = StreamController<Set<int>>.broadcast();
      });

      tearDown(() {
        weeks.close();
        published.close();
        history.close();
        live.close();
        voided.close();
      });

      Future<void> pumpGated(WidgetTester tester,
              {Duration liveWait = kLiveJoinWait, DateTime? now}) =>
          pumpTab(tester,
              now: now ?? kAfterLock,
              liveWait: liveWait,
              gameweekStates: weeks.stream,
              publishedPicksFor: (_) => published.stream,
              historyWeekFor: (_) => history.stream,
              liveStates: live.stream,
              voidedStates: voided.stream);

      Future<void> quick(WidgetTester tester) =>
          tester.pump(const Duration(milliseconds: 20));

      // The skeleton is up AND the content is not in the tree at all (an
      // AnimatedSwitcher keeps the outgoing skeleton during a cross-fade, so
      // "skeleton present" alone would not prove the reveal waited).
      void expectHeld() {
        expect(byKey('match_fantasy_skeleton'), findsOneWidget);
        expect(byKey('match_fantasy_ready'), findsNothing);
      }

      testWidgets(
          'the skeleton holds until the schedule, the locked squad, the '
          'week record, the live feed and the Voided set have all answered; '
          'the first frame with the content already has the locked squad '
          'and the strip', (tester) async {
        await pumpGated(tester);
        game.add(gameNode(status: 2));
        players.add(market());
        squads.add(squad());
        await quick(tester);
        expectHeld();

        weeks.add(schedule());
        await quick(tester);
        expectHeld();
        live.add(liveGw1());
        await quick(tester);
        expectHeld();
        voided.add(const {});
        await quick(tester);
        expectHeld();
        published.add(lockedSquad());
        await quick(tester);
        expectHeld();
        history.add(null);
        await quick(tester);
        await quick(tester);

        expect(byKey('match_fantasy_ready'), findsOneWidget);
        // The very first frame with the content is already the final one.
        expect(byKey('yours_tag_Yara'), findsOneWidget);
        expect(find.text('+57'), findsOneWidget);
        expect(stripText(tester), 'Your gameweek so far: 34 pts · #5');
        // The session store holds only the REAL value, never an interim
        // number from the saved squad.
        expect(store.values.single, 57);
      });

      testWidgets(
          'bounded: a silent feed reveals at 2 s without the viewer layer '
          'and a late answer lands in place — the skeleton never returns',
          (tester) async {
        await pumpGated(tester);
        game.add(gameNode(status: 2));
        players.add(market());
        squads.add(squad());
        weeks.add(schedule());
        live.add(liveGw1());
        voided.add(const {});
        await tester.pump(const Duration(milliseconds: 1900));
        expectHeld();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 400));

        expect(byKey('match_fantasy_ready'), findsOneWidget);
        // The saved squad is never drawn in the locked squad's place.
        expect(find.textContaining('YOURS'), findsNothing);
        expect(byKey('match_fantasy_earning_chip'), findsNothing);
        expect(store, isEmpty);

        published.add(lockedSquad());
        history.add(null);
        await settle(tester);
        expect(byKey('match_fantasy_skeleton'), findsNothing);
        expect(byKey('yours_tag_Yara'), findsOneWidget);
        expect(find.text('+57'), findsOneWidget);
      });

      testWidgets(
          'a number worked out from the SAVED squad while the locked squad '
          'is still on its way is never remembered or tweened: it shows its '
          'value at once', (tester) async {
        // The clock says the week has not locked, yet PublishedPicks exists
        // (an owner who reopened editing): the locked squad wins once it
        // arrives — but until then nothing of his is worked out.
        await pumpGated(tester, now: kBeforeLock);
        game.add(gameNode(status: 2));
        players.add(market());
        squads.add(squad()); // the saved squad: +42, NOT what the game scored
        weeks.add(schedule());
        live.add(FantasyLiveState.none);
        voided.add(const {});
        await quick(tester);
        expectHeld();
        expect(store, isEmpty, reason: 'no interim 42 may be remembered');

        published.add(lockedSquad());
        history.add(null);
        await quick(tester);
        await quick(tester);
        // The first frame with the chip already reads the locked squad's
        // value: no 42 → 57 tween was armed.
        expect(find.text('+57'), findsOneWidget);
        expect(find.text('+42'), findsNothing);
        expect(store.values.single, 57);
      });

      testWidgets('a later change of the locked squad lands in place',
          (tester) async {
        await pumpGated(tester);
        game.add(gameNode(status: 2));
        players.add(market());
        squads.add(null);
        weeks.add(schedule());
        await quick(tester);
        live.add(FantasyLiveState.none);
        voided.add(const {});
        published.add(lockedSquad());
        history.add(null);
        await settle(tester);
        expect(find.text('+57'), findsOneWidget);

        published.add(lockedSquad(chip: null));
        await settle(tester);
        expect(find.text('+47'), findsOneWidget); // Alex 10×2
        expect(byKey('match_fantasy_skeleton'), findsNothing);
      });
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: the header, the strip and the locked squad fit, '
          'no overflow — $brightness', (tester) async {
        await pumpTab(tester,
            size: const Size(360, 700),
            brightness: brightness,
            now: kAfterLock,
            liveStates: Stream.value(liveGw1(board: const {
              'me': LiveBoardRow(o: 1200, r: 1234, m: 12, w: 345, wr: 99)
            })),
            publishedPicksFor: (_) => Stream.value(lockedSquad()));
        await emitAll(tester, node: gameNode(status: 1));
        expect(tester.takeException(), isNull);
        expect(stripText(tester), 'Your gameweek so far: 345 pts · #1234');
        for (final k in ['match_fantasy_live_pill', 'match_fantasy_week_strip']) {
          final r = tester.getRect(byKey(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: k);
          expect(r.right, lessThanOrEqualTo(360), reason: k);
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(tester.widget<Text>(byKey('match_fantasy_footnote')).data,
            endsWith('Bonus, captain and bench counting show on My Team.'));
      });
    }
  });
}
