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
