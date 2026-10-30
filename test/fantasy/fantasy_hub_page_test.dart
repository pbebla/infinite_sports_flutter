// Fantasy round 3, Task 7 — every player tap inside the hub opens the fantasy
// player profile, proved with fake streams (no Firebase): News "View player"
// and the My Team court chip's new first action ("Player profile"; a locked
// court opens it directly) both go through the hub's ONE opener with the hub's
// shared draft, and "Open in Fantasy" (FantasyHubPage.initialPlayerName) opens
// that player's profile once the hub is ready — once, never before the reveal,
// never for a player who left the market.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded call of the hub's profile opener.
class _Opened {
  _Opened(this.sport, this.season, this.name, this.draft, this.outside);
  final String sport;
  final String season;
  final String name;
  final SquadDraftController? draft;
  final bool outside;
}

FantasyPlayer _player(String name, FantasyPosition pos, int price,
        {String team = 'Team A'}) =>
    FantasyPlayer(
        name: name,
        position: pos,
        priceTenths: price,
        eligible: true,
        teamName: team);

SquadPick _pick(String id, FantasyPosition pos, int price,
        {bool bench = false}) =>
    SquadPick(playerId: id, position: pos, priceTenths: price, bench: bench);

Map<String, Object?> _card(String name) => {
      'name': name,
      'position': 'ATT',
      'team': 'Team A',
      'priceTenths': 70,
      'gw': 3,
      'gwPoints': 9,
      'goals': 2,
      'assists': 1,
    };

void main() {
  late StreamController<FantasyConfigState?> config;
  late StreamController<List<FantasyPlayer>> players;
  late StreamController<FantasyManager?> manager;
  late StreamController<FantasySquad?> squad;
  late StreamController<FantasySquadAlert?> alert;
  late StreamController<List<FantasyNewsPost>> news;
  late StreamController<FantasyLeaderboards> boards;
  late StreamController<Map<String, FantasyManager>> managers;
  late StreamController<List<FantasyMiniLeague>> leagues;
  late StreamController<Map<int, FantasyDreamTeam>> dreams;
  late StreamController<Map<int, FantasySquad>> published;
  late StreamController<Map<int, FantasySquad>> history;
  late List<_Opened> opened;

  final market = [
    _player('Alan Keeper', FantasyPosition.gk, 50),
    _player('Dana Wall', FantasyPosition.def, 60),
    _player('Deb Rock', FantasyPosition.def, 55, team: 'Team B'),
    _player('Dom Stone', FantasyPosition.def, 50, team: 'Team C'),
    _player('Ava Striker', FantasyPosition.att, 70),
    _player('Axel Shot', FantasyPosition.att, 65, team: 'Team B'),
    _player('Ari Goal', FantasyPosition.att, 60, team: 'Team C'),
  ];

  final mySquad = FantasySquad(
    picks: [
      _pick('Alan Keeper', FantasyPosition.gk, 50),
      _pick('Dana Wall', FantasyPosition.def, 60),
      _pick('Deb Rock', FantasyPosition.def, 55),
      _pick('Ava Striker', FantasyPosition.att, 70),
      _pick('Axel Shot', FantasyPosition.att, 65),
      _pick('Dom Stone', FantasyPosition.def, 50, bench: true),
      _pick('Ari Goal', FantasyPosition.att, 60, bench: true),
    ],
    captainId: 'Ava Striker',
    viceId: 'Dana Wall',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {FantasyPrefs.walkthroughSeenKey: true});
    config = StreamController<FantasyConfigState?>.broadcast();
    players = StreamController<List<FantasyPlayer>>.broadcast();
    manager = StreamController<FantasyManager?>.broadcast();
    squad = StreamController<FantasySquad?>.broadcast();
    alert = StreamController<FantasySquadAlert?>.broadcast();
    news = StreamController<List<FantasyNewsPost>>.broadcast();
    boards = StreamController<FantasyLeaderboards>.broadcast();
    managers = StreamController<Map<String, FantasyManager>>.broadcast();
    leagues = StreamController<List<FantasyMiniLeague>>.broadcast();
    dreams = StreamController<Map<int, FantasyDreamTeam>>.broadcast();
    published = StreamController<Map<int, FantasySquad>>.broadcast();
    history = StreamController<Map<int, FantasySquad>>.broadcast();
    FantasyLeaderboardsTab.sessionScope = LeaderboardScope.overall;
    FantasyLeaderboardsTab.sessionWeek = null;
    DreamTeamCard.sessionWeek = null;
    opened = [];
  });

  tearDown(() {
    config.close();
    players.close();
    manager.close();
    squad.close();
    alert.close();
    news.close();
    boards.close();
    managers.close();
    leagues.close();
    dreams.close();
    published.close();
    history.close();
  });

  /// Lets the feeds land and the 300ms reveal fade finish. Never
  /// pumpAndSettle here: a tab still on its skeleton shimmer (News before its
  /// feed emits, the hub before the squad lands) animates forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpHub(
    WidgetTester tester, {
    FantasyHubTab tab = FantasyHubTab.myTeam,
    String? initialPlayerName,
    Size size = const Size(420, 1900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: FantasyHubPage(
        sport: 'Futsal',
        season: '15',
        initialTab: tab,
        initialPlayerName: initialPlayerName,
        configStates: config.stream,
        playersStates: players.stream,
        managerStates: manager.stream,
        squadStates: squad.stream,
        alertStates: alert.stream,
        gameweekStates: Stream.value(const []),
        chipHistoryFor: (weeks) => Stream.value(const {}),
        newsStates: news.stream,
        leaderboardsFeeds: FantasyLeaderboardsFeeds(
          leaderboardsStates: boards.stream,
          managersStates: managers.stream,
          miniLeaguesStates: leagues.stream,
          dreamTeamsStates: dreams.stream,
          loadProfiles: () async => {},
          selfUidOverride: 'me',
          viewerPublishedStates: published.stream,
          viewerHistoryStates: history.stream,
        ),
        profileOpener: (context,
            {required sport,
            required season,
            required playerName,
            draft,
            fromOutsideHub = false}) async {
          opened.add(_Opened(sport, season, playerName, draft, fromOutsideHub));
        },
      ),
    ));
    await tester.pump();
  }

  /// Every hub feed lands (the squad last so a test can hold the reveal).
  Future<void> land(
    WidgetTester tester, {
    FantasyLockOverride lock = FantasyLockOverride.open,
    bool withSquad = true,
  }) async {
    config.add(FantasyConfigState(
        config: FantasyConfig.futsalDefault(), lockOverride: lock));
    players.add(market);
    manager.add(
        const FantasyManager(teamName: 'Golden Boots', nameFlagged: false));
    alert.add(null);
    if (withSquad) squad.add(mySquad);
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  group('News "View player"', () {
    testWidgets('opens the profile with the hub\'s shared draft',
        (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.news);
      await land(tester);
      news.add(newsPostsFromNode({
        's': {
          'Title': 'Spotlight: Ava Striker',
          'At': 1,
          'Template': 'spotlight',
          'Players': [_card('Ava Striker')],
        },
      }));
      await tester.pumpAndSettle();

      await tester.tap(key('news_view_player_Ava Striker'));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      final call = opened.single;
      expect(call.sport, 'Futsal');
      expect(call.season, '15');
      expect(call.name, 'Ava Striker');
      expect(call.outside, isFalse);
      // The hub's own draft, already carrying the saved squad.
      expect(call.draft, isNotNull);
      expect(call.draft!.playerIds, contains('Ava Striker'));
    });

    testWidgets('compact rows (3+ players) open the profile too',
        (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.news);
      await land(tester);
      news.add(newsPostsFromNode({
        't': {
          'Title': 'Team of the Week is out',
          'At': 1,
          'Template': 'teamOfTheWeek',
          'Players': [
            _card('Alan Keeper'),
            _card('Dana Wall'),
            _card('Ava Striker'),
          ],
        },
      }));
      await tester.pumpAndSettle();
      await tester.tap(key('news_player_row_Dana Wall'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Dana Wall']);
    });

    testWidgets('a tagged player who left the market → a SnackBar, no '
        'profile', (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.news);
      await land(tester);
      news.add(newsPostsFromNode({
        's': {
          'Title': 'Spotlight: Gone Guy',
          'At': 1,
          'Template': 'spotlight',
          'Players': [_card('Gone Guy')],
        },
      }));
      await tester.pumpAndSettle();
      await tester.tap(key('news_view_player_Gone Guy'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text("That player isn't in the market anymore."),
          findsOneWidget);
    });
  });

  group('My Team court', () {
    testWidgets('the chip sheet\'s "Player profile" opens him with the same '
        'draft News uses', (tester) async {
      await pumpHub(tester, size: const Size(900, 1900));
      await land(tester);

      await tester.tap(key('squad_chip_Deb Rock'));
      await tester.pumpAndSettle();
      expect(key('action_profile'), findsOneWidget);
      await tester.tap(key('action_profile'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Deb Rock']);
      expect(opened.single.sport, 'Futsal');
      expect(opened.single.season, '15');
      expect(opened.single.outside, isFalse);

      // Same hub draft as the News route (identity, not equality).
      await tester.tap(find.text('News'));
      await settle(tester); // the News skeleton shimmers until its feed lands
      news.add(newsPostsFromNode({
        's': {
          'Title': 'Spotlight: Ava Striker',
          'At': 1,
          'Template': 'spotlight',
          'Players': [_card('Ava Striker')],
        },
      }));
      await tester.pumpAndSettle();
      await tester.tap(key('news_view_player_Ava Striker'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(2));
      expect(identical(opened[0].draft, opened[1].draft), isTrue);
      expect(opened[0].draft, isNotNull);
    });

    testWidgets('locked: a chip tap opens the profile straight away',
        (tester) async {
      await pumpHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      expect(key('locked_live_strip'), findsOneWidget);

      await tester.tap(key('squad_chip_Ava Striker'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Ava Striker']);
      expect(key('action_profile'), findsNothing);
      expect(key('action_make_captain'), findsNothing);
    });
  });

  group('Leaderboards tab (hub forwards its opener)', () {
    // Team of the Week: five market players (GK, 2 DEF, 2 ATT).
    Map<int, FantasyDreamTeam> teamOfTheWeek() => dreamTeamsFromNode({
          '1': {
            'Players': [
              {'name': 'Alan Keeper', 'position': 'GK', 'points': 9},
              {'name': 'Dana Wall', 'position': 'DEF', 'points': 7},
              {'name': 'Deb Rock', 'position': 'DEF', 'points': 6},
              {'name': 'Ava Striker', 'position': 'ATT', 'points': 8},
              {'name': 'Axel Shot', 'position': 'ATT', 'points': 5},
            ],
          },
        });

    /// Another manager's published squad: Ari Goal / Dom Stone are only here
    /// (never on the Team of the Week), so the chip tapped is unambiguous.
    final theirSquad = FantasySquad(
      picks: [
        _pick('Alan Keeper', FantasyPosition.gk, 50),
        _pick('Dana Wall', FantasyPosition.def, 60),
        _pick('Deb Rock', FantasyPosition.def, 55),
        _pick('Ava Striker', FantasyPosition.att, 70),
        _pick('Axel Shot', FantasyPosition.att, 65),
        _pick('Dom Stone', FantasyPosition.def, 50, bench: true),
        _pick('Ari Goal', FantasyPosition.att, 60, bench: true),
      ],
      captainId: 'Ava Striker',
      viceId: 'Dana Wall',
    );

    Future<void> landBoards(WidgetTester tester) async {
      boards.add(leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 50, 'rank': 1},
        },
      }));
      managers.add({
        'u1': const FantasyManager(teamName: 'Top Cats', nameFlagged: false),
      });
      leagues.add(const []);
      dreams.add(teamOfTheWeek());
      await settle(tester);
    }

    testWidgets('a Team of the Week chip opens that player via the hub '
        'opener, with the shared draft', (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.leaderboards);
      await land(tester);
      await landBoards(tester);
      expect(key('dream_team_card'), findsOneWidget);

      await tester.tap(key('squad_chip_Ava Striker'));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      final call = opened.single;
      expect(call.name, 'Ava Striker');
      expect(call.sport, 'Futsal');
      expect(call.season, '15');
      expect(call.outside, isFalse);
      expect(call.draft, isNotNull);
      expect(call.draft!.playerIds, contains('Ava Striker'));
    });

    testWidgets('row tap → manager squad viewer → a court chip opens that '
        'player via the same hub opener and draft', (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.leaderboards);
      await land(tester);
      await landBoards(tester);

      // Dream Team first, to compare the draft identity below.
      await tester.tap(key('squad_chip_Ava Striker'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Ava Striker']);

      // The default viewer builder (no squadViewerBuilder seam) is used.
      await tester.tap(key('leaderboard_row_u1'));
      await settle(tester); // the viewer shimmers until its feeds land
      published.add({1: theirSquad});
      history.add(const {});
      await settle(tester);
      expect(key('viewer_content'), findsOneWidget);

      await tester.tap(key('squad_chip_Ari Goal'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Ava Striker', 'Ari Goal']);
      expect(opened[1].sport, 'Futsal');
      expect(opened[1].season, '15');
      expect(opened[1].outside, isFalse);
      expect(opened[1].draft, isNotNull);
      expect(identical(opened[0].draft, opened[1].draft), isTrue);
    });
  });

  group('initialPlayerName ("Open in Fantasy")', () {
    testWidgets('opens that player\'s profile once the hub is ready — not '
        'before, and exactly once', (tester) async {
      // Rules tab: no tab-level feeds beyond what the hub already streams.
      await pumpHub(tester,
          tab: FantasyHubTab.rules, initialPlayerName: 'Ava Striker');
      // Hub still on its skeleton (no squad yet): nothing opens.
      await land(tester, withSquad: false);
      expect(key('hub'), findsNothing);
      expect(opened, isEmpty);

      squad.add(mySquad);
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      expect(opened, hasLength(1));
      expect(opened.single.name, 'Ava Striker');
      expect(opened.single.sport, 'Futsal');
      expect(opened.single.season, '15');
      expect(opened.single.outside, isFalse);
      expect(opened.single.draft, isNotNull);

      // Live re-emits and rebuilds never reopen it.
      players.add(market);
      squad.add(mySquad);
      manager.add(
          const FantasyManager(teamName: 'Golden Boots', nameFlagged: false));
      await settle(tester);
      expect(opened, hasLength(1));
    });

    testWidgets('a player who left the market → a SnackBar, nothing opens',
        (tester) async {
      await pumpHub(tester,
          tab: FantasyHubTab.rules, initialPlayerName: 'Gone Guy');
      await land(tester);
      expect(opened, isEmpty);
      expect(find.text("That player isn't in the market anymore."),
          findsOneWidget);
    });

    testWidgets('no initialPlayerName → nothing opens by itself',
        (tester) async {
      await pumpHub(tester, tab: FantasyHubTab.rules);
      await land(tester);
      expect(opened, isEmpty);
    });

    testWidgets('the first-open walkthrough comes first; the profile opens '
        'once the hub is revealed', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpHub(tester,
          tab: FantasyHubTab.rules, initialPlayerName: 'Ava Striker');
      await land(tester);
      expect(key('walkthrough'), findsOneWidget);
      expect(opened, isEmpty);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(key('hub'), findsOneWidget);
      expect(opened.map((o) => o.name), ['Ava Striker']);
    });
  });

  group('fantasyHubPageRoute', () {
    testWidgets('builds the hub page from a route (push taps and Open in '
        'Fantasy share it)', (tester) async {
      final route = fantasyHubPageRoute(fantasyRouteForPlayer(
          sport: 'Futsal', season: '15', playerName: 'Ava Striker'));
      late Widget page;
      await tester.pumpWidget(Builder(builder: (context) {
        page = route.builder(context);
        return const SizedBox();
      }));
      final hub = page as FantasyHubPage;
      expect(hub.sport, 'Futsal');
      expect(hub.season, '15');
      expect(hub.initialTab, FantasyHubTab.players);
      expect(hub.initialPlayerName, 'Ava Striker');
      expect(hub.focusPostId, isNull);
    });

    testWidgets('a news-push route keeps its post focus and names no player',
        (tester) async {
      final route = fantasyHubPageRoute(fantasyRouteFromPayload({
        'type': 'fantasy',
        'sport': 'Futsal',
        'season': '16',
        'postId': 'p1',
      })!);
      late Widget page;
      await tester.pumpWidget(Builder(builder: (context) {
        page = route.builder(context);
        return const SizedBox();
      }));
      final hub = page as FantasyHubPage;
      expect(hub.initialTab, FantasyHubTab.news);
      expect(hub.focusPostId, 'p1');
      expect(hub.initialPlayerName, isNull);
    });
  });

  group('the shared schedule wiring', () {
    testWidgets(
        'a Config error is logged and the showing hub keeps its last good '
        'config — never an unhandled stream error', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        await pumpHub(tester);
        await land(tester);
        expect(key('hub'), findsOneWidget);

        config.addError(StateError('permission-denied'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('hub'), findsOneWidget);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'),
          contains('FantasyHubPage: config feed failed: Bad state: '
              'permission-denied'));
    });
  });
}
