// Port of test/fantasy/scoring_test.dart.
import { describe, expect, it } from 'vitest';
import { FANTASY_POSITIONS, futsalDefault } from './fantasy_config';
import {
  PlayerGameStats, playedGame, playerGameStats,
} from './player_game_stats';
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
  it('every line carries a stable key and count', () => {
    // conceded 1: no clean sheet; ATT never loses points for conceding.
    const r = scorePlayerGame(
      s({ goals: 2, assists: 1, yellows: 1, conceded: 1 }), 'ATT', cfg);
    expect(r.breakdown.map((l) => [l.key, l.count])).toEqual([
      ['plays', 1], ['goals', 2], ['assists', 1], ['yellow', 1],
    ]);
    // Labels and points are untouched by the new fields.
    expect(r.breakdown.map((l) => [l.label, l.points])).toEqual([
      ['Plays', 1], ['Goals ×2', 8], ['Assists ×1', 3], ['Yellow ×1', -1],
    ]);
  });
  it('keys/counts for every other source (the stat each count is)', () => {
    const def = scorePlayerGame(s({
      goals: 1, assists: 2, dpl: 6, conceded: 3, yellows: 1, reds: 1,
      ownGoals: 1, penMissed: 1,
    }), 'DEF', cfg);
    expect(def.breakdown.map((l) => [l.key, l.count])).toEqual([
      ['plays', 1], ['goals', 1], ['assists', 2], ['penMissed', 1],
      ['conceded', 3], ['dpl', 6], ['yellow', 1], ['red', 1], ['ownGoals', 1],
    ]);
    const gk = scorePlayerGame(s({ saves: 5, penSaved: 1 }), 'GK', cfg);
    expect(gk.breakdown.map((l) => [l.key, l.count])).toEqual([
      ['plays', 1], ['cleanSheet', 1], ['saves', 5], ['penSaved', 1],
    ]);
  });
  it('forfeit-won Plays line is keyed plays/1', () => {
    const r = scorePlayerGame(s({ forfeit: 'won' }), 'GK', cfg);
    expect(r.breakdown).toEqual([
      { label: 'Plays', points: 1, key: 'plays', count: 1 },
    ]);
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

describe('scoring — forfeits (spec §8a, Option B)', () => {
  it('team that showed up: ONLY the Plays line, every position — no clean ' +
    'sheet even at 0 conceded, stray stats ignored', () => {
    for (const pos of FANTASY_POSITIONS) {
      const r = scorePlayerGame(s({ forfeit: 'won', goals: 2 }), pos, cfg);
      expect(r.total, pos).toBe(1);
      expect(r.breakdown.map((l) => l.label), pos).toEqual(['Plays']);
    }
  });
  it('team that showed up: an absent player still gets 0', () => {
    const r = scorePlayerGame(s({ forfeit: 'won', present: false }), 'DEF', cfg);
    expect(r.total).toBe(0);
    expect(r.breakdown).toEqual([]);
  });
  it('forfeiting team: 0, no appearance, no goals-conceded penalty', () => {
    for (const pos of FANTASY_POSITIONS) {
      const r = scorePlayerGame(s({ forfeit: 'lost', conceded: 5 }), pos, cfg);
      expect(r.total, pos).toBe(0);
      expect(r.breakdown, pos).toEqual([]);
    }
  });
  it('played: showing-up present = played; forfeiting team = NOT played', () => {
    expect(playedGame(s({ forfeit: 'won' }))).toBe(true);
    expect(playedGame(s({ forfeit: 'won', present: false }))).toBe(false);
    expect(playedGame(s({ forfeit: 'lost' }))).toBe(false);
    expect(playedGame(s({ forfeit: 'none' }))).toBe(true);
    expect(playedGame({ ...s(), forfeit: undefined })).toBe(true);

    const forfeitOnly = scorePlayerWeek([s({ forfeit: 'lost' })], 'GK', cfg);
    expect(forfeitOnly.total).toBe(0);
    expect(forfeitOnly.played).toBe(false);

    const twoGames = scorePlayerWeek(
      [s({ forfeit: 'lost' }), s({ conceded: 1 })], 'ATT', cfg);
    expect(twoGames.total).toBe(1);
    expect(twoGames.played).toBe(true);
  });
});
