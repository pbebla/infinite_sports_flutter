// The rehearsal's synthetic-client money (client_draft_money.ts): the fan
// app's FPL-rule draft (squad_draft.dart / selling.dart) — and the same
// money the server's lock judge charges for the same inputs.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from '../src/lib/fantasy/fantasy_config';
import { FantasySquad, SquadPick, squadToMap } from '../src/lib/fantasy/squad';
import {
  baselineNodeOf, integrityMarketOf, judgeSale, squadIntegrityIssues,
} from '../src/lib/fantasy/squad_integrity';
import { clientDraftMoney, clientSaleBaselineOf } from './client_draft_money';

const cfg = futsalDefault();

const pick = (playerId: string, priceTenths: number, position: SquadPick['position'] = 'DEF',
  bench = false): SquadPick => ({ playerId, position, priceTenths, bench });

/** Baselines/<uid> for {A: 80, B: 60}, realized 5, FOR gameweek 5. */
const node = (over: Record<string, unknown> = {}) =>
  ({ ForGw: 5, RealizedTenths: 5, Prices: { A: 80, B: 60 }, ...over });

const money = (over: Partial<Parameters<typeof clientDraftMoney>[0]> = {}) => clientDraftMoney({
  baselineNode: node(), currentPrices: { A: 90, B: 50, N: 85 }, lastWeekPrices: null,
  editingGw: 5, ...over,
});

describe('clientSaleBaselineOf (selling.dart saleBaselineFromNode)', () => {
  it('reads ForGw, Prices and RealizedTenths', () => {
    expect(clientSaleBaselineOf(node())).toEqual(
      { forGw: 5, prices: { A: 80, B: 60 }, realizedTenths: 5 });
  });
  it('drops non-integer prices; absent RealizedTenths reads 0', () => {
    expect(clientSaleBaselineOf({ ForGw: 2, Prices: { A: 80, B: '60', C: 7.5 } }))
      .toEqual({ forGw: 2, prices: { A: 80 }, realizedTenths: 0 });
  });
  it('is null without a numeric ForGw, or for a non-map', () => {
    expect(clientSaleBaselineOf({ RealizedTenths: 5 })).toBeNull();
    expect(clientSaleBaselineOf({ ForGw: '5' })).toBeNull();
    expect(clientSaleBaselineOf([1, 2])).toBeNull();
    expect(clientSaleBaselineOf(null)).toBeNull();
  });
});

describe('clientDraftMoney (the app draft)', () => {
  it('realizedFor: the carried total plus every sale at today\'s price', () => {
    const m = money();
    expect(m.realizedFor(['A'])).toBe(5 + (50 - 60)); // B sold, a faller: -10
    expect(m.realizedFor(['B'])).toBe(5 + (85 - 80)); // A sold, a riser: half
    expect(m.realizedFor(['A', 'B'])).toBe(5);
    expect(money({ baselineNode: null }).realizedFor([])).toBe(0);
  });

  it('a sold player with no usable price today adds 0', () => {
    expect(money({ currentPrices: { B: 60 } }).realizedFor(['B'])).toBe(5);
    expect(money({ currentPrices: { A: 0, B: 60 } }).realizedFor(['B'])).toBe(5);
  });

  it('re-adding a sold baseline player restores his baseline price, no sale', () => {
    const m = money();
    expect(m.buyPrice('A')).toBe(80); // not today's 90
    expect(m.addCost('A', ['B'])).toBe(85); // what selling him banked
    expect(m.realizedFor(['A', 'B'])).toBe(5);
  });

  it('a held pick saved at another price counts at the baseline price', () => {
    expect(money().priceOfPick(pick('A', 90))).toBe(80);
    expect(money().priceOfPick(pick('A', 10))).toBe(80);
  });

  it('a new player costs today\'s price; a new pick never under the market floor', () => {
    const m = money({ lastWeekPrices: { N: 80 } });
    expect(m.buyPrice('N')).toBe(85);
    expect(m.addCost('N', ['A', 'B'])).toBe(85);
    expect(m.priceOfPick(pick('N', 70))).toBe(80); // min(85, 80)
    expect(m.priceOfPick(pick('N', 85))).toBe(85);
    expect(money().priceOfPick(pick('N', 70))).toBe(85); // no history: today
  });

  it('ready only for a known baseline FOR the edited week', () => {
    expect(money().ready).toBe(true);
    expect(money({ editingGw: 6 }).ready).toBe(false); // stale
    expect(money({ baselineNode: null }).ready).toBe(true); // a first squad
    expect(money({ baselineNode: { Prices: {} } }).ready).toBe(false); // unreadable
  });

  it('issues: overBudget against budget + realized at the charged prices', () => {
    // 7 picks: A held at 80 (saved at 90), five fillers, total charged 505.
    const base: FantasySquad = {
      picks: [
        pick('G', 85, 'GK'), pick('A', 90, 'DEF'), pick('D2', 80, 'DEF'), pick('D3', 60, 'DEF', true),
        pick('T1', 80, 'ATT'), pick('T2', 70, 'ATT'), pick('T3', 50, 'ATT', true),
      ],
      captainId: 'T1', viceId: 'T2', chip: null,
    };
    const prices = { G: 85, A: 90, D2: 80, D3: 60, T1: 80, T2: 70, T3: 50 };
    const at = (realized: number) => clientDraftMoney({
      baselineNode: { ForGw: 3, RealizedTenths: realized, Prices: { A: 80 } },
      currentPrices: prices, lastWeekPrices: null, editingGw: 3,
    });
    expect(at(5).issues(base, cfg)).toEqual([]); // 505 <= 500 + 5
    expect(at(4).issues(base, cfg)).toEqual(['overBudget']); // 505 > 504
  });
});

describe('parity with the server lock judge (squad_integrity.ts judgeSale)', () => {
  // The previous locked squad (judged prices) + its realized total, the
  // market now and last week, and this week's saved squad.
  const previous: FantasySquad = {
    picks: [
      pick('G1', 60, 'GK'), pick('D1', 80, 'DEF'), pick('D2', 70, 'DEF'), pick('D3', 50, 'DEF', true),
      pick('A1', 100, 'ATT'), pick('A2', 90, 'ATT'), pick('A3', 45, 'ATT', true),
    ],
    captainId: 'A1', viceId: 'A2', chip: null,
  };
  // Spent 495 at realized -5: exactly on budget. D1 rose 80 -> 95 (sells
  // 87, +7); D2 70 -> 60 and A2 90 -> 70 fell; A3 left the market (his sale
  // adds 0).
  const carried = -5;
  const players: Record<string, number> = {
    G1: 65, D1: 95, D2: 60, D3: 50, A1: 110, A2: 70,
    ND: 75, ND2: 87, ND3: 88, NA: 85, NA2: 40,
  };
  const positionOf: Record<string, string> = {
    G1: 'GK', D1: 'DEF', D2: 'DEF', D3: 'DEF', A1: 'ATT', A2: 'ATT',
    ND: 'DEF', ND2: 'DEF', ND3: 'DEF', NA: 'ATT', NA2: 'ATT',
  };
  const playersNode = Object.fromEntries(Object.entries(players).map(([n, p]) =>
    [n, { priceTenths: p, position: positionOf[n], eligible: true }]));
  const lastWeek = { ND: 70, NA: 90 };
  const prevNode = { ...squadToMap(previous), realizedTenths: carried };
  // The app reads exactly what the lock publishes for it.
  const baselinesNode = baselineNodeOf(prevNode, 4);
  const market = integrityMarketOf(playersNode);
  const app = clientDraftMoney({
    baselineNode: baselinesNode, currentPrices: players, lastWeekPrices: lastWeek, editingGw: 4,
  });
  const swap = (out: Record<string, SquadPick>): SquadPick[] =>
    previous.picks.map((p) => out[p.playerId] ?? p);

  // [label, squad picks, realized, overBudget]
  const cases: Array<[string, SquadPick[], number, boolean]> = [
    ['nothing changed (exactly on budget)', previous.picks, -5, false],
    ['sold the riser D1 for ND bought under the floor (charged 70)',
      swap({ D1: pick('ND', 60) }), 2, false],
    ['sold the fallers D2 and A2: the full drops', swap({ D2: pick('ND', 75), A2: pick('NA', 85, 'ATT') }),
      -35, true],
    ['held picks re-priced by the client count at the baseline', previous.picks.map((p) =>
      ({ ...p, priceTenths: 5 })), -5, false],
    ["sold D1, then took him back at today's price: held at 80, no sale",
      swap({ D1: pick('D1', 95) }), -5, false],
    ['sold A3, who left the market, for NA2: the sale adds 0',
      swap({ A3: pick('NA2', 40, 'ATT', true) }), -5, false],
    ["spent exactly the room the riser's sale made", swap({ D1: pick('ND2', 87) }), 2, false],
    ['one tenth more is over budget', swap({ D1: pick('ND3', 88) }), 2, true],
  ];
  for (const [label, picks, realized, over] of cases) {
    it(label, () => {
      const squad: FantasySquad = { picks, captainId: 'A1', viceId: 'G1', chip: null };
      const server = judgeSale(squad, market, previous, carried, lastWeek);
      expect(server.realizedTenths).toBe(realized);
      expect(picks.map((p) => app.priceOfPick(p))).toEqual(server.prices);
      expect(app.realizedFor(picks.map((p) => p.playerId))).toBe(server.realizedTenths);
      expect(squadIntegrityIssues(squad, cfg, market, previous, carried, lastWeek)
        .includes('overBudget')).toBe(over);
      expect(app.issues(squad, cfg).includes('overBudget')).toBe(over);
    });
  }
});
