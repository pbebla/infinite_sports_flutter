import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/engine/league_time.dart';

void main() {
  test('PST offset in January', () {
    // Jan 15 2026 is PST (UTC-8): 3PM local = 23:00 UTC
    expect(lockInstantUtc('01152026', hour: 15),
        DateTime.utc(2026, 1, 15, 23, 0));
  });
  test('PDT offset in July', () {
    // Jul 12 2026 is PDT (UTC-7): 3PM local = 22:00 UTC
    expect(lockInstantUtc('07122026', hour: 15),
        DateTime.utc(2026, 7, 12, 22, 0));
  });
  test('DST start day 2026 (Mar 8) is PDT', () {
    expect(lockInstantUtc('03082026', hour: 15),
        DateTime.utc(2026, 3, 8, 22, 0));
  });
  test('day before DST start is PST', () {
    expect(lockInstantUtc('03072026', hour: 15),
        DateTime.utc(2026, 3, 7, 23, 0));
  });
  test('DST end day 2026 (Nov 1) is PST', () {
    expect(lockInstantUtc('11012026', hour: 15),
        DateTime.utc(2026, 11, 1, 23, 0));
  });
  test('parses MMDDYYYY', () {
    final d = parseDbDate('05202026');
    expect([d.year, d.month, d.day], [2026, 5, 20]);
  });
}
