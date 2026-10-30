// P3c + round 3 (spec §5) — the Players market tab, proved with fake streams
// (no Firebase): one fade reveal once every feed lands (and an instant
// revisit from the session cache); the four sorts with Total Pts the default
// once totals exist, tapping the active sort flips direction, the choice
// survives filter changes AND a remount; rows show price over points, the
// latest move over owned %, the next game; the ★ chip filters to the
// watchlist; the Price Risers / Fallers card (grouped by position, View
// all); every row / mover tap opens the player profile; adds flow into the
// SAME shared draft; and no overflow at 360 px in light AND dark.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

FantasyPlayer player(String name, FantasyPosition pos, int price,
        {bool eligible = true, String team = 'Team A'}) =>
    FantasyPlayer(
        name: name,
        position: pos,
        priceTenths: price,
        eligible: eligible,
        teamName: team);

/// A game with a stored time ("3:00 PM").
TournamentMatch game(String date, String team1, String team2) =>
    leagueMatchFromGameMap(
      dateKey: date,
      index: 0,
      raw: {'team1': team1, 'team2': team2, 'status': 0, 'Time': '15:00'},
    );

/// A legacy game with NO stored time: derived from the start hour (0 →
/// "0:00PM", the trap the market must never show).
TournamentMatch legacyGame(String date, String team1, String team2) =>
    leagueMatchFromGameMap(
      dateKey: date,
      index: 0,
      raw: {'team1': team1, 'team2': team2, 'status': 0},
    );

const longName =
    'Maximiliano Alessandro Bartholomew-Featherstonehaugh Von Grünewald';
const longTeam =
    'The Extraordinarily Long-Named Assyrian Athletic Futsal Club of San Jose';

void main() {
  late SquadDraftController draft;
  late StreamController<Map<String, FantasyPlayerTotals>?> totals;
  late StreamController<Map<int, Map<String, int>>> changes;
  late StreamController<List<TournamentMatch>> games;
  late StreamController<Set<String>> watchlist;
  late List<String> opened;

  final players = <FantasyPlayer>[
    player('Alan Keeper', FantasyPosition.gk, 50),
    player('Gus Glove', FantasyPosition.gk, 45, team: 'Team B'),
    player('Dana Wall', FantasyPosition.def, 60),
    player('Deb Rock', FantasyPosition.def, 55, team: 'Team B'),
    player('Ava Striker', FantasyPosition.att, 70),
    player('Axel Shot', FantasyPosition.att, 65, team: 'Team B'),
    player('Guest Guy', FantasyPosition.att, 65, eligible: false),
  ];

  const someTotals = <String, FantasyPlayerTotals>{
    'Ava Striker': FantasyPlayerTotals(
        points: 54, ownershipPct: 62, formTenths: 40, ppgTenths: 45, games: 12),
    'Gus Glove': FantasyPlayerTotals(
        points: 70, ownershipPct: 8, formTenths: 90, ppgTenths: 58, games: 12),
    'Dana Wall': FantasyPlayerTotals(
        points: 12, ownershipPct: 30, formTenths: 20, ppgTenths: 10, games: 12),
  };

  setUp(() {
    FantasyPlayersTab.sessionSort = MarketSort.points;
    FantasyPlayersTab.sessionDescending = true;
    FantasyPlayersTab.clearSessionCaches();
    draft = SquadDraftController(config: FantasyConfig.futsalDefault());
    totals = StreamController<Map<String, FantasyPlayerTotals>?>.broadcast();
    changes = StreamController<Map<int, Map<String, int>>>.broadcast();
    games = StreamController<List<TournamentMatch>>.broadcast();
    watchlist = StreamController<Set<String>>.broadcast();
    opened = [];
  });

  tearDown(() {
    totals.close();
    changes.close();
    games.close();
    watchlist.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    List<FantasyPlayer>? marketPlayers,
    FantasyLockOverride lockOverride = FantasyLockOverride.open,
    String selfUid = 'me',
    Size size = const Size(420, 1400),
    ThemeMode themeMode = ThemeMode.light,
    Future<int> Function()? loadStartHour,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: themeMode,
      home: Scaffold(
        body: FantasyPlayersTab(
          sport: 'Futsal',
          season: '15',
          players: marketPlayers ?? players,
          draft: draft,
          lockOverride: lockOverride,
          gameweeks: const [],
          totalsStates: totals.stream,
          priceChangeStates: changes.stream,
          gamesStates: games.stream,
          loadStartHour: loadStartHour,
          watchlistStates: watchlist.stream,
          selfUidOverride: selfUid,
          openPlayer: (context, name) => opened.add(name),
          nowUtc: () => DateTime.utc(2026, 11, 2, 18),
        ),
      ),
    ));
  }

  /// Every feed lands (the watchlist only matters signed in).
  Future<void> land(
    WidgetTester tester, {
    Map<String, FantasyPlayerTotals>? totalsValue,
    Map<int, Map<String, int>> changesValue = const {},
    List<TournamentMatch> gamesValue = const [],
    Set<String> watchlistValue = const {},
  }) async {
    totals.add(totalsValue);
    changes.add(changesValue);
    games.add(gamesValue);
    watchlist.add(watchlistValue);
    await tester.pumpAndSettle();
  }

  double rowY(WidgetTester tester, String name) =>
      tester.getTopLeft(find.byKey(ValueKey('market_row_$name'))).dy;

  void expectOrder(WidgetTester tester, List<String> names) {
    for (var i = 0; i + 1 < names.length; i++) {
      expect(rowY(tester, names[i]), lessThan(rowY(tester, names[i + 1])),
          reason: '${names[i]} should list above ${names[i + 1]}');
    }
  }

  IconData? sortArrow(WidgetTester tester) =>
      tester.widget<Icon>(find.byKey(const ValueKey('market_sort_dir'))).icon;

  testWidgets('one fade reveal: a skeleton until EVERY feed has landed',
      (tester) async {
    await pumpTab(tester);
    expect(
        find.byKey(const ValueKey('players_market_skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_row_Ava Striker')), findsNothing);

    totals.add(null);
    changes.add(const {});
    games.add(const []);
    await tester.pump();
    // The watchlist hasn't answered yet — still the skeleton, nothing pops.
    expect(
        find.byKey(const ValueKey('players_market_skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_row_Ava Striker')), findsNothing);

    watchlist.add(const {});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
    expect(
        find.byKey(const ValueKey('market_row_Ava Striker')), findsOneWidget);
  });

  testWidgets('signed out: no ★ chip and the watchlist is never awaited',
      (tester) async {
    await pumpTab(tester, selfUid: '');
    totals.add(null);
    changes.add(const {});
    games.add(const []);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('market_row_Ava Striker')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_watchlist_chip')), findsNothing);
  });

  testWidgets(
      'no totals yet: Price, highest first, with guests last under '
      'the divider, disabled', (tester) async {
    await pumpTab(tester);
    await land(tester);

    expectOrder(tester, ['Ava Striker', 'Axel Shot', 'Dana Wall', 'Deb Rock']);
    expect(rowY(tester, 'Gus Glove'), lessThan(rowY(tester, 'Guest Guy')));
    // The Price pill is the active one, arrow pointing down (highest first).
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('market_sort_price')),
            matching: find.byKey(const ValueKey('market_sort_dir'))),
        findsOneWidget);
    expect(sortArrow(tester), Icons.arrow_downward);
    // No totals → no points / owned text at all (never a made-up 0).
    expect(find.textContaining(' pts'), findsNothing);
    expect(find.textContaining('%'), findsNothing);

    // Guest: below the divider, add disabled with the guest reason.
    expect(find.byKey(const ValueKey('not_eligible_divider')), findsOneWidget);
    expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('not_eligible_divider')))
            .dy,
        lessThan(rowY(tester, 'Guest Guy')));
    expect(find.byKey(const ValueKey('market_add_Guest Guy')), findsNothing);
    final guestTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Guest Guy')));
    expect(guestTooltip.message, 'Guest player — not eligible for fantasy.');
  });

  testWidgets(
      'totals-based sorts are dead (with the reason) until totals '
      'exist', (tester) async {
    await pumpTab(tester);
    await land(tester);
    for (final key in ['points', 'form', 'ownership']) {
      final tip = tester
          .widget<Tooltip>(find.byKey(ValueKey('market_sort_disabled_$key')));
      expect(tip.message, 'Available once Gameweek 1 is scored.');
    }
    await tester.tap(find.byKey(const ValueKey('market_sort_points')));
    await tester.pump();
    // The tap shows the reason; let its dismiss timer run out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.points);
    expect(rowY(tester, 'Ava Striker'), lessThan(rowY(tester, 'Gus Glove')));
  });

  testWidgets(
      'Total Pts is the default once totals exist; the node vanishing '
      'falls back to Price', (tester) async {
    await pumpTab(tester);
    await land(tester, totalsValue: someTotals);

    // Gus 70 > Ava 54 > Dana 12 > the zero-point rest (by name).
    expectOrder(tester,
        ['Gus Glove', 'Ava Striker', 'Dana Wall', 'Alan Keeper', 'Axel Shot']);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('market_sort_points')),
            matching: find.byKey(const ValueKey('market_sort_dir'))),
        findsOneWidget);

    totals.add(null);
    await tester.pumpAndSettle();
    expectOrder(tester, ['Ava Striker', 'Axel Shot', 'Dana Wall']);
    expect(find.textContaining(' pts'), findsNothing);
  });

  testWidgets(
      'tapping the active sort flips direction; the choice survives '
      'filter + search changes AND a remount (session)', (tester) async {
    await pumpTab(tester);
    await land(tester, totalsValue: someTotals);

    // Form: Gus 9.0 > Ava 4.0 > Dana 2.0 > no form (by name).
    await tester.tap(find.byKey(const ValueKey('market_sort_form')));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.form);
    expect(FantasyPlayersTab.sessionDescending, isTrue);
    expectOrder(
        tester, ['Gus Glove', 'Ava Striker', 'Dana Wall', 'Alan Keeper']);
    expect(sortArrow(tester), Icons.arrow_downward);

    // Tap again → lowest first; players without form stay last.
    await tester.tap(find.byKey(const ValueKey('market_sort_form')));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionDescending, isFalse);
    expect(sortArrow(tester), Icons.arrow_upward);
    expectOrder(
        tester, ['Dana Wall', 'Ava Striker', 'Gus Glove', 'Alan Keeper']);

    // Position filter flips — the sort stays Form, lowest first.
    await tester.tap(find.byKey(const ValueKey('market_pos_ATT')));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.form);
    expect(find.byKey(const ValueKey('market_row_Dana Wall')), findsNothing);
    expectOrder(tester, ['Ava Striker', 'Axel Shot']);

    // Search (behind the search button) — still Form, lowest first.
    await tester.tap(find.byKey(const ValueKey('market_pos_All')));
    await tester.tap(find.byKey(const ValueKey('market_search_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('market_search')), 'team b');
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionDescending, isFalse);
    expect(find.byKey(const ValueKey('market_row_Ava Striker')), findsNothing);
    expectOrder(tester, ['Gus Glove', 'Axel Shot']);

    // Remount (a tab swipe unmounts far tabs): the session cache holds the
    // sort AND paints at once — no skeleton, no waiting on the feeds.
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester);
    await tester.pump();
    expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
    expect(FantasyPlayersTab.sessionSort, MarketSort.form);
    expect(sortArrow(tester), Icons.arrow_upward);
    expectOrder(tester, ['Dana Wall', 'Ava Striker', 'Gus Glove']);

    // Another sort starts highest first.
    await tester.tap(find.byKey(const ValueKey('market_sort_ownership')));
    await tester.pumpAndSettle();
    expect(FantasyPlayersTab.sessionSort, MarketSort.ownership);
    expect(FantasyPlayersTab.sessionDescending, isTrue);
    expectOrder(
        tester, ['Ava Striker', 'Dana Wall', 'Gus Glove', 'Alan Keeper']);
  });

  testWidgets(
      'row: price over points, the latest move over owned %, and the '
      'next game under the team line', (tester) async {
    await pumpTab(tester);
    await land(
      tester,
      totalsValue: someTotals,
      changesValue: const {
        1: {'Gus Glove': 9},
        2: {'Ava Striker': 5, 'Dana Wall': -3},
      },
      gamesValue: [game('11082026', 'Team A', 'Team B')],
    );

    expect(find.text('\$7.0M'), findsWidgets);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('market_points_Ava Striker')))
            .data,
        '54 pts');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('market_owned_Ava Striker')))
            .data,
        '62%');
    // Latest reprice (GW2): Ava up, Dana down, Gus (moved in GW1 only) flat.
    IconData? move(String name) =>
        tester.widget<Icon>(find.byKey(ValueKey('market_move_$name'))).icon;
    expect(move('Ava Striker'), Icons.arrow_drop_up);
    expect(move('Dana Wall'), Icons.arrow_drop_down);
    expect(move('Gus Glove'), Icons.remove);

    // Next game, with the stored time.
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('market_next_Ava Striker')))
            .data,
        'vs Team B · Sun 3 PM');
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('market_next_Gus Glove')))
            .data,
        'vs Team A · Sun 3 PM');
    // Position + team line ("POS · Team").
    expect(find.text('GK · Team B'), findsOneWidget);
  });

  testWidgets('no reprice yet: no move icon at all', (tester) async {
    await pumpTab(tester);
    await land(tester, totalsValue: someTotals);
    expect(find.byKey(const ValueKey('market_move_Ava Striker')), findsNothing);
    expect(
        find.byKey(const ValueKey('market_owned_Ava Striker')), findsOneWidget);
  });

  testWidgets(
      'unknown season start hour: a derived game time is dropped, '
      'never "0 PM"', (tester) async {
    await pumpTab(tester, loadStartHour: () async => 0);
    await land(tester,
        gamesValue: [legacyGame('11082026', 'Team A', 'Team B')]);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('market_next_Ava Striker')))
            .data,
        'vs Team B · Sun');
    expect(find.textContaining('0 PM'), findsNothing);
  });

  testWidgets(
      'start hour: a real hour is read once per session; an unknown '
      'one is retried, yet a revisit still paints at once', (tester) async {
    var calls = 0;
    Future<int> fivePm() async {
      calls++;
      return 5;
    }

    await pumpTab(tester, loadStartHour: fivePm);
    await land(tester, gamesValue: [game('11082026', 'Team A', 'Team B')]);
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester, loadStartHour: fivePm);
    await tester.pump();
    expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
    expect(calls, 1);

    FantasyPlayersTab.clearSessionCaches();
    var unknownCalls = 0;
    Future<int> unknown() async {
      unknownCalls++;
      return 0;
    }

    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester, loadStartHour: unknown);
    await land(tester,
        gamesValue: [legacyGame('11082026', 'Team A', 'Team B')]);
    expect(unknownCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester, loadStartHour: unknown);
    // Painted from the session at once — no skeleton while it re-asks.
    expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('market_next_Ava Striker')))
            .data,
        'vs Team B · Sun');
    await tester.pumpAndSettle();
    expect(unknownCalls, 2);
    expect(find.textContaining('0 PM'), findsNothing);
  });

  testWidgets('★ chip filters the market to the watchlist (live)',
      (tester) async {
    await pumpTab(tester);
    await land(tester, watchlistValue: {'Deb Rock', 'Guest Guy'});

    await tester.tap(find.byKey(const ValueKey('market_watchlist_chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('market_row_Deb Rock')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_row_Guest Guy')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_row_Ava Striker')), findsNothing);

    // Starring from the profile streams in.
    watchlist.add({'Deb Rock', 'Guest Guy', 'Ava Striker'});
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('market_row_Ava Striker')), findsOneWidget);

    // Empty watchlist → the friendly how-to, not "No players match".
    watchlist.add(const {});
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('market_watchlist_empty')), findsOneWidget);
    expect(find.text('No players match.'), findsNothing);

    // Off again → everyone.
    await tester.tap(find.byKey(const ValueKey('market_watchlist_chip')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('market_row_Ava Striker')), findsOneWidget);
  });

  testWidgets('a row tap opens the player profile (not the old sheet)',
      (tester) async {
    await pumpTab(tester);
    await land(tester);
    await tester.tap(find.byKey(const ValueKey('market_row_Ava Striker')));
    await tester.pumpAndSettle();
    expect(opened, ['Ava Striker']);
    expect(find.byKey(const ValueKey('market_player_sheet')), findsNothing);
  });

  group('Price Risers / Price Fallers card', () {
    final market = <FantasyPlayer>[
      player('Gil Keeper', FantasyPosition.gk, 50),
      player('Gary Gloves', FantasyPosition.gk, 45, team: 'Team B'),
      player('Gus Goalie', FantasyPosition.gk, 40, team: 'Team C'),
      player('Dan Back', FantasyPosition.def, 60),
      player('Dov Wall', FantasyPosition.def, 52, team: 'Team C'),
      player('Abe Shot', FantasyPosition.att, 70),
      player('Ari Goal', FantasyPosition.att, 65, team: 'Team B'),
    ];
    const moves = {
      1: {'Abe Shot': -9},
      3: {
        'Gil Keeper': 3,
        'Gary Gloves': 3,
        'Gus Goalie': 1,
        'Dan Back': -2,
        'Dov Wall': -5,
        'Abe Shot': 5,
        'Ari Goal': -1,
      },
    };
    const moveTotals = {
      'Gary Gloves': FantasyPlayerTotals(points: 40),
      'Gil Keeper': FantasyPlayerTotals(points: 20),
    };

    testWidgets(
        'hidden until a reprice exists, and when the latest one moved '
        'nobody', (tester) async {
      await pumpTab(tester, marketPlayers: market);
      await land(tester);
      expect(find.byKey(const ValueKey('price_movers_card')), findsNothing);

      changes.add(moves);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);

      // A voided latest week: a reprice ran, nothing moved → no card.
      changes.add({...moves, 4: const <String, int>{}});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_movers_card')), findsNothing);
    });

    testWidgets(
        'All: grouped GK / DEF / ATT, top 2 each side, short names; '
        'a position chip narrows it', (tester) async {
      await pumpTab(tester, marketPlayers: market);
      await land(tester, totalsValue: moveTotals, changesValue: moves);

      expect(find.text('Price Risers'), findsOneWidget);
      expect(find.text('Price Fallers'), findsOneWidget);
      expect(find.text('After Gameweek 3'), findsOneWidget);
      for (final g in ['GK', 'DEF', 'ATT']) {
        expect(find.byKey(ValueKey('price_movers_group_$g')), findsOneWidget);
      }
      // GK risers: Gary + Gil (same move, Gary has more points); Gus cut.
      expect(find.byKey(const ValueKey('price_mover_Gary Gloves')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('price_mover_Gil Keeper')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('price_mover_Gus Goalie')), findsNothing);
      expect(
          tester
                  .getTopLeft(
                      find.byKey(const ValueKey('price_mover_Gary Gloves')))
                  .dy <
              tester
                  .getTopLeft(
                      find.byKey(const ValueKey('price_mover_Gil Keeper')))
                  .dy,
          isTrue);
      expect(find.text('G. Gloves'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('price_movers_card')),
              matching: find.text('▲ \$0.3M')),
          findsNWidgets(2));
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('price_movers_card')),
              matching: find.text('▼ \$0.5M')),
          findsOneWidget);
      // The old GW1 move is not "latest".
      expect(find.text('▼ \$0.9M'), findsNothing);

      // DEF chip → only the DEF group (Dov the biggest drop, then Dan).
      await tester.tap(find.byKey(const ValueKey('market_pos_DEF')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_movers_group_GK')), findsNothing);
      expect(
          find.byKey(const ValueKey('price_mover_Dov Wall')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('price_mover_Dan Back')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('price_mover_Gary Gloves')), findsNothing);
    });

    testWidgets(
        'mover taps open the profile; View all lists every move and '
        'its rows open the profile too', (tester) async {
      await pumpTab(tester, marketPlayers: market);
      await land(tester, totalsValue: moveTotals, changesValue: moves);

      await tester.tap(find.byKey(const ValueKey('price_mover_Dov Wall')));
      await tester.pumpAndSettle();
      expect(opened, ['Dov Wall']);

      await tester.tap(find.byKey(const ValueKey('price_movers_view_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_moves_sheet')), findsOneWidget);
      // Every move of the latest reprice — including Gus, cut from the card.
      for (final name in [
        'Gil Keeper',
        'Gary Gloves',
        'Gus Goalie',
        'Dan Back',
        'Dov Wall',
        'Abe Shot',
        'Ari Goal',
      ]) {
        expect(find.byKey(ValueKey('price_move_all_$name')), findsOneWidget,
            reason: name);
      }
      await tester.tap(find.byKey(const ValueKey('price_move_all_Gus Goalie')));
      await tester.pumpAndSettle();
      expect(opened, ['Dov Wall', 'Gus Goalie']);
    });
  });

  testWidgets(
      'add flows into the SHARED draft: pill shows, control flips to '
      'remove, and the My Team builder sees the same pick', (tester) async {
    await pumpTab(tester);
    await land(tester);
    expect(find.byKey(const ValueKey('unsaved_pill')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('market_add_Alan Keeper')));
    await tester.pumpAndSettle();

    expect(draft.playerIds, contains('Alan Keeper'));
    expect(draft.dirty, isTrue);
    expect(find.byKey(const ValueKey('unsaved_pill')), findsOneWidget);
    expect(find.text('Unsaved changes — save on My Team'), findsOneWidget);
    expect(find.byKey(const ValueKey('market_add_Alan Keeper')), findsNothing);
    expect(find.byKey(const ValueKey('market_remove_Alan Keeper')),
        findsOneWidget);

    // The OTHER GK's add is now disabled: the one GK slot is taken.
    final gkTooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Gus Glove')));
    expect(gkTooltip.message, 'GK slots are full — remove someone first.');

    // The My Team court renders the SAME draft (cross-tab proof).
    tester.view.physicalSize = const Size(420, 1900);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasySquadBuilder(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open,
          gameweeks: const [],
          players: players,
          squadStates: const Stream.empty(),
          onSaveSquad: (_) async {},
          draft: draft,
        ),
      ),
    ));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('squad_chip_Alan Keeper')), findsOneWidget);

    // Back on the market (session-seeded): remove drops it from the draft.
    await pumpTab(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('market_remove_Alan Keeper')));
    await tester.pumpAndSettle();
    expect(draft.playerIds, isNot(contains('Alan Keeper')));
    expect(
        find.byKey(const ValueKey('market_add_Alan Keeper')), findsOneWidget);
  });

  testWidgets(
      'unaffordable: price goes error-red and the add control is '
      'dead with the money reason', (tester) async {
    final rich = [
      player('Money Bags', FantasyPosition.def, 460),
      player('Cheapo', FantasyPosition.att, 40),
      ...players,
    ];
    await pumpTab(tester, marketPlayers: rich);
    await land(tester);
    await tester.tap(find.byKey(const ValueKey('market_add_Money Bags')));
    await tester.pumpAndSettle();

    // $46.0M of $50.0M spent: everyone above $4.0M flips unaffordable.
    final context =
        tester.element(find.byKey(const ValueKey('players_market')));
    final errorColor = Theme.of(context).colorScheme.error;
    final price = tester
        .widget<Text>(find.byKey(const ValueKey('market_price_Dana Wall')));
    expect(price.style?.color, errorColor);
    final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Dana Wall')));
    expect(tooltip.message, 'Over budget — free up some money first.');
    // An exactly-affordable row keeps its live add AND its normal price.
    expect(find.byKey(const ValueKey('market_add_Cheapo')), findsOneWidget);
    final cheapoPrice =
        tester.widget<Text>(find.byKey(const ValueKey('market_price_Cheapo')));
    expect(cheapoPrice.style?.color, isNot(errorColor));
  });

  testWidgets('locked: every control is dead with the locked reason',
      (tester) async {
    await pumpTab(tester, lockOverride: FantasyLockOverride.locked);
    await land(tester);
    expect(find.byKey(const ValueKey('market_add_Alan Keeper')), findsNothing);
    final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('market_add_disabled_Alan Keeper')));
    expect(tooltip.message, 'Gameweek locked — no changes now.');
  });

  testWidgets('no underlined text anywhere on the market (house rule)',
      (tester) async {
    await pumpTab(tester);
    await land(
      tester,
      totalsValue: someTotals,
      changesValue: const {
        2: {'Ava Striker': 5, 'Deb Rock': -2},
      },
      gamesValue: [game('11082026', 'Team A', 'Team B')],
    );
    expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
          reason: '"${t.data}" must not be underlined');
    }
  });

  // Review Focus 4: long names at 360 px — market rows and the risers /
  // fallers card (and its View all sheet) wrap without overflow, light AND
  // dark.
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
        '${mode.name} theme at 360 px: a long name + long team wrap with no '
        'overflow (rows, card, View all)', (tester) async {
      final market = [
        player(longName, FantasyPosition.def, 105, team: longTeam),
        player('$longName II', FantasyPosition.def, 104, team: longTeam),
        player('Short', FantasyPosition.def, 40),
        player('$longName Jr', FantasyPosition.gk, 99, team: longTeam),
        player('$longName Guest', FantasyPosition.att, 60,
            team: longTeam, eligible: false),
      ];
      await pumpTab(tester,
          marketPlayers: market, size: const Size(360, 780), themeMode: mode);
      await land(
        tester,
        totalsValue: {
          longName: const FantasyPlayerTotals(
              points: 1234, ownershipPct: 100, formTenths: 123),
        },
        changesValue: {
          5: {
            longName: 15,
            '$longName II': -25,
            '$longName Jr': 105,
            'Short': -1,
          },
        },
        gamesValue: [
          game('11082026', longTeam, 'Another Very Long Team Name FC')
        ],
        watchlistValue: {longName},
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
      expect(find.byKey(ValueKey('market_row_$longName')), findsOneWidget);

      // Search open + unsaved pill + every sort.
      await tester.tap(find.byKey(const ValueKey('market_search_toggle')));
      draft.addPlayer(market[2]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unsaved_pill')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final s in ['form', 'price', 'ownership', 'points']) {
        await tester.tap(find.byKey(ValueKey('market_sort_$s')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'sort $s overflowed');
      }

      // Scroll the whole list (guests at the bottom).
      await tester.drag(
          find.byKey(const ValueKey('market_list')), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byKey(const ValueKey('market_list')), const Offset(0, 2000));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('price_movers_view_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_moves_sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
