// Badge push on award creation (spec 2026-10-30 §4): one push per award,
// guarded by the once-only BadgePushClaims/<uid>/<awardId> claim — for auto
// AND manual awards. A paused season (lockOverride open/locked) computes no
// auto awards, so an auto award appearing there (the S15 test fill) is
// claimed as skipped and never pushes; a manual award still pushes once
// (Review Focus 4).

import { describe, expect, it } from 'vitest';
import { badgePushCopy, pushBadgeAward } from './badge_push';
import { catalogOf, STARTER_CATALOG } from './badges';
import { F_ROOT, FakeDb, FakePusher } from './test_support';

const NOW = new Date(Date.UTC(2026, 9, 30, 18));
const B = `${F_ROOT}/Badges`;
const C = `${F_ROOT}/BadgePushClaims`;

function world(opts: {
  award?: Record<string, unknown> | null;
  lockOverride?: string;
  catalog?: Record<string, unknown>;
} = {}): FakeDb {
  const award = opts.award === undefined
    ? { Badge: 'captainGenius', Gw: 3, At: 1, Source: 'auto' }
    : opts.award;
  return new FakeDb({
    Fantasy: {
      ...(opts.catalog ? { BadgeCatalog: opts.catalog } : {}),
      Futsal: {
        '15': {
          Config: { lockHour: 15, ...(opts.lockOverride ? { lockOverride: opts.lockOverride } : {}) },
          Badges: award === null ? {} : { u1: { a1: award } },
        },
      },
    },
  });
}

const push = (db: FakeDb, pusher: FakePusher, awardId = 'a1') =>
  pushBadgeAward(db, pusher, { sport: 'Futsal', season: '15', uid: 'u1', awardId, nowUtc: NOW });

describe('pushBadgeAward', () => {
  it('an auto award pushes once to its manager; the claim records the send', async () => {
    const db = world();
    const pusher = new FakePusher();
    expect(await push(db, pusher)).toEqual({ sent: 1 });
    expect(pusher.sends).toEqual([[{
      uid: 'u1',
      title: 'You earned Captain Genius 🏅',
      body: `Gameweek 3: ${STARTER_CATALOG.captainGenius.Description}`,
      data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '3', badge: 'a1' },
    }]]);
    expect(await db.read(`${C}/u1/a1`)).toEqual({ At: NOW.getTime(), Sent: 1 });

    // Re-fired (a retry, a re-created award after a rerun flip-flop): nothing.
    expect(await push(db, pusher)).toBeNull();
    expect(pusher.sends).toHaveLength(1);
  });

  it('a manual award pushes "You received a badge: <Name>" with the owner note — once', async () => {
    const db = world({
      award: { Badge: 'mvpMonth', At: 1, Source: 'manual', Note: '  MVP of October!  ', By: 'admin1' },
      catalog: { mvpMonth: { Name: 'MVP of the month', Description: 'Owner pick', Icon: 'star', Kind: 'manual' } },
    });
    const pusher = new FakePusher();
    expect(await push(db, pusher)).toEqual({ sent: 1 });
    expect(pusher.sends[0][0]).toMatchObject({
      title: 'You received a badge: MVP of the month',
      body: 'MVP of October!',
      data: { type: 'fantasy', sport: 'Futsal', season: '15', gw: '0', badge: 'a1' },
    });
    expect(await push(db, pusher)).toBeNull();
    expect(pusher.sends).toHaveLength(1);
  });

  it('paused season: a manual award still pushes once (Review Focus 4)', async () => {
    for (const lockOverride of ['open', 'locked']) {
      const db = world({
        lockOverride,
        award: { Badge: 'topOfTheWeek', Gw: 2, At: 1, Source: 'manual', By: 'admin1' },
      });
      const pusher = new FakePusher();
      expect(await push(db, pusher), lockOverride).toEqual({ sent: 1 });
      expect(await push(db, pusher), lockOverride).toBeNull();
      expect(pusher.sends, lockOverride).toHaveLength(1);
    }
  });

  it('paused season: an auto award (test-fill data) never pushes — claimed as skipped', async () => {
    const db = world({ lockOverride: 'open' });
    const pusher = new FakePusher();
    expect(await push(db, pusher)).toBeNull();
    expect(pusher.sends).toEqual([]);
    expect(await db.read(`${C}/u1/a1`)).toEqual({ At: NOW.getTime(), Skipped: 'paused' });
  });

  // Audit I5 follow-up: a TestFill season never pushes — auto or manual,
  // even under lockOverride auto (a Resume Auto on the filled season).
  it('TestFill season: no award pushes — claimed as { At, Skipped: testfill }', async () => {
    for (const award of [
      { Badge: 'captainGenius', Gw: 3, At: 1, Source: 'auto' },
      { Badge: 'topOfTheWeek', Gw: 2, At: 1, Source: 'manual', By: 'admin1' },
    ]) {
      const db = world({ award });
      db.data.Fantasy.Futsal['15'].TestFill = { At: 1, Managers: 20 };
      const pusher = new FakePusher();
      const infos: Array<{ message: string; context?: Record<string, unknown> }> = [];
      const log = {
        info: (message: string, context?: Record<string, unknown>) => { infos.push({ message, context }); },
        warn: () => undefined,
      };
      const run = () => pushBadgeAward(db, pusher, {
        sport: 'Futsal', season: '15', uid: 'u1', awardId: 'a1', nowUtc: NOW, log,
      });
      expect(await run(), award.Source).toBeNull();
      expect(pusher.sends, award.Source).toEqual([]);
      expect(await db.read(`${C}/u1/a1`), award.Source)
        .toEqual({ At: NOW.getTime(), Skipped: 'testfill' });
      expect(infos, award.Source).toContainEqual({
        message: 'fantasy: TestFill season — engine stands down',
        context: { sport: 'Futsal', season: '15', uid: 'u1', awardId: 'a1', job: 'badgePush' },
      });
      // Re-fired: still nothing, the claim stays as it was.
      expect(await run(), award.Source).toBeNull();
      expect(pusher.sends, award.Source).toEqual([]);
      expect(await db.read(`${C}/u1/a1`), award.Source)
        .toEqual({ At: NOW.getTime(), Skipped: 'testfill' });

      // Control: the same award in the same season unmarked pushes once.
      const unmarked = world({ award });
      expect(await push(unmarked, pusher), award.Source).toEqual({ sent: 1 });
      pusher.sends.length = 0;
    }
  });

  it('a claim that already exists (the fill writes claims before badges) stops the push', async () => {
    const db = world();
    await db.write(`${C}/u1/a1`, { At: 1, Sent: 1 });
    const pusher = new FakePusher();
    expect(await push(db, pusher)).toBeNull();
    expect(pusher.sends).toEqual([]);
  });

  it('an award removed before the trigger ran is not pushed and claims nothing', async () => {
    const db = world({ award: null });
    const pusher = new FakePusher();
    expect(await push(db, pusher)).toBeNull();
    expect(await db.read(`${C}/u1/a1`)).toBeNull();
  });
});

describe('badgePushCopy', () => {
  const catalog = catalogOf(null);

  it('season awards name the season; unknown badges fall back gracefully', () => {
    expect(badgePushCopy({ Badge: 'champion', Source: 'auto' }, catalog, '15')).toEqual({
      title: 'You earned Champion 🏅',
      body: `Season 15: ${STARTER_CATALOG.champion.Description}`,
    });
    expect(badgePushCopy({ Badge: 'gone', Source: 'auto', Gw: 4 }, catalog, '15'))
      .toEqual({ title: 'You earned a badge 🏅', body: 'Gameweek 4' });
    expect(badgePushCopy({ Badge: 'gone', Source: 'manual' }, catalog, '15'))
      .toEqual({ title: 'You received a badge', body: 'Infinite Fantasy' });
    // A manual award without a note says what the badge is for.
    expect(badgePushCopy({ Badge: 'benchBoss', Source: 'manual' }, catalog, '15'))
      .toEqual({
        title: 'You received a badge: Bench Boss',
        body: STARTER_CATALOG.benchBoss.Description,
      });
  });
});
