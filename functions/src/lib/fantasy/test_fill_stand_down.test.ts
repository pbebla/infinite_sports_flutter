// TestFill stand-down (audit I5, 2026-10-31): a season carrying the
// Fantasy/<sport>/<season>/TestFill marker (tools/fill_test_season.ts — a
// replayed fake season that also holds the REAL managers' replayed squads)
// must never settle season badges nor write a trophy cabinet
// (Users/<uid>/Awards), and every engine entry point — sweep, finalize, void
// re-settle, Monday reprice, squad-save counter — stands down for it even
// when lockOverride is 'auto' (the owner tapped Resume Auto on the filled
// season). Each case is paired with the SAME world minus the marker, so the
// zero-write assertions cannot pass vacuously. Built on world2 (GW1
// settled, GW2 the week under test; see badges.test.ts HAND MATH: Overall
// churn 118 > boost 89 > alpha 70).

import { describe, expect, it } from 'vitest';
import { deterministicAwardId, settleSeasonBadges, STARTER_CATALOG } from './badges';
import { configFromMap } from './fantasy_config';
import { clone, Json } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, recordSquadSave, resettleVoidToggle,
  runLifecycleSweep, runMondayReprice,
} from './orchestration';
import { TEST_FILL_STAND_DOWN } from './orchestration_db';
import { AFTER_LOCK2, F_ROOT, FakeDb, GW2_DATE, world2 } from './test_support';

const MARKER = { At: 1793424975844, Managers: 20 };
const LATER = new Date(AFTER_LOCK2.getTime() + 3_600_000);
const SEASON_OVER = new Date(Date.UTC(2026, 7, 15));
// Monday after GW2, 10:00 PDT (the reprice slot).
const MONDAY = new Date(Date.UTC(2026, 5, 29, 17));
// Saturday before the GW2 lock: the GW2 window is open.
const OPEN_NOW = new Date(Date.UTC(2026, 5, 27, 18));
const ARGS = { sport: 'Futsal', season: '15' } as const;
const cab = (badge: string) =>
  deterministicAwardId(`fantasy_${badge}`, 'fantasy', 'Futsal/15', '15');

function capturingLog(): FantasyLogger & {
  infos: Array<{ message: string; context?: Record<string, unknown> }>;
} {
  const infos: Array<{ message: string; context?: Record<string, unknown> }> = [];
  return {
    infos,
    info: (message, context) => { infos.push({ message, context }); },
    warn: () => undefined,
  };
}

function withMarker(db: FakeDb, testFill: boolean): FakeDb {
  if (testFill) db.data.Fantasy.Futsal['15'].TestFill = clone(MARKER);
  db.writes = [];
  return db;
}

/** world2 with the badge catalog already seeded (steady state: the sweep's
 *  global seeding writes nothing) and real Users nodes for all three
 *  managers. */
function base(opts: Parameters<typeof world2>[0] = {}): FakeDb {
  const db = new FakeDb(world2(opts));
  db.data.Fantasy.BadgeCatalog = clone(STARTER_CATALOG);
  db.data.Users = { alpha: { Name: 'a' }, boost: { Name: 'b' }, churn: { Name: 'c' } };
  return db;
}

/** A season that is OVER: Finished = true and every week has History (GW2
 *  finalized while the season was still running, so no season award exists
 *  yet) — what a fill leaves behind. */
async function finishedSeason(testFill: boolean): Promise<FakeDb> {
  const db = base();
  await maybeFinalizeGame(db, { ...ARGS, dateKey: GW2_DATE, nowUtc: AFTER_LOCK2 });
  expect(await db.read(`${F_ROOT}/History/2`)).not.toBeNull();
  expect(JSON.stringify(await db.read(`${F_ROOT}/Badges`))).not.toContain('_season');
  db.data.Futsal['15'].Finished = true;
  return withMarker(db, testFill);
}

const usersWrites = (db: FakeDb) => db.writes.filter((p) => p.startsWith('Users/'));
const seasonAwards = async (db: FakeDb) =>
  JSON.stringify(await db.read(`${F_ROOT}/Badges`) ?? {}).match(/\w+_season/g) ?? [];

describe('settleSeasonBadges on a TestFill season (Finished, every week History)', () => {
  it('returns testFill: no *_season award, no Users/* write, nothing written at all', async () => {
    for (const onlyIfUnsettled of [false, true]) {
      const db = await finishedSeason(true);
      const cfg = configFromMap(db.data.Fantasy.Futsal['15'].Config);
      const log = capturingLog();
      expect(await settleSeasonBadges(db, {
        ...ARGS, cfg, nowUtc: SEASON_OVER, log, onlyIfUnsettled,
      })).toBe('testFill');
      expect(db.writes).toEqual([]);
      expect(await seasonAwards(db)).toEqual([]);
      expect(await db.read('Users/churn/Awards')).toBeNull();
      expect(log.infos.map((i) => i.message)).toContain(
        'fantasy badges: TestFill season — season badges and trophy cabinet skipped');
    }
  });

  it('control: the same season WITHOUT the marker settles the podium + cabinet', async () => {
    const db = await finishedSeason(false);
    const cfg = configFromMap(db.data.Fantasy.Futsal['15'].Config);
    expect(await settleSeasonBadges(db, { ...ARGS, cfg, nowUtc: SEASON_OVER }))
      .toBe('settled');
    expect(await seasonAwards(db)).toContain('champion_season');
    expect(await db.read(`Users/churn/Awards/${cab('champion')}`)).not.toBeNull();
  });
});

describe('Resume Auto on a TestFill season: every engine entry point stands down', () => {
  it('finalize rerun (a score correction): zero writes, logged', async () => {
    for (const testFill of [true, false]) {
      const db = await finishedSeason(testFill);
      const log = capturingLog();
      await maybeFinalizeGame(db, { ...ARGS, dateKey: GW2_DATE, nowUtc: LATER, log });
      if (testFill) {
        expect(db.writes).toEqual([]);
        expect(log.infos).toContainEqual({
          message: TEST_FILL_STAND_DOWN,
          context: { ...ARGS, dateKey: GW2_DATE, job: 'finalize' },
        });
      } else {
        // Without the marker the rerun settles the season — cabinet included.
        expect(await seasonAwards(db)).toContain('champion_season');
        expect(usersWrites(db).length).toBeGreaterThan(0);
      }
    }
  });

  it('void toggle re-settle: zero writes', async () => {
    for (const testFill of [true, false]) {
      const db = await finishedSeason(testFill);
      db.data.Fantasy.Futsal['15'].Voided = { 2: true };
      await resettleVoidToggle(db, { ...ARGS, gw: 2, nowUtc: LATER });
      if (testFill) {
        expect(db.writes).toEqual([]);
      } else {
        expect(db.writes).toContain(`${F_ROOT}/History/2`);
      }
    }
  });

  it('sweep after the season ended: no season badges, no Users/* write, nothing written', async () => {
    for (const testFill of [true, false]) {
      const db = await finishedSeason(testFill);
      const log = capturingLog();
      await runLifecycleSweep(db, SEASON_OVER, log);
      if (testFill) {
        expect(db.writes).toEqual([]);
        expect(await seasonAwards(db)).toEqual([]);
        expect(log.infos).toContainEqual(
          { message: TEST_FILL_STAND_DOWN, context: { ...ARGS, job: 'sweep' } });
      } else {
        expect(await seasonAwards(db)).toContain('champion_season');
        expect(usersWrites(db).length).toBeGreaterThan(0);
      }
    }
  });

  it('sweep across a lock with the match day final: no snapshot, no finalize, no GwState', async () => {
    for (const testFill of [true, false]) {
      const db = withMarker(base(), testFill);
      await runLifecycleSweep(db, AFTER_LOCK2);
      if (testFill) {
        expect(db.writes).toEqual([]);
      } else {
        expect(db.writes).toContain(`${F_ROOT}/PublishedPicks/2`);
        expect(db.writes).toContain(`${F_ROOT}/History/2`);
      }
    }
  });

  it('Monday reprice: no price moves, no Repriced claim', async () => {
    for (const testFill of [true, false]) {
      const db = await finishedSeason(testFill);
      const log = capturingLog();
      await runMondayReprice(db, MONDAY, log);
      if (testFill) {
        expect(db.writes).toEqual([]);
        expect(log.infos).toContainEqual(
          { message: TEST_FILL_STAND_DOWN, context: { ...ARGS, job: 'reprice' } });
      } else {
        expect(await db.read(`${F_ROOT}/Repriced/2`)).toEqual({ At: MONDAY.getTime() });
      }
    }
  });

  it('squad-save counter: no TransferState recount', async () => {
    for (const testFill of [true, false]) {
      const db = withMarker(base(), testFill);
      const churn = db.data.Fantasy.Futsal['15'].Squads.churn as Json;
      churn.picks[0].playerId = 'Wes'; // a transfer
      const log = capturingLog();
      await recordSquadSave(db, { ...ARGS, uid: 'churn', nowUtc: OPEN_NOW, log });
      if (testFill) {
        expect(db.writes).toEqual([]);
        expect(log.infos).toContainEqual({
          message: TEST_FILL_STAND_DOWN, context: { ...ARGS, uid: 'churn', job: 'squadSave' },
        });
      } else {
        expect(await db.read(`${F_ROOT}/TransferState/churn`))
          .toMatchObject({ UsedThisGw: 1, SavedGw: 2 });
      }
    }
  });
});
