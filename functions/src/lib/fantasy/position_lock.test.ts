// Positions locked per gameweek (spec §3 revision 2026-10-28): the lock
// step snapshots every market player's position into LockedPositions/<gw>
// (once), finalize and the Monday reprice of <gw> read positions from it,
// and a week without a snapshot falls back to the live Players positions.
//
// HAND MATH (golden fixture _notes): Bea's raw week = assist1 dpl5 conc0 +
// 3 BPS bonus. As DEF: 1 + 4 + 5 (CS) + 2 (dpl>=5) + 3 = 15. As ATT:
// 1 + 3 + 2 (CS) + 0 (dpl5 < 7) + 3 = 9 (BPS is position-free, so the
// bonus stays 3).

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import {
  maybeFinalizeGame, runLifecycleSweep, runMondayReprice,
} from './orchestration';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, GW1_DATE, GW2_DATE, world2,
} from './test_support';

const GW3_DATE = '07052026';
const GW3_OPEN = new Date(Date.UTC(2026, 5, 29, 23));
const AFTER_LOCK3 = new Date(Date.UTC(2026, 6, 5, 23));
// Monday 2026-06-29 10:00 PDT = 17:00Z (after GW2 settles, before GW3 opens).
const MONDAY = new Date(Date.UTC(2026, 5, 29, 17));
const args = (dateKey: string, nowUtc: Date) =>
  ({ sport: 'Futsal', season: '15', dateKey, nowUtc });

function world3(opts: Parameters<typeof world2>[0] = {}): FakeDb {
  const db = new FakeDb(world2(opts));
  db.data.Futsal['15'].Date[GW3_DATE] = (clone(db.data.Futsal['15'].Date[GW2_DATE]) as Json[])
    .map((g) => ({ ...g, status: 0 }));
  return db;
}

const setFinal = (db: FakeDb, date: string) => {
  for (const g of db.data.Futsal['15'].Date[date]) g.status = 2;
};

describe('LockedPositions snapshot', () => {
  it('the lock sweep snapshots every market position once', async () => {
    const db = world3({ gw2Status: 1 }); // games live: lock only
    await runLifecycleSweep(db, AFTER_LOCK2);
    const snap = await db.read(`${F_ROOT}/LockedPositions/2`) as Json;
    expect(snap).toEqual({
      Sam: 'GK', Wes: 'GK', Eli: 'GK', Bo: 'GK',
      Dana: 'DEF', Will: 'DEF', Eva: 'DEF', Bea: 'DEF',
      Alex: 'ATT', Wren: 'ATT', Ezra: 'ATT', Ben: 'ATT',
    });
    // A later sweep after a position change never re-snapshots.
    db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT';
    await runLifecycleSweep(db, new Date(AFTER_LOCK2.getTime() + 15 * 60_000));
    expect(await db.read(`${F_ROOT}/LockedPositions/2/Bea`)).toBe('DEF');
  });

  it('a change after lock: that week (and its reruns) score the LOCKED position; the next week the new one', async () => {
    const db = world3({ gw2Status: 1 });
    await runLifecycleSweep(db, AFTER_LOCK2); // GW2 locked, positions snapshotted
    db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT'; // owner fix, mid-lock

    setFinal(db, GW2_DATE);
    await maybeFinalizeGame(db, args(GW2_DATE, AFTER_LOCK2));
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2/Bea`)).toBe(15); // as DEF
    const dt2 = await db.read(`${F_ROOT}/DreamTeam/2/Players`) as Json[];
    expect(dt2.find((r) => r['name'] === 'Bea')).toEqual(
      { name: 'Bea', position: 'DEF', points: 15 });

    // GW3 locks with the new position.
    await runLifecycleSweep(db, GW3_OPEN);
    await runLifecycleSweep(db, AFTER_LOCK3);
    expect(await db.read(`${F_ROOT}/LockedPositions/3/Bea`)).toBe('ATT');
    setFinal(db, GW3_DATE);
    await maybeFinalizeGame(db, args(GW3_DATE, AFTER_LOCK3));
    expect(await db.read(`${F_ROOT}/PlayerWeeks/3/Bea`)).toBe(9); // as ATT

    // A late score-edit rerun of GW2 still uses GW2's locked DEF.
    await maybeFinalizeGame(db, args(GW2_DATE, AFTER_LOCK3));
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2/Bea`)).toBe(15);
    // Season total = 15 (GW2 as DEF) + 9 (GW3 as ATT); GW1 has no
    // PlayerWeeks in this world.
    expect((await db.read(`${F_ROOT}/PlayerTotals/Bea`) as Json)['points']).toBe(24);
  });

  it('a first finalize that outran every sweep claims the snapshot itself', async () => {
    const db = world3(); // GW2 games already final, no sweep has run
    await maybeFinalizeGame(db, args(GW2_DATE, AFTER_LOCK2));
    expect(await db.read(`${F_ROOT}/LockedPositions/2/Bea`)).toBe('DEF');
    db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT';
    await maybeFinalizeGame(db, args(GW2_DATE, AFTER_LOCK2)); // rerun
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2/Bea`)).toBe(15);
  });

  it('a week locked before snapshots existed falls back to live positions', async () => {
    // world2's GW1 was settled with no LockedPositions/1: a rerun after a
    // position change scores at the live position (and writes no
    // fabricated snapshot).
    const db = world3();
    db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT';
    await maybeFinalizeGame(db, args(GW1_DATE, AFTER_LOCK2));
    expect(await db.read(`${F_ROOT}/PlayerWeeks/1/Bea`)).toBe(9);
    expect(await db.read(`${F_ROOT}/LockedPositions/1`)).toBeNull();
  });

  it('the Monday reprice groups peers at the week\'s locked positions', async () => {
    const run = async (moveBea: boolean) => {
      const db = world3();
      await runLifecycleSweep(db, AFTER_LOCK2); // lock + finalize GW2
      if (moveBea) db.data.Fantasy.Futsal['15'].Players.Bea.position = 'ATT';
      await runMondayReprice(db, MONDAY);
      return await db.read(`${F_ROOT}/PriceChanges/2`);
    };
    const unmoved = await run(false);
    expect(unmoved).not.toBeNull();
    // Moving Bea after the lock changes nothing about GW2's repricing.
    expect(await run(true)).toEqual(unmoved);
  });
});
