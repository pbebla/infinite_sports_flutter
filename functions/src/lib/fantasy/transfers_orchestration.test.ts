// Phase E transfer accounting over an in-memory FantasyDb: the squad-save
// counter (recordSquadSave), the lock-time chip void + cost freeze riding
// the PublishedPicks snapshot, the finalize cost application through the
// transferCostPointsByUid seam, the Free Hit squad restore, and the
// once-only rollover. Built on a TWO-gameweek world: GW1 (06212026) already
// finalized with the golden squads, GW2 (06282026) the week under test.
// Golden gross tenths: alpha 350, boost 440, churn 595 (fixture _notes).

import { describe, expect, it } from 'vitest';
import { clone, Json, loadGoldenFixture } from './golden_fixture';
import {
  maybeFinalizeGame, recordSquadSave, runLifecycleSweep,
} from './orchestration';
import { FantasyDb } from './orchestration_db';

const fixture = loadGoldenFixture();

const GW1_DATE = '06212026'; // Sunday
const GW2_DATE = '06282026'; // Sunday; lockHour 15 => lock 22:00Z (PDT)
const LOCK2_MS = Date.UTC(2026, 5, 28, 22);
const AFTER_LOCK2 = new Date(Date.UTC(2026, 5, 28, 23));

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
}

function fixtureSquad(name: string): Json {
  const s = (fixture['squads'] as Json[]).find((x) => x['name'] === name)!;
  return clone(s['squad']);
}

/** Two gameweeks: GW1 finalized (History + PublishedPicks seeded from the
 *  golden squads — boost's GW1 chip was benchBoost), GW2 under test. */
function world2(opts: {
  gw2Status?: number;
  chipSet1EndGw?: number;
} = {}): Record<string, any> {
  const games: Json[] = fixture['games'];
  const mkGames = (status?: number) => {
    const g1 = clone(games[0]['node']) as Json;
    const g2 = clone(games[1]['node']) as Json;
    g2['team1attendance'] = { Ezra: false };
    if (status !== undefined) {
      g1['status'] = status;
      g2['status'] = status;
    }
    return [g1, g2];
  };
  const players: Json = {};
  for (const p of fixture['players'] as Json[]) {
    players[p['id']] = {
      position: p['position'], priceTenths: p['priceTenths'], eligible: true,
    };
  }
  const squads: Json = {};
  const history1: Json = {};
  const published1: Json = {};
  const grossTenths: Record<string, number> = {
    alpha: 350, boost: 440, churn: 595,
  };
  for (const s of fixture['squads'] as Json[]) {
    const name = s['name'] as string;
    squads[name] = clone(s['squad']);
    published1[name] = clone(s['squad']);
    history1[name] = {
      ...clone(s['squad']), TotalTenths: grossTenths[name], Breakdown: [],
    };
  }
  return {
    Fantasy: {
      Futsal: {
        '15': {
          Config: {
            lockHour: 15,
            ...(opts.chipSet1EndGw !== undefined
              ? { chipSet1EndGw: opts.chipSet1EndGw } : {}),
          },
          Players: players,
          Squads: squads,
          History: { 1: history1 },
          PublishedPicks: { 1: published1 },
          GwState: {
            current: 2, status: 'open', lockAtUtc: LOCK2_MS, date: GW2_DATE,
          },
        },
      },
    },
    Futsal: {
      '15': {
        Date: {
          [GW1_DATE]: mkGames(),
          [GW2_DATE]: mkGames(opts.gw2Status),
        },
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
const saveArgs = (uid: string) => ({ sport: 'Futsal', season: '15', uid });

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

  it('no-ops while locked, while frozen, and without a Config or GwState', async () => {
    const locked = new FakeDb(world2());
    locked.data.Fantasy.Futsal['15'].GwState.status = 'locked';
    await recordSquadSave(locked, saveArgs('churn'));
    expect(locked.writes).toEqual([]);

    const frozen = new FakeDb(world2());
    frozen.data.Fantasy.Futsal['15'].Config.lockOverride = 'open';
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
    expect(published['boost']).toEqual(expectedBoost);
    expect(published['alpha']).toEqual(fixtureSquad('alpha')); // verbatim
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
    // The GW1 locked squad came back, chip-free (fixture churn has none).
    expect(await db.read(`${fRoot}/Squads/churn`))
      .toEqual(fixtureSquad('churn'));
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
    await runLifecycleSweep(db, new Date(Date.UTC(2026, 5, 21, 23)));
    expect(await db.read(`${fRoot}/History/1`)).not.toBeNull();
    expect(await db.read(`${fRoot}/Squads/alpha`)).toEqual(liveAlpha);
    expect(await db.read(`${fRoot}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 1,
    });
  });
});
