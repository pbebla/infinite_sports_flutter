// Starting a fantasy season from the Manager (season setup + schedule plan
// 2026-11-05, Task 6): the preview (every roster player with the price and
// position they start at, and where each came from), the season pass
// pre-filled from last season, and the one-shot start that writes Players
// then Config. Over the in-memory FakeDb (test_support.ts).
//
// World: Futsal season 16 is the one being started. Season 15 is its
// predecessor with a market (Ann DEF 85, Bob ATT 70, Cy DEF 40) and a Config
// carrying the owner's own settings plus every override the new season must
// NOT inherit.

import { describe, expect, it } from 'vitest';
import { configToMap, futsalDefault } from './fantasy_config';
import type { FantasyLogger } from './orchestration';
import {
  AccessDraft, buildSeasonPreview, parseEditsArg, startSeason, StartSeasonError,
} from './season_start';
import { FakeDb } from './test_support';

const ROOT = 'Fantasy/Futsal/16';
const NOW = Date.UTC(2026, 10, 15, 12);
const ADMIN = 'admin1';

const FREE: AccessDraft = {
  Mode: 'free', AmountDollars: null,
  Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false,
};

/** Season 15's Config: the engine numbers, the owner's tweaks, and the
 *  things a new season must drop. */
function sourceConfig(): Record<string, any> {
  return {
    ...configToMap(futsalDefault()),
    lockHour: 14, // an owner tweak: copied
    lockOverride: 'open',
    lockOverrideUntil: 1_900_000_000_000,
    Deadlines: { '11152026': 1_800_000_000_000 },
    SkippedDates: { '11222026': true },
    Reminder: { Enabled: false },
    NewsAutopilot: { Enabled: false },
    deadlineMinutesBeforeKickoff: 90,
    Access: {
      Mode: 'pass', AmountDollars: 12.5,
      Methods: { Venmo: true, Zelle: false, Card: true, Cash: true },
      RegisteredPlayersFree: true,
      Copy: { Headline: 'Old headline' }, ChangedAt: 5, ChangedBy: 'old-admin',
    },
  };
}

function world(): Record<string, any> {
  return {
    Futsal: {
      15: { 'Line Ups': { 'Team A': { Ann: { UID: 'u1' }, Bob: { UID: 'u2' } } } },
      16: {
        'Line Ups': {
          'Team A': { Ann: { UID: 'u1', Goals: 4 }, Robert: { UID: 'u2' }, Guest: { UID: '' } },
          'Team B': { Cy: { UID: '0' }, Dee: { UID: 'u4' }, Eli: { UID: 'u5' }, Fay: {} },
        },
        Date: { '11152026': [{ team1: 'Team A', team2: 'Team B' }] },
      },
    },
    Fantasy: { Futsal: { 15: {
      Config: sourceConfig(),
      Players: {
        Ann: { position: 'DEF', priceTenths: 85, eligible: true, teamName: 'Team A' },
        Bob: { position: 'ATT', priceTenths: 70, eligible: true, teamName: 'Team A' },
        Cy: { position: 'DEF', priceTenths: 40, eligible: true, teamName: 'Team B' },
      },
    } } },
    Users: {
      u4: { Information: { FutsalPosition: 'Defender;Striker' } },
      u5: { Information: { FutsalPosition: 'Goal Keeper' } },
    },
    PublicProfiles: {
      u1: { ProfileUrl: 'https://img.example/u1.jpg' },
      u4: { ProfileUrl: '  https://img.example/u4.jpg ' },
      u5: { ProfileUrl: '' },
    },
  };
}

function rowOf(rows: { name: string }[], name: string): any {
  return rows.find((r) => r.name === name);
}

class FailingWriteDb extends FakeDb {
  constructor(seed: Record<string, any>, private readonly failPath: string) {
    super(seed);
  }

  async write(path: string, value: unknown): Promise<void> {
    if (path === this.failPath && value !== null) throw new Error(`write failed: ${path}`);
    return super.write(path, value);
  }
}

describe('buildSeasonPreview — prices and positions', () => {
  it('a returning player keeps last season\'s final price and position (owner edit included)', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(rowOf(preview.rows, 'Ann')).toEqual({
      name: 'Ann', team: 'Team A', uid: 'u1', position: 'DEF', positionFrom: 'season',
      priceTenths: 85, priceFrom: 'season', fromSeason: '15',
      photoUrl: 'https://img.example/u1.jpg',
    });
    expect(preview.sourceSeason).toBe('15');
  });

  it('a player who sat out the newest season comes back at their older price', async () => {
    const w = world();
    w.Fantasy.Futsal[14] = { Players: {
      Cy: { position: 'ATT', priceTenths: 100, eligible: true },
      Gus: { position: 'GK', priceTenths: 90, eligible: true },
    } };
    w.Futsal[16]['Line Ups']['Team B'].Gus = {};
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    // Cy played S15 too: S15 wins. Gus only has S14.
    expect(rowOf(preview.rows, 'Cy')).toMatchObject({ priceTenths: 40, fromSeason: '15' });
    expect(rowOf(preview.rows, 'Gus')).toMatchObject({
      position: 'GK', priceTenths: 90, priceFrom: 'season', fromSeason: '14',
    });
  });

  it('a uid match beats a renamed roster entry', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    // Robert is Bob (u2) renamed.
    expect(rowOf(preview.rows, 'Robert')).toMatchObject({
      uid: 'u2', position: 'ATT', priceTenths: 70, priceFrom: 'season', fromSeason: '15',
    });
  });

  it('a new player takes the sign-up position at the average of returning players there, snapped', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    // Returning DEF: Ann 85 + Cy 40 = mean 62.5 -> 63 -> snapped to 65.
    expect(rowOf(preview.rows, 'Dee')).toEqual({
      name: 'Dee', team: 'Team B', uid: 'u4', position: 'DEF', positionFrom: 'signup',
      priceTenths: 65, priceFrom: 'average', fromSeason: null,
      photoUrl: 'https://img.example/u4.jpg',
    });
  });

  it('no returning player in a position -> the rookie price', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(rowOf(preview.rows, 'Eli')).toEqual({
      name: 'Eli', team: 'Team B', uid: 'u5', position: 'GK', positionFrom: 'signup',
      priceTenths: 60, priceFrom: 'rookie', fromSeason: null, photoUrl: null,
    });
  });

  it('a new player with no sign-up position is ATT by default, at the ATT average', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(rowOf(preview.rows, 'Fay')).toMatchObject({
      uid: null, position: 'ATT', positionFrom: 'default', priceTenths: 70, priceFrom: 'average',
    });
  });

  it('new players never feed the average (only returning rows do)', async () => {
    const w = world();
    // Two more new DEFs signing up at defender; none changes Dee's 65.
    w.Futsal[16]['Line Ups']['Team B'].Gil = { UID: 'u6' };
    w.Users.u6 = { Information: { FutsalPosition: 'Defender' } };
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    expect(rowOf(preview.rows, 'Dee').priceTenths).toBe(65);
    expect(rowOf(preview.rows, 'Gil').priceTenths).toBe(65);
  });

  it('guests are excluded', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(preview.rows.map((r) => r.name)).toEqual(
      ['Ann', 'Robert', 'Cy', 'Dee', 'Eli', 'Fay']);
  });

  it('uses the basketball sign-up field for another sport', async () => {
    const w = world();
    w.Basketball = { 3: {
      'Line Ups': { T: { Zed: { UID: 'u9' } } },
      Date: { '11152026': [{}] },
    } };
    w.Users.u9 = { Information: { BasketballPosition: 'Goal Keeper', FutsalPosition: 'Striker' } };
    const preview = await buildSeasonPreview(new FakeDb(w), 'Basketball', '3');
    expect(rowOf(preview.rows, 'Zed')).toMatchObject({ position: 'GK', positionFrom: 'signup' });
  });

  it('with no earlier fantasy season everyone is new: sign-up position, rookie price', async () => {
    const w = world();
    delete w.Fantasy;
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    expect(preview.sourceSeason).toBeNull();
    expect(preview.settings).toEqual({ lockHour: 15, copiedFrom: null });
    expect(rowOf(preview.rows, 'Ann')).toMatchObject({
      position: 'ATT', positionFrom: 'default', priceTenths: 60, priceFrom: 'rookie',
    });
    expect(rowOf(preview.rows, 'Dee')).toMatchObject({ position: 'DEF', positionFrom: 'signup' });
  });

  it('reports the lock hour and the season the Config is copied from', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(preview.settings).toEqual({ lockHour: 14, copiedFrom: '15' });
  });

  it('never writes anything', async () => {
    const db = new FakeDb(world());
    const before = db.snapshot();
    await buildSeasonPreview(db, 'Futsal', '16');
    expect(db.writes).toEqual([]);
    expect(db.snapshot()).toBe(before);
  });

  it('a failed read aborts the preview — a missing position is not a fact', async () => {
    const db = new FakeDb(world());
    const read = db.read.bind(db);
    db.read = async (path: string) => {
      if (path === 'Users/u4/Information/FutsalPosition') throw new Error('boom');
      return read(path);
    };
    await expect(buildSeasonPreview(db, 'Futsal', '16')).rejects.toThrow('boom');
  });
});

describe('buildSeasonPreview — the season pass draft [S1]', () => {
  it('is pre-filled from the source season\'s Access (Cash and the stamps dropped)', async () => {
    const preview = await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16');
    expect(preview.access).toEqual({
      Mode: 'pass', AmountDollars: 12.5,
      Methods: { Venmo: true, Zelle: false, Card: true }, RegisteredPlayersFree: true,
    });
  });

  it('no source Access -> free, everything switched on', async () => {
    const w = world();
    delete w.Fantasy.Futsal[15].Config.Access;
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    expect(preview.access).toEqual(FREE);
  });

  it('no earlier season at all -> the free defaults too', async () => {
    const w = world();
    delete w.Fantasy;
    expect((await buildSeasonPreview(new FakeDb(w), 'Futsal', '16')).access).toEqual(FREE);
  });

  it('a free source with no price pre-fills AmountDollars null', async () => {
    const w = world();
    w.Fantasy.Futsal[15].Config.Access = { Mode: 'free', AmountDollars: 0,
      Methods: { Venmo: true, Zelle: true, Card: false }, RegisteredPlayersFree: false };
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    expect(preview.access).toEqual({
      Mode: 'free', AmountDollars: null,
      Methods: { Venmo: true, Zelle: true, Card: false }, RegisteredPlayersFree: false,
    });
  });
});

describe('buildSeasonPreview — problems', () => {
  it('a clean season has none', async () => {
    expect((await buildSeasonPreview(new FakeDb(world()), 'Futsal', '16')).problems).toEqual([]);
  });

  it('noRosters: nobody in Line Ups', async () => {
    const w = world();
    w.Futsal[16]['Line Ups'] = { 'Team A': { Guest: { UID: '' } } };
    const preview = await buildSeasonPreview(new FakeDb(w), 'Futsal', '16');
    expect(preview.problems).toEqual(['noRosters']);
    expect(preview.rows).toEqual([]);
  });

  it('noSchedule: no game dates', async () => {
    const w = world();
    delete w.Futsal[16].Date;
    expect((await buildSeasonPreview(new FakeDb(w), 'Futsal', '16')).problems)
      .toEqual(['noSchedule']);
  });

  it('alreadyStarted: the season has a Config', async () => {
    const w = world();
    w.Fantasy.Futsal[16] = { Config: { lockOverride: 'auto' } };
    expect((await buildSeasonPreview(new FakeDb(w), 'Futsal', '16')).problems)
      .toEqual(['alreadyStarted']);
  });

  it('alreadyStarted: a StartedAt claim without a Config (a Start under way or one that died)', async () => {
    const w = world();
    w.Fantasy.Futsal[16] = { StartedAt: { At: 1, By: 'admin2' } };
    const db = new FakeDb(w);
    expect((await buildSeasonPreview(db, 'Futsal', '16')).problems).toEqual(['alreadyStarted']);
    await expect(startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW)).rejects.toMatchObject({
      code: 'failed-precondition', details: { problems: ['alreadyStarted'] },
    });
    expect(db.writes).toEqual([]);
  });

  it('sourceIsTestFill: the source season carries the TestFill marker', async () => {
    const w = world();
    w.Fantasy.Futsal[15].TestFill = { At: 1, Managers: 8 };
    expect((await buildSeasonPreview(new FakeDb(w), 'Futsal', '16')).problems)
      .toEqual(['sourceIsTestFill']);
  });

  it('reports every problem at once, in a fixed order', async () => {
    const w = world();
    w.Futsal[16] = {};
    w.Fantasy.Futsal[16] = { Config: { lockOverride: 'auto' } };
    w.Fantasy.Futsal[15].TestFill = { At: 1 };
    expect((await buildSeasonPreview(new FakeDb(w), 'Futsal', '16')).problems)
      .toEqual(['noRosters', 'noSchedule', 'alreadyStarted', 'sourceIsTestFill']);
  });
});

describe('startSeason', () => {
  it('writes Players, StartedAt and the Config; returns the player count', async () => {
    const db = new FakeDb(world());
    const res = await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW);
    expect(res).toEqual({ players: 6 });
    const season = db.data.Fantasy.Futsal[16];
    expect(season.StartedAt).toEqual({ At: NOW, By: ADMIN });
    expect(season.Players.Ann).toEqual({
      position: 'DEF', priceTenths: 85, eligible: true, teamName: 'Team A',
      uid: 'u1', photoUrl: 'https://img.example/u1.jpg',
    });
    // No uid and no photo -> neither key (RTDB cannot store undefined).
    expect(season.Players.Fay).toEqual({
      position: 'ATT', priceTenths: 70, eligible: true, teamName: 'Team B',
    });
    expect(Object.keys(season.Players).sort()).toEqual(
      ['Ann', 'Cy', 'Dee', 'Eli', 'Fay', 'Robert']);
  });

  it('Config is a copy of the source minus Access/overrides, lockOverride auto', async () => {
    const db = new FakeDb(world());
    await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW);
    const written = db.data.Fantasy.Futsal[16].Config;
    const source = sourceConfig();
    for (const gone of ['lockOverrideUntil', 'Deadlines', 'SkippedDates']) {
      expect(written).not.toHaveProperty(gone);
      delete source[gone];
    }
    delete source.Access;
    delete source.lockOverride;
    expect(written).toEqual({
      ...source,
      lockOverride: 'auto',
      Access: {
        Mode: 'free', AmountDollars: 0,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false,
        ChangedAt: NOW, ChangedBy: ADMIN,
      },
    });
    expect(written.lockHour).toBe(14);
    expect(written.Reminder).toEqual({ Enabled: false });
  });

  it('with no earlier season the Config is the futsal default plus lockOverride auto', async () => {
    const w = world();
    delete w.Fantasy;
    const db = new FakeDb(w);
    await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW);
    const written = db.data.Fantasy.Futsal[16].Config;
    expect({ ...written, Access: undefined }).toEqual({
      ...configToMap(futsalDefault()), lockOverride: 'auto', Access: undefined,
    });
  });

  it('Config/Access is written in the Manager\'s own shape (exact keys)', async () => {
    const db = new FakeDb(world());
    await startSeason(db, 'Futsal', '16', {}, {
      Mode: 'pass', AmountDollars: 12.5,
      Methods: { Venmo: true, Zelle: false, Card: true }, RegisteredPlayersFree: true,
    }, ADMIN, NOW);
    const access = db.data.Fantasy.Futsal[16].Config.Access;
    expect(access).toEqual({
      Mode: 'pass', AmountDollars: 12.5,
      Methods: { Venmo: true, Zelle: false, Card: true }, RegisteredPlayersFree: true,
      ChangedAt: NOW, ChangedBy: ADMIN,
    });
    // fantasy_access_admin.dart AccessConfig.toMap + the service's stamps; the
    // source season's Copy, Cash and old stamps never come along.
    expect(Object.keys(access).sort()).toEqual(
      ['AmountDollars', 'ChangedAt', 'ChangedBy', 'Methods', 'Mode', 'RegisteredPlayersFree']);
    expect(Object.keys(access.Methods).sort()).toEqual(['Card', 'Venmo', 'Zelle']);
  });

  it('a whole-dollar pass price and a $1000 price are fine', async () => {
    for (const amount of [1, 10, 0.5, 1000]) {
      const db = new FakeDb(world());
      await startSeason(db, 'Futsal', '16', {}, {
        Mode: 'pass', AmountDollars: amount,
        Methods: { Venmo: false, Zelle: false, Card: true }, RegisteredPlayersFree: false,
      }, ADMIN, NOW);
      expect(db.data.Fantasy.Futsal[16].Config.Access.AmountDollars).toBe(amount);
    }
  });

  it('applies edits: price snapped and clamped, position changed', async () => {
    const db = new FakeDb(world());
    const infos: Array<{ message: string; context?: Record<string, unknown> }> = [];
    const log: FantasyLogger = {
      info: (message, context) => infos.push({ message, context }),
      warn: (message, context) => infos.push({ message, context }),
    };
    await startSeason(db, 'Futsal', '16', {
      Ann: { priceTenths: 200 }, // above the max -> 150
      Cy: { priceTenths: 63, position: 'GK' }, // snapped to 65, now a GK
      Dee: { priceTenths: 5 }, // below the min -> 40
      Nobody: { priceTenths: 50 }, // not in the roster: ignored
    }, FREE, ADMIN, NOW, log);
    const players = db.data.Fantasy.Futsal[16].Players;
    expect(players.Ann.priceTenths).toBe(150);
    expect(players.Ann.position).toBe('DEF');
    expect(players.Cy).toMatchObject({ priceTenths: 65, position: 'GK' });
    expect(players.Dee.priceTenths).toBe(40);
    expect(players).not.toHaveProperty('Nobody');
    expect(infos.some((i) => i.context?.['ignoredEdits'] === 1)).toBe(true);
  });

  it('rejects a position that is not GK/DEF/ATT — nothing is written', async () => {
    const db = new FakeDb(world());
    await expect(startSeason(db, 'Futsal', '16',
      { Ann: { position: 'MID' as never } }, FREE, ADMIN, NOW))
      .rejects.toMatchObject({ code: 'invalid-argument', details: { problem: 'badEdit' } });
    expect(db.writes).toEqual([]);
  });

  it('rejects a price that is not a finite number', async () => {
    const db = new FakeDb(world());
    await expect(startSeason(db, 'Futsal', '16',
      { Ann: { priceTenths: Number.NaN } }, FREE, ADMIN, NOW))
      .rejects.toMatchObject({ code: 'invalid-argument', details: { problem: 'badEdit' } });
    expect(db.writes).toEqual([]);
  });

  it('refuses with the problem codes (failed-precondition) when anything blocks the start', async () => {
    const w = world();
    delete w.Futsal[16].Date;
    w.Fantasy.Futsal[15].TestFill = { At: 1 };
    const db = new FakeDb(w);
    const err = await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW)
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(StartSeasonError);
    expect(err).toMatchObject({
      code: 'failed-precondition',
      details: { problems: ['noSchedule', 'sourceIsTestFill'] },
    });
    expect(db.writes).toEqual([]);
  });

  describe('bad season pass -> invalid-argument badAccess, nothing written', () => {
    const bad: Array<[string, unknown]> = [
      ['$0', { Mode: 'pass', AmountDollars: 0,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['no price', { Mode: 'pass', AmountDollars: null,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['$12.30', { Mode: 'pass', AmountDollars: 12.3,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['$12.499', { Mode: 'pass', AmountDollars: 12.499,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['$1001', { Mode: 'pass', AmountDollars: 1001,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['negative', { Mode: 'pass', AmountDollars: -5,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['NaN', { Mode: 'pass', AmountDollars: Number.NaN,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['no way to pay', { Mode: 'pass', AmountDollars: 10,
        Methods: { Venmo: false, Zelle: false, Card: false }, RegisteredPlayersFree: false }],
      ['unknown mode', { Mode: 'paid', AmountDollars: 10,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['no methods map', { Mode: 'free', AmountDollars: null, RegisteredPlayersFree: false }],
      ['non-boolean method', { Mode: 'free', AmountDollars: null,
        Methods: { Venmo: 'yes', Zelle: true, Card: true }, RegisteredPlayersFree: false }],
      ['non-boolean RegisteredPlayersFree', { Mode: 'free', AmountDollars: null,
        Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: 1 }],
      ['not a map', 'pass'],
      ['absent', undefined],
    ];
    for (const [label, access] of bad) {
      it(label, async () => {
        const db = new FakeDb(world());
        await expect(startSeason(db, 'Futsal', '16', {}, access as AccessDraft, ADMIN, NOW))
          .rejects.toMatchObject({
            code: 'invalid-argument', details: { problem: 'badAccess' },
          });
        expect(db.writes).toEqual([]);
      });
    }
  });

  it('a second start answers alreadyStarted and overwrites nothing', async () => {
    const db = new FakeDb(world());
    await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW);
    const after = db.snapshot();
    const writes = db.writes.length;
    await expect(startSeason(db, 'Futsal', '16', { Ann: { priceTenths: 40 } }, FREE, 'admin2', NOW + 1))
      .rejects.toMatchObject({
        code: 'failed-precondition', details: { problems: ['alreadyStarted'] },
      });
    expect(db.snapshot()).toBe(after);
    expect(db.writes.length).toBe(writes);
  });

  it('losing the StartedAt claim to a concurrent start is alreadyStarted too', async () => {
    const db = new FakeDb(world());
    const writeIfAbsent = db.writeIfAbsent.bind(db);
    db.writeIfAbsent = async (path: string, value: unknown) => {
      // The other start lands between our preview and our claim.
      await writeIfAbsent(path, { At: 1, By: 'other' });
      return writeIfAbsent(path, value);
    };
    await expect(startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW))
      .rejects.toMatchObject({
        code: 'failed-precondition', details: { problems: ['alreadyStarted'] },
      });
    expect(db.data.Fantasy.Futsal[16].StartedAt).toEqual({ At: 1, By: 'other' });
    expect(db.data.Fantasy.Futsal[16]).not.toHaveProperty('Players');
    expect(db.data.Fantasy.Futsal[16]).not.toHaveProperty('Config');
  });

  it('a failed Players write rolls back StartedAt and rethrows', async () => {
    const db = new FailingWriteDb(world(), `${ROOT}/Players`);
    await expect(startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW))
      .rejects.toThrow('write failed');
    const season = db.data.Fantasy.Futsal[16] ?? {};
    expect(season).not.toHaveProperty('StartedAt');
    expect(season).not.toHaveProperty('Players');
    expect(season).not.toHaveProperty('Config');
    // ...so the owner can simply try again.
    const retry = new FakeDb(db.data);
    await expect(startSeason(retry, 'Futsal', '16', {}, FREE, ADMIN, NOW)).resolves
      .toEqual({ players: 6 });
  });

  it('a failed Config write removes the Players and StartedAt it already wrote', async () => {
    const db = new FailingWriteDb(world(), `${ROOT}/Config`);
    await expect(startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW))
      .rejects.toThrow('write failed');
    const season = db.data.Fantasy.Futsal[16] ?? {};
    expect(season).not.toHaveProperty('StartedAt');
    expect(season).not.toHaveProperty('Players');
    expect(season).not.toHaveProperty('Config');
  });

  it('writes the Config last — the engine switches on at Config, after the market exists', async () => {
    const db = new FakeDb(world());
    await startSeason(db, 'Futsal', '16', {}, FREE, ADMIN, NOW);
    expect(db.writes).toEqual([`${ROOT}/StartedAt`, `${ROOT}/Players`, `${ROOT}/Config`]);
  });
});

describe('parseEditsArg (the callable\'s edits)', () => {
  it('absent -> no edits; a good map passes through', () => {
    expect(parseEditsArg(undefined)).toEqual({});
    expect(parseEditsArg(null)).toEqual({});
    expect(parseEditsArg({ Ann: { priceTenths: 90, position: 'GK' }, Bob: {} }))
      .toEqual({ Ann: { priceTenths: 90, position: 'GK' }, Bob: {} });
  });

  it('anything malformed is invalid-argument', () => {
    for (const bad of [[], 'x', { Ann: 5 }, { Ann: [] }, { Ann: { priceTenths: '90' } },
      { Ann: { priceTenths: Number.NaN } }, { Ann: { position: 3 } }]) {
      expect(() => parseEditsArg(bad)).toThrowError(StartSeasonError);
    }
  });
});
