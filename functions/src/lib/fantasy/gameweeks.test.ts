// Port of test/fantasy/gameweeks_test.dart.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import {
  currentGameweek, deriveGameweeks, gameweekStatusAt, legacyKickoffHHmm,
} from './gameweeks';

const cfg = futsalDefault();
// unsorted on purpose; typical futsal Sundays
const dates = ['07122026', '06282026', '07052026'];

describe('gameweeks', () => {
  it('derives ordered gameweeks, one per match day', () => {
    const gws = deriveGameweeks(dates, cfg);
    expect(gws.map((g) => g.number)).toEqual([1, 2, 3]);
    expect(gws.map((g) => g.date))
      .toEqual(['06282026', '07052026', '07122026']);
  });
  it('lock = 3PM league time on the match day (PDT in July)', () => {
    const gws = deriveGameweeks(dates, cfg);
    expect(gws[0].lockUtc.toISOString()).toBe('2026-06-28T22:00:00.000Z');
  });
  it('status transitions', () => {
    const gws = deriveGameweeks(dates, cfg);
    const gw2 = gws[1]; // Jul 5
    expect(gameweekStatusAt(gw2, new Date(Date.UTC(2026, 6, 3, 12))))
      .toBe('open');
    expect(gameweekStatusAt(gw2, new Date(Date.UTC(2026, 6, 5, 23))))
      .toBe('locked');
    expect(gameweekStatusAt(gw2, new Date(Date.UTC(2026, 5, 20))))
      .toBe('upcoming');
  });
  it('gw1 opens immediately; later gws open after the previous match day', () => {
    const gws = deriveGameweeks(dates, cfg);
    expect(gws[0].opensUtc).toBeNull();
    // gw2 opens Jun 29 00:00 league time = 07:00 UTC (PDT)
    expect(gws[1].opensUtc!.toISOString()).toBe('2026-06-29T07:00:00.000Z');
  });
  it('current gameweek at a moment', () => {
    const gws = deriveGameweeks(dates, cfg);
    expect(currentGameweek(gws, new Date(Date.UTC(2026, 6, 3)))!.number)
      .toBe(2);
    expect(currentGameweek(gws, new Date(Date.UTC(2026, 7, 1)))).toBeNull();
  });

  it('no schedule: nothing is frozen, lock stays lockHour on the day', () => {
    const gws = deriveGameweeks(dates, cfg);
    expect(gws.every((g) => g.frozen === false)).toBe(true);
    expect(gws.map((g) => g.lockUtc.toISOString())).toEqual([
      '2026-06-28T22:00:00.000Z', '2026-07-05T22:00:00.000Z',
      '2026-07-12T22:00:00.000Z',
    ]);
  });
  it('a partial schedule falls back to the defaults for the rest', () => {
    const gws = deriveGameweeks(dates, cfg, {
      skippedDates: new Set(['07052026']),
    });
    expect(gws.map((g) => g.date)).toEqual(['06282026', '07122026']);
    expect(gws.map((g) => g.number)).toEqual([1, 2]);
  });
  it('a frozen week keeps its stored lock even when the config moves', () => {
    const gws = deriveGameweeks(dates, { ...cfg, lockHour: 9 }, {
      lockedWeeks: {
        1: {
          date: '06282026',
          lockUtc: new Date('2026-06-28T22:00:00Z'),
          scored: true,
        },
      },
    });
    expect(gws[0].frozen).toBe(true);
    expect(gws[0].lockUtc.toISOString()).toBe('2026-06-28T22:00:00.000Z');
    expect(gws[1].frozen).toBe(false);
    expect(gws[1].lockUtc.toISOString()).toBe('2026-07-05T16:00:00.000Z');
  });
});

describe('legacyKickoffHHmm [S2]', () => {
  it('reads start hour + index as PM, clamped to 23:00', () => {
    expect(legacyKickoffHHmm(5, 0)).toBe('17:00');
    expect(legacyKickoffHHmm(2, 1)).toBe('15:00');
    expect(legacyKickoffHHmm(11, 2)).toBe('13:00'); // 13 is not < 12: no +12
    expect(legacyKickoffHHmm(10, 15)).toBe('23:00'); // 25 -> clamp
  });
  it('no start hour -> null', () => {
    expect(legacyKickoffHHmm(0, 0)).toBeNull();
    expect(legacyKickoffHHmm(-3, 4)).toBeNull();
  });
});
