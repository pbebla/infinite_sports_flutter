// Holder protection on a position change (spec §3 owner revision
// 2026-10-28) over the in-memory FantasyDb: open-window relabel + alert +
// push, a relabel that leaves the formation legal (no alert), the locked
// window deferring to PendingPositionChanges and the reopen sweep applying
// it, the free swap, and the alert clearing on a legal save.
//
// Golden squads (fixture): alpha Eli GK · Dana DEF · Eva DEF · Ezra ATT ·
// Alex ATT · bench Will DEF / Wren ATT. boost Sam GK · Bea DEF · Will DEF ·
// Ben ATT · Wren ATT · bench Eva DEF / Ezra ATT. churn Bo GK · Dana DEF ·
// Bea DEF · Ezra ATT · Ben ATT · bench Eva DEF / Wren ATT.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import { recordSquadSave, runLifecycleSweep } from './orchestration';
import {
  handlePositionWrite, positionWindowOf, squadAlertBody,
} from './position_changes';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, FakePusher, GW2_DATE, LOCK2_MS, world2,
} from './test_support';

const GW3_DATE = '07052026';
const GW3_OPEN = new Date(Date.UTC(2026, 5, 29, 23));
// Saturday before the GW2 lock: the GW2 window is open.
const OPEN_NOW = new Date(Date.UTC(2026, 5, 27, 18));

function world3(opts: Parameters<typeof world2>[0] = {}): FakeDb {
  const db = new FakeDb(world2(opts));
  db.data.Futsal['15'].Date[GW3_DATE] = (clone(db.data.Futsal['15'].Date[GW2_DATE]) as Json[])
    .map((g) => ({ ...g, status: 0 }));
  return db;
}

/** The Manager writes Players/<name>/position; the trigger runs. */
async function movePlayer(
  db: FakeDb, name: string, to: string, nowUtc: Date, pusher?: FakePusher,
): Promise<string> {
  const players = db.data.Fantasy.Futsal['15'].Players;
  const before = players[name].position;
  players[name].position = to;
  return handlePositionWrite(db, {
    sport: 'Futsal', season: '15', name, before, after: to, nowUtc, pusher,
  });
}

const pickOf = (squad: Json, id: string) =>
  (squad['picks'] as Json[]).find((p) => p['playerId'] === id)!;
/** RTDB never stores an empty map (removing the last child removes the
 *  parent); FakeDb leaves `{}` behind — read both as absent. */
const absent = async (db: FakeDb, path: string) => {
  const v = await db.read(path);
  return v === null || (typeof v === 'object' && Object.keys(v as object).length === 0);
};
const save = (db: FakeDb, uid: string, nowUtc = OPEN_NOW) =>
  recordSquadSave(db, { sport: 'Futsal', season: '15', uid, nowUtc });

describe('positionWindowOf', () => {
  it('open only while GwState is open AND its lock is ahead; no GwState = pre-season', () => {
    const open = { current: 2, status: 'open', lockAtUtc: LOCK2_MS, date: GW2_DATE };
    expect(positionWindowOf(open, LOCK2_MS - 1)).toBe('open');
    expect(positionWindowOf(open, LOCK2_MS)).toBe('locked'); // sweep not flipped yet
    expect(positionWindowOf({ ...open, status: 'locked' }, 0)).toBe('locked');
    expect(positionWindowOf({ ...open, status: 'finalized' }, 0)).toBe('locked');
    expect(positionWindowOf(null, 0)).toBe('open');
  });
});

describe('squadAlertBody', () => {
  it('spec copy, one or several changes', () => {
    expect(squadAlertBody([{ player: 'Bea', from: 'DEF', to: 'ATT' }], 'Sun, Jun 28 · 3:00 PM'))
      .toBe('Bea moved to ATT — rearrange your team before Sun, Jun 28 · 3:00 PM');
    expect(squadAlertBody([
      { player: 'A', from: 'GK', to: 'DEF' },
      { player: 'B', from: 'DEF', to: 'ATT' },
      { player: 'C', from: 'ATT', to: 'DEF' },
    ], 'x')).toBe('A moved to DEF, B moved to ATT and C moved to DEF — rearrange your team before x');
  });
});

describe('open window: relabel + alert + push', () => {
  it('re-labels every holder, alerts the illegal formations, pushes, grants the free swap', async () => {
    const db = world3();
    const pusher = new FakePusher();
    expect(await movePlayer(db, 'Bea', 'ATT', OPEN_NOW, pusher)).toBe('applied');

    const f = db.data.Fantasy.Futsal['15'];
    // Holders boost + churn re-labelled; alpha (not a holder) untouched.
    expect(pickOf(f.Squads.boost, 'Bea')['position']).toBe('ATT');
    expect(pickOf(f.Squads.churn, 'Bea')['position']).toBe('ATT');
    expect(f.Squads.alpha).toEqual(world2().Fantasy.Futsal['15'].Squads.alpha);

    // Both now field 1 DEF + 3 ATT starters: illegal -> alert for GW2.
    for (const uid of ['boost', 'churn']) {
      expect(await db.read(`${F_ROOT}/SquadAlerts/${uid}`)).toEqual({
        Gw: 2,
        Changes: [{ player: 'Bea', from: 'DEF', to: 'ATT' }],
        CreatedAt: OPEN_NOW.getTime(),
      });
      expect(await db.read(`${F_ROOT}/TransferState/${uid}`)).toEqual({
        Free: 2, UsedThisGw: 0, FreeSwaps: ['Bea'], FreeSwapsGw: 2,
      });
    }
    expect(await db.read(`${F_ROOT}/SquadAlerts/alpha`)).toBeNull();

    // One batch, one push per alerted manager, fantasy payload.
    expect(pusher.sends).toHaveLength(1);
    expect(pusher.sends[0].map((m) => m.uid).sort()).toEqual(['boost', 'churn']);
    expect(pusher.sends[0][0]).toMatchObject({
      title: 'Fantasy squad alert',
      body: 'Bea moved to ATT — rearrange your team before Sun, Jun 28 · 3:00 PM',
      data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '2' },
    });
  });

  it('a relabel that leaves the formation legal raises no alert (and clears a standing one)', async () => {
    const db = world3();
    await movePlayer(db, 'Bea', 'ATT', OPEN_NOW); // churn + boost alerted
    const pusher = new FakePusher();
    // Ezra ATT -> DEF: churn (Ezra an ATT starter beside Bea-now-ATT) is
    // back to 2 DEF + 2 ATT -> legal: its alert clears, no push. boost
    // (Ezra on the bench) merges a second change; alpha (Ezra a starter)
    // is newly illegal (3 DEF + 1 ATT).
    await movePlayer(db, 'Ezra', 'DEF', OPEN_NOW, pusher);
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`)).toBeNull();
    expect((await db.read(`${F_ROOT}/SquadAlerts/boost`) as Json)['Changes']).toEqual([
      { player: 'Bea', from: 'DEF', to: 'ATT' },
      { player: 'Ezra', from: 'ATT', to: 'DEF' },
    ]);
    expect((await db.read(`${F_ROOT}/SquadAlerts/alpha`) as Json)['Changes'])
      .toEqual([{ player: 'Ezra', from: 'ATT', to: 'DEF' }]);
    expect(pusher.sends[0].map((m) => m.uid).sort()).toEqual(['alpha', 'boost']);
    expect(await db.read(`${F_ROOT}/TransferState/boost/FreeSwaps`)).toEqual(['Bea', 'Ezra']);
  });

  it('pre-season (no GwState yet): applies now, alert for the first gameweek', async () => {
    const db = world3();
    delete db.data.Fantasy.Futsal['15'].GwState;
    const pusher = new FakePusher();
    await movePlayer(db, 'Bea', 'ATT', new Date(Date.UTC(2026, 5, 15)), pusher);
    expect((await db.read(`${F_ROOT}/SquadAlerts/churn`) as Json)['Gw']).toBe(1);
    expect(pusher.sends[0][0].body)
      .toBe('Bea moved to ATT — rearrange your team before Sun, Jun 21 · 3:00 PM');
  });

  it('ignores creations/deletions/no-ops; a frozen machine stands down', async () => {
    const db = world3();
    const call = (before: unknown, after: unknown) => handlePositionWrite(db, {
      sport: 'Futsal', season: '15', name: 'Bea', before, after, nowUtc: OPEN_NOW,
    });
    expect(await call(null, 'DEF')).toBe('ignored');
    expect(await call('DEF', null)).toBe('ignored');
    expect(await call('DEF', 'DEF')).toBe('ignored');
    expect(await call('DEF', 'MID')).toBe('ignored');
    db.data.Fantasy.Futsal['15'].Config.lockOverride = 'open';
    expect(await call('DEF', 'ATT')).toBe('frozen');
    expect(db.writes).toEqual([]);
  });
});

describe('locked window: deferred, applied at the reopen', () => {
  it('records the change, leaves squads alone, and the reopen sweep applies it', async () => {
    const db = world3({ gw2Status: 1 });
    await runLifecycleSweep(db, AFTER_LOCK2); // GW2 locked (games live)
    const lockedSquads = clone(db.data.Fantasy.Futsal['15'].Squads);

    expect(await movePlayer(db, 'Bea', 'ATT', AFTER_LOCK2)).toBe('deferred');
    expect(await movePlayer(db, 'Ezra', 'DEF', AFTER_LOCK2)).toBe('deferred');
    expect(await db.read(`${F_ROOT}/PendingPositionChanges`)).toEqual({
      Bea: { from: 'DEF', to: 'ATT' },
      Ezra: { from: 'ATT', to: 'DEF' },
    });
    expect(db.data.Fantasy.Futsal['15'].Squads).toEqual(lockedSquads);
    expect(await db.read(`${F_ROOT}/SquadAlerts`)).toBeNull();

    // GW2 settles at its locked positions (Bea as DEF = 15).
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await runLifecycleSweep(db, new Date(AFTER_LOCK2.getTime() + 3 * 3_600_000));
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2/Bea`)).toBe(15);
    expect(await db.read(`${F_ROOT}/PendingPositionChanges/Bea`)).not.toBeNull();

    // GW3 opens: the sweep applies both changes in one go.
    const pusher = new FakePusher();
    await runLifecycleSweep(db, GW3_OPEN, undefined, { pusher });
    expect(await absent(db, `${F_ROOT}/PendingPositionChanges`)).toBe(true);
    const f = db.data.Fantasy.Futsal['15'];
    expect(pickOf(f.Squads.churn, 'Bea')['position']).toBe('ATT');
    expect(pickOf(f.Squads.churn, 'Ezra')['position']).toBe('DEF');
    // churn held both: 2 DEF + 2 ATT again -> legal, no alert.
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`)).toBeNull();
    // boost and alpha are illegal -> alerted for GW3 with GW3's deadline.
    expect((await db.read(`${F_ROOT}/SquadAlerts/boost`) as Json)['Gw']).toBe(3);
    expect(await db.read(`${F_ROOT}/TransferState/alpha/FreeSwapsGw`)).toBe(3);
    const bodies = pusher.sends.flat().filter((m) => m.title === 'Fantasy squad alert');
    expect(bodies.map((m) => m.uid).sort()).toEqual(['alpha', 'boost']);
    expect(bodies.find((m) => m.uid === 'boost')!.body).toBe(
      'Bea moved to ATT and Ezra moved to DEF — rearrange your team before Sun, Jul 5 · 3:00 PM');
  });

  it('a change made and undone while locked leaves nothing pending', async () => {
    const db = world3({ gw2Status: 1 });
    await runLifecycleSweep(db, AFTER_LOCK2);
    await movePlayer(db, 'Bea', 'ATT', AFTER_LOCK2);
    await movePlayer(db, 'Bea', 'GK', AFTER_LOCK2); // second change keeps from
    expect(await db.read(`${F_ROOT}/PendingPositionChanges/Bea`))
      .toEqual({ from: 'DEF', to: 'GK' });
    await movePlayer(db, 'Bea', 'DEF', AFTER_LOCK2); // back where holders are
    expect(await absent(db, `${F_ROOT}/PendingPositionChanges`)).toBe(true);
  });
});

describe('free swap + alert clearing on saves', () => {
  it('swapping the alerted player out is free and clears the alert; other transfers still count', async () => {
    const db = world3();
    await movePlayer(db, 'Bea', 'ATT', OPEN_NOW);
    const churn = db.data.Fantasy.Futsal['15'].Squads.churn;

    // An armband-only save keeps the illegal formation: alert stays.
    churn.viceId = 'Bo';
    await save(db, 'churn');
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`)).not.toBeNull();

    // Bea (alerted) out, Will (DEF) in: legal again, and free.
    const idx = (churn.picks as Json[]).findIndex((p) => p['playerId'] === 'Bea');
    churn.picks[idx] = { playerId: 'Will', position: 'DEF', priceTenths: 60, bench: false };
    await save(db, 'churn');
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`)).toBeNull();
    expect(await db.read(`${F_ROOT}/TransferState/churn/UsedThisGw`)).toBe(0);

    // A second, ordinary transfer (Ben -> Alex) is counted as usual.
    const ben = (churn.picks as Json[]).findIndex((p) => p['playerId'] === 'Ben');
    churn.picks[ben] = { playerId: 'Alex', position: 'ATT', priceTenths: 95, bench: false };
    churn.captainId = 'Alex';
    await save(db, 'churn');
    expect(await db.read(`${F_ROOT}/TransferState/churn/UsedThisGw`)).toBe(1);
  });

  it('a stale-label save (old app / dirty draft) is re-labelled and cannot dodge the alert', async () => {
    const db = world3();
    await movePlayer(db, 'Bea', 'ATT', OPEN_NOW);
    // The client writes the squad back with Bea still labelled DEF.
    db.data.Fantasy.Futsal['15'].Squads.churn = clone(world2().Fantasy.Futsal['15'].Squads.churn);
    await save(db, 'churn');
    expect(pickOf(db.data.Fantasy.Futsal['15'].Squads.churn, 'Bea')['position']).toBe('ATT');
    expect(await db.read(`${F_ROOT}/SquadAlerts/churn`)).not.toBeNull();
  });

  it('free swaps expire at their gameweek\'s rollover', async () => {
    const db = world3();
    await movePlayer(db, 'Bea', 'ATT', OPEN_NOW);
    expect(await db.read(`${F_ROOT}/TransferState/churn/FreeSwapsGw`)).toBe(2);
    await runLifecycleSweep(db, AFTER_LOCK2); // GW2 lock + finalize + rollover
    expect(await db.read(`${F_ROOT}/TransferState/churn/FreeSwaps`)).toBeNull();
    expect(await db.read(`${F_ROOT}/TransferState/churn/RolledGw`)).toBe(2);
  });
});
