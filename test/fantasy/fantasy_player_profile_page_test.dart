// Fantasy round 3, Task 5 — the full-screen player profile page proved with
// fake streams (no Firebase): one fade reveal once every feed lands; name,
// price, move and the four tabs; "See full profile" only for a linked
// account; Add to Team edits the shared draft (reasons when it can't);
// "Open in Fantasy" from outside the hub; the watchlist star (hidden signed
// out); empty + voided copy; and no overflow at 360×780 in light AND dark.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart'
    show fantasyDownRed;
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart'
    show fantasyAccent;
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_hero.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

const _name = 'Demsin Betvarda';
const _longName =
    'Maximiliano Alessandro Bartholomew-Featherstonehaugh Von Grünewald';

FantasyPlayer _player(String name, FantasyPosition pos, int price,
        {String team = 'Ishtar', bool eligible = true}) =>
    FantasyPlayer(
      name: name,
      position: pos,
      priceTenths: price,
      eligible: eligible,
      teamName: team,
    );

TournamentPlayer _rosterRow(String name, String team,
        {String? uid, String? number, int goals = 8}) =>
    TournamentPlayer(
      name: name,
      teamId: team,
      teamName: team,
      uid: uid,
      number: number,
      goals: goals,
      assists: 6,
      saves: 0,
      dpl: 2,
      cleanSheets: 4,
      yellowCards: 1,
      redCards: 0,
    );

List<Gameweek> _gameweeks(int count) => [
      for (var i = 1; i <= count; i++)
        Gameweek(
          number: i,
          date: '1${i - 1}012026',
          lockUtc: DateTime.utc(2026, 10, i, 23),
          opensUtc: null,
        ),
    ];

PlayerWeekStats _week(int pts,
        {Map<String, ScoreSourceLine> lines = const {},
        bool voided = false,
        String vs = 'Nimrod'}) =>
    PlayerWeekStats(
      points: pts,
      played: true,
      gamesPlayed: 1,
      games: [PlayerWeekGame(vs: vs, goalsFor: 3, goalsAgainst: 2)],
      lines: lines,
      voided: voided,
    );

TournamentMatch _game(String date, String team1, String team2) =>
    leagueMatchFromGameMap(
      dateKey: date,
      index: 0,
      raw: {'team1': team1, 'team2': team2, 'status': 0, 'Time': '15:00'},
    );

/// A legacy game with NO stored Time: its text is derived from the season
/// start hour the adapter was given (0 → "0:00PM").
TournamentMatch _legacyGame(String date, String team1, String team2,
        {int startHour = 0}) =>
    leagueMatchFromGameMap(
      dateKey: date,
      index: 0,
      raw: {'team1': team1, 'team2': team2, 'status': 0},
      startHour: startHour,
    );

void main() {
  late StreamController<FantasyConfigState?> config;
  late StreamController<List<Gameweek>> gameweeks;
  late StreamController<List<FantasyPlayer>> players;
  late StreamController<Map<String, FantasyPlayerTotals>?> totals;
  late StreamController<Map<int, Map<String, int>>> history;
  late StreamController<Map<int, Map<String, int>>> changes;
  late StreamController<Map<int, PlayerWeekStats>> weekStats;
  late StreamController<Map<String, List<TournamentPlayer>>> rosters;
  late StreamController<List<TournamentMatch>> games;
  late StreamController<List<TournamentTeam>> teams;
  late StreamController<Set<String>> watchlist;
  late StreamController<bool> seasonFinished;
  late List<List<int>> requestedWeeks;
  late List<(String, bool)> starWrites;
  late List<String> openedProfiles;
  late List<FantasyHubRoute> openInFantasyRoutes;
  late SquadDraftController draft;

  final market = [
    _player(_name, FantasyPosition.def, 75),
    _player('Other Def', FantasyPosition.def, 60, team: 'Nimrod'),
    _player(_longName, FantasyPosition.att, 105, team: 'Kings'),
  ];

  setUp(() {
    FantasyPlayerProfilePage.clearSessionCaches();
    config = StreamController<FantasyConfigState?>.broadcast();
    gameweeks = StreamController<List<Gameweek>>.broadcast();
    players = StreamController<List<FantasyPlayer>>.broadcast();
    totals = StreamController<Map<String, FantasyPlayerTotals>?>.broadcast();
    history = StreamController<Map<int, Map<String, int>>>.broadcast();
    changes = StreamController<Map<int, Map<String, int>>>.broadcast();
    weekStats = StreamController<Map<int, PlayerWeekStats>>.broadcast();
    rosters = StreamController<Map<String, List<TournamentPlayer>>>.broadcast();
    games = StreamController<List<TournamentMatch>>.broadcast();
    teams = StreamController<List<TournamentTeam>>.broadcast();
    watchlist = StreamController<Set<String>>.broadcast();
    seasonFinished = StreamController<bool>.broadcast();
    requestedWeeks = [];
    starWrites = [];
    openedProfiles = [];
    openInFantasyRoutes = [];
    draft = SquadDraftController(config: FantasyConfig.futsalDefault());
  });

  tearDown(() {
    for (final c in [
      config,
      gameweeks,
      players,
      totals,
      history,
      changes,
      weekStats,
      rosters,
      games,
      teams,
      watchlist,
      seasonFinished,
    ]) {
      c.close();
    }
    draft.dispose();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String name = _name,
    String selfUid = 'me',
    bool withDraft = true,
    bool fromOutsideHub = false,
    Size size = const Size(420, 900),
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
      home: FantasyPlayerProfilePage(
        sport: 'Futsal',
        season: '15',
        playerName: name,
        draft: withDraft ? draft : null,
        fromOutsideHub: fromOutsideHub,
        configStates: config.stream,
        gameweekStates: gameweeks.stream,
        playersStates: players.stream,
        totalsStates: totals.stream,
        priceHistoryStates: history.stream,
        priceChangeStates: changes.stream,
        weekStatsFor: (weeks) {
          requestedWeeks.add(weeks);
          return weekStats.stream;
        },
        rosterStates: rosters.stream,
        // [leagueGamesFor] runs the REAL hour → games path (and its session
        // cache) with only LeagueService.watchGames replaced.
        gamesStates: leagueGamesFor == null ? games.stream : null,
        leagueGamesFor: leagueGamesFor,
        teamsStates: teams.stream,
        watchlistStates: watchlist.stream,
        // Default: the league's Finished flag answers "not over" at once
        // (like a cache-seeded stream); a test drives it live by passing
        // [seasonFinished].stream.
        seasonFinishedStates:
            seasonFinishedStates ?? Stream<bool>.value(false),
        selfUidOverride: selfUid,
        setWatchlisted: (n, on) async => starWrites.add((n, on)),
        loadLogoUrls: () async => const {},
        loadStartHour: loadStartHour,
        openFullProfile: (context, uid, n) => openedProfiles.add('$uid|$n'),
        openInFantasy: (context, route) => openInFantasyRoutes.add(route),
        nowUtc: () => DateTime.utc(2026, 11, 2, 18),
      ),
    ));
  }

  /// Every feed lands (week stats only after the schedule, as in the app).
  Future<void> emitAll(
    WidgetTester tester, {
    FantasyLockOverride lock = FantasyLockOverride.open,
    List<Gameweek>? weeks,
    Map<String, FantasyPlayerTotals>? totalsValue = const {
      _name: FantasyPlayerTotals(
          points: 64,
          ownershipPct: 55,
          formTenths: 67,
          ppgTenths: 53,
          games: 12),
    },
    Map<int, Map<String, int>> historyValue = const {
      1: {_name: 70},
      2: {_name: 70},
      3: {_name: 75},
    },
    Map<int, Map<String, int>> changesValue = const {
      1: {'Other Def': 2},
      2: {_name: 5},
    },
    Map<int, PlayerWeekStats>? weeksValue,
    Map<String, List<TournamentPlayer>>? rostersValue,
    List<TournamentMatch> gamesValue = const [],
    Set<String> watchlistValue = const {},
    List<FantasyPlayer>? playersValue,
  }) async {
    config.add(FantasyConfigState(
        config: FantasyConfig.futsalDefault(), lockOverride: lock));
    gameweeks.add(weeks ?? _gameweeks(3));
    players.add(playersValue ?? market);
    totals.add(totalsValue);
    history.add(historyValue);
    changes.add(changesValue);
    rosters.add(rostersValue ??
        {
          'Ishtar': [_rosterRow(_name, 'Ishtar', number: '3')],
        });
    games.add(gamesValue);
    teams.add(const []);
    watchlist.add(watchlistValue);
    await tester.pump();
    weekStats.add(weeksValue ??
        {
          1: _week(2, lines: const {
            'plays': ScoreSourceLine(count: 1, points: 2),
          }),
          2: _week(8,
              lines: const {
                'plays': ScoreSourceLine(count: 1, points: 2),
                'goals': ScoreSourceLine(count: 1, points: 6),
              },
              vs: 'Kings'),
          3: _week(6, lines: const {
            'plays': ScoreSourceLine(count: 1, points: 2),
            'assists': ScoreSourceLine(count: 1, points: 4),
          }),
        });
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(key('profile_tab_$tab'));
    await tester.pumpAndSettle();
  }

  group('price colour + season over (owner follow-ups B + C)', () {
    Color? priceColor(WidgetTester tester) =>
        tester.widget<Text>(key('profile_price')).style?.color;

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
          'the big price is colorScheme.onSurface ($mode), not the fantasy '
          'accent', (tester) async {
        await pumpPage(tester, themeMode: mode);
        await emitAll(tester);
        final ctx = tester.element(key('profile_price'));
        final scheme = Theme.of(ctx).colorScheme;
        expect(priceColor(tester), scheme.onSurface);
        expect(priceColor(tester), isNot(fantasyAccent(ctx)));
        // Same ink as the other strip numbers.
        expect(tester.widget<Text>(key('profile_total')).style?.color,
            scheme.onSurface);
        expect(find.text('\$7.5M'), findsWidgets);
      });
    }

    testWidgets(
        'not finished: the move line is exactly as before and there is no '
        '"Final price"', (tester) async {
      await pumpPage(tester);
      await emitAll(tester);
      expect(find.text('▲ \$0.5M this week'), findsOneWidget);
      expect(key('profile_move'), findsOneWidget);
      expect(find.text('Final price'), findsNothing);
    });

    testWidgets('a fall is still "▼ … this week" in the down red',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester, changesValue: const {
        2: {_name: -5},
      });
      expect(find.text('▼ \$0.5M this week'), findsOneWidget);
      expect(tester.widget<Text>(key('profile_move')).style?.color,
          fantasyDownRed(tester.element(key('profile_move'))));
    });

    testWidgets(
        'finished: "Final price" (muted) under the price — no arrow, no '
        '"this week"', (tester) async {
      await pumpPage(tester, seasonFinishedStates: Stream.value(true));
      await emitAll(tester);
      expect(find.text('Final price'), findsOneWidget);
      expect(key('profile_final_price'), findsOneWidget);
      expect(key('profile_move'), findsNothing);
      expect(find.textContaining('this week'), findsNothing);
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
      expect(find.text('No change'), findsNothing);
      final scheme = Theme.of(tester.element(key('profile_price'))).colorScheme;
      expect(tester.widget<Text>(key('profile_final_price')).style?.color,
          scheme.onSurfaceVariant);
      // The price itself is still the same big number.
      expect(find.text('\$7.5M'), findsWidgets);
      expect(priceColor(tester), scheme.onSurface);
    });

    testWidgets('finished before any reprice ran: still "Final price"',
        (tester) async {
      await pumpPage(tester, seasonFinishedStates: Stream.value(true));
      await emitAll(tester,
          totalsValue: null,
          historyValue: const {},
          changesValue: const {},
          weeksValue: const {});
      expect(find.text('Final price'), findsOneWidget);
      expect(key('profile_move'), findsNothing);
    });

    testWidgets('live: the flag flipping swaps the move line and the label',
        (tester) async {
      await pumpPage(tester, seasonFinishedStates: seasonFinished.stream);
      seasonFinished.add(false);
      await emitAll(tester);
      expect(find.text('▲ \$0.5M this week'), findsOneWidget);

      seasonFinished.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Final price'), findsOneWidget);
      expect(find.text('▲ \$0.5M this week'), findsNothing);

      seasonFinished.add(false);
      await tester.pumpAndSettle();
      expect(find.text('▲ \$0.5M this week'), findsOneWidget);
      expect(find.text('Final price'), findsNothing);
    });

    testWidgets('finished leaves the Price tab history untouched',
        (tester) async {
      await pumpPage(tester, seasonFinishedStates: Stream.value(true));
      await emitAll(tester);
      await openTab(tester, 'price');
      // GW2's reprice (+$0.5M) still reads in the history rows.
      expect(find.textContaining('▲ \$0.5M'), findsWidgets);
    });

    testWidgets(
        'the flag is part of the reveal gate: nothing paints (no arrow '
        'flash) until it has answered', (tester) async {
      await pumpPage(tester, seasonFinishedStates: seasonFinished.stream);
      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open));
      gameweeks.add(_gameweeks(3));
      players.add(market);
      totals.add(const {});
      history.add(const {});
      changes.add(const {
        2: {_name: 5},
      });
      rosters.add(const {});
      games.add(const []);
      teams.add(const []);
      watchlist.add(const {});
      await tester.pump();
      weekStats.add(const {});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(key('fantasy_profile_skeleton'), findsOneWidget);
      expect(key('fantasy_profile_ready'), findsNothing);
      expect(find.text('▲ \$0.5M this week'), findsNothing);

      seasonFinished.add(true);
      await tester.pumpAndSettle();
      expect(key('fantasy_profile_ready'), findsOneWidget);
      expect(find.text('Final price'), findsOneWidget);
      expect(find.text('▲ \$0.5M this week'), findsNothing);
    });

    testWidgets('a failing flag feed is logged and treated as not finished',
        (tester) async {
      final logs = <String?>[];
      final oldPrint = debugPrint;
      // Restored in the body (the framework checks foundation vars BEFORE
      // addTearDown callbacks run).
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m);
      try {
        await pumpPage(tester,
            seasonFinishedStates:
                Stream<bool>.error(StateError('permission denied')));
        await emitAll(tester);
      } finally {
        debugPrint = oldPrint;
      }
      expect(key('fantasy_profile_ready'), findsOneWidget);
      expect(find.text('▲ \$0.5M this week'), findsOneWidget);
      expect(find.text('Final price'), findsNothing);
      expect(logs.any((l) => l != null && l.contains('permission denied')),
          isTrue);
    });
  });

  group('reveal', () {
    testWidgets(
        'skeleton until every feed lands, then ONE fade to the '
        'profile', (tester) async {
      await pumpPage(tester);
      expect(key('fantasy_profile_skeleton'), findsOneWidget);

      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open));
      gameweeks.add(_gameweeks(3));
      players.add(market);
      totals.add(null);
      history.add(const {});
      changes.add(const {});
      rosters.add(const {});
      games.add(const []);
      teams.add(const []);
      watchlist.add(const {});
      await tester.pump();
      // Week stats (one listener per schedule gameweek) haven't answered.
      expect(requestedWeeks.last, [1, 2, 3]);
      expect(key('fantasy_profile_skeleton'), findsOneWidget);
      expect(key('fantasy_profile_ready'), findsNothing);

      weekStats.add(const {});
      await tester.pump();
      await tester.pumpAndSettle();
      expect(key('fantasy_profile_ready'), findsOneWidget);
      expect(key('fantasy_profile_skeleton'), findsNothing);
    });

    testWidgets('a player who left the market gets a friendly message',
        (tester) async {
      await pumpPage(tester, name: 'Gone Player');
      await emitAll(tester);
      expect(key('fantasy_profile_missing'), findsOneWidget);
      expect(find.text("This player isn't in the fantasy market anymore."),
          findsOneWidget);
    });
  });

  testWidgets(
      'renders name, team · position, price, move, the stat strip '
      'and the four tabs', (tester) async {
    await pumpPage(tester);
    await emitAll(tester);

    expect(find.text(_name), findsOneWidget);
    expect(find.text('Ishtar · #3 · Fantasy: DEF'), findsOneWidget);
    expect(find.text('\$7.5M'), findsWidgets);
    expect(find.text('▲ \$0.5M this week'), findsOneWidget);
    expect(find.text('64'), findsOneWidget); // total pts
    expect(find.text('5.3'), findsOneWidget); // ppg
    expect(find.text('55%'), findsOneWidget);
    for (final tab in ['Overview', 'Stats', 'Matches', 'Price']) {
      expect(find.text(tab), findsOneWidget);
    }

    // Overview: last weeks' bars with the value on top, next game, stats.
    expect(key('form_bar_1'), findsOneWidget);
    expect(key('form_bar_3'), findsOneWidget);
    expect(find.text('Season stats (S15)'), findsOneWidget);
    expect(find.text('1Y · 0R'), findsOneWidget);

    // Stats: points by source.
    await openTab(tester, 'stats');
    expect(find.text('Where his points came from'), findsOneWidget);
    expect(find.text('Played ×3'), findsOneWidget);
    expect(find.text('Goals ×1'), findsOneWidget);
    expect(find.text('6.7'), findsOneWidget); // form

    // Matches: newest first with the season total to date.
    await openTab(tester, 'matches');
    expect(tester.getTopLeft(key('match_row_3')).dy,
        lessThan(tester.getTopLeft(key('match_row_1')).dy));
    expect(find.text('Season 16'), findsOneWidget);

    // Price: start / high / low and per-week rows.
    await openTab(tester, 'price');
    expect(key('price_row_3'), findsOneWidget);
    expect(find.text('▲ \$0.5M'), findsOneWidget); // move after GW2
  });

  testWidgets('a form bar tap shows that week\'s breakdown', (tester) async {
    await pumpPage(tester);
    await emitAll(tester);
    expect(key('week_breakdown'), findsNothing);
    await tester.tap(key('form_bar_2'));
    await tester.pumpAndSettle();
    expect(key('week_breakdown'), findsOneWidget);
    expect(find.text('Goals ×1'), findsOneWidget);
    expect(find.text('6 pts'), findsOneWidget);
  });

  testWidgets('next game line comes from the live schedule', (tester) async {
    await pumpPage(tester);
    await emitAll(tester, gamesValue: [_game('11082026', 'Ishtar', 'Nimrod')]);
    expect(find.text('Next: vs Nimrod · Sun 3 PM'), findsOneWidget);
  });

  group('season start hour', () {
    testWidgets(
        'unknown (0 = absent / failed read): a derived time is '
        'dropped, never "0 PM"', (tester) async {
      await pumpPage(tester, loadStartHour: () async => 0);
      await emitAll(tester,
          gamesValue: [_legacyGame('11082026', 'Ishtar', 'Nimrod')]);
      expect(find.text('Next: vs Nimrod · Sun'), findsOneWidget);
      expect(find.textContaining('0 PM'), findsNothing);
    });

    testWidgets('a failed read is not cached — the next visit asks again',
        (tester) async {
      var calls = 0;
      Future<int> failing() async {
        calls++;
        throw StateError('offline');
      }

      await pumpPage(tester, loadStartHour: failing);
      await emitAll(tester,
          gamesValue: [_legacyGame('11082026', 'Ishtar', 'Nimrod')]);
      expect(find.text('Next: vs Nimrod · Sun'), findsOneWidget);
      expect(calls, 1);

      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, loadStartHour: failing);
      await emitAll(tester);
      expect(calls, 2);
    });

    testWidgets('a real hour is cached for the session (one read)',
        (tester) async {
      var calls = 0;
      Future<int> fivePm() async {
        calls++;
        return 5;
      }

      await pumpPage(tester, loadStartHour: fivePm);
      await emitAll(tester, gamesValue: [
        _legacyGame('11082026', 'Ishtar', 'Nimrod', startHour: 5),
      ]);
      expect(find.text('Next: vs Nimrod · Sun 5 PM'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester, loadStartHour: fivePm);
      await emitAll(tester);
      expect(calls, 1);
    });

    testWidgets(
        'a revisit after a FAILED then SUCCESSFUL read never shows "0 PM" '
        '(the real games path and its session cache)', (tester) async {
      final derived = <int, StreamController<List<TournamentMatch>>>{};
      Stream<List<TournamentMatch>> gamesFor(int hour) {
        final c = StreamController<List<TournamentMatch>>.broadcast();
        derived[hour] = c;
        addTearDown(c.close);
        return c.stream;
      }

      // Visit 1: the hour read fails → the games are derived with hour 0.
      await pumpPage(tester,
          loadStartHour: () async => throw StateError('offline'),
          leagueGamesFor: gamesFor);
      await tester.pump();
      derived[0]!.add([_legacyGame('11082026', 'Ishtar', 'Nimrod')]);
      await emitAll(tester);
      expect(find.text('Next: vs Nimrod · Sun'), findsOneWidget);

      // Visit 2: the hour read now succeeds — but the session's games were
      // derived with 0 until the re-derived ones arrive.
      final hour = Completer<int>();
      await tester.pumpWidget(const SizedBox());
      await pumpPage(tester,
          loadStartHour: () => hour.future, leagueGamesFor: gamesFor);
      await emitAll(tester);
      expect(find.text('Next: vs Nimrod · Sun'), findsOneWidget);

      hour.complete(5);
      await tester.pump();
      await tester.pump();
      expect(derived.keys, [0, 5]); // re-derived with the real hour
      expect(find.text('Next: vs Nimrod · Sun'), findsOneWidget);
      expect(find.textContaining('0 PM'), findsNothing);

      derived[5]!
          .add([_legacyGame('11082026', 'Ishtar', 'Nimrod', startHour: 5)]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Next: vs Nimrod · Sun 5 PM'), findsOneWidget);
    });
  });

  group('See full profile', () {
    testWidgets('hidden when the player has no linked account', (tester) async {
      await pumpPage(tester);
      await emitAll(tester);
      expect(key('profile_full_profile'), findsNothing);
    });

    testWidgets('hidden when the only link is the same name on ANOTHER team',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester, rostersValue: {
        'Nimrod': [_rosterRow(_name, 'Nimrod', uid: 'someone-else')],
        'Ishtar': [_rosterRow(_name, 'Ishtar')],
      });
      expect(key('profile_full_profile'), findsNothing);
    });

    testWidgets('shown with a linked uid and opens that account',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester, rostersValue: {
        'Ishtar': [_rosterRow(_name, 'Ishtar', uid: 'uid-42')],
      });
      expect(key('profile_full_profile'), findsOneWidget);
      await tester.tap(key('profile_full_profile'));
      await tester.pump();
      expect(openedProfiles, ['uid-42|$_name']);
    });
  });

  group('Add to Team', () {
    testWidgets('adds to the shared draft, flips to Remove, then removes',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester);
      expect(find.text('Add to Team'), findsOneWidget);

      await tester.tap(key('profile_add'));
      await tester.pumpAndSettle();
      expect(draft.playerIds, contains(_name));
      expect(draft.dirty, isTrue);
      expect(key('profile_remove'), findsOneWidget);
      expect(find.text('Changes save from the My Team tab.'), findsOneWidget);

      await tester.tap(key('profile_remove'));
      await tester.pumpAndSettle();
      expect(draft.playerIds, isNot(contains(_name)));
      expect(key('profile_add'), findsOneWidget);
    });

    // FPL selling (spec §4): an owned BASELINE player's Remove says what
    // he was bought at and what selling him banks; anyone else's doesn't.
    group('the sells-for line', () {
      void feedBaseline() => draft.setSaleContext(
            sale: const SaleBaselineState(
              baseline: SaleBaseline(
                  forGw: 3, prices: {_name: 70}, realizedTenths: 0),
              loaded: true,
            ),
            currentPrices: {for (final p in market) p.name: p.priceTenths},
            editingGw: 3,
          );

      testWidgets('an owned baseline player: Bought · Sells for',
          (tester) async {
        feedBaseline();
        draft.addPlayer(market.first); // back at his baseline $7.0M
        await pumpPage(tester);
        await emitAll(tester);
        expect(key('profile_remove'), findsOneWidget);
        // Bought $7.0M, now $7.5M: half the rise (rounded down) → $7.2M.
        expect(tester.widget<Text>(key('profile_sells_for')).data,
            'Bought \$7.0M · Sells for \$7.2M');

        // Not owned: no Remove, no line.
        draft.removePlayer(_name);
        await tester.pumpAndSettle();
        expect(key('profile_add'), findsOneWidget);
        expect(key('profile_sells_for'), findsNothing);
      });

      testWidgets('money not ready (last week\'s baseline): no line; ready '
          'again: the line comes back', (tester) async {
        draft.setSaleContext(
          sale: const SaleBaselineState(
            baseline: SaleBaseline(
                forGw: 2, prices: {_name: 70}, realizedTenths: 0),
            loaded: true,
          ),
          currentPrices: {for (final p in market) p.name: p.priceTenths},
          editingGw: 3,
        );
        draft.addPlayer(market.first);
        await pumpPage(tester);
        await emitAll(tester);
        expect(draft.moneyReady, isFalse);
        expect(key('profile_remove'), findsOneWidget);
        expect(key('profile_sells_for'), findsNothing);

        feedBaseline();
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(key('profile_sells_for')).data,
            'Bought \$7.0M · Sells for \$7.2M');
      });

      testWidgets('an owned player bought this week: no line',
          (tester) async {
        feedBaseline();
        draft.addPlayer(market[1]); // Other Def — not a baseline player
        await pumpPage(tester, name: 'Other Def');
        await emitAll(tester);
        expect(key('profile_remove'), findsOneWidget);
        expect(key('profile_sells_for'), findsNothing);
      });

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('${mode.name} theme at 360 px: the line fits the bottom '
            'bar', (tester) async {
          feedBaseline();
          draft.addPlayer(market.first);
          await pumpPage(tester,
              size: const Size(360, 780), themeMode: mode);
          await emitAll(tester);
          expect(tester.takeException(), isNull);
          final line = key('profile_sells_for');
          expect(line, findsOneWidget);
          final r = tester.getRect(line);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          final text = tester.widget<Text>(line);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          final scheme = Theme.of(tester.element(line)).colorScheme;
          expect(text.style?.color, scheme.onSurfaceVariant);
        });
      }
    });

    testWidgets('locked: the button is dead with the market\'s reason',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester, lock: FantasyLockOverride.locked);
      final button = tester.widget<FilledButton>(key('profile_add'));
      expect(button.onPressed, isNull);
      expect(find.text('Gameweek locked — no changes now.'), findsOneWidget);
    });

    testWidgets('from outside the hub the primary button is Open in Fantasy',
        (tester) async {
      await pumpPage(tester, withDraft: false, fromOutsideHub: true);
      await emitAll(tester);
      expect(key('profile_add'), findsNothing);
      expect(find.text('Open in Fantasy'), findsOneWidget);
      await tester.tap(key('profile_open_in_fantasy'));
      await tester.pump();
      // The hub opens ON THIS PLAYER's profile (Players tab + his name), not
      // just on the market list.
      expect(openInFantasyRoutes, hasLength(1));
      final route = openInFantasyRoutes.single;
      expect(route.sport, 'Futsal');
      expect(route.season, '15');
      expect(route.initialTab, FantasyHubTab.players);
      expect(route.initialPlayerName, _name);
    });

    testWidgets('Open in Fantasy carries the OPENED player (a long, odd name '
        'survives untouched)', (tester) async {
      await pumpPage(tester,
          name: _longName, withDraft: false, fromOutsideHub: true);
      await emitAll(tester);
      await tester.tap(key('profile_open_in_fantasy'));
      await tester.pump();
      expect(openInFantasyRoutes.single.initialPlayerName, _longName);
    });
  });

  group('watchlist star', () {
    testWidgets('hidden when signed out', (tester) async {
      await pumpPage(tester, selfUid: '');
      await emitAll(tester);
      expect(key('fantasy_profile_ready'), findsOneWidget);
      expect(key('profile_star'), findsNothing);
    });

    testWidgets('signed in: reflects the watchlist and toggles it',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester);
      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
      await tester.tap(key('profile_star'));
      await tester.pump();
      expect(starWrites, [(_name, true)]);

      watchlist.add({_name});
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      await tester.tap(key('profile_star'));
      await tester.pump();
      expect(starWrites.last, (_name, false));
    });
  });

  testWidgets(
      'before any finalized week: "Points start" copy, dashes, and '
      'friendly empty Matches / Price', (tester) async {
    await pumpPage(tester);
    await emitAll(
      tester,
      totalsValue: null,
      historyValue: const {},
      changesValue: const {},
      weeksValue: const {},
    );
    expect(find.text('Points start after Gameweek 1'), findsOneWidget);
    expect(find.text('▲ \$0.5M this week'), findsNothing);
    expect(find.text('No change'), findsNothing);
    expect(find.text('0.0'), findsNothing);

    await openTab(tester, 'matches');
    expect(key('matches_empty'), findsOneWidget);
    await openTab(tester, 'price');
    expect(key('price_empty'), findsOneWidget);
    await openTab(tester, 'stats');
    expect(find.text('Points start after Gameweek 1'), findsOneWidget);
  });

  testWidgets(
      'weeks exist but nothing scored (never played / only voided): Stats '
      'says "No points scored yet", never the Gameweek 1 copy', (tester) async {
    await pumpPage(tester);
    await emitAll(tester, weeksValue: {
      1: const PlayerWeekStats(
          points: 0,
          played: false,
          gamesPlayed: 0,
          games: [],
          lines: {},
          voided: false),
      2: _week(0, voided: true),
    });
    // Overview has records: bars, not the GW1 copy.
    expect(find.text('Points start after Gameweek 1'), findsNothing);
    expect(key('form_bar_1'), findsOneWidget);

    await openTab(tester, 'stats');
    expect(find.text('No points scored yet'), findsOneWidget);
    expect(find.text('Points start after Gameweek 1'), findsNothing);
  });

  testWidgets(
      'a voided week reads "Week voided — 0" on Matches; a played '
      'week expands to its lines', (tester) async {
    await pumpPage(tester);
    await emitAll(tester, weeksValue: {
      1: _week(5, lines: const {
        'plays': ScoreSourceLine(count: 1, points: 2),
        'goals': ScoreSourceLine(count: 1, points: 3),
      }),
      2: _week(0, voided: true),
    });
    await openTab(tester, 'matches');
    expect(find.text('Week voided — 0'), findsOneWidget);
    expect(find.text('Goals ×1'), findsNothing);
    await tester.tap(key('match_row_1'));
    await tester.pumpAndSettle();
    expect(find.text('Goals ×1'), findsOneWidget);
  });

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
        '${mode.name} theme at 360×780: a long name wraps with no '
        'overflow on every tab', (tester) async {
      await pumpPage(tester,
          name: _longName, size: const Size(360, 780), themeMode: mode);
      await emitAll(
        tester,
        totalsValue: {
          _longName: const FantasyPlayerTotals(
              points: 128,
              ownershipPct: 100,
              formTenths: 105,
              ppgTenths: 107,
              games: 12),
        },
        historyValue: {
          for (var gw = 1; gw <= 8; gw++) gw: {_longName: 100 + gw},
        },
        changesValue: {
          for (var gw = 1; gw <= 8; gw++) gw: {_longName: gw.isEven ? 3 : -2},
        },
        weeks: _gameweeks(8),
        weeksValue: {
          for (var gw = 1; gw <= 8; gw++)
            gw: _week(gw * 3 - 4,
                voided: gw == 5,
                vs: 'Real Sociedad de Fútbol Internacional',
                lines: const {
                  'plays': ScoreSourceLine(count: 2, points: 4),
                  'goals': ScoreSourceLine(count: 3, points: 15),
                  'penMissed': ScoreSourceLine(count: 1, points: -2),
                }),
        },
        rostersValue: {
          'Kings': [_rosterRow(_longName, 'Kings', uid: 'u1', number: '99')],
        },
        gamesValue: [_game('11082026', 'Kings', 'Nimrod')],
      );
      expect(tester.takeException(), isNull);
      expect(find.text(_longName), findsOneWidget);
      final nameText = tester.widget<Text>(find.text(_longName));
      expect(nameText.overflow, isNot(TextOverflow.ellipsis));

      await tester.tap(key('form_bar_8'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tab in ['stats', 'matches', 'price']) {
        await openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab tab overflowed');
      }
      // An expanded Matches row (negative line in red) also fits.
      await openTab(tester, 'matches');
      await tester.ensureVisible(key('match_row_8'));
      await tester.pumpAndSettle();
      await tester.tap(key('match_row_8'));
      await tester.pumpAndSettle();
      expect(find.text('Penalty misses ×1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'light theme: status-bar icons are light over the hero and '
      'follow the theme once it scrolls away', (tester) async {
    // A short phone, so the Overview is tall enough to scroll the hero away.
    await pumpPage(tester, size: const Size(360, 600));
    await emitAll(tester);
    SystemUiOverlayStyle style() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find
            .byWidgetPredicate(
                (w) => w is AnnotatedRegion<SystemUiOverlayStyle>)
            .first)
        .value;
    void expectStatusBarOnly(SystemUiOverlayStyle s) {
      // Never touches the system navigation bar (the `.light`/`.dark`
      // presets force it black on Android < 15).
      expect(s.systemNavigationBarColor, isNull);
      expect(s.systemNavigationBarIconBrightness, isNull);
      expect(s.systemNavigationBarDividerColor, isNull);
      expect(s.statusBarColor, Colors.transparent);
    }

    expect(style().statusBarIconBrightness, Brightness.light);
    expect(style().statusBarBrightness, Brightness.dark);
    expectStatusBarOnly(style());

    await tester.drag(key('profile_scroll'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(style().statusBarIconBrightness, Brightness.dark);
    expect(style().statusBarBrightness, Brightness.light);
    expectStatusBarOnly(style());
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        '${mode.name} at 360 px: once content reaches the back/star row a '
        'solid bar backs both buttons (release report #3)', (tester) async {
      await pumpPage(tester, size: const Size(360, 600), themeMode: mode);
      await emitAll(tester);
      final bar = key('profile_pinned_bar');
      double opacity() => tester
          .widget<AnimatedOpacity>(
              find.descendant(of: bar, matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 0, reason: 'over the hero the buttons float');

      // Scroll until the hero's bottom edge (and the stat strip under it)
      // sits inside the button row, but has not reached the status bar.
      final heroBottom = tester.getBottomLeft(find.byType(FantasyProfileHero)).dy;
      final starBottom = tester.getBottomLeft(key('profile_star')).dy;
      await tester.drag(
          key('profile_scroll'), Offset(0, -(heroBottom - starBottom + 20)));
      await tester.pumpAndSettle();
      expect(opacity(), 1);

      // The bar spans the full width and reaches below both buttons, in the
      // theme's surface colour (no hard-coded fill).
      final barRect = tester.getRect(bar);
      expect(barRect.left, 0);
      expect(barRect.width, 360);
      expect(barRect.bottom,
          greaterThanOrEqualTo(tester.getRect(key('profile_star')).bottom));
      expect(barRect.bottom,
          greaterThanOrEqualTo(tester.getRect(key('profile_back')).bottom));
      final scheme = Theme.of(tester.element(bar)).colorScheme;
      final fill = tester.widget<DecoratedBox>(find.descendant(
          of: bar, matching: find.byKey(const ValueKey('profile_bar_fill'))));
      expect((fill.decoration as BoxDecoration).color, scheme.surface);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no underlined text anywhere on the profile (house rule)',
      (tester) async {
    await pumpPage(tester);
    await emitAll(tester, rostersValue: {
      'Ishtar': [_rosterRow(_name, 'Ishtar', uid: 'uid-42')],
    });
    for (final tab in ['overview', 'stats', 'matches', 'price']) {
      await openTab(tester, tab);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.style?.decoration ?? TextDecoration.none, TextDecoration.none,
            reason: '"${t.data}" must not be underlined');
      }
    }
  });

  // ── Live everywhere (Task 7) ─────────────────────────────────────────────
  //
  // While a gameweek is being played his week record and totals are the live
  // ones: the shared LIVE pill on the stat strip, the live week's form bar
  // hollow with a LIVE label, the bonus line "Bonus (provisional)".
  group('live everywhere (Task 7)', () {
    PlayerWeekStats liveWeek(int pts,
            {Map<String, ScoreSourceLine> lines = const {},
            bool bonusProvisional = false}) =>
        PlayerWeekStats(
          points: pts,
          played: true,
          gamesPlayed: 1,
          games: const [],
          lines: lines,
          voided: false,
          live: true,
          bonusProvisional: bonusProvisional,
        );

    const settledTwo = ScoreSourceLine(count: 1, points: 2);

    Map<int, PlayerWeekStats> weeksWithLive({bool provisional = true}) => {
          1: _week(2, lines: const {'plays': settledTwo}),
          2: _week(8, lines: const {
            'plays': settledTwo,
            'goals': ScoreSourceLine(count: 1, points: 6),
            'bonus': ScoreSourceLine(count: 3, points: 3),
          }),
          3: liveWeek(9,
              lines: const {
                'plays': settledTwo,
                'goals': ScoreSourceLine(count: 1, points: 6),
                'bonus': ScoreSourceLine(count: 1, points: 1),
              },
              bonusProvisional: provisional),
        };

    const liveTotals = {
      _name: FantasyPlayerTotals(
          points: 70,
          ownershipPct: 55,
          formTenths: 67,
          ppgTenths: 53,
          games: 13,
          live: true),
    };

    /// emitAll + fixed frames (the LIVE pill pulses: pumpAndSettle never
    /// returns while one is on screen).
    Future<void> emitLive(
      WidgetTester tester, {
      Map<String, FantasyPlayerTotals>? totalsValue = liveTotals,
      Map<int, PlayerWeekStats>? weeksValue,
    }) async {
      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open));
      gameweeks.add(_gameweeks(3));
      players.add(market);
      totals.add(totalsValue);
      history.add(const {
        1: {_name: 70},
        2: {_name: 70},
        3: {_name: 75},
      });
      changes.add(const {
        1: {'Other Def': 2},
        2: {_name: 5},
      });
      rosters.add({
        'Ishtar': [_rosterRow(_name, 'Ishtar', number: '3')],
      });
      games.add(const []);
      teams.add(const []);
      watchlist.add(const {});
      await tester.pump();
      weekStats.add(weeksValue ?? weeksWithLive());
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Finder stripPill() => find.descendant(
        of: key('profile_stat_strip'), matching: find.byType(FantasyLivePill));

    testWidgets('the stat strip carries the LIVE pill while the numbers are '
        'live', (tester) async {
      await pumpPage(tester);
      await emitLive(tester);
      expect(stripPill(), findsOneWidget);
      expect(find.text('LIVE'), findsWidgets);
      // The numbers themselves are the live ones, in place.
      expect(tester.widget<Text>(key('profile_total')).data, '70');
    });

    testWidgets('a live week record alone (totals official) also marks it',
        (tester) async {
      await pumpPage(tester);
      await emitLive(tester, totalsValue: const {
        _name: FantasyPlayerTotals(points: 64, formTenths: 67, games: 12),
      });
      expect(stripPill(), findsOneWidget);
    });

    testWidgets('no pill, no label, no hollow bar when nothing is live',
        (tester) async {
      await pumpPage(tester);
      await emitAll(tester);
      expect(stripPill(), findsNothing);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(key('form_bar_live_3'), findsNothing);
    });

    testWidgets('the pill goes when the week settles (the official numbers '
        'take over)', (tester) async {
      await pumpPage(tester);
      await emitLive(tester);
      expect(stripPill(), findsOneWidget);

      totals.add(const {
        _name: FantasyPlayerTotals(points: 70, formTenths: 67, games: 13),
      });
      weekStats.add({
        1: _week(2, lines: const {'plays': settledTwo}),
        2: _week(8, lines: const {'plays': settledTwo}),
        3: _week(9, lines: const {'plays': settledTwo}),
      });
      await frames(tester);
      expect(stripPill(), findsNothing);
      expect(key('form_bar_live_3'), findsNothing);
    });

    group('the form bars', () {
      BoxDecoration barDecoration(WidgetTester tester, int gw) =>
          tester.widget<Container>(key('form_bar_fill_$gw')).decoration!
              as BoxDecoration;

      testWidgets('the live week\'s bar is HOLLOW (outline only) with a '
          'LIVE label; the settled bars are solid', (tester) async {
        await pumpPage(tester);
        await emitLive(tester);

        final live = barDecoration(tester, 3);
        expect(live.color, isNull, reason: 'hollow: no fill');
        expect(live.border, isNotNull);
        expect((live.border! as Border).top.width, 2);
        for (final gw in [1, 2]) {
          final solid = barDecoration(tester, gw);
          expect(solid.color, isNotNull, reason: 'GW$gw is solid');
          expect(solid.border, isNull);
          expect(key('form_bar_live_$gw'), findsNothing);
        }
        expect(key('form_bar_live_3'), findsOneWidget);
        expect(tester.widget<Text>(key('form_bar_live_3')).data, 'LIVE');
        // The GW number is still there; its points are the live ones.
        expect(find.text('GW3'), findsOneWidget);
        expect(tester.widget<Text>(key('form_bar_value_3')).data, '9');
      });

      testWidgets('the hollow outline is the bar\'s own tone (the accent)',
          (tester) async {
        await pumpPage(tester);
        await emitLive(tester);
        final ctx = tester.element(key('form_bar_fill_3'));
        final live = barDecoration(tester, 3);
        expect((live.border! as Border).top.color, fantasyAccent(ctx));
        expect(barDecoration(tester, 2).color, fantasyAccent(ctx));
      });

      testWidgets('tapping the live bar still selects the week',
          (tester) async {
        await pumpPage(tester);
        await emitLive(tester);
        await tester.tap(key('form_bar_3'));
        await frames(tester);
        expect(key('week_breakdown'), findsOneWidget);
        expect(find.textContaining('GW3'), findsWidgets);
      });
    });

    group('the provisional bonus', () {
      testWidgets('the live week\'s breakdown reads "Bonus (provisional)", '
          'a settled week plain "Bonus"', (tester) async {
        await pumpPage(tester);
        await emitLive(tester);

        await tester.tap(key('form_bar_3'));
        await frames(tester);
        expect(find.text('Bonus (provisional)'), findsOneWidget);
        expect(find.text('Bonus'), findsNothing);

        await tester.tap(key('form_bar_2'));
        await frames(tester);
        expect(find.text('Bonus'), findsOneWidget);
        expect(find.text('Bonus (provisional)'), findsNothing);
      });

      testWidgets('a live week whose bonus is final reads plain "Bonus"',
          (tester) async {
        await pumpPage(tester);
        await emitLive(tester, weeksValue: weeksWithLive(provisional: false));
        await tester.tap(key('form_bar_3'));
        await frames(tester);
        expect(find.text('Bonus'), findsOneWidget);
        expect(find.text('Bonus (provisional)'), findsNothing);
      });

      testWidgets('the Stats tab\'s season bonus is flagged while a live '
          'bonus is in it', (tester) async {
        await pumpPage(tester);
        await emitLive(tester);
        await tester.tap(key('profile_tab_stats'));
        await frames(tester);
        expect(find.text('Bonus (provisional)'), findsOneWidget);
      });

      testWidgets('the Matches tab: the live week\'s row carries the pill '
          'and its expanded bonus line is provisional', (tester) async {
        await pumpPage(tester);
        await emitLive(tester);
        await tester.tap(key('profile_tab_matches'));
        await frames(tester);
        expect(
            find.descendant(
                of: key('match_row_3'), matching: find.byType(FantasyLivePill)),
            findsOneWidget);
        expect(
            find.descendant(
                of: key('match_row_2'), matching: find.byType(FantasyLivePill)),
            findsNothing);

        await tester.tap(key('match_row_3'));
        await frames(tester);
        expect(find.text('Bonus (provisional)'), findsOneWidget);
      });
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('360 px: the pill, the hollow bar and the labels never '
          'overflow — $mode', (tester) async {
        await pumpPage(tester, size: const Size(360, 780), themeMode: mode);
        await emitLive(tester);
        expect(tester.takeException(), isNull);
        final strip = tester.getRect(key('profile_stat_strip'));
        expect(strip.left, greaterThanOrEqualTo(0));
        expect(strip.right, lessThanOrEqualTo(360));
        await tester.tap(key('form_bar_3'));
        await frames(tester);
        for (final tab in ['stats', 'matches', 'price', 'overview']) {
          await tester.tap(key('profile_tab_$tab'));
          await frames(tester);
          expect(tester.takeException(), isNull, reason: tab);
        }
        await tester.drag(key('profile_scroll'), const Offset(0, -500));
        await frames(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
