// Phase E transfer accounting over an in-memory FantasyDb: the squad-save
// counter (recordSquadSave), the lock-time chip void + cost freeze riding
// the PublishedPicks snapshot, the finalize cost application through the
// transferCostPointsByUid seam, the Free Hit squad restore, and the
// once-only rollover. Built on a TWO-gameweek world: GW1 (06212026) already
// finalized with the golden squads, GW2 (06282026) the week under test.
// Golden gross tenths: alpha 350, boost 440, churn 595 (fixture _notes).

import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import { clone, Json } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, recordSquadSave, runLifecycleSweep,
} from './orchestration';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, fixtureIds, fixtureSquad, GW1_DATE, GW2_DATE,
  world2,
} from './test_support';
import { pickIdsOf } from './transfer_state';

const fRoot = F_ROOT;
// Saves happen while GW2 is open: the counter judges the write's own time
// against GwState.lockAtUtc (audit I3), so the clock is explicit.
const GW2_OPEN_NOW = new Date(Date.UTC(2026, 5, 27, 18));
const saveArgs = (uid: string) =>
  ({ sport: 'Futsal', season: '15', uid, nowUtc: GW2_OPEN_NOW });

describe('recordSquadSave (squad-save trigger entry)', () => {
  it('counts players not in the previous locked squad; a re-save recounts', async () => {
    const db = new FakeDb(world2());
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes'; // Bo out
    churn.picks[4].playerId = 'Alex'; // Ben out
    await recordSquadSave(db, saveArgs('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 2, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });

    // Undoing one transfer before the deadline un-counts it.
    churn.picks[0].playerId = 'Bo';
    await recordSquadSave(db, saveArgs('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it('first-ever squad: no transfer accounting, but SavedGw is stamped', async () => {
    const db = new FakeDb(world2());
    db.data.Fantasy.Futsal['15'].Squads.newbie = fixtureSquad('alpha');
    await recordSquadSave(db, saveArgs('newbie'));
    // CountFromGw alone = "no squad to count from: a first team".
    expect(await db.read(`${fRoot}/TransferState/newbie`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2, CountFromGw: 2,
    });
  });

  it('keeps the banked Free from an earlier rollover', async () => {
    const db = new FakeDb(world2());
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 4, UsedThisGw: 0, RolledGw: 1 },
    };
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes';
    await recordSquadSave(db, saveArgs('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 4, UsedThisGw: 1, SavedGw: 2, RolledGw: 1,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it("no-ops while locked, while frozen 'locked', and without a Config or GwState", async () => {
    const locked = new FakeDb(world2());
    locked.data.Fantasy.Futsal['15'].GwState.status = 'locked';
    await recordSquadSave(locked, saveArgs('churn'));
    expect(locked.writes).toEqual([]);

    const frozen = new FakeDb(world2());
    frozen.data.Fantasy.Futsal['15'].Config.lockOverride = 'locked';
    await recordSquadSave(frozen, saveArgs('churn'));
    expect(frozen.writes).toEqual([]);

    const noConfig = new FakeDb(world2());
    delete noConfig.data.Fantasy.Futsal['15'].Config;
    await recordSquadSave(noConfig, saveArgs('churn'));
    expect(noConfig.writes).toEqual([]);

    const noState = new FakeDb(world2());
    delete noState.data.Fantasy.Futsal['15'].GwState;
    await recordSquadSave(noState, saveArgs('churn'));
    expect(noState.writes).toEqual([]);
  });
});

// Audit I4: the owner's routine "Open for 24 h" (lockOverride 'open' with a
// lockOverrideUntil auto-return) used to stand the counter down, so every
// transfer made in the window was lost (the next lock charged a stale
// UsedThisGw) and SavedGw stayed unstamped. Only 'locked' stands it down now.
describe("recordSquadSave under a paused-Open window (audit I4)", () => {
  // Saturday before the GW2 lock (GwState open on GW2).
  const OPEN_NOW = new Date(Date.UTC(2026, 5, 27, 18));
  const UNTIL = OPEN_NOW.getTime() + 24 * 3_600_000; // "Open for 24 h"
  const at = (uid: string) => ({ ...saveArgs(uid), nowUtc: OPEN_NOW });

  function paused(lockOverride: 'open' | 'locked'): FakeDb {
    const db = new FakeDb(world2({ gw2Status: 1 })); // GW2 games live at lock
    Object.assign(db.data.Fantasy.Futsal['15'].Config,
      { lockOverride, lockOverrideUntil: UNTIL });
    return db;
  }

  it("'open' with an auto-return: saves update UsedThisGw and stamp SavedGw (a recount)", async () => {
    const db = paused('open');
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes'; // Bo out
    churn.picks[4].playerId = 'Alex'; // Ben out
    await recordSquadSave(db, at('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 2, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
    // Undoing one in the window un-counts it, exactly as outside a pause.
    churn.picks[0].playerId = 'Bo';
    await recordSquadSave(db, at('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
    // A server write in the window recounts but never stamps SavedGw.
    db.data.Fantasy.Futsal['15'].TransferState.churn.SavedGw = 1;
    churn.ServerWriteAt = OPEN_NOW.getTime();
    await recordSquadSave(db, at('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 1,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it("'locked' with an auto-return: saves are not counted (zero writes)", async () => {
    const db = paused('locked');
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes';
    await recordSquadSave(db, at('churn'));
    expect(db.writes).toEqual([]);
  });

  it('after the auto-return the lock charges the transfers made in the window', async () => {
    const db = paused('open');
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 1, UsedThisGw: 0, RolledGw: 1 },
    };
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes';
    churn.picks[4].playerId = 'Alex';
    await recordSquadSave(db, at('churn'));
    // The window expires before the lock; the first sweep after it reverts
    // to auto and snapshots: 2 used vs 1 free = one extra = 4 points.
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(db.data.Fantasy.Futsal['15'].Config.lockOverride).toBe('auto');
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 4 });
    expect(await db.read(`${fRoot}/TransferState/churn`)).toMatchObject({
      Free: 1, UsedThisGw: 2, SavedGw: 2,
    });
  });
});

describe('lock step: chip void + cost freeze ride the snapshot', () => {
  it('voids a set-repeated chip in the snapshot and freezes costs/ChipPlayed', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: lock only
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 2, UsedThisGw: 3, SavedGw: 2 },
    };
    await runLifecycleSweep(db, AFTER_LOCK2);

    // boost replayed GW1's benchBoost inside set 1 -> voided in the reveal.
    const published = await db.read(`${fRoot}/PublishedPicks/2`) as Json;
    expect('chip' in published['boost']).toBe(false);
    const expectedBoost = fixtureSquad('boost');
    delete expectedBoost['chip'];
    // Valid squads are snapshotted at their judged prices (== the prices
    // paid here: every player held) + realizedTenths (no sales: 0).
    expect(published['boost']).toEqual({ ...expectedBoost, realizedTenths: 0 });
    expect(published['alpha']).toEqual({ ...fixtureSquad('alpha'), realizedTenths: 0 });
    expect(await db.read(`${fRoot}/TransferState/boost`)).toEqual({
      Free: 2, UsedThisGw: 0, // no ChipPlayed: the void consumed nothing
    });

    // churn: used 3 vs free 2 at -4/extra = 4 points, frozen for finalize.
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 4 });
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 3, SavedGw: 2,
    });
  });

  it('the same chip is honored again in set 2', async () => {
    const db = new FakeDb(world2({ gw2Status: 1, chipSet1EndGw: 1 }));
    await runLifecycleSweep(db, AFTER_LOCK2);
    const published = await db.read(`${fRoot}/PublishedPicks/2`) as Json;
    expect(published['boost']['chip']).toBe('benchBoost');
    expect(await db.read(`${fRoot}/TransferState/boost`)).toEqual({
      Free: 2, UsedThisGw: 0, ChipPlayed: 'benchBoost',
    });
  });
});

describe('finalize: cost application + rollover (once only)', () => {
  it('charges the frozen cost, scores the voided chip as none, rolls transfers', async () => {
    const db = new FakeDb(world2());
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 2, UsedThisGw: 3, SavedGw: 2 },
    };
    await runLifecycleSweep(db, AFTER_LOCK2); // lock + backstop finalize

    const history = await db.read(`${fRoot}/History/2`) as Json;
    expect(history['churn']['TotalTenths']).toBe(555); // 595 - 4 pts * 10
    expect(history['alpha']['TotalTenths']).toBe(350);
    // boost's benchBoost was voided: Eva scores bench-half (-15), not
    // full (-30) -> 440 + 30 - 15 = 455.
    expect(history['boost']['TotalTenths']).toBe(455);
    expect(await db.read(`${fRoot}/Leaderboards/Gameweek/2`)).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 45, rank: 2 },
      churn: { points: 55, rank: 1 },
    });
    expect(await db.read(`${fRoot}/Leaderboards/Overall`)).toEqual({
      alpha: { points: 70, rank: 3, movement: 0 },
      boost: { points: 89, rank: 2, movement: 0 },
      churn: { points: 114, rank: 1, movement: 0 },
    });

    // Rollover: churn overspent (remaining 0) -> 2; the others bank to 4.
    // Each publishes the squad it locked as next week's transfer baseline.
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2, RolledGw: 2,
      CountFromGw: 3, CountFrom: fixtureIds('churn'),
    });
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 2,
      CountFromGw: 3, CountFrom: fixtureIds('alpha'),
    });

    // Resweep + rerun: byte-identical (costs re-read from TransferCosts,
    // rollover RolledGw-guarded).
    const before = db.snapshot();
    await runLifecycleSweep(db, AFTER_LOCK2);
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(db.snapshot()).toBe(before);
  });

  it('freeHit: unlimited transfers, previous locked squad restored after the week', async () => {
    const db = new FakeDb(world2());
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;
    churn.picks[0].playerId = 'Wes';
    churn.picks[4].playerId = 'Alex';
    churn.captainId = 'Alex';
    churn.viceId = 'Dana';
    churn.chip = 'freeHit';
    db.data.Fantasy.Futsal['15'].TransferState = {
      churn: { Free: 2, UsedThisGw: 2, SavedGw: 2 },
    };
    await runLifecycleSweep(db, AFTER_LOCK2);

    // Unlimited week: nothing charged.
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toBeNull();
    // The GW1 locked squad came back, chip-free (fixture churn has none),
    // stamped as a SERVER write (never mistaken for the manager saving).
    expect(await db.read(`${fRoot}/Squads/churn`)).toEqual({
      ...fixtureSquad('churn'), ServerWriteAt: AFTER_LOCK2.getTime(),
    });
    // Rollover never consumed the bank on a freeHit week.
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 4, UsedThisGw: 0, SavedGw: 2, RolledGw: 2,
      CountFromGw: 3, CountFrom: fixtureIds('churn'),
    });

    // A post-restore edit for next week survives a finalize rerun (the
    // restore is RolledGw-guarded, not repeated).
    db.data.Fantasy.Futsal['15'].Squads.churn.captainId = 'Dana';
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect((await db.read(`${fRoot}/Squads/churn`) as Json)['captainId'])
      .toBe('Dana');
  });

  it('GW1 freeHit (no previous squad): nothing to restore, rollover still runs', async () => {
    const db = new FakeDb(world2());
    // Rewind the world to GW1: no history, no snapshot, GW1 under test.
    const f = db.data.Fantasy.Futsal['15'];
    delete f.History;
    delete f.PublishedPicks;
    delete db.data.Futsal['15'].Date[GW2_DATE];
    f.Squads.alpha.chip = 'freeHit';
    const liveAlpha = clone(f.Squads.alpha);
    const now = new Date(Date.UTC(2026, 5, 21, 23));
    await runLifecycleSweep(db, now);
    expect(await db.read(`${fRoot}/History/1`)).not.toBeNull();
    // The squad stays (nothing to restore) but the spent chip is switched
    // off — chips are one-week — by a write stamped as the server's.
    delete liveAlpha['chip'];
    expect(await db.read(`${fRoot}/Squads/alpha`))
      .toEqual({ ...liveAlpha, ServerWriteAt: now.getTime() });
    // GW1 is alpha's FIRST week: nothing banks (2, not 2 + 2). A GW1 Free Hit
    // has no earlier squad to return to, so its own squad is the baseline.
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 2, UsedThisGw: 0, RolledGw: 1,
      CountFromGw: 2, CountFrom: fixtureIds('alpha'),
    });
  });
});

// FPL selling plan Task 5, fix round 1: a save the trigger never counted
// (stored UsedThisGw lower than the transfers really made) is charged at
// the lock AND persisted into TransferState.UsedThisGw, so the rollover
// banks from the real count. Here churn's GW2 squad sells Bo, Ben and Eva
// (3 transfers, still exactly 500 tenths) but TransferState says 0 used.
describe('the lock recount is persisted (uncounted saves)', () => {
  const RECOUNT_MSG = 'fantasy transfers: lock recount raised the count';

  function uncountedWorld(state: Json, opts: { gw2Status?: number } = {}): FakeDb {
    const db = new FakeDb(world2(opts));
    const f = db.data.Fantasy.Futsal['15'];
    const churn = f.Squads.churn;
    churn.picks[0] = { playerId: 'Eli', position: 'GK', priceTenths: 55, bench: false }; // Bo out
    churn.picks[4] = { playerId: 'Alex', position: 'ATT', priceTenths: 95, bench: false }; // Ben out
    churn.picks[5] = { playerId: 'Will', position: 'DEF', priceTenths: 60, bench: true }; // Eva out
    churn.captainId = 'Alex';
    f.TransferState = { churn: state };
    return db;
  }

  function capture(): { log: FantasyLogger; infos: Array<{ m: string; c?: Json }> } {
    const infos: Array<{ m: string; c?: Json }> = [];
    return {
      infos,
      log: { info: (m, c) => { infos.push({ m, c }); }, warn: () => undefined },
    };
  }

  it('the lock charges 1 extra AND raises UsedThisGw to 3 (other fields kept), logged', async () => {
    const db = uncountedWorld({ Free: 2, UsedThisGw: 0, RolledGw: 1 }, { gw2Status: 1 });
    const { log, infos } = capture();
    await runLifecycleSweep(db, AFTER_LOCK2, log); // games live: lock only
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 4 });
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 3, RolledGw: 1,
    });
    const recounts = infos.filter((i) => i.m === RECOUNT_MSG);
    expect(recounts).toHaveLength(1);
    expect(recounts[0].c).toMatchObject({ uid: 'churn', gw: 2, stored: 0, recounted: 3 });
    // Squads the recount didn't raise are untouched (and not logged).
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({ Free: 2, UsedThisGw: 0 });
  });

  it('the rollover banks from the recount: Free 2, real 3 -> next week 0 + 2', async () => {
    const db = uncountedWorld({ Free: 2, UsedThisGw: 0, RolledGw: 1 });
    await runLifecycleSweep(db, AFTER_LOCK2); // lock + backstop finalize
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 4 });
    // Without the persisted recount this banked 2 - 0 + 2 = 4.
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 0 + futsalDefault().freeTransfersPerWeek, UsedThisGw: 0, RolledGw: 2,
      CountFromGw: 3,
      CountFrom: pickIdsOf(await db.read(`${fRoot}/PublishedPicks/2/churn`)),
    });
  });

  it('a recount that does not win changes nothing (stored kept, no log)', async () => {
    const db = uncountedWorld({ Free: 2, UsedThisGw: 5, SavedGw: 2 }, { gw2Status: 1 });
    const { log, infos } = capture();
    await runLifecycleSweep(db, AFTER_LOCK2, log);
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 12 }); // 3 extra
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 5, SavedGw: 2,
    });
    expect(infos.filter((i) => i.m === RECOUNT_MSG)).toEqual([]);
  });

  it('a first finalize from live Squads (no lock snapshot) persists it too', async () => {
    const db = uncountedWorld({ Free: 2, UsedThisGw: 0, RolledGw: 1 });
    const { log, infos } = capture();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2, log,
    });
    expect(await db.read(`${fRoot}/PublishedPicks/2`)).toBeNull(); // the fallback ran
    expect(await db.read(`${fRoot}/TransferCosts/2`)).toEqual({ churn: 4 });
    expect(infos.filter((i) => i.m === RECOUNT_MSG).map((i) => i.c))
      .toEqual([expect.objectContaining({ uid: 'churn', gw: 2, stored: 0, recounted: 3 })]);
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, RolledGw: 2,
      CountFromGw: 3,
      CountFrom: pickIdsOf(await db.read(`${fRoot}/History/2/churn`)),
    });
  });

  it("a counter already running for a LATER week is never raised (it isn't this week's)", async () => {
    // A late first finalize after the manager saved for GW3: UsedThisGw is
    // GW3's running count and survives the rollover — the GW2 recount must
    // not leak into it.
    const db = uncountedWorld({ Free: 2, UsedThisGw: 1, SavedGw: 3, RolledGw: 1 });
    const { log, infos } = capture();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2, log,
    });
    expect(infos.filter((i) => i.m === RECOUNT_MSG)).toEqual([]);
    expect(await db.read(`${fRoot}/TransferState/churn`)).toMatchObject({
      UsedThisGw: 1, SavedGw: 3, RolledGw: 2,
    });
  });
});

// Fantasy transfers in-app, Task 1. A manager's FIRST team is free to build,
// so it has no unused allowance to bank: the week after it he gets the plain
// weekly grant (D1). And every rollover publishes the squad it locked as the
// baseline the fan app counts next week's transfers against (CountFromGw +
// CountFrom; D1/D1b/D1c) — CountFromGw alone means "no squad to count from: a
// first team". Exact ids/values below are hand-derived from the golden world.
describe('first team never banks; the rollover publishes the transfer baseline', () => {
  const GW1_NOW = new Date(Date.UTC(2026, 5, 21, 23)); // just after GW1's lock
  const GW3_DATE = '07052026'; // Sunday; lock 22:00Z
  const LOCK3_MS = Date.UTC(2026, 6, 5, 22);
  const AFTER_LOCK3 = new Date(Date.UTC(2026, 6, 5, 23));
  const GW3_OPEN_NOW = new Date(Date.UTC(2026, 6, 4, 18)); // Saturday before
  const f = (db: FakeDb) => db.data.Fantasy.Futsal['15'];

  /** world2 rewound to GW1: no history, no snapshot, GW1 under test. */
  function gw1World(): FakeDb {
    const db = new FakeDb(world2());
    delete f(db).History;
    delete f(db).PublishedPicks;
    delete db.data.Futsal['15'].Date[GW2_DATE];
    return db;
  }

  /** world2 plus a finalized GW2 (same golden squads) and GW3 open. */
  function gw3World(): FakeDb {
    const w = world2();
    const root = w.Fantasy.Futsal['15'];
    w.Futsal['15'].Date[GW3_DATE] = clone(w.Futsal['15'].Date[GW2_DATE]);
    root.History[2] = clone(root.History[1]);
    root.PublishedPicks[2] = clone(root.PublishedPicks[1]);
    root.GwState = {
      current: 3, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
    };
    return new FakeDb(w);
  }

  const gw3Save = (uid: string) =>
    ({ sport: 'Futsal', season: '15', uid, nowUtc: GW3_OPEN_NOW });

  it('(a) GW1 squad, GW1 finalized: Free resets to 2 (not 4) and CountFrom is the GW1 locked squad', async () => {
    const db = gw1World();
    await runLifecycleSweep(db, GW1_NOW);
    expect(await db.read(`${fRoot}/History/1`)).not.toBeNull();
    for (const uid of ['alpha', 'boost', 'churn']) {
      expect(await db.read(`${fRoot}/TransferState/${uid}`), uid).toEqual({
        Free: 2, UsedThisGw: 0, RolledGw: 1,
        CountFromGw: 2, CountFrom: fixtureIds(uid),
      });
    }
    // The once-only guard still holds: a rerun re-rolls nothing.
    const before = db.snapshot();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW1_DATE, nowUtc: GW1_NOW,
    });
    expect(db.snapshot()).toBe(before);
  });

  it('(b) a manager whose first squad is GW3: Free is 2 after GW3, while a GW2 veteran banks to 4', async () => {
    const db = gw3World();
    f(db).Squads.late = fixtureSquad('alpha'); // no GW1/GW2 squad at all
    await recordSquadSave(db, gw3Save('late'));
    await runLifecycleSweep(db, AFTER_LOCK3); // GW3 lock + backstop finalize
    expect(await db.read(`${fRoot}/History/3/late`)).not.toBeNull(); // scored
    expect(await db.read(`${fRoot}/TransferState/late`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 3, RolledGw: 3,
      CountFromGw: 4, CountFrom: fixtureIds('alpha'),
    });
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 3,
      CountFromGw: 4, CountFrom: fixtureIds('alpha'),
    });
  });

  it('(c) GW1 squad, no save in GW2: a real bank still banks (Free 4)', async () => {
    const db = new FakeDb(world2());
    // What GW1's rollover left: the weekly grant, baseline = the GW1 squad.
    f(db).TransferState = {
      alpha: {
        Free: 2, UsedThisGw: 0, RolledGw: 1,
        CountFromGw: 2, CountFrom: fixtureIds('alpha'),
      },
    };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 2,
      CountFromGw: 3, CountFrom: fixtureIds('alpha'),
    });
  });

  it('(d) a Free Hit in GW2: CountFrom is the GW1 squad the restore put back, not the Free Hit squad', async () => {
    const db = new FakeDb(world2());
    const churn = f(db).Squads.churn;
    churn.picks[0].playerId = 'Wes';
    churn.picks[4].playerId = 'Alex';
    churn.chip = 'freeHit';
    await runLifecycleSweep(db, AFTER_LOCK2);

    const restored = await db.read(`${fRoot}/Squads/churn`);
    expect(pickIdsOf(restored)).toEqual(fixtureIds('churn')); // the GW1 squad
    const state = await db.read(`${fRoot}/TransferState/churn`) as Json;
    expect(state['CountFromGw']).toBe(3);
    expect(state['CountFrom']).toEqual(pickIdsOf(restored)); // == the restore
    expect(state['CountFrom']).not.toContain('Wes'); // never the Free Hit squad
  });

  describe('(e) the lock freeze and a counted save', () => {
    const stale = { CountFromGw: 1, CountFrom: ['Zed', 'Yan'] };

    it('the lock freeze leaves CountFrom / CountFromGw as they were', async () => {
      const db = new FakeDb(world2({ gw2Status: 1 })); // games live: lock only
      f(db).TransferState = {
        churn: { Free: 2, UsedThisGw: 3, SavedGw: 2, ...stale },
      };
      await runLifecycleSweep(db, AFTER_LOCK2);
      expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
        Free: 2, UsedThisGw: 3, SavedGw: 2, ...stale,
      });
    });

    it('a counted save rewrites them from its own baseline', async () => {
      const db = new FakeDb(world2());
      f(db).TransferState = {
        churn: { Free: 2, UsedThisGw: 3, SavedGw: 2, ...stale },
      };
      f(db).Squads.churn.picks[0].playerId = 'Wes'; // Bo out
      await recordSquadSave(db, saveArgs('churn'));
      expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
        Free: 2, UsedThisGw: 1, SavedGw: 2,
        CountFromGw: 2, CountFrom: fixtureIds('churn'),
      });
    });
  });

  it('(f) deleting the squad and saving a new one inside an open week is NOT a first team: all 5 new players count', async () => {
    const db = new FakeDb(world2());
    delete f(db).Squads.churn;
    await recordSquadSave(db, saveArgs('churn')); // a deletion counts nothing
    expect(db.writes).toEqual([]);

    // GW1's churn was Bo Dana Bea Ezra Ben Eva Wren; five of these are new.
    const pick = (playerId: string, position: string, priceTenths: number,
      bench = false) => ({ playerId, position, priceTenths, bench });
    f(db).Squads.churn = {
      picks: [
        pick('Wes', 'GK', 65), pick('Dana', 'DEF', 80), pick('Will', 'DEF', 60),
        pick('Alex', 'ATT', 95), pick('Ezra', 'ATT', 65),
        pick('Eli', 'GK', 55, true), pick('Sam', 'GK', 85, true),
      ],
      captainId: 'Alex', viceId: 'Wes',
    };
    await recordSquadSave(db, saveArgs('churn'));
    // Last week's locked squad still exists, so the save counts against it
    // (not a first team): Wes, Will, Alex, Eli, Sam are all new.
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 5, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it('(g) scored in GW1, squad deleted before the GW2 lock: rolls as if used 0, next baseline is "first team"', async () => {
    const db = new FakeDb(world2());
    // alpha made (and counted) 3 transfers in the open week, then deleted
    // the squad: nothing was locked, nothing charged, nothing spent.
    f(db).TransferState = {
      alpha: {
        Free: 2, UsedThisGw: 3, SavedGw: 2, RolledGw: 1,
        CountFromGw: 2, CountFrom: fixtureIds('alpha'),
      },
    };
    delete f(db).Squads.alpha;
    await runLifecycleSweep(db, AFTER_LOCK2);

    expect(await db.read(`${fRoot}/History/2/alpha`)).toBeNull(); // not scored
    expect(await db.read(`${fRoot}/History/2/churn`)).not.toBeNull();
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, SavedGw: 2, RolledGw: 2, CountFromGw: 3,
    });

    // GW3: he saves a squad again. There is no GW2 locked squad to count
    // against, so it is free (a first team).
    f(db).GwState = {
      current: 3, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
    };
    f(db).Squads.alpha = fixtureSquad('alpha');
    await recordSquadSave(db, gw3Save('alpha'));
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, SavedGw: 3, RolledGw: 2, CountFromGw: 3,
    });
  });

  it("(h) a brand-new manager's first save in an open week: CountFromGw is the week, no CountFrom", async () => {
    const db = new FakeDb(world2());
    f(db).Squads.newbie = fixtureSquad('alpha');
    await recordSquadSave(db, saveArgs('newbie'));
    const state = await db.read(`${fRoot}/TransferState/newbie`) as Json;
    expect(state['CountFromGw']).toBe(2);
    expect('CountFrom' in state).toBe(false);
    expect(state['UsedThisGw']).toBe(0);
  });

  // The rollover audience now includes managers who were not scored, so a
  // rerun of an OLD week (a score edit, an un-void) can reach one who joined
  // after it. Rolling him for that week would overwrite the baseline his own
  // save just published — a manager already past gw + 1 is left alone.
  it('a manager already working on a later week is not rolled by an older one', async () => {
    const db = new FakeDb(world2());
    const latecomer = { Free: 2, UsedThisGw: 1, SavedGw: 4, CountFromGw: 4 };
    f(db).TransferState = { latecomer: { ...latecomer } };
    const infos: Array<{ m: string; c?: Json }> = [];
    const log: FantasyLogger = {
      info: (m, c) => { infos.push({ m, c }); },
      warn: () => undefined,
    };
    await runLifecycleSweep(db, AFTER_LOCK2, log); // GW2 lock + finalize
    expect(await db.read(`${fRoot}/TransferState/latecomer`)).toEqual(latecomer);
    // The skip is not silent: one info line says who and why.
    const skipped = infos.filter((i) => i.m.startsWith('fantasy transfers: rollover skipped'));
    expect(skipped).toHaveLength(1);
    expect(skipped[0].m).toBe(
      'fantasy transfers: rollover skipped — manager already working on a later week');
    expect(skipped[0].c).toMatchObject({ uid: 'latecomer', gw: 2, workingOn: 4 });
  });

  it('the Free Hit restore and the chip switch-off stay scored-only', async () => {
    const db = new FakeDb(world2());
    // A manager with a GW1 locked squad and a stale Free Hit marker, but no
    // squad at the GW2 lock (not scored): nothing may be restored for him.
    f(db).PublishedPicks[1].ghost = fixtureSquad('alpha');
    f(db).TransferState = {
      ghost: { Free: 2, UsedThisGw: 0, ChipPlayed: 'freeHit', RolledGw: 1 },
    };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${fRoot}/History/2/ghost`)).toBeNull();
    expect(await db.read(`${fRoot}/Squads/ghost`)).toBeNull(); // no restore
    // He still rolls (Free 2 + 2, next baseline = the squad after GW2: none).
    expect(await db.read(`${fRoot}/TransferState/ghost`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 2, CountFromGw: 3,
    });
  });
});
