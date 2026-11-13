import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault();
  // unsorted on purpose; typical futsal Sundays
  final dates = ['07122026', '06282026', '07052026'];

  test('derives ordered gameweeks, one per match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws.map((g) => g.number), [1, 2, 3]);
    expect(gws.map((g) => g.date), ['06282026', '07052026', '07122026']);
  });
  test('lock = 3PM league time on the match day (PDT in July)', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].lockUtc, DateTime.utc(2026, 6, 28, 22, 0));
  });
  test('status transitions', () {
    final gws = deriveGameweeks(dates, cfg);
    final gw2 = gws[1]; // Jul 5
    expect(gw2.statusAt(DateTime.utc(2026, 7, 3, 12)), GameweekStatus.open);
    expect(gw2.statusAt(DateTime.utc(2026, 7, 5, 23)), GameweekStatus.locked);
    expect(gw2.statusAt(DateTime.utc(2026, 6, 20)), GameweekStatus.upcoming);
  });
  test('gw1 opens immediately; later gws open after the previous match day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws[0].opensUtc, isNull);
    // gw2 opens Jun 29 00:00 league time = 07:00 UTC (PDT)
    expect(gws[1].opensUtc, DateTime.utc(2026, 6, 29, 7, 0));
  });
  test('current gameweek at a moment', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(currentGameweek(gws, DateTime.utc(2026, 7, 3))!.number, 2);
    expect(currentGameweek(gws, DateTime.utc(2026, 8, 1)), isNull);
  });
  test('no schedule: nothing is frozen, lock stays lockHour on the day', () {
    final gws = deriveGameweeks(dates, cfg);
    expect(gws.every((g) => !g.frozen), isTrue);
    expect(gws.map((g) => g.lockUtc), [
      DateTime.utc(2026, 6, 28, 22),
      DateTime.utc(2026, 7, 5, 22),
      DateTime.utc(2026, 7, 12, 22),
    ]);
  });
  test('a partial schedule falls back to the defaults for the rest', () {
    final gws = deriveGameweeks(
        dates, cfg, const GameweekSchedule(skippedDates: {'07052026'}));
    expect(gws.map((g) => g.date), ['06282026', '07122026']);
    expect(gws.map((g) => g.number), [1, 2]);
  });
  test('a frozen week keeps its stored lock even when the config moves', () {
    final moved = FantasyConfig.fromMap(
        {...FantasyConfig.futsalDefault().toMap(), 'lockHour': 9});
    final gws = deriveGameweeks(
        dates,
        moved,
        GameweekSchedule(lockedWeeks: {
          1: LockedWeek(
              date: '06282026',
              lockUtc: DateTime.utc(2026, 6, 28, 22),
              scored: true),
        }));
    expect(gws[0].frozen, isTrue);
    expect(gws[0].lockUtc, DateTime.utc(2026, 6, 28, 22));
    expect(gws[1].frozen, isFalse);
    expect(gws[1].lockUtc, DateTime.utc(2026, 7, 5, 16)); // 9 AM PDT
  });

  group('legacyKickoffHHmm [S2]', () {
    test('reads start hour + index as PM, clamped to 23:00', () {
      expect(legacyKickoffHHmm(5, 0), '17:00');
      expect(legacyKickoffHHmm(2, 1), '15:00');
      expect(legacyKickoffHHmm(11, 2), '13:00'); // 13 is not < 12: no +12
      expect(legacyKickoffHHmm(10, 15), '23:00'); // 25 -> clamp
    });
    test('no start hour -> null', () {
      expect(legacyKickoffHHmm(0, 0), isNull);
      expect(legacyKickoffHHmm(-3, 4), isNull);
    });
  });

  group('value equality', () {
    LockedWeek week({String date = '10042026', int hour = 23, bool scored = false}) =>
        LockedWeek(
            date: date, lockUtc: DateTime.utc(2026, 10, 4, hour), scored: scored);

    test('LockedWeek', () {
      expect(week(), week());
      expect(week().hashCode, week().hashCode);
      expect(week().scored, isFalse);
      expect(week() == week(scored: true), isFalse);
      expect(week() == week(date: '10112026'), isFalse);
      expect(week() == week(hour: 22), isFalse);
    });

    ScheduleOverrides overrides({
      Set<String> skipped = const {'10112026'},
      int deadlineHour = 20,
      int minutes = 45,
    }) =>
        ScheduleOverrides(
          skippedDates: skipped,
          deadlineOverrides: {'10182026': DateTime.utc(2026, 10, 18, deadlineHour)},
          minutesBeforeKickoff: minutes,
        );

    test('ScheduleOverrides', () {
      expect(overrides(), overrides());
      expect(overrides().hashCode, overrides().hashCode);
      expect(const ScheduleOverrides(), const ScheduleOverrides());
      expect(const ScheduleOverrides().minutesBeforeKickoff, 60);
      expect(overrides() == const ScheduleOverrides(), isFalse);
      expect(overrides() == overrides(deadlineHour: 21), isFalse);
      expect(overrides() == overrides(minutes: 60), isFalse);
      expect(overrides() == overrides(skipped: {'10112026', '10182026'}), isFalse);
    });
  });

  // The cross-engine contract: the TS twin replays the SAME file
  // (functions/src/lib/fantasy/golden_schedule.test.ts). Expectations were
  // hand-computed before either engine ran.
  group('golden_schedule', () {
    final fixture = jsonDecode(
            File('test/fantasy/fixtures/golden_schedule.json')
                .readAsStringSync())
        as Map<String, dynamic>;
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

    DateTime iso(String s) => DateTime.parse(s);

    GameweekSchedule scheduleOf(
        Map<String, dynamic>? b, Map<String, DateTime> fromNode) {
      final block = b ?? const <String, dynamic>{};
      final locked = <int, LockedWeek>{};
      (block['lockedWeeks'] as Map<String, dynamic>? ?? const {})
          .forEach((n, w) {
        final m = w as Map<String, dynamic>;
        locked[int.parse(n)] = LockedWeek(
          date: m['date'] as String,
          lockUtc: iso(m['lockUtc'] as String),
          scored: m['scored'] == true,
        );
      });
      Map<String, DateTime> instants(String key) => {
            for (final e
                in (block[key] as Map<String, dynamic>? ?? const {}).entries)
              e.key: iso(e.value as String),
          };
      return GameweekSchedule(
        lockedWeeks: locked,
        skippedDates: {
          for (final d in (block['skippedDates'] as List? ?? const []))
            d as String,
        },
        deadlineOverrides: instants('deadlineOverrides'),
        // dateNode-derived kickoffs, merged under any explicit ones.
        firstKickoffUtc: {...fromNode, ...instants('firstKickoffUtc')},
        minutesBeforeKickoff: (block['minutesBeforeKickoff'] as int?) ?? 60,
      );
    }

    test('fixture carries the expected cases', () {
      expect(
          cases.map((c) => c['name']),
          containsAll([
            'plain', 'skipped', 'override', 'early kickoff', 'late kickoff',
            'frozen, day gone', 'frozen, past day inserted', 'gap in frozen',
            'override beats kickoff', 'legacy start time',
          ]));
    });

    for (final c in cases) {
      test(c['name'] as String, () {
        final fromNode = c['dateNode'] == null
            ? const <String, DateTime>{}
            : firstKickoffByDateFromNode(c['dateNode'],
                startHour: (c['startHour'] as int?) ?? 0);
        final schedule =
            scheduleOf(c['schedule'] as Map<String, dynamic>?, fromNode);
        final caseCfg = FantasyConfig.fromMap({
          ...FantasyConfig.futsalDefault().toMap(),
          'lockHour': c['lockHour'],
        });
        final gws = deriveGameweeks(
            (c['dates'] as List).cast<String>(), caseCfg, schedule);
        final expected = (c['expected'] as List).cast<Map<String, dynamic>>();
        expect(gws.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          final e = expected[i];
          final g = gws[i];
          expect(g.number, e['number'], reason: 'number @$i');
          expect(g.date, e['date'], reason: 'date @$i');
          expect(g.lockUtc, iso(e['lockUtc'] as String),
              reason: 'lockUtc @$i');
          expect(g.opensUtc,
              e['opensUtc'] == null ? isNull : iso(e['opensUtc'] as String),
              reason: 'opensUtc @$i');
          expect(g.frozen, e['frozen'], reason: 'frozen @$i');
        }
      });
    }
  });
}
