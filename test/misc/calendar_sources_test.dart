import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/calendar_sources.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';

void main() {
  group('tournamentDaysFrom', () {
    final node = {
      'Current Tournament': 'summer-cup',
      'summer-cup': {
        'Name': 'Summer Cup 2026',
        'Matches': {
          'm1': {'date': '08152026'},
          'm2': {'date': '08152026'},
          'm3': {'date': '08162026'},
          'bad': {'date': 'garbage'},
        },
      },
      'broken': 'not-a-map',
    };

    test('one entry per distinct day, pointer key skipped, bad dates ignored', () {
      final byDay = tournamentDaysFrom(node);
      expect(byDay.length, 2);
      final entry = byDay[DateTime(2026, 8, 15)]!.single;
      expect(entry.kind, CalendarKind.tournament);
      expect(entry.displayTitle, 'Summer Cup 2026');
      expect(entry.category, 'Tournaments');
      expect(entry.tournamentId, 'summer-cup');
    });

    test('whole tournament stays current until its last day passes', () {
      final byDay = tournamentDaysFrom(node);
      final firstDay = byDay[DateTime(2026, 8, 15)]!.single;
      // Aug 16 is the last day: on Aug 16 nothing is past yet.
      expect(firstDay.isPastOn(DateTime(2026, 8, 16)), isFalse);
      expect(firstDay.isPastOn(DateTime(2026, 8, 17)), isTrue);
    });

    test('non-map input yields nothing', () {
      expect(tournamentDaysFrom(null), isEmpty);
      expect(tournamentDaysFrom('x'), isEmpty);
    });
  });

  group('tournamentDaysFrom StartDate/EndDate fallback (TAS.3 Task 1)', () {
    test('no Matches node at all falls back to StartDate..EndDate range', () {
      final byDay = tournamentDaysFrom({
        'new-cup': {
          'Name': 'Brand New Cup',
          'StartDate': '08012026',
          'EndDate': '08032026',
        },
      });
      expect(byDay.length, 3);
      for (final day in [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 3),
      ]) {
        final entry = byDay[day]!.single;
        expect(entry.kind, CalendarKind.tournament);
        expect(entry.displayTitle, 'Brand New Cup');
        expect(entry.tournamentId, 'new-cup');
        // Whole range keeps the tournament current until Aug 3 passes.
        expect(entry.lastDay, DateTime(2026, 8, 3));
      }
    });

    test('Matches present but empty falls back to StartDate..EndDate', () {
      final byDay = tournamentDaysFrom({
        'empty-cup': {
          'Name': 'Empty Bracket Cup',
          'Matches': <String, dynamic>{},
          'StartDate': '09012026',
          'EndDate': '09022026',
        },
      });
      expect(byDay.length, 2);
      expect(byDay.containsKey(DateTime(2026, 9, 1)), isTrue);
      expect(byDay.containsKey(DateTime(2026, 9, 2)), isTrue);
    });

    test('Matches present but none parse falls back to StartDate..EndDate', () {
      final byDay = tournamentDaysFrom({
        'garbage-cup': {
          'Name': 'Garbage Dates Cup',
          'Matches': {
            'm1': {'date': 'not-a-date'},
          },
          'StartDate': '10012026',
          'EndDate': '10012026',
        },
      });
      expect(byDay.length, 1);
      expect(byDay[DateTime(2026, 10, 1)]!.single.displayTitle,
          'Garbage Dates Cup');
    });

    test('only StartDate parses (no EndDate) uses just that one day', () {
      final byDay = tournamentDaysFrom({
        'solo-day-cup': {
          'Name': 'Solo Day Cup',
          'StartDate': '11052026',
        },
      });
      expect(byDay.length, 1);
      expect(byDay[DateTime(2026, 11, 5)]!.single.tournamentId,
          'solo-day-cup');
    });

    test('EndDate does not parse falls back to StartDate-only single day', () {
      final byDay = tournamentDaysFrom({
        'bad-end-cup': {
          'Name': 'Bad End Cup',
          'StartDate': '12012026',
          'EndDate': 'garbage',
        },
      });
      expect(byDay.length, 1);
      expect(byDay.containsKey(DateTime(2026, 12, 1)), isTrue);
    });

    test('EndDate before StartDate collapses to StartDate-only single day',
        () {
      final byDay = tournamentDaysFrom({
        'reversed-cup': {
          'Name': 'Reversed Cup',
          'StartDate': '12102026',
          'EndDate': '12052026',
        },
      });
      expect(byDay.length, 1);
      expect(byDay.containsKey(DateTime(2026, 12, 10)), isTrue);
    });

    test('range longer than 14 days is capped as a sanity guard', () {
      final byDay = tournamentDaysFrom({
        'marathon-cup': {
          'Name': 'Marathon Cup',
          'StartDate': '01012027',
          'EndDate': '02282027',
        },
      });
      expect(byDay.length, 14);
      expect(byDay.containsKey(DateTime(2027, 1, 1)), isTrue);
      expect(byDay.containsKey(DateTime(2027, 1, 14)), isTrue);
      expect(byDay.containsKey(DateTime(2027, 1, 15)), isFalse);
    });

    test('StartDate does not parse yields no entry at all (no data to show)',
        () {
      final byDay = tournamentDaysFrom({
        'no-dates-cup': {
          'Name': 'No Dates Cup',
        },
      });
      expect(byDay, isEmpty);
    });

    test('dated matches win over StartDate/EndDate — no double counting', () {
      final byDay = tournamentDaysFrom({
        'summer-cup': {
          'Name': 'Summer Cup 2026',
          'Matches': {
            'm1': {'date': '08152026'},
            'm2': {'date': '08162026'},
          },
          // A much wider header range that would add many more days if the
          // fallback fired — it must NOT fire since dated matches exist.
          'StartDate': '08012026',
          'EndDate': '08312026',
        },
      });
      expect(byDay.length, 2);
      expect(byDay.containsKey(DateTime(2026, 8, 15)), isTrue);
      expect(byDay.containsKey(DateTime(2026, 8, 16)), isTrue);
      expect(byDay.containsKey(DateTime(2026, 8, 1)), isFalse);
    });
  });

  group('leagueDaysFrom', () {
    test('one entry per date key under the sport category', () {
      final byDay = leagueDaysFrom('Futsal', '16', {
        '07262026': {'anything': 1},
        '08022026': {'anything': 1},
        'notadate': {'anything': 1},
      });
      expect(byDay.length, 2);
      final entry = byDay[DateTime(2026, 7, 26)]!.single;
      expect(entry.kind, CalendarKind.league);
      expect(entry.category, 'Futsal');
      expect(entry.sport, 'Futsal');
      expect(entry.season, '16');
      expect(entry.displayTitle, 'Futsal League');
      expect(entry.isPastOn(DateTime(2026, 7, 27)), isTrue);
    });

    test('unknown sport falls back to Community category', () {
      final byDay = leagueDaysFrom('AFC San Jose', '3', {'07262026': 1});
      expect(byDay[DateTime(2026, 7, 26)]!.single.category, kDefaultCategory);
    });
  });

  group('mergeDayMaps', () {
    test('concatenates entries that share a day', () {
      final a = leagueDaysFrom('Futsal', '16', {'07262026': 1});
      final b = tournamentDaysFrom({
        't1': {
          'Name': 'Cup',
          'Matches': {'m': {'date': '07262026'}},
        },
      });
      final merged = mergeDayMaps([a, b]);
      expect(merged[DateTime(2026, 7, 26)]!.length, 2);
    });
  });
}
