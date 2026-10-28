// P4 Phases B–D orchestration over an in-memory FantasyDb — lifecycle
// transitions, lock-snapshot once-only, the finalize pipeline end to end on
// REAL production node shapes (absent-only attendance, Line Ups rosters,
// list Date nodes), rerun idempotence, and Monday repricing. Every expected
// number is hand-computed (fixture _notes + the derivations in comments
// below), never copied from pipeline output.

import { describe, expect, it } from 'vitest';
import { clone, Json, loadGoldenFixture } from './golden_fixture';
import {
  maybeFinalizeGame, runLifecycleSweep, runMondayReprice,
} from './orchestration';
import { FantasyDb } from './orchestration_db';

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
    expect(await db.read(`${fRoot}/PlayerWeeks/1`)).toEqual(WEEK_POINTS);
    expect(((await db.read(`${fRoot}/PlayerTotals`)) as Json)['Bea'])
      .toEqual({ points: 15, ownershipPct: 67 });
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
      .toEqual({ points: 4, ownershipPct: 33 });
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
});
