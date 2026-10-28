// Port of test/fantasy/scoring_test.dart.
import { describe, expect, it } from 'vitest';
import { futsalDefault } from './fantasy_config';
import { PlayerGameStats, playerGameStats } from './player_game_stats';
import { scorePlayerGame, scorePlayerWeek } from './scoring';

const cfg = futsalDefault();

function s(p: Partial<PlayerGameStats> & { conceded?: number } = {}): PlayerGameStats {
  const { conceded, ...rest } = p;
  return playerGameStats({ ...rest, teamConceded: conceded ?? 0 });
}

describe('scoring', () => {
  it('absent player scores zero regardless of stats', () => {
    const r = scorePlayerGame(s({ goals: 3, present: false }), 'ATT', cfg);
    expect(r.total).toBe(0);
    expect(r.breakdown).toEqual([]);
  });
  it('appearance point (CS suppressed by a conceded goal)', () => {
    expect(scorePlayerGame(s({ conceded: 1 }), 'DEF', cfg).total).toBe(1);
  });
  it('GK goal is +10 on top of plays', () => {
    expect(scorePlayerGame(s({ goals: 1, conceded: 1 }), 'GK', cfg).total)
      .toBe(1 + 10);
  });
  it('clean sheet needs present + zero conceded', () => {
    expect(scorePlayerGame(s(), 'GK', cfg).total).toBe(1 + 8);
    expect(scorePlayerGame(s({ conceded: 1 }), 'GK', cfg).total).toBe(1);
  });
  it('every 2 saves = +1 (GK), floors', () => {
    expect(scorePlayerGame(s({ saves: 5 }), 'GK', cfg).total)
      .toBe(1 + 8 + 2); // plays + CS + floor(5/2)
  });
  it('ATT never loses for conceding; GK/DEF lose 1 per 2', () => {
    expect(scorePlayerGame(s({ conceded: 4 }), 'ATT', cfg).total).toBe(1);
    expect(scorePlayerGame(s({ conceded: 4 }), 'DEF', cfg).total).toBe(1 - 2);
    expect(scorePlayerGame(s({ conceded: 5 }), 'GK', cfg).total).toBe(1 - 2);
  });
  it('DPL threshold bonus (conceded: 1 suppresses CS, too few to deduct)', () => {
    expect(scorePlayerGame(s({ dpl: 5, conceded: 1 }), 'DEF', cfg).total)
      .toBe(1 + 2);
    expect(scorePlayerGame(s({ dpl: 4, conceded: 1 }), 'DEF', cfg).total)
      .toBe(1);
    expect(scorePlayerGame(s({ dpl: 7, conceded: 1 }), 'ATT', cfg).total)
      .toBe(1 + 2);
    expect(scorePlayerGame(s({ dpl: 99, conceded: 1 }), 'GK', cfg).total)
      .toBe(1); // GK has no DPL threshold
  });
  it('cards, own goals, pens', () => {
    expect(scorePlayerGame(s({ yellows: 1, reds: 1, conceded: 1 }), 'ATT', cfg)
      .total).toBe(1 - 1 - 3);
    expect(scorePlayerGame(s({ ownGoals: 1, conceded: 1 }), 'DEF', cfg).total)
      .toBe(1 - 2);
    expect(scorePlayerGame(s({ penSaved: 1 }), 'GK', cfg).total)
      .toBe(1 + 8 + 5);
    expect(scorePlayerGame(s({ penMissed: 1, conceded: 1 }), 'ATT', cfg).total)
      .toBe(1 - 2);
  });
  it('kitchen-sink DEF example matches hand math', () => {
    // plays 1 + goal 6 + assist 4 + dpl(6>=5) 2 - conceded(3)/2 1 - yellow 1 = 11
    expect(scorePlayerGame(
      s({ goals: 1, assists: 1, dpl: 6, conceded: 3, yellows: 1 }),
      'DEF', cfg).total).toBe(11);
  });
  it('breakdown lines sum to total', () => {
    const r = scorePlayerGame(s({ goals: 2, saves: 4, conceded: 2 }), 'GK', cfg);
    expect(r.breakdown.reduce((a, b) => a + b.points, 0)).toBe(r.total);
  });
  it('gameweek sum across multiple games', () => {
    const wk = scorePlayerWeek(
      [s({ goals: 1, conceded: 1 }), s({ conceded: 2, yellows: 1 })],
      'ATT', cfg);
    expect(wk.total).toBe((1 + 4) + (1 - 1));
    expect(wk.played).toBe(true);
  });
  it('week with no present games = not played', () => {
    const wk = scorePlayerWeek([s({ present: false })], 'ATT', cfg);
    expect(wk.total).toBe(0);
    expect(wk.played).toBe(false);
  });
});
