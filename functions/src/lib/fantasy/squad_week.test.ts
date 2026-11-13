// Port of test/fantasy/squad_week_test.dart — armband fallback, auto-sub
// edge cases, bench tenths integer math, chips.
import { describe, expect, it } from 'vitest';
import { FantasyPosition, futsalDefault } from './fantasy_config';
import { FantasySquad, SquadPick } from './squad';
import {
  PlayerWeek, scoreSquadWeek, slotOf, totalTenths,
} from './squad_week';

const cfg = futsalDefault();

function p(id: string, pos: FantasyPosition, bench = false): SquadPick {
  return { playerId: id, position: pos, priceTenths: 50, bench };
}

function squad(
  { captain = 'a1', vice = 'd1', chip = null as string | null } = {},
): FantasySquad {
  return {
    picks: [
      p('g1', 'GK'),
      p('d1', 'DEF'),
      p('d2', 'DEF'),
      p('a1', 'ATT'),
      p('a2', 'ATT'),
      p('d3', 'DEF', true),
      p('a3', 'ATT', true),
    ],
    captainId: captain,
    viceId: vice,
    chip,
  };
}

function wk(
  m: Record<string, [number, boolean]>,
): Record<string, PlayerWeek> {
  const out: Record<string, PlayerWeek> = {};
  for (const [k, [points, played]] of Object.entries(m)) {
    out[k] = { points, played };
  }
  return out;
}

const allPlay = wk({
  g1: [6, true], d1: [5, true], d2: [4, true],
  a1: [10, true], a2: [3, true], d3: [7, true], a3: [2, true],
});

describe('squad_week', () => {
  it('normal week: starters full, captain x2, bench half', () => {
    const r = scoreSquadWeek(squad(), allPlay, cfg);
    // starters: 6+5+4+10+3 = 28, captain a1 doubles -> +10, bench half: (7+2)/2 = 4.5
    expect(totalTenths(r)).toBe(280 + 100 + 45);
    expect(slotOf(r, 'a1').multiplier).toBe(2);
    expect(slotOf(r, 'd3').countedTenths).toBe(35);
  });
  it('captain absent -> vice doubles', () => {
    const m = wk({
      g1: [6, true], d1: [5, true], d2: [4, true],
      a1: [0, false], a2: [3, true], d3: [7, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad(), m, cfg);
    expect(slotOf(r, 'd1').multiplier).toBe(2);
    // a1 absent -> bench a3 auto-subbed in at FULL; d3 stays half
    expect(slotOf(r, 'a3').countedTenths).toBe(20);
    expect(slotOf(r, 'a3').autoSubbedIn).toBe(true);
    expect(slotOf(r, 'd3').countedTenths).toBe(35);
    expect(totalTenths(r)).toBe((6 + 5 + 5 + 4 + 3 + 2) * 10 + 35);
  });
  it('both captain and vice absent -> nobody doubles', () => {
    const m = wk({
      g1: [6, true], d1: [0, false], d2: [4, true],
      a1: [0, false], a2: [3, true], d3: [7, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad(), m, cfg);
    expect(r.slots.filter((s) => s.multiplier > 1)).toEqual([]);
  });
  it('absent DEF starter -> bench DEF in full, bench ATT stays half', () => {
    const m = wk({
      g1: [6, true], d1: [5, true], d2: [0, false],
      a1: [10, true], a2: [3, true], d3: [7, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad(), m, cfg);
    expect(slotOf(r, 'd3').countedTenths).toBe(70);
    expect(slotOf(r, 'a3').countedTenths).toBe(10);
  });
  it('two absent ATT starters, one bench ATT covers one; other scores 0', () => {
    const m = wk({
      g1: [6, true], d1: [5, true], d2: [4, true],
      a1: [0, false], a2: [0, false], d3: [7, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad({ captain: 'g1', vice: 'd1' }), m, cfg);
    expect(slotOf(r, 'a3').autoSubbedIn).toBe(true);
    expect(slotOf(r, 'a3').countedTenths).toBe(20);
    // absent starters contribute 0; d3 half
    expect(totalTenths(r)).toBe((6 * 2 + 5 + 4 + 2) * 10 + 35);
  });
  it('absent GK has no cover (no bench GK by design)', () => {
    const m = wk({
      g1: [0, false], d1: [5, true], d2: [4, true],
      a1: [10, true], a2: [3, true], d3: [7, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad(), m, cfg);
    expect(slotOf(r, 'g1').countedTenths).toBe(0);
    expect(r.slots.filter((s) => s.autoSubbedIn)).toHaveLength(0);
  });
  it('bench boost: bench full, no auto-sub semantics change', () => {
    const r = scoreSquadWeek(squad({ chip: 'benchBoost' }), allPlay, cfg);
    // starters 28 + captain extra 10 + bench full 7+2 = 47 pts = 470 tenths
    expect(totalTenths(r)).toBe((28 + 10 + 7 + 2) * 10);
  });
  it('triple captain: x3', () => {
    const r = scoreSquadWeek(squad({ chip: 'tripleCaptain' }), allPlay, cfg);
    expect(slotOf(r, 'a1').multiplier).toBe(3);
    expect(totalTenths(r)).toBe(280 + 200 + 45);
  });
  it('absent bench player scores zero even boosted', () => {
    const m = wk({
      g1: [6, true], d1: [5, true], d2: [4, true],
      a1: [10, true], a2: [3, true], d3: [0, false], a3: [2, true],
    });
    const r = scoreSquadWeek(squad({ chip: 'benchBoost' }), m, cfg);
    expect(slotOf(r, 'd3').countedTenths).toBe(0);
  });
  it('negative bench points truncate toward zero like Dart ~/', () => {
    // -3 pts on the half bench: -3*1*50 = -150, ~/10 = -15 (golden pins this);
    // a non-multiple like -31*50=-1550... use points -31: trunc(-155)= -155?
    // Simplest divergent case: points=-1 -> -1*50/10 = -5 exactly; use
    // benchFactorPercent 25 to force a fraction: -1*25/10 = -2.5 -> Dart -2.
    const tweaked = { ...cfg, benchFactorPercent: 25 };
    const m = wk({
      g1: [6, true], d1: [5, true], d2: [4, true],
      a1: [10, true], a2: [3, true], d3: [-1, true], a3: [2, true],
    });
    const r = scoreSquadWeek(squad(), m, tweaked);
    expect(slotOf(r, 'd3').countedTenths).toBe(-2); // floor would say -3
  });
});
