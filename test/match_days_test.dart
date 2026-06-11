import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_days.dart';

void main() {
  group('sortedMatchDays', () {
    test('returns distinct days in ascending calendar order', () {
      final result = sortedMatchDays(['06012026', '05202026', '05292026']);
      expect(result, ['05202026', '05292026', '06012026']);
    });

    test('collapses duplicate days', () {
      final result =
          sortedMatchDays(['05292026', '05292026', '06012026']);
      expect(result, ['05292026', '06012026']);
    });

    test('ignores unparseable or wrong-length dates', () {
      final result =
          sortedMatchDays(['05292026', 'bad', '', '123', '06012026']);
      expect(result, ['05292026', '06012026']);
    });

    test('orders correctly across month and year boundaries', () {
      final result = sortedMatchDays(['01012027', '12312026', '12012026']);
      expect(result, ['12012026', '12312026', '01012027']);
    });

    test('returns an empty list for empty input', () {
      expect(sortedMatchDays([]), isEmpty);
    });

    test('returns a single day unchanged', () {
      expect(sortedMatchDays(['05292026']), ['05292026']);
    });
  });
}
