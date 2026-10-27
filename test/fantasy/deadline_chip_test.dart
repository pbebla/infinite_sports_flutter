// P3a Task 2 — deadline chip: league-timezone countdown with the absolute
// lock time always shown (spec §5), and the lockOverride faces.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  final gameweeks = deriveGameweeks(['07052026', '07122026'], cfg);

  Future<void> pumpChip(
    WidgetTester tester, {
    required FantasyLockOverride override,
    required DateTime now,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyDeadlineChip(
          gameweeks: gameweeks,
          lockOverride: override,
          nowUtc: () => now,
        ),
      ),
    ));
  }

  // The chip refreshes on a periodic timer; dispose it so no timer is
  // pending when the test ends.
  Future<void> teardown(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('lockOverride open → "Editing open" chip (test bed)',
      (tester) async {
    await pumpChip(tester,
        override: FantasyLockOverride.open,
        now: DateTime.utc(2026, 8, 1)); // even with the season over
    expect(find.text('Editing open'), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('open gameweek → countdown PLUS absolute league-time lock',
      (tester) async {
    await pumpChip(tester,
        override: FantasyLockOverride.auto,
        now: DateTime.utc(2026, 7, 3, 12)); // 2d 10h before GW1 lock
    expect(find.text('GW1 locks in 2d 10h'), findsOneWidget);
    expect(find.text('Sun, Jul 5 · 3:00 PM'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('match day after lock → locked face with the absolute time',
      (tester) async {
    await pumpChip(tester,
        override: FantasyLockOverride.auto,
        now: DateTime.utc(2026, 7, 5, 23));
    expect(find.text('GW1 locked'), findsOneWidget);
    expect(find.text('locked Sun, Jul 5 · 3:00 PM'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('season over → Season complete', (tester) async {
    await pumpChip(tester,
        override: FantasyLockOverride.auto, now: DateTime.utc(2026, 8, 1));
    expect(find.text('Season complete'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('lockOverride locked wins over an open gameweek',
      (tester) async {
    await pumpChip(tester,
        override: FantasyLockOverride.locked,
        now: DateTime.utc(2026, 7, 3, 12));
    expect(find.text('Locked by the league'), findsOneWidget);
    await teardown(tester);
  });
}
