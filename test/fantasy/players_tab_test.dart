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
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_player_sheet.dart';
import 'package:infinite_sports_flutter/fantasy/hub/players_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

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
  late StreamController<bool> seasonFinished;
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
    seasonFinished = StreamController<bool>.broadcast();
    opened = [];
  });

  tearDown(() {
    totals.close();
    changes.close();
    games.close();
    watchlist.close();
    seasonFinished.close();
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    List<FantasyPlayer>? marketPlayers,
    FantasyLockOverride lockOverride = FantasyLockOverride.open,
    String selfUid = 'me',
    Size size = const Size(420, 1400),
    ThemeMode themeMode = ThemeMode.light,
    Future<int> Function()? loadStartHour,
    Stream<List<TournamentMatch>> Function(int startHour)? leagueGamesFor,
    Stream<bool>? seasonFinishedStates,
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
          // [leagueGamesFor] runs the REAL hour → games path (and its
          // session cache) with only LeagueService.watchGames replaced.
          gamesStates: leagueGamesFor == null ? games.stream : null,
          leagueGamesFor: leagueGamesFor,
          loadStartHour: loadStartHour,
          watchlistStates: watchlist.stream,
          // Default: the league's Finished flag answers "not over" at once
          // (like a cache-seeded stream); a test drives it live by passing
          // [seasonFinished].stream.
          seasonFinishedStates:
              seasonFinishedStates ?? Stream<bool>.value(false),
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

  final marketScrollable = find.descendant(
      of: find.byKey(const ValueKey('market_list')),
      matching: find.byType(Scrollable));

  IconData? sortArrow(WidgetTester tester) =>
      tester.widget<Icon>(find.byKey(const ValueKey('market_sort_dir'))).icon;

  testWidgets('one fade reveal: a skeleton until EVERY feed has landed',
      (tester) async {
    await pumpTab(tester, seasonFinishedStates: seasonFinished.stream);
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
    await tester.pump();
    // The season-finished flag hasn't answered yet either — still the
    // skeleton (no price arrows flashing in then out).
    expect(
        find.byKey(const ValueKey('players_market_skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('market_row_Ava Striker')), findsNothing);

    seasonFinished.add(false);
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

  testWidgets(
      'a revisit after a FAILED then SUCCESSFUL start-hour read never shows '
      '"0 PM" (the real games path and its session cache)', (tester) async {
    final derived = <int, StreamController<List<TournamentMatch>>>{};
    Stream<List<TournamentMatch>> gamesFor(int hour) {
      final c = StreamController<List<TournamentMatch>>.broadcast();
      derived[hour] = c;
      addTearDown(c.close);
      return c.stream;
    }

    List<TournamentMatch> legacyAt(int hour) => [
          leagueMatchFromGameMap(
            dateKey: '11082026',
            index: 0,
            raw: {'team1': 'Team A', 'team2': 'Team B', 'status': 0},
            startHour: hour,
          ),
        ];
    String nextLine() => tester
        .widget<Text>(find.byKey(const ValueKey('market_next_Ava Striker')))
        .data!;

    // Visit 1: the hour read fails → the games are derived with hour 0.
    await pumpTab(tester,
        loadStartHour: () async => throw StateError('offline'),
        leagueGamesFor: gamesFor);
    await tester.pump();
    totals.add(null);
    changes.add(const {});
    watchlist.add(const {});
    derived[0]!.add(legacyAt(0));
    await tester.pumpAndSettle();
    expect(nextLine(), 'vs Team B · Sun');

    // Visit 2: the hour read now succeeds — but the session's games were
    // derived with 0 until the re-derived ones arrive.
    final hour = Completer<int>();
    await tester.pumpWidget(const SizedBox());
    await pumpTab(tester,
        loadStartHour: () => hour.future, leagueGamesFor: gamesFor);
    await tester.pump();
    expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
    expect(nextLine(), 'vs Team B · Sun');

    hour.complete(5);
    await tester.pump();
    await tester.pump();
    expect(derived.keys, [0, 5]); // re-derived with the real hour
    expect(nextLine(), 'vs Team B · Sun'); // the stale games: no "0 PM"
    expect(find.textContaining('0 PM'), findsNothing);

    derived[5]!.add(legacyAt(5));
    await tester.pumpAndSettle();
    expect(nextLine(), 'vs Team B · Sun 5 PM');
  });

  testWidgets(
      'offline first visit (Opus audit item 6): a start-hour read that never '
      'answers is given up after 8 s — the market reveals with the no-time '
      'game line, never an eternal skeleton', (tester) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    // Restored inside the body (the binding checks debug vars before any
    // tearDown runs).
    try {
      final derived = <int, StreamController<List<TournamentMatch>>>{};
      Stream<List<TournamentMatch>> gamesFor(int hour) {
        final c = StreamController<List<TournamentMatch>>.broadcast();
        derived[hour] = c;
        addTearDown(c.close);
        return c.stream;
      }

      // A cold offline once(): no answer, ever.
      final never = Completer<int>();
      await pumpTab(tester,
          loadStartHour: () => never.future, leagueGamesFor: gamesFor);
      totals.add(null);
      changes.add(const {});
      watchlist.add(const {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      // Every other feed has answered; the games still wait on the hour.
      expect(
          find.byKey(const ValueKey('players_market_skeleton')), findsOneWidget);
      expect(derived, isEmpty);

      await tester.pump(const Duration(seconds: 1)); // the 8 s bound
      expect(derived.keys, [0]); // derived WITHOUT an hour
      derived[0]!.add([legacyGame('11082026', 'Team A', 'Team B')]);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('market_next_Ava Striker')))
              .data,
          'vs Team B · Sun');
      expect(find.textContaining('0 PM'), findsNothing);
    } finally {
      debugPrint = original;
    }
    expect(logs.join('\n'),
        contains('FantasyPlayersTab: start hour: no answer after 8s'));
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

  group('form line (owner follow-up A)', () {
    // Form is shown next to total points: one decimal + " form", "—" when he
    // has played no games (or the server wrote no form).
    const formTotals = <String, FantasyPlayerTotals>{
      'Ava Striker': FantasyPlayerTotals(
          points: 331,
          ownershipPct: 62,
          formTenths: 250,
          ppgTenths: 45,
          games: 12),
      'Gus Glove': FantasyPlayerTotals(
          points: 70, ownershipPct: 8, formTenths: 67, ppgTenths: 58, games: 12),
      // Old-shape node: points only — no form, no games.
      'Dana Wall': FantasyPlayerTotals(points: 12, ownershipPct: 30),
      // Games 0 → "—" even though a form number exists.
      'Deb Rock': FantasyPlayerTotals(
          points: 0, ownershipPct: 5, formTenths: 30, ppgTenths: 0, games: 0),
      // Games but formTenths null.
      'Axel Shot': FantasyPlayerTotals(
          points: 9, ownershipPct: 1, ppgTenths: 12, games: 3),
    };

    String formText(WidgetTester tester, String name) => tester
        .widget<Text>(find.byKey(ValueKey('market_form_$name')))
        .data!;

    testWidgets(
        'under the points line: 250 → "25.0 form", 67 → "6.7 form"; no '
        'form / no games / no entry → "— form"', (tester) async {
      await pumpTab(tester);
      await land(tester, totalsValue: formTotals);

      expect(formText(tester, 'Ava Striker'), '25.0 form');
      expect(formText(tester, 'Gus Glove'), '6.7 form');
      expect(formText(tester, 'Dana Wall'), '— form'); // no form, no games
      expect(formText(tester, 'Deb Rock'), '— form'); // games == 0
      expect(formText(tester, 'Axel Shot'), '— form'); // formTenths null
      expect(formText(tester, 'Alan Keeper'), '— form'); // totals, no entry
      // The points line is unchanged.
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('market_points_Ava Striker')))
              .data,
          '331 pts');
    });

    testWidgets('same muted style as the points line, one line below it',
        (tester) async {
      await pumpTab(tester);
      await land(tester, totalsValue: formTotals);

      final points = tester.widget<Text>(
          find.byKey(const ValueKey('market_points_Ava Striker')));
      final form = tester
          .widget<Text>(find.byKey(const ValueKey('market_form_Ava Striker')));
      expect(form.style, points.style);
      final pointsY = tester
          .getTopLeft(find.byKey(const ValueKey('market_points_Ava Striker')))
          .dy;
      final formY = tester
          .getTopLeft(find.byKey(const ValueKey('market_form_Ava Striker')))
          .dy;
      expect(formY, greaterThan(pointsY));
      // Right-aligned with the points line (the same column).
      expect(
          tester
              .getTopRight(
                  find.byKey(const ValueKey('market_form_Ava Striker')))
              .dx,
          tester
              .getTopRight(
                  find.byKey(const ValueKey('market_points_Ava Striker')))
              .dx);
    });

    testWidgets('absent totals: no form line at all (like the points line)',
        (tester) async {
      await pumpTab(tester);
      await land(tester);
      expect(
          find.byKey(const ValueKey('market_form_Ava Striker')), findsNothing);
      expect(find.textContaining(' form'), findsNothing);
      expect(find.textContaining(' pts'), findsNothing);
    });

    testWidgets('sorting is untouched: Total Pts is still the default order',
        (tester) async {
      await pumpTab(tester);
      await land(tester, totalsValue: formTotals);
      expectOrder(tester, ['Ava Striker', 'Gus Glove', 'Dana Wall']);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('no overflow at 360 px with the third line ($mode)',
          (tester) async {
        await pumpTab(tester,
            size: const Size(360, 900),
            themeMode: mode,
            marketPlayers: [
              player(longName, FantasyPosition.att, 105, team: longTeam),
              ...players,
            ]);
        await land(tester, totalsValue: {
          longName: const FantasyPlayerTotals(
              points: 1234,
              ownershipPct: 100,
              formTenths: 1055,
              ppgTenths: 99,
              games: 20),
          ...formTotals,
        }, changesValue: const {
          1: {'Ava Striker': 5},
        });
        expect(tester.takeException(), isNull);
        expect(formText(tester, longName), '105.5 form');
      });
    }
  });

  group('season over (owner follow-up C): price arrows go away', () {
    final market = <FantasyPlayer>[
      player('Gil Keeper', FantasyPosition.gk, 50),
      player('Gary Gloves', FantasyPosition.gk, 45, team: 'Team B'),
      player('Dan Back', FantasyPosition.def, 60),
      player('Abe Shot', FantasyPosition.att, 70),
    ];
    const moves = {
      3: {'Gil Keeper': 3, 'Gary Gloves': -3, 'Dan Back': -2, 'Abe Shot': 5},
    };
    const owned = {
      'Gil Keeper': FantasyPlayerTotals(points: 20, ownershipPct: 41),
      'Dan Back': FantasyPlayerTotals(points: 15, ownershipPct: 17),
    };

    testWidgets(
        'not finished: every row has its arrow and the Risers / Fallers '
        'card shows', (tester) async {
      await pumpTab(tester, marketPlayers: market);
      await land(tester, totalsValue: owned, changesValue: moves);
      for (final p in market) {
        expect(find.byKey(ValueKey('market_move_${p.name}')), findsOneWidget,
            reason: p.name);
      }
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
    });

    testWidgets(
        'finished: no price-move arrow on any row and no Risers / Fallers '
        'card — the owned % stays', (tester) async {
      await pumpTab(tester,
          marketPlayers: market, seasonFinishedStates: Stream.value(true));
      await land(tester, totalsValue: owned, changesValue: moves);
      for (final p in market) {
        expect(find.byKey(ValueKey('market_move_${p.name}')), findsNothing,
            reason: p.name);
      }
      expect(find.byKey(const ValueKey('price_movers_card')), findsNothing);
      // The owned % keeps its column; price + points + form are untouched.
      expect(find.byKey(const ValueKey('market_owned_Gil Keeper')),
          findsOneWidget);
      expect(find.text('41%'), findsOneWidget);
      expect(find.byKey(const ValueKey('market_price_Gil Keeper')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('market_points_Gil Keeper')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('market_form_Gil Keeper')), findsOneWidget);
    });

    testWidgets('live: the flag flipping removes / restores the arrows + card',
        (tester) async {
      await pumpTab(tester,
          marketPlayers: market, seasonFinishedStates: seasonFinished.stream);
      seasonFinished.add(false);
      await land(tester, totalsValue: owned, changesValue: moves);
      expect(find.byKey(const ValueKey('market_move_Gil Keeper')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);

      seasonFinished.add(true);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('market_move_Gil Keeper')), findsNothing);
      expect(find.byKey(const ValueKey('price_movers_card')), findsNothing);

      seasonFinished.add(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('market_move_Gil Keeper')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
    });

    testWidgets(
        'the flag is part of the reveal gate: no arrows flashing in then '
        'out', (tester) async {
      await pumpTab(tester,
          marketPlayers: market, seasonFinishedStates: seasonFinished.stream);
      totals.add(owned);
      changes.add(moves);
      games.add(const []);
      watchlist.add(const {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Everything else landed, the flag has not: still the skeleton, and no
      // arrow was ever built.
      expect(find.byKey(const ValueKey('players_market_skeleton')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('market_move_Gil Keeper')), findsNothing);

      seasonFinished.add(true);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
      expect(
          find.byKey(const ValueKey('market_row_Gil Keeper')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('market_move_Gil Keeper')), findsNothing);
    });

    testWidgets('a failing flag feed is logged and treated as not finished',
        (tester) async {
      final logs = <String?>[];
      final oldPrint = debugPrint;
      // Restored in the body (the framework checks foundation vars BEFORE
      // addTearDown callbacks run).
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m);
      try {
        await pumpTab(tester,
            marketPlayers: market,
            seasonFinishedStates:
                Stream<bool>.error(StateError('permission denied')));
        await land(tester, totalsValue: owned, changesValue: moves);
      } finally {
        debugPrint = oldPrint;
      }
      expect(
          find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
      expect(find.byKey(const ValueKey('market_move_Gil Keeper')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
      expect(logs.any((l) => l != null && l.contains('permission denied')),
          isTrue);
    });

    testWidgets('a revisit paints at once from the session (no skeleton)',
        (tester) async {
      await pumpTab(tester,
          marketPlayers: market, seasonFinishedStates: Stream.value(true));
      await land(tester, totalsValue: owned, changesValue: moves);
      expect(
          find.byKey(const ValueKey('market_move_Gil Keeper')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      // The second visit's flag stream never answers: the session answers.
      await pumpTab(tester,
          marketPlayers: market,
          seasonFinishedStates: const Stream<bool>.empty());
      await tester.pump();
      expect(
          find.byKey(const ValueKey('players_market_skeleton')), findsNothing);
      expect(
          find.byKey(const ValueKey('market_move_Gil Keeper')), findsNothing);
      expect(find.byKey(const ValueKey('price_movers_card')), findsNothing);
    });
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
    final errorColor = fantasyDownRed(context);
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

  // FPL selling (spec §4): the add control asks the DRAFT what he costs and
  // how much room is left — never the market price against the bare budget.
  testWidgets(
      'a sold baseline player is priced by the draft: addable with exactly '
      'his sell price left, though the market says more', (tester) async {
    final rich = [
      player('Money Bags', FantasyPosition.def, 440),
      player('Pricey Att', FantasyPosition.att, 70, team: 'Team C'),
      ...players,
    ];
    // Last week: Ava bought at $6.0M; today $7.0M → selling her banked
    // $6.5M (+$0.5M realized).
    draft.setSaleContext(
      sale: const SaleBaselineState(
        baseline: SaleBaseline(
            forGw: 3, prices: {'Ava Striker': 60}, realizedTenths: 0),
        loaded: true,
      ),
      currentPrices: {for (final p in rich) p.name: p.priceTenths},
      editingGw: 3,
    );
    await pumpTab(tester, marketPlayers: rich);
    await land(tester);
    await tester.tap(find.byKey(const ValueKey('market_add_Money Bags')));
    await tester.pumpAndSettle();
    // $50.0M + $0.5M − $44.0M = $6.5M left.
    expect(draft.remainingTenths, 65);

    // Taking Ava back undoes her $6.5M sale: exactly affordable.
    expect(
        find.byKey(const ValueKey('market_add_Ava Striker')), findsOneWidget);
    final context =
        tester.element(find.byKey(const ValueKey('players_market')));
    final avaPrice = tester
        .widget<Text>(find.byKey(const ValueKey('market_price_Ava Striker')));
    expect(avaPrice.style?.color, isNot(fantasyDownRed(context)));
    // A $7.0M player bought new is not.
    expect(find.byKey(const ValueKey('market_add_disabled_Pricey Att')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('market_add_Ava Striker')));
    await tester.pumpAndSettle();
    expect(draft.playerIds, contains('Ava Striker'));
    expect(draft.remainingTenths, 0);
  });

  // The market's large player sheet (kept for a quick compare-and-buy):
  // the same Remove + sells-for rule as the profile.
  group('market player sheet: the sells-for line', () {
    Future<void> pumpSheet(WidgetTester tester, FantasyPlayer p,
        {Brightness brightness = Brightness.light,
        Size size = const Size(420, 900)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        home: Scaffold(
          body: MarketPlayerSheet(
            player: p,
            draft: draft,
            editable: true,
            totals: null,
            totalsAvailable: false,
            initialStats: const <String, TournamentPlayer>{},
            statsStates: const Stream.empty(),
          ),
        ),
      ));
      await tester.pump();
    }

    void feedBaseline() => draft.setSaleContext(
          sale: const SaleBaselineState(
            baseline: SaleBaseline(
                forGw: 3, prices: {'Ava Striker': 80}, realizedTenths: 0),
            loaded: true,
          ),
          currentPrices: {for (final p in players) p.name: p.priceTenths},
          editingGw: 3,
        );

    for (final brightness in Brightness.values) {
      testWidgets('an owned baseline player: Bought · Sells for, 360 px — '
          '$brightness', (tester) async {
        feedBaseline();
        draft.addPlayer(players[4]); // Ava, held at her $8.0M
        await pumpSheet(tester, players[4],
            brightness: brightness, size: const Size(360, 900));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('sheet_remove')), findsOneWidget);
        // Bought $8.0M, now $7.0M: the full drop.
        final line = find.byKey(const ValueKey('sheet_sells_for'));
        expect(tester.widget<Text>(line).data,
            'Bought \$8.0M · Sells for \$7.0M');
        final r = tester.getRect(line);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      });
    }

    testWidgets('money not ready: no line; ready again: the line comes back',
        (tester) async {
      // Last week's baseline (ForGw 2 while GW3 is edited): never a stale
      // "Sells for" presented as this week's.
      draft.setSaleContext(
        sale: const SaleBaselineState(
          baseline: SaleBaseline(
              forGw: 2, prices: {'Ava Striker': 80}, realizedTenths: 0),
          loaded: true,
        ),
        currentPrices: {for (final p in players) p.name: p.priceTenths},
        editingGw: 3,
      );
      draft.addPlayer(players[4]); // Ava, held at her $8.0M
      await pumpSheet(tester, players[4]);
      expect(draft.moneyReady, isFalse);
      expect(find.byKey(const ValueKey('sheet_remove')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet_sells_for')), findsNothing);

      feedBaseline();
      await tester.pump();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sheet_sells_for')))
              .data,
          'Bought \$8.0M · Sells for \$7.0M');
    });

    testWidgets('an owned player bought this week, or one not owned: no line',
        (tester) async {
      feedBaseline();
      draft.addPlayer(players[2]); // Dana Wall — new this week
      await pumpSheet(tester, players[2]);
      expect(find.byKey(const ValueKey('sheet_remove')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet_sells_for')), findsNothing);

      await pumpSheet(tester, players[4]); // Ava, sold: Add, no line
      expect(find.byKey(const ValueKey('sheet_add')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet_sells_for')), findsNothing);
    });
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

  testWidgets(
      'the Price Changes card follows every eligible row and sits '
      'before the "Not eligible" guests (owner\'s mockup)', (tester) async {
    await pumpTab(tester);
    await land(
      tester,
      totalsValue: someTotals,
      changesValue: const {
        2: {'Ava Striker': 5, 'Deb Rock': -2},
      },
    );
    // The player rows lead the market — the first row is the list's first
    // item, right under the sort bar.
    expect(
        rowY(tester, 'Gus Glove'),
        lessThan(tester
                .getBottomLeft(find.byKey(const ValueKey('market_sort_points')))
                .dy +
            40));
    final cardTop =
        tester.getTopLeft(find.byKey(const ValueKey('price_movers_card'))).dy;
    for (final name in [
      'Alan Keeper',
      'Gus Glove',
      'Dana Wall',
      'Deb Rock',
      'Ava Striker',
      'Axel Shot',
    ]) {
      expect(rowY(tester, name), lessThan(cardTop), reason: name);
    }
    expect(
        cardTop,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('not_eligible_divider')))
            .dy));
    expect(cardTop, lessThan(rowY(tester, 'Guest Guy')));
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
      // The player rows lead (above the fold); the card follows them.
      expect(find.byKey(ValueKey('market_row_$longName')), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('price_movers_card')), 150,
          scrollable: marketScrollable);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_movers_card')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byKey(const ValueKey('market_list')), const Offset(0, 3000));
      await tester.pumpAndSettle();

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

      // Scroll the whole list — through the card to the guests at the
      // bottom.
      await tester.drag(
          find.byKey(const ValueKey('market_list')), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(ValueKey('market_row_$longName Guest')), findsOneWidget);
      await tester.drag(
          find.byKey(const ValueKey('market_list')), const Offset(0, 3000));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('price_movers_view_all')), 150,
          scrollable: marketScrollable);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('price_movers_view_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price_moves_sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
