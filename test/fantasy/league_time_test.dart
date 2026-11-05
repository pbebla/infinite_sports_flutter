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
  test('leagueInstantUtc keeps minute precision with the DST rule of the day',
      () {
    // Oct 11 2026 is PDT (UTC-7): 3:30PM local = 22:30 UTC
    expect(leagueInstantUtc('10112026', 15, 30),
        DateTime.utc(2026, 10, 11, 22, 30));
    // Nov 1 2026 is PST (UTC-8): 3:30PM local = 23:30 UTC
    expect(leagueInstantUtc('11012026', 15, 30),
        DateTime.utc(2026, 11, 1, 23, 30));
    // late evening rolls into the next UTC day
    expect(leagueInstantUtc('10112026', 20, 15),
        DateTime.utc(2026, 10, 12, 3, 15));
  });
  test('lockInstantUtc is leagueInstantUtc on the hour', () {
    for (final d in ['01152026', '03072026', '03082026', '07122026', '11012026']) {
      for (final h in [0, 9, 15, 23]) {
        expect(lockInstantUtc(d, hour: h), leagueInstantUtc(d, h, 0));
      }
    }
  });
}
