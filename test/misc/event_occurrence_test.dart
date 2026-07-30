import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/calendar_sources.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/model/event.dart';

Event _legacy(String title, DateTime? when) {
  final e = Event();
  e.title = title;
  e.eventDateTime = when;
  return e;
}

Event _v2(String title, {
  required DateTime start,
  DateTime? end,
  String? repeatFreq,
  DateTime? repeatUntil,
  String? category,
}) {
  final e = Event();
  e.title = title;
  e.id = 'id-$title';
  e.eventDateTime = start;
  e.startDate = start;
  e.endDate = end;
  e.repeatFreq = repeatFreq;
  e.repeatUntil = repeatUntil;
  e.category = category;
  return e;
}

void main() {
  group('occurrenceDays', () {
    test('legacy single-date event occupies exactly its day', () {
      final days = occurrenceDays(_legacy('x', DateTime(2026, 7, 20, 18)));
      expect(days, [DateTime(2026, 7, 20)]);
    });

    test('date range covers every day start through end inclusive', () {
      final days = occurrenceDays(_v2('weekend',
          start: DateTime(2026, 8, 7), end: DateTime(2026, 8, 9)));
      expect(days, [
        DateTime(2026, 8, 7),
        DateTime(2026, 8, 8),
        DateTime(2026, 8, 9),
      ]);
    });

    test('backwards range degrades to the start day', () {
      final days = occurrenceDays(_v2('oops',
          start: DateTime(2026, 8, 7), end: DateTime(2026, 8, 1)));
      expect(days, [DateTime(2026, 8, 7)]);
    });

    test('weekly repeat lands on the same weekday until the until date inclusive', () {
      // Sundays: Jul 19, 26, Aug 2 — until Aug 2 inclusive.
      final days = occurrenceDays(_v2('futsal sundays',
          start: DateTime(2026, 7, 19),
          repeatFreq: 'weekly',
          repeatUntil: DateTime(2026, 8, 2)));
      expect(days, [
        DateTime(2026, 7, 19),
        DateTime(2026, 7, 26),
        DateTime(2026, 8, 2),
      ]);
    });

    test('weekly repeating range repeats the whole block', () {
      // Fri-Sat block repeating weekly until the second Friday: second Sat
      // is past until, so it is trimmed.
      final days = occurrenceDays(_v2('camp',
          start: DateTime(2026, 7, 17),
          end: DateTime(2026, 7, 18),
          repeatFreq: 'weekly',
          repeatUntil: DateTime(2026, 7, 24)));
      expect(days, [
        DateTime(2026, 7, 17),
        DateTime(2026, 7, 18),
        DateTime(2026, 7, 24),
      ]);
    });

    test('expansion is capped so bad data cannot explode the calendar', () {
      final days = occurrenceDays(_v2('forever',
          start: DateTime(2026, 1, 1),
          repeatFreq: 'weekly',
          repeatUntil: DateTime(2099, 1, 1)));
      expect(days.length, lessThanOrEqualTo(54));
    });

    test('event with no parseable date has no occurrences', () {
      expect(occurrenceDays(_legacy('broken', null)), isEmpty);
    });
  });

  group('eventsByDay with occurrences', () {
    test('a range event appears under every day it covers', () {
      final byDay = eventsByDay([
        _v2('weekend', start: DateTime(2026, 8, 7), end: DateTime(2026, 8, 8)),
        _legacy('same day', DateTime(2026, 8, 7)),
      ]);
      expect(byDay[DateTime(2026, 8, 7)]!.length, 2);
      expect(byDay[DateTime(2026, 8, 8)]!.single.event!.title, 'weekend');
    });

    test('entries know when their event is fully past', () {
      final byDay = eventsByDay([
        _v2('over', start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 2)),
        _v2('ongoing', start: DateTime(2026, 7, 1), end: DateTime(2026, 7, 20)),
      ]);
      final today = DateTime(2026, 7, 13);
      final entries = byDay[DateTime(2026, 7, 1)]!;
      expect(entries[0].isPastOn(today), isTrue);
      expect(entries[1].isPastOn(today), isFalse,
          reason: 'still running through Jul 20, so not past');
    });

    test('entries carry legacy index for old events and v2 id for new ones', () {
      final byDay = eventsByDay([
        _legacy('old', DateTime(2026, 8, 7)),
        _v2('new', start: DateTime(2026, 8, 7)),
      ]);
      final entries = byDay[DateTime(2026, 8, 7)]!;
      expect(entries[0].legacyIndex, 0);
      expect(entries[0].v2Id, isNull);
      expect(entries[1].v2Id, 'id-new');
      expect(entries[1].legacyIndex, isNull);
    });
  });

  group('filterByCategories', () {
    Map<DateTime, List<CalendarEntry>> byDay() => eventsByDay([
          _v2('futsal', start: DateTime(2026, 8, 7), category: 'Futsal'),
          _v2('hoop', start: DateTime(2026, 8, 7), category: 'Basketball'),
          _legacy('uncategorized', DateTime(2026, 8, 7)),
        ]);

    test('empty selection means everything shows', () {
      final filtered = filterByCategories(byDay(), const {});
      expect(filtered[DateTime(2026, 8, 7)]!.length, 3);
    });

    test('selecting categories keeps matches and drops days left empty', () {
      final filtered = filterByCategories(byDay(), const {'Futsal'});
      expect(filtered[DateTime(2026, 8, 7)]!.single.event!.title, 'futsal');
      final none = filterByCategories(byDay(), const {'Soccer'});
      expect(none.containsKey(DateTime(2026, 8, 7)), isFalse);
    });

    test('uncategorized legacy events show under Community', () {
      final filtered = filterByCategories(byDay(), const {'Community'});
      expect(filtered[DateTime(2026, 8, 7)]!.single.event!.title, 'uncategorized');
    });
  });

  group('filterByCategories across events, tournament days and league days '
      '(calendar filter scope addition)', () {
    // Same day, four entries: a Basketball tournament day, a Flag Football
    // tournament day, a Futsal league day, a Basketball league day, plus a
    // Basketball-categorized event — every kind the calendar merges.
    Map<DateTime, List<CalendarEntry>> mixedByDay() {
      final basketballTournament = tournamentDaysFrom({
        'bball-cup': {
          'Name': 'Bball Cup',
          'Sport': 'Basketball',
          'Matches': {'m1': {'date': '08072026'}},
        },
      });
      final flagFootballTournament = tournamentDaysFrom({
        'ff-cup': {
          'Name': 'FF Cup',
          'Sport': 'Flag Football',
          'Matches': {'m1': {'date': '08072026'}},
        },
      });
      final futsalLeague =
          leagueDaysFrom('Futsal', '16', {'08072026': 1});
      final basketballLeague =
          leagueDaysFrom('Basketball', '4', {'08072026': 1});
      final basketballEvent = eventsByDay([
        _v2('hoop night', start: DateTime(2026, 8, 7), category: 'Basketball'),
      ]);
      return mergeDayMaps([
        basketballTournament,
        flagFootballTournament,
        futsalLeague,
        basketballLeague,
        basketballEvent,
      ]);
    }

    test('All (empty selection) includes every kind for the day', () {
      final filtered = filterByCategories(mixedByDay(), const {});
      expect(filtered[DateTime(2026, 8, 7)]!.length, 5);
    });

    test(
        'Basketball filter keeps ONLY Basketball tournament days, league '
        'days and events — never Flag Football or Futsal', () {
      final filtered = filterByCategories(mixedByDay(), const {'Basketball'});
      final kept = filtered[DateTime(2026, 8, 7)]!;
      expect(kept.length, 3);
      expect(kept.every((e) => e.sport == 'Basketball' || e.category == 'Basketball'),
          isTrue);
      expect(kept.any((e) => e.sport == 'Flag Football'), isFalse);
      expect(kept.any((e) => e.sport == 'Futsal'), isFalse);
      expect(kept.any((e) => e.kind == CalendarKind.tournament && e.sport == 'Basketball'),
          isTrue,
          reason: 'the Basketball tournament day must survive the filter');
      expect(kept.any((e) => e.kind == CalendarKind.league && e.sport == 'Basketball'),
          isTrue,
          reason: 'the Basketball league day must survive the filter');
    });

    test('Tournaments filter still shows every sport\'s tournament days '
        '(existing "all tournaments" bucket is unchanged)', () {
      final filtered = filterByCategories(mixedByDay(), const {'Tournaments'});
      final kept = filtered[DateTime(2026, 8, 7)]!;
      expect(kept.length, 2);
      expect(kept.every((e) => e.kind == CalendarKind.tournament), isTrue);
      expect(kept.map((e) => e.sport).toSet(), {'Basketball', 'Flag Football'});
    });
  });
}
