// Port of test/fantasy/bps_test.dart — the 3/2/1 tie-sharing ladder is part
// of the published Rules page and the golden contract.
import { describe, expect, it } from 'vitest';
import { awardBonus, bpsScore } from './bps';
import { futsalDefault } from './fantasy_config';
import { playerGameStats } from './player_game_stats';

const cfg = futsalDefault();

describe('bps', () => {
  it('bps raw score', () => {
    // goal 12*2 + assist 9 + save 2*3 + yellow -4 = 35
    expect(bpsScore(playerGameStats(
      { goals: 2, assists: 1, saves: 3, yellows: 1, teamConceded: 1 }), cfg))
      .toBe(35);
  });
  it('absent player has no bps', () => {
    expect(bpsScore(playerGameStats({ goals: 2, present: false }), cfg)).toBe(0);
  });
  it('a forfeited game puts 0 into BPS for BOTH sides (spec §8a) — so it ' +
    'awards no bonus', () => {
    const won = playerGameStats({ goals: 1, forfeit: 'won' });
    const lost = playerGameStats({ saves: 4, teamConceded: 5, forfeit: 'lost' });
    expect(bpsScore(won, cfg)).toBe(0);
    expect(bpsScore(lost, cfg)).toBe(0);
    expect(awardBonus({ w: bpsScore(won, cfg), l: bpsScore(lost, cfg) }))
      .toEqual({});
  });
  it('top three get 3/2/1', () => {
    expect(awardBonus({ a: 50, b: 40, c: 30, d: 20 }))
      .toEqual({ a: 3, b: 2, c: 1 });
  });
  it('tie for first: both get 3, next gets 1', () => {
    expect(awardBonus({ a: 50, b: 50, c: 30, d: 20 }))
      .toEqual({ a: 3, b: 3, c: 1 });
  });
  it('tie for second: 3,2,2 and nobody gets 1', () => {
    expect(awardBonus({ a: 50, b: 40, c: 40, d: 20 }))
      .toEqual({ a: 3, b: 2, c: 2 });
  });
  it('triple tie for first: 3,3,3', () => {
    expect(awardBonus({ a: 50, b: 50, c: 50, d: 20 }))
      .toEqual({ a: 3, b: 3, c: 3 });
  });
  it('zero/negative bps earn nothing', () => {
    expect(awardBonus({ a: 0, b: -5, c: 10 })).toEqual({ c: 3 });
  });
  it('fewer than three players', () => {
    expect(awardBonus({ a: 10 })).toEqual({ a: 3 });
  });
});
