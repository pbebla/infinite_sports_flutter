import { describe, expect, test } from 'vitest';
import {
  sanitizeId, tournamentTopic, teamTopic, buildCondition,
  parseMatch, decideGoal, decideStatus, goalKeysToClear,
  canonicalizeTournamentActivity,
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
      names: NAMES, tid: 'T1', mid: 'M1', sport: 'Soccer' });
    expect(d?.body).toBe("Ana (Eagles) 1'");
  });

  test('parseMatch tolerates null and empty-array activity', () => {
    const m = parseMatch(null);
    expect(m.team1Score).toBe(0);
    expect(m.team1Activity).toBeNull();
    expect(parseMatch({ Team1Activity: [] }).team1Activity).toBeNull();
  });
});

describe('decideGoal', () => {
  const base = { teamTag: 1 as const, before: 1, after: 2, tid: 'T1', mid: 'M1', names: NAMES, sport: 'Soccer' };

  test('full goal alert with scorer and assist', () => {
    const d = decideGoal({ ...base, match: liveMatch() });
    expect(d).not.toBeNull();
    expect(d!.kind).toBe('goal');
    expect(d!.title).toBe('⚽ GOAL! Eagles 2 – 1 Lions');
    expect(d!.body).toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
    expect(d!.dedupeKey).toBe('goal_t1_2');
    expect(d!.color).toBe('#000000');
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

  test('two goals in one minute pair the newest assist with the newest goal', () => {
    const m = liveMatch({ Team1Activity: {
      '12': [{ Goal: 'Ana' }, { Assist: 'Old Helper' }, { Goal: 'Sam Smith' }, { Assist: 'Skylar Jackson' }] } });
    expect(decideGoal({ ...base, match: m })!.body)
      .toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('team 2 goal title uses snapshot scores', () => {
    const m = liveMatch({ Team2Score: 2, Team2Activity: { '30': [{ Goal: 'Leo' }] } });
    const d = decideGoal({ ...base, teamTag: 2, match: m });
    expect(d!.title).toBe('⚽ GOAL! Eagles 2 – 2 Lions');
  });
});

describe('decideStatus', () => {
  const base = { tid: 'T1', mid: 'M1', names: NAMES, sport: 'Soccer' };

  test('kickoff on 0 -> 1, with location', () => {
    const d = decideStatus({ ...base, before: 0, after: 1,
      match: liveMatch({ MatchLocation: 'Field A' }) });
    expect(d!.kind).toBe('kickoff');
    expect(d!.title).toBe('🟢 Kickoff: Eagles vs Lions');
    expect(d!.body).toBe('Now playing — Field A');
    expect(d!.dedupeKey).toBe('kickoff');
    expect(d!.color).toBe('#000000');
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
    expect(d!.title).toBe('🏁 Full time: Eagles 3 – 1 Lions');
    expect(d!.body).toBe('');
    expect(d!.dedupeKey).toBe('fulltime');
    expect(d!.color).toBe('#000000');
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

describe('canonicalizeTournamentActivity (P4 spelling bridge)', () => {
  test('bridges legacy spaced spellings to the compact league token', () => {
    const activity = {
      '10': [{ 'penalty goal': 'Ann' }],
      '30': [{ 'own goal': 'Ann' }],
    };
    const out = canonicalizeTournamentActivity(activity)!;
    expect(Object.keys(out['10'][0])).toEqual(['pengoal']);
    expect(Object.keys(out['30'][0])).toEqual(['owngoal']);
  });

  test('leaves already-canonical / unrelated keys untouched', () => {
    const activity = { '10': [{ Goal: 'Ann', _t: 555 }] };
    const out = canonicalizeTournamentActivity(activity)!;
    expect(out['10'][0]).toEqual({ Goal: 'Ann', _t: 555 });
  });

  test('null activity passes through as null', () => {
    expect(canonicalizeTournamentActivity(null)).toBeNull();
  });
});

describe('decideGoal — per sport (P4)', () => {
  test('Soccer output is BYTE-IDENTICAL to the pre-P4 hardcoded strings', () => {
    const match = liveMatch(); // team1Score 2, team2Score 1, Goal+Assist at '12'
    const d = decideGoal({
      teamTag: 1, before: 1, after: 2, match, names: NAMES,
      tid: 'T1', mid: 'M1', sport: 'Soccer',
    })!;
    expect(d.title).toBe('⚽ GOAL! Eagles 2 – 1 Lions');
    expect(d.body).toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
  });

  test('legacy "penalty goal" spelling still resolves a scorer', () => {
    const match = parseMatch({
      Team1Id: 'e', Team2Id: 'l', Team1Score: 1, Team2Score: 0, Status: 1,
      Team1Activity: { '40': [{ 'penalty goal': 'Ann' }] },
    });
    const d = decideGoal({
      teamTag: 1, before: 0, after: 1, match, names: NAMES,
      tid: 'T1', mid: 'M1', sport: 'Soccer',
    })!;
    expect(d.body).toContain('Ann (Eagles)');
  });

  test('Basketball: no assist pairing, sport-specific title', () => {
    const match = parseMatch({
      Team1Id: 'e', Team2Id: 'l', Team1Score: 3, Team2Score: 0, Status: 1,
      Team1Activity: { '2': [{ ThreePointer: 'Ann' }] },
    });
    const d = decideGoal({
      teamTag: 1, before: 0, after: 3, match, names: NAMES,
      tid: 'T1', mid: 'M1', sport: 'Basketball',
    })!;
    expect(d.title).toBe('🏀 Score! Eagles 3 – 0 Lions');
    expect(d.body).toBe("Ann (Eagles) 2'");
  });

  test('Flag Football: Rec TD headlines TOUCHDOWN + pairs with Pass TD', () => {
    const match = parseMatch({
      Team1Id: 'e', Team2Id: 'l', Team1Score: 6, Team2Score: 0, Status: 1,
      Team1Activity: {
        '5': [{ 'Receiving TD': 'Ann' }, { 'Pass TD': 'Amy' }],
      },
    });
    const d = decideGoal({
      teamTag: 1, before: 0, after: 6, match, names: NAMES,
      tid: 'T1', mid: 'M1', sport: 'Flag Football',
    })!;
    expect(d.title).toBe('🏈 TOUCHDOWN! Eagles 6 – 0 Lions');
    expect(d.body).toContain('Thrown by: Amy');
  });
});

describe('decideStatus — per sport (P4)', () => {
  test('Soccer kickoff/fulltime wording unchanged', () => {
    const match = parseMatch({ Team1Id: 'e', Team2Id: 'l', Status: 1 });
    const kickoff = decideStatus({
      before: 0, after: 1, match, names: NAMES, tid: 'T1', mid: 'M1',
      sport: 'Soccer',
    })!;
    expect(kickoff.title).toBe('🟢 Kickoff: Eagles vs Lions');
  });

  test('Basketball uses Tip-off / Final wording', () => {
    const match = parseMatch({ Team1Id: 'e', Team2Id: 'l', Status: 1 });
    const kickoff = decideStatus({
      before: 0, after: 1, match, names: NAMES, tid: 'T1', mid: 'M1',
      sport: 'Basketball',
    })!;
    expect(kickoff.title).toBe('🟢 Tip-off: Eagles vs Lions');
  });
});
