// P6 — the front page's in-season Infinite Fantasy banner with fake streams:
// hidden while the Config node is absent (and again when it's removed live),
// shown while it exists, the deadline countdown chip only while the current
// gameweek is open under the automatic lock, and the tap-through seam.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_home_banner.dart';

void main() {
  late StreamController<FantasyConfigState?> configs;
  late StreamController<List<Gameweek>> gameweeks;
  late int opens;

  setUp(() {
    configs = StreamController<FantasyConfigState?>.broadcast(sync: true);
    gameweeks = StreamController<List<Gameweek>>.broadcast(sync: true);
    opens = 0;
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

  Future<void> pumpBanner(WidgetTester tester, {DateTime? now}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyHomeBanner(
          sport: 'Futsal',
          season: '15',
          configStates: configs.stream,
          gameweeksStates: gameweeks.stream,
          onOpen: () => opens++,
          nowUtc: () => now ?? DateTime.utc(2026, 10, 17, 12),
        ),
      ),
    ));
  }

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
      'tap opens the hub', (tester) async {
    await pumpBanner(tester); // two days before GW1's lock
    configs.add(state());
    gameweeks.add([gw1()]);
    await tester.pump();

    expect(find.byKey(const ValueKey('fantasy_home_banner_deadline')),
        findsOneWidget);
    expect(find.textContaining('GW1 locks in'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fantasy_home_banner')));
    expect(opens, 1);
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
}
