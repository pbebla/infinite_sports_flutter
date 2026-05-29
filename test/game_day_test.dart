import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';

void main() {
  final now = DateTime(2026, 5, 29); // reference "today"

  group('currentGameDay', () {
    test('returns today when a match is scheduled today', () {
      final result =
          currentGameDay(['05202026', '05292026', '06012026'], now: now);
      expect(result, '05292026');
    });

    test('returns the earliest future date when nothing is today', () {
      final result =
          currentGameDay(['06152026', '06012026', '05202026'], now: now);
      expect(result, '06012026');
    });

    test('returns null when every date is in the past', () {
      final result = currentGameDay(['05202026', '05012026'], now: now);
      expect(result, isNull);
    });

    test('returns null for an empty list', () {
      expect(currentGameDay(const [], now: now), isNull);
    });

    test('ignores malformed date strings but still finds a valid one', () {
      final result = currentGameDay(['', 'abc', '123', '06012026'], now: now);
      expect(result, '06012026');
    });

    test('today wins even when listed after a future date', () {
      final result = currentGameDay(['06012026', '05292026'], now: now);
      expect(result, '05292026');
    });
  });
}
