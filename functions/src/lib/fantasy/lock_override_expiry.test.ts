// Lock-override auto-return (spec §2, automation round 2026-10-28) over the
// in-memory FantasyDb: an open/locked override with Config.lockOverrideUntil
// (epoch ms) is effective only while now < until. The 15-minute sweep reverts
// an expired one in the DB (lockOverride 'auto', until removed, logged) and
// runs the season normally in the SAME sweep; every other stand-down check
// (squad-save counter, finalize, void re-settle, Monday reprice, position
// trigger) reads the effective value at its own job's now. Built on the
// two-gameweek world (GW1 finalized, GW2 open, lock 2026-06-28 22:00Z).

import { describe, expect, it } from 'vitest';
import { STARTER_CATALOG } from './badges';
import { clone } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, recordSquadSave, resettleVoidToggle,
  runLifecycleSweep, runMondayReprice,
} from './orchestration';
import { handlePositionWrite } from './position_changes';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, GW2_DATE, LOCK2_MS, world2,
} from './test_support';

const HOUR_MS = 60 * 60 * 1000;
// Saturday before the GW2 lock: the GW2 window is open.
const OPEN_NOW = new Date(Date.UTC(2026, 5, 27, 18));
const EXPIRED_MSG = 'fantasy sweep: lock override expired — back to auto';

/** world2 with Config.lockOverride (+ optional lockOverrideUntil). */
function overridden(
  lockOverride: string, untilMs: number | undefined,
  opts: Parameters<typeof world2>[0] = {},
): FakeDb {
  const db = new FakeDb(world2(opts));
  // Steady state: earlier sweeps already seeded the global badge catalog, so
  // every write below is this season's (a frozen season: none at all).
  db.data.Fantasy.BadgeCatalog = clone(STARTER_CATALOG);
  const config = db.data.Fantasy.Futsal['15'].Config;
  config.lockOverride = lockOverride;
  if (untilMs !== undefined) config.lockOverrideUntil = untilMs;
  return db;
}

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

const configOf = (db: FakeDb) => db.data.Fantasy.Futsal['15'].Config;

describe('sweep: expired lock override reverts to auto and the season runs', () => {
  it('locked/open past until (or exactly at it): Config back to auto, until removed, logged, GwState written', async () => {
    for (const [lockOverride, untilMs] of [
      ['locked', AFTER_LOCK2.getTime() - 1],
      ['open', AFTER_LOCK2.getTime()], // the instant it expires
    ] as const) {
      const db = overridden(lockOverride, untilMs, { gw2Status: 1 }); // games live
      const log = capturingLog();
      await runLifecycleSweep(db, AFTER_LOCK2, log);

      // The DB carries the revert: auto, no until, the rest of Config intact
      // — ONE compare-and-set write of Config, the sweep's first write.
      expect(configOf(db)).toEqual({ lockHour: 15, lockOverride: 'auto' });
      expect(db.writes[0]).toBe(`${F_ROOT}/Config`);
      expect(db.writes.filter((p) => p.startsWith(`${F_ROOT}/Config`)))
        .toEqual([`${F_ROOT}/Config`]);
      expect(log.infos).toContainEqual(
        { message: EXPIRED_MSG, context: { sport: 'Futsal', season: '15' } });

      // ...and the season ran in the same sweep: GW2 lock snapshot + GwState.
      expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
      expect(await db.read(`${F_ROOT}/GwState`)).toEqual({
        current: 2, status: 'locked', lockAtUtc: LOCK2_MS, date: GW2_DATE,
      });
      expect(log.infos.map((i) => i.message))
        .not.toContain('fantasy sweep: lockOverride frozen — standing down');
    }
  });

  it('until still ahead: stays frozen, Config and GwState untouched (zero writes)', async () => {
    const db = overridden('locked', AFTER_LOCK2.getTime() + HOUR_MS, { gw2Status: 1 });
    const before = db.snapshot();
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);
    expect(configOf(db).lockOverride).toBe('locked');
    expect(configOf(db).lockOverrideUntil).toBe(AFTER_LOCK2.getTime() + HOUR_MS);
    expect((await db.read(`${F_ROOT}/GwState`) as Record<string, unknown>)['status'])
      .toBe('open');
  });

  it('no until ("Never") stays frozen forever', async () => {
    const db = overridden('open', undefined, { gw2Status: 1 });
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(db.writes).toEqual([]);
  });

  /** A db whose 'Fantasy' read (the sweep's season snapshot) is taken just
   *  BEFORE [ownerWrite] lands on Config — the owner's change races the
   *  revert. */
  function racing(
    expiredOverride: string, ownerWrite: (config: Record<string, any>) => void,
  ): FakeDb {
    const db = overridden(expiredOverride, AFTER_LOCK2.getTime() - 1, { gw2Status: 1 });
    const read = db.read.bind(db);
    db.read = async (path: string) => {
      const value = await read(path);
      if (path !== 'Fantasy') return value;
      const snapshot = JSON.parse(JSON.stringify(value));
      ownerWrite(configOf(db));
      return snapshot;
    };
    return db;
  }

  it('an owner re-lock (new until) between the sweep read and the revert is never wiped', async () => {
    const newUntil = AFTER_LOCK2.getTime() + 6 * HOUR_MS;
    const db = racing('locked', (c) => { c.lockOverrideUntil = newUntil; });
    const log = capturingLog();
    await runLifecycleSweep(db, AFTER_LOCK2, log);

    expect(configOf(db)).toEqual({
      lockHour: 15, lockOverride: 'locked', lockOverrideUntil: newUntil,
    });
    const messages = log.infos.map((i) => i.message);
    expect(messages).not.toContain(EXPIRED_MSG);
    // The sweep runs on the owner's fresh config: frozen again.
    expect(messages).toContain('fantasy sweep: lockOverride frozen — standing down');
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
    expect((await db.read(`${F_ROOT}/GwState`) as Record<string, unknown>)['status'])
      .toBe('open');
  });

  it('a changed override value (same until) is not reverted either', async () => {
    const db = racing('locked', (c) => { c.lockOverride = 'open'; });
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(configOf(db)).toEqual({
      lockHour: 15, lockOverride: 'open', lockOverrideUntil: AFTER_LOCK2.getTime() - 1,
    });
  });
});

describe('every other stand-down check reads the effective override at its own now', () => {
  it('finalize trigger: expired settles the week, future stands down', async () => {
    const expired = overridden('locked', AFTER_LOCK2.getTime() - 1);
    await maybeFinalizeGame(expired, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(await expired.read(`${F_ROOT}/History/2`)).not.toBeNull();

    const future = overridden('locked', AFTER_LOCK2.getTime() + HOUR_MS);
    await maybeFinalizeGame(future, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(future.writes).toEqual([]);
  });

  it('void re-settle: expired re-settles, future stands down', async () => {
    const expired = overridden('open', AFTER_LOCK2.getTime() - 1);
    await resettleVoidToggle(expired, {
      sport: 'Futsal', season: '15', gw: 2, nowUtc: AFTER_LOCK2,
    });
    expect(await expired.read(`${F_ROOT}/History/2`)).not.toBeNull();

    const future = overridden('open', AFTER_LOCK2.getTime() + HOUR_MS);
    await resettleVoidToggle(future, {
      sport: 'Futsal', season: '15', gw: 2, nowUtc: AFTER_LOCK2,
    });
    expect(future.writes).toEqual([]);
  });

  it('Monday reprice: expired reprices, future stands down', async () => {
    const monday = new Date(Date.UTC(2026, 5, 22, 17)); // after GW1, 10:00 PDT
    const expired = overridden('locked', monday.getTime() - 1);
    await runMondayReprice(expired, monday);
    expect(await expired.read(`${F_ROOT}/Repriced/1`)).toEqual({ At: monday.getTime() });

    const future = overridden('locked', monday.getTime() + HOUR_MS);
    await runMondayReprice(future, monday);
    expect(future.writes).toEqual([]);
  });

  it('squad-save counter: expired counts the save, future stays silent', async () => {
    const expired = overridden('open', OPEN_NOW.getTime() - 1);
    await recordSquadSave(expired, {
      sport: 'Futsal', season: '15', uid: 'churn', nowUtc: OPEN_NOW,
    });
    expect(await expired.read(`${F_ROOT}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2,
    });

    const future = overridden('open', OPEN_NOW.getTime() + HOUR_MS);
    await recordSquadSave(future, {
      sport: 'Futsal', season: '15', uid: 'churn', nowUtc: OPEN_NOW,
    });
    expect(future.writes).toEqual([]);
  });

  it('position trigger: expired applies the move, future is frozen', async () => {
    const move = (db: FakeDb) => {
      db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT';
      return handlePositionWrite(db, {
        sport: 'Futsal', season: '15', name: 'Bea',
        before: 'DEF', after: 'ATT', nowUtc: OPEN_NOW,
      });
    };
    expect(await move(overridden('locked', OPEN_NOW.getTime() - 1))).toBe('applied');
    const future = overridden('locked', OPEN_NOW.getTime() + HOUR_MS);
    expect(await move(future)).toBe('frozen');
    expect(future.writes).toEqual([]);
  });
});
