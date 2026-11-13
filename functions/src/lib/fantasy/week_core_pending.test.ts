// scoreWeekCore's PENDING rule (live design 2026-11-03 §2): while a team
// still has a not-started game today, its players who have not played yet
// count as "playing, 0 so far" for TEAM scoring only — no auto-sub, the
// captain keeps the armband, a bench player stays on the bench — while the
// real week map (Dream Team, PlayerWeekStats.Played) never pretends they
// played. Plus bonusProvisional: the bonus of a game that is not Final yet.
//
// Every expected number below is hand math from futsalDefault(), never
// copied from output.
//
// THE WORLD (one started game, Lions 3-1 Tigers):
// - Lions: Leo Goal x2, Lana Goal, Vic Assist; attendance Leo/Lana/Vic/Dot
//   present, Abe absent. Tigers: Tom Goal (no attendance map: event
//   players only).
// - BPS: Leo 24, Lana 12, Tom 12, Vic 9 -> bonus Leo 3, Lana + Tom tied 2
//   (the tie consumes the last slot), Vic none.
// - Week points: Leo (ATT) 1 + 8 + 3 = 12; Lana (ATT) 1 + 4 + 2 = 7;
//   Tom (ATT) 1 + 4 + 2 = 7; Vic (DEF) 1 + assist 4 = 5 (conceded 1: no
//   deduction, no clean sheet); Dot (DEF) plays 1; Abe absent 0.
// - Pumas (Pia GK, Paz DEF, Pete ATT) kick off later today: not in `games`.
//   Bears (Bert DEF) have no game today.

import { describe, expect, it } from 'vitest';
import { FantasyPosition, futsalDefault } from './fantasy_config';
import {
  FinalizeGame, MarketPlayer, pickDreamTeam, scoreWeekCore, WeekCoreInput,
  WeekCoreOutput,
} from './finalize_core';

const cfg = futsalDefault();

const PLAYERS: Record<string, MarketPlayer> = {
  Leo: { position: 'ATT', eligible: true, teamName: 'Lions' },
  Lana: { position: 'ATT', eligible: true, teamName: 'Lions' },
  Vic: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Dot: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Abe: { position: 'DEF', eligible: true, teamName: 'Lions' },
  Tom: { position: 'ATT', eligible: true, teamName: 'Tigers' },
  Pia: { position: 'GK', eligible: true, teamName: 'Pumas' },
  Paz: { position: 'DEF', eligible: true, teamName: 'Pumas' },
  Pete: { position: 'ATT', eligible: true, teamName: 'Pumas' },
  Bert: { position: 'DEF', eligible: true, teamName: 'Bears' },
};

/** Lions 3-1 Tigers at [status] (1 live, 2 Final). */
function lionsTigers(status: number): FinalizeGame {
  return {
    node: {
      team1: 'Lions', team2: 'Tigers', team1score: 3, team2score: 1, status,
      team1activity: {
        "2'": [{ Goal: 'Leo' }, { Assist: 'Vic' }],
        "7'": [{ Goal: 'Leo' }],
        "11'": [{ Goal: 'Lana' }],
      },
      team2activity: { "9'": [{ Goal: 'Tom' }] },
    },
    attendance: {
      Lions: { Leo: true, Lana: true, Vic: true, Dot: true, Abe: false },
      Tigers: null,
    },
  };
}

type Pick = [string, FantasyPosition, boolean?];

/** A raw squad map (PublishedPicks shape); [bench] marks bench picks. */
function squad(picks: Pick[], captainId: string, viceId: string) {
  return {
    picks: picks.map(([playerId, position, bench]) => ({
      playerId, position, priceTenths: 50, bench: bench === true,
    })),
    captainId,
    viceId,
  };
}

function input(overrides: Partial<WeekCoreInput> = {}): WeekCoreInput {
  return {
    cfg,
    gw: 3,
    games: [lionsTigers(1)],
    players: PLAYERS,
    squadsByUid: {},
    voided: false,
    pendingTeams: ['Pumas'],
    ...overrides,
  };
}

interface Slot {
  playerId: string;
  countedTenths: number;
  multiplier: number;
  autoSubbedIn: boolean;
}

function breakdownOf(
  out: WeekCoreOutput, uid: string,
): Record<string, Slot> {
  const rows = out.historyByUid[uid]['Breakdown'] as Slot[];
  return Object.fromEntries(rows.map((r) => [r.playerId, r]));
}

/** Pumas DEF Paz starts; Vic (DEF, played 5) waits on the bench. */
const PAZ_STARTS = squad([
  ['Pia', 'GK'], ['Paz', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
  ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
], 'Leo', 'Lana');

describe('scoreWeekCore pending rule', () => {
  it('(a) a pending captain keeps the armband: he counts 0, the vice counts 5 x 1', () => {
    // Pete (Pumas) captains, Vic (5) is vice. Pending, Pete "plays, 0 so
    // far": armband stays on him (0 x 2 = 0), Vic counts 50 tenths, and
    // nobody is auto-subbed (Paz and Pia are pending too) — bench Bert (no
    // game) 0, bench Tom half 35. Total 0+50+0+0+120+0+35 = 205.
    // Without the rule it would be Vic x2 + Tom auto-subbed full = 290.
    const out = scoreWeekCore(input({
      squadsByUid: {
        u: squad([
          ['Pia', 'GK'], ['Vic', 'DEF'], ['Paz', 'DEF'], ['Pete', 'ATT'],
          ['Leo', 'ATT'], ['Bert', 'DEF', true], ['Tom', 'ATT', true],
        ], 'Pete', 'Vic'),
      },
    }));
    const slots = breakdownOf(out, 'u');
    expect(slots['Pete']).toEqual(
      { playerId: 'Pete', countedTenths: 0, multiplier: 2, autoSubbedIn: false });
    expect(slots['Vic']).toEqual(
      { playerId: 'Vic', countedTenths: 50, multiplier: 1, autoSubbedIn: false });
    expect(slots['Tom']).toEqual(
      { playerId: 'Tom', countedTenths: 35, multiplier: 1, autoSubbedIn: false });
    expect(out.historyByUid['u']['TotalTenths']).toBe(205);
    expect(out.weekTenthsByUid['u']).toBe(205);
  });

  it('(b) a pending DEF starter is not auto-subbed: the played DEF bench counts half', () => {
    // Paz pending: Vic stays on the bench at half (5 x 50 ~/ 10 = 25).
    // Total: Pia 0 + Paz 0 + Dot 10 + Leo 12x2 240 + Lana 70 + Vic 25 +
    // Tom 35 = 380.
    const out = scoreWeekCore(input({ squadsByUid: { u: PAZ_STARTS } }));
    const slots = breakdownOf(out, 'u');
    expect(slots['Vic']).toEqual(
      { playerId: 'Vic', countedTenths: 25, multiplier: 1, autoSubbedIn: false });
    expect(slots['Paz'].countedTenths).toBe(0);
    expect(Object.values(slots).some((s) => s.autoSubbedIn)).toBe(false);
    expect(out.historyByUid['u']['TotalTenths']).toBe(380);
  });

  it('(c) the same starter marked absent in a STARTED game is auto-subbed (bench full)', () => {
    // Pumas 0-0 Hawks is under way and Paz is marked absent: Pumas are no
    // longer pending (only the Wolves still wait to kick off), so Vic
    // comes on at FULL 50. Total: 0 + 0 + 10 + 240 + 70 + 50 + 35 = 405.
    const pumasHawks: FinalizeGame = {
      node: {
        team1: 'Pumas', team2: 'Hawks', team1score: 0, team2score: 0,
        status: 1,
      },
      attendance: { Pumas: { Paz: false }, Hawks: null },
    };
    const out = scoreWeekCore(input({
      games: [lionsTigers(1), pumasHawks],
      squadsByUid: { u: PAZ_STARTS },
      pendingTeams: ['Wolves'],
    }));
    const slots = breakdownOf(out, 'u');
    expect(slots['Vic']).toEqual(
      { playerId: 'Vic', countedTenths: 50, multiplier: 1, autoSubbedIn: true });
    expect(out.historyByUid['u']['TotalTenths']).toBe(405);
  });

  it('(d) a team with no game today is not pending: its starter is auto-subbed', () => {
    // Bert (Bears, no game) starts instead of Paz: not pending, so Vic
    // comes on at FULL. Total: 0 + 0 + 10 + 240 + 70 + 50 + 35 = 405.
    const out = scoreWeekCore(input({
      squadsByUid: {
        u: squad([
          ['Pia', 'GK'], ['Bert', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
          ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
        ], 'Leo', 'Lana'),
      },
    }));
    const slots = breakdownOf(out, 'u');
    expect(slots['Bert'].countedTenths).toBe(0);
    expect(slots['Vic']).toEqual(
      { playerId: 'Vic', countedTenths: 50, multiplier: 1, autoSubbedIn: true });
    expect(out.historyByUid['u']['TotalTenths']).toBe(405);
  });

  it('(e) the real week keeps pending players unplayed, so the Dream Team never picks them', () => {
    const out = scoreWeekCore(input({ squadsByUid: { u: PAZ_STARTS } }));
    for (const name of ['Pia', 'Paz', 'Pete']) {
      expect(out.week[name], name).toEqual({ points: 0, played: false });
      expect(out.playerWeekStats[name].Played, name).toBe(false);
    }
    // Pia is the only GK in the market: had she counted as played, she
    // would hold the GK slot. Nobody who played is a GK, so it stays empty.
    // DEF: Vic 5, Dot 1. ATT: Leo 12, then Lana and Tom tie on 7 (name asc).
    expect(pickDreamTeam(out.week, PLAYERS, cfg, 1).Players).toEqual([
      { name: 'Vic', position: 'DEF', points: 5 },
      { name: 'Dot', position: 'DEF', points: 1 },
      { name: 'Leo', position: 'ATT', points: 12 },
      { name: 'Lana', position: 'ATT', points: 7 },
    ]);
  });

  it('(f) bonusProvisional holds a live game\'s bonus players, and empties once it is Final', () => {
    // Leo is the top BPS (24) of the live game; Lana and Tom share the 2.
    const live = scoreWeekCore(input());
    expect(live.bonusProvisional.has('Leo')).toBe(true);
    expect([...live.bonusProvisional].sort()).toEqual(['Lana', 'Leo', 'Tom']);
    // The bonus itself already counts (provisionally) in the week points.
    expect(live.playerWeeks['Leo']).toBe(12);

    const final = scoreWeekCore(input({ games: [lionsTigers(2)] }));
    expect(final.bonusProvisional.size).toBe(0);
    expect(final.playerWeeks['Leo']).toBe(12);
  });

  it('bonusProvisional with mixed statuses: only the live game\'s bonus holders', () => {
    // Lions 3-1 Tigers is Final (Leo/Lana/Tom hold settled bonus). Pumas
    // 1-0 Hawks is live: Pete's goal + clean sheet = BPS 12 + 5 = 17, the
    // only BPS of that game -> bonus 3. Pete (ATT): 1 + 4 + cs 2 + 3 = 10.
    const out = scoreWeekCore(input({
      games: [lionsTigers(2), {
        node: {
          team1: 'Pumas', team2: 'Hawks', team1score: 1, team2score: 0,
          status: 1, team1activity: { "4'": [{ Goal: 'Pete' }] },
        },
        attendance: null,
      }],
    }));
    expect([...out.bonusProvisional]).toEqual(['Pete']);
    expect(out.playerWeeks['Pete']).toBe(10);
    expect(out.playerWeeks['Leo']).toBe(12); // settled bonus still counts
  });

  for (const firstStatus of [1, 2]) {
    it(`double-game day: absent in an earlier ${firstStatus === 2 ? 'Final' : 'live'} game, still pending for the later one`, () => {
      // Controller ruling: Wolves play twice today. Game 1 (status
      // [firstStatus]) has Xan (DEF) marked absent; game 2 (status 0) has
      // not started, so it is not in `games` and the caller lists Wolves
      // as pending. Xan can still play game 2 (an FPL double gameweek): no
      // auto-sub yet, so bench DEF Vic counts half (25). Total: Pia 0 +
      // Xan 0 + Dot 10 + Leo 240 + Lana 70 + Vic 25 + Tom 35 = 380.
      const players: Record<string, MarketPlayer> = {
        ...PLAYERS,
        Xan: { position: 'DEF', eligible: true, teamName: 'Wolves' },
      };
      const wolvesGame1: FinalizeGame = {
        node: {
          team1: 'Wolves', team2: 'Hawks', team1score: 1, team2score: 1,
          status: firstStatus,
        },
        attendance: { Wolves: { Xan: false }, Hawks: null },
      };
      const out = scoreWeekCore(input({
        games: [lionsTigers(1), wolvesGame1],
        players,
        pendingTeams: ['Pumas', 'Wolves'],
        squadsByUid: {
          u: squad([
            ['Pia', 'GK'], ['Xan', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
            ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
          ], 'Leo', 'Lana'),
        },
      }));
      const slots = breakdownOf(out, 'u');
      expect(slots['Xan'].countedTenths).toBe(0);
      expect(slots['Vic']).toEqual(
        { playerId: 'Vic', countedTenths: 25, multiplier: 1, autoSubbedIn: false });
      expect(out.historyByUid['u']['TotalTenths']).toBe(380);
      // The real week: he has not played, so no Dream Team — not even alone
      // in the market, where a "played" entry would take a DEF slot.
      expect(out.week['Xan']).toEqual({ points: 0, played: false });
      expect(pickDreamTeam(out.week, players, cfg, 1).Players
        .map((r) => r.name)).not.toContain('Xan');
      expect(pickDreamTeam(out.week, { Xan: players['Xan'] }, cfg, 1).Players)
        .toEqual([]);
    });
  }

  it('a market player with no teamName is never pending', () => {
    // Nox (DEF, no team) starts and has not played: auto-subbed by Vic in
    // FULL even while the rule is active. Total: 0+0+10+240+70+50+35 = 405.
    const out = scoreWeekCore(input({
      players: { ...PLAYERS, Nox: { position: 'DEF', eligible: true } },
      squadsByUid: {
        u: squad([
          ['Pia', 'GK'], ['Nox', 'DEF'], ['Dot', 'DEF'], ['Leo', 'ATT'],
          ['Lana', 'ATT'], ['Vic', 'DEF', true], ['Tom', 'ATT', true],
        ], 'Leo', 'Lana'),
      },
    }));
    expect(breakdownOf(out, 'u')['Vic']).toEqual(
      { playerId: 'Vic', countedTenths: 50, multiplier: 1, autoSubbedIn: true });
    expect(out.historyByUid['u']['TotalTenths']).toBe(405);
  });

  it('no pendingTeams (or an empty list) changes nothing: a pending-team player is simply absent', () => {
    // The finalize path: Paz did not play, so Vic is auto-subbed in full.
    const none = scoreWeekCore(input({
      squadsByUid: { u: PAZ_STARTS }, pendingTeams: undefined,
    }));
    expect(breakdownOf(none, 'u')['Vic'].autoSubbedIn).toBe(true);
    expect(none.historyByUid['u']['TotalTenths']).toBe(405);
    expect(scoreWeekCore(input({ squadsByUid: { u: PAZ_STARTS }, pendingTeams: [] })))
      .toEqual(none);
  });
});
