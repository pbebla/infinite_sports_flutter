// Port of test/fantasy/gameweeks_test.dart.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import {
  currentGameweek, deriveGameweeks, gameweekStatusAt,
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
});
