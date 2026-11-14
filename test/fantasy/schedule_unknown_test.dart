// Review 6, I2: a failed schedule read is not a fact. With nothing cached,
// the feed used to fall back to an EMPTY schedule, and every face read that
// as "Season complete" (and My Team as "Locked") during a live season. The
// schedule is now three-way at the source — known / genuinely none (a real
// absent Config) / unknown (the read failed) — the feed re-subscribes on the
// same bounded back-off as the season-finished feed, and the deadline faces
// say "Deadline unavailable" instead of making a state up.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/deadline_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

List<Gameweek> _gws(int n) => [
      for (var i = 1; i <= n; i++)
        Gameweek(
          number: i,
          date: '10${(4 + 7 * (i - 1)).toString().padLeft(2, '0')}2026',
          lockUtc: DateTime.utc(2026, 10, 4 + 7 * (i - 1), 22),
          opensUtc: null,
        ),
    ];

FantasyConfigState _cfg() => FantasyConfigState(
      config: FantasyConfig.fromMap({'lockHour': 15}),
      lockOverride: FantasyLockOverride.auto,
    );

void main() {
  setUp(FantasyScheduleFeed.clearSessionCache);

  group('FantasyScheduleFeed: unknown ≠ empty', () {
    late StreamController<FantasyConfigState?> config;
    late List<StreamController<List<Gameweek>>> schedules;

    setUp(() {
      config = StreamController<FantasyConfigState?>.broadcast(sync: true);
      schedules = [];
    });
    tearDown(() => config.close());

    FantasyScheduleFeed<Object> feed() {
      final f = FantasyScheduleFeed<Object>(
        sport: 'Futsal',
        season: '15',
        owner: 'test',
        onChanged: () {},
        configStates: config.stream,
        gameweeksFor: (_, __) {
          final c = StreamController<List<Gameweek>>.broadcast(sync: true);
          schedules.add(c);
          return c.stream;
        },
      );
      addTearDown(f.dispose);
      return f..start();
    }

    testWidgets('a schedule error before any value: gates open on an empty '
        'list, but it is UNKNOWN; the feed re-subscribes and recovers',
        (tester) async {
      final f = feed();
      config.add(_cfg());
      expect(schedules, hasLength(1));
      schedules[0].addError(StateError('permission-denied'));
      expect(f.gameweeks, isEmpty);
      expect(f.scheduleUnknown, isTrue);

      await tester.pump(const Duration(seconds: 3));
      expect(schedules, hasLength(2), reason: 're-subscribed on the back-off');
      schedules[1].add(_gws(3));
      expect(f.scheduleUnknown, isFalse);
      expect(f.gameweeks, hasLength(3));
    });

    testWidgets('an error AFTER a real schedule keeps it (known)',
        (tester) async {
      final f = feed();
      config.add(_cfg());
      schedules[0].add(_gws(2));
      schedules[0].addError(StateError('blip'));
      expect(f.scheduleUnknown, isFalse);
      expect(f.gameweeks, hasLength(2));
      await tester.pump(const Duration(seconds: 3));
      expect(schedules, hasLength(2));
    });

    testWidgets('a Config error before any value: unknown, and the Config '
        'feed is re-subscribed', (tester) async {
      var listens = 0;
      final source = StreamController<FantasyConfigState?>.broadcast(
          sync: true, onListen: () => listens++);
      addTearDown(source.close);
      final f = FantasyScheduleFeed<Object>(
        sport: 'Futsal',
        season: '15',
        owner: 'test',
        onChanged: () {},
        configStates: source.stream,
        gameweeksFor: (_, __) {
          final c = StreamController<List<Gameweek>>.broadcast(sync: true);
          schedules.add(c);
          return c.stream;
        },
      )..start();
      addTearDown(f.dispose);
      source.addError(StateError('offline'));
      expect(f.scheduleUnknown, isTrue);
      expect(f.gameweeks, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(listens, 2);
      source.add(_cfg());
      schedules.last.add(_gws(1));
      expect(f.scheduleUnknown, isFalse);
    });

    testWidgets('retries are bounded', (tester) async {
      final f = feed();
      config.add(_cfg());
      for (var i = 0; i < 20; i++) {
        schedules.last.addError(StateError('down'));
        await tester.pump(const Duration(minutes: 5));
      }
      expect(f.scheduleUnknown, isTrue);
      expect(schedules.length, lessThanOrEqualTo(1 + kFantasyFeedRetryDelays.length));
    });

    testWidgets('a REAL absent Config is a fact: empty and known',
        (tester) async {
      final f = feed();
      config.add(null);
      expect(f.gameweeks, isEmpty);
      expect(f.scheduleUnknown, isFalse);
      expect(f.configAbsent, isTrue);
    });
  });

  group('faces', () {
    final now = DateTime.utc(2026, 10, 17, 12);

    test('the chip and the slim line: "Deadline unavailable" — never '
        '"Season complete" or "Locked"', () {
      final chip = deadlineChipFace(const [], FantasyLockOverride.auto, now,
          scheduleUnknown: true);
      expect(chip.title, 'Deadline unavailable');
      expect(chip.detail, isNull);
      final slim = deadlineSlimFace(const [], FantasyLockOverride.auto, now,
          scheduleUnknown: true);
      expect(slim.label, 'Deadline unavailable');
      expect(slim.countdown, isNull);
      // A genuinely finished season still says so.
      expect(
          deadlineChipFace(const [], FantasyLockOverride.auto, now).title,
          'Season complete');
    });

    test('the league override is a Config fact: still stated', () {
      expect(
          deadlineChipFace(const [], FantasyLockOverride.open, now,
                  scheduleUnknown: true)
              .title,
          'Editing open');
      expect(
          deadlineSlimFace(const [], FantasyLockOverride.locked, now,
                  scheduleUnknown: true)
              .label,
          'Locked by the league');
    });

    testWidgets('the big countdown and the slim line both say it',
        (tester) async {
      final clock = FantasyDeadlineClock(nowUtc: () => now);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FantasyDeadlineCountdown(
              gameweeks: const [],
              lockOverride: FantasyLockOverride.auto,
              clock: clock,
              scheduleUnknown: true,
            ),
            FantasyDeadlineSlimLine(
              gameweeks: const [],
              lockOverride: FantasyLockOverride.auto,
              clock: clock,
              scheduleUnknown: true,
            ),
          ]),
        ),
      ));
      expect(find.text('Deadline unavailable'), findsNWidgets(2));
      expect(find.text('Season complete'), findsNothing);
      expect(find.textContaining('ocked'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      clock.dispose();
    });
  });

  group('edit state', () {
    final now = DateTime.utc(2026, 10, 17, 12);

    test('three-way: open / locked / unknown — unknown only under the '
        'automatic lock', () {
      expect(
          squadEditState(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: _gws(5),
              nowUtc: now),
          SquadEditState.open);
      expect(
          squadEditState(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: const [],
              nowUtc: now,
              scheduleUnknown: true),
          SquadEditState.unknown);
      expect(
          squadEditState(
              lockOverride: FantasyLockOverride.open,
              gameweeks: const [],
              nowUtc: now,
              scheduleUnknown: true),
          SquadEditState.open);
      expect(
          squadEditState(
              lockOverride: FantasyLockOverride.auto,
              gameweeks: const [],
              nowUtc: now),
          SquadEditState.locked);
    });

    test('the market says it cannot check — never "Gameweek locked"', () {
      expect(
          marketAddReason(MarketAddAvailability.deadlineUnknown,
              FantasyPosition.att),
          'Can\'t check the deadline right now — try again in a moment.');
    });
  });
}
