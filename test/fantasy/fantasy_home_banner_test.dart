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
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_home_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart'
    show FantasyHubTab;

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
}
