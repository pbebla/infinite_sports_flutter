import { describe, expect, test } from 'vitest';
import {
  sanitizeId, tournamentTopic, teamTopic, buildCondition,
  parseMatch, decideGoal, decideStatus, goalKeysToClear,
} from '../src/lib/decide';

const NAMES = { tournament: 'Test Tournament 2026', team1: 'Eagles', team2: 'Lions' };

function liveMatch(extra: Record<string, unknown> = {}) {
  return parseMatch({
    Team1Id: 'eaglesId', Team2Id: 'lionsId',
    Team1Score: 2, Team2Score: 1, Status: 1,
    Team1Activity: {
      '12': [{ Goal: 'Sam Smith' }, { Assist: 'Skylar Jackson' }],
    },
    ...extra,
  });
}

describe('topics', () => {
  test('sanitizeId keeps [A-Za-z0-9_-], replaces the rest with _', () => {
    expect(sanitizeId('Test Tournament 2026!')).toBe('Test_Tournament_2026_');
    expect(sanitizeId('abc-DEF_123')).toBe('abc-DEF_123');
  });
  test('topic builders', () => {
    expect(tournamentTopic('T 1')).toBe('tournament_T_1');
    expect(teamTopic('T1', 'team a')).toBe('tournament_T1_team_team_a');
  });
  test('buildCondition includes only known team ids', () => {
    expect(buildCondition('T1', 'a', 'b')).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_a' in topics || 'tournament_T1_team_b' in topics");
    expect(buildCondition('T1', null, 'b')).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_b' in topics");
    expect(buildCondition('T1', null, null)).toBe("'tournament_T1' in topics");
  });
});

describe('parseMatch', () => {
  test('reads PascalCase fields and coerces ints', () => {
    const m = liveMatch();
    expect(m.team1Score).toBe(2);
    expect(m.status).toBe(1);
    expect(m.team1Id).toBe('eaglesId');
  });
  test('tolerates camelCase and missing fields', () => {
    const m = parseMatch({ team1Score: '3', status: 2 });
    expect(m.team1Score).toBe(3);
    expect(m.status).toBe(2);
    expect(m.team1Id).toBeNull();
  });
  test('recovers activity buckets returned as arrays with null holes', () => {
    const m = parseMatch({
      Status: 1, Team1Score: 1, Team2Score: 0,
      Team1Activity: [null, [{ Goal: 'Ana' }]], // minute 1 as array index
    });
    const d = decideGoal({ teamTag: 1, before: 0, after: 1, match: m,
      names: NAMES, tid: 'T1', mid: 'M1' });
    expect(d?.body).toBe("Ana (Eagles) 1'");
  });
});

describe('decideGoal', () => {
  const base = { teamTag: 1 as const, before: 1, after: 2, tid: 'T1', mid: 'M1', names: NAMES };

  test('full goal alert with scorer and assist', () => {
    const d = decideGoal({ ...base, match: liveMatch() });
    expect(d).not.toBeNull();
    expect(d!.kind).toBe('goal');
    expect(d!.title).toBe('GOAL! Eagles 2 – 1 Lions');
    expect(d!.body).toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
    expect(d!.dedupeKey).toBe('goal_t1_2');
    expect(d!.condition).toBe(
      "'tournament_T1' in topics || 'tournament_T1_team_eaglesId' in topics || 'tournament_T1_team_lionsId' in topics");
    expect(d!.data).toEqual({ type: 'goal', tournamentId: 'T1', matchId: 'M1' });
  });

  test('assist may sit in the NEXT minute bucket (clock ticked between taps)', () => {
    const m = liveMatch({ Team1Activity: {
      '12': [{ Goal: 'Sam Smith' }], '13': [{ Assist: 'Skylar Jackson' }] } });
    expect(decideGoal({ ...base, match: m })!.body)
      .toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('assist-then-goal tap order pairs identically (same bucket, any order)', () => {
    const m = liveMatch({ Team1Activity: {
      '12': [{ Assist: 'Skylar Jackson' }, { Goal: 'Sam Smith' }] } });
    expect(decideGoal({ ...base, match: m })!.body)
      .toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('no assist -> scorer line alone', () => {
    const m = liveMatch({ Team1Activity: { '12': [{ Goal: 'Sam Smith' }] } });
    expect(decideGoal({ ...base, match: m })!.body).toBe("Sam Smith (Eagles) 12'");
  });

  test('penalty goal counts as scorer event', () => {
    const m = liveMatch({ Team1Activity: { '9': [{ 'Penalty Goal': 'Ana' }] } });
    expect(decideGoal({ ...base, match: m })!.body).toBe("Ana (Eagles) 9'");
  });

  test('no scorer found -> empty body, alert still sent', () => {
    const m = liveMatch({ Team1Activity: null });
    const d = decideGoal({ ...base, match: m });
    expect(d).not.toBeNull();
    expect(d!.body).toBe('');
  });

  test('team 2 goal uses team 2 activity and name', () => {
    const m = liveMatch({ Team2Activity: { '30': [{ Goal: 'Leo' }] } });
    const d = decideGoal({ ...base, teamTag: 2, match: m });
    expect(d!.body).toBe("Leo (Lions) 30'");
    expect(d!.dedupeKey).toBe('goal_t2_2');
  });

  test('silence when score did not increase', () => {
    expect(decideGoal({ ...base, before: 2, after: 2, match: liveMatch() })).toBeNull();
    expect(decideGoal({ ...base, before: 3, after: 2, match: liveMatch() })).toBeNull();
  });

  test('silence when match is not live', () => {
    expect(decideGoal({ ...base, match: liveMatch({ Status: 2 }) })).toBeNull();
    expect(decideGoal({ ...base, match: liveMatch({ Status: 0 }) })).toBeNull();
  });
});

describe('decideStatus', () => {
  const base = { tid: 'T1', mid: 'M1', names: NAMES };

  test('kickoff on 0 -> 1, with location', () => {
    const d = decideStatus({ ...base, before: 0, after: 1,
      match: liveMatch({ MatchLocation: 'Field A' }) });
    expect(d!.kind).toBe('kickoff');
    expect(d!.title).toBe('Kickoff: Eagles vs Lions');
    expect(d!.body).toBe('Now playing — Field A');
    expect(d!.dedupeKey).toBe('kickoff');
    expect(d!.data.type).toBe('kickoff');
  });

  test('kickoff without location uses generic body', () => {
    const d = decideStatus({ ...base, before: 0, after: 1, match: liveMatch() });
    expect(d!.body).toBe('Now playing — follow it live!');
  });

  test('full time on -> 2 with final score', () => {
    const d = decideStatus({ ...base, before: 1, after: 2,
      match: liveMatch({ Status: 2, Team1Score: 3 }) });
    expect(d!.kind).toBe('fulltime');
    expect(d!.title).toBe('Full time: Eagles 3 – 1 Lions');
    expect(d!.body).toBe('');
    expect(d!.dedupeKey).toBe('fulltime');
  });

  test('silence on no-change, reopen (2 -> 1), and reset (1 -> 0)', () => {
    expect(decideStatus({ ...base, before: 1, after: 1, match: liveMatch() })).toBeNull();
    expect(decideStatus({ ...base, before: 2, after: 1, match: liveMatch() })).toBeNull();
    expect(decideStatus({ ...base, before: 1, after: 0, match: liveMatch() })).toBeNull();
  });
});

describe('goalKeysToClear (re-arm on undo)', () => {
  test('lists keys above the new score up to the old score', () => {
    expect(goalKeysToClear(1, 3, 1)).toEqual(['goal_t1_2', 'goal_t1_3']);
    expect(goalKeysToClear(2, 5, 4)).toEqual(['goal_t2_5']);
    expect(goalKeysToClear(1, 2, 2)).toEqual([]);
  });
});
