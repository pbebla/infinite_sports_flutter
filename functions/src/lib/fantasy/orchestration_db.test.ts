// RTDB-shape parsing for the fantasy jobs (P4) — the coercion-tolerance
// seams: list-coerced seasons/weeks, absent-only attendance, friendly
// filtering, market parsing.

import { describe, expect, it } from 'vitest';
import {
  allGamesFinal, childEntries, dateKeysOf, fantasySeasonsOf,
  firstKickoffByDateOf, fullAttendance, gamesOfDate, isVoidFlag,
  lockedWeeksOf, lockOverrideOf, marketPlayersOf, marketPricesOf,
  parseAbsentMap, rosterNamesOf, scheduleOverridesOf, toIntLoose,
  voidedWeeksOf,
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

// ── Schedule nodes (season setup + schedule changes, Task 1) ────────────────

const LOCK_MS = 1791154800000; // 2026-10-04T23:00:00Z

describe('lockedWeeksOf', () => {
  const week1 = { Date: '10042026', LockAtUtc: LOCK_MS };
  const expected1 = {
    date: '10042026', lockUtc: new Date('2026-10-04T23:00:00Z'), scored: false,
  };
  it('RTDB hands keys 1..n back as a List with a null index 0', () => {
    expect(lockedWeeksOf([null, week1])).toEqual({ 1: expected1 });
  });
  it('and as a Map when the keys are not dense', () => {
    expect(lockedWeeksOf({ '1': week1 })).toEqual({ 1: expected1 });
    expect(lockedWeeksOf({ '1': week1, '3': { ...week1, Date: '10182026' } }))
      .toEqual({ 1: expected1, 3: { ...expected1, date: '10182026' } });
  });
  it('Scored counts only as a literal true', () => {
    expect(lockedWeeksOf([null, { ...week1, Scored: true }])[1].scored)
      .toBe(true);
    expect(lockedWeeksOf([null, { ...week1, Scored: 'yes' }])[1].scored)
      .toBe(false);
    expect(lockedWeeksOf([null, { ...week1, Scored: 1 }])[1].scored)
      .toBe(false);
  });
  it('junk is skipped, never thrown on', () => {
    expect(lockedWeeksOf([
      week1, // index 0 is not a week
      null,
      'nope',
      { Date: '1004', LockAtUtc: LOCK_MS }, // not MMDDYYYY
      { Date: '13452026', LockAtUtc: LOCK_MS }, // month 13
      { Date: '02302026', LockAtUtc: LOCK_MS }, // Feb 30
      { Date: '10042026', LockAtUtc: '1791154800000' }, // not a number
      { Date: '10042026', LockAtUtc: NaN },
      { Date: '10042026', LockAtUtc: 0 },
      { Date: 10042026, LockAtUtc: LOCK_MS }, // Date not a string
      { LockAtUtc: LOCK_MS },
    ])).toEqual({});
    expect(lockedWeeksOf({ x: week1, '-1': week1, '1.5': week1 }))
      .toEqual({});
    expect(lockedWeeksOf(null)).toEqual({});
    expect(lockedWeeksOf('nope')).toEqual({});
    expect(lockedWeeksOf(7)).toEqual({});
  });
});

describe('scheduleOverridesOf', () => {
  it('SkippedDates: only a literal true counts', () => {
    expect(scheduleOverridesOf({
      SkippedDates: { '10112026': true, '10182026': 'yes', '10252026': 1 },
    }).skippedDates).toEqual(new Set(['10112026']));
  });
  it('Deadlines: epoch-ms numbers only, valid date keys only', () => {
    const o = scheduleOverridesOf({
      Deadlines: {
        '10112026': LOCK_MS, '10182026': 'x', '10252026': true,
        '11012026': '1791154800000', junk: 5,
      },
    });
    expect(Object.keys(o.deadlineOverrides)).toEqual(['10112026']);
    expect(o.deadlineOverrides['10112026'].toISOString())
      .toBe('2026-10-04T23:00:00.000Z');
  });
  it('deadlineMinutesBeforeKickoff: default 60, clamp 0..240, ints only', () => {
    const m = (v: unknown) => scheduleOverridesOf(
      { deadlineMinutesBeforeKickoff: v }).minutesBeforeKickoff;
    expect(m(undefined)).toBe(60);
    expect(m(45)).toBe(45);
    expect(m(0)).toBe(0);
    expect(m(240)).toBe(240);
    expect(m(999)).toBe(240);
    expect(m(-5)).toBe(0);
    expect(m('45')).toBe(60);
    expect(m(45.5)).toBe(60);
    expect(m(NaN)).toBe(60);
    expect(m(1e300)).toBe(60); // not a representable integer
    expect(m(null)).toBe(60);
    expect(m(true)).toBe(60);
  });
  it('an absent or malformed Config is all defaults', () => {
    for (const node of [null, undefined, 'x', 3, [1, 2]]) {
      expect(scheduleOverridesOf(node)).toEqual({
        skippedDates: new Set(), deadlineOverrides: {}, minutesBeforeKickoff: 60,
      });
    }
  });
});

describe('firstKickoffByDateOf', () => {
  const iso = (m: Record<string, Date>) => Object.fromEntries(
    Object.entries(m).map(([d, t]) => [d, t.toISOString()]));

  it('takes the earliest valid Time of the day, in league time', () => {
    expect(iso(firstKickoffByDateOf({
      '10112026': [
        { Time: '7pm' }, { Time: '15:30' }, { Time: '14:00' },
        { Time: '25:00' }, { Time: '14:60' }, { Time: '' }, {},
      ],
    }))).toEqual({ '10112026': '2026-10-11T21:00:00.000Z' }); // 14:00 PDT
  });
  it('PST dates use the winter offset', () => {
    expect(iso(firstKickoffByDateOf({ '11012026': [{ Time: '14:00' }] })))
      .toEqual({ '11012026': '2026-11-01T22:00:00.000Z' });
  });
  it('accepts a single-digit hour and padding like the schedule display', () => {
    expect(iso(firstKickoffByDateOf({ '10112026': [{ Time: ' 9:05 ' }] })))
      .toEqual({ '10112026': '2026-10-11T16:05:00.000Z' });
  });
  it('no Time and no start hour -> no kickoff for that date', () => {
    expect(firstKickoffByDateOf({ '10112026': [{ team1: 'A' }] })).toEqual({});
    expect(firstKickoffByDateOf({ '10112026': [{ Time: '7pm' }] }, 0))
      .toEqual({});
  });
  it('falls back per game to the legacy derived time when startHour > 0', () => {
    // game 0: '7pm' invalid -> legacy(5,0)=17:00; game 1: 15:30 stored;
    // game 2: no Time -> legacy(5,2)=19:00. Earliest = 15:30 PDT.
    expect(iso(firstKickoffByDateOf({
      '10112026': [{ Time: '7pm' }, { Time: '15:30' }, {}],
    }, 5))).toEqual({ '10112026': '2026-10-11T22:30:00.000Z' });
    // only a derived time: 17:00 PDT
    expect(iso(firstKickoffByDateOf({ '10112026': [{ team1: 'A' }] }, 5)))
      .toEqual({ '10112026': '2026-10-12T00:00:00.000Z' });
  });
  it('the legacy index is the list position (null holes still count)', () => {
    // index 1 -> legacy(3,1) = 16:00 PDT = 23:00Z
    expect(iso(firstKickoffByDateOf({ '10112026': [null, {}] }, 3)))
      .toEqual({ '10112026': '2026-10-11T23:00:00.000Z' });
  });
  it('an index-keyed Map of games uses the numeric key as the index', () => {
    // hole-collapsed node: games 0 and 2 survive; game 2 has no Time ->
    // legacy(2,2) = 16:00 PDT; game 0 stores 17:30.
    expect(iso(firstKickoffByDateOf({
      '10112026': { '0': { Time: '17:30' }, '2': { team1: 'A' } },
    }, 2))).toEqual({ '10112026': '2026-10-11T23:00:00.000Z' });
    // a non-numeric key has no index: skipped
    expect(firstKickoffByDateOf({ '10112026': { x: {} } }, 2)).toEqual({});
  });
  it('non-date keys and a malformed node are skipped, not thrown on', () => {
    expect(firstKickoffByDateOf({ junk: [{ Time: '14:00' }] })).toEqual({});
    expect(firstKickoffByDateOf({ '10112026': 'x', '10182026': null }))
      .toEqual({});
    expect(firstKickoffByDateOf(null)).toEqual({});
    expect(firstKickoffByDateOf('nope')).toEqual({});
    expect(firstKickoffByDateOf([{ Time: '14:00' }])).toEqual({});
  });
});
