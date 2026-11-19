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
    List<Gameweek>? weeks,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FantasyDeadlineChip(
          gameweeks: weeks ?? gameweeks,
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

  // The week reopens at league midnight after the PREVIOUS game day, so the
  // chip names that weekday — not a hard-coded Monday. An upcoming week is
  // reachable once the league moves a deadline to before its game day began.
  group('upcoming week: "opens <weekday>" follows the real game day', () {
    // GW1 is Wednesday Nov 4 2026, its deadline moved to Tuesday 18:00 PST
    // (Nov 4 02:00 UTC); GW2 is the next Wednesday. GW2 opens at league
    // midnight after Nov 4: Thursday Nov 5 00:00 PST = 08:00 UTC.
    final weeks = deriveGameweeks(
      ['11042026', '11112026'],
      cfg,
      GameweekSchedule(
          deadlineOverrides: {'11042026': DateTime.utc(2026, 11, 4, 2)}),
    );

    testWidgets('chip says opens Thursday for a Wednesday game day',
        (tester) async {
      // Wednesday 20:00 PST: GW1's day is over (24 h past its moved lock) and
      // GW2 has not opened yet.
      await pumpChip(tester,
          weeks: weeks,
          override: FantasyLockOverride.auto,
          now: DateTime.utc(2026, 11, 5, 4));
      expect(find.text('GW2 opens Thursday'), findsOneWidget);
      expect(find.text('GW2 opens Monday'), findsNothing);
      // The line under it is the REAL deadline of that week.
      expect(find.text('locks Wed, Nov 11 · 3:00 PM'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a Sunday game day still reads Monday', (tester) async {
      // GW1 Sun Nov 8, deadline moved to Saturday 10:00 PST (18:00 UTC);
      // GW2 the Sunday after opens Mon Nov 9 00:00 PST = 08:00 UTC.
      final sunday = deriveGameweeks(
        ['11082026', '11152026'],
        cfg,
        GameweekSchedule(
            deadlineOverrides: {'11082026': DateTime.utc(2026, 11, 7, 18)}),
      );
      await pumpChip(tester,
          weeks: sunday,
          override: FantasyLockOverride.auto,
          now: DateTime.utc(2026, 11, 9, 4)); // Sunday 20:00 PST
      expect(find.text('GW2 opens Monday'), findsOneWidget);
      await teardown(tester);
    });
  });

  testWidgets('the deadline text follows the lock instant across a clock '
      'change (Nov 1 2026, fall back)', (tester) async {
    // A deadline moved onto Sunday Nov 1 16:00 PST (00:00 UTC Nov 2) for a
    // game day dated BEFORE the change. Reading the offset off the match date
    // would show 5:00 PM.
    final moved = deriveGameweeks(
      ['10312026'],
      cfg,
      GameweekSchedule(
          deadlineOverrides: {'10312026': DateTime.utc(2026, 11, 2)}),
    );
    await pumpChip(tester,
        weeks: moved,
        override: FantasyLockOverride.auto,
        now: DateTime.utc(2026, 11, 1, 12));
    expect(find.text('Sun, Nov 1 · 4:00 PM'), findsOneWidget);
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

  // Release report #8: the hub header collapses to a slim one-line bar that
  // keeps the deadline visible. ONE clock drives both faces (no second
  // timer), and the slim line reads the same face logic as the chip.
  group('slim face (collapsed hub header)', () {
    final lock = DateTime.utc(2026, 7, 5, 22); // GW1 lock

    test('counting: "GW1 locks in" + a D HH:MM:SS countdown', () {
      final f = deadlineSlimFace(gameweeks, FantasyLockOverride.auto,
          lock.subtract(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)));
      expect(f.label, 'GW1 locks in');
      expect(f.countdown, '2d 03:04:05');
      expect(f.icon, Icons.timer_outlined);
    });

    test('under a day: HH:MM:SS, no day part', () {
      final f = deadlineSlimFace(gameweeks, FantasyLockOverride.auto,
          lock.subtract(const Duration(minutes: 7, seconds: 1)));
      expect(f.countdown, '00:07:01');
    });

    test('league override open: the GW label + "Editing open"', () {
      final f = deadlineSlimFace(gameweeks, FantasyLockOverride.open,
          DateTime.utc(2026, 7, 3, 12));
      expect(f.label, 'GW1 · Editing open');
      expect(f.countdown, isNull);
      expect(f.icon, Icons.lock_open);
    });

    test('league override locked / locked week / season over', () {
      expect(
          deadlineSlimFace(gameweeks, FantasyLockOverride.locked,
                  DateTime.utc(2026, 7, 3, 12))
              .label,
          'GW1 · Locked by the league');
      expect(
          deadlineSlimFace(gameweeks, FantasyLockOverride.auto,
                  DateTime.utc(2026, 7, 5, 23))
              .label,
          'GW1 locked');
      expect(
          deadlineSlimFace(gameweeks, FantasyLockOverride.auto,
                  DateTime.utc(2026, 8, 1))
              .label,
          'Season complete');
    });

    testWidgets('one shared clock ticks the big countdown AND the slim line',
        (tester) async {
      var now = lock.subtract(const Duration(seconds: 10));
      final clock = FantasyDeadlineClock(nowUtc: () => now);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FantasyDeadlineCountdown(
              gameweeks: gameweeks,
              lockOverride: FantasyLockOverride.auto,
              clock: clock,
            ),
            FantasyDeadlineSlimLine(
              gameweeks: gameweeks,
              lockOverride: FantasyLockOverride.auto,
              clock: clock,
            ),
          ]),
        ),
      ));
      expect(find.text('10'), findsOneWidget); // the Sec box
      expect(find.text('00:00:10'), findsOneWidget); // the slim line
      now = lock.subtract(const Duration(seconds: 9));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('09'), findsOneWidget);
      expect(find.text('00:00:09'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      clock.dispose(); // cancels the one timer
    });
  });
}
