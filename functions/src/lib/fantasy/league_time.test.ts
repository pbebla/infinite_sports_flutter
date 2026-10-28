// Port of test/fantasy/league_time_test.dart — the DST boundary instants are
// part of the cross-engine contract (locks must fire at the same UTC moment
// the Dart engine shows managers).
import { describe, expect, it } from 'vitest';
import { lockInstantUtc, parseDbDate } from './league_time';

describe('league_time', () => {
  it('PST offset in January', () => {
    // Jan 15 2026 is PST (UTC-8): 3PM local = 23:00 UTC
    expect(lockInstantUtc('01152026', 15).toISOString())
      .toBe('2026-01-15T23:00:00.000Z');
  });
  it('PDT offset in July', () => {
    // Jul 12 2026 is PDT (UTC-7): 3PM local = 22:00 UTC
    expect(lockInstantUtc('07122026', 15).toISOString())
      .toBe('2026-07-12T22:00:00.000Z');
  });
  it('DST start day 2026 (Mar 8) is PDT', () => {
    expect(lockInstantUtc('03082026', 15).toISOString())
      .toBe('2026-03-08T22:00:00.000Z');
  });
  it('day before DST start is PST', () => {
    expect(lockInstantUtc('03072026', 15).toISOString())
      .toBe('2026-03-07T23:00:00.000Z');
  });
  it('DST end day 2026 (Nov 1) is PST', () => {
    expect(lockInstantUtc('11012026', 15).toISOString())
      .toBe('2026-11-01T23:00:00.000Z');
  });
  it('parses MMDDYYYY', () => {
    const d = parseDbDate('05202026');
    expect([d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()])
      .toEqual([2026, 5, 20]);
  });
});
