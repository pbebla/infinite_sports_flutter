// Squad integrity (audit I2, squad hardening 2026-11-01) — the pure judge,
// the lock-accounting pass and the finalize zeroing. The orchestration-level
// contract (snapshot + alert + finalize + rerun) is squad_hardening.test.ts.

import { describe, expect, it } from 'vitest';
import { weeklyRuleWinners } from './badges';
import { configFromMap } from './fantasy_config';
import { computeGameweekFinalize } from './finalize_core';
import { parseSquadAlert } from './position_changes';
import { FantasySquad, squadFromMap } from './squad';
import {
  baselineSquadOf, IntegrityInputs, integrityMarketOf, integrityVerdictOf,
  invalidAlertNode, invalidIssuesOf, isInvalidAlert, priceSnapshotOf,
  sameInvalidAlert, squadIntegrityIssues, trustedPrices,
} from './squad_integrity';
import { annotateSquadIntegrity, lockAccounting } from './transfer_state';

const cfg = configFromMap({}); // futsal default: budget 500, 7 picks

type Raw = Record<string, any>;
const pick = (playerId: string, position: string, priceTenths: number, bench = false) =>
  ({ playerId, position, priceTenths, bench });

/** A legal 480-tenth squad (the golden "alpha"). */
function alpha(): Raw {
  return {
    picks: [
      pick('Eli', 'GK', 55), pick('Dana', 'DEF', 80), pick('Eva', 'DEF', 50),
      pick('Ezra', 'ATT', 65), pick('Alex', 'ATT', 95),
      pick('Will', 'DEF', 60, true), pick('Wren', 'ATT', 75, true),
    ],
    captainId: 'Ezra',
    viceId: 'Alex',
  };
}

const MARKET_NODE: Raw = {
  Sam: { position: 'GK', priceTenths: 85, eligible: true },
  Eli: { position: 'GK', priceTenths: 55, eligible: true },
  Bo: { position: 'GK', priceTenths: 75, eligible: false }, // guest
  Dana: { position: 'DEF', priceTenths: 80, eligible: true },
  Eva: { position: 'DEF', priceTenths: 50, eligible: true },
  Will: { position: 'DEF', priceTenths: 60, eligible: true },
  Bea: { position: 'DEF', priceTenths: 75, eligible: true },
  Ezra: { position: 'ATT', priceTenths: 65, eligible: true },
  Alex: { position: 'ATT', priceTenths: 95, eligible: true },
  Wren: { position: 'ATT', priceTenths: 75, eligible: true },
  Junk: { position: 'MID', priceTenths: 40, eligible: true }, // unusable
};
const market = integrityMarketOf(MARKET_NODE);
const sq = (raw: Raw): FantasySquad => squadFromMap(raw);

describe('squadIntegrityIssues: the judge', () => {
  it('a legal squad bought at market is clean (first squad, no baseline)', () => {
    expect(squadIntegrityIssues(sq(alpha()), cfg, market, null, {})).toEqual([]);
  });

  it('formation and badCaptain are NOT integrity issues (tolerated as today)', () => {
    const s = alpha();
    s.picks[0].bench = true; // the GK benched, a DEF started: still 5
    s.picks[5].bench = false; // starters, but an illegal formation
    s.captainId = 'Nobody'; // badCaptain
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {})).toEqual([]);
  });

  it('tooManyStarters: more non-bench picks than the formation (a REST '
    + '"Bench Boost every week") — 6 or 7 starters, never 5', () => {
    const s = alpha();
    s.picks[5].bench = false; // 6 starters
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['tooManyStarters']);
    s.picks[6].bench = false; // all 7
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['tooManyStarters']);
    const five = alpha(); // the legal 5 + 2 is clean
    expect(squadIntegrityIssues(sq(five), cfg, market, null, {})).toEqual([]);
  });

  it('too few picks is a formation problem, not an integrity one', () => {
    const s = alpha();
    s.picks.pop();
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {})).toEqual([]);
  });

  it('duplicatePlayer', () => {
    const s = alpha();
    s.picks[1] = pick('Eva', 'DEF', 50); // Dana out, a second Eva in (450)
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['duplicatePlayer']);
  });

  it('tooManyPlayers (8 picks) — and the 8th pick costs, so over budget too', () => {
    const s = alpha();
    s.picks.push(pick('Sam', 'GK', 85, true));
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['tooManyPlayers', 'overBudget']);
  });

  it('unknownPlayer: a new pick that is not in the market (or unusable)', () => {
    const s = alpha();
    s.picks[6] = pick('Ghost', 'ATT', 75, true);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['unknownPlayer']);
    s.picks[6] = pick('Junk', 'ATT', 40, true); // bad position = not selectable
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['unknownPlayer']);
  });

  it('ineligiblePlayer: a NEW guest pick', () => {
    const s = alpha();
    s.picks[0] = pick('Bo', 'GK', 75); // 500 total
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['ineligiblePlayer']);
  });

  it('a HELD guest (made ineligible after the buy) is kept — holders keep him', () => {
    const before = alpha();
    before.picks[0] = pick('Bo', 'GK', 55); // bought while eligible, at 55
    const s = alpha();
    s.picks[0] = pick('Bo', 'GK', 55);
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(before), {})).toEqual([]);
  });

  it('overBudget: low client prices do NOT fool the check (new picks at market)', () => {
    const s = alpha();
    s.picks[0] = pick('Sam', 'GK', 10); // Sam is 85: real total 510
    // The client's own sum would read 435 — under budget.
    expect(s.picks.reduce((a: number, p: Raw) => a + p.priceTenths, 0)).toBe(435);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['overBudget']);
  });

  it('negative client prices are floored at zero / the market', () => {
    const s = alpha();
    s.picks[0] = pick('Ghost', 'GK', -10000);
    expect(trustedPrices(sq(s), market, null, {})[0]).toBe(0);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, {}))
      .toEqual(['unknownPlayer']);
  });

  it("a HELD player's price RISE never pushes a legal squad over budget", () => {
    const risen = integrityMarketOf({
      ...MARKET_NODE, Alex: { position: 'ATT', priceTenths: 150, eligible: true },
    });
    const s = alpha(); // still lists Alex at the 95 he paid
    s.picks[2] = pick('Eva', 'DEF', 50);
    // 480 paid; at today's market it would be 535.
    expect(squadIntegrityIssues(sq(s), cfg, risen, sq(alpha()), {})).toEqual([]);
  });

  it('lowering a HELD pick\'s price in the save buys nothing', () => {
    const s = alpha();
    s.picks[4] = pick('Alex', 'ATT', 0); // held at 95 last week
    s.picks[1] = pick('Bea', 'DEF', 75); // Dana out: real 480 - 80 + 75 = 475
    expect(trustedPrices(sq(s), market, sq(alpha()), {})[4]).toBe(95);
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), {})).toEqual([]);
    s.picks[0] = pick('Sam', 'GK', 55); // Eli out for Sam (85): 505
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), {}))
      .toEqual(['overBudget']);
  });

  it('a HELD player whose price FELL may be re-bought at the lower price (remove + re-add)', () => {
    const fallen = integrityMarketOf({
      ...MARKET_NODE, Dana: { position: 'DEF', priceTenths: 70, eligible: true },
    });
    const s = alpha();
    s.picks[1] = pick('Dana', 'DEF', 70); // held at 80, re-added at today's 70
    s.picks[2] = pick('Bea', 'DEF', 75); // the freed 10 + Eva's 50 buy Bea: 495
    expect(trustedPrices(sq(s), fallen, sq(alpha()), { Dana: 80 })[1]).toBe(70);
    expect(squadIntegrityIssues(sq(s), cfg, fallen, sq(alpha()), { Dana: 80 }))
      .toEqual([]);
    // ...but never below that fallen price.
    s.picks[1] = pick('Dana', 'DEF', 0);
    expect(trustedPrices(sq(s), fallen, sq(alpha()), { Dana: 80 })[1]).toBe(70);
  });

  it("a Monday-morning buy at LAST week's price (before the reprice) is legal", () => {
    const s = alpha();
    s.picks[2] = pick('Bea', 'DEF', 70); // Eva out; Bea was 70, now 75
    // 480 - 50 + 70 = 500 (legal); at today's 75 it would be 505.
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), { Bea: 70 }))
      .toEqual([]);
    // Without last week's price on record, today's price is the floor.
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), {}))
      .toEqual(['overBudget']);
    // Claiming LESS than either price still counts the lower real one.
    s.picks[2] = pick('Bea', 'DEF', 1);
    expect(trustedPrices(sq(s), market, sq(alpha()), { Bea: 70 })[2]).toBe(70);
  });

  it('an INVALID previous squad is no baseline: its forged prices are re-judged', () => {
    const forged: Raw = { ...alpha(), Invalid: ['overBudget'] };
    forged.picks[0] = pick('Sam', 'GK', 10);
    expect(baselineSquadOf(forged)).toBeNull();
    const s = alpha();
    s.picks[0] = pick('Sam', 'GK', 10);
    const inputs: IntegrityInputs = {
      market, previousByUid: { u: forged }, previousWeekPrices: {},
    };
    expect(integrityVerdictOf(s, 'u', cfg, inputs)).toEqual(['overBudget']);
    // The same forged squad WITHOUT a verdict would have been trusted.
    const trusted = { ...forged };
    delete (trusted as Raw)['Invalid'];
    expect(integrityVerdictOf(s, 'u', cfg,
      { ...inputs, previousByUid: { u: trusted } })).toEqual([]);
  });

  it('a malformed squad gets no verdict (existing handling)', () => {
    const inputs: IntegrityInputs = { market, previousByUid: {}, previousWeekPrices: {} };
    expect(integrityVerdictOf({ picks: 'nope' }, 'u', cfg, inputs)).toBeNull();
    expect(integrityVerdictOf(null, 'u', cfg, inputs)).toBeNull();
  });
});

describe('markers + alert nodes', () => {
  it('invalidIssuesOf: list, index-keyed map, absent, never empty when present', () => {
    expect(invalidIssuesOf({ Invalid: ['overBudget'] })).toEqual(['overBudget']);
    expect(invalidIssuesOf({ Invalid: { 0: 'duplicatePlayer', 1: 'overBudget' } }))
      .toEqual(['duplicatePlayer', 'overBudget']);
    expect(invalidIssuesOf({ Invalid: true })).toEqual(['invalid']);
    expect(invalidIssuesOf({ Invalid: false })).toBeNull();
    expect(invalidIssuesOf({ picks: [] })).toBeNull();
    expect(invalidIssuesOf(null)).toBeNull();
  });

  it('priceSnapshotOf keeps numbers only', () => {
    expect(priceSnapshotOf({ A: 70, B: '80', C: 65.9 })).toEqual({ A: 70, C: 65 });
  });

  it('the integrity alert node and its rerun check', () => {
    const node = invalidAlertNode(3, ['duplicatePlayer', 'overBudget'], 99);
    expect(node).toEqual({
      Gw: 3, Kind: 'invalid', Issues: ['duplicatePlayer', 'overBudget'], CreatedAt: 99,
    });
    expect(isInvalidAlert(node)).toBe(true);
    expect(sameInvalidAlert(node, 3, ['duplicatePlayer', 'overBudget'])).toBe(true);
    expect(sameInvalidAlert(node, 4, ['duplicatePlayer', 'overBudget'])).toBe(false);
    expect(sameInvalidAlert(node, 3, ['overBudget'])).toBe(false);
    expect(isInvalidAlert({ Gw: 3, Changes: [] })).toBe(false);
  });

  it('position_changes never reads an integrity alert as a position alert', () => {
    expect(parseSquadAlert(invalidAlertNode(3, ['overBudget'], 1))).toBeNull();
    expect(parseSquadAlert({ Gw: 3, Changes: [{ player: 'Ann', from: 'ATT', to: 'DEF' }], CreatedAt: 1 }))
      .not.toBeNull();
  });
});

describe('lockAccounting with integrity', () => {
  const inputs: IntegrityInputs = { market, previousByUid: {}, previousWeekPrices: {} };

  it('marks the invalid squad verbatim + Invalid, leaves the valid one untouched', () => {
    const bad = alpha();
    bad.picks[0] = pick('Sam', 'GK', 10);
    const good = alpha();
    const acc = lockAccounting({
      squadsByUid: { bad, good, junk: { picks: 'x' } },
      statesByUid: {}, historyRaw: null, cfg, gw: 1, integrity: inputs,
    });
    expect(acc.cleanSquads['bad']).toEqual({ ...bad, Invalid: ['overBudget'] });
    expect(acc.cleanSquads['good']).toEqual(good);
    expect(acc.cleanSquads['junk']).toEqual({ picks: 'x' }); // malformed: verbatim
    expect(acc.invalid).toEqual([{ uid: 'bad', issues: ['overBudget'] }]);
    expect(acc.valid).toEqual(['good']);
    // The caller's squads are never mutated.
    expect(bad['Invalid']).toBeUndefined();
  });

  it('a client-written Invalid key on a CLEAN squad is dropped (server-only marker)', () => {
    const sneaky = { ...alpha(), Invalid: ['overBudget'] };
    const out = annotateSquadIntegrity({ sneaky }, cfg, inputs);
    expect(out.squads['sneaky']).toEqual(alpha());
    expect(out.valid).toEqual(['sneaky']);
  });

  it('without integrity nothing is judged (the old contract, byte for byte)', () => {
    const bad = alpha();
    bad.picks[0] = pick('Sam', 'GK', 10);
    const acc = lockAccounting({
      squadsByUid: { bad }, statesByUid: {}, historyRaw: null, cfg, gw: 1,
    });
    expect(acc.cleanSquads['bad']).toEqual(bad);
    expect(acc.invalid).toEqual([]);
    expect(acc.valid).toEqual([]);
  });
});

describe('finalize: an Invalid squad scores zero', () => {
  const games = [{
    node: {
      team1: 'Sharks', team2: 'Wolves', status: 2, team1score: 2, team2score: 0,
      activities: [{ player: 'Alex', type: 'goal', team: 'Sharks' }],
    },
    attendance: null,
  }];
  const players = {
    Alex: { position: 'ATT' as const, eligible: true, teamName: 'Sharks' },
    Eli: { position: 'GK' as const, eligible: true },
  };
  const base = {
    cfg, gw: 2, games, players,
    playerWeeksByWeek: {}, playedGamesByWeek: {}, dreamTeamAuto: null,
    nowMs: 1,
  };

  it('TotalTenths 0, verdict kept, no Breakdown, board 0, Overall keeps old weeks', () => {
    const bad = { ...alpha(), Invalid: ['duplicatePlayer'] };
    const out = computeGameweekFinalize({
      ...base,
      squadsByUid: { bad, good: alpha() },
      transferCostPointsByUid: { bad: 4 },
      historyTenthsByWeek: { 1: { bad: 300, good: 100 } },
    });
    const row = out.historyByUid['bad'];
    expect(row['TotalTenths']).toBe(0);
    expect(row['Invalid']).toEqual(['duplicatePlayer']);
    expect('Breakdown' in row).toBe(false);
    expect(row['picks']).toEqual(alpha().picks); // the squad stays visible
    expect(out.gameweekBoard['bad'].points).toBe(0);
    expect(out.overallBoard['bad'].points).toBe(30); // GW1 + 0 (no -4 either)
    // The valid squad is scored as ever (Breakdown present, no marker).
    expect('Invalid' in out.historyByUid['good']).toBe(false);
    expect(Array.isArray(out.historyByUid['good']['Breakdown'])).toBe(true);
    // Ownership counts the valid squad only: Alex held by 1 of 1.
    expect(out.playerTotals['Alex'].ownershipPct).toBe(100);
  });

  it('a voided week keeps both flags', () => {
    const out = computeGameweekFinalize({
      ...base, voidedWeeks: [2],
      squadsByUid: { bad: { ...alpha(), Invalid: ['overBudget'] } },
      historyTenthsByWeek: {},
    });
    expect(out.historyByUid['bad']).toMatchObject(
      { TotalTenths: 0, Voided: true, Invalid: ['overBudget'] });
  });

  it('rerun from the History row is identical (the marker round-trips)', () => {
    const first = computeGameweekFinalize({
      ...base, squadsByUid: { bad: { ...alpha(), Invalid: ['overBudget'] } },
      historyTenthsByWeek: {},
    });
    const again = computeGameweekFinalize({
      ...base, squadsByUid: { bad: first.historyByUid['bad'] },
      historyTenthsByWeek: {},
    });
    expect(again.historyByUid).toEqual(first.historyByUid);
    expect(again.gameweekBoard).toEqual(first.gameweekBoard);
  });
});

describe('badges skip invalid squads', () => {
  it('an invalid squad wins no weekly rule and is not an owner for Hidden Gem', () => {
    const bad = { ...alpha(), Invalid: ['overBudget'] };
    const winners = weeklyRuleWinners({
      gw: 2,
      squadsByUid: { bad, good: alpha() },
      playerWeeks: { Ezra: 12, Alex: 3 },
      playedByName: { Ezra: true, Alex: true },
      dreamTeamNames: [],
      gameweekBoard: { bad: { points: 0, rank: 1 }, good: { points: 0, rank: 1 } },
      voided: false,
      catalog: {},
      nowMs: 1,
    });
    for (const list of Object.values(winners)) expect(list).not.toContain('bad');
    expect(winners.captainGenius).toEqual(['good']);
    expect(winners.topOfTheWeek).toEqual(['good']);
  });
});
