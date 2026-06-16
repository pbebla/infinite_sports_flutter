import { describe, expect, test } from 'vitest';
import { predictionPoints, computeLeaderboard, questionPoints, computeLeaderboardV2 } from '../src/lib/predict';

const SCORING = { matchWinner: 1, exactScore: 3 };

describe('predictionPoints', () => {
  test('exact', () => {
    expect(predictionPoints(2, 1, 2, 1, SCORING)).toEqual(
      { resultCorrect: true, exactCorrect: true, points: 4 });
  });
  test('result only', () => {
    expect(predictionPoints(2, 1, 3, 0, SCORING).points).toBe(1);
  });
  test('wrong', () => {
    expect(predictionPoints(2, 1, 0, 1, SCORING).points).toBe(0);
  });
  test('draw exact', () => {
    expect(predictionPoints(0, 0, 0, 0, SCORING).points).toBe(4);
  });
});

describe('computeLeaderboard', () => {
  const finals = [
    { id: 'm1', team1Score: 2, team2Score: 1, startedAtMs: 1000 },
    { id: 'm2', team1Score: 0, team2Score: 0, startedAtMs: 2000 },
  ];
  const preds = {
    m1: [
      { uid: 'u1', team1: 2, team2: 1, updatedAt: 900 },
      { uid: 'u2', team1: 1, team2: 0, updatedAt: 900 },
      { uid: 'u3', team1: 2, team2: 1, updatedAt: 1500 },
    ],
    m2: [
      { uid: 'u1', team1: 0, team2: 0, updatedAt: 1000 },
    ],
  };

  test('sums points, counts exact, ignores late picks', () => {
    const lb = computeLeaderboard(finals, preds, SCORING);
    expect(lb['u1']).toEqual({ points: 8, exact: 2 });
    expect(lb['u2']).toEqual({ points: 1, exact: 0 });
    expect(lb['u3']).toBeUndefined();
  });

  test('idempotent (running twice is identical)', () => {
    const a = computeLeaderboard(finals, preds, SCORING);
    const b = computeLeaderboard(finals, preds, SCORING);
    expect(a).toEqual(b);
  });

  test('drops qualifying users who scored zero (leaderboard = scorers only)', () => {
    const lb = computeLeaderboard(
      [{ id: 'm1', team1Score: 2, team2Score: 1, startedAtMs: 1000 }],
      { m1: [{ uid: 'z1', team1: 0, team2: 3, updatedAt: 900 }] }, // wrong winner -> 0 pts
      SCORING,
    );
    expect(lb['z1']).toBeUndefined();
  });
});

describe('questionPoints', () => {
  const winner = { id: 'w', type: 'matchWinner' as const, points: 1, line: null };
  test('winner correct/wrong', () => {
    expect(questionPoints(winner, 'team1', 2, 1, null).points).toBe(1);
    expect(questionPoints(winner, 'draw', 2, 1, null).points).toBe(0);
  });
  test('correctScore exact', () => {
    const r = questionPoints({ id: 's', type: 'correctScore' as const, points: 3, line: null }, '2-1', 2, 1, null);
    expect(r.points).toBe(3); expect(r.isExactScore).toBe(true);
  });
  test('totalGoals on-the-line is under', () => {
    const q = { id: 't', type: 'totalGoals' as const, points: 2, line: 3 };
    expect(questionPoints(q, 'under', 2, 1, null).points).toBe(2);
    expect(questionPoints(q, 'over', 2, 1, null).points).toBe(0);
  });
  test('custom needs result', () => {
    const q = { id: 'c', type: 'custom' as const, points: 2, line: null };
    expect(questionPoints(q, 'o1', 0, 0, 'o1').points).toBe(2);
    expect(questionPoints(q, 'o1', 0, 0, null).points).toBe(0);
  });
});

describe('computeLeaderboardV2', () => {
  test('sums per-question points across questions + matches, drops zero, honors lock', () => {
    const finals = [{ id: 'm1', team1Score: 2, team2Score: 1, startedAtMs: 1000 }];
    const questionsByMatch = { m1: [
      { id: 'w', type: 'matchWinner' as const, points: 1, line: null },
      { id: 's', type: 'correctScore' as const, points: 3, line: null },
    ]};
    const answers = { m1: {
      u1: { w: { value: 'team1', updatedAt: 900 }, s: { value: '2-1', updatedAt: 900 } },
      u2: { w: { value: 'team1', updatedAt: 900 }, s: { value: '0-0', updatedAt: 900 } },
      u3: { w: { value: 'team1', updatedAt: 1500 } }, // late -> ignored
    }};
    const results = {}; // no custom
    const lb = computeLeaderboardV2(finals, questionsByMatch, answers, results);
    expect(lb['u1']).toEqual({ points: 4, exact: 1 });
    expect(lb['u2']).toEqual({ points: 1, exact: 0 });
    expect(lb['u3']).toBeUndefined();
  });
});
