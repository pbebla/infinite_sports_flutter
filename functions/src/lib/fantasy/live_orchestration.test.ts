// The live gameweek's orchestration (live design 2026-11-03 §4) over the
// in-memory FantasyDb, whose transactions run COLD FIRST like a Cloud
// Function's (the first run sees null): refreshLiveWeek (the trigger's
// work), the trigger's zero-cost gate (maybeRefreshLive +
// scoringKeysChanged), the settle tombstone at the end of finalize, the
// older-week rerun and the void toggle refreshing the live week at once,
// the sweep backstop (step 2c), and every stand-down. World: test_support.ts
// world2 (GW1 settled, GW2 under test, locking Sun Jun 28 22:00Z) with
// teams on the market and GW1's PlayerWeeks/PlayerWeekStats, locked by a
// real sweep — PublishedPicks/2 is the cleaned golden squads (boost's
// benchBoost replays set 1, so the lock voids it); nobody pays a hit.
//
// HAND MATH (futsalDefault, fixture _notes; never copied from output):
// - Settled base for GW2: History/1 nets alpha 350 / boost 440 / churn 595
//   -> O 35 / 44 / 59 (ranks churn 1, boost 2, alpha 3). PlayerWeeks/1 =
//   the golden week points; GP 1 each but Ezra.
// - ONE GOAL (game 0 Sharks 1-0 Wolves LIVE, Alex scores at 5'; game 1
//   Eagles-Bulls not started): Sharks keep a clean sheet so far — Sam 1+8 =
//   9, Dana 1+5 = 6, Alex 1+4+2 = 7; Wolves concede 1 — Wes, Will, Wren 1
//   each. BPS: every Shark gets the clean sheet's 5, Alex 12 more = 17 ->
//   bonus Alex 3, Sam and Dana tie on 5 -> 2 each. Week: Alex 10, Sam 11,
//   Dana 8, Wolves 1 each. Eagles and Bulls are PENDING (0 so far, no
//   auto-sub, armbands stay).
//   alpha = Eli 0 + Dana 80 + Eva 0 + Ezra (C, pending) 0 + Alex 100 +
//     bench Will 1 half 5 + Wren 1 half 5 = 190 -> W 19;
//   boost = Sam 110 + Bea (C) 0 + Will 10 + Ben 0 + Wren 10 + bench 0 = 130
//     -> W 13; churn = Dana 80 + bench Wren half 5 = 85 -> W 8.
//   Board: O alpha 54, boost 57, churn 67 -> R 3 / 2 / 1, M 0 each; WR
//   alpha 1, boost 2, churn 3. Alex: Total 12+10 = 22, Games 2, Form
//   round(10 x (10+12)/2) = 110, Ppg 110, Own round(100/3) = 33.
// - GAME 0 FINAL (the golden Sharks-Wolves), game 1 not started: Dana 13,
//   Alex 12, Will -4, Wren 3. alpha = Dana 130 + Ezra (C, pending) 0 x2 +
//   Alex 120 (no armband: the captain is pending, not absent) + bench Will
//   -20 + Wren 15 (half, NOT auto-subbed: Ezra may still play) = 245.

import { describe, expect, it } from 'vitest';
import { clone, Json } from './golden_fixture';
import {
  LIVE_SETTLE_HEAL_MS, maybeFinalizeGame, maybeRefreshLive, refreshLiveWeek,
  resettleVoidToggle, runLifecycleSweep,
} from './orchestration';
import { FantasyTxResult } from './orchestration_db';
import { liveWriteMatters, scoringKeysChanged, SCORING_KEYS } from './live_core';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, fixture, GW2_DATE, LOCK2_MS, world2,
} from './test_support';

const SPORT = 'Futsal';
const SEASON = '15';
const LEAGUE = `${SPORT}/${SEASON}`;
const MIN = 60_000;
const HOUR = 60 * MIN;

const WEEK_POINTS: Record<string, number> = {
  Sam: 9, Dana: 13, Alex: 12, Wes: 1, Will: -4, Wren: 3,
  Eli: 0, Eva: -3, Ezra: 0, Bo: 12, Bea: 15, Ben: 9,
};

/** Every node only finalize (or the lock / the save trigger) may write —
 *  a live run must leave each one untouched. */
const OFFICIAL = [
  'History', 'Leaderboards', 'PlayerTotals', 'PlayerWeeks', 'PlayerWeekStats',
  'DreamTeam', 'TransferState', 'TransferCosts', 'PublishedPicks', 'Baselines',
  'SquadAlerts',
];

/** The heavy reads a coalesced / settled run must never reach. */
const HEAVY = [
  `${LEAGUE}/Line Ups`, `${F_ROOT}/Players`, `${F_ROOT}/PublishedPicks/2`,
  `${F_ROOT}/TransferCosts/2`, `${F_ROOT}/Voided`, `${F_ROOT}/LiveBase/2`,
  `${F_ROOT}/History`, `${F_ROOT}/PlayerWeeks`, `${F_ROOT}/PlayerWeekStats`,
];

/** FakeDb (cold-first transactions) that records every read, and can run
 *  [beforeLiveTx] once just before the next transaction on Live — another
 *  run landing between this run's reads and its write. */
class LiveDb extends FakeDb {
  reads: string[] = [];
  beforeLiveTx: (() => Promise<void>) | undefined;

  async read(path: string): Promise<unknown> {
    this.reads.push(path);
    return super.read(path);
  }

  async transaction(
    path: string, update: (current: unknown) => unknown,
  ): Promise<FantasyTxResult> {
    if (path === `${F_ROOT}/Live` && this.beforeLiveTx) {
      const hook = this.beforeLiveTx;
      this.beforeLiveTx = undefined;
      await hook();
    }
    return super.transaction(path, update);
  }

  reset(): void {
    this.reads = [];
    this.writes = [];
  }

  get f(): Json {
    return this.data.Fantasy.Futsal['15'];
  }

  get date2(): Json[] {
    return this.data.Futsal['15'].Date[GW2_DATE];
  }
}

const golden = (i: number): Json => clone(fixture['games'][i]['node']);

/** Game 0 (Sharks-Wolves) live at 1-0: one Alex goal so far. */
function oneGoal(): Json {
  return {
    team1: 'Sharks', team2: 'Wolves', team1score: 1, team2score: 0, status: 1,
    team1activity: { "5'": [{ Goal: 'Alex' }] },
  };
}

function notStarted(i: number): Json {
  return { ...golden(i), status: 0 };
}

/** world2 with teams on the market, GW1's player records, GW2's games not
 *  started, locked by a real sweep (PublishedPicks/2, LockedPositions/2,
 *  GwState locked). */
async function lockedWorld(): Promise<LiveDb> {
  const db = new LiveDb(world2({ gw2Status: 0 }));
  const f = db.f;
  for (const p of fixture['players'] as Json[]) {
    f.Players[p['id']].teamName = p['team'];
  }
  f.PlayerWeeks = { 1: { ...WEEK_POINTS } };
  f.PlayerWeekStats = {
    1: Object.fromEntries(Object.entries(WEEK_POINTS).map(([n, pts]) => [n, {
      Pts: pts, Played: n !== 'Ezra', GP: n === 'Ezra' ? 0 : 1,
    }])),
  };
  await runLifecycleSweep(db, AFTER_LOCK2);
  expect(f.GwState.status).toBe('locked');
  expect(Object.keys(f.PublishedPicks[2]).sort()).toEqual(['alpha', 'boost', 'churn']);
  db.reset();
  return db;
}

const LIVE_AT = AFTER_LOCK2.getTime() + 30 * MIN;
const NOW = new Date(LIVE_AT);
const clockAt = (ms: number) => () => ms;

function refresh(db: LiveDb, eventAtMs: number, readAtMs: number, now = NOW) {
  return refreshLiveWeek(db, {
    sport: SPORT, season: SEASON, dateKey: GW2_DATE, eventAtMs,
    nowUtc: now, clock: clockAt(readAtMs),
  });
}

/** Writes game [i] of GW2 and runs the live trigger's entry for it. */
async function liveWrite(
  db: LiveDb, i: number, after: Json | null, eventAtMs: number, readAtMs: number,
) {
  const before = clone(db.date2[i] ?? null);
  if (after === null) delete db.date2[i]; else db.date2[i] = clone(after);
  return maybeRefreshLive(db, {
    sport: SPORT, season: SEASON, dateKey: GW2_DATE, before, after,
    eventAtMs, nowUtc: NOW, clock: clockAt(readAtMs),
  });
}

function officialSnapshot(db: LiveDb): string {
  return JSON.stringify(OFFICIAL.map((n) => [n, db.f[n] ?? null]));
}

describe('refreshLiveWeek: a game event publishes the live week', () => {
  it('1. a goal at status 1: the scorer\'s points, his owner\'s week points, the board', async () => {
    const db = await lockedWorld();
    expect(await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000))
      .toBe('written');
    const live = db.f.Live;
    expect(live.Meta).toStrictEqual({
      Gw: 2, State: 'live', ReadAt: LIVE_AT - 1000, UpdatedAt: LIVE_AT,
      Games: {
        0: { S: 1, T1: 'Sharks', T2: 'Wolves' },
        1: { S: 0, T1: 'Eagles', T2: 'Bulls' },
      },
    });
    expect(live.Players['Alex']).toMatchObject({
      Pts: 10, St: 'live', BonusProv: true, Total: 22, Games: 2, Form: 110,
      Ppg: 110, Own: 33,
    });
    expect(live.Players['Ezra']).toMatchObject({ Pts: 0, St: 'pending' });
    expect(live.Squads['alpha'].T).toBe(190);
    expect(live.Board).toStrictEqual({
      alpha: { O: 54, R: 3, M: 0, W: 19, WR: 1 },
      boost: { O: 57, R: 2, M: 0, W: 13, WR: 2 },
      churn: { O: 67, R: 1, M: 0, W: 8, WR: 3 },
    });
  });

  it('2a. coalescing: an event older than the stored read stands down before any heavy read', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    const stored = JSON.stringify(db.f.Live);
    db.reset();
    // A late duplicate of an event the stored run already read past.
    expect(await refresh(db, LIVE_AT - 1500, LIVE_AT)).toBe('stale');
    expect(JSON.stringify(db.f.Live)).toBe(stored);
    expect(db.writes).toEqual([]);
    expect(db.reads.filter((p) => HEAVY.includes(p))).toEqual([]);
  });

  it('2b. a run that read older games and lands after a newer run is refused (Review Focus 2)', async () => {
    const db = await lockedWorld();
    db.date2[0] = oneGoal();
    // Run A reads the one-goal game at t=5000. Before its write lands, Alex
    // scores again and run B (read at t=6000) publishes the two-goal game.
    db.beforeLiveTx = async () => {
      const g = oneGoal();
      g['team1score'] = 2;
      (g['team1activity'] as Json)["9'"] = [{ Goal: 'Alex' }];
      db.date2[0] = g;
      expect(await refresh(db, 5500, 6000)).toBe('written');
    };
    expect(await refresh(db, 4000, 5000)).toBe('stale');
    // B's numbers stay on top: Alex 1+8+2 = 11 + bonus 3 = 14.
    expect(db.f.Live.Meta.ReadAt).toBe(6000);
    expect(db.f.Live.Players['Alex'].Pts).toBe(14);
  });

  it('2c. the week settles between a run\'s reads and its write: refused, the tombstone stays (Review Focus 3)', async () => {
    const db = await lockedWorld();
    db.date2[0] = oneGoal();
    const tombstone = { Meta: { Gw: 2, State: 'settled', UpdatedAt: 1 } };
    db.beforeLiveTx = async () => { db.f.Live = clone(tombstone); };
    expect(await refresh(db, LIVE_AT - 2000, LIVE_AT - 1000)).toBe('settled');
    expect(db.f.Live).toStrictEqual(tombstone);
  });

  it('2d. a newer week takes Live between a run\'s reads and its write: refused, the newer week stays', async () => {
    const db = await lockedWorld();
    db.date2[0] = oneGoal();
    const newer = { Meta: { Gw: 3, State: 'live', ReadAt: 1, UpdatedAt: 1, Games: {} } };
    db.beforeLiveTx = async () => { db.f.Live = clone(newer); };
    expect(await refresh(db, LIVE_AT - 2000, LIVE_AT - 1000)).toBe('stale');
    expect(db.f.Live).toStrictEqual(newer);
    // And with the newer week already there, a run stops before any heavy read.
    db.reset();
    expect(await refresh(db, LIVE_AT, LIVE_AT + 100)).toBe('stale');
    expect(db.reads.filter((p) => HEAVY.includes(p))).toEqual([]);
  });

  it('a newer read of the same week wins; an older settled week is simply replaced', async () => {
    const db = await lockedWorld();
    db.date2[0] = oneGoal();
    db.f.Live = { Meta: { Gw: 1, State: 'settled', UpdatedAt: 1 } };
    expect(await refresh(db, LIVE_AT - 2000, LIVE_AT - 1000)).toBe('written');
    expect(db.f.Live.Meta).toMatchObject({ Gw: 2, State: 'live' });
    // Equal ReadAt is not "after": the write lands.
    expect(await refresh(db, LIVE_AT - 999, LIVE_AT - 1000)).toBe('written');
  });

  it('5. game 0 Final, game 1 not started: its players pending, no auto-sub, the armband stays (Review Focus 1)', async () => {
    const db = await lockedWorld();
    expect(await liveWrite(db, 0, golden(0), LIVE_AT - 2000, LIVE_AT - 1000))
      .toBe('written');
    const live = db.f.Live;
    for (const name of ['Eli', 'Eva', 'Ezra', 'Bo', 'Bea', 'Ben']) {
      expect(live.Players[name].St, name).toBe('pending');
      expect(live.Players[name].Pts, name).toBe(0);
    }
    expect(live.Players['Alex'].St).toBe('done');
    expect(live.Squads['alpha']).toStrictEqual({
      T: 245,
      W: 24,
      Slots: [
        { p: 'Eli', c: 0, x: 1 },
        { p: 'Dana', c: 130, x: 1 },
        { p: 'Eva', c: 0, x: 1 },
        { p: 'Ezra', c: 0, x: 2 },
        { p: 'Alex', c: 120, x: 1 },
        { p: 'Will', c: -20, x: 1 },
        { p: 'Wren', c: 15, x: 1 },
      ],
    });
  });

  it('no started game: skipped, nothing written', async () => {
    const db = await lockedWorld();
    expect(await refresh(db, LIVE_AT - 2000, LIVE_AT - 1000)).toBe('skipped');
    expect(db.writes).toEqual([]);
    expect(db.f.Live).toBeUndefined();
  });

  it('9. LiveBase is built once from the settled weeks, then reused', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    const settledReads = (d: LiveDb) => d.reads.filter((p) =>
      [`${F_ROOT}/History`, `${F_ROOT}/PlayerWeeks`, `${F_ROOT}/PlayerWeekStats`]
        .includes(p));
    expect(settledReads(db).sort()).toEqual([
      `${F_ROOT}/History`, `${F_ROOT}/PlayerWeekStats`, `${F_ROOT}/PlayerWeeks`,
    ]);
    expect(db.writes).toContain(`${F_ROOT}/LiveBase/2`);
    expect(db.f.LiveBase[2]).toStrictEqual({
      Gw: 2,
      Managers: { alpha: { O: 35 }, boost: { O: 44 }, churn: { O: 59 } },
      Players: Object.fromEntries(Object.entries(WEEK_POINTS).map(([n, p]) =>
        [n, { P: p, G: n === 'Ezra' ? 0 : 1 }])),
      FormWeeks: { 1: WEEK_POINTS },
    });
    db.reset();
    const g = oneGoal();
    g['team2activity'] = { "8'": [{ Yellow: 'Will' }] };
    expect(await liveWrite(db, 0, g, LIVE_AT + 1000, LIVE_AT + 2000)).toBe('written');
    expect(settledReads(db)).toEqual([]);
    expect(db.reads).toContain(`${F_ROOT}/LiveBase/2`);
    expect(db.writes).toEqual([`${F_ROOT}/Live`]);
    // Will's yellow: 1 - 1 = 0 this week.
    expect(db.f.Live.Players['Will'].Pts).toBe(0);
  });

  it('7. a live run never writes an official node', async () => {
    const db = await lockedWorld();
    const before = officialSnapshot(db);
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    await liveWrite(db, 0, golden(0), LIVE_AT + 1000, LIVE_AT + 2000);
    await liveWrite(db, 1, { ...golden(1), status: 1 }, LIVE_AT + 3000, LIVE_AT + 4000);
    expect(officialSnapshot(db)).toBe(before);
    expect(db.writes.length).toBeGreaterThan(0);
    for (const p of db.writes) {
      expect(p === `${F_ROOT}/Live` || p === `${F_ROOT}/LiveBase/2`, p).toBe(true);
    }
  });
});

describe('the settle hand-over: a Meta-only tombstone (Fable L1)', () => {
  /** Plays GW2 out: game 0 Final, game 1 live, then Final; the live
   *  trigger runs first, then the finalize trigger. */
  async function playedOut(db: LiveDb): Promise<Json> {
    await liveWrite(db, 0, golden(0), LIVE_AT, LIVE_AT + 100);
    await liveWrite(db, 1, { ...golden(1), status: 1 }, LIVE_AT + 1000, LIVE_AT + 1100);
    expect(await liveWrite(db, 1, golden(1), LIVE_AT + 2000, LIVE_AT + 2100))
      .toBe('written');
    const atFullTime = clone(db.f.Live);
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + HOUR),
      deps: { clock: clockAt(LIVE_AT + HOUR + 100) },
    });
    return atFullTime;
  }

  it('3. the last game Final: finalize settles Live to the tombstone, the numbers matched', async () => {
    const db = await lockedWorld();
    const atFullTime = await playedOut(db);
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + HOUR },
    });
    expect(db.f.LiveBase).toBeUndefined();
    // The hand-over never jumps: live at full time == the official boards.
    const overall = db.f.Leaderboards.Overall;
    const week = db.f.Leaderboards.Gameweek[2];
    for (const uid of ['alpha', 'boost', 'churn']) {
      expect(atFullTime.Board[uid].O, uid).toBe(overall[uid].points);
      expect(atFullTime.Board[uid].R, uid).toBe(overall[uid].rank);
      expect(atFullTime.Board[uid].W, uid).toBe(week[uid].points);
      expect(atFullTime.Squads[uid].T, uid).toBe(db.f.History[2][uid].TotalTenths);
    }
    for (const [name, t] of Object.entries(db.f.PlayerTotals as Json)) {
      expect(atFullTime.Players[name].Total, name).toBe(t['points']);
      expect(atFullTime.Players[name].Form, name).toBe(t['form']);
    }
  });

  it('3. the tombstone comes after every official write of the finalize run', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, golden(0), LIVE_AT, LIVE_AT + 100);
    await liveWrite(db, 1, golden(1), LIVE_AT + 1000, LIVE_AT + 1100);
    db.reset();
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + HOUR),
    });
    const w = db.writes.map((p) => p.slice(F_ROOT.length + 1));
    const lastLive = w.lastIndexOf('Live');
    expect(lastLive).toBeGreaterThan(-1);
    for (const official of [
      /^PlayerWeeks\/2$/, /^PlayerWeekStats\/2$/, /^History\/2$/,
      /^Leaderboards\/Gameweek\/2$/, /^Leaderboards\/Overall$/,
      /^Leaderboards\/RankHistory$/, /^PlayerTotals$/, /^DreamTeam\/2$/,
      /^TransferState\/.+$/,
    ]) {
      const at = w.map((p, i) => (official.test(p) ? i : -1)).filter((i) => i >= 0);
      expect(at.length, String(official)).toBeGreaterThan(0);
      expect(Math.max(...at), String(official)).toBeLessThan(lastLive);
    }
  });

  it('3. a late event or a score correction after settle never brings the week back (Review Focus 3)', async () => {
    const db = await lockedWorld();
    await playedOut(db);
    const tombstone = clone(db.f.Live);

    // A late live run: PlayerWeeks/2 exists -> settled before any heavy read.
    db.reset();
    expect(await refresh(db, LIVE_AT + 2 * HOUR, LIVE_AT + 2 * HOUR + 100)).toBe('settled');
    expect(db.reads.filter((p) => HEAVY.includes(p))).toEqual([]);
    expect(db.writes).toEqual([]);
    expect(db.f.Live).toStrictEqual(tombstone);

    // A score correction: the live trigger fires (settled), finalize reruns.
    const corrected = golden(1);
    corrected['team2score'] = 3;
    (corrected['team2activity'] as Json)["45'"] = [{ Goal: 'Ben' }];
    expect(await liveWrite(db, 1, corrected, LIVE_AT + 3 * HOUR, LIVE_AT + 3 * HOUR + 100))
      .toBe('settled');
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + 3 * HOUR),
    });
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + 3 * HOUR },
    });

    // Live deleted after settle: another correction never recreates live
    // numbers — the live run writes nothing; finalize's rerun writes only
    // the tombstone again.
    db.f.Live = undefined;
    delete db.f.Live;
    db.reset();
    const again = clone(corrected);
    (again['team1activity'] as Json)["46'"] = [{ Yellow: 'Eva' }];
    expect(await liveWrite(db, 1, again, LIVE_AT + 4 * HOUR, LIVE_AT + 4 * HOUR + 100))
      .toBe('settled');
    expect(db.f.Live).toBeUndefined();
    expect(db.writes).toEqual([]);
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + 4 * HOUR),
    });
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + 4 * HOUR },
    });
  });

  it('3b. an older-week correction while the next week is live: Live stays the newer week, the corrected Overall shows at once', async () => {
    // GW3 (Sun Jul 5, lock 22:00Z) plays the golden games again.
    const GW3_DATE = '07052026';
    const LOCK3 = Date.UTC(2026, 6, 5, 22);
    const db = await lockedWorld();
    db.data.Futsal['15'].Date[GW3_DATE] = [notStarted(0), notStarted(1)];
    // GW2 settles (its games Final), GW3 locks.
    db.date2[0] = golden(0);
    db.date2[1] = golden(1);
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + HOUR),
    });
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + HOUR },
    });
    await runLifecycleSweep(db, new Date(LOCK3 + MIN));
    expect(db.f.PublishedPicks[3]).toBeDefined();
    // GW3 goes live: Alex's goal (the ONE GOAL numbers: churn W 8). Base O
    // churn = GW1 59 + GW2 59 = 118 -> O 126.
    const gw3 = db.data.Futsal['15'].Date[GW3_DATE] as Json[];
    gw3[0] = oneGoal();
    expect(await refreshLiveWeek(db, {
      sport: SPORT, season: SEASON, dateKey: GW3_DATE, eventAtMs: LOCK3 + HOUR,
      nowUtc: new Date(LOCK3 + HOUR), clock: clockAt(LOCK3 + HOUR + 100),
    })).toBe('written');
    expect(db.f.Live.Meta.Gw).toBe(3);
    expect(db.f.Live.Board['churn']).toMatchObject({ O: 126, W: 8 });
    expect(db.f.LiveBase[3].Managers['churn']).toStrictEqual({ O: 118 });

    // The owner corrects GW2: Ben scores again (Bulls 3-0). Ben 7+4 = 11 +
    // bonus 3 (BPS 29 now tops Bea's 24) = 14; Bea's bonus drops to 2 ->
    // 14. churn GW2 = Bo 120 + Dana 130 + Bea 140 + Ben 14x2 280 + Eva -15
    // + Wren 30 = 685 -> 68: settled O 59 + 68 = 127, live O 127 + 8 = 135.
    const corrected = golden(1);
    corrected['team2score'] = 3;
    (corrected['team2activity'] as Json)["45'"] = [{ Goal: 'Ben' }];
    db.date2[1] = corrected;
    db.reset();
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LOCK3 + 2 * HOUR),
      deps: { clock: clockAt(LOCK3 + 2 * HOUR + 100) },
    });
    expect(db.f.Leaderboards.Overall['churn'].points).toBe(127);
    expect(db.writes).toContain(`${F_ROOT}/LiveBase`); // the whole node removed
    expect(db.f.Live.Meta).toMatchObject({ Gw: 3, State: 'live', ReadAt: LOCK3 + 2 * HOUR + 100 });
    expect(db.f.Live.Board['churn']).toMatchObject({ O: 135, W: 8 });
    expect(db.f.LiveBase[3].Managers['churn']).toStrictEqual({ O: 127 });
  });
});

describe('the owner voids the live week mid-day (Review Focus 4, Fable L4)', () => {
  it('4. LiveBase is removed whole and the live week refreshes at once: W 0, O = the settled base', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    expect(db.f.Live.Board['alpha'].W).toBe(19);
    db.f.LiveBase[1] = { Gw: 1 }; // a stale leftover: the whole node goes
    db.f.Voided = { 2: true };
    db.reset();
    await resettleVoidToggle(db, {
      sport: SPORT, season: SEASON, gw: 2, nowUtc: new Date(LIVE_AT + MIN),
      deps: { clock: clockAt(LIVE_AT + MIN + 100) },
    });
    expect(db.writes).toContain(`${F_ROOT}/LiveBase`);
    expect(db.f.LiveBase[1]).toBeUndefined();
    expect(db.f.Live.Meta).toMatchObject({ Gw: 2, State: 'live', ReadAt: LIVE_AT + MIN + 100 });
    expect(db.f.Live.Board).toStrictEqual({
      alpha: { O: 35, R: 3, M: 0, W: 0, WR: 1 },
      boost: { O: 44, R: 2, M: 0, W: 0, WR: 1 },
      churn: { O: 59, R: 1, M: 0, W: 0, WR: 1 },
    });
    expect(db.f.Live.Players['Alex']).toMatchObject({ Pts: 0, Total: 12, Games: 1 });
    // Nothing official moved: the week has not settled.
    expect(db.f.History[2]).toBeUndefined();
  });
});

describe('the trigger gate: writes that do not touch scoring cost nothing (Review Focus 5, Fable L2)', () => {
  it('4b. a Clock, livestream link or undo-bookkeeping write: zero reads, zero writes', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    const stored = JSON.stringify(db.f.Live);
    for (const [key, value] of [
      ['Clock', { Start: 123, Running: true }],
      ['link', 'https://youtu.be/x'],
      ['Undo', { Stack: [1, 2] }],
    ] as const) {
      db.reset();
      expect(await liveWrite(db, 0, { ...db.date2[0], [key]: value },
        LIVE_AT + 1000, LIVE_AT + 1100), key).toBe('ignored');
      expect(db.reads, key).toEqual([]);
      expect(db.writes, key).toEqual([]);
    }
    expect(JSON.stringify(db.f.Live)).toBe(stored);
  });

  it('4b. a scoring write on a game that is not live (status 0 before and after): ignored', async () => {
    const db = await lockedWorld();
    expect(await liveWrite(db, 1, { ...notStarted(1), team1attendance: { Eli: false } },
      LIVE_AT, LIVE_AT + 100)).toBe('ignored');
    expect(db.reads).toEqual([]);
  });

  it('an undone kickoff (1 -> 0) refreshes: with nothing started any more, the week\'s live node goes', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    db.date2[1] = { ...golden(1), status: 1 };
    expect(await liveWrite(db, 1, notStarted(1), LIVE_AT, LIVE_AT + 100)).toBe('written');
    // Game 1 counts nothing again; game 0 still does.
    expect(db.f.Live.Meta.Games[1].S).toBe(0);
    expect(db.f.Live.Players['Bea'].St).toBe('pending');
    expect(await liveWrite(db, 0, notStarted(0), LIVE_AT + 1000, LIVE_AT + 1100))
      .toBe('skipped');
    expect(db.f.Live).toBeUndefined();
  });

  it('nothing started never removes another week\'s node, nor a newer read', async () => {
    const db = await lockedWorld();
    const settled = { Meta: { Gw: 1, State: 'settled', UpdatedAt: 1 } };
    db.f.Live = clone(settled);
    expect(await refresh(db, LIVE_AT, LIVE_AT + 100)).toBe('skipped');
    expect(db.f.Live).toStrictEqual(settled);
    // This week's node read at a later instant than this run (it lands
    // between this run's read and its write): kept.
    const newer = { Meta: { Gw: 2, State: 'live', ReadAt: LIVE_AT + 500, UpdatedAt: 1, Games: {} } };
    db.f.Live = clone(newer);
    expect(await refresh(db, LIVE_AT + 600, LIVE_AT + 100)).toBe('skipped');
    expect(db.f.Live).toStrictEqual(newer);
  });

  it('the gate counts a game that counts or counted: a Final game reset to not started passes', () => {
    expect(liveWriteMatters(golden(0), notStarted(0))).toBe(true); // 2 -> 0
    expect(liveWriteMatters(oneGoal(), notStarted(0))).toBe(true); // 1 -> 0
    expect(liveWriteMatters(notStarted(0), oneGoal())).toBe(true); // 0 -> 1
    expect(liveWriteMatters(oneGoal(), golden(0))).toBe(true); // 1 -> 2
    expect(liveWriteMatters(notStarted(1),
      { ...notStarted(1), team1attendance: { Eli: false } })).toBe(false); // 0 -> 0
    expect(liveWriteMatters(golden(0), { ...golden(0), Clock: 1 })).toBe(false);
    expect(liveWriteMatters(notStarted(0), null)).toBe(false); // an unstarted game deleted
  });

  it('a Final game reset to not started refreshes: it counts nothing again', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, golden(0), LIVE_AT, LIVE_AT + 100);
    await liveWrite(db, 1, { ...golden(1), status: 1 }, LIVE_AT + 1000, LIVE_AT + 1100);
    expect(db.f.Live.Players['Alex']).toMatchObject({ St: 'done', Pts: 12 });
    expect(await liveWrite(db, 0, notStarted(0), LIVE_AT + 2000, LIVE_AT + 2100))
      .toBe('written');
    expect(db.f.Live.Meta.Games[0].S).toBe(0);
    expect(db.f.Live.Players['Alex']).toMatchObject({ St: 'pending', Pts: 0 });
  });

  it('scoringKeysChanged: each scoring key flips it; Clock, link and unknown keys do not', () => {
    expect([...SCORING_KEYS].sort()).toEqual([
      'Stage', 'forfeitedBy', 'status', 'team1', 'team1Score', 'team1activity',
      'team1attendance', 'team1keepers', 'team1score', 'team2', 'team2Score',
      'team2activity', 'team2attendance', 'team2keepers', 'team2score',
    ]);
    const base = oneGoal();
    expect(scoringKeysChanged(base, clone(base))).toBe(false);
    for (const key of SCORING_KEYS) {
      expect(scoringKeysChanged(base, { ...base, [key]: { changed: key } }), key).toBe(true);
    }
    // A deep change inside the activity map counts.
    const deeper = clone(base);
    (deeper['team1activity'] as Json)["5'"][0]['Goal'] = 'Dana';
    expect(scoringKeysChanged(base, deeper)).toBe(true);
    // An added / removed key counts; absent == null.
    const noScore = clone(base);
    delete noScore['team2score'];
    expect(scoringKeysChanged(base, noScore)).toBe(true);
    expect(scoringKeysChanged({ ...base, forfeitedBy: null }, base)).toBe(false);
    // The whole game created / deleted.
    expect(scoringKeysChanged(null, base)).toBe(true);
    expect(scoringKeysChanged(base, null)).toBe(true);
    for (const key of ['Clock', 'link', 'Undo', 'whatever', '_t']) {
      expect(scoringKeysChanged(base, { ...base, [key]: 1 }), key).toBe(false);
    }
  });
});

describe('stand-downs: exactly where finalize stands down, plus no lock snapshot', () => {
  const cases: Array<[string, (db: LiveDb) => void, Date?]> = [
    ['no fantasy Config', (db) => { delete db.f.Config; }],
    ['lockOverride open', (db) => { db.f.Config.lockOverride = 'open'; }],
    ['a TestFill season', (db) => { db.f.TestFill = { At: 1, Managers: 20 }; }],
    ['before the lock', () => undefined, new Date(LOCK2_MS - HOUR)],
    ['no PublishedPicks/<gw>', (db) => { delete db.f.PublishedPicks[2]; }],
    ['no LockedPositions/<gw>', (db) => { delete db.f.LockedPositions[2]; }],
  ];
  for (const [label, arrange, now] of cases) {
    it(`6. ${label}: standDown, zero writes`, async () => {
      const db = await lockedWorld();
      db.date2[0] = oneGoal();
      arrange(db);
      db.reset();
      expect(await refresh(db, LIVE_AT - 2000, LIVE_AT - 1000, now ?? NOW))
        .toBe('standDown');
      expect(db.writes).toEqual([]);
      expect(db.f.Live).toBeUndefined();
    });
  }
});

describe('sweep step 2d: a lost settle heals after the margin', () => {
  it('finalize loses its hand-over: a sweep inside the margin writes nothing, one after it writes the tombstone', async () => {
    expect(LIVE_SETTLE_HEAL_MS).toBe(10 * MIN);
    const db = await lockedWorld();
    await liveWrite(db, 0, golden(0), LIVE_AT, LIVE_AT + 100);
    expect(await liveWrite(db, 1, golden(1), LIVE_AT + 1000, LIVE_AT + 1100))
      .toBe('written'); // Live/Meta.UpdatedAt = LIVE_AT
    // The settle's Live transaction fails once (the run died there).
    db.beforeLiveTx = async () => { throw new Error('connection lost'); };
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + MIN),
    });
    expect(db.f.History[2]).toBeDefined();
    expect(db.f.Live.Meta.State).toBe('live'); // the hand-over was lost
    const lost = clone(db.f.Live);

    db.reset();
    await runLifecycleSweep(db, new Date(LIVE_AT + 9 * MIN), undefined, {
      clock: clockAt(LIVE_AT + 9 * MIN + 100),
    });
    expect(db.f.Live).toStrictEqual(lost);
    expect(db.writes.filter((p) => p.startsWith(`${F_ROOT}/Live`))).toEqual([]);
    // Step 3 marks the week finalized, so step 2c never looks again.
    expect(db.f.GwState.status).toBe('finalized');

    db.reset();
    await runLifecycleSweep(db, new Date(LIVE_AT + 11 * MIN), undefined, {
      clock: clockAt(LIVE_AT + 11 * MIN + 100),
    });
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + 11 * MIN },
    });
    expect(db.f.LiveBase).toBeUndefined();
    // Healed: the next sweep changes nothing.
    db.reset();
    await runLifecycleSweep(db, new Date(LIVE_AT + 30 * MIN));
    expect(db.writes.filter((p) => p.startsWith(`${F_ROOT}/Live`))).toEqual([]);
  });

  it('the heal asks whether History/<n> exists; it never downloads the week', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, golden(0), LIVE_AT, LIVE_AT + 100);
    await liveWrite(db, 1, golden(1), LIVE_AT + 1000, LIVE_AT + 1100);
    db.beforeLiveTx = async () => { throw new Error('connection lost'); };
    await maybeFinalizeGame(db, {
      sport: SPORT, season: SEASON, dateKey: GW2_DATE, nowUtc: new Date(LIVE_AT + MIN),
    });
    expect(db.f.Live.Meta.State).toBe('live'); // the hand-over was lost

    db.reset();
    await runLifecycleSweep(db, new Date(LIVE_AT + 11 * MIN), undefined, {
      clock: clockAt(LIVE_AT + 11 * MIN + 100),
    });
    expect(db.f.Live.Meta.State).toBe('settled'); // healed, as before
    expect(db.reads).toContain(`exists:${F_ROOT}/History/2`);
    expect(db.reads).not.toContain(`read:${F_ROOT}/History/2`);
  });

  it('a live week without History is never tombstoned, however old its last write', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    const live = clone(db.f.Live);
    db.reset();
    // An hour on with no new event (a slow game, not a lost settle).
    await runLifecycleSweep(db, new Date(LIVE_AT + HOUR), undefined, {
      clock: clockAt(LIVE_AT + HOUR + 100),
    });
    expect(db.f.Live.Meta).toMatchObject({ Gw: 2, State: 'live' });
    expect(db.f.Live.Board).toStrictEqual(live.Board);
  });
});

describe('sweep step 2c: the live backstop', () => {
  it('8. a lost trigger: the next sweep publishes the live week', async () => {
    const db = await lockedWorld();
    db.date2[0] = oneGoal(); // written, but no trigger ever ran
    await runLifecycleSweep(db, new Date(LIVE_AT), undefined, {
      clock: clockAt(LIVE_AT + 100),
    });
    expect(db.f.Live.Meta).toMatchObject({ Gw: 2, State: 'live', ReadAt: LIVE_AT + 100 });
    expect(db.f.Live.Players['Alex'].Pts).toBe(10);
    expect(db.f.Live.Board['alpha'].W).toBe(19);
  });

  it('8. a lost trigger on a game that went straight to Final while the other has not started: 2c refreshes', async () => {
    const db = await lockedWorld();
    db.date2[0] = golden(0); // Final, its trigger lost; game 1 not started
    await runLifecycleSweep(db, new Date(LIVE_AT), undefined, {
      clock: clockAt(LIVE_AT + 100),
    });
    expect(db.f.History[2]).toBeUndefined(); // not every game is Final
    expect(db.f.Live.Meta).toMatchObject({ Gw: 2, State: 'live', ReadAt: LIVE_AT + 100 });
    expect(db.f.Live.Meta.Games[0].S).toBe(2);
    expect(db.f.Live.Players['Alex']).toMatchObject({ St: 'done', Pts: 12 });
    expect(db.f.Live.Squads['alpha'].T).toBe(245); // hand math: test 5
  });

  it('nothing started: the sweep writes no Live', async () => {
    const db = await lockedWorld();
    await runLifecycleSweep(db, new Date(LIVE_AT), undefined, {
      clock: clockAt(LIVE_AT + 100),
    });
    expect(db.f.Live).toBeUndefined();
  });

  it('every game Final: the sweep finalizes (step 2), the week stays settled', async () => {
    const db = await lockedWorld();
    await liveWrite(db, 0, oneGoal(), LIVE_AT - 2000, LIVE_AT - 1000);
    db.date2[0] = golden(0);
    db.date2[1] = golden(1); // both Final, both triggers lost
    await runLifecycleSweep(db, new Date(LIVE_AT + HOUR), undefined, {
      clock: clockAt(LIVE_AT + HOUR + 100),
    });
    expect(db.f.History[2]).toBeDefined();
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + HOUR },
    });
    // And the next sweep leaves it alone.
    await runLifecycleSweep(db, new Date(LIVE_AT + 2 * HOUR), undefined, {
      clock: clockAt(LIVE_AT + 2 * HOUR + 100),
    });
    expect(db.f.Live).toStrictEqual({
      Meta: { Gw: 2, State: 'settled', UpdatedAt: LIVE_AT + HOUR },
    });
  });
});
