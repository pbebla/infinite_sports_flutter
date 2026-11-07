// Achievement badges (spec 2026-10-30-fantasy-badges-design.md §2–§4): the
// pure rules over hand-built squads, the reconcile that makes a finalize
// rerun match the new scores exactly (added AND removed, manual awards never
// touched), the season-end awards + the trophy-cabinet copy, the catalog
// seeding, and the finalize/sweep hooks over the in-memory FantasyDb.
//
// HAND MATH for the world2 (test_support.ts) end-to-end block — GW2 replays
// the golden games; week points (bonus-inclusive): Sam 9, Dana 13, Alex 12,
// Wes 1, Will -4, Wren 3, Eli 0, Eva -3, Ezra 0 (absent), Bo 12, Bea 15,
// Ben 9. Team of the Week: Bo, Bea, Dana, Alex, Ben. GW2 nets: alpha 35,
// boost 45 (its replayed benchBoost is voided at the lock), churn 59.
// - alpha (cap Ezra absent): captain 0 -> no Captain Genius; TOTW held Dana,
//   Alex = 2; bench Will -4 <= Eva -3 (DEF starters who played), Wren 3 <=
//   Alex 12 (Ezra did not play) -> Bench Boss.
// - boost (cap Bea 15 >= 9, -4, 9, 3) -> Captain Genius; TOTW Bea, Ben = 2;
//   bench Eva -3 > Will -4 -> no Bench Boss.
// - churn (cap Ben 9 < Bo 12): TOTW Bo, Dana, Bea, Ben = 4 -> Crystal Ball;
//   bench Eva -3 <= Dana/Bea, Wren 3 <= Ben 9 -> Bench Boss; 59 -> Top of
//   the Week. Three managers -> nobody owns anything below 10%: no Hidden Gem.
// - Score correction (Bea marked absent in GW2): Bea 0, not played; g2 bonus
//   Ben 3 / Bo 2 / Eli 1 -> Ben 10, Bo 13, Eli 1. TOTW Bo, Dana, Eva (-3
//   beats Will -4), Alex, Ben. boost loses Captain Genius (captain absent);
//   alpha gains Crystal Ball (Dana, Eva, Alex). Nets: churn 46 (Bo 13 + Dana
//   13 + Eva subbed -3 + Wren subbed 3 + Ben cap 20), alpha 36, boost 25.
// - Season (GW1 stored 35 / 44 / 59): Overall churn 118, boost 89, alpha 70
//   -> churn Champion, boost Runner-up, alpha Third; after the correction
//   churn 105, alpha 71, boost 69 -> alpha Runner-up, boost Third.

import { describe, expect, it } from 'vitest';
import {
  BADGE_CATALOG_PATH, cabinetAwardFor, catalogOf, CatalogEntry,
  deterministicAwardId, leagueDateKey, reconcileAwards, seasonAutoAwards,
  SEASON_RULES, seedBadgeCatalog, settleSeasonBadges, settleWeeklyBadges,
  STARTER_CATALOG, weeklyAutoAwards, WeeklyAwardsInput,
} from './badges';
import { clone, Json } from './golden_fixture';
import {
  maybeFinalizeGame, resettleVoidToggle, runLifecycleSweep,
} from './orchestration';
import { configFromMap } from './fantasy_config';
import {
  AFTER_LOCK2, F_ROOT, FakeDb, GW1_DATE, GW2_DATE, world2,
} from './test_support';

const NOW_MS = Date.UTC(2026, 5, 29, 3);

function pick(playerId: string, position: string, bench = false) {
  return { playerId, position, priceTenths: 50, bench };
}

/** A 5+2 futsal squad: [gk, def1, def2, att1, att2] starters and
 *  [benchDef, benchAtt]; captain/vice by id. */
function squad(
  starters: [string, string, string, string, string],
  bench: [string, string],
  captainId: string, viceId: string, chip?: string,
): Json {
  return {
    picks: [
      pick(starters[0], 'GK'), pick(starters[1], 'DEF'), pick(starters[2], 'DEF'),
      pick(starters[3], 'ATT'), pick(starters[4], 'ATT'),
      pick(bench[0], 'DEF', true), pick(bench[1], 'ATT', true),
    ],
    captainId, viceId, ...(chip ? { chip } : {}),
  };
}

const ALL = ['G1', 'D1', 'D2', 'A1', 'A2', 'BD', 'BA'];

/** A one-manager week: everyone played, [pts] per player (default 1). */
function week(over: Partial<WeeklyAwardsInput> = {}): WeeklyAwardsInput {
  return {
    gw: 3,
    squadsByUid: { u1: squad(['G1', 'D1', 'D2', 'A1', 'A2'], ['BD', 'BA'], 'A1', 'A2') },
    playerWeeks: Object.fromEntries(ALL.map((n) => [n, 1])),
    playedByName: Object.fromEntries(ALL.map((n) => [n, true])),
    dreamTeamNames: [],
    gameweekBoard: { u1: { points: 10, rank: 2 } },
    voided: false,
    catalog: catalogOf(null),
    nowMs: NOW_MS,
    ...over,
  };
}

function badgesOf(input: WeeklyAwardsInput, uid = 'u1'): string[] {
  return Object.keys(weeklyAutoAwards(input)[uid] ?? {}).sort();
}

describe('starter catalog (spec §2/§3, coordinator icon keys)', () => {
  it('seeds the nine starter badges in table order with the agreed icons', () => {
    expect(Object.keys(STARTER_CATALOG)).toEqual([
      'captainGenius', 'crystalBall', 'benchBoss', 'hiddenGem', 'topOfTheWeek',
      'everPresent', 'champion', 'runnerUp', 'thirdPlace',
    ]);
    const icons = Object.fromEntries(
      Object.entries(STARTER_CATALOG).map(([id, e]) => [id, e.Icon]));
    expect(icons).toEqual({
      captainGenius: 'military_tech', crystalBall: 'auto_awesome',
      benchBoss: 'event_seat', hiddenGem: 'diamond', topOfTheWeek: 'emoji_events',
      everPresent: 'calendar_month', champion: 'workspace_premium',
      runnerUp: 'looks_two', thirdPlace: 'looks_3',
    });
    expect(Object.values(STARTER_CATALOG).map((e) => e.Order))
      .toEqual([10, 20, 30, 40, 50, 60, 70, 80, 90]);
    for (const [id, e] of Object.entries(STARTER_CATALOG)) {
      expect(Object.keys(e).sort()).toEqual([
        'Active', 'Description', 'Icon', 'Kind', 'Name', 'Order', 'Repeatable', 'Rule',
      ]);
      expect(e.Kind).toBe('auto');
      expect(e.Rule).toBe(id);
      expect(e.Active).toBe(true);
      expect(e.Description.length).toBeGreaterThan(10);
    }
    expect(STARTER_CATALOG.captainGenius.Name).toBe('Captain Genius');
    expect(STARTER_CATALOG.runnerUp.Name).toBe('Runner-up');
    expect(STARTER_CATALOG.thirdPlace.Name).toBe('Third place');
    // Weekly badges repeat; season badges are once per season.
    expect(Object.entries(STARTER_CATALOG).filter(([, e]) => e.Repeatable)
      .map(([id]) => id))
      .toEqual(['captainGenius', 'crystalBall', 'benchBoss', 'hiddenGem', 'topOfTheWeek']);
  });

  it('catalogOf: stored entries win over the starter set; junk tolerated', () => {
    const c = catalogOf({
      captainGenius: { ...STARTER_CATALOG.captainGenius, Name: 'Armband Ace', Active: false },
      mvpMonth: { Name: 'MVP of the month', Kind: 'manual', Icon: 'star' },
      broken: 'not a map',
      weird: { Name: 'Weird', Kind: 'auto', Rule: 'noSuchRule' },
    });
    expect(c.captainGenius.Name).toBe('Armband Ace');
    expect(c.captainGenius.Active).toBe(false);
    expect(c.benchBoss).toEqual(STARTER_CATALOG.benchBoss); // never stored: starter
    expect(c.mvpMonth).toMatchObject({
      Name: 'MVP of the month', Kind: 'manual', Active: true, Repeatable: true,
    });
    expect(c.mvpMonth.Rule).toBeUndefined();
    expect(c.broken).toBeUndefined();
    expect(c.weird.Rule).toBeUndefined(); // an unknown rule never auto-awards
  });
});

describe('weekly rules (hand-built squads)', () => {
  it('Captain Genius: captain >= every other starter, ties count, > 0 needed', () => {
    const pts = (cap: number, other: number, bench = 0) => week({
      playerWeeks: { G1: 1, D1: 2, D2: other, A1: cap, A2: 3, BD: bench, BA: 0 },
    });
    expect(badgesOf(pts(9, 5))).toContain('captainGenius_gw3');
    expect(badgesOf(pts(9, 9))).toContain('captainGenius_gw3'); // tied: still a genius
    expect(badgesOf(pts(9, 10))).not.toContain('captainGenius_gw3');
    // Only STARTERS compete: a bench player outscoring the captain is fine.
    expect(badgesOf(pts(9, 5, 20))).toContain('captainGenius_gw3');
    // > 0: a zero captain is never a genius, even when everyone else is <= 0.
    expect(badgesOf(week({
      playerWeeks: { G1: 0, D1: -1, D2: 0, A1: 0, A2: -2, BD: 0, BA: 0 },
    }))).not.toContain('captainGenius_gw3');
  });

  it('Captain Genius: an absent captain (0 raw) is not a genius — the vice never counts', () => {
    const input = week({
      playerWeeks: { G1: 1, D1: 1, D2: 1, A1: 0, A2: 12, BD: 0, BA: 0 },
      playedByName: { ...week().playedByName, A1: false },
    });
    expect(badgesOf(input)).not.toContain('captainGenius_gw3');
  });

  it('Crystal Ball: >= 3 Team of the Week players anywhere in the squad (bench too)', () => {
    expect(badgesOf(week({ dreamTeamNames: ['G1', 'D1', 'BD', 'X', 'Y'] })))
      .toContain('crystalBall_gw3');
    expect(badgesOf(week({ dreamTeamNames: ['G1', 'BD', 'X', 'Y', 'Z'] })))
      .not.toContain('crystalBall_gw3');
  });

  it('Bench Boss: no played bench player outscored a played same-position starter', () => {
    // BD 3 vs DEF starters D1 4 / D2 3 (ties fine); BA 2 vs ATT A1 5, A2 2.
    const base = { G1: 1, D1: 4, D2: 3, A1: 5, A2: 2, BD: 3, BA: 2 };
    expect(badgesOf(week({ playerWeeks: base }))).toContain('benchBoss_gw3');
    // BD outscores D2 -> no.
    expect(badgesOf(week({ playerWeeks: { ...base, BD: 4 } }))).not.toContain('benchBoss_gw3');
    // A bench DEF outscoring an ATT starter is fine (same position only).
    expect(badgesOf(week({ playerWeeks: { ...base, BD: 3, A2: 2 } }))).toContain('benchBoss_gw3');
    // A starter who did NOT play is not compared: D2 absent (0), BD auto-subbed 3.
    expect(badgesOf(week({
      playerWeeks: { ...base, D2: 0, BD: 3 },
      playedByName: { ...week().playedByName, D2: false },
    }))).toContain('benchBoss_gw3');
  });

  it('Bench Boss: needs a bench player who played; never in a Bench Boost week', () => {
    const base = { G1: 1, D1: 4, D2: 3, A1: 5, A2: 2, BD: 1, BA: 1 };
    expect(badgesOf(week({
      playerWeeks: base,
      playedByName: { ...week().playedByName, BD: false, BA: false },
    }))).not.toContain('benchBoss_gw3');
    const boosted = squad(['G1', 'D1', 'D2', 'A1', 'A2'], ['BD', 'BA'], 'A1', 'A2', 'benchBoost');
    expect(badgesOf(week({ playerWeeks: base, squadsByUid: { u1: boosted } })))
      .not.toContain('benchBoss_gw3');
  });

  it('Free Hit / Wildcard / Triple Captain weeks score every rule normally (Review Focus 3)', () => {
    const base = { G1: 1, D1: 4, D2: 3, A1: 5, A2: 2, BD: 1, BA: 1 };
    for (const chip of ['freeHit', 'wildcard', 'tripleCaptain']) {
      const s = squad(['G1', 'D1', 'D2', 'A1', 'A2'], ['BD', 'BA'], 'A1', 'A2', chip);
      expect(badgesOf(week({ playerWeeks: base, squadsByUid: { u1: s } })), chip)
        .toEqual(['benchBoss_gw3', 'captainGenius_gw3']);
    }
  });

  /** [managers] squads: u1 holds the gem G (a starter), the rest hold
   *  [heldByOthers] of them as well. */
  function gemWeek(gemPts: number, managers: number, heldByOthers: number,
    gemOnBench = false): WeeklyAwardsInput {
    const squadsByUid: Record<string, unknown> = {
      u1: gemOnBench
        ? squad(['G1', 'D1', 'D2', 'A1', 'A2'], ['BD', 'GEM'], 'A1', 'A2')
        : squad(['G1', 'D1', 'D2', 'GEM', 'A2'], ['BD', 'BA'], 'A2', 'D1'),
    };
    for (let i = 2; i <= managers; i++) {
      const att = i - 2 < heldByOthers ? 'GEM' : `X${i}`;
      squadsByUid[`u${i}`] = squad(['G1', 'D1', 'D2', att, 'A2'], ['BD', 'BA'], 'A2', 'D1');
    }
    return week({
      squadsByUid,
      playerWeeks: { ...week().playerWeeks, GEM: gemPts },
      playedByName: { ...week().playedByName, GEM: true },
      gameweekBoard: {},
    });
  }

  it('Hidden Gem: a starter on >= 10 raw points owned by < 10% of the week\'s managers', () => {
    // 11 managers, only u1 holds GEM: 1/11 = 9.09% < 10%, exactly 10 pts.
    expect(badgesOf(gemWeek(10, 11, 0))).toContain('hiddenGem_gw3');
    // 9 points is not enough.
    expect(badgesOf(gemWeek(9, 11, 0))).not.toContain('hiddenGem_gw3');
    // Exactly 10% (1 of 10 managers) is NOT under 10%.
    expect(badgesOf(gemWeek(10, 10, 0))).not.toContain('hiddenGem_gw3');
    // 2 of 21 = 9.52% -> still a gem (exact math, never a rounded percent).
    expect(badgesOf(gemWeek(15, 21, 1))).toContain('hiddenGem_gw3');
    expect(badgesOf(gemWeek(15, 21, 1), 'u2')).toContain('hiddenGem_gw3');
    // 2 of 20 = 10% -> no.
    expect(badgesOf(gemWeek(15, 20, 1))).not.toContain('hiddenGem_gw3');
    // A benched gem never counts.
    expect(badgesOf(gemWeek(15, 11, 0, true))).not.toContain('hiddenGem_gw3');
  });

  it('Top of the Week: gameweek rank 1, every tied manager wins', () => {
    const input = week({
      squadsByUid: {
        u1: week().squadsByUid['u1'], u2: week().squadsByUid['u1'],
        u3: week().squadsByUid['u1'],
      },
      gameweekBoard: {
        u1: { points: 50, rank: 1 }, u2: { points: 50, rank: 1 },
        u3: { points: 40, rank: 3 },
      },
    });
    const out = weeklyAutoAwards(input);
    expect(Object.keys(out['u1'])).toContain('topOfTheWeek_gw3');
    expect(Object.keys(out['u2'])).toContain('topOfTheWeek_gw3');
    expect(Object.keys(out['u3'] ?? {})).not.toContain('topOfTheWeek_gw3');
  });

  it('award rows are { Badge, Gw, At, Source:auto } under <badgeId>_gw<N>', () => {
    const out = weeklyAutoAwards(week({
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
    }));
    expect(out['u1']['captainGenius_gw3']).toEqual({
      Badge: 'captainGenius', Gw: 3, At: NOW_MS, Source: 'auto',
    });
  });

  it('a voided week awards nothing at all', () => {
    expect(weeklyAutoAwards(week({
      voided: true,
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
      gameweekBoard: { u1: { points: 10, rank: 1 } },
    }))).toEqual({});
  });

  it('catalog: Active:false is not awarded; an owner auto badge on a known rule is; manual never', () => {
    const catalog = catalogOf({
      captainGenius: { ...STARTER_CATALOG.captainGenius, Active: false },
      armbandKing: {
        Name: 'Armband King', Description: 'x', Icon: 'star', Kind: 'auto',
        Rule: 'captainGenius', Repeatable: true, Order: 100, Active: true,
      },
      handGiven: {
        Name: 'Hand given', Description: 'x', Icon: 'star', Kind: 'manual',
        Rule: 'captainGenius', Repeatable: true, Order: 110, Active: true,
      },
    });
    const ids = badgesOf(week({
      catalog,
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
    }));
    expect(ids).toContain('armbandKing_gw3');
    expect(ids).not.toContain('captainGenius_gw3');
    expect(ids).not.toContain('handGiven_gw3');
  });

  it('a malformed squad is skipped, never fatal', () => {
    const out = weeklyAutoAwards(week({
      squadsByUid: { u1: week().squadsByUid['u1'], bad: { picks: 'nope' } },
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
    }));
    expect(out['bad']).toBeUndefined();
    expect(Object.keys(out['u1'])).toContain('captainGenius_gw3');
  });
});

describe('season rules', () => {
  const catalog = catalogOf(null);

  it('Champion / Runner-up / Third place on competition ranks — ties share', () => {
    const out = seasonAutoAwards({
      overallBoard: { a: { rank: 1 }, b: { rank: 1 }, c: { rank: 3 }, d: { rank: 4 } },
      historyWeeksByUid: {},
      allWeeks: [1, 2],
      catalog,
      nowMs: NOW_MS,
    });
    expect(out['a']).toEqual({ champion_season: { Badge: 'champion', At: NOW_MS, Source: 'auto' } });
    expect(Object.keys(out['b'])).toEqual(['champion_season']);
    expect(Object.keys(out['c'])).toEqual(['thirdPlace_season']); // nobody is 2nd
    expect(out['d']).toBeUndefined();
  });

  it('a tie for second gives two Runner-ups and no Third place', () => {
    const out = seasonAutoAwards({
      overallBoard: { a: { rank: 1 }, b: { rank: 2 }, c: { rank: 2 }, d: { rank: 4 } },
      historyWeeksByUid: {}, allWeeks: [1], catalog, nowMs: NOW_MS,
    });
    expect(Object.keys(out['b'])).toEqual(['runnerUp_season']);
    expect(Object.keys(out['c'])).toEqual(['runnerUp_season']);
    expect(out['d']).toBeUndefined();
  });

  it('Ever Present: a scored team in EVERY gameweek of the season', () => {
    const out = seasonAutoAwards({
      overallBoard: {},
      historyWeeksByUid: { a: [1, 2, 3], b: [1, 3], c: [3, 2, 1, 4] },
      allWeeks: [1, 2, 3],
      catalog, nowMs: NOW_MS,
    });
    expect(Object.keys(out['a'])).toEqual(['everPresent_season']);
    expect(out['b']).toBeUndefined();
    expect(Object.keys(out['c'])).toEqual(['everPresent_season']);
  });

  it('inactive season badges are not awarded', () => {
    const out = seasonAutoAwards({
      overallBoard: { a: { rank: 1 } },
      historyWeeksByUid: { a: [1] },
      allWeeks: [1],
      catalog: catalogOf({ champion: { ...STARTER_CATALOG.champion, Active: false } }),
      nowMs: NOW_MS,
    });
    expect(Object.keys(out['a'])).toEqual(['everPresent_season']);
  });
});

describe('reconcileAwards (rerun-exact, manual untouched)', () => {
  const catalog = catalogOf(null);
  const row = (Badge: string, Gw?: number, Source = 'auto') =>
    ({ Badge, ...(Gw !== undefined ? { Gw } : {}), At: 1, Source });

  it('adds what is newly earned, removes auto awards no longer earned, keeps the rest as stored', () => {
    const existing = {
      u1: {
        captainGenius_gw3: row('captainGenius', 3), // no longer earned
        benchBoss_gw3: { ...row('benchBoss', 3), At: 42 }, // still earned: kept as is
        captainGenius_gw2: row('captainGenius', 2), // another week: not ours
        '-Mmanual1': { ...row('captainGenius', 3, 'manual'), Note: 'Nice', By: 'admin1' },
      },
    };
    const desired = {
      u1: { benchBoss_gw3: { Badge: 'benchBoss', Gw: 3, At: 99, Source: 'auto' as const } },
      u2: { crystalBall_gw3: { Badge: 'crystalBall', Gw: 3, At: 99, Source: 'auto' as const } },
    };
    const changes = reconcileAwards({
      existing, desired, catalog, scope: { kind: 'week', gw: 3, voided: false },
    });
    expect(changes.removes.map((r) => `${r.uid}/${r.awardId}`)).toEqual(['u1/captainGenius_gw3']);
    expect(changes.writes.map((w) => `${w.uid}/${w.awardId}`)).toEqual(['u2/crystalBall_gw3']);
  });

  it('an inactive badge\'s existing award stays; a voided week removes every auto award of that week', () => {
    const inactive = catalogOf({ benchBoss: { ...STARTER_CATALOG.benchBoss, Active: false } });
    const existing = {
      u1: {
        benchBoss_gw3: row('benchBoss', 3),
        topOfTheWeek_gw3: row('topOfTheWeek', 3),
        '-Mmanual1': row('benchBoss', 3, 'manual'),
        topOfTheWeek_gw4: row('topOfTheWeek', 4),
      },
    };
    const normal = reconcileAwards({
      existing, desired: {}, catalog: inactive, scope: { kind: 'week', gw: 3, voided: false },
    });
    expect(normal.removes.map((r) => r.awardId)).toEqual(['topOfTheWeek_gw3']);
    const voided = reconcileAwards({
      existing, desired: {}, catalog: inactive, scope: { kind: 'week', gw: 3, voided: true },
    });
    expect(voided.removes.map((r) => r.awardId).sort())
      .toEqual(['benchBoss_gw3', 'topOfTheWeek_gw3']);
  });

  it('never overwrites a stored row at the same id (a manual row included)', () => {
    const changes = reconcileAwards({
      existing: { u1: { benchBoss_gw3: row('benchBoss', 3, 'manual') } },
      desired: { u1: { benchBoss_gw3: { Badge: 'benchBoss', Gw: 3, At: 9, Source: 'auto' } } },
      catalog, scope: { kind: 'week', gw: 3, voided: false },
    });
    expect(changes).toEqual({ writes: [], removes: [] });
  });

  it('Repeatable:false weekly badge: only while the manager holds no other auto award of it', () => {
    const once = catalogOf({ topOfTheWeek: { ...STARTER_CATALOG.topOfTheWeek, Repeatable: false } });
    const desired = { u1: { topOfTheWeek_gw4: { Badge: 'topOfTheWeek', Gw: 4, At: 9, Source: 'auto' as const } } };
    const held = reconcileAwards({
      existing: { u1: { topOfTheWeek_gw2: row('topOfTheWeek', 2) } },
      desired, catalog: once, scope: { kind: 'week', gw: 4, voided: false },
    });
    expect(held.writes).toEqual([]);
    const fresh = reconcileAwards({
      existing: { u1: { '-Mm': row('topOfTheWeek', 2, 'manual') } },
      desired, catalog: once, scope: { kind: 'week', gw: 4, voided: false },
    });
    expect(fresh.writes.map((w) => w.awardId)).toEqual(['topOfTheWeek_gw4']);
  });

  it('season scope owns only <badgeId>_season auto awards of active season badges', () => {
    const changes = reconcileAwards({
      existing: {
        u1: { champion_season: row('champion'), topOfTheWeek_gw3: row('topOfTheWeek', 3) },
        u2: { '-Mm': row('champion', undefined, 'manual') },
      },
      desired: { u3: { champion_season: { Badge: 'champion', At: 9, Source: 'auto' } } },
      catalog, scope: { kind: 'season' },
    });
    expect(changes.removes.map((r) => `${r.uid}/${r.awardId}`)).toEqual(['u1/champion_season']);
    expect(changes.writes.map((w) => `${w.uid}/${w.awardId}`)).toEqual(['u3/champion_season']);
  });
});

describe('trophy cabinet copy', () => {
  it('deterministicAwardId is the Manager award_engine.dart port', () => {
    expect(deterministicAwardId('fantasy_champion', 'fantasy', 'Futsal/15', '15'))
      .toBe('fantasy_champion_fantasy_Futsal_15_15');
    expect(deterministicAwardId('fantasy_runnerUp', 'fantasy', 'Flag Football/3', '3'))
      .toBe('fantasy_runnerUp_fantasy_Flag_Football_3_3');
    expect(deterministicAwardId('a.b#c$d[e]f', 'x\ty', 'z', '1'))
      .toBe('a_b_c_d_e_f_x_y_z_1');
  });

  it('cabinet rows for the podium badges only, in the Award shape', () => {
    const at = { sport: 'Futsal', season: '15', dateKey: '06292026' };
    expect(cabinetAwardFor({ badgeId: 'champion', entry: STARTER_CATALOG.champion, ...at }))
      .toEqual({
        id: 'fantasy_champion_fantasy_Futsal_15_15',
        row: {
          TrophyId: 'fantasy_champion', Name: 'Champion', Icon: 'trophy_gold',
          IconType: 'builtin', Tier: 'gold', Sport: 'Futsal', ScopeType: 'fantasy',
          ScopeId: 'Futsal/15', Season: '15', Edition: '', Context: 'Infinite Fantasy',
          Date: '06292026', Source: 'auto',
        },
      });
    expect(cabinetAwardFor({ badgeId: 'runnerUp', entry: STARTER_CATALOG.runnerUp, ...at })?.row)
      .toMatchObject({ Tier: 'silver', Icon: 'medal', TrophyId: 'fantasy_runnerUp' });
    expect(cabinetAwardFor({ badgeId: 'thirdPlace', entry: STARTER_CATALOG.thirdPlace, ...at })?.row)
      .toMatchObject({ Tier: 'bronze', Icon: 'medal' });
    expect(cabinetAwardFor({ badgeId: 'everPresent', entry: STARTER_CATALOG.everPresent, ...at }))
      .toBeNull();
  });

  it('leagueDateKey is the league-local calendar date', () => {
    // 2026-06-29 03:00Z = Jun 28 8 PM PDT.
    expect(leagueDateKey(new Date(NOW_MS))).toBe('06282026');
    // 2026-12-01 07:30Z = Nov 30 11:30 PM PST.
    expect(leagueDateKey(new Date(Date.UTC(2026, 11, 1, 7, 30)))).toBe('11302026');
  });
});

describe('catalog seeding (set-if-absent, owner edits survive)', () => {
  it('writes every missing starter entry once; a stored (edited) one is never overwritten', async () => {
    const db = new FakeDb({
      Fantasy: { BadgeCatalog: { benchBoss: { ...STARTER_CATALOG.benchBoss, Name: 'Bench Genius', Active: false } } },
    });
    const n = await seedBadgeCatalog(db, await db.read(BADGE_CATALOG_PATH));
    expect(n).toBe(8);
    const stored = await db.read(BADGE_CATALOG_PATH) as Record<string, CatalogEntry>;
    expect(stored.benchBoss.Name).toBe('Bench Genius');
    expect(stored.benchBoss.Active).toBe(false);
    expect(stored.captainGenius).toEqual(STARTER_CATALOG.captainGenius);
    db.writes = [];
    expect(await seedBadgeCatalog(db, await db.read(BADGE_CATALOG_PATH))).toBe(0);
    expect(db.writes).toEqual([]);
  });

  it('every sweep run seeds it — even when every season is paused', async () => {
    const data = world2();
    data.Fantasy.Futsal['15'].Config.lockOverride = 'open';
    const db = new FakeDb(data);
    await runLifecycleSweep(db, AFTER_LOCK2);
    expect(Object.keys(await db.read(BADGE_CATALOG_PATH) as Json).sort())
      .toEqual(Object.keys(STARTER_CATALOG).sort());
    // The paused season itself was not touched.
    expect(db.writes.every((p) => p.startsWith(`${BADGE_CATALOG_PATH}/`))).toBe(true);
  });
});

// ── End to end over the finalize pipeline (world2: GW1 settled, GW2 under
// test; see HAND MATH above) ─────────────────────────────────────────────────

const B = `${F_ROOT}/Badges`;
const LATER = new Date(AFTER_LOCK2.getTime() + 3_600_000);

async function finalizeGw2(db: FakeDb, nowUtc = AFTER_LOCK2): Promise<void> {
  await maybeFinalizeGame(db, { sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc });
}

async function awardIds(db: FakeDb): Promise<Record<string, string[]>> {
  const out: Record<string, string[]> = {};
  for (const [uid, m] of Object.entries((await db.read(B) ?? {}) as Json)) {
    // FakeDb keeps an emptied parent as {}; RTDB drops it.
    if (Object.keys(m).length > 0) out[uid] = Object.keys(m).sort();
  }
  return out;
}

/** Bea marked absent in GW2's second game (Bulls are team2). */
function markBeaAbsent(db: FakeDb): void {
  db.data.Futsal['15'].Date[GW2_DATE][1].team2attendance = { Bea: false };
}

describe('finalize hook: weekly awards (Review Focus 1 + voided weeks)', () => {
  it('a finalize writes exactly the earned awards, one child write each', async () => {
    const db = new FakeDb(world2());
    await finalizeGw2(db);
    expect(await awardIds(db)).toEqual({
      alpha: ['benchBoss_gw2'],
      boost: ['captainGenius_gw2'],
      churn: ['benchBoss_gw2', 'crystalBall_gw2', 'topOfTheWeek_gw2'],
    });
    expect(await db.read(`${B}/boost/captainGenius_gw2`)).toEqual({
      Badge: 'captainGenius', Gw: 2, At: AFTER_LOCK2.getTime(), Source: 'auto',
    });
    // Child writes only — the whole Badges/<uid> node is never set, so a
    // manual award can never be clobbered.
    const badgeWrites = db.writes.filter((p) => p.startsWith(B));
    expect(badgeWrites.every((p) => p.split('/').length === 6)).toBe(true);
  });

  it('a rerun with unchanged scores writes nothing to Badges (At kept)', async () => {
    const db = new FakeDb(world2());
    await finalizeGw2(db);
    db.writes = [];
    await finalizeGw2(db, LATER);
    expect(db.writes.filter((p) => p.startsWith(B))).toEqual([]);
    expect((await db.read(`${B}/boost/captainGenius_gw2`) as Json).At).toBe(AFTER_LOCK2.getTime());
  });

  it('a score correction re-settles: added AND removed; manual + other weeks untouched', async () => {
    const db = new FakeDb(world2());
    const manual = { Badge: 'captainGenius', Gw: 2, At: 5, Source: 'manual', Note: 'Owner pick', By: 'admin1' };
    db.data.Fantasy.Futsal['15'].Badges = {
      boost: { '-Mmanual1': manual },
      churn: { topOfTheWeek_gw1: { Badge: 'topOfTheWeek', Gw: 1, At: 4, Source: 'auto' } },
    };
    await finalizeGw2(db);
    markBeaAbsent(db);
    await finalizeGw2(db, LATER);
    expect(await awardIds(db)).toEqual({
      alpha: ['benchBoss_gw2', 'crystalBall_gw2'], // gained Crystal Ball
      boost: ['-Mmanual1'], // lost Captain Genius; the manual one stays
      churn: ['benchBoss_gw2', 'crystalBall_gw2', 'topOfTheWeek_gw1', 'topOfTheWeek_gw2'],
    });
    expect(await db.read(`${B}/boost/-Mmanual1`)).toEqual(manual);
    expect((await db.read(`${B}/alpha/crystalBall_gw2`) as Json).At).toBe(LATER.getTime());
  });

  it('voiding the week removes its auto awards (manual stay); un-voiding brings them back', async () => {
    const db = new FakeDb(world2());
    const manual = { Badge: 'benchBoss', Gw: 2, At: 5, Source: 'manual', By: 'admin1' };
    db.data.Fantasy.Futsal['15'].Badges = { boost: { '-Mmanual1': manual } };
    await finalizeGw2(db);
    db.data.Fantasy.Futsal['15'].Voided = { 2: true };
    await resettleVoidToggle(db, { sport: 'Futsal', season: '15', gw: 2, nowUtc: LATER });
    expect(await awardIds(db)).toEqual({ boost: ['-Mmanual1'] });

    delete db.data.Fantasy.Futsal['15'].Voided;
    await resettleVoidToggle(db, { sport: 'Futsal', season: '15', gw: 2, nowUtc: LATER });
    expect((await awardIds(db))['churn'])
      .toEqual(['benchBoss_gw2', 'crystalBall_gw2', 'topOfTheWeek_gw2']);
  });

  it('a first finalize of an already-voided week awards nothing', async () => {
    const data = world2();
    data.Fantasy.Futsal['15'].Voided = { 2: true };
    const db = new FakeDb(data);
    await finalizeGw2(db);
    expect(await db.read(B)).toBeNull();
  });

  it('an inactive catalog badge is not awarded; its existing award stays', async () => {
    const data = world2();
    data.Fantasy.BadgeCatalog = {
      benchBoss: { ...STARTER_CATALOG.benchBoss, Active: false },
    };
    data.Fantasy.Futsal['15'].Badges = {
      boost: { benchBoss_gw2: { Badge: 'benchBoss', Gw: 2, At: 1, Source: 'auto' } },
    };
    const db = new FakeDb(data);
    await finalizeGw2(db);
    const ids = await awardIds(db);
    expect(ids['alpha']).toBeUndefined(); // alpha only earned Bench Boss
    expect(ids['churn']).toEqual(['crystalBall_gw2', 'topOfTheWeek_gw2']);
    expect(ids['boost']).toEqual(['benchBoss_gw2', 'captainGenius_gw2']); // stale one stays
  });

  it('a badge failure is logged and never fails the finalize (scores still land)', async () => {
    class BrokenBadges extends FakeDb {
      async read(path: string): Promise<unknown> {
        if (path.endsWith('/Badges')) throw new Error('boom');
        return super.read(path);
      }
    }
    const db = new BrokenBadges(world2());
    const warns: string[] = [];
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW2_DATE, nowUtc: AFTER_LOCK2,
      log: { info: () => undefined, warn: (m) => { warns.push(m); } },
    });
    expect(await db.read(`${F_ROOT}/History/2`)).not.toBeNull();
    expect(warns).toContain('fantasy badges: settle failed');
  });

  it('a failure in a LATER finalize step (totals, dream team, rollover, news) still leaves the week badges written', async () => {
    const later = [
      `${F_ROOT}/PlayerTotals`, `${F_ROOT}/DreamTeam/2`, `${F_ROOT}/Squads/`, `${F_ROOT}/NewsDrafted/2`,
    ];
    for (const prefix of later) {
      class BreaksLater extends FakeDb {
        async write(path: string, value: unknown): Promise<void> {
          if (path.startsWith(prefix)) throw new Error(`later step ${prefix}`);
          return super.write(path, value);
        }
      }
      const db = new BreaksLater(world2());
      await expect(finalizeGw2(db), prefix).rejects.toThrow('later step');
      expect(await awardIds(db), prefix).toEqual({
        alpha: ['benchBoss_gw2'],
        boost: ['captainGenius_gw2'],
        churn: ['benchBoss_gw2', 'crystalBall_gw2', 'topOfTheWeek_gw2'],
      });
    }
  });

  it('Crystal Ball reads an admin-edited Team of the Week (the node the hub shows)', async () => {
    const data = world2();
    data.Fantasy.Futsal['15'].DreamTeam = {
      2: {
        Auto: false,
        Players: [
          { name: 'Dana', position: 'DEF', points: 13 },
          { name: 'Eva', position: 'DEF', points: -3 },
          { name: 'Alex', position: 'ATT', points: 12 },
        ],
      },
    };
    const db = new FakeDb(data);
    await finalizeGw2(db);
    const ids = await awardIds(db);
    expect(ids['alpha']).toContain('crystalBall_gw2'); // Dana, Eva, Alex
    expect(ids['churn']).not.toContain('crystalBall_gw2'); // Dana + bench Eva = 2
  });

  it('a paused season computes no auto awards (Review Focus 4, engine side)', async () => {
    const data = world2();
    data.Fantasy.Futsal['15'].Config.lockOverride = 'locked';
    const db = new FakeDb(data);
    await finalizeGw2(db);
    expect(await db.read(B)).toBeNull();
  });
});

describe('settleWeeklyBadges (direct)', () => {
  it('reads the catalog + Badges and applies the reconcile', async () => {
    const db = new FakeDb({ Fantasy: { Futsal: { '15': {} } } });
    const args = {
      sport: 'Futsal', season: '15', gw: 3,
      squadsByUid: week().squadsByUid,
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
      playedByName: week().playedByName,
      dreamTeamNames: [],
      gameweekBoard: { u1: { points: 10, rank: 1 } },
      voided: false,
      nowMs: NOW_MS,
    };
    expect(await settleWeeklyBadges(db, args)).toEqual({ written: 3, removed: 0 });
    expect(Object.keys(await db.read(`${B}/u1`) as Json).sort())
      .toEqual(['benchBoss_gw3', 'captainGenius_gw3', 'topOfTheWeek_gw3']);
    // Corrected: the captain is now outscored (A2 10 > A1 9).
    expect(await settleWeeklyBadges(db, {
      ...args, playerWeeks: { ...args.playerWeeks, A2: 10 },
    })).toEqual({ written: 0, removed: 1 });
    expect(Object.keys(await db.read(`${B}/u1`) as Json).sort())
      .toEqual(['benchBoss_gw3', 'topOfTheWeek_gw3']);
  });
});

describe('season end (Finished + every gameweek finalized)', () => {
  function seasonWorld(users: string[] = ['churn', 'boost']): FakeDb {
    const data = world2();
    data.Futsal['15'].Finished = true;
    data.Users = Object.fromEntries(users.map((u) => [u, { Name: u }]));
    return new FakeDb(data);
  }
  const cab = (badge: string) => deterministicAwardId(`fantasy_${badge}`, 'fantasy', 'Futsal/15', '15');

  it('the last week\'s finalize awards the season badges + cabinet for real users only', async () => {
    const db = seasonWorld();
    await finalizeGw2(db);
    const ids = await awardIds(db);
    expect(ids['churn']).toContain('champion_season');
    expect(ids['boost']).toContain('runnerUp_season');
    expect(ids['alpha']).toContain('thirdPlace_season');
    for (const uid of ['alpha', 'boost', 'churn']) expect(ids[uid]).toContain('everPresent_season');
    expect(await db.read(`${B}/churn/champion_season`)).toEqual({
      Badge: 'champion', At: AFTER_LOCK2.getTime(), Source: 'auto',
    });
    expect(await db.read(`Users/churn/Awards/${cab('champion')}`)).toMatchObject({
      TrophyId: 'fantasy_champion', Tier: 'gold', ScopeType: 'fantasy', ScopeId: 'Futsal/15',
      Season: '15', Context: 'Infinite Fantasy', Source: 'auto', Date: '06282026',
    });
    expect(await db.read(`Users/boost/Awards/${cab('runnerUp')}`)).toMatchObject({ Tier: 'silver' });
    // alpha has no Users node (a test-fill style uid): no cabinet write at all.
    expect(await db.read('Users/alpha')).toBeNull();
    expect(db.writes.filter((p) => p.startsWith('Users/')).sort()).toEqual([
      `Users/boost/Awards/${cab('runnerUp')}`, `Users/churn/Awards/${cab('champion')}`,
    ]);
  });

  it('not over: Finished false, or a gameweek not finalized yet', async () => {
    const notFinished = new FakeDb(world2());
    await finalizeGw2(notFinished);
    expect(JSON.stringify(await notFinished.read(B))).not.toContain('_season');

    const db = seasonWorld();
    const cfg = configFromMap(db.data.Fantasy.Futsal['15'].Config);
    expect(await settleSeasonBadges(db, { sport: 'Futsal', season: '15', cfg, nowUtc: AFTER_LOCK2 }))
      .toBe('notOver'); // GW2 has no History yet
  });

  it('a score correction after the season re-settles placements and the cabinet', async () => {
    const db = seasonWorld();
    await finalizeGw2(db);
    markBeaAbsent(db);
    await finalizeGw2(db, LATER);
    const ids = await awardIds(db);
    expect(ids['alpha']).toContain('runnerUp_season');
    expect(ids['alpha']).not.toContain('thirdPlace_season');
    expect(ids['boost']).toContain('thirdPlace_season');
    expect(ids['boost']).not.toContain('runnerUp_season');
    // boost's silver went, bronze came; alpha has no Users node.
    expect(await db.read(`Users/boost/Awards/${cab('runnerUp')}`)).toBeNull();
    expect(await db.read(`Users/boost/Awards/${cab('thirdPlace')}`)).toMatchObject({ Tier: 'bronze' });
    expect(await db.read(`Users/churn/Awards/${cab('champion')}`)).not.toBeNull();
  });

  it('a cabinet award the owner edited (not ours any more) is never removed', async () => {
    const db = seasonWorld();
    await finalizeGw2(db);
    await db.write(`Users/boost/Awards/${cab('runnerUp')}/Source`, 'manual');
    markBeaAbsent(db);
    await finalizeGw2(db, LATER);
    expect(await db.read(`Users/boost/Awards/${cab('runnerUp')}`)).not.toBeNull();
  });

  it('the sweep settles a season flagged Finished after its last finalize — once', async () => {
    const data = world2();
    data.Users = { churn: { Name: 'c' } };
    const db = new FakeDb(data);
    await finalizeGw2(db);
    db.data.Futsal['15'].Finished = true;
    const after = new Date(Date.UTC(2026, 7, 15)); // season over
    await runLifecycleSweep(db, after);
    expect((await awardIds(db))['churn']).toContain('champion_season');
    expect(await db.read(`Users/churn/Awards/${cab('champion')}`)).not.toBeNull();

    // The owner removes a season badge by hand: later sweeps leave it removed
    // (only a re-score of a week re-settles the season).
    await db.write(`${B}/churn/champion_season`, null);
    db.writes = [];
    await runLifecycleSweep(db, new Date(after.getTime() + 900_000));
    expect(await db.read(`${B}/churn/champion_season`)).toBeNull();
    expect(db.writes.filter((p) => p.startsWith(B) || p.startsWith('Users/'))).toEqual([]);
  });

  it('a paused season gets no season awards from the sweep', async () => {
    const data = world2();
    const db = new FakeDb(data);
    await finalizeGw2(db);
    db.data.Futsal['15'].Finished = true;
    db.data.Fantasy.Futsal['15'].Config.lockOverride = 'open';
    await runLifecycleSweep(db, new Date(Date.UTC(2026, 7, 15)));
    expect(JSON.stringify(await db.read(B))).not.toContain('_season');
  });

  it('a match day with no scoreable game (friendlies only) never blocks the season end', async () => {
    const data = world2();
    data.Futsal['15'].Finished = true;
    data.Futsal['15'].Date['07052026'] = [{ team1: 'Sharks', team2: 'Wolves', Stage: 'friendly', status: 2 }];
    const db = new FakeDb(data);
    await finalizeGw2(db);
    // GW3 (friendlies) is never finalized; GW1 + GW2 are the season.
    expect((await awardIds(db))['churn']).toContain('champion_season');
    expect((await awardIds(db))['alpha']).toContain('everPresent_season');
  });

  it('mid-season start: the season counts from the first finalized week (earlier weeks never filled)', async () => {
    const data = world2();
    data.Futsal['15'].Finished = true;
    // Fantasy switched on after GW1: no lock snapshot, no History for it —
    // the first-run guard never fabricates GW1, so it stays empty for good.
    delete data.Fantasy.Futsal['15'].History;
    delete data.Fantasy.Futsal['15'].PublishedPicks;
    const db = new FakeDb(data);
    await finalizeGw2(db);
    await runLifecycleSweep(db, new Date(Date.UTC(2026, 7, 15))); // backstop: GW1 still skipped
    expect(await db.read(`${F_ROOT}/History/1`)).toBeNull();
    // GW2 alone (boost's Bench Boost honored: nothing before it): churn 59,
    // boost 44, alpha 35.
    const ids = await awardIds(db);
    expect(ids['churn']).toContain('champion_season');
    expect(ids['boost']).toContain('runnerUp_season');
    expect(ids['alpha']).toContain('thirdPlace_season');
    for (const uid of ['alpha', 'boost', 'churn']) expect(ids[uid], uid).toContain('everPresent_season');
  });

  it('a week with no squads writes no History: the season starts after it', async () => {
    const data = world2();
    data.Futsal['15'].Finished = true;
    const f = data.Fantasy.Futsal['15'];
    delete f.History;
    delete f.PublishedPicks;
    const squads = f.Squads;
    delete f.Squads;
    const db = new FakeDb(data);
    // GW1 settles with nobody's squad saved yet (finalize writes no History).
    await maybeFinalizeGame(db, {
      sport: 'Futsal', season: '15', dateKey: GW1_DATE, nowUtc: new Date(Date.UTC(2026, 5, 21, 23)),
    });
    expect(await db.read(`${F_ROOT}/PlayerWeeks/1`)).not.toBeNull(); // GW1 did settle
    expect(await db.read(`${F_ROOT}/History/1`)).toBeNull();
    db.data.Fantasy.Futsal['15'].Squads = squads;
    await finalizeGw2(db);
    const ids = await awardIds(db);
    expect(ids['churn']).toContain('champion_season');
    for (const uid of ['alpha', 'boost', 'churn']) expect(ids[uid], uid).toContain('everPresent_season');
  });

  it('Finished but a lock-passed week never finalized: not over + a warning naming it', async () => {
    const db = seasonWorld(); // History/1 only
    const cfg = configFromMap(db.data.Fantasy.Futsal['15'].Config);
    const warns: Array<{ m: string; c?: Record<string, unknown> }> = [];
    const log = { info: () => undefined, warn: (m: string, c?: Record<string, unknown>) => { warns.push({ m, c }); } };
    expect(await settleSeasonBadges(db, { sport: 'Futsal', season: '15', cfg, nowUtc: AFTER_LOCK2, log }))
      .toBe('notOver');
    expect(warns).toEqual([{
      m: 'fantasy badges: season Finished but gameweeks not finalized — season badges wait',
      c: { sport: 'Futsal', season: '15', missing: [2] },
    }]);
    // Before GW2's lock it simply has not been played yet: no warning.
    warns.length = 0;
    expect(await settleSeasonBadges(db, {
      sport: 'Futsal', season: '15', cfg, nowUtc: new Date(Date.UTC(2026, 5, 27)), log,
    })).toBe('notOver');
    expect(warns).toEqual([]);
  });

  it('seasonWorld fixture sanity: GW1/GW2 nets', () => {
    const data = world2();
    expect(clone(data.Fantasy.Futsal['15'].History[1].churn.TotalTenths)).toBe(595);
  });
});

describe('season-end marker (Fantasy/<sport>/<season>/SeasonBadgesSettledAt, D6)', () => {
  // A scalar leaf: it is read with read() != null — db.exists() is for map
  // nodes only and answers false for a number in production.
  const MARKER = `${F_ROOT}/SeasonBadgesSettledAt`;

  function settledWorld(): FakeDb {
    const data = world2();
    data.Futsal['15'].Finished = true;
    data.Users = { churn: { Name: 'churn' }, boost: { Name: 'boost' } };
    return new FakeDb(data);
  }
  const sweepArgs = (db: FakeDb) => ({
    sport: 'Futsal', season: '15',
    cfg: configFromMap(db.data.Fantasy.Futsal['15'].Config),
    nowUtc: AFTER_LOCK2, onlyIfUnsettled: true,
  });
  const finalizeArgs = (db: FakeDb, nowUtc = AFTER_LOCK2) => ({
    sport: 'Futsal', season: '15',
    cfg: configFromMap(db.data.Fantasy.Futsal['15'].Config), nowUtc,
  });

  it('a settled season: the sweep check answers from the marker alone (no Badges, no History)', async () => {
    const db = settledWorld();
    await finalizeGw2(db); // settles the season and sets the marker
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
    db.reads = [];
    db.writes = [];
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    // The TestFill belt, the league flag, the marker — nothing else; the
    // marker is a number, so it is read with read(), never exists().
    expect(db.reads).toEqual([
      `read:${F_ROOT}/TestFill`, 'read:Futsal/15/Finished', `read:${MARKER}`,
    ]);
    expect(db.writes).toEqual([]);
  });

  it('an auto season award but no marker (settled before the marker existed): backfills it once', async () => {
    const db = settledWorld();
    await finalizeGw2(db);
    await db.write(MARKER, null);
    db.reads = [];
    db.writes = [];
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    expect(db.reads).toContain(`read:${B}`); // had to look at the awards once
    expect(db.writes).toEqual([MARKER]);
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
    db.reads = [];
    db.writes = [];
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    expect(db.reads).not.toContain(`read:${B}`);
    expect(db.writes).toEqual([]);
  });

  it('the lifecycle sweep of a settled season no longer reads its Badges', async () => {
    const db = settledWorld();
    await finalizeGw2(db);
    db.reads = [];
    await runLifecycleSweep(db, new Date(Date.UTC(2026, 7, 15))); // season over
    expect(db.reads).toContain(`read:${MARKER}`);
    expect(db.reads).not.toContain(`read:${B}`);
    expect(db.reads).not.toContain(`read:${F_ROOT}/History`);
  });

  it('a finalize-style call (no onlyIfUnsettled) ignores the marker and re-settles', async () => {
    const db = settledWorld();
    await finalizeGw2(db);
    await db.write(`${B}/churn/champion_season`, null); // removed by hand
    // The sweep trusts the marker: the removal stays.
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    expect(await db.read(`${B}/churn/champion_season`)).toBeNull();
    // A finalize rerun re-settles exactly as before.
    db.reads = [];
    expect(await settleSeasonBadges(db, finalizeArgs(db))).toBe('settled');
    expect(db.reads).toContain(`read:${B}`);
    expect(db.reads).toContain(`read:${F_ROOT}/History`);
    expect(await db.read(`${B}/churn/champion_season`)).toMatchObject({ Badge: 'champion' });
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
  });

  it('a rerun with unchanged scores does not rewrite the marker (it keeps its first instant)', async () => {
    const db = settledWorld();
    await finalizeGw2(db);
    db.writes = [];
    expect(await settleSeasonBadges(db, finalizeArgs(db, LATER))).toBe('settled');
    expect(db.writes).not.toContain(MARKER);
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
  });

  it('a re-settle that takes season awards away deletes the marker first and sets it again after', async () => {
    const db = settledWorld();
    await finalizeGw2(db);
    markBeaAbsent(db);
    db.writes = [];
    await finalizeGw2(db, LATER); // boost loses runnerUp_season, gains thirdPlace_season
    const firstMarker = db.writes.indexOf(MARKER);
    const removal = db.writes.indexOf(`${B}/boost/runnerUp_season`);
    expect(removal).toBeGreaterThanOrEqual(0);
    expect(firstMarker).toBeGreaterThanOrEqual(0);
    expect(firstMarker).toBeLessThan(removal); // gone before the first award goes
    expect(db.writes.filter((p) => p === MARKER)).toHaveLength(2); // delete, then set
    expect(await db.read(MARKER)).toBe(LATER.getTime()); // the settle that stands
    expect(await db.read(`${B}/boost/thirdPlace_season`)).not.toBeNull();
  });

  it('if a removal write fails mid-settle, the marker was already deleted (the failure is only logged)', async () => {
    class Crashing extends FakeDb {
      armed = false;
      async write(path: string, value: unknown): Promise<void> {
        if (this.armed && path === `${B}/boost/runnerUp_season` && value === null) {
          throw new Error('boom');
        }
        return super.write(path, value);
      }
    }
    const data = world2();
    data.Futsal['15'].Finished = true;
    const db = new Crashing(data);
    await finalizeGw2(db);
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
    markBeaAbsent(db);
    db.armed = true;
    await finalizeGw2(db, LATER); // a badge failure is logged, never fails the finalize
    expect(await db.read(MARKER)).toBeNull();
  });

  it('the weekly reconcile never removes a season award, so it never touches the marker', async () => {
    const db = new FakeDb({ Fantasy: { Futsal: { '15': { SeasonBadgesSettledAt: 123 } } } });
    const args = {
      sport: 'Futsal', season: '15', gw: 3,
      squadsByUid: week().squadsByUid,
      playerWeeks: { G1: 1, D1: 2, D2: 3, A1: 9, A2: 3, BD: 0, BA: 0 },
      playedByName: week().playedByName,
      dreamTeamNames: [],
      gameweekBoard: { u1: { points: 10, rank: 1 } },
      voided: false,
      nowMs: NOW_MS,
    };
    expect(await settleWeeklyBadges(db, args)).toEqual({ written: 3, removed: 0 });
    expect(await settleWeeklyBadges(db, {
      ...args, playerWeeks: { ...args.playerWeeks, A2: 10 },
    })).toEqual({ written: 0, removed: 1 });
    expect(db.writes).not.toContain(MARKER);
    expect(await db.read(MARKER)).toBe(123);
  });

  it('a Finished season whose settle awards nobody still gets the marker, and the next sweep reads no Badges/History', async () => {
    const data = world2();
    data.Futsal['15'].Finished = true;
    // Ever Present off, and no Overall board to rank: every gameweek is
    // finalized and the full settle runs, but nobody earns a season award.
    data.Fantasy.BadgeCatalog = { everPresent: { ...STARTER_CATALOG.everPresent, Active: false } };
    const db = new FakeDb(data);
    await finalizeGw2(db);
    await db.write(`${F_ROOT}/Leaderboards/Overall`, null);
    await db.write(MARKER, null);
    db.writes = [];
    expect(await settleSeasonBadges(db, finalizeArgs(db))).toBe('settled');
    expect(JSON.stringify(await db.read(B))).not.toContain('_season'); // zero season awards
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
    db.reads = [];
    db.writes = [];
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    expect(db.reads).toEqual([
      `read:${F_ROOT}/TestFill`, 'read:Futsal/15/Finished', `read:${MARKER}`,
    ]);
    expect(db.writes).toEqual([]);
  });

  it('every season badge switched off: the season is settled (nothing to award) and marked', async () => {
    const data = world2();
    data.Futsal['15'].Finished = true;
    data.Fantasy.BadgeCatalog = Object.fromEntries(
      Object.entries(STARTER_CATALOG)
        .filter(([, e]) => (SEASON_RULES as readonly string[]).includes(String(e.Rule)))
        .map(([id, e]) => [id, { ...e, Active: false }]));
    const db = new FakeDb(data);
    expect(await settleSeasonBadges(db, finalizeArgs(db))).toBe('settled');
    expect(await db.read(MARKER)).toBe(AFTER_LOCK2.getTime());
    db.reads = [];
    expect(await settleSeasonBadges(db, sweepArgs(db))).toBe('alreadySettled');
    expect(db.reads).not.toContain(`read:${B}`);
  });

  it('not over (not Finished, a week not finalized) and TestFill seasons never get a marker', async () => {
    const notFinished = new FakeDb(world2());
    await finalizeGw2(notFinished);
    expect(await notFinished.read(MARKER)).toBeNull();

    const early = settledWorld(); // GW2 has no History yet
    expect(await settleSeasonBadges(early, finalizeArgs(early))).toBe('notOver');
    expect(await early.read(MARKER)).toBeNull();

    const data = world2();
    data.Futsal['15'].Finished = true;
    data.Fantasy.Futsal['15'].TestFill = { At: 1, Managers: 20 };
    const test = new FakeDb(data);
    expect(await settleSeasonBadges(test, finalizeArgs(test))).toBe('testFill');
    expect(await test.read(MARKER)).toBeNull();
    expect(test.writes).toEqual([]);
  });
});
