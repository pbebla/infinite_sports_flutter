// Push audiences (spec §3): every fantasy manager (Managers ∪ Squads) and
// the owners of named players (current squad, starters or bench), parsed
// through the stored-squad parser — malformed squads are skipped.

import { describe, expect, it } from 'vitest';
import { allManagers, ownersOf } from './audiences';

function pick(playerId: string, position: string, bench = false) {
  return { playerId, position, priceTenths: 50, bench };
}

function squad(starters: string[], bench: string[] = []) {
  return {
    picks: [
      ...starters.map((n, i) => pick(n, i === 0 ? 'GK' : 'ATT')),
      ...bench.map((n) => pick(n, 'DEF', true)),
    ],
    captainId: starters[1] ?? starters[0],
    viceId: starters[2] ?? starters[0],
  };
}

describe('allManagers', () => {
  it('union of Managers and Squads keys, sorted', () => {
    expect(allManagers(
      { u2: { TeamName: 'B' }, u1: true },
      { u3: squad(['K', 'A', 'B']), u1: squad(['K', 'A', 'B']) },
    )).toEqual(['u1', 'u2', 'u3']);
  });

  it('absent nodes -> []', () => {
    expect(allManagers(null, null)).toEqual([]);
    expect(allManagers(undefined, { u9: squad(['K', 'A', 'B']) }))
      .toEqual(['u9']);
  });
});

describe('ownersOf', () => {
  const squads = {
    u3: squad(['K', 'Zed', 'B']),
    u1: squad(['K', 'Alex', 'B']), // starter
    u2: { ...squad(['K', 'A', 'B'], ['Alex']), ServerWriteAt: 123 }, // bench
    u4: { ...squad(['K', 'Alex', 'B']), picks: 'nope' }, // malformed
    u5: true, // not a squad
    u6: { ...squad(['K', 'Alex', 'B']), captainId: 7 }, // malformed
    u7: { ...squad(['K', 'B', 'C']), picks: [pick('Alex', 'MID')] }, // bad pos
  };

  it('starters and bench both count; malformed squads skipped; sorted', () => {
    expect(ownersOf(squads, ['Alex'])).toEqual(['u1', 'u2']);
  });

  it('any of several names', () => {
    expect(ownersOf(squads, ['Zed', 'Alex'])).toEqual(['u1', 'u2', 'u3']);
  });

  it('no names / unknown names / no squads -> []', () => {
    expect(ownersOf(squads, [])).toEqual([]);
    expect(ownersOf(squads, ['Nobody'])).toEqual([]);
    expect(ownersOf(null, ['Alex'])).toEqual([]);
  });
});
