// Port of test/fantasy/league_time_test.dart — the DST boundary instants are
// part of the cross-engine contract (locks must fire at the same UTC moment
// the Dart engine shows managers).
import { describe, expect, it } from 'vitest';
import { leagueInstantUtc, lockInstantUtc, parseDbDate } from './league_time';

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
  it('leagueInstantUtc keeps minute precision with the DST rule of the day', () => {
    // Oct 11 2026 is PDT (UTC-7): 3:30PM local = 22:30 UTC
    expect(leagueInstantUtc('10112026', 15, 30).toISOString())
      .toBe('2026-10-11T22:30:00.000Z');
    // Nov 1 2026 is PST (UTC-8): 3:30PM local = 23:30 UTC
    expect(leagueInstantUtc('11012026', 15, 30).toISOString())
      .toBe('2026-11-01T23:30:00.000Z');
    // late evening rolls into the next UTC day
    expect(leagueInstantUtc('10112026', 20, 15).toISOString())
      .toBe('2026-10-12T03:15:00.000Z');
  });
  it('lockInstantUtc is leagueInstantUtc on the hour', () => {
    for (const d of ['01152026', '03072026', '03082026', '07122026', '11012026']) {
      for (const h of [0, 9, 15, 23]) {
        expect(lockInstantUtc(d, h).getTime())
          .toBe(leagueInstantUtc(d, h, 0).getTime());
      }
    }
  });
});
