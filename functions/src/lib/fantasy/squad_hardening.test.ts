// Squad hardening (audit I2/I3, owner-approved 2026-11-01) over the
// in-memory FantasyDb: the lock's integrity pass (snapshot verbatim +
// Invalid, SquadAlerts, warn), the zero score at finalize, the first-run
// live-Squads fallback judged the same way, rerun idempotency, and the
// integrity alert's lifecycle. Two-gameweek world (test_support.ts world2):
// GW1 finalized with the golden squads, GW2 the week under test.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, recordSquadSave, runLifecycleSweep,
} from './orchestration';
import { writeTimeOf } from './orchestration_db';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, fixtureIds, fixtureSquad, GW2_DATE, LOCK2_MS,
  world2,
} from './test_support';

const fRoot = F_ROOT;
const NOW = AFTER_LOCK2.getTime();

function capture(): {
  log: FantasyLogger; warns: Array<{ m: string; c?: Json }>;
  infos: Array<{ m: string; c?: Json }>;
} {
  const warns: Array<{ m: string; c?: Json }> = [];
  const infos: Array<{ m: string; c?: Json }> = [];
  return {
    warns, infos,
    log: {
      info: (m, c) => { infos.push({ m, c }); },
      warn: (m, c) => { warns.push({ m, c }); },
    },
  };
}

const f = (db: FakeDb) => db.data.Fantasy.Futsal['15'];

/** The GW2 kinds of invalid squad, each built from a golden squad. */
const INVALID_CASES: Array<{
  name: string; issues: string[]; mutate: (db: FakeDb) => void;
}> = [
  {
    name: 'duplicatePlayer',
    issues: ['duplicatePlayer'],
    // Dana (80) out, a second Eva (50) in: 450, no budget problem.
    mutate: (db) => { f(db).Squads.alpha.picks[1] = clone(f(db).Squads.alpha.picks[2]); },
  },
  {
    name: 'tooManyPlayers',
    issues: ['tooManyPlayers', 'overBudget'],
    mutate: (db) => {
      f(db).Squads.alpha.picks.push(
        { playerId: 'Sam', position: 'GK', priceTenths: 85, bench: true });
    },
  },
  {
    name: 'overBudget (client claims a low price)',
    issues: ['overBudget'],
    // Eli (55) out, Sam (85 at market) in at a claimed 10: really 510.
    mutate: (db) => {
      f(db).Squads.alpha.picks[0] =
        { playerId: 'Sam', position: 'GK', priceTenths: 10, bench: false };
    },
  },
  {
    name: 'unknownPlayer',
    issues: ['unknownPlayer'],
    mutate: (db) => {
      f(db).Squads.alpha.picks[6] =
        { playerId: 'Ghost', position: 'ATT', priceTenths: 75, bench: true };
    },
  },
  {
    name: 'ineligiblePlayer (a NEW guest pick)',
    issues: ['ineligiblePlayer'],
    mutate: (db) => {
      f(db).Players.Bo.eligible = false;
      f(db).Squads.alpha.picks[0] =
        { playerId: 'Bo', position: 'GK', priceTenths: 75, bench: false };
    },
  },
];

describe('lock + finalize: an invalid squad scores zero, snapshot kept, alerted', () => {
  for (const c of INVALID_CASES) {
    it(c.name, async () => {
      const db = new FakeDb(world2());
      c.mutate(db);
      const submitted = clone(f(db).Squads.alpha);
      const { log, warns } = capture();
      await runLifecycleSweep(db, AFTER_LOCK2, log);

      // Snapshot: verbatim + the verdict + the baseline's realizedTenths
      // (GW1 carried none: 0; no sale is credited for an invalid week).
      expect(await db.read(`${fRoot}/PublishedPicks/2/alpha`))
        .toEqual({ ...submitted, Invalid: c.issues, realizedTenths: 0 });
      // Finalize: zero, the verdict kept, the squad visible, no Breakdown.
      const row = await db.read(`${fRoot}/History/2/alpha`) as Json;
      expect(row['TotalTenths']).toBe(0);
      expect(row['Invalid']).toEqual(c.issues);
      expect(row['realizedTenths']).toBe(0);
      expect(row['picks']).toEqual(submitted.picks);
      expect('Breakdown' in row).toBe(false);
      expect(await db.read(`${fRoot}/Leaderboards/Gameweek/2/alpha`))
        .toMatchObject({ points: 0 });
      // GW1's 35 points stand; GW2 adds nothing.
      expect((await db.read(`${fRoot}/Leaderboards/Overall/alpha`) as Json)['points'])
        .toBe(35);
      // The fan banner's alert, and a loud log line.
      expect(await db.read(`${fRoot}/SquadAlerts/alpha`)).toEqual({
        Gw: 2, Kind: 'invalid', Issues: c.issues, CreatedAt: NOW,
      });
      expect(warns.some((w) => w.m.includes('invalid squad') &&
        w.c?.['uid'] === 'alpha')).toBe(true);
      // The other managers are untouched.
      expect('Invalid' in (await db.read(`${fRoot}/History/2/boost`) as Json)).toBe(false);
      expect(await db.read(`${fRoot}/SquadAlerts/boost`)).toBeNull();
    });
  }

  it('a rerun (score edit + later sweeps) is byte-identical', async () => {
    const db = new FakeDb(world2());
    INVALID_CASES[2].mutate(db);
    await runLifecycleSweep(db, AFTER_LOCK2);
    const settled = db.snapshot();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(db.snapshot()).toEqual(settled);
  });

  it('every squad valid: no marker, no alert, no warn (the old behaviour)', async () => {
    const db = new FakeDb(world2());
    const { log, warns } = capture();
    await runLifecycleSweep(db, AFTER_LOCK2, log);
    for (const uid of ['alpha', 'boost', 'churn']) {
      const snap = await db.read(`${fRoot}/PublishedPicks/2/${uid}`) as Json;
      expect('Invalid' in snap, uid).toBe(false);
      const row = await db.read(`${fRoot}/History/2/${uid}`) as Json;
      expect('Invalid' in row, uid).toBe(false);
      expect(Array.isArray(row['Breakdown']), uid).toBe(true);
    }
    expect(await db.read(`${fRoot}/SquadAlerts`)).toBeNull();
    expect(warns.filter((w) => w.m.includes('invalid squad'))).toEqual([]);
  });

  it("held players whose price ROSE since the buy keep a legal squad legal", async () => {
    const db = new FakeDb(world2());
    // churn spent exactly 500 in GW1; two of his players rose since.
    f(db).Players.Ben.priceTenths = 120;
    f(db).Players.Dana.priceTenths = 110;
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect('Invalid' in (await db.read(`${fRoot}/PublishedPicks/2/churn`) as Json))
      .toBe(false);
    expect((await db.read(`${fRoot}/History/2/churn`) as Json)['TotalTenths'])
      .not.toBe(0);
  });

  it('a guest made ineligible AFTER the buy stays with his holders', async () => {
    const db = new FakeDb(world2());
    f(db).Players.Wren.eligible = false; // held by all three golden squads
    await runLifecycleSweep(db, AFTER_LOCK2);
    for (const uid of ['alpha', 'boost', 'churn']) {
      expect('Invalid' in (await db.read(`${fRoot}/PublishedPicks/2/${uid}`) as Json), uid)
        .toBe(false);
    }
  });

  it('FPL selling: the snapshot stores the judged prices + realizedTenths, '
    + 'and History carries it', async () => {
    const db = new FakeDb(world2());
    f(db).PublishedPicks[1].alpha.realizedTenths = 3; // earlier sales
    // alpha sells Alex (bought at 95, now 115: sells for 105, +10) for Ben
    // (85), and lowballs held Dana (paid 80) — the client's price for a
    // held player is ignored.
    f(db).Players.Alex.priceTenths = 115;
    f(db).Squads.alpha.picks[4] =
      { playerId: 'Ben', position: 'ATT', priceTenths: 85, bench: false };
    f(db).Squads.alpha.viceId = 'Ben';
    f(db).Squads.alpha.picks[1].priceTenths = 10;
    const submitted = clone(f(db).Squads.alpha);
    await runLifecycleSweep(db, AFTER_LOCK2);

    const judged = clone(submitted);
    judged.picks[1].priceTenths = 80;
    expect(await db.read(`${fRoot}/PublishedPicks/2/alpha`))
      .toEqual({ ...judged, realizedTenths: 13 }); // 3 + 10
    const row = await db.read(`${fRoot}/History/2/alpha`) as Json;
    expect(row['realizedTenths']).toBe(13);
    expect(row['picks'][1]['priceTenths']).toBe(80);
    expect('Invalid' in row).toBe(false);
    expect(row['TotalTenths']).not.toBe(0);
    // Unchanged squads carry their (absent = 0) realized forward too.
    expect((await db.read(`${fRoot}/PublishedPicks/2/boost`) as Json)['realizedTenths'])
      .toBe(0);
  });

  it('a Monday-morning buy at last week\'s price (PriceHistory/<gw-1>) is legal', async () => {
    const db = new FakeDb(world2());
    // alpha (480) swaps Eva (50) for Bea, who was 70 last week and is 75 now.
    f(db).PriceHistory = { 1: { Bea: 70 } };
    f(db).Players.Bea.priceTenths = 75;
    f(db).Squads.alpha.picks[2] =
      { playerId: 'Bea', position: 'DEF', priceTenths: 70, bench: false };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect('Invalid' in (await db.read(`${fRoot}/PublishedPicks/2/alpha`) as Json))
      .toBe(false);
  });
});

describe('first finalize WITHOUT a lock snapshot (live-Squads fallback)', () => {
  it('judges the live squads like the lock would: zero + alert, rerun identical', async () => {
    const db = new FakeDb(world2());
    INVALID_CASES[0].mutate(db); // duplicate
    // No sweep ran: no PublishedPicks/2, no TransferCosts/2.
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(await db.read(`${fRoot}/PublishedPicks/2`)).toBeNull();
    const row = await db.read(`${fRoot}/History/2/alpha`) as Json;
    expect(row).toMatchObject({ TotalTenths: 0, Invalid: ['duplicatePlayer'] });
    expect(await db.read(`${fRoot}/SquadAlerts/alpha`)).toMatchObject(
      { Gw: 2, Kind: 'invalid', Issues: ['duplicatePlayer'] });
    expect('Invalid' in (await db.read(`${fRoot}/History/2/boost`) as Json)).toBe(false);

    // A rerun reads History (the marker is the law) — identical.
    const settled = db.snapshot();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(db.snapshot()).toEqual(settled);
  });

  it('a snapshot source is never re-judged, even if the market changed since', async () => {
    const db = new FakeDb(world2());
    await runLifecycleSweep(db, new Date(AFTER_LOCK2.getTime() - 50 * 60 * 1000));
    // Games not final yet? world2 GW2 games are final, so the sweep may have
    // finalized already; either way the snapshot exists and is clean.
    expect(await db.read(`${fRoot}/PublishedPicks/2/alpha`)).not.toBeNull();
    f(db).Players.Alex.eligible = false;
    f(db).Players.Alex.priceTenths = 150;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect('Invalid' in (await db.read(`${fRoot}/History/2/alpha`) as Json)).toBe(false);
  });
});

describe('the integrity alert lifecycle', () => {
  const stale = { Gw: 1, Kind: 'invalid', Issues: ['overBudget'], CreatedAt: 5 };

  it('a clean squad at the next lock clears it; a position alert is left alone', async () => {
    const db = new FakeDb(world2());
    const position = { Gw: 2, Changes: [{ player: 'Wren', from: 'ATT', to: 'DEF' }], CreatedAt: 6 };
    f(db).SquadAlerts = { alpha: clone(stale), boost: clone(position) };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${fRoot}/SquadAlerts/alpha`)).toBeNull();
    expect(await db.read(`${fRoot}/SquadAlerts/boost`)).toEqual(position);
  });

  it('a save clears it only when the saved squad would pass the next lock', async () => {
    const db = new FakeDb(world2()); // GW2 open
    f(db).SquadAlerts = { alpha: clone(stale) };
    // Still over budget: Sam (85) at a claimed 10 — alert stays.
    INVALID_CASES[2].mutate(db);
    await recordSquadSave(db, { sport: 'Futsal', season: '15', uid: 'alpha',
      nowUtc: new Date(AFTER_LOCK2.getTime() - 2 * 3600 * 1000) });
    expect(await db.read(`${fRoot}/SquadAlerts/alpha`)).toEqual(stale);
    // Fixed: back to the legal golden squad — alert cleared.
    f(db).Squads.alpha = fixtureSquad('alpha');
    await recordSquadSave(db, { sport: 'Futsal', season: '15', uid: 'alpha',
      nowUtc: new Date(AFTER_LOCK2.getTime() - 2 * 3600 * 1000) });
    expect(await db.read(`${fRoot}/SquadAlerts/alpha`)).toBeNull();
  });
});

describe('post-lock saves (audit I3)', () => {
  const MIN = 60 * 1000;
  const save = (db: FakeDb, at: number, log?: FantasyLogger) => recordSquadSave(db,
    { sport: 'Futsal', season: '15', uid: 'churn', nowUtc: new Date(at), log });
  /** churn sells Bo for Wes (one transfer) — GwState still says 'open'. */
  const transfer = (db: FakeDb) => { f(db).Squads.churn.picks[0].playerId = 'Wes'; };

  it('a save before the lock is counted', async () => {
    const db = new FakeDb(world2());
    transfer(db);
    await save(db, LOCK2_MS - MIN);
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it('a save AT or after lockAtUtc is not counted, even while GwState says open', async () => {
    for (const at of [LOCK2_MS, LOCK2_MS + 7 * MIN]) {
      const db = new FakeDb(world2());
      transfer(db);
      const { log, infos } = capture();
      await save(db, at, log);
      expect(await db.read(`${fRoot}/TransferState/churn`), String(at)).toBeNull();
      expect(infos.some((i) => i.m.includes('after the lock') &&
        i.c?.['gw'] === 2 && i.c?.['lockAtUtc'] === LOCK2_MS)).toBe(true);
    }
  });

  it("a post-lock save made earlier keeps its count — a late one doesn't re-count", async () => {
    const db = new FakeDb(world2());
    transfer(db);
    await save(db, LOCK2_MS - MIN); // counted: 1 transfer
    f(db).Squads.churn.picks[4].playerId = 'Alex'; // a second sale, after the lock
    await save(db, LOCK2_MS + MIN);
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
  });

  it("under the owner's effective 'open' override the window is extended: counted", async () => {
    const db = new FakeDb(world2());
    f(db).Config.lockOverride = 'open';
    f(db).Config.lockOverrideUntil = LOCK2_MS + 60 * MIN;
    transfer(db);
    await save(db, LOCK2_MS + 7 * MIN);
    expect(await db.read(`${fRoot}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 1, SavedGw: 2,
      CountFromGw: 2, CountFrom: fixtureIds('churn'),
    });
    // Once the override has expired, the lock instant rules again.
    const late = new FakeDb(world2());
    f(late).Config.lockOverride = 'open';
    f(late).Config.lockOverrideUntil = LOCK2_MS + 5 * MIN;
    transfer(late);
    await save(late, LOCK2_MS + 7 * MIN);
    expect(await db.read(`${fRoot}/TransferState/churn`)).not.toBeNull();
    expect(await late.read(`${fRoot}/TransferState/churn`)).toBeNull();
  });

  it('the trigger judges the WRITE time (event.time), not when it runs', () => {
    const fallback = new Date(LOCK2_MS + 3000);
    expect(writeTimeOf('2026-06-28T21:59:59.000Z', fallback).getTime())
      .toBe(LOCK2_MS - 1000);
    expect(writeTimeOf(undefined, fallback)).toBe(fallback);
    expect(writeTimeOf('', fallback)).toBe(fallback);
    expect(writeTimeOf('not a date', fallback)).toBe(fallback);
  });
});

describe('a first finalize without a lock snapshot warns when late (audit I3)', () => {
  const MIN = 60 * 1000;
  const finalizeAt = async (db: FakeDb, at: number) => {
    const { log, warns } = capture();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: new Date(at), log,
    });
    return warns.filter((w) => w.m.includes('without a lock snapshot'));
  };

  it('more than 30 minutes after the lock: a loud warn (squads read live)', async () => {
    const warns = await finalizeAt(new FakeDb(world2()), LOCK2_MS + 31 * MIN);
    expect(warns).toHaveLength(1);
    expect(warns[0].c).toMatchObject({ gw: 2, minutesAfterLock: 31, squads: 3 });
  });

  it('within 30 minutes: no warn (the sweep may simply not have run yet)', async () => {
    expect(await finalizeAt(new FakeDb(world2()), LOCK2_MS + 29 * MIN)).toEqual([]);
  });

  it('with the lock snapshot present: no warn, however late', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games not final at the sweep
    await runLifecycleSweep(db, new Date(LOCK2_MS + 5 * MIN)); // snapshot only
    expect(await db.read(`${fRoot}/PublishedPicks/2`)).not.toBeNull();
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    expect(await finalizeAt(db, LOCK2_MS + 300 * MIN)).toEqual([]);
    expect(await db.read(`${fRoot}/History/2`)).not.toBeNull();
  });
});
