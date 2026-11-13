// The Start-a-season callables (season setup + schedule plan 2026-11-05,
// Task 6): previewFantasySeason and startFantasySeason driven through
// `.run(request)` with firebase-admin mocked over an in-memory tree
// (fantasy_access.test.ts style): the admin gate, the argument checks and the
// translation of the lib's errors into HttpsError code + details. The logic
// itself is covered in lib/fantasy/season_start.test.ts.

import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ tree: {} as Record<string, any> }));

/** Minimal admin Reference over h.tree: child().get()/set()/remove()/
 *  transaction() (what rtdbFantasyDb and requireAdmin use). */
function fakeRef(path: string): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = h.tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : node;
  };
  const write = (value: unknown) => {
    let node: any = h.tree;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') node[p] = {};
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete node[last]; else node[last] = value;
  };
  return {
    child: (sub: string) => fakeRef(`${path}/${sub}`),
    get: async () => ({ val: () => read() }),
    set: async (v: unknown) => write(JSON.parse(JSON.stringify(v))),
    remove: async () => write(null),
    transaction: async (update: (cur: unknown) => unknown) => {
      const cur = read();
      const next = update(cur === null ? null : JSON.parse(JSON.stringify(cur)));
      if (next === undefined) return { committed: false, snapshot: { val: () => cur } };
      write(next);
      return { committed: true, snapshot: { val: () => next } };
    },
  };
}

vi.mock('firebase-admin', () => ({
  database: () => ({ ref: (path?: string) => fakeRef(path ?? '') }),
}));
vi.mock('firebase-functions/logger', () => ({
  info: vi.fn(), warn: vi.fn(), error: vi.fn(),
}));

import { previewFantasySeason, startFantasySeason } from './fantasy_season';

/** A CallableRequest as the v2 runtime hands it over (only data/auth matter). */
function call(
  fn: { run: (req: never) => Promise<unknown> }, data: unknown, uid?: string,
): Promise<any> {
  return fn.run({
    data,
    auth: uid === undefined ? undefined : { uid, token: {} },
    rawRequest: {},
    acceptsStreaming: false,
  } as never);
}

const FREE = {
  Mode: 'free', AmountDollars: null,
  Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false,
};

function seed(): void {
  h.tree = {
    Admins: { adm: true },
    Futsal: {
      15: { 'Line Ups': { 'Team A': { Ann: { UID: 'u1' } } } },
      16: {
        'Line Ups': { 'Team A': { Ann: { UID: 'u1' }, Bea: { UID: '' } } },
        Date: { '11152026': [{ team1: 'Team A', team2: 'Team B' }] },
      },
    },
    Fantasy: { Futsal: { 15: {
      Config: { lockHour: 14 },
      Players: { Ann: { position: 'DEF', priceTenths: 85, eligible: true, teamName: 'Team A' } },
    } } },
  };
}

beforeEach(seed);

describe.each([
  ['previewFantasySeason', previewFantasySeason],
  ['startFantasySeason', startFantasySeason],
])('%s gate and arguments', (_name, fn) => {
  const good = { sport: 'Futsal', season: '16', access: FREE };

  it('unauthenticated -> unauthenticated', async () => {
    await expect(call(fn as never, good)).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('a signed-in non-admin -> permission-denied; nothing written', async () => {
    h.tree.Admins = { someoneElse: true };
    const before = JSON.stringify(h.tree);
    await expect(call(fn as never, good, 'fan')).rejects.toMatchObject({
      code: 'permission-denied',
    });
    expect(JSON.stringify(h.tree)).toBe(before);
  });

  it('a bad sport or season -> invalid-argument', async () => {
    for (const bad of [
      {}, { sport: 'Futsal' }, { season: '16' }, { sport: 'Chess', season: '16' },
      { sport: 'Futsal', season: '' }, { sport: 'Futsal', season: 'spring' },
      { sport: 'Futsal', season: '0' }, { sport: 'Futsal', season: '2026' },
      { sport: 'Futsal', season: '1.5' }, { sport: 'Futsal', season: ['16'] },
    ]) {
      await expect(call(fn as never, { ...bad, access: FREE }, 'adm')).rejects.toMatchObject({
        code: 'invalid-argument',
      });
    }
    await expect(call(fn as never, undefined, 'adm')).rejects.toMatchObject({
      code: 'invalid-argument',
    });
  });
});

describe('previewFantasySeason', () => {
  it('returns the preview and writes nothing', async () => {
    const before = JSON.stringify(h.tree);
    const preview = await call(previewFantasySeason, { sport: 'Futsal', season: 16 }, 'adm');
    expect(preview).toMatchObject({
      sport: 'Futsal', season: '16', sourceSeason: '15',
      settings: { lockHour: 14, copiedFrom: '15' },
      access: FREE, problems: [],
    });
    expect(preview.rows).toEqual([{
      name: 'Ann', team: 'Team A', uid: 'u1', position: 'DEF', positionFrom: 'season',
      priceTenths: 85, priceFrom: 'season', fromSeason: '15', photoUrl: null,
    }, {
      name: 'Bea', team: 'Team A', uid: null, position: 'ATT', positionFrom: 'default',
      priceTenths: 60, priceFrom: 'rookie', fromSeason: null, photoUrl: null,
    }]);
    expect(JSON.stringify(h.tree)).toBe(before);
  });

  it('a season that cannot start still previews, with the problems', async () => {
    delete h.tree.Futsal[16].Date;
    const preview = await call(previewFantasySeason, { sport: 'Futsal', season: '16' }, 'adm');
    expect(preview.problems).toEqual(['noSchedule']);
  });
});

describe('startFantasySeason', () => {
  it('starts the season as the calling admin and returns the player count', async () => {
    const res = await call(startFantasySeason, {
      sport: 'Futsal', season: 16, edits: { Bea: { priceTenths: 63 } }, access: FREE,
    }, 'adm');
    expect(res).toEqual({ players: 2 });
    const season = h.tree.Fantasy.Futsal[16];
    expect(season.StartedAt.By).toBe('adm');
    expect(season.Players.Bea.priceTenths).toBe(65);
    expect(season.Config.lockOverride).toBe('auto');
    expect(season.Config.Access).toMatchObject({ Mode: 'free', ChangedBy: 'adm' });
  });

  it('refusals carry the problem codes in details (failed-precondition)', async () => {
    delete h.tree.Futsal[16]['Line Ups'];
    const err = await call(startFantasySeason, { sport: 'Futsal', season: '16', access: FREE }, 'adm')
      .catch((e: unknown) => e);
    expect(err).toMatchObject({
      code: 'failed-precondition', details: { problems: ['noRosters'] },
    });
    expect(h.tree.Fantasy.Futsal[16]).toBeUndefined();
  });

  it('a second start -> failed-precondition alreadyStarted, nothing overwritten', async () => {
    await call(startFantasySeason, { sport: 'Futsal', season: '16', access: FREE }, 'adm');
    const before = JSON.stringify(h.tree);
    await expect(call(startFantasySeason,
      { sport: 'Futsal', season: '16', access: FREE }, 'adm')).rejects.toMatchObject({
      code: 'failed-precondition', details: { problems: ['alreadyStarted'] },
    });
    expect(JSON.stringify(h.tree)).toBe(before);
  });

  it('a bad season pass -> invalid-argument with details.problem badAccess', async () => {
    for (const access of [undefined, { ...FREE, Mode: 'pass', AmountDollars: 12.3 }]) {
      await expect(call(startFantasySeason,
        { sport: 'Futsal', season: '16', access }, 'adm')).rejects.toMatchObject({
        code: 'invalid-argument', details: { problem: 'badAccess' },
      });
    }
    expect(h.tree.Fantasy.Futsal[16]).toBeUndefined();
  });

  it('an unusable edit -> invalid-argument with details.problem badEdit', async () => {
    for (const edits of [[], { Ann: { position: 'MID' } }, { Ann: { priceTenths: '90' } }]) {
      await expect(call(startFantasySeason,
        { sport: 'Futsal', season: '16', edits, access: FREE }, 'adm')).rejects.toMatchObject({
        code: 'invalid-argument', details: { problem: 'badEdit' },
      });
    }
    expect(h.tree.Fantasy.Futsal[16]).toBeUndefined();
  });
});
