// Regression tests for bugs surfaced by the read-only Season 15 dress
// rehearsal (functions/tools/rehearse_s15.ts; findings in
// docs/superpowers/reports/2026-10-28-fantasy-s15-rehearsal.md).
//
// FIXED (was `it.fails`): after a Free Hit week the server restores the
// manager's previous squad (orchestration.ts settleTransfersAfterFinalize),
// but the next week's squad-save counter (recordSquadSave) counted "used
// transfers" against PublishedPicks/<gw-1> — the FREE HIT squad. So the
// restore itself was billed as transfers the moment the manager saved
// anything (even an armband-only change). Rehearsal: Free Hit Fiona, GW6,
// 1 real transfer counted as 6 → -8 points and a drained bank afterwards.
// Both now share orchestration.ts effectiveSquadAfterWeek as the baseline.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import {
  maybeFinalizeGame, recordSquadSave, runLifecycleSweep,
} from './orchestration';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, fixtureSquad, GW1_DATE, GW2_DATE, world2,
} from './test_support';

const GW3_DATE = '07052026'; // the Sunday after GW2
// After GW2's lock + 24h (2026-06-29 22:00Z): the GW3 window is open.
const GW3_OPEN = new Date(Date.UTC(2026, 5, 29, 23));
// One hour after GW3's lock (2026-07-05 22:00Z).
const AFTER_LOCK3 = new Date(Date.UTC(2026, 6, 5, 23));
// Saves happen while GW3 is open (the counter judges the write's time
// against GwState.lockAtUtc — audit I3).
const saveArgs = { sport: 'Futsal', season: '15', uid: 'churn', nowUtc: GW3_OPEN };

/** world2 + a GW3 match day whose games are still scheduled (status 0). */
function world3(opts: Parameters<typeof world2>[0] = {}): FakeDb {
  const db = new FakeDb(world2(opts));
  db.data.Futsal['15'].Date[GW3_DATE] = (clone(db.data.Futsal['15'].Date[GW2_DATE]) as Json[])
    .map((g) => ({ ...g, status: 0 }));
  return db;
}

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
    // The restore is a server write: stamped, so it never counts as a save.
    expect(await db.read(`${F_ROOT}/Squads/churn`))
      .toEqual({ ...fixtureSquad('churn'), ServerWriteAt: AFTER_LOCK2.getTime() });
    expect(await db.read(`${F_ROOT}/GwState`)).toMatchObject({ current: 3, status: 'open' });
    expect(await db.read(`${F_ROOT}/TransferState/churn`)).toMatchObject({ Free: 4, UsedThisGw: 0 });
  });

  /** The manager's save: the client writes the WHOLE node (one set() of
   *  FantasySquad.toMap), so the server marker never survives it. */
  function clientSave(db: FakeDb, edit: (squad: Json) => void): void {
    const squad = db.data.Fantasy.Futsal['15'].Squads.churn;
    delete squad['ServerWriteAt'];
    edit(squad);
  }

  it('an armband-only save after the restore counts 0 transfers', async () => {
    const db = await afterFreeHitRestore();
    clientSave(db, (squad) => {
      squad.captainId = 'Dana';
      squad.viceId = 'Ben';
    });
    await recordSquadSave(db, saveArgs);
    // Was 2 (Bo and Ben, the RESTORED players, counted as bought).
    expect((await db.read(`${F_ROOT}/TransferState/churn`) as Json)['UsedThisGw']).toBe(0);
  });

  it('one transfer from the restored squad counts 1', async () => {
    const db = await afterFreeHitRestore();
    clientSave(db, (squad) => {
      squad.picks[5].playerId = 'Will'; // Eva -> Will on the bench
    });
    await recordSquadSave(db, saveArgs);
    // Was 3 (Bo, Ben restored + Will).
    expect((await db.read(`${F_ROOT}/TransferState/churn`) as Json)['UsedThisGw']).toBe(1);
  });
});

// Bug 2 (owner decision 2026-10-28): chips are ONE-WEEK. A played chip used
// to stay on Squads/<uid>; the server voided it inside its set and then
// HONORED it again at the first set-2 lock (Bench Boost Bob, GW7). Now the
// first finalize's rollover switches it off.
describe('S15 rehearsal finding: chips are one-week', () => {
  it('an un-reactivated chip does NOT fire the following week (set 2)', async () => {
    // chipSet1EndGw 2: GW3 is set 2, so a leftover GW2 Triple Captain
    // would be legal again there — exactly the Bob trap.
    const db = world3({ chipSet1EndGw: 2 });
    db.data.Fantasy.Futsal['15'].Squads.boost.chip = 'tripleCaptain';
    await runLifecycleSweep(db, AFTER_LOCK2); // GW2 lock + finalize

    expect((await db.read(`${F_ROOT}/History/2`) as Json)['boost']['chip'])
      .toBe('tripleCaptain'); // honored in GW2
    const live = await db.read(`${F_ROOT}/Squads/boost`) as Json;
    expect('chip' in live).toBe(false); // switched off at rollover
    expect(live['picks']).toEqual(fixtureSquad('boost')['picks']); // nothing else touched

    await runLifecycleSweep(db, GW3_OPEN);
    await runLifecycleSweep(db, AFTER_LOCK3); // GW3 lock, nobody touched the app
    const published3 = await db.read(`${F_ROOT}/PublishedPicks/3`) as Json;
    expect('chip' in published3['boost']).toBe(false);
    expect(await db.read(`${F_ROOT}/TransferState/boost/ChipPlayed`)).toBeNull();
  });

  it('a FRESH activation in set 2 is still honored', async () => {
    const db = world3({ chipSet1EndGw: 2 });
    db.data.Fantasy.Futsal['15'].Squads.boost.chip = 'tripleCaptain';
    await runLifecycleSweep(db, AFTER_LOCK2);
    await runLifecycleSweep(db, GW3_OPEN);
    // The manager taps Triple Captain again for GW3 (set 2).
    db.data.Fantasy.Futsal['15'].Squads.boost.chip = 'tripleCaptain';
    await recordSquadSave(db, { sport: 'Futsal', season: '15', uid: 'boost', nowUtc: GW3_OPEN });
    await runLifecycleSweep(db, AFTER_LOCK3);
    expect((await db.read(`${F_ROOT}/PublishedPicks/3`) as Json)['boost']['chip'])
      .toBe('tripleCaptain');
    expect(await db.read(`${F_ROOT}/TransferState/boost/ChipPlayed`))
      .toBe('tripleCaptain');
  });

  it('a VOIDED chip is switched off too', async () => {
    // world2: boost's live squad still carries GW1's benchBoost -> voided
    // at the GW2 lock (same set). It must not stay armed either.
    const db = world3();
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect('chip' in (await db.read(`${F_ROOT}/PublishedPicks/2`) as Json)['boost'])
      .toBe(false);
    expect('chip' in (await db.read(`${F_ROOT}/Squads/boost`) as Json)).toBe(false);
  });

  it('delayed finalize: a different chip saved for next week survives, the same one does not', async () => {
    const db = world3({ gw2Status: 1, chipSet1EndGw: 2 }); // GW2 games still live
    const f = db.data.Fantasy.Futsal['15'];
    f.Squads.boost.chip = 'tripleCaptain';
    f.Squads.churn.chip = 'tripleCaptain';
    await runLifecycleSweep(db, AFTER_LOCK2); // lock only — not final yet
    await runLifecycleSweep(db, GW3_OPEN); // GW3 opens before GW2 settles
    // boost arms a DIFFERENT chip for GW3; churn re-saves with the same one.
    f.Squads.boost.chip = 'benchBoost';
    await recordSquadSave(db, { sport: 'Futsal', season: '15', uid: 'boost', nowUtc: GW3_OPEN });
    await recordSquadSave(db, saveArgs);
    // GW2's games finally go final: the late first finalize + rollover.
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: GW3_OPEN,
    });
    expect(await db.read(`${F_ROOT}/History/2`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/Squads/boost/chip`)).toBe('benchBoost');
    expect(await db.read(`${F_ROOT}/Squads/churn/chip`)).toBeNull();
  });
});

// Finding 2.5c: a late score correction re-ran GW1 and reset PlayerTotals
// ownership to GW1's holdings. Ownership now follows the latest week.
describe('S15 rehearsal finding: ownership after an old-week rerun', () => {
  it('re-scoring an older week leaves ownership on the latest week', async () => {
    const db = world3();
    // churn sells Bo for Wes in GW2: GW1 ownership Bo 33 / Wes 0, GW2 the
    // reverse (3 managers).
    db.data.Fantasy.Futsal['15'].Squads.churn.picks[0].playerId = 'Wes';
    await recordSquadSave(db, saveArgs);
    await runLifecycleSweep(db, AFTER_LOCK2);
    const ownership = async () => Object.fromEntries(
      Object.entries(await db.read(`${F_ROOT}/PlayerTotals`) as Json)
        .map(([name, row]) => [name, (row as Json)['ownershipPct']]));
    const afterGw2 = await ownership();
    expect(afterGw2['Bo']).toBe(0);
    expect(afterGw2['Wes']).toBe(33);

    // A late GW1 correction rerun (any write to a final GW1 game). Before
    // the fix ownership snapped back to GW1's holdings (Bo 33, Wes 0).
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW1_DATE, nowUtc: GW3_OPEN,
    });
    expect(await ownership()).toEqual(afterGw2);
  });
});
