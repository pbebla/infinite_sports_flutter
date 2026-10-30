// Fantasy round 3, Task 9 — the Fantasy tab on the Infinite player profile,
// proved with fake streams (no Firebase):
//   * the pure join: which uids are a fantasy player and/or manager
//     (guests never; same name on another team never; ambiguous never),
//   * the manager standing (rank / movement / points) and the flagged-name
//     rule,
//   * the tab itself on ProfilePage: absent when neither, player-only,
//     manager-only, both; never on a limited (unlinked) profile; the tab
//     decision lands BEFORE the TabBar is built (no 2→3 flash) and a late
//     answer fades in without losing the selected tab; one fade reveal for
//     the content; "Open in Fantasy" lands on THAT player's profile inside
//     the hub; "View team" opens the real squad viewer (chips open the
//     fantasy player profile from outside the hub); no overflow in light AND
//     dark at 360 px.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_season_resolver.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_source.dart';
import 'package:infinite_sports_flutter/profile/profile_page.dart';

const _uid = 'u1';
const _name = 'Demsin Betvarda';
const _longName =
    'Maximiliano Alessandro Bartholomew-Featherstonehaugh Von Grünewald';
const _longTeam = 'The Unbelievably Long-Named Futsal Collective of Old Town';

FantasyPlayer _player(String name, FantasyPosition pos, int price,
        {String team = 'Ishtar', bool eligible = true}) =>
    FantasyPlayer(
      name: name,
      position: pos,
      priceTenths: price,
      eligible: eligible,
      teamName: team,
    );

TournamentPlayer _row(String name, String team, {String? uid}) =>
    TournamentPlayer(
      name: name,
      teamId: team,
      teamName: team,
      uid: uid,
      goals: 0,
      assists: 0,
      saves: 0,
      dpl: 0,
      cleanSheets: 0,
      yellowCards: 0,
      redCards: 0,
    );

SquadPick _pick(String id, FantasyPosition pos, int price,
        {bool bench = false}) =>
    SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

PlayerWeekStats _week(int pts, {bool voided = false}) => PlayerWeekStats(
      points: pts,
      played: true,
      gamesPlayed: 1,
      games: const [PlayerWeekGame(vs: 'Nimrod', goalsFor: 3, goalsAgainst: 2)],
      lines: const {},
      voided: voided,
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

/// One recorded call of the fantasy player-profile opener.
class _Opened {
  _Opened(this.sport, this.season, this.name, this.draft, this.outside);
  final String sport;
  final String season;
  final String name;
  final Object? draft;
  final bool outside;
}

void main() {
  // ── Pure logic ──────────────────────────────────────────────────────────
  group('fantasyProfileAccess', () {
    final market = [
      _player(_name, FantasyPosition.def, 75),
      _player('Guest Guy', FantasyPosition.att, 50,
          team: 'Nimrod', eligible: false),
      _player('Twin Name', FantasyPosition.att, 60, team: 'Nimrod'),
      _player('Twin Name', FantasyPosition.def, 60, team: 'Kings'),
    ];
    final linked = {
      'Ishtar': [_row(_name, 'Ishtar', uid: _uid)],
      'Nimrod': [
        _row('Guest Guy', 'Nimrod', uid: 'guest-uid'),
        _row('Twin Name', 'Nimrod', uid: 'twin-uid'),
      ],
      'Kings': [_row('Twin Name', 'Kings')],
    };
    const manager = FantasyManager(teamName: 'Top Cats', nameFlagged: false);

    FantasyProfileAccess? access(String uid,
            {FantasyManager? m,
            Map<String, List<TournamentPlayer>>? rosters}) =>
        fantasyProfileAccess(
          sport: 'Futsal',
          season: '15',
          uid: uid,
          players: market,
          rosters: rosters ?? linked,
          manager: m,
        );

    test('neither a fantasy player nor a manager → no Fantasy access', () {
      expect(access('stranger'), isNull);
    });

    test('a linked eligible market player is a fantasy player', () {
      final a = access(_uid)!;
      expect(a.player!.name, _name);
      expect(a.manager, isNull);
      expect(a.hasTab, isTrue);
      expect(a.sport, 'Futsal');
      expect(a.season, '15');
    });

    test('a manager entry alone is enough', () {
      final a = access('stranger', m: manager)!;
      expect(a.player, isNull);
      expect(a.manager, manager);
      expect(a.hasTab, isTrue);
    });

    test('both roles', () {
      final a = access(_uid, m: manager)!;
      expect(a.player!.name, _name);
      expect(a.manager, manager);
    });

    test('a guest (ineligible) is never a fantasy player', () {
      expect(access('guest-uid'), isNull);
    });

    test('same name on two teams: only the linked team\'s row links', () {
      final a = access('twin-uid')!;
      expect(a.player!.teamName, 'Nimrod');
    });

    test('ambiguous: one account on two fantasy rows → no player', () {
      final rosters = {
        'Nimrod': [_row('Twin Name', 'Nimrod', uid: 'twin-uid')],
        'Kings': [_row('Twin Name', 'Kings', uid: 'twin-uid')],
      };
      expect(access('twin-uid', rosters: rosters), isNull);
    });
  });

  group('managerStanding', () {
    final boards = leaderboardsFromNode({
      'Overall': {
        'a': {'points': 90, 'rank': 1},
        'u1': {'points': 80, 'rank': 2, 'movement': 3},
        'c': {'points': 70, 'rank': 3, 'movement': -1},
      },
    });

    test('rank, points and movement come from Overall/<uid>', () {
      final s = managerStanding(boards, 'u1');
      expect(s.rank, 2);
      expect(s.points, 80);
      expect(s.movement, 3);
      expect(s.ranked, isTrue);
      expect(managerStanding(boards, 'c').movement, -1);
    });

    test('no earlier week → movement null', () {
      final s = managerStanding(boards, 'a');
      expect(s.rank, 1);
      expect(s.movement, isNull);
    });

    test('a missing rank falls back to the list position', () {
      final b = leaderboardsFromNode({
        'Overall': {
          'x': {'points': 50},
          'y': {'points': 40},
        },
      });
      expect(managerStanding(b, 'y').rank, 2);
    });

    test('not on the board → not ranked (no made-up zeros)', () {
      final s = managerStanding(boards, 'nobody');
      expect(s.ranked, isFalse);
      expect(s.rank, isNull);
      expect(s.points, isNull);
      expect(managerStanding(FantasyLeaderboards.empty, 'u1').ranked, isFalse);
    });
  });

  group('visibleTeamName', () {
    test('a flagged team name is never visible', () {
      expect(
          visibleTeamName(_uid,
              const FantasyManager(teamName: 'Rude Name', nameFlagged: true)),
          isNull);
    });

    test('an unflagged name shows, trimmed', () {
      expect(
          visibleTeamName(_uid,
              const FantasyManager(teamName: ' Top Cats ', nameFlagged: false)),
          'Top Cats');
    });
  });

  group('resolveSeasonShared', () {
    setUp(FantasyProfileSource.clearSessionCaches);

    test('a "none" answer is remembered for a few minutes, then re-asked',
        () async {
      var calls = 0;
      var clock = DateTime(2026, 10, 29, 12);
      Future<FantasySeasonKey?> none() async {
        calls++;
        return null;
      }

      expect(
          await FantasyProfileSource.resolveSeasonShared(none,
              now: () => clock),
          isNull);
      expect(calls, 1);

      clock = clock.add(const Duration(minutes: 4));
      expect(
          await FantasyProfileSource.resolveSeasonShared(none,
              now: () => clock),
          isNull);
      expect(calls, 1); // trusted: no re-probe on every profile open

      clock = clock.add(const Duration(minutes: 2));
      await FantasyProfileSource.resolveSeasonShared(none, now: () => clock);
      expect(calls, 2); // asked again after the window
    });

    test('simultaneous opens share ONE in-flight resolution', () async {
      var calls = 0;
      final gate = Completer<FantasySeasonKey?>();
      Future<FantasySeasonKey?> slow() {
        calls++;
        return gate.future;
      }

      final a = FantasyProfileSource.resolveSeasonShared(slow);
      final b = FantasyProfileSource.resolveSeasonShared(slow);
      gate.complete((sport: 'Futsal', season: '15'));
      expect((await a)?.season, '15');
      expect((await b)?.season, '15');
      expect(calls, 1);
    });

    test(
        'a success is not cached here (the resolver memoizes it) and a '
        'throwing resolver counts as none', () async {
      var calls = 0;
      Future<FantasySeasonKey?> ok() async {
        calls++;
        return (sport: 'Futsal', season: '15');
      }

      await FantasyProfileSource.resolveSeasonShared(ok);
      await FantasyProfileSource.resolveSeasonShared(ok);
      expect(calls, 2);

      FantasyProfileSource.clearSessionCaches();
      expect(
          await FantasyProfileSource.resolveSeasonShared(
              () async => throw StateError('offline')),
          isNull);
    });
  });

  // ── The tab on ProfilePage ──────────────────────────────────────────────
  late StreamController<List<FantasyPlayer>> players;
  late StreamController<Map<String, List<TournamentPlayer>>> rosters;
  late StreamController<FantasyManager?> manager;
  late StreamController<FantasyConfigState?> config;
  late StreamController<List<Gameweek>> gameweeks;
  late StreamController<Map<String, FantasyPlayerTotals>?> totals;
  late StreamController<Map<int, Map<String, int>>> changes;
  late StreamController<Map<int, PlayerWeekStats>> weekStats;
  late StreamController<FantasyLeaderboards> boards;
  late StreamController<Map<int, FantasySquad>> published;
  late StreamController<Map<int, FantasySquad>> history;
  late StreamController<FantasySquad?> viewerSquad;
  late FantasySeasonKey? resolved;
  late List<FantasyHubRoute> routes;
  late List<_Opened> openedPlayers;
  late List<(String, List<int>)> requestedWeeks;

  final market = [
    _player(_name, FantasyPosition.def, 75),
    _player('Other Def', FantasyPosition.def, 60, team: 'Nimrod'),
    _player(_longName, FantasyPosition.att, 105, team: _longTeam),
    _player('Alan Keeper', FantasyPosition.gk, 50, team: 'Kings'),
    _player('Ari Goal', FantasyPosition.att, 60, team: 'Kings'),
  ];

  setUp(() {
    ProfilePage.clearCareerCache();
    FantasyProfileSource.clearSessionCaches();
    players = StreamController<List<FantasyPlayer>>.broadcast();
    rosters = StreamController<Map<String, List<TournamentPlayer>>>.broadcast();
    manager = StreamController<FantasyManager?>.broadcast();
    config = StreamController<FantasyConfigState?>.broadcast();
    gameweeks = StreamController<List<Gameweek>>.broadcast();
    totals = StreamController<Map<String, FantasyPlayerTotals>?>.broadcast();
    changes = StreamController<Map<int, Map<String, int>>>.broadcast();
    weekStats = StreamController<Map<int, PlayerWeekStats>>.broadcast();
    boards = StreamController<FantasyLeaderboards>.broadcast();
    published = StreamController<Map<int, FantasySquad>>.broadcast();
    history = StreamController<Map<int, FantasySquad>>.broadcast();
    viewerSquad = StreamController<FantasySquad?>.broadcast();
    resolved = (sport: 'Futsal', season: '15');
    routes = [];
    openedPlayers = [];
    requestedWeeks = [];
  });

  tearDown(() {
    for (final c in [
      players,
      rosters,
      manager,
      config,
      gameweeks,
      totals,
      changes,
      weekStats,
      boards,
      published,
      history,
      viewerSquad,
    ]) {
      c.close();
    }
  });

  FantasyProfileSeams seams({String self = 'me'}) => FantasyProfileSeams(
        resolveSeason: () async => resolved,
        playersStates: players.stream,
        rosterStates: rosters.stream,
        managerStates: manager.stream,
        configStates: config.stream,
        gameweekStates: gameweeks.stream,
        totalsStates: totals.stream,
        priceChangeStates: changes.stream,
        weekStatsFor: (name, weeks) {
          requestedWeeks.add((name, weeks));
          return weekStats.stream;
        },
        leaderboardsStates: boards.stream,
        selfUidOverride: self,
        openInFantasy: (context, route) => routes.add(route),
        viewerPublishedStates: published.stream,
        viewerHistoryStates: history.stream,
        viewerSquadStates: viewerSquad.stream,
        profileOpener: (context,
            {required sport,
            required season,
            required playerName,
            draft,
            fromOutsideHub = false}) async {
          openedPlayers
              .add(_Opened(sport, season, playerName, draft, fromOutsideHub));
        },
      );

  /// Lets feeds land and fades finish. Never pumpAndSettle while a skeleton
  /// shimmer can be on screen (it animates forever).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps the profile; [identity] (when held) gates phase 1 so a test can
  /// land the fantasy feeds before/after the page reveals.
  Future<Completer<int>> pumpProfile(
    WidgetTester tester, {
    String uid = _uid,
    String self = 'me',
    bool holdIdentity = false,
    Size size = const Size(420, 1000),
    ThemeMode themeMode = ThemeMode.light,
    FantasyProfileSeams? withSeams,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final identity = Completer<int>();
    if (!holdIdentity) identity.complete(1);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: themeMode,
      home: ProfilePage(
        uid: uid,
        loadOverride: () => identity.future,
        fantasySeams: withSeams ?? seams(self: self),
      ),
    ));
    await tester.pump(); // seams subscribed
    return identity;
  }

  /// The eligibility feeds land: [asPlayer] links [_uid] to his market row;
  /// [asManager] is the `Managers/<uid>` entry (null = not a manager).
  Future<void> landEligibility(
    WidgetTester tester, {
    bool asPlayer = false,
    FantasyManager? asManager,
    List<FantasyPlayer>? marketValue,
    String linkedTeam = 'Ishtar',
  }) async {
    players.add(marketValue ?? market);
    rosters.add({
      linkedTeam: [_row(_name, linkedTeam, uid: asPlayer ? _uid : null)],
      'Nimrod': [_row('Other Def', 'Nimrod')],
    });
    manager.add(asManager);
    await tester.pump();
  }

  /// The content feeds land (the schedule first, then his weekly records —
  /// as in the app).
  Future<void> landContent(
    WidgetTester tester, {
    bool player = false,
    bool managerRole = false,
    Map<String, FantasyPlayerTotals>? totalsValue = const {
      _name: FantasyPlayerTotals(
          points: 64,
          ownershipPct: 55,
          formTenths: 67,
          ppgTenths: 53,
          games: 12),
    },
    Map<int, Map<String, int>> changesValue = const {
      7: {_name: 5},
    },
    Map<int, PlayerWeekStats>? weeksValue,
    FantasyLeaderboards? boardsValue,
  }) async {
    config.add(FantasyConfigState(
        config: FantasyConfig.futsalDefault(),
        lockOverride: FantasyLockOverride.open));
    gameweeks.add(_gameweeks(8));
    await tester.pump();
    if (player) {
      totals.add(totalsValue);
      changes.add(changesValue);
      await tester.pump();
      weekStats.add(weeksValue ??
          {
            for (var gw = 1; gw <= 8; gw++) gw: _week(gw + 1),
          });
    }
    if (managerRole) {
      boards.add(boardsValue ??
          leaderboardsFromNode({
            'Overall': {
              'a': {'points': 90, 'rank': 1},
              _uid: {'points': 80, 'rank': 2, 'movement': 3},
            },
          }));
    }
    await tester.pump();
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder fantasyTab() => find.widgetWithText(Tab, 'Fantasy');

  Future<void> openFantasyTab(WidgetTester tester) async {
    await tester.tap(fantasyTab());
    await tester.pumpAndSettle();
  }

  const topCats = FantasyManager(teamName: 'Top Cats', nameFlagged: false);

  group('tab visibility', () {
    testWidgets('neither a fantasy player nor a manager: no Fantasy tab',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester);
      await settle(tester);

      expect(find.byType(Tab), findsNWidgets(2));
      expect(fantasyTab(), findsNothing);
      expect(requestedWeeks, isEmpty); // nothing else is subscribed for him
    });

    testWidgets('no current fantasy season: no Fantasy tab', (tester) async {
      resolved = null;
      await pumpProfile(tester);
      await settle(tester);

      expect(find.byType(Tab), findsNWidgets(2));
      expect(fantasyTab(), findsNothing);
    });

    testWidgets('a limited (unlinked) profile has no tab at all',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ProfilePage.limited(name: 'Some Player'),
      ));
      await tester.pump();

      expect(find.byType(TabBar), findsNothing);
      expect(fantasyTab(), findsNothing);
      expect(find.text("This player isn't linked to an account yet."),
          findsOneWidget);
    });

    testWidgets('failing eligibility feeds degrade to no tab, never a crash',
        (tester) async {
      await pumpProfile(
        tester,
        withSeams: FantasyProfileSeams(
          resolveSeason: () async => resolved,
          playersStates: Stream<List<FantasyPlayer>>.error(StateError('x')),
          rosterStates: Stream<Map<String, List<TournamentPlayer>>>.error(
              StateError('x')),
          managerStates: Stream<FantasyManager?>.error(StateError('x')),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(Tab), findsNWidgets(2));
    });

    testWidgets('player only: the tab shows, with the player section only',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);

      expect(find.byType(Tab), findsNWidgets(3));
      await openFantasyTab(tester);
      expect(key('fantasy_player_card'), findsOneWidget);
      expect(key('fantasy_manager_card'), findsNothing);
    });

    testWidgets('manager only: the tab shows, with the manager section only',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);

      expect(find.byType(Tab), findsNWidgets(3));
      await openFantasyTab(tester);
      expect(key('fantasy_manager_card'), findsOneWidget);
      expect(key('fantasy_player_card'), findsNothing);
    });

    testWidgets('both: the player section then the manager section',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true, asManager: topCats);
      await landContent(tester, player: true, managerRole: true);

      await openFantasyTab(tester);
      expect(key('fantasy_player_card'), findsOneWidget);
      expect(key('fantasy_manager_card'), findsOneWidget);
      expect(tester.getTopLeft(key('fantasy_player_card')).dy,
          lessThan(tester.getTopLeft(key('fantasy_manager_card')).dy));
    });

    testWidgets('a guest who is on a roster gets no tab', (tester) async {
      await pumpProfile(tester);
      await landEligibility(
        tester,
        asPlayer: true,
        marketValue: [
          _player(_name, FantasyPosition.def, 75, eligible: false),
        ],
      );
      await settle(tester);

      expect(fantasyTab(), findsNothing);
    });
  });

  group('no flash: the decision comes before the TabBar', () {
    testWidgets(
        'answered before the page reveals → the TabBar is built with three '
        'tabs from its very first frame', (tester) async {
      final identity = await pumpProfile(tester, holdIdentity: true);
      await landEligibility(tester, asPlayer: true);
      expect(find.byType(TabBar), findsNothing); // still on the skeleton

      identity.complete(1);
      await tester.pump(); // reveal frame
      expect(find.byType(Tab), findsNWidgets(3));
      expect(fantasyTab(), findsOneWidget);
    });

    testWidgets(
        'identity first, answer inside the grace window → the page waits, '
        'then builds the TabBar once, with three tabs', (tester) async {
      await pumpProfile(tester); // identity is ready at once
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TabBar), findsNothing); // still waiting on the answer

      await landEligibility(tester, asPlayer: true);
      await tester.pump();
      expect(find.byType(Tab), findsNWidgets(3)); // never a two-tab frame
      expect(fantasyTab(), findsOneWidget);
    });

    testWidgets(
        'answered AFTER the grace window → revealed with two tabs, the third '
        'fades in without losing the selected tab', (tester) async {
      final identity = await pumpProfile(tester, holdIdentity: true);
      identity.complete(1);
      // Eligibility never answers: the page waits at most the grace window.
      await tester
          .pump(kFantasyTabDecisionGrace + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(Tab), findsNWidgets(2));

      // The reader moves to Career before the answer arrives.
      await tester.tap(find.widgetWithText(Tab, 'Career'));
      await tester.pumpAndSettle();

      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);
      await tester.pumpAndSettle();

      expect(find.byType(Tab), findsNWidgets(3));
      expect(fantasyTab(), findsOneWidget);
      // Still on Career: the controller swap kept the index.
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.controller!.index, 1);
    });

    testWidgets(
        'a revisit decides at once from the session (no waiting on '
        'the feeds)', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);
      expect(fantasyTab(), findsOneWidget);

      // Second visit: the feeds never answer — only the session can decide.
      await tester.pumpWidget(const SizedBox());
      final identity = await pumpProfile(
        tester,
        holdIdentity: true,
        withSeams: FantasyProfileSeams(
          resolveSeason: () async => resolved,
          playersStates: StreamController<List<FantasyPlayer>>().stream,
          rosterStates:
              StreamController<Map<String, List<TournamentPlayer>>>().stream,
          managerStates: StreamController<FantasyManager?>().stream,
          configStates: StreamController<FantasyConfigState?>().stream,
          gameweekStates: StreamController<List<Gameweek>>().stream,
        ),
      );
      await tester.pump(); // season resolved, decision seeded
      identity.complete(1);
      await tester.pump();
      expect(find.byType(Tab), findsNWidgets(3));
    });

    testWidgets(
        'the share action hides on the Fantasy tab and returns on '
        'the others', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);

      expect(find.byTooltip('Share'), findsOneWidget);
      await openFantasyTab(tester);
      expect(find.byTooltip('Share'), findsNothing);
      await tester.tap(find.widgetWithText(Tab, 'Profile'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Share'), findsOneWidget);
    });
  });

  group('live changes', () {
    testWidgets(
        'the tab goes away live when he stops being a manager; the '
        'selection falls back to the last remaining tab', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);
      expect(key('fantasy_manager_card'), findsOneWidget);

      manager.add(null); // the Managers/<uid> entry is gone
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(Tab), findsNWidgets(2));
      expect(fantasyTab(), findsNothing);
      expect(key('fantasy_manager_card'), findsNothing);
      expect(tester.takeException(), isNull);
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.controller!.index, 1);
      expect(
          find.byTooltip('Share'), findsOneWidget); // back on a shareable tab
    });

    testWidgets('a name change reaches the open tab (live, no refresh)',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);
      expect(find.text('Top Cats'), findsOneWidget);

      manager.add(
          const FantasyManager(teamName: 'Night Owls', nameFlagged: false));
      await tester.pump(); // the broadcast event is delivered...
      await tester.pump(); // ...and the rebuild lands
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('Top Cats'), findsNothing);

      // The owner flags it: it disappears at once, never shown.
      manager
          .add(const FantasyManager(teamName: 'Night Owls', nameFlagged: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Night Owls'), findsNothing);
      expect(find.text('Unnamed team'), findsOneWidget);
    });
  });

  group('player section', () {
    testWidgets(
        'price + move, total pts, form, owned %, the last six weeks\' bars '
        'and Open in Fantasy', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);
      await openFantasyTab(tester);

      expect(requestedWeeks.last.$1, _name);
      expect(requestedWeeks.last.$2, [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(find.text('Ishtar · Defender'), findsOneWidget);
      expect(find.text('\$7.5M'), findsOneWidget);
      expect(find.text('▲ \$0.5M this week'), findsOneWidget);
      expect(find.text('64'), findsOneWidget); // total pts
      expect(find.text('6.7'), findsOneWidget); // form
      expect(find.text('55%'), findsOneWidget); // owned
      // Only the last six of the eight weeks.
      expect(key('form_bar_2'), findsNothing);
      for (final gw in [3, 4, 5, 6, 7, 8]) {
        expect(key('form_bar_$gw'), findsOneWidget);
      }
      expect(find.text('9'), findsOneWidget); // GW8's 8+1 on its bar
      expect(find.text('Open in Fantasy'), findsOneWidget);
    });

    testWidgets('Open in Fantasy lands on THIS player\'s profile in the hub',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true);
      await openFantasyTab(tester);

      await tester.tap(key('fantasy_open_in_fantasy'));
      await tester.pump();

      expect(routes, hasLength(1));
      expect(routes.single.sport, 'Futsal');
      expect(routes.single.season, '15');
      expect(routes.single.initialTab, FantasyHubTab.players);
      expect(routes.single.initialPlayerName, _name);
    });

    testWidgets('no finalized week yet: copy + dashes, never 0.0 / NaN / bars',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(
        tester,
        player: true,
        totalsValue: null,
        changesValue: const {},
        weeksValue: const {},
      );
      await openFantasyTab(tester);

      expect(find.text('Points start after Gameweek 1'), findsOneWidget);
      expect(key('profile_form_bars'), findsNothing);
      expect(find.text('0.0'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.text('—'), findsWidgets); // total / form / owned
      expect(key('fantasy_move'), findsNothing); // nothing before a reprice
      expect(find.text('Open in Fantasy'), findsOneWidget);
    });

    testWidgets('a player added mid-season: only the weeks he has bars for',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true, weeksValue: {
        7: _week(4),
        8: _week(6, voided: false),
      });
      await openFantasyTab(tester);

      expect(key('form_bar_7'), findsOneWidget);
      expect(key('form_bar_8'), findsOneWidget);
      expect(key('form_bar_6'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a voided week shows as Void, not as points', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true);
      await landContent(tester, player: true, weeksValue: {
        1: _week(5),
        2: _week(0, voided: true),
      });
      await openFantasyTab(tester);

      expect(find.text('Void'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
    });
  });

  group('manager section', () {
    testWidgets('team name, overall rank + movement + points, View team',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);

      expect(find.text('Top Cats'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('▲3'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('View team'), findsOneWidget);
    });

    testWidgets('a manager who dropped shows the red ▼ label', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(
        tester,
        managerRole: true,
        boardsValue: leaderboardsFromNode({
          'Overall': {
            _uid: {'points': 12, 'rank': 9, 'movement': -2},
          },
        }),
      );
      await openFantasyTab(tester);

      expect(find.text('#9'), findsOneWidget);
      expect(find.text('▼2'), findsOneWidget);
    });

    testWidgets('no ranking yet: copy, not zeros', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester,
          managerRole: true, boardsValue: FantasyLeaderboards.empty);
      await openFantasyTab(tester);

      expect(find.text('Top Cats'), findsOneWidget);
      expect(find.text('Ranking starts after Gameweek 1'), findsOneWidget);
      expect(find.text('#0'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('View team'), findsOneWidget);
    });

    testWidgets(
        'a FLAGGED team name never shows (anywhere, incl. the viewer '
        'title)', (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester,
          asManager:
              const FantasyManager(teamName: 'Rude Name', nameFlagged: true));
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);

      expect(find.textContaining('Rude'), findsNothing);
      expect(find.text('Unnamed team'), findsOneWidget);

      await tester.tap(key('fantasy_view_team'));
      await tester.pump();
      await settle(tester);
      expect(find.textContaining('Rude'), findsNothing);
      expect(find.text('Unnamed manager'), findsOneWidget); // viewer title
    });

    testWidgets(
        'View team opens the real squad viewer for that manager; '
        'a chip opens the fantasy player profile from outside the hub',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);

      await tester.tap(key('fantasy_view_team'));
      await tester.pump();
      await settle(tester);
      expect(find.byType(ManagerSquadViewerPage), findsOneWidget);
      final viewer = tester
          .widget<ManagerSquadViewerPage>(find.byType(ManagerSquadViewerPage));
      expect(viewer.uid, _uid);
      expect(viewer.title, 'Top Cats');
      expect(viewer.isSelf, isFalse);
      expect(viewer.sport, 'Futsal');
      expect(viewer.season, '15');

      published.add({
        1: FantasySquad(
          picks: [
            _pick('Alan Keeper', FantasyPosition.gk, 50),
            _pick(_name, FantasyPosition.def, 75),
            _pick('Other Def', FantasyPosition.def, 60),
            _pick('Ari Goal', FantasyPosition.att, 60),
            _pick(_longName, FantasyPosition.att, 105),
            _pick('Bench Def', FantasyPosition.def, 50, bench: true),
            _pick('Bench Att', FantasyPosition.att, 50, bench: true),
          ],
          captainId: 'Ari Goal',
          viceId: _name,
        ),
      });
      history.add(const {});
      await settle(tester);
      expect(key('viewer_content'), findsOneWidget);

      await tester.tap(key('squad_chip_Ari Goal'));
      await tester.pumpAndSettle();
      expect(openedPlayers, hasLength(1));
      expect(openedPlayers.single.name, 'Ari Goal');
      expect(openedPlayers.single.sport, 'Futsal');
      expect(openedPlayers.single.season, '15');
      expect(openedPlayers.single.outside, isTrue);
      expect(openedPlayers.single.draft, isNull);
    });

    testWidgets('on his OWN profile View team opens the live squad (isSelf)',
        (tester) async {
      await pumpProfile(tester, self: _uid);
      await landEligibility(tester, asManager: topCats);
      await landContent(tester, managerRole: true);
      await openFantasyTab(tester);

      await tester.tap(key('fantasy_view_team'));
      await tester.pump();
      published.add(const {});
      history.add(const {});
      viewerSquad.add(null);
      await settle(tester);

      final viewer = tester
          .widget<ManagerSquadViewerPage>(find.byType(ManagerSquadViewerPage));
      expect(viewer.isSelf, isTrue);
      expect(key('viewer_week_now'), findsOneWidget);
    });
  });

  group('reveal', () {
    testWidgets('the content waits on a skeleton, then ONE fade shows it',
        (tester) async {
      await pumpProfile(tester);
      await landEligibility(tester, asPlayer: true, asManager: topCats);

      // The tab is there (decided) but its feeds haven't landed.
      await tester.tap(fantasyTab());
      await settle(tester); // never pumpAndSettle: the skeleton shimmers
      expect(key('fantasy_tab_skeleton'), findsOneWidget);
      expect(key('fantasy_tab_ready'), findsNothing);
      expect(key('fantasy_player_card'), findsNothing);

      // Part of it lands: still no piecemeal content.
      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open));
      gameweeks.add(_gameweeks(8));
      await tester.pump();
      totals.add(const {});
      changes.add(const {});
      await tester.pump();
      expect(key('fantasy_tab_ready'), findsNothing);

      weekStats.add(const {});
      boards.add(FantasyLeaderboards.empty);
      await tester.pump();
      await settle(tester);
      expect(key('fantasy_tab_ready'), findsOneWidget);
      expect(key('fantasy_tab_skeleton'), findsNothing);
      expect(key('fantasy_player_card'), findsOneWidget);
      expect(key('fantasy_manager_card'), findsOneWidget);
    });
  });

  group('phone width, light and dark', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('no overflow at 360 px with long names ($mode)',
          (tester) async {
        await pumpProfile(
          tester,
          size: const Size(360, 780),
          themeMode: mode,
        );
        await landEligibility(
          tester,
          asPlayer: true,
          asManager: const FantasyManager(
              teamName: '$_longTeam $_longTeam', nameFlagged: false),
          linkedTeam: _longTeam,
          marketValue: [
            _player(_name, FantasyPosition.def, 75, team: _longTeam),
            ...market.skip(1),
          ],
        );
        await landContent(tester,
            player: true,
            managerRole: true,
            changesValue: const {
              7: {_name: -12}
            });
        await openFantasyTab(tester);

        expect(tester.takeException(), isNull);
        expect(key('fantasy_player_card'), findsOneWidget);
        // Names wrap — never ellipsized, never underlined.
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.overflow, isNot(TextOverflow.ellipsis));
          expect(t.style?.decoration, isNot(TextDecoration.underline));
        }
        await tester.drag(key('fantasy_tab_ready'), const Offset(0, -600));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(key('fantasy_manager_card'), findsOneWidget);
      });
    }
  });
}
