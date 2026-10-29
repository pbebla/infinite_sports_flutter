// RTDB-shape parsing for the fantasy jobs (P4) — the coercion-tolerance
// seams: list-coerced seasons/weeks, absent-only attendance, friendly
// filtering, market parsing.

import { describe, expect, it } from 'vitest';
import {
  allGamesFinal, childEntries, dateKeysOf, fantasySeasonsOf, fullAttendance,
  gamesOfDate, isVoidFlag, lockOverrideOf, marketPlayersOf, marketPricesOf,
  parseAbsentMap, rosterNamesOf, toIntLoose, voidedWeeksOf,
} from './orchestration_db';

describe('toIntLoose', () => {
  it('nums truncate, full int strings parse, junk is 0', () => {
    expect(toIntLoose(2)).toBe(2);
    expect(toIntLoose(2.9)).toBe(2);
    expect(toIntLoose('2')).toBe(2);
    expect(toIntLoose(' -3 ')).toBe(-3);
    expect(toIntLoose('2x')).toBe(0);
    expect(toIntLoose(null)).toBe(0);
  });
});

describe('childEntries', () => {
  it('maps pass through, null children skipped', () => {
    expect(childEntries({ a: 1, b: null, c: 2 }))
      .toEqual([['a', 1], ['c', 2]]);
  });
  it('list coercion: indexes become keys, holes skipped', () => {
    expect(childEntries([null, 'x', null, 'y']))
      .toEqual([['1', 'x'], ['3', 'y']]);
  });
  it('junk is empty', () => {
    expect(childEntries('nope')).toEqual([]);
    expect(childEntries(null)).toEqual([]);
  });
});

describe('fantasySeasonsOf', () => {
  it('finds Config-bearing seasons, tolerating list-coerced season keys', () => {
    const node = {
      Futsal: { 15: { Config: { lockHour: 15 } }, 14: { Players: {} } },
      // Small-int season keys list-coerce: index 3 = season "3".
      Basketball: [null, null, null, { Config: { lockHour: 18 } }],
      Junk: 'nope',
    };
    expect(fantasySeasonsOf(node)).toEqual([
      { sport: 'Futsal', season: '15', configNode: { lockHour: 15 } },
      { sport: 'Basketball', season: '3', configNode: { lockHour: 18 } },
    ]);
  });
  it('absent node = nothing enabled', () => {
    expect(fantasySeasonsOf(null)).toEqual([]);
  });
});

describe('lockOverrideOf', () => {
  it("absent/unknown = auto; 'open'/'locked' freeze", () => {
    expect(lockOverrideOf({ lockHour: 15 })).toBe('auto');
    expect(lockOverrideOf({ lockOverride: 'auto' })).toBe('auto');
    expect(lockOverrideOf({ lockOverride: 'weird' })).toBe('auto');
    expect(lockOverrideOf({ lockOverride: 'open' })).toBe('open');
    expect(lockOverrideOf({ lockOverride: 'locked' })).toBe('locked');
    expect(lockOverrideOf(null)).toBe('auto');
  });

  // Config.lockOverrideUntil (epoch ms, spec §2): an open/locked override is
  // effective only while now < until; at/after it the engine is back on auto.
  const NOW = Date.UTC(2026, 9, 28, 12);
  it('open without lockOverrideUntil stays open (with or without now)', () => {
    expect(lockOverrideOf({ lockOverride: 'open' }, NOW)).toBe('open');
    expect(lockOverrideOf({ lockOverride: 'open' })).toBe('open');
  });
  it('open with lockOverrideUntil in the future stays open', () => {
    expect(lockOverrideOf(
      { lockOverride: 'open', lockOverrideUntil: NOW + 1 }, NOW)).toBe('open');
  });
  it('open with lockOverrideUntil in the past is auto', () => {
    expect(lockOverrideOf(
      { lockOverride: 'open', lockOverrideUntil: NOW - 1 }, NOW)).toBe('auto');
  });
  it('locked with lockOverrideUntil == now is auto (the instant it expires)', () => {
    expect(lockOverrideOf(
      { lockOverride: 'locked', lockOverrideUntil: NOW }, NOW)).toBe('auto');
  });
  it('junk lockOverrideUntil is treated as absent', () => {
    for (const until of ['x', String(NOW - 1), NaN, Infinity, true, {}]) {
      expect(lockOverrideOf(
        { lockOverride: 'locked', lockOverrideUntil: until }, NOW)).toBe('locked');
    }
  });
  it('no now = old behaviour (an until alone never expires it)', () => {
    expect(lockOverrideOf(
      { lockOverride: 'locked', lockOverrideUntil: NOW - 1 })).toBe('locked');
  });
  it('auto stays auto whatever the until', () => {
    expect(lockOverrideOf(
      { lockOverride: 'auto', lockOverrideUntil: NOW + 1 }, NOW)).toBe('auto');
    expect(lockOverrideOf({ lockOverrideUntil: NOW - 1 }, NOW)).toBe('auto');
  });
});

describe('owner void flags (Voided/<gw> = true)', () => {
  it('isVoidFlag: only a literal boolean true voids', () => {
    expect(isVoidFlag(true)).toBe(true);
    expect(isVoidFlag(false)).toBe(false);
    expect(isVoidFlag('true')).toBe(false);
    expect(isVoidFlag(1)).toBe(false);
    expect(isVoidFlag(null)).toBe(false);
  });
  it('voidedWeeksOf: true leaves only, sorted, list coercion tolerated', () => {
    expect(voidedWeeksOf({ 4: true, 2: true, 3: false, 5: 'true', x: true }))
      .toEqual([2, 4]);
    // Small-int gameweek keys list-coerce: index = gameweek.
    expect(voidedWeeksOf([null, true, false, true])).toEqual([1, 3]);
    expect(voidedWeeksOf(null)).toEqual([]);
  });
});

describe('gamesOfDate + allGamesFinal', () => {
  const final = { team1: 'A', team2: 'B', status: 2 };
  const live = { team1: 'C', team2: 'D', status: 1 };
  const friendly = { team1: 'E', team2: 'F', status: 1, Stage: 'Friendly' };

  it('drops friendlies and holes, accepts list or index-keyed map', () => {
    expect(gamesOfDate([final, null, friendly, live]))
      .toEqual([final, live]);
    expect(gamesOfDate({ 0: final, 2: friendly })).toEqual([final]);
  });
  it('final gate: every game status 2, string statuses tolerated', () => {
    expect(allGamesFinal([final, live])).toBe(false);
    expect(allGamesFinal([final, { status: '2' }])).toBe(true);
    expect(allGamesFinal([])).toBe(false); // nothing to settle
  });
  it('dateKeysOf lists non-null keys', () => {
    expect(dateKeysOf({ '06282026': { 0: final }, bad: null }))
      .toEqual(['06282026']);
  });
});

describe('attendance (absent-only node -> full default-present map)', () => {
  it('parseAbsentMap: false and "false" mark absent, junk means present', () => {
    expect(parseAbsentMap({ Ezra: false, Eli: true, Eva: 'false', X: null }))
      .toEqual({ Ezra: false, Eva: false });
    expect(parseAbsentMap(null)).toEqual({});
    // Numeric-keyed node collapsed to a List: index is the stored "name".
    expect(parseAbsentMap([null, false])).toEqual({ '1': false });
  });
  it('fullAttendance: roster present by default, absents override, strays stay false', () => {
    expect(fullAttendance(['Eli', 'Eva', 'Ezra'], { Ezra: false, Gone: false }))
      .toEqual({ Eli: true, Eva: true, Ezra: false, Gone: false });
  });
});

describe('rosters + market', () => {
  it('rosterNamesOf reads Line Ups team keys', () => {
    const lineups = { Sharks: { Sam: { Goals: 1 }, Dana: {} }, Empty: null };
    expect(rosterNamesOf(lineups, 'Sharks')).toEqual(['Sam', 'Dana']);
    expect(rosterNamesOf(lineups, 'Missing')).toEqual([]);
    expect(rosterNamesOf(null, 'Sharks')).toEqual([]);
  });
  it('marketPlayersOf skips unusable positions, eligible defaults false', () => {
    expect(marketPlayersOf({
      Sam: { position: 'GK', eligible: true, priceTenths: 85 },
      Gus: { position: 'ATT', priceTenths: 60 },
      Bad: { position: 'MID' },
      Junk: 7,
    })).toEqual({
      Sam: { position: 'GK', eligible: true },
      Gus: { position: 'ATT', eligible: false },
    });
  });
  it('marketPlayersOf carries teamName when it is a non-empty string', () => {
    expect(marketPlayersOf({
      Sam: { position: 'GK', teamName: 'Sharks' },
      Gus: { position: 'ATT', teamName: '' },
      Ann: { position: 'DEF', teamName: 7 },
    })).toStrictEqual({
      Sam: { position: 'GK', eligible: false, teamName: 'Sharks' },
      Gus: { position: 'ATT', eligible: false },
      Ann: { position: 'DEF', eligible: false },
    });
  });
  it('marketPricesOf reads tenths, junk reads 0', () => {
    expect(marketPricesOf({
      Sam: { priceTenths: 85 }, Gus: { priceTenths: 'x' },
    })).toEqual({ Sam: 85, Gus: 0 });
  });
});
