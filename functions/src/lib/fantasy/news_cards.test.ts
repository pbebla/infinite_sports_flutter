// News player-card snapshots (spec §4.1): season goal/assist tallies over
// the real Date-node shapes (List- and Map-coerced games, case-insensitive
// keys, PenGoal, forfeits + friendlies ignored), the card builder over the
// RTDB node shapes (latest gw = numeric max key, Manual flag ignored,
// PlayerTotals as map or bare number, optional fields OMITTED) and the
// RTDB-safe cards node.

import { describe, expect, it } from 'vitest';
import {
  buildPlayerCard, cardsNode, PlayerCard, seasonGoalsAssists,
} from './news_cards';

// `<sport>/<season>/Date` — two match days:
// - 10072026 arrives LIST-coerced (null hole), with a forfeited game whose
//   stray activity must not count;
// - 10142026 arrives as an index-keyed MAP (hole collapsing) and holds a
//   friendly that must not count.
function dateNode(): Record<string, unknown> {
  return {
    '10072026': [
      {
        team1: 'Sharks', team2: 'Wolves', status: 2,
        team1score: 2, team2score: 1,
        team1activity: {
          "5'": [{ Goal: 'Alex', _t: 1111 }, { Assist: 'Dana' }],
          "9'": [{ PenGoal: 'Alex' }],
        },
        // activity list-coerced, null padding, lower/upper-case keys
        team2activity: [
          null,
          [{ goal: 'Wren' }],
          [{ ASSIST: 'Wes' }, { Foul: 'Wes' }, null],
        ],
      },
      null,
      {
        team1: 'Bears', team2: 'Lions', status: 2, forfeitedBy: 1,
        team1activity: { "1'": [{ Goal: 'Stray' }] },
      },
    ],
    '10142026': {
      '0': {
        team1: 'Sharks', team2: 'Bears', status: 2,
        team1activity: {
          "3'": [{ Goal: 'Dana' }, { Assist: 'Alex' }],
        },
        team2activity: {
          "7'": { '0': { PenGoal: 'Bo' } }, // bucket index-Map-coerced
        },
      },
      '2': {
        Stage: 'friendly', team1: 'Sharks', team2: 'Wolves', status: 2,
        team1activity: { "1'": [{ Goal: 'Alex' }] },
      },
    },
  };
}

describe('seasonGoalsAssists', () => {
  it('tallies Goal+PenGoal and Assist across every game of the season', () => {
    expect(seasonGoalsAssists(dateNode())).toEqual({
      Alex: { goals: 2, assists: 1 }, // friendly goal not counted
      Dana: { goals: 1, assists: 1 },
      Wren: { goals: 1, assists: 0 },
      Wes: { goals: 0, assists: 1 },
      Bo: { goals: 1, assists: 0 },
      // Stray: forfeited game's activity ignored
    });
  });

  it('a game without team names is skipped, never throws', () => {
    expect(seasonGoalsAssists({
      '10212026': [{ team1activity: { "1'": [{ Goal: 'Ghost' }] } }],
    })).toEqual({});
  });

  it('absent / junk Date node -> {}', () => {
    expect(seasonGoalsAssists(null)).toEqual({});
    expect(seasonGoalsAssists('junk')).toEqual({});
  });
});

const playersRaw = {
  Alex: {
    position: 'ATT', priceTenths: 85, eligible: true, teamName: 'Sharks',
    photoUrl: ' https://img/alex.jpg ',
  },
  Sam: { position: 'GK', priceTenths: '60', eligible: true, teamName: 'Wolves' },
  Bad: { position: 'MID', priceTenths: 50, eligible: true, teamName: 'X' },
};

describe('buildPlayerCard', () => {
  const src = {
    playersRaw,
    playerTotalsRaw: { Alex: { points: 31, ownershipPct: 42 }, Sam: 12 },
    // gw keys are small ints -> list-coerced; gw 2 is the latest
    playerWeeksRaw: [null, { Alex: 4, Sam: 2 }, { Alex: 9, Sam: 1 }],
    priceChangesRaw: {
      '1': { Alex: { delta: 5 } },
      '2': { Manual: true, Alex: { delta: -3 } },
    },
    goalsAssists: { Alex: { goals: 2, assists: 1 } },
  };

  it('full card from every source (latest week, Manual flag ignored)', () => {
    expect(buildPlayerCard('Alex', src)).toEqual({
      name: 'Alex', position: 'ATT', team: 'Sharks',
      photoUrl: 'https://img/alex.jpg', priceTenths: 85, priceDeltaTenths: -3,
      gw: 2, gwPoints: 9, seasonPoints: 31, ownershipPct: 42,
      goals: 2, assists: 1,
    });
  });

  it('PlayerTotals as a bare number = season points; unknown optionals OMITTED', () => {
    const card = buildPlayerCard('Sam', src)!;
    expect(card).toEqual({
      name: 'Sam', position: 'GK', team: 'Wolves', priceTenths: 60,
      gw: 2, gwPoints: 1, seasonPoints: 12, goals: 0, assists: 0,
    });
    // RTDB rejects undefined: the keys must be absent, not undefined
    for (const k of ['photoUrl', 'priceDeltaTenths', 'ownershipPct']) {
      expect(Object.prototype.hasOwnProperty.call(card, k)).toBe(false);
    }
    expect(Object.values(card).every((v) => v !== undefined)).toBe(true);
  });

  it('latest gw is the NUMERIC max key (10 beats 9) in each node', () => {
    const card = buildPlayerCard('Alex', {
      ...src,
      playerWeeksRaw: { '9': { Alex: 3 }, '10': { Alex: 7 } },
      priceChangesRaw: { '9': { Alex: { delta: 1 } }, '10': { Alex: { delta: 2 } } },
    })!;
    expect(card.gw).toBe(10);
    expect(card.gwPoints).toBe(7);
    expect(card.priceDeltaTenths).toBe(2);
  });

  it('player missing from the latest week: gw kept, gwPoints / delta omitted', () => {
    const card = buildPlayerCard('Alex', {
      ...src,
      playerWeeksRaw: { '1': { Alex: 4 }, '2': { Sam: 1 } },
      priceChangesRaw: { '1': { Alex: { delta: 5 } }, '2': { Sam: { delta: 1 } } },
    })!;
    expect(card.gw).toBe(2);
    expect(Object.prototype.hasOwnProperty.call(card, 'gwPoints')).toBe(false);
    expect(Object.prototype.hasOwnProperty.call(card, 'priceDeltaTenths')).toBe(false);
  });

  it('no weeks / totals / price changes yet -> base card only', () => {
    expect(buildPlayerCard('Alex', {
      playersRaw,
      playerTotalsRaw: null,
      playerWeeksRaw: null,
      priceChangesRaw: null,
      goalsAssists: {},
    })).toEqual({
      name: 'Alex', position: 'ATT', team: 'Sharks',
      photoUrl: 'https://img/alex.jpg', priceTenths: 85, goals: 0, assists: 0,
    });
  });

  it('unknown name or unusable position -> null', () => {
    expect(buildPlayerCard('Nobody', src)).toBeNull();
    expect(buildPlayerCard('Bad', src)).toBeNull();
    expect(buildPlayerCard('Alex', { ...src, playersRaw: null })).toBeNull();
  });
});

describe('cardsNode', () => {
  const card = (name: string): PlayerCard => ({
    name, position: 'DEF', team: 'T', priceTenths: 50, goals: 0, assists: 0,
  });

  it('empty -> null', () => {
    expect(cardsNode([])).toBeNull();
    expect(cardsNode([null])).toBeNull();
  });

  it('input order, unknown (null) names dropped, index keys', () => {
    expect(cardsNode([card('A'), null, card('B')])).toEqual({
      '0': card('A'), '1': card('B'),
    });
  });

  it('caps at 5', () => {
    const node = cardsNode(['A', 'B', 'C', 'D', 'E', 'F'].map(card))!;
    expect(Object.keys(node)).toEqual(['0', '1', '2', '3', '4']);
    expect(node['4'].name).toBe('E');
  });

  it('strips undefined optionals so RTDB accepts the node', () => {
    const node = cardsNode([{ ...card('A'), photoUrl: undefined, gw: 3 }])!;
    expect(node['0']).toEqual({ ...card('A'), gw: 3 });
    expect(Object.prototype.hasOwnProperty.call(node['0'], 'photoUrl')).toBe(false);
  });
});
