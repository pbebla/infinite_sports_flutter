// Season discovery + the reprice's latest week without whole-node reads
// (scale fixes D3 / D5). The 15-minute sweep and the hourly reprice used to
// read the WHOLE Fantasy node (every season's Players, Squads, Leaderboards,
// History...) just to learn which (sport, season) pairs exist, and the reprice
// read a season's whole History just to find its highest week. Now: keys-only
// reads down to each season's Config, and the LockedWeeks ledger.

import { describe, expect, it } from 'vitest';
import { STARTER_CATALOG } from './badges';
import { clone } from './golden_fixture';
import {
  FantasyLogger, runLifecycleSweep, runMondayReprice,
} from './orchestration';
import {
  fantasySeasonsOf, latestScoredWeek, listFantasySeasons,
} from './orchestration_db';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, GW1_DATE, LOCK2_MS, world2,
} from './test_support';

function spyLog() {
  const warns: Array<{ message: string; context?: Record<string, unknown> }> = [];
  const log: FantasyLogger = {
    info: () => undefined,
    warn: (message, context) => { warns.push({ message, context }); },
  };
  return { log, warns };
}

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

const KEYS_WARN = 'fantasy keys: shallow read failed';

describe('listFantasySeasons', () => {
  const fantasyFixture = () => ({
    Fantasy: {
      BadgeCatalog: { first_goal: { Name: 'First goal' } },
      Futsal: {
        '14': { Players: { Sam: { position: 'GK' } } }, // no Config -> not a season
        '15': { Config: { a: 1 } },
        '16': { Config: 'junk' }, // Config is not a map -> not a season
      },
      Basketball: {},
    },
  });

  it('finds exactly the seasons fantasySeasonsOf finds in the whole node', async () => {
    const db = new FakeDb(fantasyFixture());
    const seasons = await listFantasySeasons(db, silent);
    expect(seasons).toEqual(fantasySeasonsOf(fantasyFixture().Fantasy));
    expect(seasons).toEqual([
      { sport: 'Futsal', season: '15', configNode: { a: 1 } },
    ]);
  });

  it('never reads the whole Fantasy node, a sport node or a season node', async () => {
    const db = new FakeDb(fantasyFixture());
    await listFantasySeasons(db, silent);
    expect(db.reads).toContain('read:Fantasy/Futsal/15/Config');
    expect(db.reads).not.toContain('read:Fantasy');
    expect(db.reads).not.toContain('read:Fantasy/Futsal');
    expect(db.reads).not.toContain('read:Fantasy/Futsal/15');
    expect(db.reads).toEqual([
      'keys:Fantasy',
      'keys:Fantasy/Futsal',
      'read:Fantasy/Futsal/14/Config',
      'read:Fantasy/Futsal/15/Config',
      'read:Fantasy/Futsal/16/Config',
      'keys:Fantasy/Basketball',
    ]);
  });

  it('skips the BadgeCatalog sibling without even listing it', async () => {
    const db = new FakeDb(fantasyFixture());
    await listFantasySeasons(db, silent);
    expect(db.reads.some((r) => r.includes('BadgeCatalog'))).toBe(false);
  });

  it('lists sports then seasons in the order the keys come back', async () => {
    const db = new FakeDb({
      Fantasy: {
        Futsal: { '15': { Config: { x: 1 } }, '16': { Config: { x: 2 } } },
        Basketball: { '3': { Config: { x: 3 } } },
      },
    });
    const seasons = await listFantasySeasons(db, silent);
    expect(seasons.map((s) => `${s.sport}/${s.season}`))
      .toEqual(['Futsal/15', 'Futsal/16', 'Basketball/3']);
  });

  it('handles a list-coerced season node like the whole-node parser', async () => {
    // RTDB hands back small-int season keys as a null-padded array.
    const configs = [...Array(15).fill(null), { Config: { a: 1 } }, { Config: { a: 2 } }];
    const db = new FakeDb({ Fantasy: { Futsal: configs } });
    const seasons = await listFantasySeasons(db, silent);
    expect(seasons).toEqual(fantasySeasonsOf({ Futsal: configs }));
    expect(seasons.map((s) => s.season)).toEqual(['15', '16']);
  });

  it('a failed shallow read falls back to full reads — same seasons, one warning per failed read', async () => {
    const db = new FakeDb(fantasyFixture());
    db.childKeys = async () => { throw new Error('shallow read: HTTP 503'); };
    const { log, warns } = spyLog();
    const seasons = await listFantasySeasons(db, log);
    expect(seasons).toEqual(fantasySeasonsOf(fantasyFixture().Fantasy));
    // Fantasy itself + the two sports (BadgeCatalog is never listed).
    expect(warns.map((w) => w.message)).toEqual([KEYS_WARN, KEYS_WARN, KEYS_WARN]);
    expect(warns.map((w) => w.context?.path))
      .toEqual(['Fantasy', 'Fantasy/Futsal', 'Fantasy/Basketball']);
  });

  it('a db without childKeys discovers the same seasons by full reads, silently', async () => {
    const db = new FakeDb(fantasyFixture());
    db.childKeys = undefined;
    const { log, warns } = spyLog();
    expect(await listFantasySeasons(db, log))
      .toEqual(fantasySeasonsOf(fantasyFixture().Fantasy));
    expect(warns).toEqual([]);
  });

  it('is empty when nothing is fantasy-enabled', async () => {
    expect(await listFantasySeasons(new FakeDb({}), silent)).toEqual([]);
  });
});

describe('latestScoredWeek', () => {
  const ROOT = 'Fantasy/Futsal/15';
  const entry = (extra: Record<string, unknown> = {}) => ({
    Date: GW1_DATE, LockAtUtc: 1, ...extra,
  });

  it('is the largest week whose ledger entry is Scored, with no History read', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': {
        LockedWeeks: { 1: entry({ Scored: true }), 2: entry({ Scored: true }), 3: entry() },
        History: { 1: { a: 1 }, 2: { a: 1 } },
      } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(2);
    expect(db.reads).toEqual([`read:${ROOT}/LockedWeeks`]);
    expect(db.reads.some((r) => r.includes('History'))).toBe(false);
  });

  it('compares weeks as numbers, not strings (10 beats 9)', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': { LockedWeeks: {
        9: entry({ Scored: true }), 10: entry({ Scored: true }), 2: entry({ Scored: true }),
      } } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(10);
  });

  it('reads a list-coerced ledger (index = week, index 0 null)', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': { LockedWeeks: [
        null, entry({ Scored: true }), entry({ Scored: true }), entry(),
      ] } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(2);
  });

  it('counts only a literal Scored: true', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': {
        LockedWeeks: {
          1: entry({ Scored: true }), 2: entry({ Scored: 'true' }),
          3: entry({ Scored: 1 }), 4: entry({ Scored: false }),
        },
        History: { 1: { a: 1 } },
      } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(1);
  });

  it('falls back to the History keys when no ledger entry is scored', async () => {
    // A season locked before the ledger existed.
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': {
        LockedWeeks: { 5: entry() },
        History: { 1: { a: 1 }, 2: { a: 1 }, 3: { a: 1 }, 4: { a: 1 } },
      } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(4);
    // Keys only: the History weeks' contents are never downloaded.
    expect(db.reads).toEqual([`read:${ROOT}/LockedWeeks`, `keys:${ROOT}/History`]);
  });

  it('falls back with no ledger at all, taking the numerically largest integer key', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': {
        History: { 2: { a: 1 }, 10: { a: 1 }, junk: { a: 1 } },
      } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBe(10);
  });

  it('is null when nothing was scored or finalized', async () => {
    expect(await latestScoredWeek(new FakeDb({}), ROOT, silent)).toBeNull();
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': { LockedWeeks: { 1: entry() } } } },
    });
    expect(await latestScoredWeek(db, ROOT, silent)).toBeNull();
  });

  it('a failed keys read on the fallback falls back to the full History read, with one warning', async () => {
    const db = new FakeDb({
      Fantasy: { Futsal: { '15': { History: { 1: { a: 1 }, 3: { a: 1 } } } } },
    });
    db.childKeys = async () => { throw new Error('shallow read: HTTP 500'); };
    const { log, warns } = spyLog();
    expect(await latestScoredWeek(db, ROOT, log)).toBe(3);
    expect(warns.map((w) => w.message)).toEqual([KEYS_WARN]);
  });
});

describe('the sweep and the reprice never read whole season nodes', () => {
  /** Sweep a finished-lock world; the db the engine runs against. */
  async function sweptWorld(withKeys: boolean): Promise<FakeDb> {
    const db = new FakeDb(world2());
    if (!withKeys) db.childKeys = undefined;
    await runLifecycleSweep(db, AFTER_LOCK2);
    return db;
  }

  it('runLifecycleSweep: the same season work, and no read of the Fantasy, sport or season node', async () => {
    const db = await sweptWorld(true);

    // The sweep still did its job through the new discovery: GW2 locked,
    // snapshotted, finalized by the backstop.
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/History/2`)).not.toBeNull();
    expect((await db.read(`${F_ROOT}/GwState`) as Record<string, unknown>)['status'])
      .toBe('finalized');
    // The badge catalog is still seeded (from its own node).
    expect(await db.read('Fantasy/BadgeCatalog')).toEqual(STARTER_CATALOG);

    // (A sweep that locks and finalizes a week legitimately reads that
    // season's History for its contents — once per week, scale fixes D10 —
    // so only the discovery reads are pinned here; the quiet sweep below
    // pins History.)
    const reads = db.reads;
    expect(reads).not.toContain('read:Fantasy');
    expect(reads).not.toContain('read:Fantasy/Futsal');
    expect(reads).not.toContain(`read:${F_ROOT}`);
    expect(reads).toContain('read:Fantasy/BadgeCatalog');
    expect(reads).toContain(`read:${F_ROOT}/Config`);
    expect(reads.slice(0, 4)).toEqual([
      'read:Fantasy/BadgeCatalog', 'keys:Fantasy', 'keys:Fantasy/Futsal',
      `read:${F_ROOT}/Config`,
    ]);
  });

  it('runLifecycleSweep on a quiet day: never reads Fantasy or a season\'s whole History', async () => {
    // GW2 open, two hours before its lock: nothing to lock or finalize.
    const db = new FakeDb(world2());
    await runLifecycleSweep(db, new Date(LOCK2_MS - 2 * 3600_000));
    expect(db.reads).not.toContain('read:Fantasy');
    expect(db.reads).not.toContain(`read:${F_ROOT}/History`);
    expect(db.reads.some((r) => r === `keys:${F_ROOT}/History`)).toBe(false);
    // Only the starter catalog was written; the open week needed nothing.
    expect(db.writes.every((p) => p.startsWith('Fantasy/BadgeCatalog/'))).toBe(true);
  });

  it('runLifecycleSweep: writes the same data as with a db that cannot list keys', async () => {
    // The fallback path is today's whole-node reading; both must agree.
    const viaKeys = await sweptWorld(true);
    const viaFullRead = await sweptWorld(false);
    expect(viaKeys.snapshot()).toBe(viaFullRead.snapshot());
    expect(viaKeys.writes).toEqual(viaFullRead.writes);
  });

  it('runLifecycleSweep: a throwing keys read still sweeps every season (one warning per read)', async () => {
    const db = new FakeDb(world2());
    db.childKeys = async () => { throw new Error('shallow read: HTTP 503'); };
    const { log, warns } = spyLog();
    await runLifecycleSweep(db, AFTER_LOCK2, log);
    expect(warns.filter((w) => w.message === KEYS_WARN)).toHaveLength(2);
    expect((await db.read(`${F_ROOT}/GwState`) as Record<string, unknown>)['status'])
      .toBe('finalized');
  });

  // The reprice world = the golden "Monday repricing" week (orchestration
  // .test.ts): GW1 finalized, week points hand-computed in the fixture notes.
  const WEEK_POINTS: Record<string, number> = {
    Sam: 9, Dana: 13, Alex: 12, Wes: 1, Will: -4, Wren: 3,
    Eli: 0, Eva: -3, Ezra: 0, Bo: 12, Bea: 15, Ben: 9,
  };
  const NOW = new Date(Date.UTC(2026, 5, 22, 17)); // Monday 10:00 PDT, day after GW1

  function repriceWorld(opts: { scored: boolean; keys: boolean }): FakeDb {
    const data = world2();
    const season = data.Fantasy.Futsal['15'];
    season.PlayerWeeks = { 1: { ...WEEK_POINTS } };
    // The ledger the real engine writes for a finalized week 1.
    if (opts.scored) {
      season.LockedWeeks = {
        1: { Date: GW1_DATE, LockAtUtc: Date.UTC(2026, 5, 21, 22), Scored: true },
      };
    }
    const db = new FakeDb(clone(data));
    if (!opts.keys) db.childKeys = undefined;
    return db;
  }

  async function expectGoldenReprice(db: FakeDb): Promise<void> {
    // Golden reprice hand math (fixture _notes): GK mean 5.5 -> Bo +5,
    // Wes/Eli -5; DEF mean 5.25 -> Dana/Bea +5, Will/Eva -5; ATT mean 6 ->
    // Alex +5, Ezra -5. Sam/Wren/Ben hold.
    const price = async (name: string) =>
      db.read(`${F_ROOT}/Players/${name}/priceTenths`);
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
    expect(await db.read(`${F_ROOT}/Repriced/1`)).toEqual({ At: NOW.getTime() });
  }

  it('runMondayReprice with a scored ledger: golden prices, no read of Fantasy or History', async () => {
    const db = repriceWorld({ scored: true, keys: true });
    await runMondayReprice(db, NOW);
    await expectGoldenReprice(db);

    const reads = db.reads;
    expect(reads).not.toContain('read:Fantasy');
    expect(reads).not.toContain(`read:${F_ROOT}/History`);
    expect(reads.some((r) => r.endsWith('/History'))).toBe(false); // nor keys:
    expect(reads).toContain(`read:${F_ROOT}/LockedWeeks`);
  });

  it('runMondayReprice with no scored entry: golden prices via the History keys, never its contents', async () => {
    const db = repriceWorld({ scored: false, keys: true });
    await runMondayReprice(db, NOW);
    await expectGoldenReprice(db);

    const reads = db.reads;
    expect(reads).not.toContain('read:Fantasy');
    expect(reads).not.toContain(`read:${F_ROOT}/History`);
    expect(reads).toContain(`keys:${F_ROOT}/History`);
  });

  it('runMondayReprice: the same prices when keys cannot be listed (fallback = today)', async () => {
    const viaKeys = repriceWorld({ scored: false, keys: true });
    const viaFullRead = repriceWorld({ scored: false, keys: false });
    await runMondayReprice(viaKeys, NOW);
    await runMondayReprice(viaFullRead, NOW);
    await expectGoldenReprice(viaFullRead);
    expect(viaKeys.snapshot()).toBe(viaFullRead.snapshot());
  });

  it('runMondayReprice: an unscored, unfinalized season does nothing', async () => {
    const data = world2();
    delete data.Fantasy.Futsal['15'].History;
    const db = new FakeDb(data);
    await runMondayReprice(db, NOW);
    expect(db.writes).toEqual([]);
  });
});
