import { describe, expect, test } from 'vitest';
import { predictionPoints, computeLeaderboard, questionPoints, computeLeaderboardV2, matchStatLeaders } from '../src/lib/predict';

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

  test('playerAward: awards fans who picked the match leader', () => {
    const finals = [{ id: 'm1', team1Score: 0, team2Score: 0, startedAtMs: 1000,
      team1Activity: { '5': [{ Goal: 'Alex' }, { Goal: 'Alex' }] }, team2Activity: { '7': [{ Goal: 'Bea' }] } }];
    const qs = { m1: [{ id: 'pg', type: 'playerAward' as const, points: 2, line: null, stat: 'goals' }] };
    const answers = { m1: {
      u1: { pg: { value: 'Alex', updatedAt: 900 } }, // correct (Alex 2 > Bea 1)
      u2: { pg: { value: 'Bea', updatedAt: 900 } },  // wrong
    }};
    const lb = computeLeaderboardV2(finals, qs, answers, {});
    expect(lb['u1']).toEqual({ points: 2, exact: 0 });
    expect(lb['u2']).toBeUndefined();
  });
});

describe('matchStatLeaders', () => {
  const t1 = { '10': [{ Goal: 'Alex' }], '20': [{ Goal: 'Alex' }, { Assist: 'Sam' }] };
  const t2 = { '30': [{ Goal: 'Bea' }] };
  test('single leader', () => {
    expect(matchStatLeaders(t1, t2, 'goals').sort()).toEqual(['Alex']);
  });
  test('tie', () => {
    expect(matchStatLeaders({ '1': [{ Goal: 'Alex' }] }, { '2': [{ Goal: 'Bea' }] }, 'goals').sort())
      .toEqual(['Alex', 'Bea']);
  });
  test('penalty goal counts as goal; map-bucket shape', () => {
    expect(matchStatLeaders({ '1': { '0': { 'penalty goal': 'Cy' } } }, null, 'goals')).toEqual(['Cy']);
  });
  test('nobody', () => {
    expect(matchStatLeaders(null, null, 'saves')).toEqual([]);
  });
});

describe('matchStatLeaders league aliases (P3)', () => {
  test('counts league PenGoal as goals and PenSaved as saves, skipping _t', () => {
    // League activity shape: minute keys keep a trailing apostrophe and every
    // entry carries a _t insertion stamp.
    const act = {
      "5'": [{ PenGoal: 'Ana', _t: 1000 }],
      "9'": [{ PenSaved: 'Kim', _t: 2000 }, { Goal: 'Ana', _t: 3000 }],
    };
    expect(matchStatLeaders(act, null, 'goals')).toEqual(['Ana']);
    expect(matchStatLeaders(act, null, 'saves')).toEqual(['Kim']);
  });
  test('tournament spellings still count (no regression)', () => {
    const act = { '5': [{ 'Penalty Goal': 'Bo' }] };
    expect(matchStatLeaders(act, null, 'goals')).toEqual(['Bo']);
  });
});

describe('matchStatLeaders — per sport (P4)', () => {
  test('Soccer/Futsal default behavior unchanged (3-arg call)', () => {
    const a1 = { '10': [{ Goal: 'Ann' }] };
    expect(matchStatLeaders(a1, null, 'goals')).toEqual(['Ann']);
  });

  test('Basketball: points is weighted 1/2/3, ties share', () => {
    const a1 = {
      '1': [{ OnePointer: 'Ann' }],
      '2': [{ TwoPointer: 'Ann' }],
      '3': [{ ThreePointer: 'Amy' }],
    };
    // Ann: 1 + 2 = 3. Amy: 3. Tied.
    expect(matchStatLeaders(a1, null, 'points', 'Basketball').sort())
      .toEqual(['Amy', 'Ann']);
  });

  test('Basketball: rebounds/steals/blocks/assists tally independently', () => {
    const a1 = {
      '1': [{ Rebound: 'Ann' }, { Rebound: 'Ann' }],
      '2': [{ Steal: 'Amy' }],
      '3': [{ Block: 'Amy' }],
    };
    expect(matchStatLeaders(a1, null, 'rebounds', 'Basketball')).toEqual(['Ann']);
    expect(matchStatLeaders(a1, null, 'steals', 'Basketball')).toEqual(['Amy']);
  });

  test('Flag Football: touchdowns combine Receiving/Rushing/INT TD', () => {
    const a1 = {
      '1': [{ 'Receiving TD': 'Ann' }],
      '2': [{ 'Rushing TD': 'Ann' }],
    };
    expect(matchStatLeaders(a1, null, 'touchdowns', 'Flag Football')).toEqual(['Ann']);
  });

  test('Flag Football: catchPercentage gated to >=3 targets', () => {
    const a1 = {
      '1': [{ REC: 'Ann' }],
      '2': [{ REC: 'Ann' }],
    };
    // Only 2 targets — below the gate, so nobody leads.
    expect(matchStatLeaders(a1, null, 'catchPercentage', 'Flag Football')).toEqual([]);
  });

  test('Flag Football: catchPercentage at exactly 3 targets computes a rate', () => {
    const a1 = {
      '1': [{ REC: 'Ann' }],
      '2': [{ REC: 'Ann' }],
      '3': [{ RECMiss: 'Ann' }],
    };
    // 2/3 = 67%.
    expect(matchStatLeaders(a1, null, 'catchPercentage', 'Flag Football')).toEqual(['Ann']);
  });
});
