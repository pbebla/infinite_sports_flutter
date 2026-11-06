// P4 Phases B–D orchestration over an in-memory FantasyDb — lifecycle
// transitions, lock-snapshot once-only, the finalize pipeline end to end on
// REAL production node shapes (absent-only attendance, Line Ups rosters,
// list Date nodes), rerun idempotence, and Monday repricing. Every expected
// number is hand-computed (fixture _notes + the derivations in comments
// below), never copied from pipeline output.

import { describe, expect, it } from 'vitest';
import { STARTER_CATALOG } from './badges';
import { clone, Json, loadGoldenFixture } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, publishSaleBaselines, recordSquadSave,
  runLifecycleSweep, runMondayReprice,
} from './orchestration';
import { configFromMap } from './fantasy_config';
import {
  FantasyDb, FantasyTxResult, loadSeasonGameweeks, nodeExists,
} from './orchestration_db';
import {
  AFTER_LOCK2, F_ROOT, FakeDb as ColdFakeDb, FakePusher, fixtureSquad,
  GW1_DATE, GW2_DATE, LOCK2_MS, world2,
} from './test_support';

const fixture = loadGoldenFixture();

// 2026-06-28 is a Sunday; futsal default lockHour 15 => lock 22:00Z (PDT).
const DATE_KEY = '06282026';
const LOCK_MS = Date.UTC(2026, 5, 28, 22);
const BEFORE_LOCK = new Date(Date.UTC(2026, 5, 28, 10));
const AFTER_LOCK = new Date(Date.UTC(2026, 5, 28, 23));

// Hand-computed golden week points (base + bonus; fixture _notes).
const WEEK_POINTS: Record<string, number> = {
  Sam: 9, Dana: 13, Alex: 12, Wes: 1, Will: -4, Wren: 3,
  Eli: 0, Eva: -3, Ezra: 0, Bo: 12, Bea: 15, Ben: 9,
};

class FakeDb implements FantasyDb {
  data: Record<string, any>;
  writes: string[] = [];

  constructor(seed: Record<string, any>) {
    this.data = seed;
  }

  private parts(path: string): string[] {
    return path.split('/').filter((p) => p.length > 0);
  }

  async read(path: string): Promise<unknown> {
    let node: any = this.data;
    for (const p of this.parts(path)) {
      if (node === null || node === undefined || typeof node !== 'object') {
        return null;
      }
      node = Array.isArray(node) ? node[Number(p)] : node[p];
    }
    return node === undefined ? null : node;
  }

  async exists(path: string): Promise<boolean> {
    return nodeExists(await this.read(path));
  }

  async write(path: string, value: unknown): Promise<void> {
    this.writes.push(path);
    const parts = this.parts(path);
    let node: any = this.data;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') {
        node[p] = {};
      }
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) {
      delete node[last];
    } else {
      node[last] = clone(value);
    }
  }

  async writeIfAbsent(path: string, value: unknown): Promise<boolean> {
    if ((await this.read(path)) !== null) return false;
    await this.write(path, value);
    return true;
  }

  async transaction(
    path: string, update: (current: unknown) => unknown,
  ): Promise<FantasyTxResult> {
    const current = await this.read(path);
    const next = update(current === null ? null : clone(current));
    if (next === undefined) return { committed: false, value: current };
    if (!(next === null && current === null)) await this.write(path, next);
    return { committed: true, value: next === null ? null : clone(next) };
  }

  snapshot(): string {
    return JSON.stringify(this.data);
  }

  writeCount(suffix: string): number {
    return this.writes.filter((w) => w.endsWith(suffix)).length;
  }
}

/** The production world: golden games under a real Date list node with the
 *  ABSENT-ONLY attendance shape the Manager writes (Ezra false on the
 *  Eagles' game), Line Ups rosters, market, squads. */
function world(opts: {
  gameStatus?: number;
  lockOverride?: string;
  extraDates?: Record<string, unknown>;
} = {}): Record<string, any> {
  const games: Json[] = fixture['games'];
  const g1 = clone(games[0]['node']) as Json;
  const g2 = clone(games[1]['node']) as Json;
  g2['team1attendance'] = { Ezra: false }; // Eagles are team1 of game 2
  if (opts.gameStatus !== undefined) {
    g1['status'] = opts.gameStatus;
    g2['status'] = opts.gameStatus;
  }
  const players: Json = {};
  for (const p of fixture['players'] as Json[]) {
    players[p['id']] = {
      position: p['position'], priceTenths: p['priceTenths'], eligible: true,
      teamName: p['team'],
    };
  }
  const squads: Json = {};
  for (const s of fixture['squads'] as Json[]) {
    squads[s['name']] = clone(s['squad']);
  }
  return {
    Fantasy: {
      Futsal: {
        '15': {
          Config: {
            lockHour: 15,
            ...(opts.lockOverride ? { lockOverride: opts.lockOverride } : {}),
          },
          Players: players,
          Squads: squads,
        },
      },
    },
    Futsal: {
      '15': {
        Date: { [DATE_KEY]: [g1, g2], ...(opts.extraDates ?? {}) },
        'Line Ups': {
          Sharks: { Sam: { n: 1 }, Dana: { n: 2 }, Alex: { n: 3 } },
          Wolves: { Wes: { n: 1 }, Will: { n: 2 }, Wren: { n: 3 } },
          Eagles: { Eli: { n: 1 }, Eva: { n: 2 }, Ezra: { n: 3 } },
          Bulls: { Bo: { n: 1 }, Bea: { n: 2 }, Ben: { n: 3 } },
        },
      },
    },
  };
}

const fRoot = 'Fantasy/Futsal/15';

describe('lifecycle sweep (Phase B)', () => {
  it('writes GwState open once before lock, idempotent on resweep', async () => {
    const db = new FakeDb(world());
    await runLifecycleSweep(db, BEFORE_LOCK);
    expect(db.data.Fantasy.Futsal['15'].GwState).toEqual({
      current: 1, status: 'open', lockAtUtc: LOCK_MS, date: DATE_KEY,
    });
    expect(await db.read(`${fRoot}/PublishedPicks/1`)).toBeNull();
    await runLifecycleSweep(db, BEFORE_LOCK);
    expect(db.writeCount('GwState')).toBe(1); // no-op second pass
  });

  it('at lock: GwState locked + Squads snapshotted to PublishedPicks once, never overwritten', async () => {
    const db = new FakeDb(world({ gameStatus: 1 })); // games still live
    await runLifecycleSweep(db, AFTER_LOCK);
    expect((await db.read(`${fRoot}/GwState`) as Json)['status']).toBe('locked');
    const published = await db.read(`${fRoot}/PublishedPicks/1`) as Json;
    expect(Object.keys(published).sort()).toEqual(['alpha', 'boost', 'churn']);
    expect(published['alpha']['captainId']).toBe('Ezra');
    expect(await db.read(`${fRoot}/History/1`)).toBeNull(); // nothing final yet

    // Post-lock squad edit must never leak into the published snapshot.
    db.data.Fantasy.Futsal['15'].Squads.alpha.captainId = 'Alex';
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(((await db.read(`${fRoot}/PublishedPicks/1`)) as Json)['alpha']['captainId'])
      .toBe('Ezra');
  });

  it('backstop finalizes a completed locked match day and lands finalized in the same sweep', async () => {
    const db = new FakeDb(world()); // fixture games are status 2
    await runLifecycleSweep(db, AFTER_LOCK);

    // Snapshot happened BEFORE finalize, so the squads source is the lock
    // snapshot; totals are the golden gross tenths (no transfer costs in
    // Phase C): alpha 350, boost 440, churn 595 -> 35/44/59 points.
    const history = await db.read(`${fRoot}/History/1`) as Json;
    expect(history['alpha']['TotalTenths']).toBe(350);
    expect(history['boost']['TotalTenths']).toBe(440);
    expect(history['churn']['TotalTenths']).toBe(595);
    expect(await db.read(`${fRoot}/Leaderboards/Gameweek/1`)).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 59, rank: 1 },
    });
    expect(await db.read(`${fRoot}/Leaderboards/Overall`)).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 59, rank: 1 },
    });
    // RankHistory (whole node, next to Overall): rank after GW1 = Overall.
    expect(await db.read(`${fRoot}/Leaderboards/RankHistory`)).toEqual({
      alpha: { '1': 3 },
      boost: { '1': 2 },
      churn: { '1': 1 },
    });
    expect(await db.read(`${fRoot}/PlayerWeeks/1`)).toEqual(WEEK_POINTS);
    // PlayerWeekStats/1: the whole week node, Games from Players/<n>/teamName
    // (hand math: Dana = plays 1 + goal 6 + assist 4 + bonus 2; Ezra was
    // marked absent on the Eagles' game, so Played false but the game lists).
    const stats = await db.read(`${fRoot}/PlayerWeekStats/1`) as Json;
    expect(Object.keys(stats).sort()).toEqual(Object.keys(WEEK_POINTS).sort());
    expect(stats['Dana']).toEqual({
      Pts: 13, Played: true, GP: 1,
      Games: [{ Vs: 'Wolves', For: 3, Against: 1 }],
      Lines: {
        plays: { N: 1, P: 1 }, goals: { N: 1, P: 6 },
        assists: { N: 1, P: 4 }, bonus: { N: 2, P: 2 },
      },
    });
    expect(stats['Ezra']).toEqual({
      Pts: 0, Played: false, GP: 0,
      Games: [{ Vs: 'Bulls', For: 0, Against: 2 }],
    });
    expect(((await db.read(`${fRoot}/PlayerTotals`)) as Json)['Bea'])
      .toEqual({ points: 15, ownershipPct: 67, form: 150, ppg: 150, games: 1 });
    expect(((await db.read(`${fRoot}/DreamTeam/1`)) as Json)['Players']).toEqual([
      { name: 'Bo', position: 'GK', points: 12 },
      { name: 'Bea', position: 'DEF', points: 15 },
      { name: 'Dana', position: 'DEF', points: 13 },
      { name: 'Alex', position: 'ATT', points: 12 },
      { name: 'Ben', position: 'ATT', points: 9 },
    ]);
    expect((await db.read(`${fRoot}/GwState`) as Json)['status']).toBe('finalized');

    // Resweep: byte-identical world (idempotence is the debounce).
    const before = db.snapshot();
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(db.snapshot()).toBe(before);
  });

  it("lockOverride 'locked'/'open' freezes the machine (zero writes)", async () => {
    for (const lockOverride of ['locked', 'open']) {
      const db = new FakeDb(world({ lockOverride }));
      // The global badge catalog is seeded on every run, frozen or not
      // (badges.test.ts); with it already in place the frozen season gets
      // zero writes.
      db.data.Fantasy.BadgeCatalog = clone(STARTER_CATALOG);
      await runLifecycleSweep(db, AFTER_LOCK);
      expect(db.writes).toEqual([]);
    }
  });

  it('season over (no current gameweek): GwState untouched, finalized weeks stay', async () => {
    const db = new FakeDb(world());
    db.data.Fantasy.Futsal['15'].History = { 1: { alpha: { TotalTenths: 350 } } };
    await runLifecycleSweep(db, new Date(Date.UTC(2026, 7, 15)));
    expect(await db.read(`${fRoot}/GwState`)).toBeNull();
  });
});

describe('match-day finalize trigger entry (Phase C)', () => {
  it('finalizes the completed date, falling back to live Squads when no snapshot exists', async () => {
    const db = new FakeDb(world());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    const history = await db.read(`${fRoot}/History/1`) as Json;
    expect(history['churn']['TotalTenths']).toBe(595);
    // The fallback scores from Squads but never publishes picks itself.
    expect(await db.read(`${fRoot}/PublishedPicks/1`)).toBeNull();
    expect(await db.read(`${fRoot}/Leaderboards/Gameweek/1`)).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 59, rank: 1 },
    });
  });

  it('a date that finishes before its lock waits (History is public — no pre-lock leak)', async () => {
    const db = new FakeDb(world());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: BEFORE_LOCK,
    });
    expect(db.writes).toEqual([]);
  });

  it('waits while any game of the date is still live', async () => {
    const db = new FakeDb(world());
    db.data.Futsal['15'].Date[DATE_KEY][1].status = 1;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(db.writes).toEqual([]);
  });

  it('silent no-op without a Fantasy Config; frozen override stands down', async () => {
    const noConfig = new FakeDb(world());
    delete noConfig.data.Fantasy.Futsal['15'].Config;
    await maybeFinalizeGame(noConfig, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(noConfig.writes).toEqual([]);

    const frozen = new FakeDb(world({ lockOverride: 'locked' }));
    await maybeFinalizeGame(frozen, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(frozen.writes).toEqual([]);
  });

  it('a post-final edit re-settles everything; admin-edited DreamTeam survives', async () => {
    const db = new FakeDb(world());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });

    // Admin swaps the Dream Team (Auto flag gone = admin owns it now).
    db.data.Fantasy.Futsal['15'].DreamTeam['1'] =
      { Players: [{ name: 'OwnerPick', position: 'GK', points: 1 }] };

    // Score correction: Eagles 1–2 Bulls (team1score 0 -> 1). Bulls lose
    // their clean sheets. Hand math: Bo base 1+2(saves)=3, BPS 8; Bea base
    // 1+4+2(dpl)=7, BPS 9+10=19; Ben base 1+4=5, BPS 12. Bonus unchanged
    // order: Bea 3, Ben 2, Bo 1 -> weeks Bo 4, Bea 10, Ben 7.
    // Squads: alpha has no Bulls -> 350 (35). boost: 90 + Bea 10*2*10=200 -
    // 40 + Ben 70 + Wren 30 + Eva(boost full) -30 + Ezra 0 = 320 (32).
    // churn: Bo 40 + Dana 130 + Bea 100 + Ezra 0 + Ben(cap) 140 + Eva(bench
    // half) -15 + Wren(auto-sub full) 30 = 425 (42).
    db.data.Futsal['15'].Date[DATE_KEY][1].team1score = 1;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });

    expect(await db.read(`${fRoot}/PlayerWeeks/1`)).toEqual({
      ...WEEK_POINTS, Bo: 4, Bea: 10, Ben: 7,
    });
    const history = await db.read(`${fRoot}/History/1`) as Json;
    expect(history['alpha']['TotalTenths']).toBe(350);
    expect(history['boost']['TotalTenths']).toBe(320);
    expect(history['churn']['TotalTenths']).toBe(425);
    expect(await db.read(`${fRoot}/Leaderboards/Gameweek/1`)).toEqual({
      alpha: { points: 35, rank: 2 },
      boost: { points: 32, rank: 3 },
      churn: { points: 42, rank: 1 },
    });
    expect(((await db.read(`${fRoot}/PlayerTotals`)) as Json)['Bo'])
      .toEqual({ points: 4, ownershipPct: 33, form: 40, ppg: 40, games: 1 });
    // The admin's Dream Team was left alone.
    expect(await db.read(`${fRoot}/DreamTeam/1`)).toEqual(
      { Players: [{ name: 'OwnerPick', position: 'GK', points: 1 }] });
  });

  it('rerun sources squads from History (deterministic even if live Squads changed)', async () => {
    const db = new FakeDb(world());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    // Managers churn their live squads after the week settled...
    db.data.Fantasy.Futsal['15'].Squads = {};
    expect(await db.read(`${fRoot}/Leaderboards/RankHistory`)).not.toBeNull();
    const before = db.snapshot();
    // ...and a rerun still reproduces the identical week.
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(db.snapshot()).toBe(before);
  });

  it('an old gameweek with no lock snapshot never finalizes from live Squads', async () => {
    // Two match days; both complete; nothing snapshotted or finalized.
    // Only the LATEST lock-passed gameweek (GW2, 06282026) may fall back.
    const earlier = clone(
      (world() as Json)['Futsal']['15']['Date'][DATE_KEY]);
    const db = new FakeDb(world({ extraDates: { '06212026': earlier } }));

    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: '06212026', nowUtc: AFTER_LOCK,
    });
    expect(await db.read(`${fRoot}/History/1`)).toBeNull();

    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(await db.read(`${fRoot}/History/2`)).not.toBeNull();
    expect(await db.read(`${fRoot}/History/1`)).toBeNull();

    // The sweep's backstop honors the same guard.
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(await db.read(`${fRoot}/History/1`)).toBeNull();
  });
});

describe('Monday repricing (Phase D)', () => {
  function repriceWorld(): FakeDb {
    const db = new FakeDb(world());
    db.data.Fantasy.Futsal['15'].History = { 1: { alpha: { TotalTenths: 350 } } };
    db.data.Fantasy.Futsal['15'].PlayerWeeks = { 1: { ...WEEK_POINTS } };
    return db;
  }
  const NOW = new Date(Date.UTC(2026, 5, 29, 17)); // Monday 10:00 PDT

  it('applies golden position-relative deltas, logs PriceChanges, flags Repriced', async () => {
    const db = repriceWorld();
    await runMondayReprice(db, NOW);

    // Golden reprice hand math (fixture _notes): GK mean 5.5 -> Bo +5,
    // Wes/Eli -5; DEF mean 5.25 -> Dana/Bea +5, Will/Eva -5; ATT mean 6 ->
    // Alex +5, Ezra -5. Sam/Wren/Ben hold.
    const price = async (name: string) =>
      db.read(`${fRoot}/Players/${name}/priceTenths`);
    expect(await price('Wes')).toBe(60);
    expect(await price('Eli')).toBe(50);
    expect(await price('Bo')).toBe(80);
    expect(await price('Dana')).toBe(85);
    expect(await price('Will')).toBe(55);
    expect(await price('Eva')).toBe(45);
    expect(await price('Bea')).toBe(75);
    expect(await price('Alex')).toBe(100);
    expect(await price('Ezra')).toBe(60);
    expect(await price('Sam')).toBe(85);
    expect(await price('Wren')).toBe(75);
    expect(await price('Ben')).toBe(85);

    expect(await db.read(`${fRoot}/PriceChanges/1`)).toEqual({
      Bo: { delta: 5 }, Wes: { delta: -5 }, Eli: { delta: -5 },
      Dana: { delta: 5 }, Bea: { delta: 5 }, Will: { delta: -5 },
      Eva: { delta: -5 }, Alex: { delta: 5 }, Ezra: { delta: -5 },
    });
    expect(await db.read(`${fRoot}/Repriced/1`))
      .toEqual({ At: NOW.getTime() });

    // Already repriced: the next Monday is a byte-identical no-op.
    const before = db.snapshot();
    await runMondayReprice(db, new Date(NOW.getTime() + 7 * 86400_000));
    expect(db.snapshot()).toBe(before);
  });

  it('a concurrent run that already claimed the week moves nothing (double-fire)', async () => {
    // Cloud Scheduler can double-fire; a second run must see the first
    // run's Repriced claim (even mid-flight, Pending:true) and stand down —
    // prices move exactly once.
    const db = repriceWorld();
    await db.write(`${fRoot}/Repriced/1`, { At: NOW.getTime(), Pending: true });
    await runMondayReprice(db, NOW);
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(75); // untouched
    expect(await db.read(`${fRoot}/PriceChanges/1`)).toBeNull();
    expect(await db.read(`${fRoot}/Repriced/1`))
      .toEqual({ At: NOW.getTime(), Pending: true }); // the claim is not ours to finish
  });

  // Audit M5: a run that died after its claim leaves Repriced/<gw>
  // {At, Pending:true} forever; later Mondays used to skip it silently.
  it('a stale Pending claim (> 1 h) warns for the operator and still moves nothing', async () => {
    const db = repriceWorld();
    const claimedAt = NOW.getTime() - 60 * 60 * 1000 - 1; // just over an hour
    await db.write(`${fRoot}/Repriced/1`, { At: claimedAt, Pending: true });
    db.writes = [];
    const warns: Array<{ m: string; c?: Record<string, unknown> }> = [];
    await runMondayReprice(db, NOW, {
      info: () => undefined,
      warn: (m, c) => { warns.push({ m, c }); },
    });
    expect(warns).toEqual([{
      m: 'fantasy reprice: stale Pending claim — needs operator attention',
      c: { sport: 'Futsal', season: '15', gw: 1, At: claimedAt },
    }]);
    // Never taken over: prices may be half-moved.
    expect(db.writes).toEqual([]);
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(75);
    expect(await db.read(`${fRoot}/Repriced/1`)).toEqual({ At: claimedAt, Pending: true });
  });

  it('a fresh Pending claim (a run in flight) and a done row stand down without a warning', async () => {
    for (const row of [
      { At: NOW.getTime() - 60 * 60 * 1000, Pending: true }, // exactly an hour: not yet stale
      { At: NOW.getTime() - 7 * 86400_000 }, // finished long ago
      { At: NOW.getTime() - 7 * 86400_000, Manual: true },
    ]) {
      const db = repriceWorld();
      await db.write(`${fRoot}/Repriced/1`, row);
      db.writes = [];
      const warns: string[] = [];
      await runMondayReprice(db, NOW, {
        info: () => undefined, warn: (m) => { warns.push(m); },
      });
      expect(warns, JSON.stringify(row)).toEqual([]);
      expect(db.writes, JSON.stringify(row)).toEqual([]);
    }
  });

  it('admin Manual flag stands the job down and marks the week handled', async () => {
    const db = repriceWorld();
    db.data.Fantasy.Futsal['15'].PriceChanges = { 1: { Manual: true } };
    await runMondayReprice(db, NOW);
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(75); // held
    expect(await db.read(`${fRoot}/Repriced/1`))
      .toEqual({ At: NOW.getTime(), Manual: true });
    expect(await db.read(`${fRoot}/PriceChanges/1`)).toEqual({ Manual: true });
  });

  it('a ceiling-clamped riser is not logged as a move', async () => {
    const db = repriceWorld();
    db.data.Fantasy.Futsal['15'].Players.Alex.priceTenths = 150; // at max
    await runMondayReprice(db, NOW);
    expect(await db.read(`${fRoot}/Players/Alex/priceTenths`)).toBe(150);
    expect('Alex' in (await db.read(`${fRoot}/PriceChanges/1`) as Json))
      .toBe(false);
  });

  it('ineligible players are outside the position group (they shift no mean)', async () => {
    const db = repriceWorld();
    db.data.Fantasy.Futsal['15'].Players.Ezra.eligible = false;
    await runMondayReprice(db, NOW);
    // ATT group without Ezra: {Alex 12, Wren 3, Ben 9}, mean 8, gap 4 ->
    // Alex rises, Wren falls, Ben holds; Ezra is untouched.
    const changes = await db.read(`${fRoot}/PriceChanges/1`) as Json;
    expect(changes['Alex']).toEqual({ delta: 5 });
    expect(changes['Wren']).toEqual({ delta: -5 });
    expect('Ben' in changes).toBe(false);
    expect('Ezra' in changes).toBe(false);
    expect(await db.read(`${fRoot}/Players/Ezra/priceTenths`)).toBe(65);
  });

  it('nothing finalized yet or frozen override: zero writes', async () => {
    const none = new FakeDb(world());
    await runMondayReprice(none, NOW);
    expect(none.writes).toEqual([]);

    const frozen = repriceWorld();
    frozen.data.Fantasy.Futsal['15'].Config.lockOverride = 'locked';
    await runMondayReprice(frozen, NOW);
    expect(frozen.writes).toEqual([]);
  });

  // ── Season setup + schedule, Task 5: the morning after ANY game day ──────
  // The job now runs every day at 10:00 league time. It reprices the newest
  // finalized week only when the week's date is BEFORE today (league time)
  // and teams have not reopened yet (now < lockUtc + 24 h); a week finalized
  // after the reopen is skipped for good ({Skipped:'late'}), a game day that
  // is still today waits for tomorrow's run.
  //
  // PDT is UTC-7, so 10:00 league time = 17:00Z. 2026-06-28 is a Sunday:
  // Sun lock 15:00 PDT = 22:00Z -> reopen Mon 22:00Z; the Wednesday 07/01
  // game locks Wed 22:00Z -> reopen Thu 22:00Z.
  const SUN_10 = new Date(Date.UTC(2026, 5, 28, 17));
  const TUE_10 = new Date(Date.UTC(2026, 5, 30, 17));
  const WED_KEY = '07012026';
  const WED_LOCK_MS = Date.UTC(2026, 6, 1, 22);
  const WED_10 = new Date(Date.UTC(2026, 6, 1, 17));
  const THU_10 = new Date(Date.UTC(2026, 6, 2, 17));

  /** The golden week finalized in its production shape: the game on [dateKey]
   *  with its frozen LockedWeeks/1 ledger entry. */
  function frozenWeekWorld(dateKey: string, lockMs: number): FakeDb {
    const db = repriceWorld();
    const season = db.data.Futsal['15'];
    season.Date = { [dateKey]: season.Date[DATE_KEY] };
    db.data.Fantasy.Futsal['15'].LockedWeeks = {
      1: { Date: dateKey, LockAtUtc: lockMs },
    };
    return db;
  }

  function recordingLog(): {
    log: FantasyLogger;
    warns: Array<{ m: string; c?: Record<string, unknown> }>;
  } {
    const warns: Array<{ m: string; c?: Record<string, unknown> }> = [];
    return {
      warns,
      log: { info: () => undefined, warn: (m, c) => { warns.push({ m, c }); } },
    };
  }

  const pricesOf = async (db: FakeDb) => Promise.all(
    Object.keys(WEEK_POINTS).map(
      async (n) => db.read(`${fRoot}/Players/${n}/priceTenths`)));

  it('Sunday game, Monday 10:00 -> repriced (unchanged behaviour)', async () => {
    const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
    await runMondayReprice(db, NOW);
    expect(await db.read(`${fRoot}/Repriced/1`)).toEqual({ At: NOW.getTime() });
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(80);
    expect(await db.read(`${fRoot}/Players/Wes/priceTenths`)).toBe(60);
    expect(await db.read(`${fRoot}/PriceChanges/1`)).not.toBeNull();
  });

  it('Wednesday game, Thursday 10:00 -> repriced', async () => {
    const db = frozenWeekWorld(WED_KEY, WED_LOCK_MS);
    await runMondayReprice(db, THU_10);
    expect(await db.read(`${fRoot}/Repriced/1`)).toEqual({ At: THU_10.getTime() });
    // Same golden hand math as the Sunday run: GK mean 5.5 -> Bo +5, Wes -5.
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(80);
    expect(await db.read(`${fRoot}/Players/Wes/priceTenths`)).toBe(60);
    expect(await db.read(`${fRoot}/Players/Dana/priceTenths`)).toBe(85);
    expect(await db.read(`${fRoot}/PriceChanges/1`)).toEqual({
      Bo: { delta: 5 }, Wes: { delta: -5 }, Eli: { delta: -5 },
      Dana: { delta: 5 }, Bea: { delta: 5 }, Will: { delta: -5 },
      Eva: { delta: -5 }, Alex: { delta: 5 }, Ezra: { delta: -5 },
    });
  });

  it('a daily schedule: game day waits, the morning after reprices, later days are no-ops', async () => {
    const db = frozenWeekWorld(WED_KEY, WED_LOCK_MS);
    const { log, warns } = recordingLog();

    // Wednesday 10:00 (game day, games not played yet): nothing at all.
    await runMondayReprice(db, WED_10, log);
    expect(db.writes).toEqual([]);

    // Thursday 10:00: repriced exactly once.
    await runMondayReprice(db, THU_10, log);
    expect(await db.read(`${fRoot}/Repriced/1`)).toEqual({ At: THU_10.getTime() });
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(80);

    // Friday, Saturday, ... Monday 10:00: byte-identical no-ops, no warnings
    // (a done week is neither re-repriced nor marked late).
    const before = db.snapshot();
    for (let d = 1; d <= 4; d++) {
      await runMondayReprice(db, new Date(THU_10.getTime() + d * 86400_000), log);
    }
    expect(db.snapshot()).toBe(before);
    expect(warns).toEqual([]);
  });

  it('game day itself at 10:00 -> nothing (tomorrow\'s run), whatever the weekday', async () => {
    const sunday = repriceWorld(); // History/1 already there, date = today
    await runMondayReprice(sunday, SUN_10);
    expect(sunday.writes).toEqual([]);
    expect(await sunday.read(`${fRoot}/Repriced/1`)).toBeNull();
    expect(await sunday.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(75);

    const wednesday = frozenWeekWorld(WED_KEY, WED_LOCK_MS);
    await runMondayReprice(wednesday, WED_10);
    expect(wednesday.writes).toEqual([]);
  });

  it('"today" is league time, not UTC: Sunday 19:00 PDT is already Monday in UTC and still game day', async () => {
    const db = repriceWorld();
    const sundayEvening = new Date(Date.UTC(2026, 5, 29, 2)); // Mon 02:00Z
    await runMondayReprice(db, sundayEvening);
    expect(db.writes).toEqual([]);

    // Monday 00:30 PDT (07:30Z) is the morning after: the date is before
    // today and the week has not reopened.
    await runMondayReprice(db, new Date(Date.UTC(2026, 5, 29, 7, 30)));
    expect(await db.read(`${fRoot}/Repriced/1`))
      .toEqual({ At: Date.UTC(2026, 5, 29, 7, 30) });
  });

  it('finalized after the reopen -> Repriced {Skipped:\'late\'}, a warning, no price change', async () => {
    const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
    const pricesBefore = await pricesOf(db);
    const { log, warns } = recordingLog();
    db.writes = [];

    // Tuesday 10:00: teams reopened Monday 22:00Z (Sun lock + 24 h).
    await runMondayReprice(db, TUE_10, log);

    expect(await db.read(`${fRoot}/Repriced/1`))
      .toEqual({ Skipped: 'late', At: TUE_10.getTime() });
    expect(await pricesOf(db)).toEqual(pricesBefore);
    expect(await db.read(`${fRoot}/PriceChanges/1`)).toBeNull();
    expect(db.writes).toEqual([`${fRoot}/Repriced/1`]);
    expect(warns).toHaveLength(1);
    expect(warns[0].m).toBe(
      'fantasy reprice: week finalized after teams reopened — prices not moved');
    expect(warns[0].c).toMatchObject({ sport: 'Futsal', season: '15', gw: 1 });

    // The mark is final: the next days are no-ops (no second write, no warn).
    const before = db.snapshot();
    await runMondayReprice(db, new Date(TUE_10.getTime() + 86400_000), log);
    expect(db.snapshot()).toBe(before);
    expect(warns).toHaveLength(1);
  });

  it('the reopen is exactly lockUtc + 24 h: one millisecond before reprices, at it is late', async () => {
    const reopen = LOCK_MS + 24 * 3600_000;
    const early = frozenWeekWorld(DATE_KEY, LOCK_MS);
    await runMondayReprice(early, new Date(reopen - 1));
    expect(await early.read(`${fRoot}/Repriced/1`)).toEqual({ At: reopen - 1 });
    expect(await early.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(80);

    const late = frozenWeekWorld(DATE_KEY, LOCK_MS);
    await runMondayReprice(late, new Date(reopen));
    expect(await late.read(`${fRoot}/Repriced/1`))
      .toEqual({ Skipped: 'late', At: reopen });
    expect(await late.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(75);
  });

  it('a late run never overwrites a real claim or a done row', async () => {
    // Existing rows (done, Manual, a live Pending claim): the done-check
    // stands down before any lateness mark is considered.
    for (const row of [
      { At: NOW.getTime() }, { At: NOW.getTime(), Manual: true },
      { At: NOW.getTime(), Voided: true },
      { At: TUE_10.getTime() - 60_000, Pending: true },
    ]) {
      const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
      await db.write(`${fRoot}/Repriced/1`, row);
      db.writes = [];
      await runMondayReprice(db, TUE_10);
      expect(db.writes, JSON.stringify(row)).toEqual([]);
      expect(await db.read(`${fRoot}/Repriced/1`), JSON.stringify(row)).toEqual(row);
    }

    // A claim that lands between the read and the mark (concurrent run): the
    // mark is a writeIfAbsent, so the claim survives.
    const raced = frozenWeekWorld(DATE_KEY, LOCK_MS);
    const claim = { At: TUE_10.getTime() - 5, Pending: true };
    const realRead = raced.read.bind(raced);
    let hidden = true;
    raced.read = async (path: string) => {
      if (hidden && path === `${fRoot}/Repriced/1`) {
        hidden = false;
        // The first read (the done-check) sees nothing; the run then
        // competes against the claim a concurrent job wrote just after.
        raced.data.Fantasy.Futsal['15'].Repriced = { 1: claim };
        return null;
      }
      return realRead(path);
    };
    await runMondayReprice(raced, TUE_10);
    expect(await realRead(`${fRoot}/Repriced/1`)).toEqual(claim);
    expect(await realRead(`${fRoot}/PriceChanges/1`)).toBeNull();
  });

  it('a History week the schedule no longer has: warn and do nothing', async () => {
    const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
    db.data.Fantasy.Futsal['15'].History = { 3: { alpha: { TotalTenths: 350 } } };
    const { log, warns } = recordingLog();
    db.writes = [];
    await runMondayReprice(db, NOW, log);
    expect(db.writes).toEqual([]); // not even a Skipped mark
    expect(await db.read(`${fRoot}/Repriced/3`)).toBeNull();
    expect(warns).toHaveLength(1);
    expect(warns[0].m).toBe(
      'fantasy reprice: no gameweek 3 in the schedule — skipped');
    expect(warns[0].c).toMatchObject({ sport: 'Futsal', season: '15', gw: 3 });
  });

  it('a failed schedule read aborts the season without writing or marking it late', async () => {
    const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
    const realRead = db.read.bind(db);
    db.read = async (path: string) => {
      if (path === 'Futsal/15/Date') throw new Error('read timed out');
      return realRead(path);
    };
    const { log, warns } = recordingLog();
    db.writes = [];
    await runMondayReprice(db, TUE_10, log); // would be "late" if it read fine
    expect(db.writes).toEqual([]);
    expect(warns.map((w) => w.m)).toEqual(['fantasy reprice: season failed']);
  });

  // Final review I5: the job tries hourly 10:00-15:00 league time
  // (fantasy_lifecycle.ts), so a failed attempt is retried the same morning.
  it('hourly attempts: a 10:00 run that failed before its claim is retried at '
    + '11:00 and reprices; the 12:00 run is a no-op', async () => {
    const db = frozenWeekWorld(DATE_KEY, LOCK_MS);
    const realRead = db.read.bind(db);
    let failed = false;
    db.read = async (path: string) => {
      if (!failed && path === 'Futsal/15/Date') {
        failed = true;
        throw new Error('read timed out');
      }
      return realRead(path);
    };
    const { log, warns } = recordingLog();
    await runMondayReprice(db, NOW, log); // Monday 10:00: the read fails
    expect(failed).toBe(true);
    expect(await db.read(`${fRoot}/Repriced/1`)).toBeNull();
    expect(warns.map((w) => w.m)).toEqual(['fantasy reprice: season failed']);

    const eleven = new Date(NOW.getTime() + 3600_000);
    await runMondayReprice(db, eleven, log);
    expect(await db.read(`${fRoot}/Repriced/1`)).toEqual({ At: eleven.getTime() });
    expect(await db.read(`${fRoot}/Players/Bo/priceTenths`)).toBe(80);

    const before = db.snapshot();
    db.writes = [];
    await runMondayReprice(db, new Date(NOW.getTime() + 2 * 3600_000), log);
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);
    expect(warns).toHaveLength(1);
  });
});

// Round 3 spec §3.2: the lock step records the price every market player has
// DURING the gameweek in PriceHistory/<gw>, claimed once on its OWN
// set-if-absent — independent of the PublishedPicks claim, so a week with no
// squads still records prices. Expected prices are the golden fixture's
// priceTenths (golden_gameweek.json players).
const GOLDEN_PRICES: Record<string, number> = {
  Sam: 85, Wes: 65, Eli: 55, Bo: 75, Dana: 80, Will: 60,
  Eva: 50, Bea: 70, Alex: 95, Wren: 75, Ezra: 65, Ben: 85,
};
const LATER_SWEEP = new Date(AFTER_LOCK.getTime() + 15 * 60_000);

describe('PriceHistory at lock (round 3 spec 3.2)', () => {
  it('lock snapshots PriceHistory once, even with no squads', async () => {
    const seed = world({ gameStatus: 1 }); // games live: lock only
    delete seed.Fantasy.Futsal['15'].Squads;
    const db = new FakeDb(seed);

    await runLifecycleSweep(db, AFTER_LOCK);
    // No squads: the picks claim never happens, but prices are recorded.
    expect(await db.read(`${fRoot}/PublishedPicks/1`)).toBeNull();
    expect(await db.read(`${fRoot}/PriceHistory/1`)).toEqual(GOLDEN_PRICES);

    // Once only: a resweep adds no write for it.
    await runLifecycleSweep(db, LATER_SWEEP);
    expect(db.writeCount('PriceHistory/1')).toBe(1);
  });

  it('records alongside PublishedPicks when squads exist', async () => {
    const db = new FakeDb(world({ gameStatus: 1 }));
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(await db.read(`${fRoot}/PublishedPicks/1`)).not.toBeNull();
    expect(await db.read(`${fRoot}/PriceHistory/1`)).toEqual(GOLDEN_PRICES);
    expect(db.writeCount('PriceHistory/1')).toBe(1);
  });

  it('PriceHistory is not overwritten by a later sweep after a price edit', async () => {
    const db = new FakeDb(world({ gameStatus: 1 }));
    await runLifecycleSweep(db, AFTER_LOCK);

    // Owner edits a price mid-lock (and a Monday reprice would move more).
    db.data.Fantasy.Futsal['15'].Players.Sam.priceTenths = 90;
    await runLifecycleSweep(db, LATER_SWEEP);

    expect(await db.read(`${fRoot}/PriceHistory/1/Sam`)).toBe(85);
    expect(await db.read(`${fRoot}/Players/Sam/priceTenths`)).toBe(90);
    expect(db.writeCount('PriceHistory/1')).toBe(1);
  });

  it('is claimed on its own: PublishedPicks already present still records prices', async () => {
    const seed = world({ gameStatus: 1 });
    seed.Fantasy.Futsal['15'].PublishedPicks = { 1: { alpha: { captainId: 'Ezra' } } };
    const db = new FakeDb(seed);
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(await db.read(`${fRoot}/PriceHistory/1`)).toEqual(GOLDEN_PRICES);
  });

  it('every Players entry is recorded, guests (ineligible) included', async () => {
    const seed = world({ gameStatus: 1 });
    seed.Fantasy.Futsal['15'].Players.Ezra.eligible = false;
    const db = new FakeDb(seed);
    await runLifecycleSweep(db, AFTER_LOCK);
    expect(await db.read(`${fRoot}/PriceHistory/1/Ezra`)).toBe(65);
    expect(Object.keys(await db.read(`${fRoot}/PriceHistory/1`) as Json).sort())
      .toEqual(Object.keys(GOLDEN_PRICES).sort());
  });

  // Audit M2: the first-finalize backstop LockedPositions already had.
  it('a first finalize that outran every sweep records PriceHistory itself (once)', async () => {
    const db = new FakeDb(world()); // games final, no sweep ever ran
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    expect(await db.read(`${fRoot}/History/1`)).not.toBeNull();
    expect(await db.read(`${fRoot}/PriceHistory/1`)).toEqual(GOLDEN_PRICES);
    expect(await db.read(`${fRoot}/LockedPositions/1`)).not.toBeNull();

    // A price edit, then a score-edit rerun and a late sweep: the week's
    // recorded prices never move.
    db.data.Fantasy.Futsal['15'].Players.Sam.priceTenths = 90;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: LATER_SWEEP,
    });
    await runLifecycleSweep(db, LATER_SWEEP);
    expect(await db.read(`${fRoot}/PriceHistory/1/Sam`)).toBe(85);
    expect(db.writeCount('PriceHistory/1')).toBe(1);
  });

  it('a first finalize never overwrites prices the lock sweep recorded', async () => {
    const db = new FakeDb(world({ gameStatus: 1 })); // games live at lock
    await runLifecycleSweep(db, AFTER_LOCK);
    db.data.Fantasy.Futsal['15'].Players.Sam.priceTenths = 90; // owner edit
    for (const g of db.data.Futsal['15'].Date[DATE_KEY]) g.status = 2;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: LATER_SWEEP,
    });
    expect(await db.read(`${fRoot}/History/1`)).not.toBeNull();
    expect(await db.read(`${fRoot}/PriceHistory/1/Sam`)).toBe(85);
    expect(db.writeCount('PriceHistory/1')).toBe(1);
  });

  it('a rerun (History exists) never fabricates PriceHistory for its week', async () => {
    const db = new FakeDb(world());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: AFTER_LOCK,
    });
    // A week settled before PriceHistory existed has History and no prices.
    delete db.data.Fantasy.Futsal['15'].PriceHistory;
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: DATE_KEY, nowUtc: LATER_SWEEP,
    });
    expect(await db.read(`${fRoot}/PriceHistory`)).toBeNull();
  });

  it('nothing is recorded before the lock, or for an empty market', async () => {
    const open = new FakeDb(world());
    await runLifecycleSweep(open, BEFORE_LOCK);
    expect(await open.read(`${fRoot}/PriceHistory`)).toBeNull();

    const seed = world({ gameStatus: 1 });
    delete seed.Fantasy.Futsal['15'].Players;
    const empty = new FakeDb(seed);
    await runLifecycleSweep(empty, AFTER_LOCK);
    expect(await empty.read(`${fRoot}/PriceHistory`)).toBeNull();
  });
});

// FPL selling rule (spec §4), Task 3: Baselines/<uid> = { ForGw,
// RealizedTenths, Prices } — the last locked prices + the running sale
// total, written for EVERY manager at the lock and re-checked by every
// finalize, so the fan app shows the money the next lock will charge.
// Two-gameweek world (test_support.ts world2: GW1 finalized with the golden
// squads, GW2 the week under test) on the cold-transaction FakeDb.
describe('Baselines/<uid> (FPL selling: last locked prices + realized)', () => {
  const t = (db: ColdFakeDb) => db.data.Fantasy.Futsal['15'];
  /** GW2 games still live: the sweep locks, nothing finalizes. */
  const lockOnly = () => new ColdFakeDb(world2({ gw2Status: 1 }));
  const LATER2 = new Date(AFTER_LOCK2.getTime() + 15 * 60_000);
  const finalizeGw = (db: ColdFakeDb, dateKey: string) => maybeFinalizeGame(db, {
    sport: 'Futsal', season: '15', dateKey, nowUtc: AFTER_LOCK2,
  });
  const baselineWrites = (db: ColdFakeDb) =>
    db.writes.filter((w) => w.includes('/Baselines/'));
  // The golden GW1 squads' prices (golden_gameweek.json).
  const GW1_ALPHA = { Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Alex: 95, Will: 60, Wren: 75 };
  const GW1_BOOST = { Sam: 85, Bea: 70, Will: 60, Ben: 85, Wren: 75, Eva: 50, Ezra: 65 };
  const GW1_CHURN = { Bo: 75, Dana: 80, Bea: 70, Ezra: 65, Ben: 85, Eva: 50, Wren: 75 };

  it('(a) the lock writes ForGw = gw + 1 for every snapshotted manager', async () => {
    const db = lockOnly();
    // alpha sells Alex (bought 95, now 105: sells for 95 + 5 = 100, +5) for
    // Ben (85 at market).
    t(db).Players.Alex.priceTenths = 105;
    t(db).Squads.alpha.picks[4] =
      { playerId: 'Ben', position: 'ATT', priceTenths: 85, bench: false };
    t(db).Squads.alpha.viceId = 'Ben';
    await runLifecycleSweep(db, AFTER_LOCK2);

    expect(await db.read(`${F_ROOT}/PublishedPicks/2/alpha/realizedTenths`)).toBe(5);
    expect(await db.read(`${F_ROOT}/Baselines/alpha`)).toEqual({
      ForGw: 3, RealizedTenths: 5,
      Prices: { Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Ben: 85, Will: 60, Wren: 75 },
    });
    expect(await db.read(`${F_ROOT}/Baselines/boost`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_BOOST });
    expect(await db.read(`${F_ROOT}/Baselines/churn`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_CHURN });
  });

  it('(b) a manager with no squad at the lock still gets a fresh baseline', async () => {
    const db = lockOnly();
    t(db).Managers = { alpha: { TeamName: 'Alpha FC' }, dave: { TeamName: 'Dave XI' } };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2/dave`)).toBeNull();
    expect(await db.read(`${F_ROOT}/Baselines/dave`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: {} });
  });

  it('deleting or breaking the squad before a lock never wipes a loss: the '
    + 'running total carries (Prices do not)', async () => {
    const db = lockOnly();
    t(db).Baselines = {
      alpha: { ForGw: 2, RealizedTenths: -15, Prices: GW1_ALPHA },
      churn: { ForGw: 2, RealizedTenths: 7, Prices: GW1_CHURN },
    };
    // Even with no Managers row: an existing Baselines/<uid> is rolled too.
    delete t(db).Squads.alpha;
    t(db).Squads.churn = { picks: 'junk', captainId: 'x', viceId: 'x', realizedTenths: 999 };
    await runLifecycleSweep(db, AFTER_LOCK2);
    // (The lock stashes the node it replaces as Prev — the rewind's undo.)
    expect(await db.read(`${F_ROOT}/Baselines/alpha`)).toEqual({
      ForGw: 3, RealizedTenths: -15, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: GW1_ALPHA },
    });
    expect(await db.read(`${F_ROOT}/Baselines/churn`)).toEqual({
      ForGw: 3, RealizedTenths: 7, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: 7, Prices: GW1_CHURN },
    });
  });

  it('the lock judge takes the realized money from Baselines/<uid> when it is '
    + 'for the judged week — even with NO previous squad', async () => {
    const db = lockOnly();
    // dave: no GW1 squad, -15 carried into GW2. Eli claimed at 61 (> market
    // 55) counts at 61: the squad spends 486 = 500 - 15 + 1.
    const dave = fixtureSquad('alpha');
    dave['picks'][0]['priceTenths'] = 61;
    t(db).Squads.dave = dave;
    t(db).Baselines = { dave: { ForGw: 2, RealizedTenths: -15 } };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2/dave`))
      .toMatchObject({ Invalid: ['overBudget'], realizedTenths: -15 });
    expect(await db.read(`${F_ROOT}/SquadAlerts/dave`))
      .toMatchObject({ Gw: 2, Kind: 'invalid', Issues: ['overBudget'] });
    // The Invalid week passes the running total on, with no trusted prices
    // (the GW2 node it replaced is stashed as Prev).
    expect(await db.read(`${F_ROOT}/Baselines/dave`)).toEqual({
      ForGw: 3, RealizedTenths: -15, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: {} },
    });

    // At 485 (Eli at 60) the same manager is clean, still at -15.
    const clean = lockOnly();
    const dave485 = fixtureSquad('alpha');
    dave485['picks'][0]['priceTenths'] = 60;
    t(clean).Squads.dave = dave485;
    t(clean).Baselines = { dave: { ForGw: 2, RealizedTenths: -15 } };
    await runLifecycleSweep(clean, AFTER_LOCK2);
    const snap = await clean.read(`${F_ROOT}/PublishedPicks/2/dave`) as Json;
    expect(snap['Invalid']).toBeUndefined();
    expect(snap['realizedTenths']).toBe(-15);
  });

  it('a Baselines node for ANOTHER week is not believed: the previous squad decides', async () => {
    const db = lockOnly();
    const dave = fixtureSquad('alpha');
    dave['picks'][0]['priceTenths'] = 61; // 486
    t(db).Squads.dave = dave;
    t(db).Baselines = { dave: { ForGw: 1, RealizedTenths: -15 } }; // stale
    await runLifecycleSweep(db, AFTER_LOCK2);
    const snap = await db.read(`${F_ROOT}/PublishedPicks/2/dave`) as Json;
    expect(snap['Invalid']).toBeUndefined(); // judged at realized 0
    expect(snap['realizedTenths']).toBe(0);
  });

  it('(c) a Free Hit week\'s baseline is the week-before node (its sales were '
    + 'temporary): prices + realized', async () => {
    const db = lockOnly();
    t(db).PublishedPicks[1].boost.realizedTenths = 4;
    t(db).History[1].boost.realizedTenths = 4;
    // boost plays a Free Hit in GW2: Sam (85 -> 95: sells for 90, +5) out
    // for Bo (75). GW1's chip was a Bench Boost, so the Free Hit stands.
    t(db).Players.Sam.priceTenths = 95;
    t(db).Squads.boost.chip = 'freeHit';
    t(db).Squads.boost.picks[0] =
      { playerId: 'Bo', position: 'GK', priceTenths: 75, bench: false };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2/boost`))
      .toMatchObject({ chip: 'freeHit', realizedTenths: 9 });
    expect(await db.read(`${F_ROOT}/Baselines/boost`))
      .toEqual({ ForGw: 3, RealizedTenths: 4, Prices: GW1_BOOST });
  });

  it('(d) re-finalizing gameweek 3 when Baselines/<uid>.ForGw is 10 writes nothing', async () => {
    const db = new ColdFakeDb({ Fantasy: { Futsal: { '15': {
      Managers: { alpha: { TeamName: 'Alpha FC' } },
      PublishedPicks: { 3: { alpha: { ...fixtureSquad('alpha'), realizedTenths: 0 } } },
      Baselines: { alpha: { ForGw: 10, RealizedTenths: -20, Prices: { Sam: 85 } } },
    } } } });
    const before = db.snapshot();
    await publishSaleBaselines(db, F_ROOT, 3);
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);
  });

  it('(d) end to end: a score-edit rerun of an older week leaves the newer '
    + 'baselines alone', async () => {
    const db = lockOnly();
    await runLifecycleSweep(db, AFTER_LOCK2); // Baselines ForGw 3
    const before = JSON.stringify(t(db).Baselines);
    db.writes = [];
    await finalizeGw(db, GW1_DATE); // GW1 re-settles (History/1 rewritten)
    expect(db.writes).toContain(`${F_ROOT}/History/1`);
    expect(baselineWrites(db)).toEqual([]);
    expect(JSON.stringify(t(db).Baselines)).toBe(before);
  });

  it('an older week\'s rerun never creates a STALE node for a manager who has '
    + 'none (absent = "first squad, ready" in the app; ForGw 2 while GW3 is '
    + 'next would block his Save until the GW3 lock)', async () => {
    const db = lockOnly();
    await runLifecycleSweep(db, AFTER_LOCK2); // GwState: GW2 locked, GW3 next
    // erin joins after the GW2 lock: no Baselines node yet.
    t(db).Managers = { erin: { TeamName: 'Erin Athletic' } };
    db.writes = [];
    await finalizeGw(db, GW1_DATE); // a score correction on the GW1 date
    expect(db.writes).toContain(`${F_ROOT}/History/1`);
    expect(baselineWrites(db)).toEqual([]);
    expect(await db.read(`${F_ROOT}/Baselines/erin`)).toBeNull();
    // The next lock (GW3) still gives her a node — the floor never blocks a
    // current week: the GW2 finalize writes ForGw 3 for her.
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/Baselines/erin`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: {} });
  });

  it('a week first-finalized from LIVE Squads is never snapshotted later: no '
    + 'PublishedPicks claim, no Baselines rewrite, a carried -15 stays -15', async () => {
    const db = new ColdFakeDb(world2()); // GW2 final; the sweep was down at the lock
    // dave: no GW1 squad, -15 carried into GW2; a 480 squad (<= 500 - 15).
    t(db).Squads.dave = fixtureSquad('alpha');
    t(db).Baselines = { dave: { ForGw: 2, RealizedTenths: -15 } };
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/History/2/dave/realizedTenths`)).toBe(-15);
    const carried = { ForGw: 3, RealizedTenths: -15, Prices: GW1_ALPHA };
    expect(await db.read(`${F_ROOT}/Baselines/dave`)).toEqual(carried);

    // The sweep comes back inside the locked window (GW2 still current).
    const infos: string[] = [];
    db.writes = [];
    await runLifecycleSweep(db, LATER2,
      { info: (m) => { infos.push(m); }, warn: () => undefined });
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
    expect(baselineWrites(db)).toEqual([]);
    expect(await db.read(`${F_ROOT}/Baselines/dave`)).toEqual(carried);
    expect(infos).toContain('fantasy lock: History already written — snapshot skipped');
  });

  it('never backwards even in a race: the write is a guarded transaction', async () => {
    const db = new ColdFakeDb({ Fantasy: { Futsal: { '15': {
      Managers: { alpha: { TeamName: 'Alpha FC' } },
      PublishedPicks: { 3: { alpha: { ...fixtureSquad('alpha'), realizedTenths: 0 } } },
      Baselines: { alpha: { ForGw: 10, RealizedTenths: -20, Prices: { Sam: 85 } } },
    } } } });
    // The pre-check read sees no node yet (a newer write lands right after).
    const realRead = db.read.bind(db);
    let calls = 0;
    db.read = async (p: string) =>
      p.endsWith('/Baselines/alpha') && calls++ === 0 ? null : realRead(p);
    await publishSaleBaselines(db, F_ROOT, 3);
    expect(t(db).Baselines.alpha)
      .toEqual({ ForGw: 10, RealizedTenths: -20, Prices: { Sam: 85 } });
  });

  it('(e) a rerun with identical data writes nothing (resweep, direct call, '
    + 'RTDB-pruned empty Prices)', async () => {
    const db = lockOnly();
    t(db).Managers = { dave: { TeamName: 'Dave XI' } };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(baselineWrites(db).sort()).toEqual(['alpha', 'boost', 'churn', 'dave']
      .map((u) => `${F_ROOT}/Baselines/${u}`));
    // RTDB never stores an empty map: dave's node comes back without Prices.
    delete t(db).Baselines.dave.Prices;
    db.writes = [];
    await publishSaleBaselines(db, F_ROOT, 2);
    await runLifecycleSweep(db, LATER2);
    expect(baselineWrites(db)).toEqual([]);
  });

  it('(f) a first finalize on the live-Squads fallback writes the baselines '
    + 'after its History write', async () => {
    const db = new ColdFakeDb(world2()); // GW2 final, no sweep ever ran
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/Baselines/alpha`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_ALPHA });
    expect(await db.read(`${F_ROOT}/Baselines/churn`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_CHURN });
    const history = db.writes.indexOf(`${F_ROOT}/History/2`);
    expect(history).toBeGreaterThanOrEqual(0);
    expect(db.writes.findIndex((w) => w.includes('/Baselines/')))
      .toBeGreaterThan(history);
  });

  it('every finalize run heals a baseline the lock failed to write', async () => {
    const db = lockOnly();
    await runLifecycleSweep(db, AFTER_LOCK2);
    delete t(db).Baselines; // the lock-time write was lost
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/Baselines/alpha`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_ALPHA });
    // ...and a later rerun (score edit) heals again.
    delete t(db).Baselines.alpha;
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/Baselines/alpha`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_ALPHA });
  });

  // [M3] (season setup + schedule plan 2026-11-05, Task 3): the lock-time
  // publish keeps the node it overwrites as Baselines/<uid>/Prev, so a
  // rewind of a called-off week (Task 4) restores it EXACTLY — recomputing
  // is lossy (a manager with no squad carries RealizedTenths from the
  // stored node). Finalize-time publishes drop it: a scored week is never
  // rewound.
  /** The lock of GW2 over stored GW2 baselines: alpha sells Alex (bought
   *  95, now 105: +5) for Ben (85); dave sat GW1 out carrying -15 (RTDB
   *  pruned his empty Prices); boost's stored node still carries a stash of
   *  its own (never nested). */
  const lockOverStoredBaselines = async () => {
    const db = lockOnly();
    t(db).Managers = { dave: { TeamName: 'Dave XI' } };
    t(db).Baselines = {
      alpha: { ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA },
      boost: {
        ForGw: 2, RealizedTenths: 0, Prices: GW1_BOOST,
        Prev: { ForGw: 1, RealizedTenths: 0, Prices: {} },
      },
      dave: { ForGw: 2, RealizedTenths: -15 },
    };
    t(db).Players.Alex.priceTenths = 105;
    t(db).Squads.alpha.picks[4] =
      { playerId: 'Ben', position: 'ATT', priceTenths: 85, bench: false };
    t(db).Squads.alpha.viceId = 'Ben';
    await runLifecycleSweep(db, AFTER_LOCK2);
    return db;
  };
  const ALPHA_GW2 = { Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Ben: 85, Will: 60, Wren: 75 };

  it('[M3] the lock stashes the previous baseline as Prev', async () => {
    const db = await lockOverStoredBaselines();
    expect(await db.read(`${F_ROOT}/Baselines/alpha`)).toEqual({
      ForGw: 3, RealizedTenths: 5, Prices: ALPHA_GW2,
      Prev: { ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA },
    });
    // The stored node's {ForGw, RealizedTenths, Prices} WITH its own Prev
    // nested (ruling T4c: a chain, so each rewind pops exactly one level).
    expect(await db.read(`${F_ROOT}/Baselines/boost`)).toEqual({
      ForGw: 3, RealizedTenths: 0, Prices: GW1_BOOST,
      Prev: {
        ForGw: 2, RealizedTenths: 0, Prices: GW1_BOOST,
        Prev: { ForGw: 1, RealizedTenths: 0, Prices: {} },
      },
    });
    expect(await db.read(`${F_ROOT}/Baselines/dave`)).toEqual({
      ForGw: 3, RealizedTenths: -15, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: {} },
    });
  });

  it('[M3] no previous baseline → no Prev', async () => {
    const db = lockOnly(); // no Baselines node at all before the GW2 lock
    t(db).Managers = { dave: { TeamName: 'Dave XI' } };
    await runLifecycleSweep(db, AFTER_LOCK2);
    for (const uid of ['alpha', 'boost', 'churn', 'dave']) {
      const node = await db.read(`${F_ROOT}/Baselines/${uid}`) as Json;
      expect(node['ForGw'], uid).toBe(3);
      expect(Object.keys(node), uid).not.toContain('Prev');
    }
  });

  it('[M3] finalize drops Prev', async () => {
    const db = await lockOverStoredBaselines();
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/Baselines/alpha`))
      .toEqual({ ForGw: 3, RealizedTenths: 5, Prices: ALPHA_GW2 });
    expect(await db.read(`${F_ROOT}/Baselines/boost`))
      .toEqual({ ForGw: 3, RealizedTenths: 0, Prices: GW1_BOOST });
    expect(await db.read(`${F_ROOT}/Baselines/dave`))
      .toEqual({ ForGw: 3, RealizedTenths: -15, Prices: {} });
    // ...and a rerun (score edit) writes nothing more.
    db.writes = [];
    await finalizeGw(db, GW2_DATE);
    expect(baselineWrites(db)).toEqual([]);
  });

  it('[M3] a finalize that wrote NO History (nobody to score) leaves Prev '
    + 'intact — the week is not scored, so it can still be rewound — and '
    + 'stashes like the lock', async () => {
    const db = new ColdFakeDb(world2({ gw2Status: 2 })); // GW2 final
    delete t(db).Squads; // no snapshot, no History, no Squads: nobody to score
    t(db).Managers = {
      dave: { TeamName: 'Dave XI' }, erin: { TeamName: 'Erin Athletic' },
    };
    // dave: the GW2 lock already stashed his GW2 node; erin: the lock wrote
    // nothing for her (still FOR GW2, +4 realized).
    const daveStashed = {
      ForGw: 3, RealizedTenths: -15, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: GW1_ALPHA },
    };
    t(db).Baselines = {
      dave: clone(daveStashed),
      erin: { ForGw: 2, RealizedTenths: 4, Prices: { Sam: 85 } },
    };
    await finalizeGw(db, GW2_DATE);
    expect(await db.read(`${F_ROOT}/History/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/Baselines/dave`)).toEqual(daveStashed);
    expect(await db.read(`${F_ROOT}/Baselines/erin`)).toEqual({
      ForGw: 3, RealizedTenths: 4, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: 4, Prices: { Sam: 85 } },
    });
  });

  it('[M3] a concurrent second lock-time publish writes nothing (the stash '
    + 'survives)', async () => {
    const db = await lockOverStoredBaselines();
    const after = JSON.stringify(t(db).Baselines);
    // A second lock-time publish that read alpha's node BEFORE the first
    // one landed: its guarded transaction then sees the fresh node.
    const stale = { ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA };
    const realRead = db.read.bind(db);
    let calls = 0;
    db.read = async (p: string) =>
      p === `${F_ROOT}/Baselines/alpha` && calls++ === 0 ? clone(stale) : realRead(p);
    db.writes = [];
    await publishSaleBaselines(db, F_ROOT, 2, undefined, {}, { stashPrev: true });
    expect(calls).toBeGreaterThan(1); // it did reach the transaction
    expect(baselineWrites(db)).toEqual([]);
    expect(JSON.stringify(t(db).Baselines)).toBe(after);
    expect(t(db).Baselines.alpha.Prev)
      .toEqual({ ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA });
  });
});

// ── LockedWeeks: a gameweek freezes when it locks (season setup + schedule
// plan 2026-11-05, Task 3) ─────────────────────────────────────────────────
//
// LockedWeeks/<n> = {Date, LockAtUtc, Scored?}: the lock's FIRST write, so
// later schedule edits can never renumber or re-time a locked week; finalize
// marks it Scored. [M2] Every lock write re-checks it first, and each
// snapshot write re-checks it again once it landed (deleting itself when the
// week is no longer frozen), so a sweep that started before a rewind (Task 4
// MARKS LockedWeeks/<n> Rewinding first and deletes it last) leaves no stale
// snapshot or lock write behind.

describe('LockedWeeks: a gameweek freezes when it locks', () => {
  // 2026-10-04 and 10-11 are Sundays (PDT): lockHour 15 => lock 22:00Z.
  const D1 = '10042026';
  const D2 = '10112026';
  const LOCK1_MS = Date.UTC(2026, 9, 4, 22);
  const LOCK2_OCT_MS = Date.UTC(2026, 9, 11, 22);
  const AFTER1 = new Date(Date.UTC(2026, 9, 4, 23));
  const LATER1 = new Date(Date.UTC(2026, 9, 4, 23, 15));
  const t = (db: ColdFakeDb) => db.data.Fantasy.Futsal['15'];
  /** The production world moved to October: D1 holds the golden games at
   *  [status] (1 = live: the sweep locks, nothing finalizes), D2 the same
   *  games not started. */
  const octWorld = (status = 1): ColdFakeDb => {
    const w = world({ gameStatus: status });
    const games = w.Futsal['15'].Date[DATE_KEY] as Json[];
    const later = clone(games);
    for (const g of later) g['status'] = 0;
    w.Futsal['15'].Date = { [D1]: games, [D2]: later };
    return new ColdFakeDb(w);
  };
  const logSpy = () => {
    const infos: string[] = [];
    const warns: string[] = [];
    const log: FantasyLogger = {
      info: (m) => { infos.push(m); },
      warn: (m) => { warns.push(m); },
    };
    return { infos, warns, log };
  };
  const lockedWeekWrites = (db: ColdFakeDb) =>
    db.writes.filter((w) => w.includes('/LockedWeeks/'));
  const FROZEN = 'fantasy lock: week frozen on another date — lock step skipped';
  const REWINDING = 'fantasy lock: week being rewound — lock step skipped';
  const NO_LONGER = 'fantasy lock: week no longer frozen — snapshot skipped';
  const REMOVED = 'fantasy lock: week no longer frozen — snapshot removed';
  const STOPPED = 'fantasy lock: week no longer frozen — lock step stopped';
  /** Task 4's rewind, step one: LockedWeeks/<n> marked Rewinding (written
   *  straight into the data, as another process would). */
  const markRewinding = (db: ColdFakeDb, n: number) => {
    const ledger = t(db).LockedWeeks;
    ledger[n] = { ...ledger[n], Rewinding: true };
  };
  const LATER_NODES = ['TransferCosts', 'TransferState', 'SquadAlerts', 'Baselines'];

  it('the lock writes LockedWeeks/1 before PublishedPicks (its first lock write)', async () => {
    const db = octWorld();
    await runLifecycleSweep(db, AFTER1);
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`))
      .toEqual({ Date: D1, LockAtUtc: LOCK1_MS });
    const at = (p: string) => db.writes.indexOf(`${F_ROOT}/${p}`);
    // The first write under the season of this sweep.
    expect(db.writes.find((w) => w.startsWith(`${F_ROOT}/`)))
      .toBe(`${F_ROOT}/LockedWeeks/1`);
    for (const p of ['LockedPositions/1', 'PriceHistory/1', 'PublishedPicks/1']) {
      expect(at(p), p).toBeGreaterThan(at('LockedWeeks/1'));
    }
  });

  it('a second sweep never rewrites LockedWeeks', async () => {
    const db = octWorld();
    await runLifecycleSweep(db, AFTER1);
    // The owner changes the lock hour afterwards: the frozen week keeps the
    // instant it actually locked at (18:00 would put it back in the future).
    t(db).Config.lockHour = 18;
    await runLifecycleSweep(db, LATER1);
    expect(lockedWeekWrites(db)).toEqual([`${F_ROOT}/LockedWeeks/1`]);
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`))
      .toEqual({ Date: D1, LockAtUtc: LOCK1_MS });
    expect((await db.read(`${F_ROOT}/GwState`) as Json)['status']).toBe('locked');
  });

  it('a lost claim with a different Date aborts the lock step', async () => {
    const db = octWorld();
    const realClaim = db.writeIfAbsent.bind(db);
    const other = { Date: D2, LockAtUtc: LOCK2_OCT_MS };
    db.writeIfAbsent = async (p: string, v: unknown) => {
      // Another sweep, on another schedule, froze GW1 a moment earlier.
      if (p === `${F_ROOT}/LockedWeeks/1`) await db.write(p, other);
      return realClaim(p, v);
    };
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER1, spy.log);
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`)).toEqual(other);
    for (const p of ['LockedPositions', 'PriceHistory', 'PublishedPicks',
      'TransferCosts', 'TransferState', 'Baselines']) {
      expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
    }
    expect(spy.warns).toContain(FROZEN);
  });

  it('a lost claim on the SAME Date (an earlier sweep froze it) carries on', async () => {
    const db = octWorld();
    const realClaim = db.writeIfAbsent.bind(db);
    db.writeIfAbsent = async (p: string, v: unknown) => {
      if (p === `${F_ROOT}/LockedWeeks/1`) await db.write(p, clone(v));
      return realClaim(p, v);
    };
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER1, spy.log);
    expect(await db.read(`${F_ROOT}/PublishedPicks/1`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/LockedPositions/1`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/PriceHistory/1`)).not.toBeNull();
    expect(spy.warns).not.toContain(FROZEN);
  });

  it.each([
    ['there by the claim\'s read', false],
    ['won the race', true],
  ])('a ledger entry marked Rewinding is no claim (%s): the lock step writes '
    + 'nothing', async (_label, race) => {
    const db = octWorld();
    const marked = { Date: D1, LockAtUtc: LOCK1_MS, Rewinding: true };
    if (race) {
      const realClaim = db.writeIfAbsent.bind(db);
      db.writeIfAbsent = async (p: string, v: unknown) => {
        if (p === `${F_ROOT}/LockedWeeks/1`) await db.write(p, clone(marked));
        return realClaim(p, v);
      };
    } else {
      // Marked after this sweep's rewind check and week list (Task 4: a
      // mark already there when the sweep starts is a rewind to RESUME —
      // schedule_rewind.test.ts), so the claim's first read finds it.
      const realRead = db.read.bind(db);
      db.read = async (p: string) => {
        if (p === `${F_ROOT}/LockedWeeks/1` && t(db).LockedWeeks === undefined) {
          t(db).LockedWeeks = { 1: clone(marked) };
        }
        return realRead(p);
      };
    }
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER1, spy.log);
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`)).toEqual(marked);
    for (const p of ['LockedPositions', 'PriceHistory', 'PublishedPicks', ...LATER_NODES]) {
      expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
    }
    expect(spy.warns).toContain(REWINDING);
  });

  it.each([
    ['marked Rewinding (the rewind\'s first step)', 'mark'],
    ['deleted (the rewind\'s last step)', 'delete'],
  ])('[M2] a stale sweep whose LockedWeeks/1 is %s right after its claim '
    + 'writes no snapshot and stops', async (_label, how) => {
    const db = octWorld();
    const realClaim = db.writeIfAbsent.bind(db);
    db.writeIfAbsent = async (p: string, v: unknown) => {
      const won = await realClaim(p, v);
      if (won && p === `${F_ROOT}/LockedWeeks/1`) {
        if (how === 'mark') markRewinding(db, 1);
        else await db.write(p, null);
      }
      return won;
    };
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER1, spy.log);
    for (const p of ['LockedPositions', 'PriceHistory', 'PublishedPicks', ...LATER_NODES]) {
      expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
    }
    // The first refused re-check stops the whole lock step.
    expect(spy.warns.filter((m) => m === NO_LONGER)).toHaveLength(1);
  });

  it.each(['LockedPositions', 'PriceHistory', 'PublishedPicks'])(
    '[M2] a rewind mark landing between the pre-check and the %s write: the '
    + 'stale snapshot is deleted again and the lock step stops', async (node) => {
      const db = octWorld();
      const realClaim = db.writeIfAbsent.bind(db);
      db.writeIfAbsent = async (p: string, v: unknown) => {
        // Our pre-check already passed; the rewind marks the week now.
        if (p === `${F_ROOT}/${node}/1`) markRewinding(db, 1);
        return realClaim(p, v);
      };
      const spy = logSpy();
      await runLifecycleSweep(db, AFTER1, spy.log);
      const path = `${F_ROOT}/${node}/1`;
      expect(db.writes.filter((w) => w === path)).toHaveLength(2); // landed, then went
      const order = ['LockedPositions', 'PriceHistory', 'PublishedPicks'];
      for (const [k, n] of order.entries()) {
        const v = await db.read(`${F_ROOT}/${n}/1`);
        // Snapshots taken before the mark stand (the rewind deletes them).
        if (k < order.indexOf(node)) expect(v, n).not.toBeNull();
        else expect(v, n).toBeNull();
      }
      for (const p of LATER_NODES) expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
      expect(spy.warns.filter((m) => m === REMOVED)).toHaveLength(1);
    });

  it('[M2] the re-check sits right before the PublishedPicks claim: a rewind '
    + 'mark while the picks are judged leaves no picks and nothing after them', async () => {
    const db = octWorld();
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      // TransferState is read while the lock accounting judges the squads.
      if (p === `${F_ROOT}/TransferState`) markRewinding(db, 1);
      return realRead(p);
    };
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER1, spy.log);
    // Positions + prices landed before the mark (Task 4 deletes them).
    expect(await db.read(`${F_ROOT}/LockedPositions/1`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/PriceHistory/1`)).not.toBeNull();
    expect(db.writes).not.toContain(`${F_ROOT}/PublishedPicks/1`);
    for (const p of ['PublishedPicks', ...LATER_NODES]) {
      expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
    }
    expect(spy.warns).toContain(NO_LONGER);
  });

  it('[M2] a rewind mark landing after the PublishedPicks claim stops every '
    + 'later lock write: no TransferCosts, TransferState, SquadAlerts or '
    + 'Baselines change', async () => {
    const db = new ColdFakeDb(world2({ gw2Status: 1 })); // the GW2 lock
    const s = t(db);
    // Things the lock would change: alpha's stored baseline (re-published
    // FOR GW3) and his over-budget preview (cleared by a clean lock); every
    // squad's TransferState (frozen at the lock).
    s.Baselines = { alpha: { ForGw: 2, RealizedTenths: 0, Prices: { Sam: 85 } } };
    s.SquadAlerts = {
      alpha: { Gw: 2, Kind: 'preview', Issues: ['overBudget'], OverTenths: 5, CreatedAt: 1 },
    };
    const before = LATER_NODES.map((n) => JSON.stringify(s[n] ?? null));
    const realRead = db.read.bind(db);
    let marked = false;
    db.read = async (p: string) => {
      const v = await realRead(p);
      // The claim's own after-write re-check passes; the mark lands right
      // after it.
      if (!marked && p === `${F_ROOT}/LockedWeeks/2` && s.PublishedPicks?.[2] != null) {
        marked = true;
        markRewinding(db, 2);
      }
      return v;
    };
    const spy = logSpy();
    await runLifecycleSweep(db, AFTER_LOCK2, spy.log);
    expect(marked).toBe(true);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull(); // the rewind's to delete
    expect(db.writes.filter((w) =>
      LATER_NODES.some((n) => w.startsWith(`${F_ROOT}/${n}`)))).toEqual([]);
    expect(LATER_NODES.map((n) => JSON.stringify(s[n] ?? null))).toEqual(before);
    expect(spy.warns).toContain(STOPPED);
  });

  it('finalize never marks a week being rewound Scored (warned)', async () => {
    const db = octWorld(); // games live: the sweep locks GW1
    await runLifecycleSweep(db, AFTER1);
    for (const g of db.data.Futsal['15'].Date[D1]) g.status = 2;
    // Task 4: finalize stands down for a week already marked (at entry and
    // right before its first official write), so the mark lands while
    // History is being written.
    const realWrite = db.write.bind(db);
    db.write = async (p: string, v: unknown) => {
      await realWrite(p, v);
      if (p === `${F_ROOT}/History/1`) markRewinding(db, 1);
    };
    const spy = logSpy();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: D1, nowUtc: LATER1, log: spy.log,
    });
    expect(await db.read(`${F_ROOT}/History/1`)).not.toBeNull();
    // A direct mark: the real rewind refuses a week carrying a fresh
    // Finalizing stamp (final review I1 — schedule_rewind.test.ts).
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`)).toEqual({
      Date: D1, LockAtUtc: LOCK1_MS, Finalizing: LATER1.getTime(), Rewinding: true,
    });
    expect(spy.warns).toContain(
      'fantasy finalize: week being rewound — not marked Scored');
  });

  it('finalize marks Scored (after History lands); a rerun writes nothing there', async () => {
    const db = octWorld(2); // final: the sweep locks, then its backstop finalizes
    await runLifecycleSweep(db, AFTER1);
    expect(await db.read(`${F_ROOT}/History/1`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`))
      .toEqual({ Date: D1, LockAtUtc: LOCK1_MS, Scored: true });
    expect(db.writes.lastIndexOf(`${F_ROOT}/LockedWeeks/1`))
      .toBeGreaterThan(db.writes.indexOf(`${F_ROOT}/History/1`));

    db.writes = [];
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: D1, nowUtc: LATER1,
    });
    expect(db.writes).toContain(`${F_ROOT}/History/1`);
    expect(lockedWeekWrites(db)).toEqual([]);
  });

  it('pre-feature season gets the full node at finalize', async () => {
    // world2: GW1 was locked + scored before LockedWeeks existed.
    const db = new ColdFakeDb(world2());
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW1_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(await db.read(`${F_ROOT}/LockedWeeks/1`)).toEqual({
      Date: GW1_DATE, LockAtUtc: Date.UTC(2026, 5, 21, 22), Scored: true,
    });
  });

  it('a first finalize that outran every sweep claims the week the same way', async () => {
    const db = new ColdFakeDb(world2({ gw2Status: 2 }));
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
    });
    expect(await db.read(`${F_ROOT}/LockedWeeks/2`))
      .toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS, Scored: true });
    const at = (p: string) => db.writes.indexOf(`${F_ROOT}/${p}`);
    expect(at('LockedWeeks/2')).toBeGreaterThanOrEqual(0);
    expect(at('LockedPositions/2')).toBeGreaterThan(at('LockedWeeks/2'));
    expect(at('PriceHistory/2')).toBeGreaterThan(at('LockedWeeks/2'));
  });

  it('a first finalize whose claim finds ANOTHER date takes no snapshot and '
    + 'stands down: no History for a date the ledger does not freeze (final '
    + 'review I4)', async () => {
    const db = new ColdFakeDb(world2({ gw2Status: 2 }));
    const other = { Date: '07052026', LockAtUtc: Date.UTC(2026, 6, 5, 22) };
    const realClaim = db.writeIfAbsent.bind(db);
    db.writeIfAbsent = async (p: string, v: unknown) => {
      if (p === `${F_ROOT}/LockedWeeks/2`) await db.write(p, other);
      return realClaim(p, v);
    };
    const spy = logSpy();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
      log: spy.log,
    });
    expect(await db.read(`${F_ROOT}/History/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/TransferCosts/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/LockedPositions/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/PriceHistory/2`)).toBeNull();
    expect(await db.read(`${F_ROOT}/LockedWeeks/2`)).toEqual(other);
    expect(spy.warns).toContain(FROZEN);
    expect(spy.warns).toContain(
      'fantasy finalize: week frozen on another date — standing down');
  });

  it('the week list stays frozen when the locked day disappears', async () => {
    const db = octWorld();
    await runLifecycleSweep(db, AFTER1); // GW1 locks
    delete db.data.Futsal['15'].Date[D1]; // the game day is removed
    const configNode = t(db).Config;
    const { gws } = await loadSeasonGameweeks(
      db, 'Futsal', '15', configFromMap(configNode), configNode);
    expect(gws.map((g) => [g.number, g.date, g.lockUtc.getTime(), g.frozen]))
      .toEqual([
        [1, D1, LOCK1_MS, true],
        [2, D2, LOCK2_OCT_MS, false],
      ]);
  });
});

describe('over-budget preview while the window is open (sweep step 3c)', () => {
  const t = (db: ColdFakeDb) => db.data.Fantasy.Futsal['15'];
  // Saturday 15:00 league time: GW2 open, before the Sunday-noon reminder.
  const SATURDAY = new Date(LOCK2_MS - 24 * 3600 * 1000);
  const SATURDAY_LATER = new Date(SATURDAY.getTime() + 15 * 60_000);
  const TITLE = 'Your fantasy team is over budget';
  const previews = (p: FakePusher) =>
    p.sends.flat().filter((m) => m.title === TITLE);
  const alertWrites = (db: ColdFakeDb) => db.writes.filter((w) =>
    w.includes('/SquadAlerts/') || w.includes('/PreviewPushed/'));
  const capture = () => {
    const warns: Array<{ m: string; c?: Json }> = [];
    const log: FantasyLogger = {
      info: () => undefined, warn: (m, c) => { warns.push({ m, c }); },
    };
    return { log, warns };
  };
  /** alpha (480) sells Eva (bought 50, still 50: no profit) for Bea (70 at
   *  market, a NEW pick): exactly 500, the whole budget. */
  const spendItAll = (db: ColdFakeDb) => {
    t(db).Squads.alpha.picks[2] =
      { playerId: 'Bea', position: 'DEF', priceTenths: 70, bench: false };
  };
  /** ...and then Bea rises 5 (a riser reprice / owner edit; no
   *  PriceHistory/1, so the buy floor is her price now): 505 = over by 5. */
  const overByFive = (db: ColdFakeDb) => {
    spendItAll(db);
    t(db).Players.Bea.priceTenths = 75;
  };
  const PREVIEW = (at: Date, over = 5) => ({
    Gw: 2, Kind: 'preview', Issues: ['overBudget'], OverTenths: over,
    CreatedAt: at.getTime(),
  });

  it('a riser makes a saved squad over by 5: the preview alert + exactly one push', async () => {
    const db = new ColdFakeDb(world2());
    overByFive(db);
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });

    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    expect(previews(pusher)).toEqual([{
      uid: 'alpha',
      title: TITLE,
      body: "This week's price changes put your team $0.5M over. Fix it " +
        "before Sun, Jun 28 · 3:00 PM or this week won't count.",
      data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '2' },
    }]);
    expect(await db.read(`${F_ROOT}/PreviewPushed/2/alpha`))
      .toEqual({ At: SATURDAY.getTime() });
    // The squads within budget: nothing.
    for (const uid of ['boost', 'churn']) {
      expect(await db.read(`${F_ROOT}/SquadAlerts/${uid}`), uid).toBeNull();
      expect(await db.read(`${F_ROOT}/PreviewPushed/2/${uid}`), uid).toBeNull();
    }
    // A preview is a warning, never a verdict: no snapshot, no Invalid.
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
  });

  it('a second sweep: no new push, no rewrite; a further rise rewrites the '
    + 'amount, still no second push', async () => {
    const db = new ColdFakeDb(world2());
    overByFive(db);
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
    db.writes = [];
    await runLifecycleSweep(db, SATURDAY_LATER, undefined, { pusher });
    expect(alertWrites(db)).toEqual([]);
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    expect(previews(pusher)).toHaveLength(1);

    t(db).Players.Bea.priceTenths = 80; // over by 10 now
    const later = new Date(SATURDAY_LATER.getTime() + 15 * 60_000);
    await runLifecycleSweep(db, later, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(later, 10));
    expect(previews(pusher)).toHaveLength(1); // one push per gameweek
  });

  it('the fan saves a clean squad: the save trigger clears it (a save still '
    + 'over budget keeps it)', async () => {
    const db = new ColdFakeDb(world2());
    overByFive(db);
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher: new FakePusher() });
    // Still over (a formation-legal save that did not fix the money).
    t(db).Squads.alpha.captainId = 'Alex';
    t(db).Squads.alpha.viceId = 'Ezra';
    await recordSquadSave(db,
      { sport: 'Futsal', season: '15', uid: 'alpha', nowUtc: SATURDAY_LATER });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    // Fixed: back to the golden squad (480).
    t(db).Squads.alpha = fixtureSquad('alpha');
    await recordSquadSave(db,
      { sport: 'Futsal', season: '15', uid: 'alpha', nowUtc: SATURDAY_LATER });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toBeNull();
  });

  it('a squad back under budget by itself: the next sweep clears it, no push', async () => {
    const db = new ColdFakeDb(world2());
    overByFive(db);
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
    t(db).Players.Bea.priceTenths = 70; // the edit is undone
    await runLifecycleSweep(db, SATURDAY_LATER, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toBeNull();
    expect(previews(pusher)).toHaveLength(1);
  });

  it("a locked week runs nothing: the owner's 'locked' override, and the "
    + 'lock itself', async () => {
    const frozen = new ColdFakeDb(world2());
    overByFive(frozen);
    t(frozen).Config.lockOverride = 'locked';
    const pusher = new FakePusher();
    await runLifecycleSweep(frozen, SATURDAY, undefined, { pusher });
    expect(await frozen.read(`${F_ROOT}/SquadAlerts`)).toBeNull();
    expect(await frozen.read(`${F_ROOT}/PreviewPushed`)).toBeNull();
    expect(previews(pusher)).toEqual([]);

    // After the lock instant (GW2 games still live): the lock judged the
    // squad clean at 500; a price move AFTER the lock is not previewed —
    // the week is decided.
    const locked = new ColdFakeDb(world2({ gw2Status: 1 }));
    spendItAll(locked);
    await runLifecycleSweep(locked, new Date(LOCK2_MS + 5 * 60_000),
      undefined, { pusher });
    expect('Invalid' in (await locked.read(`${F_ROOT}/PublishedPicks/2/alpha`) as Json))
      .toBe(false);
    t(locked).Players.Bea.priceTenths = 75;
    await runLifecycleSweep(locked, new Date(LOCK2_MS + 20 * 60_000),
      undefined, { pusher });
    expect(await locked.read(`${F_ROOT}/SquadAlerts`)).toBeNull();
    expect(await locked.read(`${F_ROOT}/PreviewPushed`)).toBeNull();
    expect(previews(pusher)).toEqual([]);
  });

  it('the lock judging the same squad Invalid replaces the preview with the '
    + 'Invalid alert; a clean lock clears it', async () => {
    const db = new ColdFakeDb(world2({ gw2Status: 1 }));
    overByFive(db);
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual({
      Gw: 2, Kind: 'invalid', Issues: ['overBudget'], CreatedAt: AFTER_LOCK2.getTime(),
    });
    expect(previews(pusher)).toHaveLength(1);

    // The price fell back after the last sweep: the lock finds it clean.
    const clean = new ColdFakeDb(world2({ gw2Status: 1 }));
    overByFive(clean);
    await runLifecycleSweep(clean, SATURDAY);
    t(clean).Players.Bea.priceTenths = 70;
    await runLifecycleSweep(clean, AFTER_LOCK2);
    expect('Invalid' in (await clean.read(`${F_ROOT}/PublishedPicks/2/alpha`) as Json))
      .toBe(false);
    expect(await clean.read(`${F_ROOT}/SquadAlerts/alpha`)).toBeNull();
  });

  it('a sold player who FELL lowers the credit: the sell-side case is '
    + 'previewed too', async () => {
    const db = new ColdFakeDb(world2());
    // alpha sold Alex (bought 95) for Ben (85): 470 spent. Then Alex falls
    // to 60 before the lock: the sale banks 60, -35 → budget 465, over by 5.
    t(db).Squads.alpha.picks[4] =
      { playerId: 'Ben', position: 'ATT', priceTenths: 85, bench: false };
    t(db).Squads.alpha.viceId = 'Ben';
    t(db).Players.Alex.priceTenths = 60;
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    expect(previews(pusher).map((m) => m.uid)).toEqual(['alpha']);
  });

  it('an Invalid alert and a position-change alert are never touched (no '
    + 'push either)', async () => {
    const invalid = { Gw: 1, Kind: 'invalid', Issues: ['overBudget'], CreatedAt: 5 };
    const position = {
      Gw: 2, Changes: [{ player: 'Wren', from: 'ATT', to: 'DEF' }], CreatedAt: 6,
    };
    for (const standing of [invalid, position]) {
      const db = new ColdFakeDb(world2());
      overByFive(db);
      t(db).SquadAlerts = { alpha: clone(standing) };
      const pusher = new FakePusher();
      await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
      expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(standing);
      expect(await db.read(`${F_ROOT}/PreviewPushed`)).toBeNull();
      expect(previews(pusher)).toEqual([]);
    }
  });

  it('a forged squad (issues other than overBudget) gets no preview, no push', async () => {
    const db = new ColdFakeDb(world2());
    // Wren (75) out, an unknown "Ghost" at 75 in: 480, unknownPlayer only.
    t(db).Squads.alpha.picks[6] =
      { playerId: 'Ghost', position: 'ATT', priceTenths: 75, bench: true };
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts`)).toBeNull();
    expect(previews(pusher)).toEqual([]);
  });

  it('no pusher: the alert lands, nothing is claimed; a later equipped sweep '
    + 'pushes once', async () => {
    const db = new ColdFakeDb(world2());
    overByFive(db);
    await runLifecycleSweep(db, SATURDAY);
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toEqual(PREVIEW(SATURDAY));
    expect(await db.read(`${F_ROOT}/PreviewPushed`)).toBeNull();
    const pusher = new FakePusher();
    await runLifecycleSweep(db, SATURDAY_LATER, undefined, { pusher });
    await runLifecycleSweep(db, SATURDAY_LATER, undefined, { pusher });
    expect(previews(pusher).map((m) => m.uid)).toEqual(['alpha']);
  });

  it("one manager's failure never stops the others, or the sweep", async () => {
    class FlakyDb extends ColdFakeDb {
      failWrite: string | null = null;
      failRead: string | null = null;
      async write(path: string, value: unknown): Promise<void> {
        if (path === this.failWrite) throw new Error('boom');
        return super.write(path, value);
      }
      async read(path: string): Promise<unknown> {
        if (path === this.failRead) throw new Error('boom');
        return super.read(path);
      }
    }
    // alpha AND churn over budget (churn sells Eva 50 for Will 60: over 10).
    const db = new FlakyDb(world2());
    overByFive(db);
    t(db).Squads.churn.picks[5] =
      { playerId: 'Will', position: 'DEF', priceTenths: 60, bench: true };
    db.failWrite = `${F_ROOT}/SquadAlerts/alpha`;
    const pusher = new FakePusher();
    const { log, warns } = capture();
    await runLifecycleSweep(db, SATURDAY, log, { pusher });
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toBeNull();
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`))
      .toEqual(PREVIEW(SATURDAY, 10));
    expect(previews(pusher).map((m) => m.uid)).toEqual(['churn']);
    expect(warns.some((w) => w.c?.['uid'] === 'alpha')).toBe(true);

    // A whole-step failure is logged; the sweep goes on (the Sunday-noon
    // reminder still fires).
    const broken = new FlakyDb(world2());
    overByFive(broken);
    broken.failRead = `${F_ROOT}/PreviewPushed/2`;
    const later = new FakePusher();
    const step = capture();
    await runLifecycleSweep(broken, new Date(LOCK2_MS - 3 * 3600 * 1000),
      step.log, { pusher: later });
    expect(later.sends.flat().some((m) => m.title === 'Fantasy deadline')).toBe(true);
    expect(step.warns.some((w) => w.m.includes('preview'))).toBe(true);
  });
});

describe('scored-week checks are existence queries (scale fixes D4)', () => {
  const GW_DATES = ['06212026', '06282026', '07052026', '07122026', '07192026'];
  const week = (n: number) => `${fRoot}/History/${n}`;
  const picks = (n: number) => `${fRoot}/PublishedPicks/${n}`;
  const WHOLE_WEEK_READ = /\/(History|PublishedPicks)\/\d+$/;

  /** world2 stretched to [last] gameweeks on consecutive Sundays (all games
   *  final, lock 22:00Z each); weeks 1..[scored] carry History and
   *  PublishedPicks (copies of the golden GW1). */
  function weeks(last: number, scored: number): { db: ColdFakeDb; w: Record<string, any> } {
    const w = world2();
    const s = w.Fantasy.Futsal['15'];
    for (let n = 2; n <= scored; n++) {
      s.History[n] = clone(s.History[1]);
      s.PublishedPicks[n] = clone(s.PublishedPicks[1]);
    }
    for (let n = 3; n <= last; n++) {
      w.Futsal['15'].Date[GW_DATES[n - 1]] = clone(w.Futsal['15'].Date[GW1_DATE]);
    }
    return { db: new ColdFakeDb(w), w };
  }

  it('five finalized weeks swept three times never download a week, and finalize nothing again', async () => {
    const { db } = weeks(5, 5);
    const after5 = new Date(Date.UTC(2026, 6, 19, 23)); // Sun Jul 19, an hour past lock 5
    for (let i = 0; i < 3; i++) await runLifecycleSweep(db, after5);

    expect(db.reads.filter((r) => r.startsWith('read:') && WHOLE_WEEK_READ.test(r)))
      .toEqual([]);
    // The backstop asks once per lock-passed week per sweep (plus the GwState
    // upsert for the latest week): never fewer than once per sweep.
    for (let n = 1; n <= 5; n++) {
      expect(db.reads.filter((r) => r === `exists:${week(n)}`).length, `History/${n}`)
        .toBeGreaterThanOrEqual(3);
    }
    expect(db.reads.filter((r) => r === `exists:${picks(5)}`).length)
      .toBeGreaterThanOrEqual(3);
    expect(db.writes.filter((p) => p.startsWith(`${fRoot}/History/`))).toEqual([]);
    expect(db.writes.filter((p) => p.startsWith(`${fRoot}/Leaderboards`))).toEqual([]);
  });

  it('a week finalized moments ago in the same sweep is not finalized twice, and an unlocked later week is untouched', async () => {
    // Weeks 1-2 finalized; week 3 (Jul 5) lock-passed, every game final, no
    // History; week 4 (Jul 12) not locked yet.
    const { db } = weeks(4, 2);
    for (const g of db.data.Futsal['15'].Date[GW_DATES[3]] as Json[]) g['status'] = 0;
    const afterLock3 = new Date(Date.UTC(2026, 6, 5, 23));

    await runLifecycleSweep(db, afterLock3);
    expect(db.writes.filter((p) => p === week(3))).toHaveLength(1);
    expect((await db.read(week(3))) as Json).toBeTruthy();
    const week4 = new RegExp(
      `^${fRoot}/(History|PublishedPicks|LockedWeeks|LockedPositions|PriceHistory|` +
      `TransferCosts|PlayerWeeks|PlayerWeekStats|Leaderboards/Gameweek)/4(/|$)`);
    expect(db.writes.filter((p) => week4.test(p))).toEqual([]);

    // The reads that decided it: every guard asked "exists", none downloaded
    // the week. First look at each node is the existence query.
    expect(db.reads.find((r) => r.endsWith('/PublishedPicks/3')))
      .toBe(`exists:${picks(3)}`);
    expect(db.reads.find((r) => r.endsWith('/History/3'))).toBe(`exists:${week(3)}`);
    // History/3: the lock snapshot's guard, the backstop loop, the first-run
    // guard and the GwState upsert; PublishedPicks/3: the snapshot's guard
    // and the first-run guard.
    expect(db.reads.filter((r) => r === `exists:${week(3)}`)).toHaveLength(4);
    expect(db.reads.filter((r) => r === `exists:${picks(3)}`)).toHaveLength(2);

    await runLifecycleSweep(db, afterLock3);
    expect(db.writes.filter((p) => p === week(3))).toHaveLength(1); // not again
  });
});
