// A game day called off after its deadline (season setup + schedule plan
// 2026-11-05, Task 4): the sweep rewinds the latest frozen week as if it
// never happened — snapshots, chips, money baselines, live node, ledger
// entry — reopens it until the next game day's deadline and tells every
// manager once; the Config trigger keeps an OPEN week's deadline live and
// never rewinds. Over the cold-first FakeDb (test_support.ts): a transaction
// first sees null, as RTDB's empty cache in a Cloud Function does.
//
// World: test_support.ts world2 — GW1 settled (and frozen in LockedWeeks),
// GW2 (Sun Jun 28, lock 22:00Z) the week under test, the next game day a
// week later (Sun Jul 5, lock 22:00Z).

import { describe, expect, it } from 'vitest';
import { configFromMap } from './fantasy_config';
import { Gameweek } from './gameweeks';
import { clone, Json } from './golden_fixture';
import {
  FantasyLogger, maybeFinalizeGame, resettleVoidToggle, runLifecycleSweep,
} from './orchestration';
import { FantasyPusher, FantasyUserPush, formatDeadlineInstant } from './pushes';
import {
  refreshOpenGwState, restoreBaselineAfterRewind, rewindCancelledWeek,
  scheduleConfigChanged, upsertGwState,
} from './schedule_rewind';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, FakePusher, fixtureSquad, GW1_DATE, GW2_DATE,
  LOCK2_MS, world2,
} from './test_support';

const GW3_DATE = '07052026'; // the next Sunday
const LOCK1_MS = Date.UTC(2026, 5, 21, 22);
const LOCK3_MS = Date.UTC(2026, 6, 5, 22);
const BEFORE_LOCK2 = new Date(Date.UTC(2026, 5, 28, 10));
/** Sun Jun 28, 5 PM league time: GW2 locked an hour ago. */
const LATER = new Date(AFTER_LOCK2.getTime() + 60 * 60_000);
const LATER2 = new Date(LATER.getTime() + 15 * 60_000);
const LATER3 = new Date(LATER2.getTime() + 15 * 60_000);

// The golden GW1 squads' prices; alpha's after selling Alex for Ben.
const GW1_ALPHA = { Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Alex: 95, Will: 60, Wren: 75 };
const GW1_BOOST = { Sam: 85, Bea: 70, Will: 60, Ben: 85, Wren: 75, Eva: 50, Ezra: 65 };
const GW1_CHURN = { Bo: 75, Dana: 80, Bea: 70, Ezra: 65, Ben: 85, Eva: 50, Wren: 75 };
const ALPHA_GW2 = { Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Ben: 85, Will: 60, Wren: 75 };

/** Every lock snapshot of a week (the heal's orphan list). */
const SNAPSHOTS = ['PublishedPicks', 'LockedPositions', 'PriceHistory', 'TransferCosts'];
const CALLED_OFF_TITLE = 'Infinite Fantasy';
const KICKED_OFF = 'fantasy rewind: deadline moved after kickoff — not reopened';

const t = (db: FakeDb) => db.data.Fantasy.Futsal['15'];
const dates = (db: FakeDb) => db.data.Futsal['15'].Date;

const logSpy = () => {
  const infos: string[] = [];
  const warns: string[] = [];
  const log: FantasyLogger = {
    info: (m) => { infos.push(m); },
    warn: (m) => { warns.push(m); },
  };
  return { infos, warns, log };
};

/** The pre-lock Baselines: every golden manager FOR GW2 at GW1's prices;
 *  dave sat GW1 out carrying -15 (RTDB pruned his empty Prices). */
const preLockBaselines = (): Json => ({
  alpha: { ForGw: 2, RealizedTenths: 0, Prices: { ...GW1_ALPHA } },
  boost: { ForGw: 2, RealizedTenths: 0, Prices: { ...GW1_BOOST } },
  churn: { ForGw: 2, RealizedTenths: 0, Prices: { ...GW1_CHURN } },
  dave: { ForGw: 2, RealizedTenths: -15 },
});

/** world2 with GW1 frozen + Scored, GW2's games at [gw2Status] (0 = not
 *  started), and — unless [later] is false — the next game day GW3_DATE a
 *  week later (same fixtures, not started). Managers: the golden three,
 *  dave (sat GW1 out carrying -15; his GW2 team is 15 over budget, so the
 *  lock judges it Invalid) and erin (signed up, no squad, no baseline yet).
 *  In GW2's window alpha sold Alex (bought 95, now 105: +5) for Ben with no
 *  free transfer left (4 points) and armed his triple captain; GW2's
 *  deadline reminder already went out. */
function world(opts: { gw2Status?: number; later?: boolean } = {}): FakeDb {
  const w = world2({ gw2Status: opts.gw2Status ?? 0 });
  const s = w.Fantasy.Futsal['15'];
  s.LockedWeeks = { 1: { Date: GW1_DATE, LockAtUtc: LOCK1_MS, Scored: true } };
  s.Managers = {
    alpha: { TeamName: 'Alpha FC' }, boost: { TeamName: 'Boost FC' },
    churn: { TeamName: 'Churn FC' }, dave: { TeamName: 'Dave XI' },
    erin: { TeamName: 'Erin Athletic' },
  };
  s.Baselines = preLockBaselines();
  s.Players.Alex.priceTenths = 105;
  s.Squads.alpha.picks[4] =
    { playerId: 'Ben', position: 'ATT', priceTenths: 85, bench: false };
  s.Squads.alpha.viceId = 'Ben';
  s.Squads.alpha.chip = 'tripleCaptain';
  s.Squads.dave = fixtureSquad('churn'); // 500 against a 485 budget
  s.TransferState = { alpha: { Free: 0, UsedThisGw: 0 } };
  s.ReminderSent = { 2: { At: Date.UTC(2026, 5, 28, 19) } };
  if (opts.later !== false) {
    const next = clone(w.Futsal['15'].Date[GW2_DATE]) as Json[];
    for (const g of next) g['status'] = 0;
    w.Futsal['15'].Date[GW3_DATE] = next;
  }
  return new FakeDb(w);
}

/** world() after the sweep that locks GW2. */
async function lockedGw2(
  opts: { gw2Status?: number; later?: boolean } = {},
): Promise<FakeDb> {
  const db = world(opts);
  await runLifecycleSweep(db, AFTER_LOCK2);
  return db;
}

const rewind = (
  db: FakeDb, nowUtc: Date,
  extra: { log?: FantasyLogger; pusher?: FantasyPusher } = {},
) => rewindCancelledWeek(db, {
  sport: 'Futsal', season: '15', cfg: configFromMap(t(db).Config),
  configNode: t(db).Config, nowUtc, ...extra,
});

/** The "called off" messages among everything the pusher sent. */
const calledOffSends = (pusher: FakePusher): FantasyUserPush[][] =>
  pusher.sends.filter((batch) => batch.some((m) => m.title === CALLED_OFF_TITLE));

/** Makes ONE matching call of [method] throw (a function instance dying
 *  there); every other call goes through. */
function crashOnce(
  db: FakeDb, method: 'read' | 'write' | 'transaction',
  match: (path: string) => boolean,
): void {
  const real = (db[method] as (...a: unknown[]) => Promise<unknown>).bind(db);
  let crashed = false;
  (db as unknown as Record<string, unknown>)[method] = async (...a: unknown[]) => {
    if (!crashed && match(a[0] as string)) {
      crashed = true;
      throw new Error(`crash at ${method} ${String(a[0])}`);
    }
    return real(...a);
  };
}

/** Everything a clean rewind of world()'s GW2 leaves behind. */
async function expectRewound(db: FakeDb): Promise<void> {
  for (const n of [...SNAPSHOTS, 'ReminderSent']) {
    expect(await db.read(`${F_ROOT}/${n}/2`), n).toBeNull();
  }
  expect(t(db).LockedWeeks)
    .toEqual({ 1: { Date: GW1_DATE, LockAtUtc: LOCK1_MS, Scored: true } });
  expect(t(db).GwState).toEqual({
    current: 2, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
  });
  // Nothing was scored, so no chip was spent; the window is still GW2, so
  // its transfer count stands (the next save recounts it).
  expect(t(db).TransferState.alpha).toEqual({ Free: 0, UsedThisGw: 1 });
  // [M3] the exact pre-lock money (dave's empty Prices: RTDB prunes it, as
  // it did before the lock); erin's first-ever node is gone again.
  expect(t(db).Baselines).toEqual({
    ...preLockBaselines(),
    dave: { ForGw: 2, RealizedTenths: -15, Prices: {} },
  });
  // The lock's Invalid verdict is gone (the reopened week's own over-budget
  // preview may stand in its slot).
  expect(t(db).SquadAlerts?.dave?.Kind).not.toBe('invalid');
}

describe('restoreBaselineAfterRewind (pure)', () => {
  const prev = { ForGw: 2, RealizedTenths: -15, Prices: { Sam: 85 } };

  it('a node FOR the week after the rewound one with a Prev → the Prev node', () => {
    expect(restoreBaselineAfterRewind(
      { ForGw: 3, RealizedTenths: 5, Prices: { Ben: 85 }, Prev: prev }, 2)).toEqual(prev);
  });

  it('[T4c] pops exactly ONE level of the Prev chain: the stashed node comes '
    + 'back with its own Prev', () => {
    const chain = {
      ForGw: 3, RealizedTenths: 0, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: {} },
    };
    expect(restoreBaselineAfterRewind(
      { ForGw: 4, RealizedTenths: 5, Prices: { Ben: 85 }, Prev: chain }, 3))
      .toEqual(chain);
    expect(restoreBaselineAfterRewind(chain, 2))
      .toEqual({ ForGw: 2, RealizedTenths: -15, Prices: {} });
  });

  it('FOR the week after, no Prev (or an unreadable one) → removed', () => {
    expect(restoreBaselineAfterRewind({ ForGw: 3, RealizedTenths: 0 }, 2)).toBeNull();
    expect(restoreBaselineAfterRewind(
      { ForGw: 3, RealizedTenths: 0, Prev: { RealizedTenths: 4 } }, 2)).toBeNull();
  });

  it('any other node is left alone — even one carrying an older lock\'s Prev', () => {
    expect(restoreBaselineAfterRewind({ ForGw: 2, RealizedTenths: 0 }, 2)).toBeUndefined();
    expect(restoreBaselineAfterRewind(
      { ForGw: 2, RealizedTenths: 0, Prev: { ForGw: 1, RealizedTenths: 0 } }, 2))
      .toBeUndefined();
    expect(restoreBaselineAfterRewind({ ForGw: 4, RealizedTenths: 0 }, 2)).toBeUndefined();
    expect(restoreBaselineAfterRewind(null, 2)).toBeUndefined();
    expect(restoreBaselineAfterRewind('junk', 2)).toBeUndefined();
  });
});

describe('the sweep rewinds a called-off week', () => {
  it('rewinds the latest unscored week; GW2 reopens with the next date\'s deadline', async () => {
    const db = await lockedGw2();
    // The lock as it happened.
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    for (const n of SNAPSHOTS) expect(await db.read(`${F_ROOT}/${n}/2`), n).not.toBeNull();
    expect(t(db).TransferState.alpha.ChipPlayed).toBe('tripleCaptain');
    expect(t(db).SquadAlerts.dave).toMatchObject({ Gw: 2, Kind: 'invalid' });
    expect(t(db).GwState.status).toBe('locked');

    delete dates(db)[GW2_DATE]; // rained out, after the deadline
    const pusher = new FakePusher();
    const spy = logSpy();
    await runLifecycleSweep(db, LATER, spy.log, { pusher });

    await expectRewound(db);
    expect(calledOffSends(pusher)).toEqual([
      ['alpha', 'boost', 'churn', 'dave', 'erin'].map((uid) => ({
        uid,
        title: 'Infinite Fantasy',
        body: 'GW2 was called off — your team is open again until Sun, Jul 5 · 3:00 PM.',
        data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '2' },
      })),
    ]);
    expect(await db.read(`${F_ROOT}/CalledOff/2/${GW2_DATE}`))
      .toEqual({ At: LATER.getTime() });
    // The rest of the sweep ran on the reopened week: dave's saved team is
    // still 15 over, so the open-window preview warns him.
    expect(t(db).SquadAlerts.dave).toMatchObject({ Gw: 2, Kind: 'preview' });

    // A second sweep finds nothing to do.
    db.writes = [];
    await runLifecycleSweep(db, LATER2, undefined, { pusher });
    expect(db.writes.filter((w) => w.startsWith(`${F_ROOT}/`))).toEqual([]);
    expect(calledOffSends(pusher)).toHaveLength(1);
  });

  it('[M3] a manager who sat out GW1 and sold players in GW2\'s window gets the '
    + 'pre-lock baseline back exactly (from Prev)', async () => {
    const db = await lockedGw2();
    // The lock stashed what it overwrote.
    expect(t(db).Baselines.alpha).toEqual({
      ForGw: 3, RealizedTenths: 5, Prices: ALPHA_GW2,
      Prev: { ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA },
    });
    expect(t(db).Baselines.dave).toEqual({
      ForGw: 3, RealizedTenths: -15, Prices: {},
      Prev: { ForGw: 2, RealizedTenths: -15, Prices: {} },
    });
    delete dates(db)[GW2_DATE];
    await runLifecycleSweep(db, LATER);
    // alpha's +5 sale is undone; dave keeps exactly the -15 he carried in.
    expect(t(db).Baselines.alpha)
      .toEqual({ ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA });
    expect(t(db).Baselines.dave)
      .toEqual({ ForGw: 2, RealizedTenths: -15, Prices: {} });
  });

  it('[M3] a manager with no Prev and ForGw 3 loses the node; ForGw 2 is left', async () => {
    const db = await lockedGw2();
    expect(t(db).Baselines.erin).toEqual({ ForGw: 3, RealizedTenths: 0, Prices: {} });
    // A node the lock never reached (still FOR GW2).
    t(db).Baselines.frank = { ForGw: 2, RealizedTenths: 3, Prices: { Sam: 85 } };
    delete dates(db)[GW2_DATE];
    await runLifecycleSweep(db, LATER);
    expect(t(db).Baselines.erin).toBeUndefined();
    expect(t(db).Baselines.frank)
      .toEqual({ ForGw: 2, RealizedTenths: 3, Prices: { Sam: 85 } });
    expect(db.writes).not.toContain(`${F_ROOT}/Baselines/frank`);
  });

  it('games moved one week later → GW2 is the new date', async () => {
    const db = await lockedGw2({ later: false });
    const moved = clone(dates(db)[GW2_DATE]) as Json[];
    for (const g of moved) g['status'] = 0;
    dates(db)[GW3_DATE] = moved;
    delete dates(db)[GW2_DATE];
    await runLifecycleSweep(db, LATER);
    expect(await db.read(`${F_ROOT}/LockedWeeks/2`)).toBeNull();
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
    });
  });

  it('skipping the date by Config rewinds the same way', async () => {
    const db = await lockedGw2();
    t(db).Config.SkippedDates = { [GW2_DATE]: true }; // the games stay listed
    const pusher = new FakePusher();
    await runLifecycleSweep(db, LATER, undefined, { pusher });
    await expectRewound(db);
    expect(calledOffSends(pusher)).toHaveLength(1);
  });

  it('[M1] an override pushed into the future rewinds when no game started', async () => {
    const db = await lockedGw2(); // GW2's games not started
    const override = LATER.getTime() + 2 * 60 * 60_000; // Sun 7 PM league time
    t(db).Config.Deadlines = { [GW2_DATE]: override };
    const pusher = new FakePusher();
    await runLifecycleSweep(db, LATER, undefined, { pusher });
    for (const n of SNAPSHOTS) expect(await db.read(`${F_ROOT}/${n}/2`), n).toBeNull();
    expect(await db.read(`${F_ROOT}/LockedWeeks/2`)).toBeNull();
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: override, date: GW2_DATE,
    });
    expect(calledOffSends(pusher)[0][0].body).toBe(
      'GW2 was called off — your team is open again until Sun, Jun 28 · 7:00 PM.');
  });

  it('[M1] the same override with a game at status 1 → no rewind, warn logged', async () => {
    const db = await lockedGw2();
    dates(db)[GW2_DATE][0].status = 1; // a game of the day kicked off
    t(db).Config.Deadlines = { [GW2_DATE]: LATER.getTime() + 2 * 60 * 60_000 };
    db.writes = [];
    const spy = logSpy();
    expect(await rewind(db, LATER, { log: spy.log })).toBe('none');
    expect(db.writes).toEqual([]);
    expect(spy.warns).toContain(KICKED_OFF);
    // ...and the whole sweep keeps the week locked.
    await runLifecycleSweep(db, LATER);
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
    expect(t(db).GwState.status).toBe('locked');
  });

  it('[M1] an override still in the past → no rewind', async () => {
    const db = await lockedGw2();
    t(db).Config.Deadlines = { [GW2_DATE]: LATER.getTime() - 60_000 };
    db.writes = [];
    expect(await rewind(db, LATER)).toBe('none');
    expect(db.writes).toEqual([]);
  });

  it('partial cancel: one Final game left on the date → no rewind', async () => {
    const db = await lockedGw2();
    const kept = dates(db)[GW2_DATE][0];
    kept.status = 2;
    dates(db)[GW2_DATE] = [kept];
    db.writes = [];
    expect(await rewind(db, LATER)).toBe('none');
    expect(db.writes).toEqual([]);
  });

  it.each([
    ['History present', (db: FakeDb) => {
      t(db).History[2] = { alpha: { ...fixtureSquad('alpha'), TotalTenths: 0 } };
    }],
    ['a Scored marker', (db: FakeDb) => { t(db).LockedWeeks[2].Scored = true; }],
  ])('never rewinds a scored week (%s)', async (_label, score) => {
    const db = await lockedGw2();
    score(db);
    delete dates(db)[GW2_DATE];
    db.writes = [];
    expect(await rewind(db, LATER)).toBe('none');
    expect(db.writes).toEqual([]);
    expect(t(db).LockedWeeks[2]['Rewinding']).toBeUndefined();
  });

  it('never rewinds when the schedule read throws', async () => {
    const db = await lockedGw2();
    delete dates(db)[GW2_DATE];
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      if (p.startsWith('Futsal/15/Date')) throw new Error('network down');
      return realRead(p);
    };
    db.writes = [];
    await expect(rewind(db, LATER)).rejects.toThrow('network down');
    expect(db.writes).toEqual([]);
    // The sweep gives the season up for this run — still nothing written.
    const spy = logSpy();
    await runLifecycleSweep(db, LATER, spy.log, { pusher: new FakePusher() });
    expect(db.writes.filter((w) => w.startsWith(`${F_ROOT}/`))).toEqual([]);
    expect(spy.warns).toContain('fantasy sweep: season failed');
  });

  it('stands down when the whole schedule is empty', async () => {
    const db = await lockedGw2();
    delete db.data.Futsal['15'].Date;
    db.writes = [];
    const spy = logSpy();
    expect(await rewind(db, LATER, { log: spy.log })).toBe('standDown');
    expect(spy.warns).toContain(
      'fantasy rewind: the season has no game days at all — standing down');
    // The sweep stands the season down with it.
    await runLifecycleSweep(db, LATER, undefined, { pusher: new FakePusher() });
    expect(db.writes.filter((w) => w.startsWith(`${F_ROOT}/`))).toEqual([]);
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
  });

  it('[M2] a stale re-claim of the old date is rewound again by the next sweep; '
    + 'exactly one push', async () => {
    const db = await lockedGw2();
    const pusher = new FakePusher();
    // Sweep S reads the schedule while GW2's games are still listed. Before
    // its lock step claims the week, the owner deletes the games and sweep R
    // rewinds GW2 — so S re-claims LockedWeeks/2 with the OLD date and
    // writes a stale lock under it.
    const realRead = db.read.bind(db);
    let rewound: Promise<void> | null = null;
    db.read = async (p: string) => {
      if (rewound === null && p === `${F_ROOT}/LockedWeeks/2`) {
        rewound = (async () => {
          delete dates(db)[GW2_DATE];
          db.read = realRead;
          await runLifecycleSweep(db, LATER, undefined, { pusher });
        })();
        await rewound;
      }
      return realRead(p);
    };
    await runLifecycleSweep(db, LATER, undefined, { pusher });
    expect(rewound).not.toBeNull();
    expect(calledOffSends(pusher)).toHaveLength(1);
    // S's stale lock stands for now...
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
    expect(t(db).GwState.status).toBe('locked');

    // ...until the next sweep rewinds it again — without a second push.
    await runLifecycleSweep(db, LATER2, undefined, { pusher });
    await expectRewound(db);
    expect(calledOffSends(pusher)).toHaveLength(1);
  });

  it('[T3a] the mark refuses when History appeared after the reasons check → '
    + 'Rewinding removed, nothing deleted', async () => {
    const db = await lockedGw2();
    delete dates(db)[GW2_DATE];
    const before = clone(t(db));
    const history = { alpha: { ...fixtureSquad('alpha'), TotalTenths: 0 } };
    const realTx = db.transaction.bind(db);
    db.transaction = async (p: string, update: (c: unknown) => unknown) => {
      // A finalize lands History/2 just as the rewind marks the week.
      if (p === `${F_ROOT}/LockedWeeks/2` && t(db).History[2] === undefined) {
        t(db).History[2] = clone(history);
      }
      return realTx(p, update);
    };
    const spy = logSpy();
    const pusher = new FakePusher();
    expect(await rewind(db, LATER, { log: spy.log, pusher })).toBe('none');
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    expect(t(db)).toEqual({ ...before, History: { ...before.History, 2: history } });
    expect(pusher.sends).toEqual([]);
    expect(spy.warns).toContain(
      'fantasy rewind: the week was scored meanwhile — kept');
  });

  it('[T3a] a finalize landing while the rewind runs (before the ledger entry '
    + 'goes) keeps the week: no push, the entry unmarked', async () => {
    const db = await lockedGw2();
    delete dates(db)[GW2_DATE];
    const realTx = db.transaction.bind(db);
    db.transaction = async (p: string, update: (c: unknown) => unknown) => {
      if (p === `${F_ROOT}/Baselines/alpha` && t(db).History[2] === undefined) {
        t(db).History[2] = { alpha: { ...fixtureSquad('alpha'), TotalTenths: 0 } };
      }
      return realTx(p, update);
    };
    const pusher = new FakePusher();
    expect(await rewind(db, LATER, { pusher })).toBe('none');
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    expect(pusher.sends).toEqual([]);
    expect(t(db).CalledOff).toBeUndefined();
  });

  it.each([
    ['right after the mark', 'read', (p: string) => p === `${F_ROOT}/PublishedPicks/2`],
    ['clearing a chip', 'transaction', (p: string) => p === `${F_ROOT}/TransferState/alpha`],
    ['deleting the snapshots', 'write', (p: string) => p === `${F_ROOT}/LockedPositions/2`],
    ['restoring a baseline', 'transaction', (p: string) => p === `${F_ROOT}/Baselines/dave`],
    ['sending the push', 'read', (p: string) => p === `${F_ROOT}/Managers`],
    ['removing the ledger entry', 'transaction', (() => {
      let marks = 0; // the first LockedWeeks/2 transaction is the mark
      return (p: string) => p === `${F_ROOT}/LockedWeeks/2` && ++marks === 2;
    })()],
    ['writing GwState', 'write', (p: string) => p === `${F_ROOT}/GwState`],
  ] as const)('[T3a] a rewind that crashed %s is finished by the next sweep; one push',
    async (_label, method, match) => {
      const db = await lockedGw2();
      delete dates(db)[GW2_DATE];
      const pusher = new FakePusher();
      crashOnce(db, method, match);
      const spy = logSpy();
      await runLifecycleSweep(db, LATER, spy.log, { pusher });
      expect(spy.warns).toContain('fantasy sweep: season failed');
      await runLifecycleSweep(db, LATER2, undefined, { pusher });
      await expectRewound(db);
      expect(calledOffSends(pusher)).toHaveLength(1);
      await runLifecycleSweep(db, LATER3, undefined, { pusher });
      expect(calledOffSends(pusher)).toHaveLength(1);
    });

  it('[T3a] a crashed rewind (node left marked) is resumed by the next sweep '
    + 'without re-checking why', async () => {
    const db = await lockedGw2();
    // Marked by a rewind that died; the owner has since put the games back.
    t(db).LockedWeeks[2].Rewinding = true;
    const spy = logSpy();
    expect(await rewind(db, LATER, { log: spy.log })).toBe('rewound');
    expect(spy.warns).toContain('fantasy rewind: resuming an unfinished rewind');
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
    expect(t(db).TransferState.alpha.ChipPlayed).toBeUndefined();
    // GW2 is its old date again — already past its deadline: the next
    // lock takes a fresh snapshot.
    expect(t(db).LockedWeeks[2]).toBeUndefined();
    expect(t(db).GwState).toMatchObject({ current: 2, date: GW2_DATE, status: 'locked' });
  });

  it('[T3a] a finalize trigger for a marked week stands down', async () => {
    const db = await lockedGw2();
    t(db).LockedWeeks[2].Rewinding = true;
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    db.writes = [];
    const spy = logSpy();
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: LATER, log: spy.log,
    });
    expect(db.writes).toEqual([]);
    expect(await db.read(`${F_ROOT}/History/2`)).toBeNull();
    expect(spy.infos).toContain('fantasy finalize: week being rewound — standing down');
  });

  it('[T3a] the sweep\'s finalize backstop stands down for a week marked after '
    + 'the rewind check, and that sweep writes no GwState', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2; // complete: backstop due
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      // Another sweep's rewind marks GW2 once this one has loaded its weeks.
      if (p === 'Futsal/15/Start Time') t(db).LockedWeeks[2].Rewinding = true;
      return realRead(p);
    };
    db.writes = [];
    const spy = logSpy();
    await runLifecycleSweep(db, LATER, spy.log);
    expect(await db.read(`${F_ROOT}/History/2`)).toBeNull();
    expect(spy.infos).toContain('fantasy finalize: week being rewound — standing down');
    expect(db.writes).not.toContain(`${F_ROOT}/GwState`);
  });

  it('an abandoned live day (games status 1, then all moved away): Live and '
    + 'LiveBase/2 removed', async () => {
    const db = await lockedGw2({ gw2Status: 1, later: false });
    // The next sweep's live backstop publishes the live week.
    await runLifecycleSweep(db, new Date(AFTER_LOCK2.getTime() + 15 * 60_000));
    expect(t(db).Live.Meta).toMatchObject({ Gw: 2, State: 'live' });
    expect(await db.read(`${F_ROOT}/LiveBase/2`)).not.toBeNull();
    // Abandoned: every game moved a week later (not started there).
    const moved = clone(dates(db)[GW2_DATE]) as Json[];
    for (const g of moved) g['status'] = 0;
    dates(db)[GW3_DATE] = moved;
    delete dates(db)[GW2_DATE];
    await runLifecycleSweep(db, LATER);
    expect(await db.read(`${F_ROOT}/Live`)).toBeNull();
    expect(await db.read(`${F_ROOT}/LiveBase/2`)).toBeNull();
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
    });
  });

  it('[S3] no later game day → GwState null, push says plain \'GW2 was called off.\'', async () => {
    const db = await lockedGw2({ later: false });
    delete dates(db)[GW2_DATE];
    const pusher = new FakePusher();
    await runLifecycleSweep(db, LATER, undefined, { pusher });
    expect(await db.read(`${F_ROOT}/GwState`)).toBeNull();
    expect(await db.read(`${F_ROOT}/LockedWeeks/2`)).toBeNull();
    expect(calledOffSends(pusher).map((b) => b.map((m) => m.body)))
      .toEqual([Array(5).fill('GW2 was called off.')]);
  });

  it('a push that fails still finishes the rewind (logged); nothing re-sends it', async () => {
    const db = await lockedGw2();
    delete dates(db)[GW2_DATE];
    const failing: FantasyPusher = {
      sendToUsers: async () => { throw new Error('FCM down'); },
      sendToTopic: async () => 0,
    };
    const spy = logSpy();
    expect(await rewind(db, LATER, { log: spy.log, pusher: failing })).toBe('rewound');
    await expectRewound(db);
    expect(spy.warns).toContain('fantasy rewind: called-off push failed');
  });

  it('[T4c] two called-off weeks in a row (GW3, then GW2 on the next sweep): '
    + 'every manager\'s money comes back exactly', async () => {
    const GW4_DATE = '07122026';
    const LOCK4_MS = Date.UTC(2026, 6, 12, 22);
    const db = await lockedGw2({ gw2Status: 1 }); // GW2 kicked off, never finished
    dates(db)[GW4_DATE] = clone(dates(db)[GW3_DATE]);
    const afterLock3 = new Date(LOCK3_MS + 60 * 60_000);
    await runLifecycleSweep(db, afterLock3); // GW3 locks on top of unscored GW2
    expect(t(db).LockedWeeks[3]).toEqual({ Date: GW3_DATE, LockAtUtc: LOCK3_MS });
    // dave's carried -15, stashed one level per lock.
    expect(t(db).Baselines.dave).toEqual({
      ForGw: 4, RealizedTenths: -15, Prices: {},
      Prev: {
        ForGw: 3, RealizedTenths: -15, Prices: {},
        Prev: { ForGw: 2, RealizedTenths: -15, Prices: {} },
      },
    });

    delete dates(db)[GW2_DATE]; // both days called off
    delete dates(db)[GW3_DATE];
    const pusher = new FakePusher();
    const t1 = new Date(afterLock3.getTime() + 60 * 60_000);
    await runLifecycleSweep(db, t1, undefined, { pusher }); // rewinds GW3
    expect(t(db).LockedWeeks[3]).toBeUndefined();
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
    await runLifecycleSweep(db, new Date(t1.getTime() + 15 * 60_000), undefined,
      { pusher }); // rewinds GW2

    expect(t(db).Baselines).toEqual({
      ...preLockBaselines(),
      dave: { ForGw: 2, RealizedTenths: -15, Prices: {} },
    });
    expect(t(db).LockedWeeks)
      .toEqual({ 1: { Date: GW1_DATE, LockAtUtc: LOCK1_MS, Scored: true } });
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: LOCK4_MS, date: GW4_DATE,
    });
    expect(calledOffSends(pusher).map((batch) => batch[0].body)).toEqual([
      'GW3 was called off — your team is open again until Sun, Jul 12 · 3:00 PM.',
      'GW2 was called off — your team is open again until Sun, Jul 12 · 3:00 PM.',
    ]);
  });

  it('[T4b] the rewind clears Voided/<n>; the void trigger that fires on the '
    + 'removal settles nothing', async () => {
    const db = await lockedGw2();
    t(db).Voided = { 2: true }; // the owner voided the day...
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    t(db).Config.SkippedDates = { [GW2_DATE]: true }; // ...then skipped it
    const settled = ['History/2', 'PlayerWeeks/2', 'PlayerWeekStats/2',
      'RecapSent/2', 'NewsDrafted/2', 'Leaderboards'];
    const realWrite = db.write.bind(db);
    const triggerWrites: string[][] = [];
    const fireTrigger = async () => {
      const before = db.writes.length;
      await resettleVoidToggle(db, {
        sport: 'Futsal', season: '15', gw: 2, nowUtc: LATER,
      });
      triggerWrites.push(db.writes.slice(before));
    };
    db.write = async (p: string, v: unknown) => {
      await realWrite(p, v);
      // onFantasyVoidWritten fires on the removal (true → absent).
      if (p === `${F_ROOT}/Voided/2` && v === null) await fireTrigger();
    };
    await runLifecycleSweep(db, LATER);
    expect(await db.read(`${F_ROOT}/Voided/2`)).toBeNull();
    expect(t(db).GwState).toMatchObject({ current: 2, status: 'open', date: GW3_DATE });
    // ...and once more after the rewind finished.
    db.write = realWrite;
    await fireTrigger();
    expect(triggerWrites).toEqual([[], []]);
    for (const p of settled) expect(await db.read(`${F_ROOT}/${p}`), p).toBeNull();
  });

  it('[T4e] a sweep that locked before a rewind never writes \'locked\' over '
    + 'the reopened week', async () => {
    const db = await lockedGw2();
    const pusher = new FakePusher();
    const realRead = db.read.bind(db);
    let rewound = false;
    db.read = async (p: string) => {
      // This sweep's lock step already passed; a concurrent sweep rewinds
      // GW2 before this one reaches its GwState upsert (step 2d reads
      // Live/Meta just before it).
      if (!rewound && p === `${F_ROOT}/Live/Meta`) {
        rewound = true;
        db.read = realRead;
        delete dates(db)[GW2_DATE];
        await runLifecycleSweep(db, LATER, undefined, { pusher });
      }
      return realRead(p);
    };
    await runLifecycleSweep(db, LATER);
    expect(rewound).toBe(true);
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: LOCK3_MS, date: GW3_DATE,
    });
    expect(calledOffSends(pusher)).toHaveLength(1);
  });
});

describe('the heal step while the week is open and unfrozen (rulings T3c, T3d)', () => {
  it('[T3c] a re-lock with no costs writes TransferCosts/<n> null over a stale node', async () => {
    const db = world();
    delete t(db).TransferState; // alpha's swap is free now: nobody owes anything
    t(db).TransferCosts = { 2: { alpha: 4 } }; // left by a cancelled lock
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
    expect(await db.read(`${F_ROOT}/TransferCosts/2`)).toBeNull();
    expect(db.writes).toContain(`${F_ROOT}/TransferCosts/2`);
  });

  it('[T3c] a stale ForGw L+1 baseline found while week L is open is restored '
    + 'from Prev (or removed) by the next sweep; a correct ForGw L node is left alone', async () => {
    const db = world();
    t(db).Baselines = {
      ...preLockBaselines(),
      // Landed by a stale lock write after a completed rewind.
      alpha: {
        ForGw: 3, RealizedTenths: 5, Prices: ALPHA_GW2,
        Prev: { ForGw: 2, RealizedTenths: 0, Prices: GW1_ALPHA },
      },
      erin: { ForGw: 3, RealizedTenths: 0, Prices: {} },
    };
    const spy = logSpy();
    await runLifecycleSweep(db, BEFORE_LOCK2, spy.log);
    expect(t(db).Baselines).toEqual(preLockBaselines());
    for (const uid of ['boost', 'churn', 'dave']) {
      expect(db.writes, uid).not.toContain(`${F_ROOT}/Baselines/${uid}`);
    }
    expect(spy.warns).toContain(
      'fantasy heal: a baseline written for a lock that never stood — restored');
  });

  it('[T3d] orphan PublishedPicks/LockedPositions/PriceHistory/TransferCosts of '
    + 'the open unfrozen week are deleted by the heal step', async () => {
    const db = world();
    t(db).PublishedPicks[2] = { alpha: fixtureSquad('alpha') };
    t(db).LockedPositions = { 2: { Sam: 'GK' } };
    t(db).PriceHistory = { 2: { Sam: 85 } };
    t(db).TransferCosts = { 2: { alpha: 4 } };
    const spy = logSpy();
    await runLifecycleSweep(db, BEFORE_LOCK2, spy.log);
    for (const n of SNAPSHOTS) expect(await db.read(`${F_ROOT}/${n}/2`), n).toBeNull();
    expect(await db.read(`${F_ROOT}/PublishedPicks/1`)).not.toBeNull();
    expect(spy.warns.filter((m) =>
      m === 'fantasy heal: orphan lock snapshot of the open week removed')).toHaveLength(4);
    // The real lock then takes its own snapshot.
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(t(db).PublishedPicks[2].alpha.picks[4].playerId).toBe('Ben');
  });

  it('[T3d] the heal keeps its hands off once a lock of the week has begun', async () => {
    const db = world();
    t(db).PublishedPicks[2] = { alpha: fixtureSquad('alpha') };
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      // A concurrent sweep freezes GW2 between our derivation and the heal.
      if (p === `${F_ROOT}/PublishedPicks/2` && t(db).LockedWeeks[2] === undefined) {
        t(db).LockedWeeks[2] = { Date: GW2_DATE, LockAtUtc: LOCK2_MS };
      }
      return realRead(p);
    };
    await runLifecycleSweep(db, BEFORE_LOCK2);
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
  });

  it('[T3d] a stale live node of the open week is removed', async () => {
    const db = world();
    t(db).Live = { Meta: { Gw: 2, State: 'live', ReadAt: 1, UpdatedAt: 1 }, Board: { alpha: 1 } };
    await runLifecycleSweep(db, BEFORE_LOCK2);
    expect(await db.read(`${F_ROOT}/Live`)).toBeNull();
    // The settled tombstone of the week before is no orphan.
    t(db).Live = { Meta: { Gw: 1, State: 'settled', UpdatedAt: 1 } };
    await runLifecycleSweep(db, BEFORE_LOCK2);
    expect(t(db).Live).toEqual({ Meta: { Gw: 1, State: 'settled', UpdatedAt: 1 } });
  });

  it('[T3d] a sweep whose lock step stopped as unfrozen writes no GwState', async () => {
    const db = world(); // GwState says GW2 open
    const realRead = db.read.bind(db);
    db.read = async (p: string) => {
      // A rewind marks GW2 between this sweep's derivation and its claim.
      if (p === `${F_ROOT}/LockedWeeks/2` && t(db).LockedWeeks[2] === undefined) {
        t(db).LockedWeeks[2] = { Date: GW2_DATE, LockAtUtc: LOCK2_MS, Rewinding: true };
      }
      return realRead(p);
    };
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(db.writes).not.toContain(`${F_ROOT}/GwState`);
    expect(t(db).GwState.status).toBe('open');
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).toBeNull();
  });

  /** Week 2's lock + finalize as a season that predates the ledger left
   *  them: snapshots, and every manager's finalize-written FOR-3 baseline
   *  (no Prev — finalize drops it). */
  const seedWeek2Settled = (db: FakeDb) => {
    const s = t(db);
    s.PublishedPicks[2] = { alpha: fixtureSquad('alpha') };
    s.LockedPositions = { 2: { Sam: 'GK' } };
    s.PriceHistory = { 2: { Sam: 85 } };
    s.TransferCosts = { 2: { alpha: 4 } };
    s.Baselines = {
      alpha: { ForGw: 3, RealizedTenths: 0, Prices: GW1_ALPHA },
      dave: { ForGw: 3, RealizedTenths: -15, Prices: {} },
    };
  };
  const week2Nodes = (db: FakeDb) => JSON.stringify(
    ['PublishedPicks', 'LockedPositions', 'PriceHistory', 'TransferCosts', 'Baselines']
      .map((n) => n === 'Baselines' ? t(db)[n] : t(db)[n]?.[2] ?? null));

  it('[T4d] a season with no ledger: a deleted past date renumbers the weeks, '
    + 'the open week carries a locked week\'s number — the heal does nothing', async () => {
    const db = world();
    delete t(db).LockedWeeks; // the season predates LockedWeeks
    seedWeek2Settled(db);
    const before = week2Nodes(db);
    const spy = logSpy();
    await runLifecycleSweep(db, BEFORE_LOCK2, spy.log);
    expect(week2Nodes(db)).toBe(before);
    expect(spy.warns.filter((m) => m.startsWith('fantasy heal'))).toEqual([]);
  });

  it('[T4d] History/<n> present → the heal does nothing', async () => {
    const db = world(); // GW1 frozen: GW2 open and unfrozen
    seedWeek2Settled(db);
    t(db).History[2] = { alpha: { ...fixtureSquad('alpha'), TotalTenths: 0 } };
    const before = week2Nodes(db);
    const spy = logSpy();
    await runLifecycleSweep(db, BEFORE_LOCK2, spy.log);
    expect(week2Nodes(db)).toBe(before);
    expect(spy.warns.filter((m) => m.startsWith('fantasy heal'))).toEqual([]);
  });
});

describe('upsertGwState', () => {
  const week = (date: string, lockMs: number): Gameweek => ({
    number: 2, date, lockUtc: new Date(lockMs),
    opensUtc: new Date(Date.UTC(2026, 5, 22, 7)), frozen: false,
  });
  const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

  it('[S3] clears ReminderSent when the open week\'s deadline moved later; keeps '
    + 'it when unchanged', async () => {
    const db = world();
    // Unchanged: nothing written at all.
    await upsertGwState(db, F_ROOT, week(GW2_DATE, LOCK2_MS), BEFORE_LOCK2, silent, {});
    expect(db.writes).toEqual([]);
    expect(t(db).ReminderSent[2]).toBeDefined();
    // Moved EARLIER: the reminder already sent still stands.
    await upsertGwState(db, F_ROOT,
      week(GW2_DATE, LOCK2_MS - 60 * 60_000), BEFORE_LOCK2, silent, {});
    expect(t(db).GwState.lockAtUtc).toBe(LOCK2_MS - 60 * 60_000);
    expect(t(db).ReminderSent[2]).toBeDefined();
    // Moved later: the reminder fires again for the new deadline.
    await upsertGwState(db, F_ROOT,
      week(GW2_DATE, LOCK2_MS + 60 * 60_000), BEFORE_LOCK2, silent, {});
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: LOCK2_MS + 60 * 60_000, date: GW2_DATE,
    });
    expect(t(db).ReminderSent?.[2]).toBeUndefined();
  });

  it('[S3] a new date for the same open week re-arms the reminder too', async () => {
    const db = world();
    await upsertGwState(db, F_ROOT, week(GW3_DATE, LOCK3_MS), BEFORE_LOCK2, silent, {});
    expect(t(db).GwState).toMatchObject({ current: 2, status: 'open', date: GW3_DATE });
    expect(t(db).ReminderSent?.[2]).toBeUndefined();
  });

  it('a locked week reads History for finalized, as the sweep always did', async () => {
    const db = world();
    t(db).LockedWeeks[2] = { Date: GW2_DATE, LockAtUtc: LOCK2_MS };
    await upsertGwState(db, F_ROOT, week(GW2_DATE, LOCK2_MS), AFTER_LOCK2, silent, {});
    expect(t(db).GwState.status).toBe('locked');
    expect(t(db).ReminderSent[2]).toBeDefined(); // only an OPEN week re-arms
    t(db).History[2] = { alpha: { ...fixtureSquad('alpha'), TotalTenths: 0 } };
    await upsertGwState(db, F_ROOT, week(GW2_DATE, LOCK2_MS), AFTER_LOCK2, silent, {});
    expect(t(db).GwState.status).toBe('finalized');
  });

  it.each([
    ['absent (a rewind removed it)', undefined],
    ['marked Rewinding', { Date: GW2_DATE, LockAtUtc: LOCK2_MS, Rewinding: true }],
    ['frozen on another date', { Date: GW3_DATE, LockAtUtc: LOCK3_MS }],
  ])('[T4e] \'locked\' is never written while LockedWeeks/<n> is %s', async (_label, entry) => {
    const db = world(); // GwState says GW2 open
    if (entry !== undefined) t(db).LockedWeeks[2] = entry;
    const spy = logSpy();
    await upsertGwState(db, F_ROOT, week(GW2_DATE, LOCK2_MS), AFTER_LOCK2, spy.log, {});
    expect(db.writes).toEqual([]);
    expect(t(db).GwState.status).toBe('open');
    expect(spy.infos).toContain(
      'fantasy sweep: week no longer frozen — GwState not marked locked');
  });
});

describe('refreshOpenGwState (the Config trigger)', () => {
  const refresh = (db: FakeDb, nowUtc: Date) => refreshOpenGwState(db, {
    sport: 'Futsal', season: '15', nowUtc,
  });

  it('a Deadlines change on the open week updates GwState.lockAtUtc', async () => {
    const db = world();
    const moved = LOCK2_MS + 2 * 60 * 60_000;
    t(db).Config.Deadlines = { [GW2_DATE]: moved };
    await refresh(db, BEFORE_LOCK2);
    expect(t(db).GwState).toEqual({
      current: 2, status: 'open', lockAtUtc: moved, date: GW2_DATE,
    });
    expect(t(db).ReminderSent?.[2]).toBeUndefined(); // re-armed for the new deadline
    expect(formatDeadlineInstant(moved)).toBe('Sun, Jun 28 · 5:00 PM');
  });

  it('a locked week is left alone (never rewound, never re-timed)', async () => {
    const db = await lockedGw2();
    t(db).Config.Deadlines = { [GW2_DATE]: LATER.getTime() + 2 * 60 * 60_000 };
    db.writes = [];
    await refresh(db, LATER);
    expect(db.writes).toEqual([]);
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
  });

  it.each([
    ['TestFill', (db: FakeDb) => { t(db).TestFill = { At: 1, Managers: 3 }; }],
    ['lockOverride \'open\'', (db: FakeDb) => { t(db).Config.lockOverride = 'open'; }],
    ['no Config', (db: FakeDb) => { delete t(db).Config; }],
  ])('%s → nothing', async (_label, setUp) => {
    const db = world();
    t(db).Config.Deadlines = { [GW2_DATE]: LOCK2_MS + 2 * 60 * 60_000 };
    setUp(db);
    db.writes = [];
    await refresh(db, BEFORE_LOCK2);
    expect(db.writes).toEqual([]);
  });
});

describe('scheduleConfigChanged (the Config trigger\'s zero-read gate)', () => {
  const base = { lockHour: 15, Reminder: { HoursBefore: 3 } };

  it('a Reminder edit (or any non-schedule key) → false', () => {
    expect(scheduleConfigChanged(base,
      { ...base, Reminder: { HoursBefore: 5 } })).toBe(false);
    expect(scheduleConfigChanged(base, { ...base, lockOverride: 'open' })).toBe(false);
    expect(scheduleConfigChanged(base, { ...base })).toBe(false);
  });

  it('a Deadlines edit → true; so are skips, the kickoff lead and the lock hour', () => {
    expect(scheduleConfigChanged(base,
      { ...base, Deadlines: { [GW2_DATE]: LOCK2_MS } })).toBe(true);
    expect(scheduleConfigChanged(
      { ...base, Deadlines: { [GW2_DATE]: LOCK2_MS } },
      { ...base, Deadlines: { [GW2_DATE]: LOCK2_MS + 1 } })).toBe(true);
    expect(scheduleConfigChanged(base,
      { ...base, SkippedDates: { [GW2_DATE]: true } })).toBe(true);
    expect(scheduleConfigChanged(base,
      { ...base, deadlineMinutesBeforeKickoff: 30 })).toBe(true);
    expect(scheduleConfigChanged(base, { ...base, lockHour: 14 })).toBe(true);
  });

  it('key order does not matter; Config created or removed counts', () => {
    expect(scheduleConfigChanged(
      { ...base, Deadlines: { [GW1_DATE]: 1, [GW2_DATE]: 2 } },
      { ...base, Deadlines: { [GW2_DATE]: 2, [GW1_DATE]: 1 } })).toBe(false);
    expect(scheduleConfigChanged(null, base)).toBe(true);
    expect(scheduleConfigChanged(base, null)).toBe(true);
    expect(scheduleConfigChanged(null, null)).toBe(false);
  });
});

// ── Final review (2026-11-05): finalize and rewind exclude each other ───────
// I1: both write LockedWeeks/<n>, so that node is the lock. The finalize's
// last check before its first official write is a TRANSACTION stamping
// `Finalizing: <now>` — refused while the rewind's mark is there, or when
// the entry it saw at its start is gone or re-dated. The rewind's mark
// refuses while a Finalizing stamp younger than 10 minutes is there; an
// older one is a finalize that died. I2: a skipped day is never scored for
// the first time. I4: a first finalize whose claim finds the week frozen on
// another date writes nothing.

const FINALIZING_REFUSED =
  'fantasy rewind: a finalize is scoring the week — the next sweep decides';
const FINALIZE_UNFROZEN =
  'fantasy finalize: week no longer frozen — standing down';
const FINALIZE_REWINDING_LINE =
  'fantasy finalize: week being rewound — standing down';
const FINALIZE_SKIPPED = 'fantasy finalize: game day skipped — not scored';
const FINALIZE_OTHER_DATE =
  'fantasy finalize: week frozen on another date — standing down';

const finalizeGw2 = (db: FakeDb, nowUtc: Date, log?: FantasyLogger) =>
  maybeFinalizeGame(db, {
    sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc, log,
  });

describe('[I1] finalize and rewind exclude each other on LockedWeeks/<n>', () => {
  it('a rewind that runs while a finalize writes refuses to mark the stamped '
    + 'week; the week scores whole and the stamp is cleared with Scored', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    const spy = logSpy();
    const realWrite = db.write.bind(db);
    let result: string | null = null;
    let stampAtHistory: unknown = null;
    db.write = async (p: string, v: unknown) => {
      if (result === null && p === `${F_ROOT}/History/2`) {
        result = 'running';
        stampAtHistory = t(db).LockedWeeks[2]?.Finalizing ?? null;
        // The owner deletes the day and a sweep's rewind runs right now.
        delete dates(db)[GW2_DATE];
        result = await rewind(db, LATER, { log: spy.log });
      }
      return realWrite(p, v);
    };
    await finalizeGw2(db, LATER, spy.log);

    expect(result).toBe('none');
    expect(stampAtHistory).toBe(LATER.getTime());
    expect(spy.infos).toContain(FINALIZING_REFUSED);
    expect(t(db).History[2]).toBeDefined();
    expect(t(db).LockedWeeks[2])
      .toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS, Scored: true });
    expect(await db.read(`${F_ROOT}/PublishedPicks/2`)).not.toBeNull();
    expect(t(db).CalledOff).toBeUndefined();
  });

  it('a rewind that marked the week first: the finalize stands down at its '
    + 'last check — no write at all, no stamp', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    const realRead = db.read.bind(db);
    let marked = false;
    db.read = async (p: string) => {
      if (!marked && p === `${F_ROOT}/DreamTeam/2`) {
        marked = true;
        // The sweep's mark lands while this finalize computes.
        delete dates(db)[GW2_DATE];
        await db.transaction(`${F_ROOT}/LockedWeeks/2`, (cur) =>
          cur === null ? null : { ...(cur as Json), Rewinding: true });
        db.writes = [];
      }
      return realRead(p);
    };
    const spy = logSpy();
    await finalizeGw2(db, LATER, spy.log);

    expect(marked).toBe(true);
    expect(db.writes).toEqual([]);
    expect(t(db).History[2]).toBeUndefined();
    expect(t(db).LockedWeeks[2]).toEqual(
      { Date: GW2_DATE, LockAtUtc: LOCK2_MS, Rewinding: true });
    expect(spy.infos).toContain(FINALIZE_REWINDING_LINE);
  });

  it('a whole rewind inside one finalize\'s compute: the finalize stands down '
    + 'and never resurrects LockedWeeks/2', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    const realRead = db.read.bind(db);
    let result: string | null = null;
    db.read = async (p: string) => {
      if (result === null && p === `${F_ROOT}/DreamTeam/2`) {
        result = 'running';
        db.read = realRead;
        delete dates(db)[GW2_DATE];
        result = await rewind(db, LATER);
        db.writes = [];
      }
      return realRead(p);
    };
    const spy = logSpy();
    await finalizeGw2(db, LATER, spy.log);

    expect(result).toBe('rewound');
    expect(db.writes).toEqual([]);
    expect(t(db).History[2]).toBeUndefined();
    expect(t(db).LockedWeeks).toEqual(
      { 1: { Date: GW1_DATE, LockAtUtc: LOCK1_MS, Scored: true } });
    expect(spy.warns).toContain(FINALIZE_UNFROZEN);
  });

  it('the ledger entry re-dated mid-finalize: the finalize stands down', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    const realRead = db.read.bind(db);
    let moved = false;
    db.read = async (p: string) => {
      if (!moved && p === `${F_ROOT}/DreamTeam/2`) {
        moved = true;
        t(db).LockedWeeks[2] = { Date: GW3_DATE, LockAtUtc: LOCK3_MS };
        db.writes = [];
      }
      return realRead(p);
    };
    const spy = logSpy();
    await finalizeGw2(db, LATER, spy.log);
    expect(moved).toBe(true);
    expect(db.writes).toEqual([]);
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW3_DATE, LockAtUtc: LOCK3_MS });
    expect(spy.warns).toContain(FINALIZE_UNFROZEN);
  });

  it('a fresh Finalizing stamp blocks the mark; a stale one (10 minutes or '
    + 'more: a finalize that died) does not', async () => {
    const db = await lockedGw2();
    delete dates(db)[GW2_DATE];
    t(db).LockedWeeks[2].Finalizing = LATER.getTime() - 9 * 60_000;
    const before = clone(t(db));
    const spy = logSpy();
    expect(await rewind(db, LATER, { log: spy.log })).toBe('none');
    expect(t(db)).toEqual(before);
    expect(spy.infos).toContain(FINALIZING_REFUSED);

    t(db).LockedWeeks[2].Finalizing = LATER.getTime() - 10 * 60_000;
    expect(await rewind(db, LATER)).toBe('rewound');
    await expectRewound(db);
  });

  it('a finalize that scores nobody clears its own stamp', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    delete t(db).PublishedPicks[2];
    delete t(db).Squads;
    const realTx = db.transaction.bind(db);
    const seen: unknown[] = [];
    db.transaction = async (p: string, update: (c: unknown) => unknown) => {
      const res = await realTx(p, update);
      if (p === `${F_ROOT}/LockedWeeks/2` && res.committed) seen.push(res.value);
      return res;
    };
    await finalizeGw2(db, LATER);
    expect(t(db).History[2]).toBeUndefined();
    expect(seen).toContainEqual(
      { Date: GW2_DATE, LockAtUtc: LOCK2_MS, Finalizing: LATER.getTime() });
    expect(t(db).LockedWeeks[2]).toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS });
  });

  it('a rerun of a scored week never stamps it', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    await finalizeGw2(db, LATER);
    expect(t(db).LockedWeeks[2])
      .toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS, Scored: true });
    const realTx = db.transaction.bind(db);
    const stamped: unknown[] = [];
    db.transaction = async (p: string, update: (c: unknown) => unknown) => {
      const res = await realTx(p, update);
      if (p === `${F_ROOT}/LockedWeeks/2` && res.committed) stamped.push(res.value);
      return res;
    };
    dates(db)[GW2_DATE][0].team1score = 7; // a late score correction
    db.writes = [];
    await finalizeGw2(db, LATER2);
    expect(db.writes).toContain(`${F_ROOT}/History/2`);
    expect(stamped).toEqual([]);
    expect(t(db).LockedWeeks[2])
      .toEqual({ Date: GW2_DATE, LockAtUtc: LOCK2_MS, Scored: true });
  });
});

describe('[I2] a skipped game day is never scored for the first time', () => {
  it('the match-day trigger stands down for a frozen week whose day is skipped',
    async () => {
      const db = await lockedGw2();
      t(db).Config.SkippedDates = { [GW2_DATE]: true };
      for (const g of dates(db)[GW2_DATE]) g.status = 2;
      db.writes = [];
      const spy = logSpy();
      await finalizeGw2(db, LATER, spy.log);
      expect(db.writes).toEqual([]);
      expect(t(db).History[2]).toBeUndefined();
      expect(spy.infos).toContain(FINALIZE_SKIPPED);
    });

  it('the sweep\'s backstop stands down too (a later week locked, so the '
    + 'rewind leaves this one be)', async () => {
    const db = await lockedGw2();
    const afterLock3 = new Date(LOCK3_MS + 60 * 60_000);
    await runLifecycleSweep(db, afterLock3); // GW3 locks
    expect(t(db).LockedWeeks[3]).toMatchObject({ Date: GW3_DATE });
    t(db).Config.SkippedDates = { [GW2_DATE]: true };
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    const spy = logSpy();
    await runLifecycleSweep(
      db, new Date(afterLock3.getTime() + 15 * 60_000), spy.log);
    expect(spy.infos).toContain('fantasy sweep: backstop finalize');
    expect(spy.infos).toContain(FINALIZE_SKIPPED);
    expect(t(db).History[2]).toBeUndefined();
    expect(await db.read(`${F_ROOT}/PlayerWeeks/2`)).toBeNull();
  });

  it('a rerun of a week already scored still re-settles after its day is '
    + 'skipped (a late score correction)', async () => {
    const db = await lockedGw2();
    for (const g of dates(db)[GW2_DATE]) g.status = 2;
    await finalizeGw2(db, LATER);
    expect(t(db).History[2]).toBeDefined();
    t(db).Config.SkippedDates = { [GW2_DATE]: true };
    dates(db)[GW2_DATE][0].team1score = 7;
    db.writes = [];
    await finalizeGw2(db, LATER2);
    expect(db.writes).toContain(`${F_ROOT}/History/2`);
  });
});

describe('[I4] a first finalize whose claim is refused writes nothing', () => {
  it('the week frozen on another date between the week list and the claim',
    async () => {
      const db = world(); // no sweep ever locked GW2: no snapshot, no entry
      for (const g of dates(db)[GW2_DATE]) g.status = 2;
      const realRead = db.read.bind(db);
      let hooked = false;
      db.read = async (p: string) => {
        if (!hooked && p === `${F_ROOT}/Players`) {
          hooked = true;
          // A sweep froze week 2 on another date meanwhile.
          t(db).LockedWeeks[2] = { Date: GW3_DATE, LockAtUtc: LOCK3_MS };
          db.writes = [];
        }
        return realRead(p);
      };
      const spy = logSpy();
      await finalizeGw2(db, LATER, spy.log);
      expect(hooked).toBe(true);
      expect(db.writes).toEqual([]);
      expect(t(db).History[2]).toBeUndefined();
      expect(t(db).LockedWeeks[2]).toEqual({ Date: GW3_DATE, LockAtUtc: LOCK3_MS });
      expect(spy.warns).toContain(FINALIZE_OTHER_DATE);
    });
});
