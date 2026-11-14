// Fantasy round 3, Task 7 — every player tap inside the hub opens the fantasy
// player profile, proved with fake streams (no Firebase): News "View player"
// and the My Team court chip's new first action ("Player profile"; a locked
// court opens it directly) both go through the hub's ONE opener with the hub's
// shared draft, and "Open in Fantasy" (FantasyHubPage.initialPlayerName) opens
// that player's profile once the hub is ready — once, never before the reveal,
// never for a player who left the market.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_prefs.dart';
import 'package:infinite_sports_flutter/fantasy/data/per_week_stream.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/access_pay_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboards_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/my_team_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/news_tab.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_preview.dart';
import 'package:infinite_sports_flutter/registration/payment_links.dart';
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
  late StreamController<Map<int, HistoryWeek>> history;
  late StreamController<FantasyAccessState> access;
  late StreamController<SaleBaselineState> sale;
  late StreamController<TransferStateView?> transfer;
  late int transferListens;
  late StreamController<Map<int, Map<String, int>>> priceHistory;
  late List<_Opened> opened;

  // Paid-access seam recorders.
  late int checkoutCalls;
  late List<Uri> launched;
  late List<({FantasyAccessMethod method, double amount, String note})> claims;
  final checkoutUri = Uri.parse('https://checkout.stripe.com/c/pay/cs_1');

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
    history = StreamController<Map<int, HistoryWeek>>.broadcast();
    access = StreamController<FantasyAccessState>.broadcast();
    sale = StreamController<SaleBaselineState>.broadcast();
    transferListens = 0;
    transfer = StreamController<TransferStateView?>.broadcast(
        onListen: () => transferListens++);
    priceHistory = StreamController<Map<int, Map<String, int>>>.broadcast();
    checkoutCalls = 0;
    launched = [];
    claims = [];
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
    access.close();
    sale.close();
    transfer.close();
    priceHistory.close();
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
    Stream<List<Gameweek>>? gameweekStates,
    Stream<Map<int, ChipHistoryEntry>> Function(List<int> weeks)?
        chipHistoryFor,
    Stream<Set<int>>? voidedWeeksStates,
    DateTime Function()? nowUtc,
    Brightness brightness = Brightness.light,
    // false = nobody signed in (the transfer feed is never subscribed).
    bool signedIn = true,
    // The locked week's feeds (live everywhere, Task 5) — null = the real
    // ones (which, with no Firebase app, answer "nothing" at once).
    Stream<FantasyLiveState>? liveStates,
    Stream<LiveSquad?>? liveSquadStates,
    Stream<HistoryWeek?> Function(int week)? historyWeekFor,
    Stream<FantasySquad?> Function(int week)? publishedPicksFor,
    Stream<OverallStanding?>? overallStandingStates,
    Stream<Map<String, FantasyPlayerTotals>?>? playerTotalsStates,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
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
        gameweekStates: gameweekStates ?? Stream.value(const []),
        chipHistoryFor: chipHistoryFor ?? (weeks) => Stream.value(const {}),
        voidedWeeksStates: voidedWeeksStates ?? Stream.value(const <int>{}),
        nowUtc: nowUtc,
        accessStates: access.stream,
        saleBaselineStates: sale.stream,
        transferStateStates: transfer.stream,
        signedInUid: () => signedIn ? 'me' : null,
        liveStates: liveStates,
        liveSquadStates: liveSquadStates,
        historyWeekFor: historyWeekFor,
        publishedPicksFor: publishedPicksFor,
        overallStandingStates: overallStandingStates,
        playerTotalsStates: playerTotalsStates,
        priceHistoryStates: priceHistory.stream,
        createCheckoutUrl: () async {
          checkoutCalls++;
          return checkoutUri;
        },
        launchExternal: (uri) async {
          launched.add(uri);
          return true;
        },
        submitAccessClaim: (method, amount, note) async {
          claims.add((method: method, amount: amount, note: note));
        },
        displayName: () => 'Golden Fan',
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
    FantasyAccessConfig accessConfig = FantasyAccessConfig.free,
    bool withManager = true,
    bool withAccess = true,
    FantasyAccessState accessState = FantasyAccessState.none,
    // A user with no squad yet: the feed answers null (withSquad: false
    // keeps the feed SILENT to hold the reveal).
    bool squadNull = false,
    // The transfer feed joins the reveal gate: it answers "no node yet"
    // (null) unless a test holds it back to prove the wait.
    bool withTransfer = true,
  }) async {
    config.add(FantasyConfigState(
        config: FantasyConfig.futsalDefault(),
        lockOverride: lock,
        access: accessConfig));
    players.add(market);
    manager.add(withManager
        ? const FantasyManager(teamName: 'Golden Boots', nameFlagged: false)
        : null);
    alert.add(null);
    if (withAccess) access.add(accessState);
    if (squadNull) {
      squad.add(null);
    } else if (withSquad) {
      squad.add(mySquad);
    }
    if (withTransfer) transfer.add(null);
    await settle(tester);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  // Opus audit item 3: the hub's reveal gate waits on the chip history —
  // it must neither open listeners for weeks that can't have History yet
  // nor make a revisit wait on the network.
  group('chip history (reveal gate)', () {
    // GW n locks Oct 4 + 7(n-1), 22:00 UTC; "now" (Oct 17) sits in GW3.
    final gws = [
      for (var n = 1; n <= 5; n++)
        Gameweek(
          number: n,
          date: '10${(4 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];
    DateTime now() => DateTime.utc(2026, 10, 17, 12);

    testWidgets('only weeks up to the current gameweek get a listener — '
        'future weeks none', (tester) async {
      final requested = <List<int>>[];
      await pumpHub(
        tester,
        gameweekStates: Stream.value(gws),
        nowUtc: now,
        chipHistoryFor: (weeks) {
          requested.add(weeks);
          return Stream.value(const {});
        },
      );
      await land(tester);
      expect(requested, [
        [1, 2, 3]
      ]);
      expect(key('hub'), findsOneWidget);
    });

    testWidgets('a revisit reveals at once from the session seed — before '
        'any History week answers', (tester) async {
      // The REAL per-week wiring (FantasyService.watchChipHistoryFor's
      // shape) with fake History nodes and a test-owned session cache.
      final cache = <String, Map<int, ChipHistoryEntry>>{};
      late Map<int, StreamController<Object?>> history;
      final listened = <int>[];
      Stream<Map<int, ChipHistoryEntry>> chips(List<int> weeks) =>
          perWeekStream<ChipHistoryEntry>(
            weeks: weeks,
            cache: cache,
            cacheKey: 'Fantasy/Futsal/15|me',
            watchWeek: (w) {
              listened.add(w);
              final c = StreamController<Object?>();
              history[w] = c;
              addTearDown(c.close);
              return c.stream;
            },
            parse: chipHistoryEntryFromNode,
          );

      // Visit 1: the gate waits for every History week, then reveals.
      history = {};
      await pumpHub(tester,
          gameweekStates: Stream.value(gws), nowUtc: now, chipHistoryFor: chips);
      await land(tester);
      expect(key('hub'), findsNothing); // History hasn't answered yet
      expect(listened..sort(), [1, 2, 3]); // never GW4 / GW5
      history[1]!.add({'chip': 'tripleCaptain'});
      history[2]!.add(null);
      history[3]!.add(null);
      await settle(tester);
      expect(key('hub'), findsOneWidget);

      // Visit 2: History is silent (offline / slow) — the seed reveals.
      await tester.pumpWidget(const SizedBox());
      history = {};
      await pumpHub(tester,
          gameweekStates: Stream.value(gws), nowUtc: now, chipHistoryFor: chips);
      await land(tester);
      expect(key('hub'), findsOneWidget);
      final usedBadge = find.descendant(
          of: key('chip_count_tripleCaptain'), matching: find.byType(Text));
      expect(tester.widget<Text>(usedBadge).data, 'Used');
    });

    // Opus audit item 4: the chip row reads Voided/<gw> like the server.
    // Final fix wave: a failed History read is UNKNOWN, not "nothing used" —
    // a Wildcard / Free Hit spent earlier this set would look "1 left" and
    // could be armed again (the lock voids a replay and charges every
    // transfer). It holds arming of those two; Triple Captain / Bench Boost
    // keep today's behaviour. A loaded-empty History is known.
    group('chip history unknown vs empty', () {
      TransferStateView counted() => TransferStateView(
          free: 2,
          countFromGw: 3, // "now" (Oct 17) edits GW3
          countFrom: [for (final p in mySquad.picks) p.playerId]);

      Future<void> tapChip(WidgetTester tester, String id) async {
        final chip = key('fantasy_chip_$id');
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip, warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      testWidgets('a History read error holds Wildcard / Free Hit; Triple '
          'Captain still arms; the hub still reveals', (tester) async {
        await pumpHub(
          tester,
          gameweekStates: Stream.value(gws),
          nowUtc: now,
          chipHistoryFor: (weeks) => Stream.error(StateError('denied')),
        );
        await land(tester, withTransfer: false);
        transfer.add(counted());
        await settle(tester);
        expect(key('hub'), findsOneWidget);
        expect(find.text('Checking your transfers…'), findsNWidgets(2));

        await tapChip(tester, 'wildcard');
        await tapChip(tester, 'freeHit');
        expect(find.byType(AlertDialog), findsNothing);
        await tapChip(tester, 'tripleCaptain');
        expect(key('chip_active_tripleCaptain'), findsOneWidget);
      });

      testWidgets('a loaded-EMPTY History is known: Wildcard asks as usual',
          (tester) async {
        await pumpHub(tester, gameweekStates: Stream.value(gws), nowUtc: now);
        await land(tester, withTransfer: false);
        transfer.add(counted());
        await settle(tester);
        expect(find.text('Checking your transfers…'), findsNothing);
        await tapChip(tester, 'wildcard');
        expect(find.text('Play your Wildcard?'), findsOneWidget);
      });
    });

    testWidgets('the Voided feed joins the reveal gate and refunds a chip '
        'History still shows as spent', (tester) async {
      final voided = StreamController<Set<int>>();
      addTearDown(voided.close);
      await pumpHub(
        tester,
        gameweekStates: Stream.value(gws),
        nowUtc: now,
        chipHistoryFor: (weeks) =>
            Stream.value({1: const ChipHistoryEntry(chip: 'tripleCaptain')}),
        voidedWeeksStates: voided.stream,
      );
      await land(tester);
      expect(key('hub'), findsNothing); // the refund source hasn't answered

      voided.add({1}); // the owner voided GW1 (not mirrored into History yet)
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      final badge = find.descendant(
          of: key('chip_count_tripleCaptain'), matching: find.byType(Text));
      expect(tester.widget<Text>(badge).data, '1 left');
    });
  });

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

    /// Taps one of the Leaderboards tab's scope segments by its label.
    Future<void> selectScope(WidgetTester tester, String label) async {
      await tester.tap(find.descendant(
          of: key('leaderboard_scope'), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

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
      // The card lives in its own "Team of the week" segment (not above the
      // Overall list).
      expect(key('dream_team_card'), findsNothing);
      await selectScope(tester, kTeamOfWeekSegmentLabel);
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
      await selectScope(tester, kTeamOfWeekSegmentLabel);
      await tester.tap(key('squad_chip_Ava Striker'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Ava Striker']);

      // Back on Overall for the manager rows.
      await selectScope(tester, 'Overall');

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

  group('badge push (spec 2026-10-30 §4)', () {
    testWidgets('opens Leaderboards on Overall — where your row and its badge '
        'count are — even after a Gameweek session scope', (tester) async {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.gameweek;
      final route = fantasyRouteFromPayload({
        'type': 'fantasy',
        'sport': 'Futsal',
        'season': '15',
        'badge': 'captainGenius_gw3',
      })!;
      await pumpHub(tester, tab: route.initialTab);
      await land(tester);
      expect(key('hub'), findsOneWidget);
      expect(FantasyLeaderboardsTab.sessionScope, LeaderboardScope.overall);
      expect(find.byType(FantasyLeaderboardsTab), findsOneWidget);
    });

    testWidgets('any other entry keeps the session scope', (tester) async {
      FantasyLeaderboardsTab.sessionScope = LeaderboardScope.gameweek;
      await pumpHub(tester);
      await land(tester);
      expect(FantasyLeaderboardsTab.sessionScope, LeaderboardScope.gameweek);
    });
  });

  // FPL selling (spec §4): the own `Baselines/<uid>` feed prices the shared
  // draft — and never holds the single fade reveal.
  group('sale baseline feed', () {
    // GW n locks Oct 4 + 7(n-1), 22:00 UTC; "now" (Oct 17) edits GW3.
    final gws = [
      for (var n = 1; n <= 5; n++)
        Gameweek(
          number: n,
          date: '10${(4 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];

    SaleBaselineState baseline(int forGw) => SaleBaselineState(
          baseline: SaleBaseline(
              forGw: forGw,
              prices: const {'Ava Striker': 60, 'Dana Wall': 60},
              realizedTenths: 5),
          loaded: true,
        );

    /// The hub revealed WITHOUT any baseline answer, and its shared draft
    /// (reached through "Open in Fantasy", which hands the opener the draft).
    ///
    /// The transfer feed (part of the reveal gate) answers with
    /// [transferState] (null = no node), or fails when [transferError].
    Future<SquadDraftController> hubDraft(WidgetTester tester,
        {FantasyLockOverride lock = FantasyLockOverride.auto,
        DateTime? now,
        TransferStateView? transferState,
        bool transferError = false}) async {
      final at = now ?? DateTime.utc(2026, 10, 17, 12);
      await pumpHub(tester,
          tab: FantasyHubTab.rules,
          initialPlayerName: 'Ava Striker',
          gameweekStates: Stream.value(gws),
          nowUtc: () => at);
      await land(tester, lock: lock, withTransfer: false);
      if (transferError) {
        transfer.addError(StateError('network'));
      } else {
        transfer.add(transferState);
      }
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      return opened.single.draft!;
    }

    testWidgets('never holds the reveal; its emits price the shared draft',
        (tester) async {
      final draft = await hubDraft(tester);
      expect(draft.moneyReady, isFalse); // nothing answered yet

      sale.add(baseline(3));
      await settle(tester);
      expect(draft.moneyReady, isTrue);
      expect(draft.realizedTenths, 5);
      // Ava was saved at 70 but is held at her baseline 60.
      expect(draft.spentTenths, 410 - 10);
      expect(draft.availableTenths, 505);
      // Today's prices come from the live market: 60 -> 70 sells 65.
      expect(draft.sellPriceOf('Ava Striker'), 65);
      players.add([
        for (final p in market)
          p.name == 'Ava Striker'
              ? _player('Ava Striker', FantasyPosition.att, 80)
              : p,
      ]);
      await settle(tester);
      expect(draft.sellPriceOf('Ava Striker'), 70);

      // A baseline for another week is not this week's money.
      sale.add(baseline(2));
      await settle(tester);
      expect(draft.moneyReady, isFalse);

      // No node = a first squad: ready, nothing held, nothing sold.
      sale.add(const SaleBaselineState(loaded: true));
      await settle(tester);
      expect(draft.moneyReady, isTrue);
      expect(draft.realizedTenths, 0);
      // Every pick is NEW now, charged like the server: at least
      // min(today, last week). Ava was saved at 70 and is 80 today; with
      // no price history the floor is today's 80...
      expect(draft.spentTenths, 420);
      // ...and once PriceHistory/2 (the week before the edited GW3) says
      // she was 70, the floor is 70.
      priceHistory.add(const {
        2: {'Ava Striker': 70},
        1: {'Ava Striker': 90},
      });
      await settle(tester);
      expect(draft.spentTenths, 410);
    });

    testWidgets('a price history read error is logged and keeps the last '
        'known history (error ≠ fact)', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        final draft = await hubDraft(tester);
        // A first squad: every pick NEW. Ava was saved at 70; last week she
        // was 70; today she is 80 → her floor is min(80, 70) = 70.
        sale.add(const SaleBaselineState(loaded: true));
        priceHistory.add(const {
          2: {'Ava Striker': 70},
        });
        final dearAva = [
          for (final p in market)
            p.name == 'Ava Striker'
                ? _player('Ava Striker', FantasyPosition.att, 80)
                : p,
        ];
        players.add(dearAva);
        await settle(tester);
        expect(draft.spentTenths, 410);

        priceHistory.addError(StateError('network'));
        await settle(tester);
        // The next feed (a market re-emit) still prices her from the last
        // known history — a wiped history would charge today's 80 (420).
        players.add([...dearAva]);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('hub'), findsOneWidget);
        expect(draft.moneyReady, isTrue);
        expect(draft.spentTenths, 410);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'),
          contains('FantasyHubPage: price history feed failed: Bad state: '
              'network'));
    });

    testWidgets('a read error before any value: degraded, never ready — the '
        'hub still shows and the failure is logged', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        final draft = await hubDraft(tester);
        sale.addError(StateError('permission-denied'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('hub'), findsOneWidget);
        expect(draft.moneyReady, isFalse);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'),
          contains('FantasyHubPage: sale baseline feed failed: Bad state: '
              'permission-denied'));
    });

    testWidgets('a known baseline survives a later feed error (error ≠ fact)',
        (tester) async {
      final draft = await hubDraft(tester);
      sale.add(baseline(3));
      await settle(tester);
      expect(draft.moneyReady, isTrue);
      sale.addError(StateError('network'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(draft.moneyReady, isTrue);
      expect(draft.realizedTenths, 5);
    });

    testWidgets('the open override past the clock deadline: the stored '
        'baseline is still this week\'s money', (tester) async {
      // Oct 19: GW3's lock (Oct 18 22:00) has passed by the clock, but the
      // owner's open override stands the lock sweep down.
      final draft = await hubDraft(tester,
          lock: FantasyLockOverride.open, now: DateTime.utc(2026, 10, 19, 12));
      sale.add(baseline(3));
      await settle(tester);
      expect(draft.moneyReady, isTrue);
    });

    // Plan 2026-11-03: the own `TransferState/<uid>` feed rides the same
    // wiring and the SAME edited week as the sale baseline — and never holds
    // the reveal either.
    group('transfer state feed', () {
      final held = [for (final p in mySquad.picks) p.playerId];
      TransferStateView view(int countFromGw) => TransferStateView(
          free: 2, countFromGw: countFromGw, countFrom: List.of(held));

      // The owner's standing rule: no pop-ins after the single reveal — the
      // transfers line and the chips' first-team caption are final when the
      // hub appears, so the feed's first answer (or error) is waited for.
      testWidgets('the reveal waits for the transfer feed: its first answer '
          'ends the wait', (tester) async {
        await pumpHub(tester);
        await land(tester, withTransfer: false);
        expect(key('hub'), findsNothing);

        transfer.add(null);
        await settle(tester);
        expect(key('hub'), findsOneWidget);
      });

      testWidgets('its first ERROR ends the wait too — a failed feed never '
          'holds the screen', (tester) async {
        await pumpHub(tester);
        await land(tester, withTransfer: false);
        expect(key('hub'), findsNothing);

        transfer.addError(StateError('permission-denied'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('hub'), findsOneWidget);
      });

      testWidgets('signed out: counts as loaded at once — nothing to wait '
          'for', (tester) async {
        await pumpHub(tester, signedIn: false);
        await land(tester, withTransfer: false);
        expect(key('hub'), findsOneWidget);
      });

      testWidgets('an absent node (null) answers: a first team',
          (tester) async {
        final draft = await hubDraft(tester);
        expect(draft.transferPreview.kind, TransferPreviewKind.firstTeam);
      });

      testWidgets('a baseline for the week being edited is counted — the '
          'same editingGw the sale context uses', (tester) async {
        final draft = await hubDraft(tester, transferState: view(3)); // GW3
        expect(draft.transferPreview.kind, TransferPreviewKind.counted);
        expect(draft.transferPreview.used, 0);

        draft.removePlayer('Ari Goal');
        draft.addPlayer(_player('Ari New', FantasyPosition.att, 60));
        await settle(tester);
        expect(draft.transferPreview.used, 1);

        // Another week's baseline is not this week's count.
        transfer.add(view(2));
        await settle(tester);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);
        transfer.add(view(3));
        await settle(tester);
        expect(draft.transferPreview.kind, TransferPreviewKind.counted);
      });

      testWidgets('a read error: logged, not ready — never a first team — '
          'and the hub still shows', (tester) async {
        final logs = <String>[];
        final original = debugPrint;
        debugPrint =
            (String? message, {int? wrapWidth}) => logs.add(message ?? '');
        try {
          final draft = await hubDraft(tester, transferState: view(3));
          expect(draft.transferPreview.kind, TransferPreviewKind.counted);

          transfer.addError(StateError('permission-denied'));
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(key('hub'), findsOneWidget);
          expect(draft.transferPreview.kind, TransferPreviewKind.notReady);
        } finally {
          debugPrint = original;
        }
        expect(logs.join('\n'),
            contains('FantasyHubPage: transfer state feed failed: Bad state: '
                'permission-denied'));
      });

      // The copy says "updating…" — so something must actually retry. The
      // service's stream ends after an error, so the hub re-subscribes.
      testWidgets('after a failed read the feed is re-subscribed every 30 s '
          'until it answers; data stops the retries', (tester) async {
        final draft = await hubDraft(tester, transferError: true);
        expect(transferListens, 1);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);

        await tester.pump(const Duration(seconds: 29));
        expect(transferListens, 1, reason: 'not before 30 s');
        await tester.pump(const Duration(seconds: 1));
        expect(transferListens, 2);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);

        // Still failing: a fresh failure schedules the next try.
        transfer.addError(StateError('still down'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));
        expect(transferListens, 3);

        // It answers: counted, and no more retries.
        transfer.add(view(3));
        await tester.pump();
        expect(draft.transferPreview.kind, TransferPreviewKind.counted);
        await tester.pump(const Duration(minutes: 5));
        expect(transferListens, 3);
        expect(tester.takeException(), isNull);
      });

      testWidgets('leaving the hub cancels the pending retry', (tester) async {
        await hubDraft(tester, transferError: true);
        expect(transferListens, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 5));
        expect(transferListens, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('signed out: nothing to retry', (tester) async {
        await pumpHub(tester, signedIn: false);
        await land(tester, withTransfer: false);
        await tester.pump(const Duration(minutes: 5));
        expect(transferListens, 0);
      });

      testWidgets('a read error before any answer is notReady too — and the '
          'hub still reveals', (tester) async {
        final draft = await hubDraft(tester, transferError: true);
        expect(tester.takeException(), isNull);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);
      });

      testWidgets('with no signed-in user the feed is never subscribed: '
          'the signed-out null is "no user", not "no node"', (tester) async {
        // The real signed-out feed streams a lone null — it must not read as
        // an answered, absent node (a free first team).
        await pumpHub(tester,
            tab: FantasyHubTab.rules,
            initialPlayerName: 'Ava Striker',
            gameweekStates: Stream.value(gws),
            nowUtc: () => DateTime.utc(2026, 10, 17, 12),
            signedIn: false);
        await land(tester, withTransfer: false);
        final draft = opened.single.draft!;
        expect(tester.takeException(), isNull);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);
        // Whatever the stream emits is not listened to.
        transfer.add(null);
        await settle(tester);
        expect(draft.transferPreview.kind, TransferPreviewKind.notReady);
      });
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


  // Paid access (spec 2026-11-01 §5/§6): the hub's gate, live.
  group('paid access gate', () {
    final pass = accessConfigFromNode({
      'Mode': 'pass',
      'AmountDollars': 10,
      'Methods': {'Venmo': true, 'Zelle': false, 'Card': true},
    });
    FantasyAccessState status(String s) =>
        accessStateFromNode({'Status': s, 'Via': 'venmo'});

    testWidgets('free mode: no card — the name step shows as today',
        (tester) async {
      await pumpHub(tester);
      await land(tester, withManager: false, squadNull: true);
      expect(key('hub'), findsOneWidget);
      expect(key('my_team_name_prompt'), findsOneWidget);
      expect(key('access_pay_card'), findsNothing);
      expect(key('my_team_pay_gate'), findsNothing);
    });

    testWidgets('pass + no record: the pay card replaces the name step',
        (tester) async {
      await pumpHub(tester);
      await land(tester,
          accessConfig: pass, withManager: false, squadNull: true);
      expect(key('hub'), findsOneWidget);
      expect(key('my_team_pay_gate'), findsOneWidget);
      expect(key('access_pay_card'), findsOneWidget);
      expect(key('access_pay_card_card'), findsOneWidget);
      expect(find.text('Pay with card'), findsOneWidget);
      expect(key('access_pay_card_venmo'), findsOneWidget);
      expect(key('my_team_name_prompt'), findsNothing);
      expect(find.text('Name your team'), findsNothing);
      expect(find.text('Join Infinite Fantasy'), findsOneWidget);
    });

    testWidgets('pass + pending: the waiting copy', (tester) async {
      await pumpHub(tester);
      await land(tester,
          accessConfig: pass,
          withManager: false,
          squadNull: true,
          accessState: status('pending'));
      expect(key('access_pay_card_pending'), findsOneWidget);
      expect(find.text(kAccessPendingText), findsOneWidget);
      expect(key('my_team_name_prompt'), findsNothing);
    });

    testWidgets('pass + active: the normal name step, no card',
        (tester) async {
      await pumpHub(tester);
      await land(tester,
          accessConfig: pass,
          withManager: false,
          squadNull: true,
          accessState: status('active'));
      expect(key('my_team_name_prompt'), findsOneWidget);
      expect(key('access_pay_card'), findsNothing);
    });

    testWidgets('an existing manager without access (revoked): the card '
        'above a READ-ONLY court — no Save, no budget bar, chips inert, '
        'profiles still open', (tester) async {
      await pumpHub(tester);
      await land(tester, accessConfig: pass, accessState: status('revoked'));
      expect(key('hub'), findsOneWidget);
      expect(key('access_pay_card'), findsOneWidget);
      expect(key('access_pay_card_revoked'), findsOneWidget);
      expect(key('my_team_ready'), findsOneWidget);
      expect(key('squad_save'), findsNothing);
      expect(key('budget_bar'), findsNothing);
      expect(key('locked_live_strip'), findsNothing);
      // The card sits ABOVE the court.
      final card = tester.getRect(key('access_pay_card'));
      final chip = tester.getRect(key('squad_chip_Deb Rock'));
      expect(card.bottom, lessThanOrEqualTo(chip.top));
      // A filled chip opens the profile (viewing is never locked); the
      // chip action sheet (edit affordances) never opens.
      await tester.tap(key('squad_chip_Deb Rock'));
      await tester.pumpAndSettle();
      expect(opened.map((o) => o.name), ['Deb Rock']);
      expect(key('action_make_captain'), findsNothing);
    });

    testWidgets('the gate flips live: paying reveals the editable court; a '
        'revoke locks it again — nothing polls', (tester) async {
      await pumpHub(tester);
      await land(tester, accessConfig: pass);
      expect(key('access_pay_card'), findsOneWidget);
      expect(key('squad_save'), findsNothing);

      access.add(status('active')); // the server activated the pass
      await settle(tester);
      expect(key('access_pay_card'), findsNothing);
      expect(key('squad_save'), findsOneWidget);
      expect(key('budget_bar'), findsOneWidget);

      access.add(status('revoked')); // a refund
      await settle(tester);
      expect(key('access_pay_card_revoked'), findsOneWidget);
      expect(key('squad_save'), findsNothing);
    });

    testWidgets('the reveal waits for the Access feed (single fade — the '
        'card never pops in after the hub shows)', (tester) async {
      await pumpHub(tester);
      await land(tester, accessConfig: pass, withAccess: false);
      expect(key('hub'), findsNothing);
      access.add(FantasyAccessState.none);
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      expect(key('access_pay_card'), findsOneWidget);
    });

    testWidgets('an Access read error before any value: the hub reveals '
        'with the retry line, never the pay methods; Try again '
        're-subscribes', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        await pumpHub(tester);
        await land(tester,
            accessConfig: pass, withManager: false, squadNull: true,
            withAccess: false);
        access.addError(StateError('permission-denied'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('hub'), findsOneWidget);
        expect(key('access_pay_card_degraded'), findsOneWidget);
        expect(key('access_pay_card_card'), findsNothing);
        expect(key('access_pay_card_venmo'), findsNothing);

        await tester.tap(key('access_pay_card_retry_access'));
        await settle(tester);
        access.add(FantasyAccessState.none); // the re-subscribe answers
        await settle(tester);
        expect(key('access_pay_card_degraded'), findsNothing);
        expect(key('access_pay_card_venmo'), findsOneWidget);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'),
          contains('FantasyHubPage: access feed failed: Bad state: '
              'permission-denied'));
    });

    testWidgets('a known record survives a later feed error (error ≠ fact)',
        (tester) async {
      await pumpHub(tester);
      await land(tester, accessConfig: pass, accessState: status('active'));
      expect(key('squad_save'), findsOneWidget);
      access.addError(StateError('network'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(key('squad_save'), findsOneWidget);
      expect(key('access_pay_card'), findsNothing);
    });

    testWidgets('card tap → the callable seam + the launch seam; Venmo → '
        'the shared link; I sent it → the claim seam with the hub\'s '
        'sport/season/name in the note', (tester) async {
      await pumpHub(tester);
      await land(tester,
          accessConfig: pass, withManager: false, squadNull: true);

      await tester.tap(key('access_pay_card_card'));
      await tester.pumpAndSettle();
      expect(checkoutCalls, 1);
      expect(launched, [checkoutUri]);
      expect(find.text(kAccessBrowserText), findsOneWidget);

      await tester.tap(key('access_pay_card_venmo'));
      await tester.pumpAndSettle();
      expect(launched.last,
          venmoPayUri(amount: 10, note: 'Fantasy Futsal S15 Golden Fan'));

      await tester.tap(key('access_pay_card_sent'));
      await tester.pumpAndSettle();
      expect(claims, hasLength(1));
      expect(claims.single.method, FantasyAccessMethod.venmo);
      expect(claims.single.amount, 10.0);
      expect(claims.single.note, 'Fantasy Futsal S15 Golden Fan');
      expect(key('access_pay_card_pending'), findsOneWidget);
    });

    testWidgets('a push of type fantasyAccess opens the hub on My Team',
        (tester) async {
      final route = fantasyRouteFromPayload({
        'type': 'fantasyAccess',
        'sport': 'Futsal',
        'season': '15',
      })!;
      expect(route.initialTab, FantasyHubTab.myTeam);
      await pumpHub(tester, tab: route.initialTab);
      await land(tester,
          accessConfig: pass, withManager: false, squadNull: true);
      expect(key('access_pay_card'), findsOneWidget);
    });

    // Owner rule: 360 px in BOTH themes — the card above the read-only
    // court, scrolled through, no overflow.
    for (final brightness in Brightness.values) {
      testWidgets('360 px: the card above the read-only court fits — '
          '$brightness', (tester) async {
        await pumpHub(tester,
            size: const Size(360, 1600), brightness: brightness);
        await land(tester,
            accessConfig: pass, accessState: status('revoked'));
        expect(tester.takeException(), isNull);
        await tester.tap(key('access_pay_card_venmo'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final k in [
          'access_pay_card',
          'access_pay_card_revoked',
          'access_pay_card_card',
          'access_pay_card_venmo',
          'access_pay_card_sent',
          'squad_chip_Deb Rock',
        ]) {
          final r = tester.getRect(key(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: k);
          expect(r.right, lessThanOrEqualTo(360), reason: k);
        }
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.style?.decoration ?? TextDecoration.none,
              TextDecoration.none,
              reason: t.data);
        }
      });
    }
  });

  // Live everywhere, Task 5: the locked My Team. The hub subscribes to the
  // locked week's four small streams ONLY while a week is locked, joins them
  // to the single reveal gate (bounded at 2 s) so the first painted frame
  // already carries live numbers, and hands the resolved view to the court.
  group('locked week (live everywhere)', () {
    // GW1..3 lock Oct 3 / 10 / 17 at 22:00 UTC; "now" (Oct 17, 23:00) is the
    // lock day of GW3: it is the locked week. The owner's `locked` override
    // is what the builder reads (it keeps its own real clock).
    final gws = [
      for (var n = 1; n <= 3; n++)
        Gameweek(
          number: n,
          date: '10${(3 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 3 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];
    DateTime lockDay() => DateTime.utc(2026, 10, 17, 23);

    late StreamController<FantasyLiveState> liveFeed;
    late StreamController<LiveSquad?> liveSquadFeed;
    late StreamController<OverallStanding?> overallFeed;
    late Map<int, StreamController<HistoryWeek?>> historyFeeds;
    late Map<int, StreamController<FantasySquad?>> publishedFeeds;
    late int liveListens;
    late List<int> historyRequests;
    late List<int> publishedRequests;

    setUp(() {
      liveListens = 0;
      historyRequests = [];
      publishedRequests = [];
      liveFeed = StreamController<FantasyLiveState>.broadcast(
          onListen: () => liveListens++);
      liveSquadFeed = StreamController<LiveSquad?>.broadcast();
      overallFeed = StreamController<OverallStanding?>.broadcast();
      historyFeeds = {};
      publishedFeeds = {};
    });

    tearDown(() {
      liveFeed.close();
      liveSquadFeed.close();
      overallFeed.close();
      for (final c in [...historyFeeds.values, ...publishedFeeds.values]) {
        c.close();
      }
    });

    Stream<HistoryWeek?> historyFor(int week) {
      historyRequests.add(week);
      return (historyFeeds[week] ??= StreamController<HistoryWeek?>.broadcast())
          .stream;
    }

    Stream<FantasySquad?> publishedFor(int week) {
      publishedRequests.add(week);
      return (publishedFeeds[week] ??=
              StreamController<FantasySquad?>.broadcast())
          .stream;
    }

    Future<void> pumpLockedHub(
      WidgetTester tester, {
      Size size = const Size(420, 1900),
      Brightness brightness = Brightness.light,
      Stream<Set<int>>? voided,
      DateTime Function()? now,
    }) =>
        pumpHub(tester,
            size: size,
            brightness: brightness,
            gameweekStates: Stream.value(gws),
            nowUtc: now ?? lockDay,
            voidedWeeksStates: voided,
            liveStates: liveFeed.stream,
            liveSquadStates: liveSquadFeed.stream,
            historyWeekFor: historyFor,
            publishedPicksFor: publishedFor,
            overallStandingStates: overallFeed.stream);

    LiveSquad liveSquad({int week = 34}) => LiveSquad(
          totalTenths: week * 10 + 5,
          week: week,
          slots: const [
            LiveSlot(playerId: 'Alan Keeper', countedTenths: 40, multiplier: 1),
            LiveSlot(playerId: 'Dana Wall', countedTenths: 30, multiplier: 1),
            LiveSlot(playerId: 'Deb Rock', countedTenths: 0, multiplier: 1),
            LiveSlot(
                playerId: 'Ava Striker', countedTenths: 160, multiplier: 2),
            LiveSlot(playerId: 'Axel Shot', countedTenths: 70, multiplier: 1),
            LiveSlot(playerId: 'Dom Stone', countedTenths: 25, multiplier: 1),
            LiveSlot(playerId: 'Ari Goal', countedTenths: 0, multiplier: 1),
          ],
        );

    FantasyLiveState liveState({LiveState state = LiveState.live, int gw = 3}) =>
        FantasyLiveState(
          meta: LiveMeta(gw: gw, state: state),
          board: const {
            'me': LiveBoardRow(o: 90, r: 5, m: 2, w: 34, wr: 1),
          },
          players: {
            for (final e in {
              'Alan Keeper': LivePlayerStatus.done,
              'Dana Wall': LivePlayerStatus.done,
              'Deb Rock': LivePlayerStatus.pending,
              'Ava Striker': LivePlayerStatus.live,
              'Axel Shot': LivePlayerStatus.out,
              'Dom Stone': LivePlayerStatus.done,
              'Ari Goal': LivePlayerStatus.pending,
            }.entries)
              e.key: LivePlayer(
                  pts: 0,
                  st: e.value,
                  total: 0,
                  form: 0,
                  ppg: 0,
                  games: 0,
                  own: 0),
          },
        );

    HistoryWeek settledWeek({FantasySquad? squad}) => HistoryWeek(
            totalTenths: 345,
            squad: squad ?? mySquad,
            slots: const [
              LiveSlot(
                  playerId: 'Alan Keeper', countedTenths: 40, multiplier: 1),
              LiveSlot(
                  playerId: 'Ava Striker', countedTenths: 160, multiplier: 2),
              LiveSlot(
                  playerId: 'Dom Stone', countedTenths: 25, multiplier: 1),
            ]);

    /// The own feeds answer: the live squad, History not written yet, the
    /// squad that was LOCKED (PublishedPicks — [locked], default the same
    /// squad Squads holds) and the Overall rank.
    void answerOwn({bool withLive = true, FantasySquad? locked}) {
      if (withLive) liveFeed.add(liveState());
      liveSquadFeed.add(liveSquad());
      historyFeeds[3]?.add(null);
      publishedFeeds[3]?.add(locked ?? mySquad);
      overallFeed.add(const OverallStanding(rank: 5, movement: 2));
    }

    Finder strip() => key('locked_live_strip');

    testWidgets('live: the strip, the pill and the chips all show live '
        'numbers; nothing else subscribed for other weeks', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      expect(historyRequests, [3]);
      answerOwn();
      await settle(tester);

      expect(key('hub'), findsOneWidget);
      expect(find.text('34 pts · #5 ▲2'), findsOneWidget);
      // The pill beside the banner's live line and the strip's own.
      expect(find.byType(FantasyLivePill), findsNWidgets(2));
      Finder inChip(String id, String text) => find.descendant(
          of: key('squad_chip_$id'), matching: find.text(text));
      expect(inChip('Ava Striker', '16 pts · live'), findsOneWidget);
      expect(inChip('Alan Keeper', '4 pts'), findsOneWidget);
      expect(inChip('Deb Rock', 'Not started'), findsOneWidget);
      expect(inChip('Axel Shot', 'Out'), findsOneWidget);
      expect(inChip('Dom Stone', '2.5 pts'), findsOneWidget);
      // The captain's nameplate carries the real multiplier.
      expect(find.text('ATT · \$7.0M · ×2'), findsOneWidget);
      // Tapping a locked chip still opens the profile.
      await tester.tap(key('squad_chip_Ava Striker'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(opened.map((o) => o.name), ['Ava Striker']);
    });

    testWidgets('live: the hub banner says "GW{n} live · {W} pts · #{R}" with '
        'the pill; no squad this week = the banner unchanged; the tombstone '
        'takes the line away', (tester) async {
      Finder inBanner(Finder f) =>
          find.descendant(of: find.byType(FantasyBanner), matching: f);

      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      answerOwn();
      await settle(tester);
      expect(inBanner(find.text('GW3 live · 34 pts · #5')), findsOneWidget);
      expect(inBanner(find.byType(FantasyLivePill)), findsOneWidget);

      // A moving score changes the line in place.
      liveFeed.add(FantasyLiveState(
        meta: const LiveMeta(gw: 3, state: LiveState.live),
        board: const {'me': LiveBoardRow(o: 93, r: 4, m: 3, w: 37, wr: 1)},
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(inBanner(find.text('GW3 live · 37 pts · #4')), findsOneWidget);

      // The week settles: the banner is the plain one again.
      liveFeed.add(liveState(state: LiveState.settled));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(inBanner(find.textContaining('live ·')), findsNothing);
      expect(inBanner(find.byType(FantasyLivePill)), findsNothing);
    });

    testWidgets('live, but he has no squad scored this week (no W): the '
        'banner is exactly as before', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      answerOwn(withLive: false);
      liveFeed.add(FantasyLiveState(
        meta: const LiveMeta(gw: 3, state: LiveState.live),
        board: const {'me': LiveBoardRow(o: 90, r: 5)},
      ));
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(FantasyBanner),
              matching: find.byType(FantasyLivePill)),
          findsNothing);
      expect(find.textContaining('GW3 live'), findsNothing);
    });

    testWidgets('live arriving 500 ms late: the reveal waits for it, and the '
        'FIRST painted frame of the hub already has live numbers — never '
        '"waiting for kickoff" flipping to live', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      // Every own feed but the live one has answered.
      answerOwn(withLive: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(key('hub'), findsNothing);
      expect(key('skeleton'), findsOneWidget);

      var sawHub = false;
      var elapsed = 100;
      while (elapsed < 1200) {
        if (elapsed == 500) liveFeed.add(liveState());
        await tester.pump(const Duration(milliseconds: 20));
        elapsed += 20;
        // Not one frame — before or after the reveal — shows the default.
        expect(find.text('Locked · waiting for kickoff'), findsNothing,
            reason: 'frame at $elapsed ms');
        if (key('hub').evaluate().isNotEmpty) {
          if (!sawHub) {
            // The first frame the hub exists in the tree.
            expect(find.text('34 pts · #5 ▲2'), findsOneWidget,
                reason: 'the first revealed frame already has live numbers');
            // …and so does the banner: it never pops its live line in later.
            expect(find.text('GW3 live · 34 pts · #5'), findsOneWidget,
                reason: 'the banner joins the same single reveal');
            expect(elapsed, greaterThanOrEqualTo(500));
          }
          sawHub = true;
        }
      }
      expect(sawHub, isTrue);
    });

    testWidgets('live silent for 2 s: the hub reveals without it (just "Locked": '
        'not a claim about kickoff), and a late live lands in place', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      answerOwn(withLive: false);
      await tester.pump(const Duration(milliseconds: 900));
      expect(key('hub'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      // The load is incomplete (live has not answered): never "waiting for
      // kickoff" — only what is certain.
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);

      liveFeed.add(liveState());
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('34 pts · #5 ▲2'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);
    });

    testWidgets('settled: Final, the official rank, History points on the '
        'chips, no pill', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      // finalize left a tombstone (overlays nothing); History is written.
      liveFeed.add(liveState(state: LiveState.settled));
      liveSquadFeed.add(null);
      historyFeeds[3]!.add(settledWeek());
      publishedFeeds[3]!.add(null);
      overallFeed.add(const OverallStanding(rank: 4, movement: 1));
      await settle(tester);

      expect(find.text('Final · 34 pts · #4'), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(
          find.descendant(
              of: key('squad_chip_Ava Striker'), matching: find.text('16 pts')),
          findsOneWidget);
      expect(
          find.descendant(
              of: key('squad_chip_Dom Stone'), matching: find.text('2.5 pts')),
          findsOneWidget);
    });

    testWidgets('the hand-over: live → tombstone updates in place, the pill '
        'disappears, the numbers become the official ones', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      answerOwn();
      await tester.pump(const Duration(milliseconds: 50));
      await settle(tester);
      expect(find.byType(FantasyLivePill), findsNWidgets(2)); // banner + strip

      historyFeeds[3]!.add(settledWeek());
      overallFeed.add(const OverallStanding(rank: 4));
      liveSquadFeed.add(null);
      liveFeed.add(liveState(state: LiveState.settled));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Final · 34 pts · #4'), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
    });

    testWidgets('a voided week reads Voided from the Voided set (the live '
        'record says "not voided")', (tester) async {
      await pumpLockedHub(tester, voided: Stream.value(const {3}));
      await land(tester, lock: FantasyLockOverride.locked);
      answerOwn();
      await settle(tester);
      expect(find.text('Voided · this week counts 0'), findsOneWidget);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(find.textContaining(' pts'), findsNothing);
    });

    testWidgets('an invalid squad: 0 pts, "this week didn\'t count"',
        (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      liveFeed.add(liveState());
      liveSquadFeed.add(const LiveSquad(totalTenths: 0, week: 0, slots: []));
      historyFeeds[3]?.add(null);
      publishedFeeds[3]?.add(mySquad);
      overallFeed.add(null);
      await settle(tester);
      expect(find.text("0 pts · this week didn't count"), findsOneWidget);
    });

    // The court is the squad that was LOCKED, not Squads/<uid> (which the
    // server rewrites after finalize and which keeps a chip the lock voided).
    FantasySquad tripleCaptainOnAxel() => FantasySquad(
          picks: mySquad.picks,
          captainId: 'Axel Shot',
          viceId: 'Dana Wall',
          chip: 'tripleCaptain',
        );

    testWidgets(
        'live: the court, armband and ×N come from PublishedPicks, not from '
        'the saved squad', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked); // Squads: ×2, Ava
      answerOwn(locked: tripleCaptainOnAxel());
      await settle(tester);
      expect(publishedRequests, [3]);
      expect(find.text('ATT · \$6.5M · ×3'), findsOneWidget);
      expect(find.text('ATT · \$7.0M · ×2'), findsNothing);
      expect(key('captain_ring_Axel Shot'), findsOneWidget);
      expect(key('captain_ring_Ava Striker'), findsNothing);
    });

    testWidgets(
        'settled: the court, armband and ×N come from History — the chip the '
        'rollover removed from Squads still reads ×3', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked); // Squads: no chip
      liveFeed.add(liveState(state: LiveState.settled));
      liveSquadFeed.add(null);
      historyFeeds[3]!.add(settledWeek(squad: tripleCaptainOnAxel()));
      publishedFeeds[3]!.add(null);
      overallFeed.add(const OverallStanding(rank: 4));
      await settle(tester);
      expect(find.text('Final · 34 pts · #4'), findsOneWidget);
      expect(find.text('ATT · \$6.5M · ×3'), findsOneWidget);
      expect(key('captain_ring_Axel Shot'), findsOneWidget);
    });

    testWidgets(
        'a failed History read in a settled week: just "Locked", no chip '
        'lines — never "waiting for kickoff"', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      liveFeed.add(liveState(state: LiveState.settled));
      liveSquadFeed.add(null);
      historyFeeds[3]!.addError(StateError('permission denied'));
      publishedFeeds[3]!.add(null);
      overallFeed.add(const OverallStanding(rank: 4));
      await settle(tester);
      expect(key('hub'), findsOneWidget);
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);
      expect(
          find.descendant(
              of: key('squad_chip_Ava Striker'),
              matching: find.textContaining('pts')),
          findsNothing);
    });

    testWidgets(
        'before kickoff with every stream answered: the genuine "waiting '
        'for kickoff"', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.locked);
      liveFeed.add(const FantasyLiveState()); // no Live node yet
      liveSquadFeed.add(null);
      historyFeeds[3]!.add(null);
      publishedFeeds[3]!.add(mySquad);
      overallFeed.add(null);
      await settle(tester);
      expect(find.text('Locked · waiting for kickoff'), findsOneWidget);
    });

    testWidgets('editing open: no locked-week stream is ever subscribed',
        (tester) async {
      await pumpLockedHub(tester, now: () => DateTime.utc(2026, 10, 10, 12));
      await land(tester, lock: FantasyLockOverride.open);
      expect(key('hub'), findsOneWidget);
      expect(liveListens, 0);
      expect(historyRequests, isEmpty);
      expect(strip(), findsNothing);
      expect(find.byType(FantasyLivePill), findsNothing);
    });

    testWidgets('the owner locking the week while the hub is open starts the '
        'streams; reopening stops them', (tester) async {
      await pumpLockedHub(tester);
      await land(tester, lock: FantasyLockOverride.open);
      expect(liveListens, 0);

      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.locked));
      await tester.pump(const Duration(milliseconds: 50));
      expect(liveListens, 1);
      expect(historyRequests, [3]);
      // The streams have not answered yet — and the shown hub never goes back
      // to its skeleton for it (the gate belongs to the first reveal only).
      expect(key('hub'), findsOneWidget);
      expect(key('skeleton'), findsNothing);
      answerOwn();
      await settle(tester);
      expect(find.text('34 pts · #5 ▲2'), findsOneWidget);

      config.add(FantasyConfigState(
          config: FantasyConfig.futsalDefault(),
          lockOverride: FantasyLockOverride.open));
      await settle(tester);
      expect(strip(), findsNothing);
      expect(find.byType(FantasyLivePill), findsNothing);
      expect(liveFeed.hasListener, isFalse);
    });

    testWidgets('the clock crossing the lock (auto) starts the streams at '
        'that instant', (tester) async {
      var now = DateTime.utc(2026, 10, 17, 21, 59, 50);
      await pumpLockedHub(tester, now: () => now);
      await land(tester, lock: FantasyLockOverride.auto);
      expect(liveListens, 0);
      expect(historyRequests, isEmpty);

      now = DateTime.utc(2026, 10, 17, 22, 0, 1);
      await tester.pump(const Duration(seconds: 11));
      expect(liveListens, 1);
      expect(historyRequests, [3]);
    });

    testWidgets('nobody signed in: nothing is subscribed, the hub still '
        'reveals', (tester) async {
      await pumpHub(tester,
          signedIn: false,
          gameweekStates: Stream.value(gws),
          nowUtc: lockDay,
          liveStates: liveFeed.stream,
          liveSquadStates: liveSquadFeed.stream,
          historyWeekFor: historyFor,
          publishedPicksFor: publishedFor,
          overallStandingStates: overallFeed.stream);
      await land(tester, lock: FantasyLockOverride.locked);
      expect(key('hub'), findsOneWidget);
      expect(liveListens, 0);
      expect(historyRequests, isEmpty);
      expect(publishedRequests, isEmpty);
      // Nothing was read, so nothing is claimed about kickoff.
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Locked · waiting for kickoff'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px, $brightness: the live court fits, no overflow',
          (tester) async {
        await pumpLockedHub(tester,
            size: const Size(360, 1900), brightness: brightness);
        await land(tester, lock: FantasyLockOverride.locked);
        answerOwn();
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('34 pts · #5 ▲2'), findsOneWidget);
        for (final k in ['locked_live_strip', 'squad_chip_Ava Striker']) {
          final r = tester.getRect(key(k));
          expect(r.left, greaterThanOrEqualTo(0), reason: k);
          expect(r.right, lessThanOrEqualTo(360), reason: k);
        }
      });
    }
  });

  // Release report #8: the hub header shrinks on scroll to a slim pinned bar
  // that keeps the live deadline countdown; the tab row stays pinned and
  // shows every label whole at 360 px; each tab keeps its scroll offset.
  group('collapsing header (report #8)', () {
    // GW n locks Oct 4 + 7(n-1), 22:00 UTC; "now" (Oct 17 12:00) is GW3,
    // 1d 10h before its lock.
    final gws = [
      for (var n = 1; n <= 5; n++)
        Gameweek(
          number: n,
          date: '10${(4 + 7 * (n - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (n - 1), 22),
          opensUtc: null,
        ),
    ];
    DateTime now() => DateTime.utc(2026, 10, 17, 12);

    Future<void> pumpOpenHub(WidgetTester tester, Brightness brightness) async {
      await pumpHub(tester,
          size: const Size(360, 740),
          brightness: brightness,
          gameweekStates: Stream.value(gws),
          nowUtc: now);
      await land(tester, lock: FantasyLockOverride.auto);
    }

    ScrollableState myTeamList(WidgetTester tester) => tester.state(find
        .descendant(
            of: find.byType(FantasyMyTeamTab, skipOffstage: false),
            matching: find.byType(Scrollable),
            skipOffstage: false)
        .first);

    Finder slimCountdown() => key('deadline_slim_countdown');

    bool collapsed() =>
        slimCountdown().evaluate().isNotEmpty &&
        find.byType(FantasyBanner).evaluate().isEmpty;

    /// The active tab's own vertical list.
    ScrollPosition tabList(WidgetTester tester, Type tab) => tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(tab),
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first)
        .position;

    /// A slow finger drag with the finger held down while the collapse runs
    /// (review 6, I1), then release; returns how often the header changed
    /// state while pumping.
    Future<int> slowDrag(WidgetTester tester, double dy,
        {Offset at = const Offset(180, 600)}) async {
      var changes = 0;
      var last = collapsed();
      void sample() {
        final now = collapsed();
        if (now != last) changes++;
        last = now;
      }

      final g = await tester.startGesture(at);
      final steps = (dy.abs() / 4).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(0, dy / steps));
        await tester.pump(const Duration(milliseconds: 16));
        sample();
      }
      await g.up();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        sample();
      }
      return changes;
    }

    Map<String, Object?> post(int i) => {
          'Title': 'Post $i',
          'Body': 'A line of league news number $i.',
          'At': 100 - i,
          'Template': 'custom',
        };

    Future<void> openNews(WidgetTester tester, int posts,
        {Size size = const Size(360, 740)}) async {
      await pumpHub(tester,
          tab: FantasyHubTab.news,
          size: size,
          gameweekStates: Stream.value(gws),
          nowUtc: now);
      await land(tester, lock: FantasyLockOverride.auto);
      news.add(newsPostsFromNode({
        for (var i = 0; i < posts; i++) 'p$i': post(i),
      }));
      await settle(tester);
    }

    group('every tab collapses and expands (review 6)', () {
      Future<void> roundTrip(WidgetTester tester, FantasyHubTab tab,
          Future<void> Function() feed) async {
        await pumpHub(tester,
            tab: tab,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now);
        await land(tester, lock: FantasyLockOverride.auto);
        await feed();
        await settle(tester);
        expect(collapsed(), isFalse);
        await tester.dragFrom(const Offset(180, 650), const Offset(0, -400));
        await settle(tester);
        expect(collapsed(), isTrue, reason: '$tab');
        expect(tester.widget<Text>(slimCountdown()).data, '1d 10:00:00');
        expect(tester.getRect(slimCountdown()).top, greaterThanOrEqualTo(0));
        await tester.flingFrom(
            const Offset(180, 400), const Offset(0, 3000), 4000);
        await settle(tester);
        await settle(tester);
        expect(collapsed(), isFalse, reason: '$tab');
        expect(tester.takeException(), isNull);
      }

      testWidgets('Players (a long market)', (tester) async {
        await roundTrip(tester, FantasyHubTab.players, () async {
          players.add([
            ...market,
            for (var i = 0; i < 30; i++)
              _player('Extra Player $i', FantasyPosition.att, 40 + i,
                  team: 'Team ${i % 4}'),
          ]);
        });
      });

      testWidgets('Leaderboards (a long table)', (tester) async {
        await roundTrip(tester, FantasyHubTab.leaderboards, () async {
          boards.add(leaderboardsFromNode({
            'Overall': {
              for (var i = 1; i <= 40; i++)
                'u$i': {'points': 200 - i, 'rank': i},
            },
          }));
          managers.add({
            for (var i = 1; i <= 40; i++)
              'u$i': FantasyManager(teamName: 'Team $i', nameFlagged: false),
          });
          leagues.add(const []);
          dreams.add(const {});
        });
      });

      testWidgets('News (many posts)', (tester) async {
        await roundTrip(tester, FantasyHubTab.news, () async {
          news.add(newsPostsFromNode({
            for (var i = 0; i < 20; i++) 'p$i': post(i),
          }));
        });
      });

      testWidgets('Rules', (tester) async {
        await roundTrip(tester, FantasyHubTab.rules, () async {});
      });
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('Players search at 360 px with the keyboard open, text '
          'scale $scale: no overflow; switching tabs drops the keyboard '
          '(review 6, M-a)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpHub(tester,
            tab: FantasyHubTab.players,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now);
        await land(tester, lock: FantasyLockOverride.auto);
        await tester.tap(key('market_search_toggle'));
        await settle(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(key('market_search'), findsOneWidget);

        await tester.tap(find.widgetWithText(Tab, 'My Team'));
        await settle(tester);
        expect(tester.testTextInput.isVisible, isFalse);
        tester.view.resetViewInsets();
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('$brightness: a failed schedule read — both header faces '
          'say "Deadline unavailable", My Team never says "Locked", the '
          'market says it cannot check (review 6, I2)', (tester) async {
        await pumpHub(tester,
            size: const Size(360, 740),
            brightness: brightness,
            gameweekStates: Stream<List<Gameweek>>.error(
                StateError('permission-denied')),
            nowUtc: now);
        await land(tester, lock: FantasyLockOverride.auto);
        expect(find.byType(FantasyBanner), findsOneWidget);
        expect(find.text('Deadline unavailable'), findsOneWidget);
        expect(find.text('Season complete'), findsNothing);
        expect(find.text('Locked'), findsNothing);
        expect(key('locked_live_strip'), findsNothing);
        expect(key('deadline_unknown_strip'), findsOneWidget);

        await tester.dragFrom(const Offset(180, 650), const Offset(0, -400));
        await settle(tester);
        expect(collapsed(), isFalse,
            reason: 'no countdown: the slim bar has a label only');
        expect(find.byType(FantasyBanner), findsNothing);
        expect(tester.widget<Text>(key('deadline_slim_label')).data,
            'Deadline unavailable');
        expect(find.text('Season complete'), findsNothing);

        await tester.ensureVisible(find.widgetWithText(Tab, 'Players'));
        await tester.tap(find.widgetWithText(Tab, 'Players'));
        await settle(tester);
        await settle(tester);
        final tip = tester.widget<Tooltip>(
            key('market_add_disabled_Ava Striker'));
        expect(tip.message,
            'Can\'t check the deadline right now — try again in a moment.');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a kept-alive Leaderboards tab drops its large live feeds '
        'while off screen and picks them up on return with no reload '
        '(review 6, M-b)', (tester) async {
      await pumpHub(tester,
          tab: FantasyHubTab.leaderboards,
          size: const Size(360, 740),
          gameweekStates: Stream.value(gws),
          nowUtc: now);
      await land(tester, lock: FantasyLockOverride.auto);
      boards.add(leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 50, 'rank': 1},
        },
      }));
      managers.add({
        'u1': const FantasyManager(teamName: 'Top Cats', nameFlagged: false),
      });
      leagues.add(const []);
      dreams.add(const {});
      await settle(tester);
      expect(find.text('Top Cats'), findsOneWidget);
      expect(boards.hasListener, isTrue);
      expect(dreams.hasListener, isTrue);

      await tester.ensureVisible(find.widgetWithText(Tab, 'My Team'));
      await settle(tester);
      await tester.tap(find.widgetWithText(Tab, 'My Team'));
      await settle(tester);
      await settle(tester);
      expect(boards.hasListener, isFalse, reason: 'paused off screen');
      expect(dreams.hasListener, isFalse);
      expect(managers.hasListener, isTrue, reason: 'small, rare: kept');

      await tester.ensureVisible(find.widgetWithText(Tab, 'Leaderboards'));
      await settle(tester);
      await tester.tap(find.widgetWithText(Tab, 'Leaderboards'));
      // The tab slide (no feed has answered again yet: the new listeners
      // only re-attached) — the rows it had are there, no skeleton.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Top Cats'), findsOneWidget);
      await settle(tester);
      expect(boards.hasListener, isTrue);
      expect(dreams.hasListener, isTrue);
      boards.add(leaderboardsFromNode({
        'Overall': {
          'u1': {'points': 61, 'rank': 1},
        },
      }));
      await settle(tester);
      expect(find.textContaining('61'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    group('first visit and hide/show of a kept-alive tab (review 6b)', () {
      Future<void> tapTab(WidgetTester tester, String label) async {
        await tester.ensureVisible(find.widgetWithText(Tab, label));
        await settle(tester);
        await tester.tap(find.widgetWithText(Tab, label));
      }

      testWidgets('Leaderboards, first open: its feeds attach once (no '
          'cancel / re-attach), from the first frame of the switch',
          (tester) async {
        var listens = 0, cancels = 0;
        await boards.close();
        boards = StreamController<FantasyLeaderboards>.broadcast(
            onListen: () => listens++, onCancel: () => cancels++);
        await pumpHub(tester,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now);
        await land(tester, lock: FantasyLockOverride.auto);
        expect(listens, 0, reason: 'not built before its first visit');

        await tapTab(tester, 'Leaderboards');
        await tester.pump();
        // Mid-switch (the slide takes 300 ms): attached from the first
        // frame of the switch and never dropped.
        await tester.pump(const Duration(milliseconds: 50));
        expect(listens, 1);
        expect(cancels, 0);
        expect(tester.binding.hasScheduledFrame, isTrue,
            reason: 'still mid-switch');
        boards.add(leaderboardsFromNode({
          'Overall': {
            'u1': {'points': 50, 'rank': 1},
          },
        }));
        managers.add({
          'u1': const FantasyManager(teamName: 'Top Cats', nameFlagged: false),
        });
        leagues.add(const []);
        dreams.add(const {});
        await settle(tester);
        expect(find.text('Top Cats'), findsOneWidget);
        expect(listens, 1);
        expect(cancels, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Players, first open: totals attach at the start of the '
          'switch, once', (tester) async {
        var listens = 0, cancels = 0;
        final totals = StreamController<Map<String, FantasyPlayerTotals>?>
            .broadcast(onListen: () => listens++, onCancel: () => cancels++);
        addTearDown(totals.close);
        await pumpHub(tester,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now,
            playerTotalsStates: totals.stream);
        await land(tester, lock: FantasyLockOverride.auto);
        expect(listens, 0);

        await tapTab(tester, 'Players');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(listens, 1, reason: 'attached from the first frame');
        expect(cancels, 0);
        totals.add(const {});
        await settle(tester);
        expect(key('market_row_Ava Striker'), findsOneWidget);
        expect(listens, 1);
        expect(cancels, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Players hidden then shown: totals drop and re-attach; no '
          'reload, the filter and scroll offset are kept', (tester) async {
        var listens = 0, cancels = 0;
        final totals = StreamController<Map<String, FantasyPlayerTotals>?>
            .broadcast(onListen: () => listens++, onCancel: () => cancels++);
        addTearDown(totals.close);
        await pumpHub(tester,
            tab: FantasyHubTab.players,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now,
            playerTotalsStates: totals.stream);
        await land(tester, lock: FantasyLockOverride.auto);
        players.add([
          ...market,
          for (var i = 0; i < 30; i++)
            _player('Extra Def $i', FantasyPosition.def, 40 + i,
                team: 'Team ${i % 4}'),
        ]);
        totals.add(const {});
        await settle(tester);
        await tester.tap(key('market_pos_DEF'));
        await settle(tester);
        expect(key('market_row_Ava Striker'), findsNothing);
        await tester.dragFrom(const Offset(180, 650), const Offset(0, -300));
        await settle(tester);
        final list = tester.state<ScrollableState>(find
            .descendant(
                of: key('players_market'),
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first);
        final offset = list.position.pixels;
        expect(offset, greaterThan(0));
        expect(listens, 1);

        await tapTab(tester, 'My Team');
        await settle(tester);
        await settle(tester);
        expect(cancels, 1, reason: 'dropped while hidden');

        await tapTab(tester, 'Players');
        await tester.pump();
        expect(key('players_market_skeleton'), findsNothing);
        await settle(tester);
        await settle(tester);
        expect(listens, 2, reason: 're-attached on return');
        expect(key('players_market_skeleton'), findsNothing);
        expect(key('market_row_Ava Striker'), findsNothing,
            reason: 'the DEF filter is kept');
        expect(list.position.pixels, offset);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a failed schedule read: the squad alert promises no free '
        'swap and names no deadline it could not read (review 6b, item 3)',
        (tester) async {
      await pumpHub(tester,
          size: const Size(360, 1200),
          gameweekStates:
              Stream<List<Gameweek>>.error(StateError('permission-denied')),
          nowUtc: now);
      await land(tester, lock: FantasyLockOverride.auto);
      alert.add(const FantasySquadAlert(gameweek: 3, changes: [
        FantasyPositionChange(
            player: 'Ava Striker',
            from: FantasyPosition.att,
            to: FantasyPosition.def),
      ]));
      await settle(tester);
      expect(
          find.text('Ava Striker moved to DEF — your team needs rearranging '
              'before the deadline.'),
          findsOneWidget);
      expect(find.textContaining('free this week'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    group('never stuck collapsed (review 6, I1)', () {
      testWidgets('News, one post (short): a slow drag never collapses',
          (tester) async {
        await openNews(tester, 1);
        expect(await slowDrag(tester, -200), 0);
        expect(collapsed(), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('News, many posts (long): collapses once, stays draggable, '
          'pulling down at the top expands', (tester) async {
        await openNews(tester, 20);
        expect(await slowDrag(tester, -200), 1);
        expect(collapsed(), isTrue);
        expect(tabList(tester, FantasyNewsTab).maxScrollExtent,
            greaterThan(0));
        await slowDrag(tester, 600, at: const Offset(180, 300));
        expect(collapsed(), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('News across the boundary band (screen heights sweep): a '
          'drag that ends collapsed always leaves something to drag back',
          (tester) async {
        for (var h = 600.0; h <= 1100; h += 50) {
          await tester.pumpWidget(const SizedBox()); // a fresh hub each time
          await openNews(tester, 3, size: Size(360, h));
          final changes = await slowDrag(tester, -220,
              at: Offset(180, h - 120));
          expect(changes, lessThanOrEqualTo(1), reason: 'height $h');
          if (collapsed()) {
            expect(tabList(tester, FantasyNewsTab).maxScrollExtent,
                greaterThan(16),
                reason: 'height $h: collapsed with nothing to drag');
          }
          expect(tester.takeException(), isNull, reason: 'height $h');
        }
      });

      testWidgets('My Team across the boundary band (screen heights sweep)',
          (tester) async {
        for (var h = 600.0; h <= 1300; h += 50) {
          await tester.pumpWidget(const SizedBox()); // a fresh hub each time
          await pumpHub(tester,
              size: Size(360, h),
              gameweekStates: Stream.value(gws),
              nowUtc: now);
          await land(tester, lock: FantasyLockOverride.auto);
          final changes = await slowDrag(tester, -220,
              at: Offset(180, h - 120));
          expect(changes, lessThanOrEqualTo(1), reason: 'height $h');
          if (collapsed()) {
            expect(tabList(tester, FantasyMyTeamTab).maxScrollExtent,
                greaterThan(16),
                reason: 'height $h: collapsed with nothing to drag');
          }
          expect(tester.takeException(), isNull, reason: 'height $h');
        }
      });

      testWidgets('My Team, short (no team name yet): a slow drag never '
          'collapses', (tester) async {
        await pumpHub(tester,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now);
        await land(tester,
            lock: FantasyLockOverride.auto, withManager: false);
        expect(await slowDrag(tester, -200), 0);
        expect(collapsed(), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('scrolled My Team → a short News tab opens the header; '
          'back on My Team it is collapsed again', (tester) async {
        await pumpHub(tester,
            size: const Size(360, 740),
            gameweekStates: Stream.value(gws),
            nowUtc: now);
        await land(tester, lock: FantasyLockOverride.auto);
        news.add(newsPostsFromNode({'p0': post(0)}));
        await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
        await settle(tester);
        expect(collapsed(), isTrue);
        await tester.ensureVisible(find.widgetWithText(Tab, 'News'));
        await settle(tester);
        await tester.tap(find.widgetWithText(Tab, 'News'));
        await settle(tester);
        await settle(tester);
        expect(collapsed(), isFalse);
        await tester.ensureVisible(find.widgetWithText(Tab, 'My Team'));
        await settle(tester);
        await tester.tap(find.widgetWithText(Tab, 'My Team'));
        await settle(tester);
        await settle(tester);
        expect(collapsed(), isTrue);
        expect(tester.takeException(), isNull);
      });
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px, $brightness: expanded at the top; a scroll '
          'collapses it with the countdown still on screen; back at the top '
          'it expands', (tester) async {
        await pumpOpenHub(tester, brightness);
        expect(find.byType(FantasyBanner), findsOneWidget);
        expect(key('deadline_countdown'), findsOneWidget);
        expect(slimCountdown(), findsNothing);

        await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
        await settle(tester);
        expect(find.byType(FantasyBanner), findsNothing);
        expect(slimCountdown(), findsOneWidget);
        expect(tester.widget<Text>(slimCountdown()).data, '1d 10:00:00');
        expect(find.text('GW3 locks in'), findsOneWidget);
        expect(tester.getRect(slimCountdown()).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);

        await tester.flingFrom(
            const Offset(180, 400), const Offset(0, 1500), 3000);
        await settle(tester);
        await settle(tester);
        expect(find.byType(FantasyBanner), findsOneWidget);
        expect(slimCountdown(), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('360 px, $brightness: every tab label is whole — none '
          'ellipsized', (tester) async {
        await pumpOpenHub(tester, brightness);
        for (final l in ['My Team', 'Players', 'Leaderboards', 'News', 'Rules']) {
          final p = tester.renderObject<RenderParagraph>(find.descendant(
              of: find.widgetWithText(Tab, l), matching: find.text(l)));
          expect(p.didExceedMaxLines, isFalse, reason: l);
          expect(
              p.size.width,
              greaterThanOrEqualTo(
                  p.getMaxIntrinsicWidth(double.infinity) - 0.5),
              reason: l);
        }
        // More tabs off the right edge: the fade says so.
        expect(key('tabs_more_end'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('switching tabs and coming back keeps My Team\'s scroll '
        'offset', (tester) async {
      await pumpOpenHub(tester, Brightness.light);
      await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
      await settle(tester);
      final offset = myTeamList(tester).position.pixels;
      expect(offset, greaterThan(0));

      await tester.tap(find.widgetWithText(Tab, 'Players'));
      await settle(tester);
      await tester.tap(find.widgetWithText(Tab, 'My Team'));
      await settle(tester);
      expect(myTeamList(tester).position.pixels, offset);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text scale 1.3 at 360 px: expanded and collapsed headers do '
        'not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpOpenHub(tester, Brightness.dark);
      expect(tester.takeException(), isNull);
      await tester.dragFrom(const Offset(180, 600), const Offset(0, -300));
      await settle(tester);
      expect(slimCountdown(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
