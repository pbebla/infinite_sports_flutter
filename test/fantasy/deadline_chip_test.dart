// P3a Task 2 — deadline chip: league-timezone countdown with the absolute
// lock time always shown (spec §5), and the lockOverride faces. Plus the
// P3b Task 4 live countdown: D/H/M/S breakdown math and the ticking boxes
// that flip to the locked chip when the deadline crosses zero.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
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

  // ── P3b Task 4: the live countdown ─────────────────────────────────────

  group('countdownParts (pure breakdown math)', () {
    test('splits into days/hours/minutes/seconds', () {
      expect(
          countdownParts(
              const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
          (days: 2, hours: 3, minutes: 4, seconds: 5));
      // Carries roll correctly: 26h = 1d 2h.
      expect(countdownParts(const Duration(hours: 26)),
          (days: 1, hours: 2, minutes: 0, seconds: 0));
      expect(countdownParts(const Duration(seconds: 59)),
          (days: 0, hours: 0, minutes: 0, seconds: 59));
    });
    test('zero and crossing zero clamp to all zeros (locked face takes over)',
        () {
      expect(countdownParts(Duration.zero),
          (days: 0, hours: 0, minutes: 0, seconds: 0));
      expect(countdownParts(const Duration(seconds: -5)),
          (days: 0, hours: 0, minutes: 0, seconds: 0));
    });
    test('countdownDigits pads to two digits', () {
      expect(countdownDigits(4), '04');
      expect(countdownDigits(0), '00');
      expect(countdownDigits(59), '59');
      expect(countdownDigits(123), '123'); // long preseason, unpadded
    });
  });

  group('FantasyDeadlineCountdown', () {
    // GW1 locks 07052026 at 15:00 league time (PDT) = 22:00 UTC.
    final lock = DateTime.utc(2026, 7, 5, 22);

    Future<void> pumpCountdown(
        WidgetTester tester, DateTime Function() now,
        {FantasyLockOverride override = FantasyLockOverride.auto}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FantasyDeadlineCountdown(
            gameweeks: gameweeks,
            lockOverride: override,
            nowUtc: now,
          ),
        ),
      ));
    }

    testWidgets(
        'ticking D/H/M/S boxes + absolute line, flipping to the locked chip '
        'across zero', (tester) async {
      var now = lock
          .subtract(const Duration(days: 1, hours: 2, minutes: 3, seconds: 4));
      await pumpCountdown(tester, () => now);

      expect(find.byKey(const ValueKey('deadline_countdown')), findsOneWidget);
      expect(find.text('01'), findsOneWidget); // Days
      expect(find.text('02'), findsOneWidget); // Hours
      expect(find.text('03'), findsOneWidget); // Min
      expect(find.text('04'), findsOneWidget); // Sec
      expect(find.text('Days'), findsOneWidget);
      expect(find.text('Sec'), findsOneWidget);
      expect(find.text('GW1 deadline · Sun, Jul 5 · 3:00 PM'), findsOneWidget);

      // One periodic tick later the seconds move.
      now = lock.subtract(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00'), findsNWidgets(3));
      expect(find.text('02'), findsOneWidget);

      // Crossing zero: the next tick swaps the boxes for the locked chip.
      now = lock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('deadline_countdown')), findsNothing);
      expect(find.text('GW1 locked'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('league override keeps the "Editing open" chip, no boxes',
        (tester) async {
      await pumpCountdown(tester, () => DateTime.utc(2026, 7, 3, 12),
          override: FantasyLockOverride.open);
      expect(find.byKey(const ValueKey('deadline_countdown')), findsNothing);
      expect(find.text('Editing open'), findsOneWidget);
      expect(find.text('league override'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('season over falls back to the chip face', (tester) async {
      await pumpCountdown(tester, () => DateTime.utc(2026, 8, 1));
      expect(find.byKey(const ValueKey('deadline_countdown')), findsNothing);
      expect(find.text('Season complete'), findsOneWidget);
      await teardown(tester);
    });
  });
}
