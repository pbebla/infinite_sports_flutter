// Owner void-a-week (spec §15, Voided/<gw> = true) over the in-memory
// FantasyDb: the zero settle + markers, cost waiver + normal rollover, the
// suppressed recap/news guards, the toggle re-settle in both directions
// (resettleVoidToggle = the Voided/<gw> trigger's entry), the chip refund at
// the next lock, the Monday skip, the admin Dream Team guard, and the held
// Dream Team auto-publish. World: test_support.ts world2 (GW1 settled, GW2
// under test; GW2 locks Sun Jun 28 22:00Z).
//
// HAND MATH (fixture _notes; never copied from pipeline output):
// - GW1 stored nets: alpha 350, boost 440, churn 595 -> 35 / 44 / 59.
// - GW2 normal: alpha 350 (35); boost 455 (45 — its benchBoost replays
//   GW1's inside set 1, so the lock voids it: Eva bench-half -15 instead of
//   full -30 -> 440 + 30 - 15); churn 595 - 4 pts * 10 = 555 (55) — used 3
//   vs free 2 at -4 per extra transfer, frozen at lock.
// - Overall after a NORMAL GW2: alpha 70, boost 89, churn 114 (ranks
//   3/2/1, same as before GW2 -> movement 0).
// - Overall after a VOIDED GW2: GW1 only — alpha 35, boost 44, churn 59
//   (ranks 3/2/1, movement 0).
// - Week points (both weeks, same golden games): Bea 15, Bo 12, ...;
//   PlayerTotals with GW1 seeded: normal = 2x (Bea 30, Bo 24), voided GW2
//   = GW1 only (Bea 15, Bo 12). GW2 ownership: Bea held by boost + churn =
//   round(200/3) = 67, Bo by churn only = round(100/3) = 33.
// - Round 3 PlayerTotals (voidWorld seeds GW1's PlayerWeekStats: everyone but
//   Ezra played 1 game): form (tenths) = round(10 x mean Pts of the 3 latest
//   NON-voided weeks) and ppg = round(10 x points / games). Normal GW2:
//   Bea weeks 15, 15 -> form 150; points 30 / games 2 -> ppg 150. Voided
//   GW2: only GW1 counts -> Bea form 150, ppg round(10*15/1) = 150, games 1;
//   Bo 120 / 120 / 1.
// - Rollover after GW2 (normal OR voided): churn free 2 - used 3 clamps to
//   0, + 2 = 2; alpha/boost (no state: free 2, used 0) bank to 4.

import { describe, expect, it } from 'vitest';
import { FetchLike } from '../support';
import { Json } from './golden_fixture';
import {
  resettleVoidToggle, runLifecycleSweep, runMondayReprice,
} from './orchestration';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, FakePusher, GW2_DATE, world2,
} from './test_support';

const WEEK_POINTS: Record<string, number> = {
  Sam: 9, Dana: 13, Alex: 12, Wes: 1, Will: -4, Wren: 3,
  Eli: 0, Eva: -3, Ezra: 0, Bo: 12, Bea: 15, Ben: 9,
};

const GOLDEN_DREAM_PLAYERS = [
  { name: 'Bo', position: 'GK', points: 12 },
  { name: 'Bea', position: 'DEF', points: 15 },
  { name: 'Dana', position: 'DEF', points: 13 },
  { name: 'Alex', position: 'ATT', points: 12 },
  { name: 'Ben', position: 'ATT', points: 9 },
];

const LATER = new Date(AFTER_LOCK2.getTime() + 3_600_000);
const toggle = (db: FakeDb, gw: number, deps?: Json) =>
  resettleVoidToggle(db, {
    sport: 'Futsal', season: '15', gw, nowUtc: LATER, deps,
  });

/** world2 + GW1's PlayerWeeks (so PlayerTotals has an earlier week to
 *  keep) + churn's over-budget transfers (3 used vs 2 free). */
function voidWorld(opts: { gw2Status?: number } = {}): FakeDb {
  const db = new FakeDb(world2(opts));
  const f = db.data.Fantasy.Futsal['15'];
  f.PlayerWeeks = { 1: { ...WEEK_POINTS } };
  f.PlayerWeekStats = {
    1: Object.fromEntries(Object.entries(WEEK_POINTS).map(([n, pts]) => [n, {
      Pts: pts, Played: n !== 'Ezra', GP: n === 'Ezra' ? 0 : 1,
      Games: [{ Vs: 'X', For: 1, Against: 0 }],
    }])),
  };
  f.TransferState = { churn: { Free: 2, UsedThisGw: 3, SavedGw: 2 } };
  return db;
}

/** A model that would happily draft — counts every call. */
function countingNews(): { calls: () => number; fetchImpl: FetchLike } {
  let calls = 0;
  return {
    calls: () => calls,
    fetchImpl: async () => {
      calls++;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          content: [{ type: 'text', text: '[{"title":"T","body":"B"}]' }],
        }),
      };
    },
  };
}

const NORMAL_OVERALL = {
  alpha: { points: 70, rank: 3, movement: 0 },
  boost: { points: 89, rank: 2, movement: 0 },
  churn: { points: 114, rank: 1, movement: 0 },
};
const VOIDED_OVERALL = {
  alpha: { points: 35, rank: 3, movement: 0 },
  boost: { points: 44, rank: 2, movement: 0 },
  churn: { points: 59, rank: 1, movement: 0 },
};
const ZERO_WEEK = {
  alpha: { points: 0, rank: 1 },
  boost: { points: 0, rank: 1 },
  churn: { points: 0, rank: 1 },
};
const NORMAL_WEEK2 = {
  alpha: { points: 35, rank: 3 },
  boost: { points: 45, rank: 2 },
  churn: { points: 55, rank: 1 },
};
// Rank after each week (voided or not, the places never change here: GW1
// 35/44/59 -> 3/2/1; normal GW2 70/89/114 -> 3/2/1; voided GW2 +0 -> 3/2/1).
const RANK_HISTORY = {
  alpha: { '1': 3, '2': 3 },
  boost: { '1': 2, '2': 2 },
  churn: { '1': 1, '2': 1 },
};

describe('void BEFORE finalize (the week settles voided first time)', () => {
  it('zeros + Voided markers; Overall/PlayerTotals exclude the week; no DreamTeam/recap/news', async () => {
    const db = voidWorld();
    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    const pusher = new FakePusher();
    const news = countingNews();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, {
      pusher, news: { apiKey: 'k', fetchImpl: news.fetchImpl },
    });

    const history = await db.read(`${F_ROOT}/History/2`) as Json;
    for (const uid of ['alpha', 'boost', 'churn']) {
      expect(history[uid]['TotalTenths']).toBe(0);
      expect(history[uid]['Voided']).toBe(true);
    }
    // The squad viewer still reads the locked squad.
    expect(history['alpha']['captainId']).toBe('Ezra');
    expect((history['churn']['picks'] as unknown[]).length).toBe(7);

    expect(await db.read(`${F_ROOT}/Leaderboards/Gameweek/2`)).toEqual(ZERO_WEEK);
    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual(VOIDED_OVERALL);
    expect(await db.read(`${F_ROOT}/Leaderboards/RankHistory`)).toEqual(RANK_HISTORY);
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2`)).toEqual(WEEK_POINTS); // real
    const totals = await db.read(`${F_ROOT}/PlayerTotals`) as Json;
    expect(totals['Bea']).toEqual(
      { points: 15, ownershipPct: 67, form: 150, ppg: 150, games: 1 });
    expect(totals['Bo']).toEqual(
      { points: 12, ownershipPct: 33, form: 120, ppg: 120, games: 1 });

    expect(await db.read(`${F_ROOT}/DreamTeam/2`)).toBeNull();
    expect(pusher.sends).toEqual([]);
    expect(news.calls()).toBe(0);
    expect(await db.read(`${F_ROOT}/News`)).toBeNull(); // not even the dream post
    expect(await db.read(`${F_ROOT}/RecapSent/2`))
      .toEqual({ At: AFTER_LOCK2.getTime(), Voided: true });
    expect(await db.read(`${F_ROOT}/NewsDrafted/2`))
      .toEqual({ At: AFTER_LOCK2.getTime(), Voided: true });
    expect((await db.read(`${F_ROOT}/GwState`) as Json)['status']).toBe('finalized');

    // Resweep: byte-identical (guards read-before-claim, nothing re-sent).
    const before = db.snapshot();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, { pusher });
    expect(db.snapshot()).toBe(before);
  });

  it('waives the frozen transfer cost but rolls transfers over normally', async () => {
    const db = voidWorld();
    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    await runLifecycleSweep(db, AFTER_LOCK2);

    // The lock still froze churn's 4-point charge (an un-void recharges it)...
    expect(await db.read(`${F_ROOT}/TransferCosts/2`)).toEqual({ churn: 4 });
    // ...but the voided week nets 0, not -40.
    expect((await db.read(`${F_ROOT}/History/2/churn`) as Json)['TotalTenths'])
      .toBe(0);
    // Rollover exactly as an unvoided week: neither punished nor rewarded.
    expect(await db.read(`${F_ROOT}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2, RolledGw: 2,
    });
    expect(await db.read(`${F_ROOT}/TransferState/alpha`)).toEqual({
      Free: 4, UsedThisGw: 0, RolledGw: 2,
    });
  });

  it('un-void re-settles normal scores but sends NO late recap or news', async () => {
    const db = voidWorld();
    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    const pusher = new FakePusher();
    const news = countingNews();
    const deps = { pusher, news: { apiKey: 'k', fetchImpl: news.fetchImpl } };
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, deps);

    await db.write(`${F_ROOT}/Voided/2`, null); // the Manager's un-void
    await toggle(db, 2, deps);

    const history = await db.read(`${F_ROOT}/History/2`) as Json;
    expect(history['churn']['TotalTenths']).toBe(555); // frozen cost recharged
    expect(history['boost']['TotalTenths']).toBe(455);
    expect('Voided' in history['alpha']).toBe(false);
    expect(await db.read(`${F_ROOT}/Leaderboards/Gameweek/2`)).toEqual(NORMAL_WEEK2);
    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual(NORMAL_OVERALL);
    expect(await db.read(`${F_ROOT}/Leaderboards/RankHistory`)).toEqual(RANK_HISTORY);
    expect(((await db.read(`${F_ROOT}/DreamTeam/2`)) as Json)['Players'])
      .toEqual(GOLDEN_DREAM_PLAYERS);
    // Documented choice: the void path's guards hold — no late sends.
    expect(pusher.sends).toEqual([]);
    expect(news.calls()).toBe(0);
    expect(await db.read(`${F_ROOT}/News`)).toBeNull();
    expect(await db.read(`${F_ROOT}/RecapSent/2`))
      .toEqual({ At: AFTER_LOCK2.getTime(), Voided: true });
  });
});

describe('void AFTER finalize (the Voided/<gw> toggle re-settles)', () => {
  it('voiding drops the week from Overall + PlayerTotals; un-voiding restores them', async () => {
    const db = voidWorld();
    const pusher = new FakePusher();
    await runLifecycleSweep(db, AFTER_LOCK2, undefined, { pusher });

    // Normal settle first (sanity against the hand math).
    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual(NORMAL_OVERALL);
    expect(((await db.read(`${F_ROOT}/PlayerTotals`)) as Json)['Bea'])
      .toEqual({ points: 30, ownershipPct: 67, form: 150, ppg: 150, games: 2 });
    expect(pusher.sends).toHaveLength(1); // the GW2 recap
    expect(((await db.read(`${F_ROOT}/DreamTeam/2`)) as Json)['Auto']).toBe(true);

    // Owner voids GW2.
    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    await toggle(db, 2, { pusher });

    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual(VOIDED_OVERALL);
    expect(await db.read(`${F_ROOT}/Leaderboards/Gameweek/2`)).toEqual(ZERO_WEEK);
    const totals = await db.read(`${F_ROOT}/PlayerTotals`) as Json;
    expect(totals['Bea']).toEqual(
      { points: 15, ownershipPct: 67, form: 150, ppg: 150, games: 1 });
    expect(totals['Bo']).toEqual(
      { points: 12, ownershipPct: 33, form: 120, ppg: 120, games: 1 });
    expect(await db.read(`${F_ROOT}/History/2/churn/TotalTenths`)).toBe(0);
    expect(await db.read(`${F_ROOT}/History/2/churn/Voided`)).toBe(true);
    // PlayerWeekStats re-settles with the void: Pts 0, marker, no Lines (the
    // court record stays).
    const voidedDana = await db.read(`${F_ROOT}/PlayerWeekStats/2/Dana`) as Json;
    expect(voidedDana['Pts']).toBe(0);
    expect(voidedDana['Voided']).toBe(true);
    expect(voidedDana['Played']).toBe(true);
    expect(voidedDana['GP']).toBe(1);
    expect('Lines' in voidedDana).toBe(false);
    expect(await db.read(`${F_ROOT}/DreamTeam/2`)).toBeNull(); // ours: removed
    // Already-sent guards are untouched; nothing re-sent; no re-rollover.
    expect(pusher.sends).toHaveLength(1);
    expect(await db.read(`${F_ROOT}/RecapSent/2`))
      .toEqual({ At: AFTER_LOCK2.getTime() });
    expect(await db.read(`${F_ROOT}/TransferState/churn`)).toEqual({
      Free: 2, UsedThisGw: 0, SavedGw: 2, RolledGw: 2,
    });

    // Owner un-voids: back to the normal settle.
    await db.write(`${F_ROOT}/Voided/2`, null);
    await toggle(db, 2, { pusher });

    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual(NORMAL_OVERALL);
    expect(await db.read(`${F_ROOT}/Leaderboards/Gameweek/2`)).toEqual(NORMAL_WEEK2);
    const restored = await db.read(`${F_ROOT}/PlayerTotals`) as Json;
    expect(restored['Bea']).toEqual(
      { points: 30, ownershipPct: 67, form: 150, ppg: 150, games: 2 });
    expect(restored['Bo']).toEqual(
      { points: 24, ownershipPct: 33, form: 120, ppg: 120, games: 2 });
    const churn = await db.read(`${F_ROOT}/History/2/churn`) as Json;
    expect(churn['TotalTenths']).toBe(555);
    expect('Voided' in churn).toBe(false);
    // ... and PlayerWeekStats comes back whole (set, so the marker is gone).
    const backDana = await db.read(`${F_ROOT}/PlayerWeekStats/2/Dana`) as Json;
    expect(backDana['Pts']).toBe(13);
    expect('Voided' in backDana).toBe(false);
    expect(backDana['Lines']).toEqual({
      plays: { N: 1, P: 1 }, goals: { N: 1, P: 6 },
      assists: { N: 1, P: 4 }, bonus: { N: 2, P: 2 },
    });
    expect(await db.read(`${F_ROOT}/DreamTeam/2`)).toEqual({
      Players: GOLDEN_DREAM_PLAYERS, ComputedAt: LATER.getTime(), Auto: true,
    });
    expect(pusher.sends).toHaveLength(1);
  });

  it('an admin-edited DreamTeam survives the void and the un-void', async () => {
    const db = voidWorld();
    await runLifecycleSweep(db, AFTER_LOCK2);
    const adminTeam = { Players: [{ name: 'OwnerPick', position: 'GK', points: 1 }] };
    db.data.Fantasy.Futsal['15'].DreamTeam['2'] = adminTeam; // Auto gone

    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    await toggle(db, 2);
    expect(await db.read(`${F_ROOT}/DreamTeam/2`)).toEqual(adminTeam);

    await db.write(`${F_ROOT}/Voided/2`, null);
    await toggle(db, 2);
    expect(await db.read(`${F_ROOT}/DreamTeam/2`)).toEqual(adminTeam);
  });

  it('frozen machine, unknown gameweek, or an unsettled week: no writes now', async () => {
    const frozen = voidWorld();
    await runLifecycleSweep(frozen, AFTER_LOCK2);
    frozen.data.Fantasy.Futsal['15'].Config.lockOverride = 'locked';
    frozen.data.Fantasy.Futsal['15'].Voided = { 2: true };
    frozen.writes = [];
    await toggle(frozen, 2);
    expect(frozen.writes).toEqual([]);

    const unknown = voidWorld();
    unknown.data.Fantasy.Futsal['15'].Voided = { 9: true };
    await toggle(unknown, 9);
    expect(unknown.writes).toEqual([]);

    // GW2 games still live: nothing to settle yet (its finalize reads the
    // flag whenever it does run).
    const live = voidWorld({ gw2Status: 1 });
    live.data.Fantasy.Futsal['15'].Voided = { 2: true };
    await toggle(live, 2);
    expect(live.writes).toEqual([]);
  });
});

describe('chip refund at the next lock', () => {
  it("a chip played in a voided week can be played again in the same set", async () => {
    // boost played benchBoost in GW1 and again in GW2 (both set 1). Without
    // the void the GW2 replay is stripped at lock
    // (transfers_orchestration.test.ts); with GW1 voided it is refunded.
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: lock only
    db.data.Fantasy.Futsal['15'].Voided = { 1: true };
    await runLifecycleSweep(db, AFTER_LOCK2);

    const published = await db.read(`${F_ROOT}/PublishedPicks/2`) as Json;
    expect(published['boost']['chip']).toBe('benchBoost');
    expect(await db.read(`${F_ROOT}/TransferState/boost`)).toEqual({
      Free: 2, UsedThisGw: 0, ChipPlayed: 'benchBoost',
    });

    // GW2 completes: the honored benchBoost scores boost's golden 440
    // (bench Eva full -30). Overall: GW1 is voided, so its (stale, pre-void)
    // stored nets resum as zero -> 35/44/59, ranks 3/2/1; the standings
    // before GW2 were all-zero ties (rank 1) -> movement alpha -2, boost
    // -1, churn 0.
    for (const g of db.data.Futsal['15'].Date[GW2_DATE]) g.status = 2;
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${F_ROOT}/History/2/boost/TotalTenths`)).toBe(440);
    expect(await db.read(`${F_ROOT}/Leaderboards/Overall`)).toEqual({
      alpha: { points: 35, rank: 3, movement: -2 },
      boost: { points: 44, rank: 2, movement: -1 },
      churn: { points: 59, rank: 1, movement: 0 },
    });
  });
});

describe('Monday repricing skips a voided week', () => {
  it('flags Repriced {At, Voided:true}, moves no price, never re-evaluates', async () => {
    const db = new FakeDb(world2());
    const f = db.data.Fantasy.Futsal['15'];
    f.History[2] = { alpha: { TotalTenths: 0, Voided: true } };
    f.PlayerWeeks = { 2: { ...WEEK_POINTS } }; // would move 9 prices
    f.Voided = { 2: true };
    const NOW = new Date(Date.UTC(2026, 5, 29, 17)); // Monday 10:00 PDT

    await runMondayReprice(db, NOW);
    expect(db.writes).toEqual([`${F_ROOT}/Repriced/2`]);
    expect(await db.read(`${F_ROOT}/Repriced/2`))
      .toEqual({ At: NOW.getTime(), Voided: true });
    expect(await db.read(`${F_ROOT}/PriceChanges`)).toBeNull();
    expect(await db.read(`${F_ROOT}/Players/Bo/priceTenths`)).toBe(75);

    const before = db.snapshot();
    await runMondayReprice(db, new Date(NOW.getTime() + 7 * 86400_000));
    expect(db.snapshot()).toBe(before);
  });
});

describe('News draft auto-publish holds for a voided week', () => {
  it('due drafts of a voided week stay queued; un-void releases them', async () => {
    const db = new FakeDb(world2({ gw2Status: 1 })); // games live: no finalize
    const now = new Date(Date.UTC(2026, 5, 24, 12));
    const f = db.data.Fantasy.Futsal['15'];
    f.News = {
      Drafts: {
        gw1dreamteam: {
          Title: 'Team of the Week — GW1', Body: 'B', Gw: 1, CreatedAt: 1,
          Source: 'dreamteam', AutoPublishAt: now.getTime() - 1,
        },
        // Autopilot schedules AI drafts too: the hold covers every Source.
        gw1ai1: {
          Title: 'AI', Body: 'B', Gw: 1, CreatedAt: 1,
          Source: 'ai', AutoPublishAt: now.getTime() - 1,
        },
      },
    };
    f.Voided = { 1: true };
    await runLifecycleSweep(db, now);
    expect(await db.read(`${F_ROOT}/News/Published`)).toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/gw1dreamteam`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/News/Drafts/gw1ai1`)).not.toBeNull();

    await db.write(`${F_ROOT}/Voided/1`, null);
    await runLifecycleSweep(db, now);
    expect(await db.read(`${F_ROOT}/News/Published/gw1dreamteam`)).toEqual({
      Title: 'Team of the Week — GW1', Body: 'B', At: now.getTime(), Gw: 1,
    });
    expect(await db.read(`${F_ROOT}/News/Drafts/gw1dreamteam`)).toBeNull();
    expect(await db.read(`${F_ROOT}/News/Published/gw1ai1`)).toEqual({
      Title: 'AI', Body: 'B', At: now.getTime(), Gw: 1,
    });
  });
});
