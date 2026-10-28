// KNOWN-BUG reproductions surfaced by the read-only Season 15 dress rehearsal
// (functions/tools/rehearse_s15.ts; findings in
// docs/superpowers/reports/2026-10-28-fantasy-s15-rehearsal.md).
//
// The bug cases are marked `it.fails`: they PASS while the bug exists and
// start FAILING the moment it is fixed — then flip `it.fails` to `it`.
// Production code is intentionally NOT patched here (stop-for-review).
//
// BUG: after a Free Hit week the server restores the manager's previous
// squad (orchestration.ts settleTransfersAfterFinalize), but the next
// week's squad-save counter (orchestration.ts recordSquadSave) still counts
// "used transfers" against PublishedPicks/<gw-1> — the FREE HIT squad. So
// the restore itself is billed as transfers the moment the manager saves
// anything (even an armband-only change). Rehearsal: Free Hit Fiona, GW6,
// 1 real transfer counted as 6 → -8 points and a drained bank afterwards.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import { recordSquadSave, runLifecycleSweep } from './orchestration';
import { AFTER_LOCK2, F_ROOT, FakeDb, fixtureSquad, GW2_DATE, world2 } from './test_support';

const GW3_DATE = '07052026'; // the Sunday after GW2
// After GW2's lock + 24h (2026-06-29 22:00Z): the GW3 window is open.
const GW3_OPEN = new Date(Date.UTC(2026, 5, 29, 23));
const saveArgs = { sport: 'Futsal', season: '15', uid: 'churn' };

/** world2 + a GW3 match day; churn plays Free Hit in GW2 (Bo -> Wes,
 *  Ben -> Alex), GW2 locks + finalizes (restore runs), GW3 opens. */
async function afterFreeHitRestore(): Promise<FakeDb> {
  const db = new FakeDb(world2());
  const f = db.data.Fantasy.Futsal['15'];
  const churn = f.Squads.churn;
  churn.picks[0].playerId = 'Wes';
  churn.picks[4].playerId = 'Alex';
  churn.captainId = 'Alex';
  churn.viceId = 'Dana';
  churn.chip = 'freeHit';
  f.TransferState = { churn: { Free: 2, UsedThisGw: 2, SavedGw: 2 } };
  db.data.Futsal['15'].Date[GW3_DATE] = (clone(db.data.Futsal['15'].Date[GW2_DATE]) as Json[])
    .map((g) => ({ ...g, status: 0 }));
  await runLifecycleSweep(db, AFTER_LOCK2); // GW2 lock + backstop finalize
  await runLifecycleSweep(db, GW3_OPEN); // GW3 window opens
  return db;
}

describe('S15 rehearsal finding: transfer count after a Free Hit restore', () => {
  it('setup holds: the GW1 squad was restored and GW3 is open', async () => {
    const db = await afterFreeHitRestore();
    expect(await db.read(`${F_ROOT}/Squads/churn`)).toEqual(fixtureSquad('churn'));
    expect(await db.read(`${F_ROOT}/GwState`)).toMatchObject({ current: 3, status: 'open' });
    expect(await db.read(`${F_ROOT}/TransferState/churn`)).toMatchObject({ Free: 4, UsedThisGw: 0 });
  });

  it.fails('KNOWN BUG: an armband-only save after the restore counts 0 transfers', async () => {
    const db = await afterFreeHitRestore();
    const squad = db.data.Fantasy.Futsal['15'].Squads.churn;
    squad.captainId = 'Dana';
    squad.viceId = 'Ben';
    await recordSquadSave(db, saveArgs);
    // Today: 2 (Bo and Ben, the RESTORED players, are counted as bought).
    expect((await db.read(`${F_ROOT}/TransferState/churn`) as Json)['UsedThisGw']).toBe(0);
  });

  it.fails('KNOWN BUG: one transfer from the restored squad counts 1', async () => {
    const db = await afterFreeHitRestore();
    const squad = db.data.Fantasy.Futsal['15'].Squads.churn;
    squad.picks[5].playerId = 'Will'; // Eva -> Will on the bench
    await recordSquadSave(db, saveArgs);
    // Today: 3 (Bo, Ben restored + Will).
    expect((await db.read(`${F_ROOT}/TransferState/churn`) as Json)['UsedThisGw']).toBe(1);
  });
});
