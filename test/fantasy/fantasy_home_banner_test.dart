// P6 — the front page's in-season Infinite Fantasy banner with fake streams:
// hidden while the Config node is absent (and again when it's removed live),
// shown while it exists, the deadline countdown chip only while the current
// gameweek is open under the automatic lock, and the tap-through seam. Once
// the league's Finished flag is set (Opus audit Minor 8): "Season over — see
// the final standings", no chip, the tap opens Leaderboards — and the banner
// waits for that flag so its copy never flips. 360 px in light AND dark
// (Opus audit item 7).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_home_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart'
    show FantasyHubTab;
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';

void main() {
  late StreamController<FantasyConfigState?> configs;
  late StreamController<List<Gameweek>> gameweeks;
  late List<FantasyHubTab> opened;

  setUp(() {
    FantasySeasonFinishedFeed.clearSessionCache();
    configs = StreamController<FantasyConfigState?>.broadcast(sync: true);
    gameweeks = StreamController<List<Gameweek>>.broadcast(sync: true);
    opened = [];
  });

  tearDown(() {
    configs.close();
    gameweeks.close();
  });

  FantasyConfigState state(
          [FantasyLockOverride override = FantasyLockOverride.auto]) =>
      FantasyConfigState(
          config: FantasyConfig.futsalDefault(), lockOverride: override);

  Gameweek gw1() => Gameweek(
        number: 1,
        date: '10192026',
        lockUtc: DateTime.utc(2026, 10, 19, 22),
        opensUtc: null,
      );

  Future<void> pumpBanner(
    WidgetTester tester, {
    DateTime? now,
    Size size = const Size(420, 900),
    Brightness brightness = Brightness.light,
    Stream<bool>? finished,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: Scaffold(
        body: FantasyHomeBanner(
          sport: 'Futsal',
          season: '15',
          configStates: configs.stream,
          gameweeksStates: gameweeks.stream,
          // Default: the league's Finished flag answers "not over" at once.
          finishedStates: finished ?? Stream<bool>.value(false),
          onOpen: opened.add,
          nowUtc: () => now ?? DateTime.utc(2026, 10, 17, 12),
        ),
      ),
    ));
  }

  String title(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('fantasy_home_banner_title')))
      .data!;

  testWidgets('hidden while Config is absent, shown while it exists, hidden '
      'again when it goes away live', (tester) async {
    await pumpBanner(tester);
    expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

    configs.add(state());
    gameweeks.add(const []);
    await tester.pump();
    expect(find.byKey(const ValueKey('fantasy_home_banner')), findsOneWidget);
    expect(find.text('Fantasy is live — set your squad'), findsOneWidget);

    configs.add(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);
  });

  testWidgets(
      'a Config error is logged and keeps a shown banner (the last good '
      'config); before any config it stays hidden', (tester) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    try {
      await pumpBanner(tester);
      configs.addError(StateError('offline'));
      await tester.pump();
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

      configs.add(state());
      gameweeks.add(const []);
      await tester.pump();
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsOneWidget);

      configs.addError(StateError('permission-denied blip'));
      await tester.pump();
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugPrint = original;
    }
    expect(logs.join('\n'),
        contains('FantasyHomeBanner: config feed failed: Bad state: offline'));
    expect(logs.join('\n'), contains('permission-denied blip'));
  });

  testWidgets('deadline chip while the gameweek is open under auto lock; '
      'tap opens the hub on My Team', (tester) async {
    await pumpBanner(tester); // two days before GW1's lock
    configs.add(state());
    gameweeks.add([gw1()]);
    await tester.pump();

    expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
        findsOneWidget);
    expect(find.textContaining('GW1 locks in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fantasy_home_banner')));
    expect(opened, [FantasyHubTab.myTeam]);
  });

  testWidgets('no deadline chip once locked or under a league override',
      (tester) async {
    // After the lock instant: banner stays, chip goes.
    await pumpBanner(tester, now: DateTime.utc(2026, 10, 19, 23));
    configs.add(state());
    gameweeks.add([gw1()]);
    await tester.pump();
    expect(find.byKey(const ValueKey('fantasy_home_banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
        findsNothing);

    // League override (open test bed): countdown would lie — no chip.
    configs.add(state(FantasyLockOverride.open));
    await tester.pump();
    expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
        findsNothing);
  });

  group('locked: never "set your squad" while saving is shut (owner 2026-11-04)',
      () {
    testWidgets('lock → midnight on match day: "GW1 locked · games today"',
        (tester) async {
      // 4 PM PDT on match day, an hour after the 3 PM lock.
      await pumpBanner(tester, now: DateTime.utc(2026, 10, 19, 23));
      configs.add(state());
      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'GW1 locked · games today');
      expect(find.text('Fantasy is live — set your squad'), findsNothing);
    });

    testWidgets(
        'the first reveal waits for the schedule: never "set your squad" '
        'first, then "locked"', (tester) async {
      await pumpBanner(tester, now: DateTime.utc(2026, 10, 19, 23));
      configs.add(state());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'GW1 locked · games today');
    });

    testWidgets(
        'a silent schedule never holds the banner: it shows after 2 s and '
        'the schedule lands in place', (tester) async {
      await pumpBanner(tester, now: DateTime.utc(2026, 10, 19, 23));
      configs.add(state());
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(title(tester), 'Fantasy is live — set your squad');

      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'GW1 locked · games today');
    });

    testWidgets('11:59 PM on match day still says games today', (tester) async {
      await pumpBanner(tester, now: DateTime.utc(2026, 10, 20, 6, 59));
      configs.add(state());
      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'GW1 locked · games today');
    });

    testWidgets(
        'the next morning, before the next week opens: plain "GW1 locked"',
        (tester) async {
      // 00:00 and 2:59 PM PDT the day after (lock + 24 h = 3 PM).
      for (final now in [
        DateTime.utc(2026, 10, 20, 7),
        DateTime.utc(2026, 10, 20, 21, 59),
      ]) {
        await pumpBanner(tester, now: now);
        configs.add(state());
        gameweeks.add([gw1()]);
        await tester.pump();
        expect(title(tester), 'GW1 locked', reason: '$now');
      }
    });

    testWidgets('league override: locked says so, open still invites a save',
        (tester) async {
      await pumpBanner(tester); // GW1 open by the clock
      configs.add(state(FantasyLockOverride.locked));
      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'Squads locked by the league');
      expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
          findsNothing);

      configs.add(state(FantasyLockOverride.open));
      await tester.pump();
      expect(title(tester), 'Fantasy is live — set your squad');
    });

    testWidgets('season over wins over a locked week', (tester) async {
      await pumpBanner(tester,
          now: DateTime.utc(2026, 10, 19, 23),
          finished: Stream<bool>.value(true));
      configs.add(state());
      gameweeks.add([gw1()]);
      await tester.pump();
      expect(title(tester), 'Season over — see the final standings');
    });

    for (final brightness in Brightness.values) {
      testWidgets('360 px: the locked line wraps, never overflows — $brightness',
          (tester) async {
        await pumpBanner(tester,
            now: DateTime.utc(2026, 10, 19, 23),
            size: const Size(360, 640),
            brightness: brightness);
        configs.add(state());
        gameweeks.add([gw1()]);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final r = tester
            .getRect(find.byKey(const ValueKey('fantasy_home_banner_title')));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      });
    }
  });

  group('season over (Opus audit Minor 8)', () {
    testWidgets(
        '"Season over — see the final standings", no deadline chip, the tap '
        'opens Leaderboards', (tester) async {
      await pumpBanner(tester, finished: Stream<bool>.value(true));
      configs.add(state());
      gameweeks.add([gw1()]); // still "open" by the clock
      await tester.pump();
      expect(title(tester), 'Season over — see the final standings');
      expect(find.text('Fantasy is live — set your squad'), findsNothing);
      expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('fantasy_home_banner')));
      expect(opened, [FantasyHubTab.leaderboards]);
    });

    testWidgets('hidden until the Finished flag answers — the copy never '
        'flips in front of the fan; live flips still follow', (tester) async {
      final finished = StreamController<bool>.broadcast(sync: true);
      addTearDown(finished.close);
      await pumpBanner(tester, finished: finished.stream);
      configs.add(state());
      gameweeks.add(const []);
      await tester.pump();
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

      finished.add(false);
      await tester.pump();
      expect(title(tester), 'Fantasy is live — set your squad');

      finished.add(true); // the owner closes the season live
      await tester.pump();
      expect(title(tester), 'Season over — see the final standings');
    });
  });

  // Opus audit item 7: 360 px in light AND dark — the live state with its
  // deadline chip, and the season-over state.
  group('360 px, light + dark', () {
    for (final brightness in Brightness.values) {
      for (final over in [false, true]) {
        final label = over ? 'season over' : 'live + deadline chip';
        testWidgets('no overflow ($label) — $brightness', (tester) async {
          await pumpBanner(tester,
              size: const Size(360, 640),
              brightness: brightness,
              finished: Stream<bool>.value(over));
          configs.add(state());
          gameweeks.add([gw1()]);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
              over ? findsNothing : findsOneWidget);
          for (final key in [
            'fantasy_home_banner',
            'fantasy_home_banner_title',
            if (!over) 'fantasy_home_banner_deadline',
          ]) {
            final r = tester.getRect(find.byKey(ValueKey(key)));
            expect(r.left, greaterThanOrEqualTo(0), reason: key);
            expect(r.right, lessThanOrEqualTo(360), reason: key);
          }
          final t = tester.widget<Text>(
              find.byKey(const ValueKey('fantasy_home_banner_title')));
          expect(t.maxLines, isNull);
          expect(t.overflow, isNot(TextOverflow.ellipsis));
        });
      }
    }
  });

  // ── Live everywhere (Task 6) ─────────────────────────────────────────────
  group('live gameweek', () {
    late StreamController<FantasyLiveState> live;
    setUp(() {
      live = StreamController<FantasyLiveState>.broadcast(sync: true);
    });
    tearDown(() => live.close());

    FantasyLiveState liveState({
      LiveState state = LiveState.live,
      int gw = 3,
      Map<String, LiveBoardRow> board = const {
        'me': LiveBoardRow(o: 120, r: 5, m: 2, w: 34, wr: 2),
      },
    }) =>
        FantasyLiveState(meta: LiveMeta(gw: gw, state: state), board: board);

    const liveLine = 'GW3 live · 34 pts · #5';
    // The clock below is an hour after GW1's lock on match day: with the
    // schedule loaded, the no-live-line title is the locked one.
    const restingLocked = 'GW1 locked · games today';

    // The pill pulses forever: pump fixed durations, never pumpAndSettle.
    Future<void> pumpLive(
      WidgetTester tester, {
      Stream<FantasyLiveState>? liveStates,
      Stream<Set<int>>? voidedStates,
      String? uid = 'me',
      Size size = const Size(420, 900),
      Brightness brightness = Brightness.light,
      bool finished = false,
      Stream<HistoryWeek?> Function(int week)? historyWeekFor,
      Stream<OverallStanding?>? overallStates,
      DateTime Function()? clock,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        home: Scaffold(
          body: FantasyHomeBanner(
            sport: 'Futsal',
            season: '15',
            configStates: configs.stream,
            gameweeksStates: gameweeks.stream,
            finishedStates: Stream<bool>.value(finished),
            liveStates: liveStates ?? live.stream,
            // Default: nothing voided, answered at once (a cache-seeded feed).
            voidedStates: voidedStates ?? Stream<Set<int>>.value(const {}),
            // Default: nothing settled yet, answered at once.
            historyWeekFor:
                historyWeekFor ?? (_) => Stream<HistoryWeek?>.value(null),
            overallStates:
                overallStates ?? Stream<OverallStanding?>.value(null),
            signedInUid: () => uid,
            onOpen: opened.add,
            nowUtc: clock ?? () => DateTime.utc(2026, 10, 19, 23),
          ),
        ),
      ));
    }

    Finder pill() => find.descendant(
        of: find.byKey(const ValueKey('fantasy_home_banner')),
        matching: find.byType(FantasyLivePill));

    testWidgets(
        'while live the banner says "GW{n} live · {W} pts · #{R}" with the '
        'pill — his own row of the live board', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState());
      await tester.pump();

      expect(title(tester), liveLine);
      expect(pill(), findsOneWidget);
      expect(find.text('Fantasy is live — set your squad'), findsNothing);

      // A moving score changes the numbers in place.
      live.add(liveState(board: const {
        'me': LiveBoardRow(o: 123, r: 4, m: 3, w: 37, wr: 1),
      }));
      await tester.pump();
      expect(title(tester), 'GW3 live · 37 pts · #4');
      expect(pill(), findsOneWidget);

      // The tap still opens My Team (the locked live strip lives there).
      await tester.tap(find.byKey(const ValueKey('fantasy_home_banner')));
      expect(opened, [FantasyHubTab.myTeam]);
    });

    testWidgets(
        'a manager with no squad this week (no W) or not on the live board: '
        'the banner is exactly as before', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState(board: const {'me': LiveBoardRow(o: 120, r: 5)}));
      await tester.pump();
      expect(title(tester), restingLocked);
      expect(pill(), findsNothing);

      live.add(liveState(board: const {
        'someone': LiveBoardRow(o: 1, r: 1, w: 9),
      }));
      await tester.pump();
      expect(title(tester), restingLocked);
      expect(pill(), findsNothing);
    });

    testWidgets(
        'nobody signed in: no live subscription at all, the banner shows as '
        'before', (tester) async {
      var listened = false;
      final spy = StreamController<FantasyLiveState>.broadcast(
          onListen: () => listened = true);
      addTearDown(spy.close);
      await pumpLive(tester, liveStates: spy.stream, uid: null);
      configs.add(state());
      gameweeks.add(const []);
      await tester.pump();
      expect(listened, isFalse);
      expect(title(tester), 'Fantasy is live — set your squad');
    });

    testWidgets(
        'the week settles: the live line and the pill go, the banner is as '
        'before', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState());
      await tester.pump();
      expect(pill(), findsOneWidget);

      live.add(liveState(state: LiveState.settled, board: const {}));
      await tester.pump();
      expect(title(tester), restingLocked);
      expect(pill(), findsNothing);
    });

    testWidgets('no Live node (the feed says "none"): no pill', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add(const []);
      live.add(FantasyLiveState.none);
      await tester.pump();
      expect(title(tester), 'Fantasy is live — set your squad');
      expect(pill(), findsNothing);
    });

    testWidgets(
        'the banner joins the reveal: hidden until the live feed answers, so '
        'its FIRST frame already has the live numbers', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add([gw1()]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

      live.add(liveState());
      await tester.pump();
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsOneWidget);
      expect(title(tester), liveLine);
      // Never "Fantasy is live — set your squad" first.
      expect(find.text('Fantasy is live — set your squad'), findsNothing);
    });

    testWidgets(
        'live silent for 2 s: the banner shows without it, and a late live '
        'lands in place', (tester) async {
      await pumpLive(tester);
      configs.add(state());
      gameweeks.add([gw1()]);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(title(tester), restingLocked);

      live.add(liveState());
      await tester.pump();
      expect(title(tester), liveLine);
    });

    testWidgets('a failing live feed never hides the banner', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      try {
        await pumpLive(tester);
        configs.add(state());
        gameweeks.add(const []);
        live.addError(StateError('offline'));
        await tester.pump();
        expect(title(tester), 'Fantasy is live — set your squad');
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'), contains('FantasyHomeBanner: live feed failed'));
    });

    testWidgets(
        'a week the owner voided: no live line (the Voided set decides — '
        'the live board says 0 pts · #1 for everyone)', (tester) async {
      await pumpLive(tester, voidedStates: Stream.value(const {3}));
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState());
      await tester.pump();
      expect(title(tester), restingLocked);
      expect(pill(), findsNothing);
    });

    testWidgets(
        'the Voided set joins the reveal: until it answers the banner waits '
        '(bounded 2 s); a late answer lands in place', (tester) async {
      final late = StreamController<Set<int>>.broadcast(sync: true);
      addTearDown(late.close);
      await pumpLive(tester, voidedStates: late.stream);
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

      late.add(const {});
      await tester.pump();
      expect(title(tester), liveLine); // the very first frame has it
    });

    testWidgets(
        'the Voided set silent for 2 s: the banner shows WITHOUT a live line '
        '(a possibly-voided week is never called live), the late answer '
        'lands in place', (tester) async {
      final late = StreamController<Set<int>>.broadcast(sync: true);
      addTearDown(late.close);
      await pumpLive(tester, voidedStates: late.stream);
      configs.add(state());
      gameweeks.add([gw1()]);
      live.add(liveState());
      await tester.pump(const Duration(milliseconds: 2100));
      expect(title(tester), restingLocked);

      late.add(const {});
      await tester.pump();
      expect(title(tester), liveLine);
    });

    testWidgets('a failing Voided feed: logged, the banner shows as before '
        '(unknown is never "live")', (tester) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint =
          (String? message, {int? wrapWidth}) => logs.add(message ?? '');
      final broken = StreamController<Set<int>>.broadcast(sync: true);
      addTearDown(broken.close);
      try {
        await pumpLive(tester, voidedStates: broken.stream);
        configs.add(state());
        gameweeks.add(const []);
        live.add(liveState());
        broken.addError(StateError('rules'));
        await tester.pump();
        expect(title(tester), 'Fantasy is live — set your squad');
        expect(pill(), findsNothing);
      } finally {
        debugPrint = original;
      }
      expect(logs.join('\n'), contains('FantasyHomeBanner: voided feed failed'));
    });

    testWidgets('season over: the final-standings copy, never a live line',
        (tester) async {
      await pumpLive(tester, finished: true);
      configs.add(state());
      gameweeks.add(const []);
      live.add(liveState());
      await tester.pump();
      expect(title(tester), 'Season over — see the final standings');
      expect(pill(), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
          '360 px: the live line + pill wrap, never overflow — $brightness',
          (tester) async {
        await pumpLive(tester,
            size: const Size(360, 640), brightness: brightness);
        configs.add(state());
        gameweeks.add([gw1()]);
        live.add(liveState(gw: 12, board: const {
          'me': LiveBoardRow(o: 1234, r: 128, m: 12, w: 134, wr: 12),
        }));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(title(tester), 'GW12 live · 134 pts · #128');
        for (final finder in [
          find.byKey(const ValueKey('fantasy_home_banner')),
          find.byKey(const ValueKey('fantasy_home_banner_title')),
          pill(),
        ]) {
          final r = tester.getRect(finder);
          expect(r.left, greaterThanOrEqualTo(0), reason: '$finder');
          expect(r.right, lessThanOrEqualTo(360), reason: '$finder');
        }
        final t = tester.widget<Text>(
            find.byKey(const ValueKey('fantasy_home_banner_title')));
        expect(t.overflow, isNot(TextOverflow.ellipsis));
        expect(t.style?.decoration, isNot(TextDecoration.underline));
      });
    }

    // ── The final line (owner 2026-11-04) ──────────────────────────────────
    group('final line once the week settles', () {
      late StreamController<HistoryWeek?> history;
      late StreamController<OverallStanding?> overall;
      late List<int> historyWeeks;
      var historyListening = false;
      setUp(() {
        historyWeeks = [];
        historyListening = false;
        history = StreamController<HistoryWeek?>.broadcast(
            sync: true,
            onListen: () => historyListening = true,
            onCancel: () => historyListening = false);
        overall = StreamController<OverallStanding?>.broadcast(sync: true);
      });
      tearDown(() {
        history.close();
        overall.close();
      });

      HistoryWeek week(int tenths,
              {bool voided = false, bool invalid = false}) =>
          HistoryWeek(
              slots: const [],
              totalTenths: tenths,
              voided: voided,
              invalid: invalid);

      Stream<HistoryWeek?> historyFor(int gw) {
        historyWeeks.add(gw);
        return history.stream;
      }

      const settledLive = FantasyLiveState(
          meta: LiveMeta(gw: 1, state: LiveState.settled), board: {});
      const finalLine = 'GW1 final · 34 pts · #5';

      Future<void> pumpFinal(WidgetTester tester,
          {Stream<Set<int>>? voidedStates,
          String? uid = 'me',
          DateTime Function()? clock,
          Size size = const Size(420, 900),
          Brightness brightness = Brightness.light}) async {
        await pumpLive(tester,
            voidedStates: voidedStates,
            uid: uid,
            clock: clock,
            size: size,
            brightness: brightness,
            historyWeekFor: historyFor,
            overallStates: overall.stream);
        configs.add(state());
        gameweeks.add([gw1()]);
        live.add(settledLive);
      }

      testWidgets(
          "settled: 'GW1 final · 34 pts · #5' — My Team's numbers, no pill",
          (tester) async {
        await pumpFinal(tester);
        history.add(week(345)); // net 34.5 → 34, like My Team
        overall.add(const OverallStanding(rank: 5, movement: 2));
        await tester.pump();
        expect(title(tester), finalLine);
        expect(pill(), findsNothing);
        expect(historyWeeks, [1]);

        await tester.tap(find.byKey(const ValueKey('fantasy_home_banner')));
        expect(opened, [FantasyHubTab.myTeam]);
      });

      testWidgets(
          'before finalize the locked line; the result lands in place when '
          'finalize writes it', (tester) async {
        await pumpFinal(tester);
        history.add(null);
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), restingLocked);

        history.add(week(345));
        await tester.pump();
        expect(title(tester), finalLine);
      });

      testWidgets('no Overall rank known: the points alone', (tester) async {
        await pumpFinal(tester);
        history.add(week(10));
        overall.add(null);
        await tester.pump();
        expect(title(tester), 'GW1 final · 1 pt');
      });

      testWidgets('the live line wins while the week is still being played',
          (tester) async {
        await pumpFinal(tester);
        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        live.add(liveState(gw: 1));
        await tester.pump();
        expect(title(tester), 'GW1 live · 34 pts · #5');
        expect(pill(), findsOneWidget);
      });

      testWidgets(
          'a voided week or an invalid squad: the locked line (it counts 0; '
          'My Team says why)', (tester) async {
        await pumpFinal(tester, voidedStates: Stream.value(const {1}));
        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), restingLocked);

        await tester.pumpWidget(const SizedBox());
        await pumpFinal(tester);
        history.add(week(0, invalid: true));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), restingLocked);

        history.add(week(345, voided: true)); // History's own flag
        await tester.pump();
        expect(title(tester), restingLocked);
      });

      testWidgets(
          'a cold open joins the reveal: hidden until History answers, so the '
          'FIRST frame already has the result', (tester) async {
        await pumpFinal(tester);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
            find.byKey(const ValueKey('fantasy_home_banner')), findsNothing);

        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), finalLine);
      });

      testWidgets(
          'History silent for 2 s: the banner shows the locked line and the '
          'late result lands in place', (tester) async {
        await pumpFinal(tester);
        await tester.pump(const Duration(milliseconds: 2100));
        expect(title(tester), restingLocked);

        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), finalLine);
      });

      testWidgets('the next morning, until the next week opens: still final',
          (tester) async {
        await pumpFinal(tester, clock: () => DateTime.utc(2026, 10, 20, 18));
        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), finalLine);
      });

      testWidgets('the next week opening drops the line and stops listening',
          (tester) async {
        var now = DateTime.utc(2026, 10, 20, 21);
        final gw2 = Gameweek(
          number: 2,
          date: '10262026',
          lockUtc: DateTime.utc(2026, 10, 26, 22),
          opensUtc: DateTime.utc(2026, 10, 20, 7),
        );
        await pumpLive(tester,
            historyWeekFor: historyFor,
            overallStates: overall.stream,
            clock: () => now);
        configs.add(state());
        gameweeks.add([gw1(), gw2]);
        live.add(settledLive);
        history.add(week(345));
        overall.add(const OverallStanding(rank: 5));
        await tester.pump();
        expect(title(tester), finalLine);
        expect(historyListening, isTrue);

        now = DateTime.utc(2026, 10, 20, 22, 1); // GW2 open, GW1's day over
        await tester.pump(const Duration(seconds: 61)); // the 60 s refresh
        expect(title(tester), 'Fantasy is live — set your squad');
        expect(historyListening, isFalse);
        expect(historyWeeks, [1]);
      });

      testWidgets('editing open, or nobody signed in: no History listener',
          (tester) async {
        await pumpFinal(tester, clock: () => DateTime.utc(2026, 10, 17, 12));
        await tester.pump();
        expect(title(tester), 'Fantasy is live — set your squad');
        expect(historyListening, isFalse);

        await tester.pumpWidget(const SizedBox());
        await pumpFinal(tester, uid: null);
        await tester.pump();
        expect(title(tester), restingLocked);
        expect(historyListening, isFalse);
      });

      for (final brightness in Brightness.values) {
        testWidgets(
            '360 px: the final line wraps, never overflows — $brightness',
            (tester) async {
          await pumpFinal(tester,
              size: const Size(360, 640), brightness: brightness);
          history.add(week(1345));
          overall.add(const OverallStanding(rank: 128));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(title(tester), 'GW1 final · 134 pts · #128');
          final r = tester.getRect(
              find.byKey(const ValueKey('fantasy_home_banner_title')));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
        });
      }
    });
  });
}
