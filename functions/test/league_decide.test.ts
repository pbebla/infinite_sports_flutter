import { describe, expect, test } from 'vitest';
import {
  leagueSeasonTopic, leagueTeamTopic, buildLeagueCondition, isPlaceholderTeam,
  parseLeagueGame, decideLeagueGoal, decideLeagueStatus,
} from '../src/lib/league_decide';

const CTX = { sport: 'Futsal', season: '16', dateKey: '05202026', gameIndex: 3 };

function liveGame(extra: Record<string, unknown> = {}) {
  return parseLeagueGame({
    team1: 'Eagles', team2: 'Lions',
    team1score: 2, team2score: 1, status: 1,
    team1activity: {
      "12'": [{ Goal: 'Sam Smith', _t: 1000 }, { Assist: 'Skylar Jackson', _t: 2000 }],
    },
    ...extra,
  });
}

describe('league topics', () => {
  test('leagueTeamTopic matches the fan builder byte-for-byte', () => {
    // Fan contract (lib/misc/notification_topics.dart:17-18):
    // 'league_{sport}_{season}_team_{team}', each part sanitized.
    expect(leagueTeamTopic('Futsal', '16', 'FC Nineveh!')).toBe(
      'league_Futsal_16_team_FC_Nineveh_');
    expect(leagueTeamTopic('Flag Football', '7', 'A-Team'))
      .toBe('league_Flag_Football_7_team_A-Team');
  });
  test('leagueSeasonTopic matches the fan builder byte-for-byte (P3.3)', () => {
    // Fan contract (lib/misc/notification_topics.dart leagueSeasonTopic):
    // 'league_{sport}_{season}', each part through the same sanitizer.
    expect(leagueSeasonTopic('Futsal', '16')).toBe('league_Futsal_16');
    expect(leagueSeasonTopic('Flag Football', '7')).toBe('league_Flag_Football_7');
  });
  test('season topic is a strict prefix-sibling of the team topic', () => {
    expect(leagueTeamTopic('Flag Football', '7', 'A-Team'))
      .toBe(`${leagueSeasonTopic('Flag Football', '7')}_team_A-Team`);
  });
  test('buildLeagueCondition: season topic first, then both team topics (P3.3)', () => {
    expect(buildLeagueCondition('Futsal', '16', 'Eagles', 'Lions')).toBe(
      "'league_Futsal_16' in topics || " +
      "'league_Futsal_16_team_Eagles' in topics || " +
      "'league_Futsal_16_team_Lions' in topics");
  });
  test('placeholders drop their TEAM topic only — season followers still covered', () => {
    expect(isPlaceholderTeam('Winner of SF1')).toBe(true);
    expect(buildLeagueCondition('Futsal', '16', 'Winner of SF1', 'Lions')).toBe(
      "'league_Futsal_16' in topics || 'league_Futsal_16_team_Lions' in topics");
    // P3.3 silence-rule change: a two-placeholder game is still a REAL game
    // (bracket names lagging data entry) — season followers get its alerts.
    expect(buildLeagueCondition('Futsal', '16', 'Winner of SF1', 'Loser of QF2')).toBe(
      "'league_Futsal_16' in topics");
  });
  test('malformed game (no team names at all) -> null: nobody gets alerted', () => {
    expect(buildLeagueCondition('Futsal', '16', null, null)).toBeNull();
    expect(buildLeagueCondition('Futsal', '16', '', '   ')).toBeNull();
  });
});

describe('parseLeagueGame', () => {
  test('reads lowercase league keys and coerces legacy string scores', () => {
    const g = parseLeagueGame({ team1: 'A', team2: 'B', team1score: '3', team2score: 0, status: '1' });
    expect(g.team1).toBe('A');
    expect(g.team1Score).toBe(3);
    expect(g.status).toBe(1);
    expect(g.stage).toBe('');
  });
  test('reads Stage, Location.Venue, and tolerates null', () => {
    const g = parseLeagueGame({ Stage: 'friendly', Location: { Venue: 'Sherman Oaks Gym' } });
    expect(g.stage).toBe('friendly');
    expect(g.location).toBe('Sherman Oaks Gym');
    expect(parseLeagueGame(null).team1).toBeNull();
  });
});

describe('decideLeagueGoal', () => {
  const base = { teamTag: 1 as const, before: 1, after: 2, ...CTX };

  test('full goal alert with scorer + assist from apostrophe-minute _t buckets', () => {
    const d = decideLeagueGoal({ ...base, game: liveGame() });
    expect(d).not.toBeNull();
    expect(d!.kind).toBe('goal');
    expect(d!.title).toBe('⚽ GOAL! Eagles 2 – 1 Lions');
    expect(d!.body).toBe("Sam Smith (Eagles) 12' · Assist: Skylar Jackson");
    expect(d!.dedupeKey).toBe('goal_t1_2');
    expect(d!.condition).toBe(
      "'league_Futsal_16' in topics || " +
      "'league_Futsal_16_team_Eagles' in topics || " +
      "'league_Futsal_16_team_Lions' in topics");
    expect(d!.data).toEqual({
      type: 'goal', sport: 'Futsal', season: '16',
      dateKey: '05202026', gameIndex: '3',
    });
  });
  test('PenGoal counts as a scorer event', () => {
    const g = liveGame({ team1activity: { "8'": [{ PenGoal: 'Ana', _t: 1 }] } });
    expect(decideLeagueGoal({ ...base, game: g })!.body).toBe("Ana (Eagles) 8'");
  });
  test('own-goal fallback: no scorer on scoring team, OwnGoal on opponent', () => {
    const g = liveGame({
      team1activity: null,
      team2activity: { "20'": [{ OwnGoal: 'Bad Luck Bo', _t: 1 }] },
    });
    expect(decideLeagueGoal({ ...base, game: g })!.body).toBe("Own goal · Bad Luck Bo 20'");
  });
  test('silent ONLY when not live, no increase, friendly, or malformed (P3.3)', () => {
    expect(decideLeagueGoal({ ...base, game: liveGame({ status: 2 }) })).toBeNull();
    expect(decideLeagueGoal({ ...base, before: 2, after: 2, game: liveGame() })).toBeNull();
    expect(decideLeagueGoal({ ...base, game: liveGame({ Stage: 'friendly' }) })).toBeNull();
    // Malformed: no team names at all.
    expect(decideLeagueGoal({
      ...base, game: liveGame({ team1: null, team2: null }),
    })).toBeNull();
  });
  test('P3.3: two-placeholder game still alerts season followers (season-only condition)', () => {
    const d = decideLeagueGoal({
      ...base,
      game: liveGame({ team1: 'Winner of SF1', team2: 'Loser of QF2' }),
    });
    expect(d).not.toBeNull();
    expect(d!.condition).toBe("'league_Futsal_16' in topics");
  });
});

describe('decideLeagueStatus', () => {
  const base = { ...CTX };

  test('kickoff 0->1 with venue body', () => {
    const g = liveGame({ team1score: 0, team2score: 0, Location: { Venue: 'Main Gym' } });
    const d = decideLeagueStatus({ ...base, before: 0, after: 1, game: g });
    expect(d!.kind).toBe('kickoff');
    expect(d!.dedupeKey).toBe('kickoff');
    expect(d!.title).toBe('🟢 Kickoff: Eagles vs Lions');
    expect(d!.body).toBe('Now playing — Main Gym');
    expect(d!.data['type']).toBe('kickoff');
    // P3.3: kickoff condition carries the season topic too.
    expect(d!.condition).toBe(
      "'league_Futsal_16' in topics || " +
      "'league_Futsal_16_team_Eagles' in topics || " +
      "'league_Futsal_16_team_Lions' in topics");
  });
  test('kickoff without venue uses the generic body', () => {
    const g = liveGame({ team1score: 0, team2score: 0 });
    expect(decideLeagueStatus({ ...base, before: 0, after: 1, game: g })!.body)
      .toBe('Now playing — follow it live!');
  });
  test('fulltime on any ->2 transition', () => {
    const d = decideLeagueStatus({ ...base, before: 1, after: 2, game: liveGame({ status: 2 }) });
    expect(d!.kind).toBe('fulltime');
    expect(d!.title).toBe('🏁 Full time: Eagles 2 – 1 Lions');
    // P3.3: full-time condition carries the season topic too.
    expect(d!.condition).toBe(
      "'league_Futsal_16' in topics || " +
      "'league_Futsal_16_team_Eagles' in topics || " +
      "'league_Futsal_16_team_Lions' in topics");
  });
  test('silent on friendly, reopen (2->1), reset (->0), and no-change', () => {
    expect(decideLeagueStatus({ ...base, before: 0, after: 1,
      game: liveGame({ Stage: 'friendly' }) })).toBeNull();
    expect(decideLeagueStatus({ ...base, before: 2, after: 1, game: liveGame() })).toBeNull();
    expect(decideLeagueStatus({ ...base, before: 1, after: 0, game: liveGame() })).toBeNull();
    expect(decideLeagueStatus({ ...base, before: 1, after: 1, game: liveGame() })).toBeNull();
  });
});
