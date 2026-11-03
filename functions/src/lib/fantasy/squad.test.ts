// Port of test/fantasy/squad_test.dart.
import { describe, expect, it } from 'vitest';
import { FantasyPosition, futsalDefault } from './fantasy_config';
import {
  FantasySquad, SquadPick, spentTenths, squadFromMap, squadToMap,
  validateSquad,
} from './squad';

const cfg = futsalDefault();

function p(
  id: string, pos: FantasyPosition, price: number, bench = false,
): SquadPick {
  return { playerId: id, position: pos, priceTenths: price, bench };
}

function legal(): SquadPick[] {
  return [
    p('g1', 'GK', 70),
    p('d1', 'DEF', 80),
    p('d2', 'DEF', 60),
    p('a1', 'ATT', 90),
    p('a2', 'ATT', 80),
    p('d3', 'DEF', 50, true),
    p('a3', 'ATT', 50, true),
  ];
}

function squad(
  picks: SquadPick[], captainId = 'a1', viceId = 'd1',
): FantasySquad {
  return { picks, captainId, viceId, chip: null };
}

describe('squad', () => {
  it('legal squad validates with no errors', () => {
    expect(validateSquad(squad(legal()), cfg)).toEqual([]);
  });
  it('budget overflow flagged', () => {
    const picks = legal();
    picks[3] = p('a1', 'ATT', 150);
    expect(validateSquad(squad(picks), cfg)).toContain('overBudget');
  });
  it('wrong formation flagged (2 GKs)', () => {
    const picks = legal();
    picks[1] = p('g2', 'GK', 60);
    expect(validateSquad(squad(picks, 'a1', 'g1'), cfg)).toContain('formation');
  });
  it('wrong bench composition flagged', () => {
    const picks = legal();
    picks[5] = p('d3', 'DEF', 50);
    picks[6] = p('a3', 'ATT', 50, true);
    picks.push(p('a4', 'ATT', 40, true));
    expect(validateSquad(squad(picks), cfg)).toContain('formation');
  });
  it('duplicate player flagged', () => {
    const picks = legal();
    picks[4] = p('a1', 'ATT', 80);
    expect(validateSquad(squad(picks), cfg)).toContain('duplicatePlayer');
  });
  it('captain must be a starter; vice must differ', () => {
    expect(validateSquad(squad(legal(), 'd3', 'd1'), cfg))
      .toContain('badCaptain');
    expect(validateSquad(squad(legal(), 'a1', 'a1'), cfg))
      .toContain('badCaptain');
  });
  it('round-trips through RTDB-safe map', () => {
    const s = squad(legal());
    expect(squadToMap(squadFromMap(squadToMap(s)))).toEqual(squadToMap(s));
  });
  it('fromMap skips non-map picks and throws on bad types', () => {
    const m = squadToMap(squad(legal()));
    (m['picks'] as unknown[]).push(null, 'junk'); // whereType<Map> drops these
    expect(squadFromMap(m).picks).toHaveLength(7);
    expect(() => squadFromMap({ ...m, picks: 'nope' })).toThrow();
    expect(() => squadFromMap({ ...m, captainId: 7 })).toThrow();
  });
  it('spentTenths and bank', () => {
    const s = squad(legal());
    expect(spentTenths(s)).toBe(480);
    expect(cfg.budgetTenths - spentTenths(s)).toBe(20);
  });

  // The budget rule is spent <= budget + realizedTenths (FPL selling, spec §4).
  // legal() spends 480; raising a1 from 90 by n tenths spends 480 + n.
  function spending(total: number): FantasySquad {
    const picks = legal();
    picks[3] = p('a1', 'ATT', 90 + (total - 480));
    expect(spentTenths(squad(picks))).toBe(total);
    return squad(picks);
  }
  it('realized profit lifts the budget: spent 505 with realized 5 is legal', () => {
    expect(validateSquad(spending(505), cfg, 5)).not.toContain('overBudget');
  });
  it('one tenth past budget + realized is overBudget: 506 with realized 5', () => {
    expect(validateSquad(spending(506), cfg, 5)).toContain('overBudget');
  });
  it('realized loss shrinks the budget: spent 500 with realized -1', () => {
    expect(validateSquad(spending(500), cfg, -1)).toContain('overBudget');
    expect(validateSquad(spending(499), cfg, -1)).not.toContain('overBudget');
  });
  it('realized defaults to 0: spent 500 legal, 501 over', () => {
    expect(validateSquad(spending(500), cfg)).not.toContain('overBudget');
    expect(validateSquad(spending(501), cfg)).toContain('overBudget');
  });
});
