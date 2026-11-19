import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/futsal_periods.dart';

void main() {
  group('FutsalPeriod', () {
    test('keys and fromKey', () {
      expect(FutsalPeriod.firstHalf.key, '1H');
      expect(FutsalPeriod.halfTime.key, 'HT');
      expect(FutsalPeriod.secondHalf.key, '2H');
      expect(FutsalPeriod.extraTime.key, 'ET');
      expect(FutsalPeriod.fromKey('2H'), FutsalPeriod.secondHalf);
      expect(FutsalPeriod.fromKey('XX'), isNull);
      expect(FutsalPeriod.fromKey(null), isNull);
      expect(FutsalPeriod.fromKey(5), isNull);
    });
  });

  group('FutsalPeriodInfo.fromGame', () {
    test('reads Period and PeriodStarts', () {
      final info = FutsalPeriodInfo.fromGame({
        'Period': '2H',
        'PeriodStarts': {'2H': 2000, 'ET': 5000},
      });
      expect(info.period, FutsalPeriod.secondHalf);
      expect(info.secondHalfStartMs, 2000);
      expect(info.extraTimeStartMs, 5000);
    });
    test('tolerates missing and malformed values', () {
      final empty = FutsalPeriodInfo.fromGame({});
      expect(empty.period, isNull);
      expect(empty.secondHalfStartMs, isNull);
      final bad = FutsalPeriodInfo.fromGame({
        'Period': 7,
        'PeriodStarts': 'oops',
      });
      expect(bad.period, isNull);
      expect(bad.extraTimeStartMs, isNull);
      final partial = FutsalPeriodInfo.fromGame({
        'PeriodStarts': {'2H': 'x', 'ET': 9.0},
      });
      expect(partial.secondHalfStartMs, isNull);
      expect(partial.extraTimeStartMs, 9);
    });
  });

  group('foulPenaltyFor', () {
    test('table', () {
      expect(foulPenaltyFor(1), isA<FoulNone>());
      expect(foulPenaltyFor(4), isA<FoulNone>());
      expect(foulPenaltyFor(5), isA<FoulWarning>());
      expect(
        (foulPenaltyFor(6) as FoulManDown).duration,
        const Duration(minutes: 1),
      );
      expect(foulPenaltyFor(7), isA<FoulNone>());
      expect(
        (foulPenaltyFor(8) as FoulManDown).duration,
        const Duration(minutes: 1),
      );
      expect(foulPenaltyFor(9), isA<FoulNone>());
      expect(
        (foulPenaltyFor(10) as FoulManDown).duration,
        const Duration(minutes: 2),
      );
      expect(foulPenaltyFor(11), isA<FoulNone>());
      expect(
        (foulPenaltyFor(12) as FoulManDown).duration,
        const Duration(minutes: 2),
      );
      expect(
        (foulPenaltyFor(14) as FoulManDown).duration,
        const Duration(minutes: 2),
      );
    });
  });

  group('eventPeriod', () {
    const info = FutsalPeriodInfo(
      period: FutsalPeriod.secondHalf,
      secondHalfStartMs: 1000,
      extraTimeStartMs: 5000,
    );
    test('before the 2H start', () {
      expect(eventPeriod(999, info), FutsalPeriod.firstHalf);
    });
    test('exactly at the 2H start', () {
      expect(eventPeriod(1000, info), FutsalPeriod.secondHalf);
    });
    test('after the ET start', () {
      expect(eventPeriod(5000, info), FutsalPeriod.extraTime);
      expect(eventPeriod(9000, info), FutsalPeriod.extraTime);
    });
    test('null _t is 1st half', () {
      expect(eventPeriod(null, info), FutsalPeriod.firstHalf);
    });
    test('no starts at all is 1st half', () {
      expect(
        eventPeriod(9999, const FutsalPeriodInfo()),
        FutsalPeriod.firstHalf,
      );
    });
  });

  group('teamFoulsShown', () {
    Map<String, Object?> foul(int t, [String type = 'Foul', String p = 'A']) =>
        {type: p, '_t': t};

    List<Object?> bucket() => [
      foul(100), // 1H
      foul(200, 'foul', 'Guest'), // 1H, lower-case type
      foul(300, 'Yellow'), // not a foul
      foul(400, 'Save'),
      foul(500, 'Goal'),
      foul(1500), // during half time -> 1H (HT before 2H start)
      foul(2100), // 2H
      foul(2200, 'Foul', 'Guest'), // 2H
      foul(5100), // ET
    ];

    FutsalPeriodInfo info(FutsalPeriod? p, {int? h2 = 2000, int? et = 5000}) =>
        FutsalPeriodInfo(
          period: p,
          secondHalfStartMs: h2,
          extraTimeStartMs: et,
        );

    Object? activity() => {
      '3': bucket().sublist(0, 4),
      '10': bucket().sublist(4),
    };

    test('1H counts only 1st half', () {
      expect(teamFoulsShown(activity(), info(FutsalPeriod.firstHalf)), 3);
    });
    test('HT shows the 1st-half count', () {
      expect(teamFoulsShown(activity(), info(FutsalPeriod.halfTime)), 3);
    });
    test('2H counts only 2nd half', () {
      expect(teamFoulsShown(activity(), info(FutsalPeriod.secondHalf)), 2);
    });
    test('2H starting with no fouls is 0', () {
      final a = {
        '1': [foul(100)],
      };
      expect(teamFoulsShown(a, info(FutsalPeriod.secondHalf)), 0);
    });
    test('ET is 2nd half plus extra time', () {
      expect(teamFoulsShown(activity(), info(FutsalPeriod.extraTime)), 3);
    });
    test('null period gives 0', () {
      expect(teamFoulsShown(activity(), info(null)), 0);
    });
    test('null / odd activity gives 0', () {
      expect(teamFoulsShown(null, info(FutsalPeriod.firstHalf)), 0);
      expect(teamFoulsShown('x', info(FutsalPeriod.firstHalf)), 0);
    });
    test('List bucket and Map bucket agree', () {
      final asList = {
        '4': [foul(100), foul(2100)],
      };
      final asMap = {
        '4': {'-a': foul(100), '-b': foul(2100)},
      };
      for (final p in FutsalPeriod.values) {
        expect(teamFoulsShown(asMap, info(p)), teamFoulsShown(asList, info(p)));
      }
      expect(teamFoulsShown(asMap, info(FutsalPeriod.secondHalf)), 1);
    });
    test('top-level list of buckets works', () {
      final a = [
        null,
        [foul(100)],
        [foul(200)],
      ];
      expect(teamFoulsShown(a, info(FutsalPeriod.firstHalf)), 2);
    });
    test('_t key first in the leaf does not hide the event', () {
      final a = {
        '1': [
          {'_t': 100, 'Foul': 'A'},
        ],
      };
      expect(teamFoulsShown(a, info(FutsalPeriod.firstHalf)), 1);
    });
  });

  group('man-down', () {
    test('manDownForCard', () {
      expect(manDownForCard('Yellow'), const Duration(minutes: 1));
      expect(manDownForCard('SecondYellow'), const Duration(minutes: 1));
      expect(manDownForCard('Red'), const Duration(minutes: 2));
      expect(manDownForCard('Foul'), isNull);
    });
    test('manDownRemainingMs', () {
      int r(int clock) => manDownRemainingMs(
        durationMs: 60000,
        startElapsedMs: 10000,
        clockElapsedMs: clock,
      );
      expect(r(10000), 60000);
      expect(r(40000), 30000);
      expect(r(70000), 0);
      expect(r(200000), 0);
      expect(r(5000), 60000); // negative difference clamps to full
    });
  });

  group('rule edges', () {
    test('a bad man-down duration gives 0', () {
      expect(
        manDownRemainingMs(
          durationMs: -5,
          startElapsedMs: 0,
          clockElapsedMs: 10,
        ),
        0,
      );
      expect(
        manDownRemainingMs(
          durationMs: 0,
          startElapsedMs: 0,
          clockElapsedMs: 10,
        ),
        0,
      );
    });
    test('Fouls and foul play are not counted', () {
      final a = {
        '1': [
          {'Fouls': 'A', '_t': 100},
          {'foul play': 'A', '_t': 100},
          {'Foul': 'A', '_t': 100},
        ],
      };
      expect(
        teamFoulsShown(
          a,
          const FutsalPeriodInfo(period: FutsalPeriod.firstHalf),
        ),
        1,
      );
    });
    test('foulPenaltyFor(0) and (-2) are none', () {
      expect(foulPenaltyFor(0), isA<FoulNone>());
      expect(foulPenaltyFor(-2), isA<FoulNone>());
    });
    test('an ET start with no 2H start', () {
      const info = FutsalPeriodInfo(extraTimeStartMs: 5000);
      expect(eventPeriod(4999, info), FutsalPeriod.firstHalf);
      expect(eventPeriod(5000, info), FutsalPeriod.extraTime);
      expect(eventPeriod(6000, info), FutsalPeriod.extraTime);
    });
    test('a string _t counts as the 1st half', () {
      final a = {
        '1': [
          {'Foul': 'A', '_t': '9999'},
        ],
      };
      const info = FutsalPeriodInfo(
        period: FutsalPeriod.secondHalf,
        secondHalfStartMs: 1000,
      );
      expect(teamFoulsShown(a, info), 0);
      expect(
        teamFoulsShown(
          a,
          const FutsalPeriodInfo(period: FutsalPeriod.firstHalf),
        ),
        1,
      );
    });
  });
}
