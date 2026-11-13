// Deadline-reminder false positive (fix): the Squads/<uid> trigger also
// fires for the SERVER's own squad writes — the post-finalize chip
// switch-off, the Free Hit restore, position re-labels — and those used to
// stamp TransferState.SavedGw as if the manager had saved, silently
// dropping them from the "unchanged squad" reminder audience. Server writes
// now carry ServerWriteAt (orchestration_db.ts SERVER_WRITE_KEY) and
// recordSquadSave judges the triggering event's value: a server write is
// recounted but never stamps SavedGw; the manager's own whole-node save
// (which wipes the marker) always does.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import { maybeFinalizeGame, recordSquadSave, runLifecycleSweep } from './orchestration';
import { handlePositionWrite } from './position_changes';
import { reminderAudience } from './pushes';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, GW2_DATE, world2,
} from './test_support';

const GW3_DATE = '07052026'; // the Sunday after GW2
// After GW2's lock + 24h: the GW3 window is open.
const GW3_OPEN = new Date(Date.UTC(2026, 5, 29, 23));

/** The trigger, replayed with THIS write's after-value (production passes
 *  event.data.after.val()). */
async function trigger(db: FakeDb, uid: string, nowUtc: Date): Promise<void> {
  await recordSquadSave(db, {
    sport: 'Futsal', season: '15', uid, nowUtc,
    after: clone(await db.read(`${F_ROOT}/Squads/${uid}`)),
  });
}

async function audience(db: FakeDb, gw: number): Promise<string[]> {
  return reminderAudience({
    managersRaw: await db.read(`${F_ROOT}/Managers`),
    squadsRaw: await db.read(`${F_ROOT}/Squads`),
    transferStateRaw: await db.read(`${F_ROOT}/TransferState`),
    gw,
  });
}

/** GW2 locks while its games are still live, GW3 opens, THEN GW2 goes final
 *  (a delayed finalize): its rollover writes to live squads while the GW3
 *  window is open — exactly when a stray SavedGw stamp silences the GW3
 *  reminder. churn plays Free Hit in GW2 (restore pending); boost carries
 *  the fixture's benchBoost (switched off at rollover). */
async function delayedFinalizeWorld(): Promise<FakeDb> {
  const db = new FakeDb(world2({ gw2Status: 1 }));
  const f = db.data.Fantasy.Futsal['15'];
  const churn = f.Squads.churn;
  churn.picks[0].playerId = 'Wes';
  churn.picks[4].playerId = 'Alex';
  churn.captainId = 'Alex';
  churn.viceId = 'Dana';
  churn.chip = 'freeHit';
  f.TransferState = { churn: { Free: 2, UsedThisGw: 2, SavedGw: 2 } };
  db.data.Futsal['15'].Date[GW3_DATE] =
    (clone(db.data.Futsal['15'].Date[GW2_DATE]) as Json[])
      .map((g) => ({ ...g, status: 0 }));
  await runLifecycleSweep(db, AFTER_LOCK2); // GW2 lock snapshot, no finalize
  await runLifecycleSweep(db, GW3_OPEN); // GW3 opens
  expect(await db.read(`${F_ROOT}/GwState`))
    .toMatchObject({ current: 3, status: 'open' });
  for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
  await maybeFinalizeGame(db, {
    sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: GW3_OPEN,
  });
  return db;
}

describe('server squad writes never count as a manager save', () => {
  it('Free Hit restore: recounted, SavedGw untouched -> still reminded; ' +
    'the manager\'s own save then counts', async () => {
    const db = await delayedFinalizeWorld();
    const restored = await db.read(`${F_ROOT}/Squads/churn`) as Json;
    expect(restored['ServerWriteAt']).toBe(GW3_OPEN.getTime());

    await trigger(db, 'churn', GW3_OPEN); // the restore's trigger
    const state = await db.read(`${F_ROOT}/TransferState/churn`) as Json;
    expect(state['SavedGw']).toBe(2); // NOT 3
    expect(state['UsedThisGw']).toBe(0); // recounted vs the restored baseline
    expect(await audience(db, 3)).toContain('churn');

    // The manager saves for GW3: one whole-node set — the marker is gone.
    const save = clone(restored);
    delete save['ServerWriteAt'];
    save['captainId'] = 'Dana';
    await db.write(`${F_ROOT}/Squads/churn`, save);
    await trigger(db, 'churn', GW3_OPEN);
    expect((await db.read(`${F_ROOT}/TransferState/churn`) as Json)['SavedGw'])
      .toBe(3);
    expect(await audience(db, 3)).not.toContain('churn');
  });

  it('chip switch-off after the week: marked first, never stamps SavedGw',
    async () => {
      const db = await delayedFinalizeWorld();
      const boost = await db.read(`${F_ROOT}/Squads/boost`) as Json;
      expect('chip' in boost).toBe(false); // spent chip switched off
      expect(boost['ServerWriteAt']).toBe(GW3_OPEN.getTime());

      await trigger(db, 'boost', GW3_OPEN);
      const state = await db.read(`${F_ROOT}/TransferState/boost`) as Json;
      expect(state['SavedGw']).toBeUndefined(); // never saved -> no stamp
      expect(await audience(db, 3)).toContain('boost');
    });

  it('position re-label while the window is open: marked, not a save',
    async () => {
      const db = new FakeDb(world2());
      // Dana (DEF in alpha + churn) moves to ATT while GW2 is open.
      db.data.Fantasy.Futsal['15'].Players.Dana.position = 'ATT';
      const now = new Date(Date.UTC(2026, 5, 27, 12));
      await handlePositionWrite(db, {
        sport: 'Futsal', season: '15', name: 'Dana',
        before: 'DEF', after: 'ATT', nowUtc: now,
      });
      const alpha = await db.read(`${F_ROOT}/Squads/alpha`) as Json;
      expect(alpha['ServerWriteAt']).toBe(now.getTime());
      expect((alpha['picks'] as Json[]).find((p) => p['playerId'] === 'Dana')!
        ['position']).toBe('ATT');

      await trigger(db, 'alpha', now);
      expect((await db.read(`${F_ROOT}/TransferState/alpha`) as Json)['SavedGw'])
        .toBeUndefined();
      expect(await audience(db, 2)).toContain('alpha');
    });

  it('a manager save racing a server write is judged on ITS OWN event: ' +
    'still counted', async () => {
    const db = new FakeDb(world2());
    const now = new Date(Date.UTC(2026, 5, 27, 12));
    const managerSave = clone(await db.read(`${F_ROOT}/Squads/alpha`)) as Json;
    managerSave['captainId'] = 'Dana';
    // By the time the trigger runs, a server write has re-marked the node.
    await db.write(`${F_ROOT}/Squads/alpha`,
      { ...managerSave, ServerWriteAt: now.getTime() });
    await recordSquadSave(db, {
      sport: 'Futsal', season: '15', uid: 'alpha', nowUtc: now,
      after: managerSave, // this event's value: no marker
    });
    expect((await db.read(`${F_ROOT}/TransferState/alpha`) as Json)['SavedGw'])
      .toBe(2);
    expect(await audience(db, 2)).not.toContain('alpha');
  });

  it('the trigger\'s own re-label of a stale manager save: the save counts, ' +
    'the re-label it writes is marked as the server\'s', async () => {
    const db = new FakeDb(world2());
    const now = new Date(Date.UTC(2026, 5, 27, 12));
    // The market says Dana is ATT, but the manager saves her as DEF.
    db.data.Fantasy.Futsal['15'].Players.Dana.position = 'ATT';
    const managerSave = clone(await db.read(`${F_ROOT}/Squads/alpha`)) as Json;
    await recordSquadSave(db, {
      sport: 'Futsal', season: '15', uid: 'alpha', nowUtc: now, after: managerSave,
    });
    expect((await db.read(`${F_ROOT}/TransferState/alpha`) as Json)['SavedGw'])
      .toBe(2);
    expect((await db.read(`${F_ROOT}/Squads/alpha`) as Json)['ServerWriteAt'])
      .toBe(now.getTime());
  });
});
