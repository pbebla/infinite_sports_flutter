// Squad integrity (audit I2, squad hardening 2026-11-01) — the pure judge,
// the lock-accounting pass and the finalize zeroing. The orchestration-level
// contract (snapshot + alert + finalize + rerun) is squad_hardening.test.ts.

import { describe, expect, it } from 'vitest';
import { weeklyRuleWinners } from './badges';
import { configFromMap } from './fantasy_config';
import { computeGameweekFinalize } from './finalize_core';
import { clone } from './golden_fixture';
import { parseSquadAlert } from './position_changes';
import { FantasySquad, squadFromMap } from './squad';
import {
  baselineForGwOf, baselineNodeOf, baselineRealizedFor, baselineSquadOf,
  IntegrityInputs, integrityMarketOf, integrityVerdictOf, invalidAlertNode,
  invalidIssuesOf, isInvalidAlert, judgeSale, judgeSquad, picksAtJudgedPrices,
  priceSnapshotOf, sameBaselineNode, sameInvalidAlert, squadIntegrityIssues,
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
    expect(squadIntegrityIssues(sq(alpha()), cfg, market, null, 0, {})).toEqual([]);
  });

  it('formation and badCaptain are NOT integrity issues (tolerated as today)', () => {
    const s = alpha();
    s.picks[0].bench = true; // the GK benched, a DEF started: still 5
    s.picks[5].bench = false; // starters, but an illegal formation
    s.captainId = 'Nobody'; // badCaptain
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {})).toEqual([]);
  });

  it('tooManyStarters: more non-bench picks than the formation (a REST '
    + '"Bench Boost every week") — 6 or 7 starters, never 5', () => {
    const s = alpha();
    s.picks[5].bench = false; // 6 starters
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['tooManyStarters']);
    s.picks[6].bench = false; // all 7
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['tooManyStarters']);
    const five = alpha(); // the legal 5 + 2 is clean
    expect(squadIntegrityIssues(sq(five), cfg, market, null, 0, {})).toEqual([]);
  });

  it('too few picks is a formation problem, not an integrity one', () => {
    const s = alpha();
    s.picks.pop();
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {})).toEqual([]);
  });

  it('duplicatePlayer', () => {
    const s = alpha();
    s.picks[1] = pick('Eva', 'DEF', 50); // Dana out, a second Eva in (450)
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['duplicatePlayer']);
  });

  it('tooManyPlayers (8 picks) — and the 8th pick costs, so over budget too', () => {
    const s = alpha();
    s.picks.push(pick('Sam', 'GK', 85, true));
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['tooManyPlayers', 'overBudget']);
  });

  it('unknownPlayer: a new pick that is not in the market (or unusable)', () => {
    const s = alpha();
    s.picks[6] = pick('Ghost', 'ATT', 75, true);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['unknownPlayer']);
    s.picks[6] = pick('Junk', 'ATT', 40, true); // bad position = not selectable
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['unknownPlayer']);
  });

  it('ineligiblePlayer: a NEW guest pick', () => {
    const s = alpha();
    s.picks[0] = pick('Bo', 'GK', 75); // 500 total
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['ineligiblePlayer']);
  });

  it('a HELD guest (made ineligible after the buy) is kept — holders keep him', () => {
    const before = alpha();
    before.picks[0] = pick('Bo', 'GK', 55); // bought while eligible, at 55
    const s = alpha();
    s.picks[0] = pick('Bo', 'GK', 55);
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(before), 0, {})).toEqual([]);
  });

  it('overBudget: low client prices do NOT fool the check (new picks at market)', () => {
    const s = alpha();
    s.picks[0] = pick('Sam', 'GK', 10); // Sam is 85: real total 510
    // The client's own sum would read 435 — under budget.
    expect(s.picks.reduce((a: number, p: Raw) => a + p.priceTenths, 0)).toBe(435);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['overBudget']);
  });

  it('negative client prices are floored at zero / the market', () => {
    const s = alpha();
    s.picks[0] = pick('Ghost', 'GK', -10000);
    expect(judgeSale(sq(s), market, null, 0, {}).prices[0]).toBe(0);
    expect(squadIntegrityIssues(sq(s), cfg, market, null, 0, {}))
      .toEqual(['unknownPlayer']);
  });

  it("a HELD player's price RISE never pushes a legal squad over budget", () => {
    const risen = integrityMarketOf({
      ...MARKET_NODE, Alex: { position: 'ATT', priceTenths: 150, eligible: true },
    });
    const s = alpha(); // still lists Alex at the 95 he paid
    s.picks[2] = pick('Eva', 'DEF', 50);
    // 480 paid; at today's market it would be 535.
    expect(squadIntegrityIssues(sq(s), cfg, risen, sq(alpha()), 0, {})).toEqual([]);
  });

  it('lowering a HELD pick\'s price in the save buys nothing', () => {
    const s = alpha();
    s.picks[4] = pick('Alex', 'ATT', 0); // held at 95 last week
    s.picks[1] = pick('Bea', 'DEF', 75); // Dana out: real 480 - 80 + 75 = 475
    expect(judgeSale(sq(s), market, sq(alpha()), 0, {}).prices[4]).toBe(95);
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), 0, {})).toEqual([]);
    s.picks[0] = pick('Sam', 'GK', 55); // Eli out for Sam (85): 505
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), 0, {}))
      .toEqual(['overBudget']);
  });

  it('a HELD player whose price FELL stays at the price paid (FPL: removing '
    + 'and re-adding him before the deadline is no sale, no cheaper re-buy)', () => {
    const fallen = integrityMarketOf({
      ...MARKET_NODE, Dana: { position: 'DEF', priceTenths: 70, eligible: true },
    });
    const s = alpha();
    s.picks[1] = pick('Dana', 'DEF', 70); // held at 80, "re-added" at today's 70
    s.picks[2] = pick('Bea', 'DEF', 75); // Eva (50, sold at 50) out for Bea
    const sale = judgeSale(sq(s), fallen, sq(alpha()), 0, { Dana: 80 });
    expect(sale.prices[1]).toBe(80);
    expect(sale.realizedTenths).toBe(0);
    // 480 - 50 + 75 = 505: the 10 Dana fell by is NOT freed.
    expect(squadIntegrityIssues(sq(s), cfg, fallen, sq(alpha()), 0, { Dana: 80 }))
      .toEqual(['overBudget']);
    s.picks[1] = pick('Dana', 'DEF', 0);
    expect(judgeSale(sq(s), fallen, sq(alpha()), 0, { Dana: 80 }).prices[1]).toBe(80);
  });

  it("a Monday-morning buy at LAST week's price (before the reprice) is legal", () => {
    const s = alpha();
    s.picks[2] = pick('Bea', 'DEF', 70); // Eva out; Bea was 70, now 75
    // 480 - 50 + 70 = 500 (legal); at today's 75 it would be 505.
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), 0, { Bea: 70 }))
      .toEqual([]);
    // Without last week's price on record, today's price is the floor.
    expect(squadIntegrityIssues(sq(s), cfg, market, sq(alpha()), 0, {}))
      .toEqual(['overBudget']);
    // Claiming LESS than either price still counts the lower real one.
    s.picks[2] = pick('Bea', 'DEF', 1);
    expect(judgeSale(sq(s), market, sq(alpha()), 0, { Bea: 70 }).prices[2]).toBe(70);
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
    expect(integrityVerdictOf(s, 'u', cfg, inputs)?.issues).toEqual(['overBudget']);
    // The same forged squad WITHOUT a verdict would have been trusted.
    const trusted = { ...forged };
    delete (trusted as Raw)['Invalid'];
    expect(integrityVerdictOf(s, 'u', cfg,
      { ...inputs, previousByUid: { u: trusted } })?.issues).toEqual([]);
  });

  it('a malformed squad gets no verdict (existing handling)', () => {
    const inputs: IntegrityInputs = { market, previousByUid: {}, previousWeekPrices: {} };
    expect(integrityVerdictOf({ picks: 'nope' }, 'u', cfg, inputs)).toBeNull();
    expect(integrityVerdictOf(null, 'u', cfg, inputs)).toBeNull();
  });
});

describe('judgeSale', () => {
  /** A squad of bare picks (judgeSale never looks at formation/captains). */
  const bare = (...ps: Array<[string, number]>): FantasySquad => ({
    picks: ps.map(([playerId, priceTenths]) =>
      ({ playerId, position: 'ATT' as const, priceTenths, bench: false })),
    captainId: '', viceId: '', chip: null,
  });
  /** name -> price, every entry a usable eligible ATT. */
  const mkt = (prices: Record<string, number>) => integrityMarketOf(
    Object.fromEntries(Object.entries(prices).map(([name, priceTenths]) =>
      [name, { position: 'ATT', priceTenths, eligible: true }])));

  it('held keeps the baseline price whatever the client sent', () => {
    const baseline = bare(['A', 80]);
    const m = mkt({ A: 90 });
    for (const client of [80, 90, 10]) {
      expect(judgeSale(bare(['A', client]), m, baseline, 0, {}), String(client))
        .toEqual({ prices: [80], realizedTenths: 0 });
    }
  });

  it('sold riser credits half the rise', () => {
    // A bought at 80, now 90: sells for 85 -> +5.
    expect(judgeSale(bare(['B', 50]), mkt({ A: 90, B: 50 }), bare(['A', 80]), 0, {}))
      .toEqual({ prices: [50], realizedTenths: 5 });
  });

  it('sold faller costs the full drop', () => {
    // A bought at 80, now 70: sells for 70 -> -10, even though he was still
    // 80 during the previous gameweek (no max(current, last week)).
    expect(judgeSale(bare(['B', 50]), mkt({ A: 70, B: 50 }), bare(['A', 80]), 0,
      { A: 80 })).toEqual({ prices: [50], realizedTenths: -10 });
  });

  it('a sold player missing from the market adds 0', () => {
    expect(judgeSale(bare(['B', 50]), mkt({ B: 50 }), bare(['A', 80]), 0, {}))
      .toEqual({ prices: [50], realizedTenths: 0 });
    // ...and the baseline's own realized still carries.
    expect(judgeSale(bare(['B', 50]), mkt({ B: 50 }), bare(['A', 80]), 3, {})
      .realizedTenths).toBe(3);
  });

  it('a sold player priced <= 0 in the market counts as missing (adds 0), '
    + 'never as a sale at 0', () => {
    for (const price of [0, -5]) {
      expect(judgeSale(bare(['B', 50]), mkt({ A: price, B: 50 }), bare(['A', 80]), 3, {}),
        String(price)).toEqual({ prices: [50], realizedTenths: 3 });
    }
    // A Players entry with no price at all reads 0 in the market: same.
    const noPrice = integrityMarketOf({
      A: { position: 'ATT', eligible: true },
      B: { position: 'ATT', priceTenths: 50, eligible: true },
    });
    expect(judgeSale(bare(['B', 50]), noPrice, bare(['A', 80]), 3, {}).realizedTenths)
      .toBe(3);
  });

  it('an RTDB null-padded picks list keeps the judged prices aligned', () => {
    // RTDB hands back a list with a deleted index as null; squadFromMap
    // skips it, so judgeSale's prices are dense — picksAtJudgedPrices must
    // put the k-th price on the k-th REAL pick, nulls kept in place.
    const raw: Raw = {
      picks: [pick('A', 'ATT', 10), null, pick('B', 'ATT', 99), null, pick('C', 'ATT', 70)],
      captainId: 'A', viceId: 'B',
    };
    const sale = judgeSale(sq(raw), mkt({ A: 80, B: 60, C: 60 }), bare(['B', 40]), 0, {});
    // A new (client 10 < market 80), B held at 40, C new (client 70 > 60).
    expect(sale.prices).toEqual([80, 40, 70]);
    expect(picksAtJudgedPrices(raw['picks'], sale.prices)).toEqual([
      pick('A', 'ATT', 80), null, pick('B', 'ATT', 40), null, pick('C', 'ATT', 70),
    ]);
  });

  it('new pick keeps the market floor', () => {
    // No baseline, market 85, PriceHistory/gw-1 80, client 70 -> 80.
    expect(judgeSale(bare(['A', 70]), mkt({ A: 85 }), null, 0, { A: 80 }))
      .toEqual({ prices: [80], realizedTenths: 0 });
  });

  it('invalid baseline: picks are NEW, realized carries', () => {
    // Last week was judged Invalid with Alex forged at 10 and realized 7.
    const forged: Raw = { ...alpha(), Invalid: ['overBudget'], realizedTenths: 7 };
    forged.picks[4] = pick('Alex', 'ATT', 10);
    const s = alpha();
    s.picks[4] = pick('Alex', 'ATT', 10);
    const v = integrityVerdictOf(s, 'u', cfg,
      { market, previousByUid: { u: forged }, previousWeekPrices: {} });
    // Alex is NEW (no held picks): at market 95, not the forged 10. No
    // sales either (an Invalid baseline has no trusted picks to sell).
    expect(v).toEqual({
      issues: [], prices: [55, 80, 50, 65, 95, 60, 75], realizedTenths: 7,
    });
  });

  it('overBudget uses realized', () => {
    // Alex bought at 95, now 105: selling him banks +5. His replacement Max
    // (ATT, 120 at market) makes the picks sum 480 - 95 + 120 = 505.
    const risen = integrityMarketOf({
      ...MARKET_NODE,
      Alex: { position: 'ATT', priceTenths: 105, eligible: true },
      Max: { position: 'ATT', priceTenths: 120, eligible: true },
    });
    const inputs: IntegrityInputs = {
      market: risen, previousByUid: { u: alpha() }, previousWeekPrices: {},
    };
    const s = alpha();
    s.picks[4] = pick('Max', 'ATT', 120);
    expect(integrityVerdictOf(s, 'u', cfg, inputs))
      .toMatchObject({ issues: [], realizedTenths: 5 });
    s.picks[4] = pick('Max', 'ATT', 121); // 506 > 500 + 5
    expect(integrityVerdictOf(s, 'u', cfg, inputs))
      .toMatchObject({ issues: ['overBudget'], realizedTenths: 5 });
  });

  it("a malformed baseline's realizedTenths is never believed (the server "
    + 'never judged — never wrote — it; a client can write any extra key)', () => {
    const malformed = { picks: { 0: pick('Eli', 'GK', 55) }, realizedTenths: 9999,
      captainId: 'Eli', viceId: 'Eli' };
    expect(judgeSquad(sq(alpha()), 'u', cfg,
      { market, previousByUid: { u: malformed }, previousWeekPrices: {} })
      .realizedTenths).toBe(0);
  });

  it('judgeSquad: the verdict for a parsed squad (the save trigger reads .issues)', () => {
    const s = alpha();
    s.picks[0] = pick('Sam', 'GK', 10); // really 85: 510
    expect(judgeSquad(sq(s), 'u', cfg,
      { market, previousByUid: {}, previousWeekPrices: {} })).toEqual({
      issues: ['overBudget'], prices: [85, 80, 50, 65, 95, 60, 75], realizedTenths: 0,
    });
  });
});

describe('Baselines/<uid>: baselineNodeOf', () => {
  const ALPHA_PRICES = {
    Eli: 55, Dana: 80, Eva: 50, Ezra: 65, Alex: 95, Will: 60, Wren: 75,
  };

  it('a valid node: its (judged) prices by id + its realizedTenths', () => {
    expect(baselineNodeOf({ ...alpha(), realizedTenths: 7 }, 5)).toEqual({
      ForGw: 5, RealizedTenths: 7, Prices: ALPHA_PRICES,
    });
    // A valid node from before the selling rule (no realizedTenths) reads 0.
    expect(baselineNodeOf(alpha(), 5).RealizedTenths).toBe(0);
  });

  it('an Invalid node: no trusted prices, but its realizedTenths carries', () => {
    expect(baselineNodeOf(
      { ...alpha(), Invalid: ['overBudget'], realizedTenths: -3 }, 5,
    )).toEqual({ ForGw: 5, RealizedTenths: -3, Prices: {} });
  });

  it('no node (no squad at the lock) and no previous baseline: a fresh start', () => {
    expect(baselineNodeOf(null, 5)).toEqual({ ForGw: 5, RealizedTenths: 0, Prices: {} });
    expect(baselineNodeOf(undefined, 5, null))
      .toEqual({ ForGw: 5, RealizedTenths: 0, Prices: {} });
  });

  it('an ABSENT node carries the previous baseline\'s RealizedTenths (deleting '
    + 'the squad before a lock never wipes a loss); its Prices are not carried', () => {
    expect(baselineNodeOf(null, 5,
      { ForGw: 4, RealizedTenths: -15, Prices: { Alex: 95 } }))
      .toEqual({ ForGw: 5, RealizedTenths: -15, Prices: {} });
  });

  it('a MALFORMED node carries the previous baseline too — its own '
    + 'realizedTenths is the client\'s writing, never believed', () => {
    const malformed = { picks: 'junk', captainId: 'x', viceId: 'x', realizedTenths: 999 };
    expect(baselineNodeOf(malformed, 5, { ForGw: 4, RealizedTenths: 7 }))
      .toEqual({ ForGw: 5, RealizedTenths: 7, Prices: {} });
    expect(baselineNodeOf('nope', 5, { ForGw: 4, RealizedTenths: 7 }).RealizedTenths)
      .toBe(7);
  });

  it('a parseable node ignores the previous baseline (the node is the truth)', () => {
    expect(baselineNodeOf({ ...alpha(), realizedTenths: 2 }, 5,
      { ForGw: 4, RealizedTenths: -40 }).RealizedTenths).toBe(2);
  });

  it('a junk previous RealizedTenths reads 0 (finite numbers only, truncated)', () => {
    for (const junk of ['5', NaN, Infinity, null, true]) {
      expect(baselineNodeOf(null, 5, { RealizedTenths: junk }).RealizedTenths,
        String(junk)).toBe(0);
    }
    expect(baselineNodeOf(null, 5, { RealizedTenths: -7.9 }).RealizedTenths).toBe(-7);
    expect(baselineNodeOf(null, 5, 'nope').RealizedTenths).toBe(0);
  });

  it('an RTDB null-padded picks list prices the real picks only', () => {
    const raw: Raw = { ...alpha(), realizedTenths: 1 };
    raw.picks = [raw.picks[0], null, ...raw.picks.slice(1)];
    expect(baselineNodeOf(raw, 5).Prices).toEqual(ALPHA_PRICES);
  });

  it('a player id RTDB cannot store as a key never reaches Prices', () => {
    const raw: Raw = { ...alpha() };
    raw.picks = [...raw.picks, pick('J.Doe', 'ATT', 40, true), pick('a/b', 'ATT', 40, true)];
    expect(Object.keys(baselineNodeOf(raw, 5).Prices).sort())
      .toEqual(Object.keys(ALPHA_PRICES).sort());
  });

  it('sameBaselineNode: what RTDB hands back (empty Prices dropped) equals '
    + 'the node we would write', () => {
    const node = { ForGw: 5, RealizedTenths: 0, Prices: {} };
    expect(sameBaselineNode({ ForGw: 5, RealizedTenths: 0 }, node)).toBe(true);
    expect(sameBaselineNode({ ForGw: 5, RealizedTenths: 0, Prices: {} }, node)).toBe(true);
    const full = baselineNodeOf({ ...alpha(), realizedTenths: 7 }, 5);
    expect(sameBaselineNode(clone(full), full)).toBe(true);
    expect(sameBaselineNode({ ...clone(full), ForGw: 6 }, full)).toBe(false);
    expect(sameBaselineNode({ ...clone(full), RealizedTenths: 8 }, full)).toBe(false);
    expect(sameBaselineNode(
      { ...clone(full), Prices: { ...ALPHA_PRICES, Alex: 96 } }, full)).toBe(false);
    expect(sameBaselineNode(
      { ...clone(full), Prices: { ...ALPHA_PRICES, Extra: 1 } }, full)).toBe(false);
    expect(sameBaselineNode(null, node)).toBe(false);
  });

  it('baselineForGwOf: a finite ForGw, else null', () => {
    expect(baselineForGwOf({ ForGw: 10 })).toBe(10);
    expect(baselineForGwOf({ ForGw: '10' })).toBeNull();
    expect(baselineForGwOf({})).toBeNull();
    expect(baselineForGwOf(null)).toBeNull();
  });
});

describe('the judge reads its realized money from Baselines/<uid> (one source)', () => {
  // Alpha bought at market is 480; Eli claimed at 61 (> market 55) counts
  // at 61 as a NEW pick, so the squad spends 486 = 500 - 15 + 1.
  const spend486 = (): Raw => {
    const s = alpha();
    s.picks[0] = pick('Eli', 'GK', 61);
    return s;
  };

  it('baselineRealizedByUid wins when present, even with NO previous squad', () => {
    const inputs: IntegrityInputs = {
      market, previousByUid: {}, previousWeekPrices: {},
      baselineRealizedByUid: { u: -15 },
    };
    expect(baselineRealizedFor(inputs, 'u')).toBe(-15);
    expect(judgeSquad(sq(spend486()), 'u', cfg, inputs))
      .toMatchObject({ issues: ['overBudget'], realizedTenths: -15 });
    const s = spend486();
    s.picks[0] = pick('Eli', 'GK', 60); // 485: exactly the budget
    expect(judgeSquad(sq(s), 'u', cfg, inputs))
      .toMatchObject({ issues: [], realizedTenths: -15 });
  });

  it('absent from baselineRealizedByUid: the previous squad\'s realizedTenths '
    + '(baselineRealizedOf — malformed reads 0)', () => {
    const inputs: IntegrityInputs = {
      market, previousWeekPrices: {}, baselineRealizedByUid: { other: -50 },
      previousByUid: {
        u: { ...alpha(), realizedTenths: 4 },
        junk: { picks: 'x', captainId: 'a', viceId: 'b', realizedTenths: 9999 },
      },
    };
    expect(baselineRealizedFor(inputs, 'u')).toBe(4);
    expect(baselineRealizedFor(inputs, 'junk')).toBe(0);
    expect(baselineRealizedFor(inputs, 'nobody')).toBe(0);
    expect(baselineRealizedFor(
      { market, previousByUid: { u: { ...alpha(), realizedTenths: 4 } },
        previousWeekPrices: {} }, 'u')).toBe(4);
  });

  it('an INVALID squad is snapshotted with the same realized the judge used', () => {
    const inputs: IntegrityInputs = {
      market, previousByUid: {}, previousWeekPrices: {},
      baselineRealizedByUid: { bad: -15 },
    };
    const out = annotateSquadIntegrity({ bad: spend486() }, cfg, inputs);
    expect(out.squads['bad']).toEqual(
      { ...spend486(), Invalid: ['overBudget'], realizedTenths: -15 });
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

  it('marks the invalid squad verbatim + Invalid, the valid one at its judged '
    + 'prices; both carry realizedTenths', () => {
    const bad = alpha();
    bad.picks[0] = pick('Sam', 'GK', 10);
    const good = alpha(); // bought at market: judged prices == its own
    const acc = lockAccounting({
      squadsByUid: { bad, good, junk: { picks: 'x' } },
      statesByUid: {}, historyRaw: null, cfg, gw: 1, integrity: inputs,
    });
    expect(acc.cleanSquads['bad'])
      .toEqual({ ...bad, Invalid: ['overBudget'], realizedTenths: 0 });
    expect(acc.cleanSquads['good']).toEqual({ ...good, realizedTenths: 0 });
    expect(acc.cleanSquads['junk']).toEqual({ picks: 'x' }); // malformed: verbatim
    expect(acc.invalid).toEqual([{ uid: 'bad', issues: ['overBudget'] }]);
    expect(acc.valid).toEqual(['good']);
    // The caller's squads are never mutated.
    expect(bad['Invalid']).toBeUndefined();
  });

  it('a client-written Invalid key on a CLEAN squad is dropped (server-only marker)', () => {
    const sneaky = { ...alpha(), Invalid: ['overBudget'] };
    const out = annotateSquadIntegrity({ sneaky }, cfg, inputs);
    expect(out.squads['sneaky']).toEqual({ ...alpha(), realizedTenths: 0 });
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
