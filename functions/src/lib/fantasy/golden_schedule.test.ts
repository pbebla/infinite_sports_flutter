// Golden schedule — the cross-engine contract for deriveGameweeks with a
// GameweekSchedule (weeks freeze once locked, skipped dates, deadline
// overrides, kickoff-aware automatic deadline).
//
// Loads test/fantasy/fixtures/golden_schedule.json FROM THE REPO (not a copy,
// like golden_replay.test.ts) and replays every case; the Dart twin replays
// the same file in test/fantasy/gameweeks_test.dart (group golden_schedule).
// The expectations were hand-computed BEFORE either engine ran — if this
// replay ever disagrees, the TS port is wrong; never copy actual values into
// the file.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import {
  deriveGameweeks, GameweekSchedule, LockedWeek,
} from './gameweeks';
import { firstKickoffByDateOf } from './orchestration_db';

/** The fixture lives in the Flutter repo root's test tree; vitest runs from
 *  functions/, but resolve robustly by walking up to the directory that
 *  holds pubspec.yaml (the repo root), wherever the runner starts. */
function fixturePath(): string {
  let dir = process.cwd();
  for (; ;) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) {
      return path.join(
        dir, 'test', 'fantasy', 'fixtures', 'golden_schedule.json');
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(
        'Could not find the Flutter repo root (pubspec.yaml) above ' +
        process.cwd());
    }
    dir = parent;
  }
}

type Json = Record<string, any>;

const fixture: Json = JSON.parse(fs.readFileSync(fixturePath(), 'utf8'));
const cases: Json[] = fixture['cases'];

const iso = (s: string): Date => new Date(s);

/** The fixture's `schedule` block (ISO instants) as a GameweekSchedule. */
function scheduleOf(block: Json | undefined): Partial<GameweekSchedule> {
  const b = block ?? {};
  const out: Partial<GameweekSchedule> = {};
  if (b['lockedWeeks']) {
    const locked: Record<number, LockedWeek> = {};
    for (const [n, w] of Object.entries<Json>(b['lockedWeeks'])) {
      locked[Number(n)] = {
        date: w['date'], lockUtc: iso(w['lockUtc']), scored: w['scored'] === true,
      };
    }
    out.lockedWeeks = locked;
  }
  if (b['skippedDates']) out.skippedDates = new Set<string>(b['skippedDates']);
  if (b['deadlineOverrides']) {
    out.deadlineOverrides = Object.fromEntries(
      Object.entries<string>(b['deadlineOverrides'])
        .map(([d, s]) => [d, iso(s)]));
  }
  if (b['firstKickoffUtc']) {
    out.firstKickoffUtc = Object.fromEntries(
      Object.entries<string>(b['firstKickoffUtc'])
        .map(([d, s]) => [d, iso(s)]));
  }
  if (b['minutesBeforeKickoff'] !== undefined) {
    out.minutesBeforeKickoff = b['minutesBeforeKickoff'];
  }
  return out;
}

describe('golden_schedule', () => {
  it('fixture carries the expected cases', () => {
    expect(cases.map((c) => c['name'])).toEqual(expect.arrayContaining([
      'plain', 'skipped', 'override', 'early kickoff', 'late kickoff',
      'frozen, day gone', 'frozen, past day inserted', 'gap in frozen',
      'override beats kickoff', 'legacy start time',
    ]));
  });

  for (const c of cases) {
    it(c['name'], () => {
      const schedule = scheduleOf(c['schedule']);
      if (c['dateNode']) {
        // dateNode-derived kickoffs, merged under any explicit ones.
        schedule.firstKickoffUtc = {
          ...firstKickoffByDateOf(c['dateNode'], c['startHour'] ?? 0),
          ...(schedule.firstKickoffUtc ?? {}),
        };
      }
      const cfg = { ...futsalDefault(), lockHour: c['lockHour'] as number };
      const gws = deriveGameweeks(c['dates'], cfg, schedule);
      const expected: Json[] = c['expected'];
      expect(gws.length).toBe(expected.length);
      expected.forEach((e, i) => {
        const g = gws[i];
        expect(g.number).toBe(e['number']);
        expect(g.date).toBe(e['date']);
        expect(g.lockUtc.toISOString()).toBe(iso(e['lockUtc']).toISOString());
        expect(g.opensUtc === null ? null : g.opensUtc.toISOString())
          .toBe(e['opensUtc'] === null ? null : iso(e['opensUtc']).toISOString());
        expect(g.frozen).toBe(e['frozen']);
      });
    });
  }
});
