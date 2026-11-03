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
  AFTER_LOCK2, F_ROOT, FakeDb, fixtureSquad, GW2_DATE, world2,
} from './test_support';

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
    });

    // Undoing one transfer before the deadline un-counts it.
    churn.picks[0].playerId = 'Bo';
    await recordSquadSave(db, saveArgs('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
    });
  });

  it('first-ever squad: no transfer accounting, but SavedGw is stamped', async () => {
    const db = new FakeDb(world2());
    db.data.Fantasy.Futsal['15'].Squads.newbie = fixtureSquad('alpha');
    await recordSquadSave(db, saveArgs('newbie'));
    expect(await db.read(`${fRoot}/TransferState/newbie`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2,
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
    });
    // Undoing one in the window un-counts it, exactly as outside a pause.
    churn.picks[0].playerId = 'Bo';
    await recordSquadSave(db, at('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
    });
    // A server write in the window recounts but never stamps SavedGw.
    db.data.Fantasy.Futsal['15'].TransferState.churn.SavedGw = 1;
    churn.ServerWriteAt = OPEN_NOW.getTime();
    await recordSquadSave(db, at('churn'));
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 1,
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
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2, RolledGw: 2,
    });
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 2,
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
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 1,
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
