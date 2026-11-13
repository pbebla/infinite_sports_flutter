// Mid-season joiners enter the market by themselves (season setup + schedule
// plan 2026-11-05, Task 7). Over the in-memory FakeDb (test_support.ts).
//
// World: Futsal season 16 is running (Config present, lockOverride auto).
// Its market holds Ann DEF 60 (uid u1, Team A), Bob DEF 66 (Team A), Cy ATT 120
// (Team B), Gus DEF 150 (NOT eligible), Gil GK 70 and Gwen GK 80 (Team B): the
// DEF average of the eligible players is 63 -> 65, the GK average 75, the ATT
// average 120.
//
// The brief's hard rule (review focus 5 / Fable M4): live scoring writes a stat
// increment under `<Sport>/<Season>/Line Ups/<team>/<player>/<Stat>` on every
// goal — the trigger must return before ANY read unless the roster's SHAPE
// (player keys, UIDs) changed.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { configToMap, futsalDefault } from './fantasy_config';
import type { FantasyLogger } from './orchestration';
import {
  maybeSyncRoster, rosterShapeChanged, syncRosterIntoMarket,
} from './roster_sync';
import { FakeDb } from './test_support';

const ROOT = 'Fantasy/Futsal/16';

/** A FakeDb that counts every read (the transaction's own included) and whose
 *  writeIfAbsent is ATOMIC like RTDB's transaction: the check and the claim
 *  happen with no yield between them (the stock FakeDb awaits a read first, so
 *  two concurrent claims would both see "absent"). */
class CountingDb extends FakeDb {
  reads: string[] = [];
  override async read(p: string): Promise<unknown> {
    this.reads.push(p);
    return super.read(p);
  }
  override async writeIfAbsent(p: string, value: unknown): Promise<boolean> {
    let node: any = this.data;
    for (const part of p.split('/').filter((x) => x.length > 0)) {
      if (node === null || node === undefined || typeof node !== 'object') {
        node = undefined;
        break;
      }
      node = node[part];
    }
    if (node !== null && node !== undefined) return false;
    await this.write(p, value); // write's body runs synchronously to its end
    return true;
  }
}

function logger(): FantasyLogger & { infos: string[]; warns: Array<[string, unknown]> } {
  const infos: string[] = [];
  const warns: Array<[string, unknown]> = [];
  return {
    infos, warns,
    info: (m) => { infos.push(m); },
    warn: (m, c) => { warns.push([m, c]); },
  };
}

function market(): Record<string, any> {
  const e = (position: string, priceTenths: number, teamName: string, extra = {}) =>
    ({ position, priceTenths, eligible: true, teamName, ...extra });
  return {
    Ann: e('DEF', 60, 'Team A', { uid: 'u1' }),
    Bob: e('DEF', 66, 'Team A'),
    Cy: e('ATT', 120, 'Team B'),
    Gus: { ...e('DEF', 150, 'Team B'), eligible: false },
    Gil: e('GK', 70, 'Team B'),
    Gwen: e('GK', 80, 'Team B'),
  };
}

function world(extra: Record<string, any> = {}): Record<string, any> {
  return {
    Fantasy: { Futsal: { 16: {
      Config: { ...configToMap(futsalDefault()), lockOverride: 'auto' },
      Players: market(),
    } } },
    ...extra,
  };
}

function db0(extra: Record<string, any> = {}): CountingDb {
  return new CountingDb(world(extra));
}

const players = (db: FakeDb) => (db.data.Fantasy.Futsal[16].Players as Record<string, any>);

const ARGS = { sport: 'Futsal', season: '16' };

describe('rosterShapeChanged [M4]', () => {
  const team = () => ({
    Ann: { UID: 'u1', Goals: 1, number: 7 },
    Bob: { UID: '', Goals: 0 },
  });

  it('a stat increment is not a shape change', () => {
    const after = team();
    after.Ann.Goals = 2;
    expect(rosterShapeChanged(team(), after)).toBe(false);
    const withAssist: any = team();
    withAssist.Bob.Assists = 1; // a stat that did not exist yet
    expect(rosterShapeChanged(team(), withAssist)).toBe(false);
  });

  it('a jersey number edit is not a shape change', () => {
    const after = team();
    after.Ann.number = 10;
    expect(rosterShapeChanged(team(), after)).toBe(false);
  });

  it('a player added is a shape change', () => {
    const after: any = team();
    after.Cy = { UID: '' };
    expect(rosterShapeChanged(team(), after)).toBe(true);
  });

  it('a player removed is a shape change', () => {
    const after: any = team();
    delete after.Bob;
    expect(rosterShapeChanged(team(), after)).toBe(true);
  });

  it('a UID linked (or relinked, or unlinked) is a shape change', () => {
    const linked = team();
    linked.Bob.UID = 'u2';
    expect(rosterShapeChanged(team(), linked)).toBe(true);
    const relinked = team();
    relinked.Ann.UID = 'u9';
    expect(rosterShapeChanged(team(), relinked)).toBe(true);
    const unlinked = team();
    unlinked.Ann.UID = '';
    expect(rosterShapeChanged(team(), unlinked)).toBe(true);
  });

  it('blank, "0" and missing UIDs all mean unlinked, and whitespace is trimmed', () => {
    const a: any = { Ann: { UID: '' }, Bob: { UID: '0' }, Cy: {}, Dee: { UID: ' u4 ' } };
    const b: any = { Ann: {}, Bob: { UID: '' }, Cy: { UID: '0' }, Dee: { UID: 'u4' } };
    expect(rosterShapeChanged(a, b)).toBe(false);
    expect(rosterShapeChanged(b, a)).toBe(false);
  });

  it('a team node created or deleted is a shape change', () => {
    expect(rosterShapeChanged(null, team())).toBe(true);
    expect(rosterShapeChanged(team(), null)).toBe(true);
    expect(rosterShapeChanged(undefined, team())).toBe(true);
  });

  it('nothing before and nothing after is no change', () => {
    expect(rosterShapeChanged(null, null)).toBe(false);
    expect(rosterShapeChanged(undefined, null)).toBe(false);
  });

  it('a renamed player (one key out, one in) is a shape change', () => {
    const after: any = { Ann: { UID: 'u1' }, Robert: { UID: '' } };
    expect(rosterShapeChanged(team(), after)).toBe(true);
  });
});

describe('maybeSyncRoster — the trigger handler', () => {
  it('an unchanged shape performs zero reads (and zero writes)', async () => {
    const db = db0();
    const before = { Ann: { UID: 'u1', Goals: 1 }, Newbie: { UID: 'u9', Goals: 0 } };
    const after = { Ann: { UID: 'u1', Goals: 2 }, Newbie: { UID: 'u9', Goals: 1 } };
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team A', before, after, log: logger(),
    });
    expect(res).toBeNull();
    expect(db.reads).toEqual([]);
    expect(db.writes).toEqual([]);
    expect(players(db).Newbie).toBeUndefined(); // not even a would-be joiner is looked at
  });

  it('a changed shape syncs the team', async () => {
    const db = db0();
    const before = { Ann: { UID: 'u1' } };
    const after = { Ann: { UID: 'u1' }, Newbie: {} };
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team A', before, after, log: logger(),
    });
    expect(res?.added).toEqual(['Newbie']);
    expect(players(db).Newbie.teamName).toBe('Team A');
  });

  it('a team deleted reads nothing and changes nothing (the market keeps its players)', async () => {
    const db = db0();
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team A', before: { Ann: {}, Bob: {} }, after: null, log: logger(),
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.reads).toEqual([]);
    expect(db.writes).toEqual([]);
  });

  it('team rename: the old node deleted + a new one written updates teamName, no duplicate', async () => {
    const db = db0();
    const roster = () => ({ Ann: { UID: 'u1', Goals: 3 }, Bob: { UID: '' } });
    await maybeSyncRoster(db, {
      ...ARGS, team: 'Team A', before: roster(), after: null, log: logger(),
    });
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team Z', before: null, after: roster(), log: logger(),
    });
    expect(res).toEqual({ added: [], teamUpdated: ['Ann', 'Bob'] });
    expect(players(db).Ann.teamName).toBe('Team Z');
    expect(players(db).Bob.teamName).toBe('Team Z');
    expect(Object.keys(players(db)).sort())
      .toEqual(['Ann', 'Bob', 'Cy', 'Gil', 'Gus', 'Gwen']);
    expect(players(db).Ann.priceTenths).toBe(60);
    expect(players(db).Bob.priceTenths).toBe(66);
  });
});

describe('syncRosterIntoMarket — a joiner', () => {
  it('joins at the DEF average, eligible, with team, uid and photo', async () => {
    const db = db0({
      Users: { u9: { Information: { FutsalPosition: 'Defender' } } },
      PublicProfiles: { u9: { ProfileUrl: ' https://img/u9.jpg ' } },
    });
    const log = logger();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', log,
      teamNode: { Ann: { UID: 'u1' }, Newbie: { UID: 'u9', Goals: 0 } },
    });
    expect(res).toEqual({ added: ['Newbie'], teamUpdated: [] });
    expect(players(db).Newbie).toEqual({
      position: 'DEF', priceTenths: 65, eligible: true, teamName: 'Team A',
      uid: 'u9', photoUrl: 'https://img/u9.jpg',
    });
    expect(log.infos.some((m) => m.includes('joined the market'))).toBe(true);
  });

  it('an unlinked joiner has no uid and no photo, and no sign-up reads happen for him', async () => {
    const db = db0();
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Newbie: {} },
    });
    expect(players(db).Newbie).toEqual({
      position: 'ATT', priceTenths: 120, eligible: true, teamName: 'Team A',
    });
    expect(db.reads.some((p) => p.startsWith('Users/') || p.startsWith('PublicProfiles/')))
      .toBe(false);
  });

  it('with no sign-up position he is ATT at the ATT average', async () => {
    const db = db0({ Users: { u9: { Information: { FutsalPosition: '' } } } });
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Newbie: { UID: 'u9' } },
    });
    expect(players(db).Newbie.position).toBe('ATT');
    expect(players(db).Newbie.priceTenths).toBe(120);
  });

  it('the sign-up position is read from the sport\'s own field', async () => {
    const db = new CountingDb({
      Fantasy: { 'Flag Football': { 4: {
        Config: configToMap(futsalDefault()),
        Players: {
          A: { position: 'GK', priceTenths: 100, eligible: true },
        },
      } } },
      Users: { u9: { Information: { FlagFootballPosition: 'Goal Keeper', FutsalPosition: 'Defender' } } },
    });
    await syncRosterIntoMarket(db, {
      sport: 'Flag Football', season: '4', team: 'T', teamNode: { Newbie: { UID: 'u9' } },
    });
    const p = (db.data.Fantasy['Flag Football'][4].Players as any).Newbie;
    expect(p.position).toBe('GK');
    expect(p.priceTenths).toBe(100);
  });

  it('a returning player joins at his last fantasy position but at TODAY\'s average, not his old price', async () => {
    const db = db0();
    db.data.Fantasy.Futsal[15] = { Players: {
      Dan: { position: 'GK', priceTenths: 110, eligible: true },
    } };
    // Sign-up says defender, last season says goalkeeper: the last season wins.
    db.data.Users = { u5: { Information: { FutsalPosition: 'Defender' } } };
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', teamNode: { Dan: { UID: 'u5' } },
    });
    expect(players(db).Dan).toMatchObject({
      position: 'GK', priceTenths: 75, eligible: true, teamName: 'Team B', uid: 'u5',
    });
  });

  it('a returning player is found by uid under a new name', async () => {
    const db = db0();
    db.data.Futsal = { 15: { 'Line Ups': { 'Team B': { Daniel: { UID: 'u5' } } } } };
    db.data.Fantasy.Futsal[15] = { Players: {
      Daniel: { position: 'GK', priceTenths: 110, eligible: true },
    } };
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', teamNode: { Dan: { UID: 'u5' } },
    });
    expect(players(db).Dan).toMatchObject({ position: 'GK', priceTenths: 75 });
  });

  it('a namesake of a returning player is NOT treated as him', async () => {
    const db = db0({ Users: { u8: { Information: { FutsalPosition: 'Defender' } } } });
    db.data.Fantasy.Futsal[15] = { Players: {
      Dan: { position: 'GK', priceTenths: 110, eligible: true, uid: 'u5' },
    } };
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', teamNode: { Dan: { UID: 'u8' } },
    });
    expect(players(db).Dan).toMatchObject({ position: 'DEF', priceTenths: 65 });
  });

  it('no eligible player of his position yet -> the rookie price', async () => {
    const db = db0();
    db.data.Fantasy.Futsal[16].Players = { A: { position: 'ATT', priceTenths: 100, eligible: true } };
    db.data.Users = { u9: { Information: { FutsalPosition: 'Goalkeeper' } } };
    await syncRosterIntoMarket(db, {
      ...ARGS, team: 'T', teamNode: { Newbie: { UID: 'u9' } },
    });
    expect(players(db).Newbie).toMatchObject({ position: 'GK', priceTenths: 60 });
  });

  it('nobody else\'s price or position moves when several join at once', async () => {
    const db = db0({ Users: {
      u7: { Information: { FutsalPosition: 'Defender' } },
      u8: { Information: { FutsalPosition: 'Defender' } },
    } });
    const before = JSON.parse(JSON.stringify(players(db)));
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team C', teamNode: { N1: { UID: 'u7' }, N2: { UID: 'u8' }, N3: {} },
    });
    expect(res.added.sort()).toEqual(['N1', 'N2', 'N3']);
    for (const [name, entry] of Object.entries(before)) {
      expect(players(db)[name]).toEqual(entry);
    }
    // Both defenders were priced off the market that was there, not each other.
    expect(players(db).N1.priceTenths).toBe(65);
    expect(players(db).N2.priceTenths).toBe(65);
  });

  it('Guest is never a market player', async () => {
    const db = db0();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Guest: { UID: 'u1' }, guest: {} },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
  });

  it('joins even while the season is paused (lockOverride is not a stand-down here)', async () => {
    const db = db0();
    db.data.Fantasy.Futsal[16].Config.lockOverride = 'locked';
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Newbie: {} },
    });
    expect(res.added).toEqual(['Newbie']);
  });
});

describe('syncRosterIntoMarket — a player already in the market', () => {
  it('only teamName changes — price, position and eligibility never do', async () => {
    const db = db0({ Users: { u1: { Information: { FutsalPosition: 'Goalkeeper' } } } });
    const before = JSON.parse(JSON.stringify(players(db)));
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', teamNode: { Ann: { UID: 'u1' }, Gus: {} },
    });
    expect(res).toEqual({ added: [], teamUpdated: ['Ann'] });
    expect(players(db).Ann).toEqual({ ...before.Ann, teamName: 'Team B' });
    expect(players(db).Gus).toEqual(before.Gus); // already on Team B
    // Nothing was looked up for people already in the market.
    expect(db.reads.some((p) => p.startsWith('Users/'))).toBe(false);
  });

  it('a market entry with no teamName gets one', async () => {
    const db = db0();
    delete players(db).Bob.teamName;
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Bob: {} },
    });
    expect(res.teamUpdated).toEqual(['Bob']);
    expect(players(db).Bob).toEqual({
      position: 'DEF', priceTenths: 66, eligible: true, teamName: 'Team A',
    });
  });

  it('a re-save of the same names (Create Lineup) makes no writes', async () => {
    const db = db0();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A',
      teamNode: { Ann: { UID: 'u1', Goals: 0 }, Bob: { UID: '', Goals: 0 } },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
  });

  it('a Create Lineup re-save through the handler is gated out before any read', async () => {
    const db = db0();
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team A', log: logger(),
      before: { Ann: { UID: 'u1', Goals: 4 }, Bob: { UID: '', Goals: 2 } },
      after: { Ann: { UID: 'u1', Goals: 0 }, Bob: { UID: '', Goals: 0 } },
    });
    expect(res).toBeNull();
    expect(db.reads).toEqual([]);
  });

  it('the same uid under a new name is not added twice — and it is logged', async () => {
    const db = db0();
    const log = logger();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', log, teamNode: { Annie: { UID: 'u1' } },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(Object.keys(players(db)).sort())
      .toEqual(['Ann', 'Bob', 'Cy', 'Gil', 'Gus', 'Gwen']);
    expect(log.warns).toHaveLength(1);
    expect(log.warns[0][0]).toContain('already in the market under another name');
    expect(log.warns[0][1]).toMatchObject({ name: 'Annie', existing: 'Ann', uid: 'u1' });
  });

  it('the same uid under a new name on ANOTHER team moves the entry\'s teamName', async () => {
    const db = db0();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', log: logger(), teamNode: { Annie: { UID: 'u1' } },
    });
    expect(res).toEqual({ added: [], teamUpdated: ['Ann'] });
    expect(players(db).Ann.teamName).toBe('Team B');
    expect(players(db).Ann.priceTenths).toBe(60);
  });

  it('an older entry WITHOUT a uid matches by name only', async () => {
    const db = db0({ Users: { u2: { Information: { FutsalPosition: 'Defender' } } } });
    // Bob (no uid field) is linked to u2 in the roster under a different name:
    // nothing in the market says Robert is Bob, so Robert is a new player.
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Robert: { UID: 'u2' } },
    });
    expect(res.added).toEqual(['Robert']);
  });

  it('a removed player stays in the market', async () => {
    const db = db0();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Ann: { UID: 'u1' } }, // Bob is gone
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(players(db).Bob).toBeDefined();
  });

  it('a teamName update never recreates an entry the owner deleted meanwhile', async () => {
    const db = db0();
    const realTx = db.transaction.bind(db);
    db.transaction = async (p, update) => {
      delete players(db).Bob; // gone between the snapshot and the update
      return realTx(p, update);
    };
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team Z', teamNode: { Bob: {} },
    });
    expect(res.teamUpdated).toEqual([]);
    expect(players(db).Bob).toBeUndefined();
  });
});

describe('syncRosterIntoMarket — when it does nothing', () => {
  it('a null team node does nothing and reads nothing', async () => {
    const db = db0();
    const res = await syncRosterIntoMarket(db, { ...ARGS, team: 'Team A', teamNode: null });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.reads).toEqual([]);
    expect(db.writes).toEqual([]);
  });

  it('a TestFill season is left alone', async () => {
    const db = db0();
    db.data.Fantasy.Futsal[16].TestFill = { At: 1 };
    const log = logger();
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', log, teamNode: { Newbie: {}, Ann: {} },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
    expect(log.infos.some((m) => m.includes('TestFill'))).toBe(true);
  });

  it('a season with no Config (fantasy not started) is left alone', async () => {
    const db = db0();
    delete db.data.Fantasy.Futsal[16].Config;
    const res = await syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team B', teamNode: { Newbie: {} },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
  });

  it('a season with no fantasy at all is left alone', async () => {
    const db = new CountingDb({});
    const res = await maybeSyncRoster(db, {
      ...ARGS, team: 'Team B', before: null, after: { Newbie: {} },
    });
    expect(res).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes).toEqual([]);
  });

  it('a failed read aborts the whole sync: nobody is half-added', async () => {
    const db = db0({ Users: { u9: { Information: { FutsalPosition: 'Defender' } } } });
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      if (p === 'PublicProfiles/u9/ProfileUrl') throw new Error('boom');
      return realRead(p);
    };
    await expect(syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team A', teamNode: { Plain: {}, Newbie: { UID: 'u9' } },
    })).rejects.toThrow('boom');
    expect(players(db).Plain).toBeUndefined();
    expect(players(db).Newbie).toBeUndefined();
    expect(db.writes).toEqual([]);
  });
});

describe('syncRosterIntoMarket — concurrency', () => {
  it('two teams\' triggers adding the same name produce ONE entry', async () => {
    const db = db0();
    const [a, b] = await Promise.all([
      syncRosterIntoMarket(db, { ...ARGS, team: 'Team A', teamNode: { Zed: {} } }),
      syncRosterIntoMarket(db, { ...ARGS, team: 'Team B', teamNode: { Zed: {} } }),
    ]);
    expect(a.added.length + b.added.length).toBe(1);
    expect(Object.keys(players(db)).filter((n) => n === 'Zed')).toHaveLength(1);
    expect(['Team A', 'Team B']).toContain(players(db).Zed.teamName);
    expect(players(db).Zed.priceTenths).toBe(120);
  });

  it('a second run over the same roster adds nothing', async () => {
    const db = db0();
    const run = () => syncRosterIntoMarket(db, {
      ...ARGS, team: 'Team C', teamNode: { Newbie: {} },
    });
    expect((await run()).added).toEqual(['Newbie']);
    const writesAfterFirst = db.writes.length;
    expect(await run()).toEqual({ added: [], teamUpdated: [] });
    expect(db.writes.length).toBe(writesAfterFirst);
  });
});

describe('wiring', () => {
  it('onLineupsWritten is exported by each of the three sport groups', () => {
    const src = path.join(__dirname, '..', '..');
    const index = fs.readFileSync(path.join(src, 'index.ts'), 'utf8');
    for (const sport of ['Futsal', 'Basketball', 'Flag Football']) {
      expect(index).toContain(`...makeFantasyRosterTrigger('${sport}')`);
    }
    const trigger = fs.readFileSync(path.join(src, 'fantasy_roster.ts'), 'utf8');
    expect(trigger).toContain('onLineupsWritten');
    expect(trigger).toContain('/Line Ups/{team}');
  });
});
