// Finalization math (P4 Phase C) over the golden gameweek. Every expected
// number below was computed BY HAND from futsalDefault() and the fixture's
// documented raw stats BEFORE the pipeline ran (same discipline as the
// golden file itself) — never copied from pipeline output.
//
// HAND MATH USED THROUGHOUT (fixture _notes carry the full derivation):
// week points (base + bonus): Sam9 Dana13 Alex12 Wes1 Will-4 Wren3 Eli0
// Eva-3 Ezra0 Bo12 Bea15 Ben9.
// squad gross tenths: alpha 350, boost 440, churn 595.
// golden transfer costs: alpha 0, boost 0, churn 4 pts -> nets 350/440/555.
// weekly whole points = trunc(net/10): alpha 35, boost 44, churn 55.

import { describe, expect, it } from 'vitest';
import { futsalDefault, parsePosition } from './fantasy_config';
import {
  competitionRanks, composeOverallBoard, composeRankHistory,
  computeGameweekFinalize, FinalizeGame, FinalizeInput, MarketPlayer,
  pickDreamTeam, scoreWeekCore, wholePoints,
} from './finalize_core';
import { clone, Json, loadGoldenFixture } from './golden_fixture';

const fixture = loadGoldenFixture();
const cfg = futsalDefault();

function fixtureGames(): FinalizeGame[] {
  return (fixture['games'] as Json[]).map((g) => {
    const attendanceByTeam: Json | null = g['attendance'] ?? null;
    const attendance: Record<string, Record<string, boolean> | null> = {};
    for (const team of [g['node']['team1'], g['node']['team2']] as string[]) {
      const raw: Json | null = attendanceByTeam?.[team] ?? null;
      if (raw === null) {
        attendance[team] = null;
        continue;
      }
      const m: Record<string, boolean> = {};
      for (const [k, v] of Object.entries(raw)) m[k] = v === true;
      attendance[team] = m;
    }
    return { node: clone(g['node']) as Record<string, unknown>, attendance };
  });
}

function fixturePlayers(): Record<string, MarketPlayer> {
  const out: Record<string, MarketPlayer> = {};
  for (const p of fixture['players'] as Json[]) {
    out[p['id']] = {
      position: parsePosition(p['position']), eligible: true,
      teamName: p['team'],
    };
  }
  return out;
}

function fixtureSquads(): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const s of fixture['squads'] as Json[]) {
    out[s['name']] = clone(s['squad']);
  }
  return out;
}

function baseInput(): FinalizeInput {
  return {
    cfg,
    gw: 1,
    games: fixtureGames(),
    players: fixturePlayers(),
    squadsByUid: fixtureSquads(),
    // Golden transfer usage: alpha used1/free2 -> 0, boost 0/1 -> 0,
    // churn used3/free2 -> (3-2)*4 = 4 points.
    transferCostPointsByUid: { alpha: 0, boost: 0, churn: 4 },
    playerWeeksByWeek: {},
    playedGamesByWeek: {},
    historyTenthsByWeek: {},
    dreamTeamAuto: null,
    nowMs: 1_750_000_000_000,
  };
}

// Hand-computed week points (fixture _notes derivation).
const WEEK_POINTS: Record<string, number> = {
  Sam: 9, Dana: 13, Alex: 12, Wes: 1, Will: -4, Wren: 3,
  Eli: 0, Eva: -3, Ezra: 0, Bo: 12, Bea: 15, Ben: 9,
};

describe('wholePoints', () => {
  it('truncates toward zero like Dart ~/ 10', () => {
    expect(wholePoints(350)).toBe(35);
    expect(wholePoints(595)).toBe(59); // bench half-point lost
    expect(wholePoints(-155)).toBe(-15); // NOT floor's -16
    expect(wholePoints(0)).toBe(0);
  });
});

describe('competitionRanks', () => {
  it('ties share the smaller rank and consume the slots below', () => {
    expect(competitionRanks({ x: 100, y: 100, z: 50 }))
      .toEqual({ x: 1, y: 1, z: 3 });
  });
  it('plain ordering', () => {
    expect(competitionRanks({ a: 35, b: 44, c: 55 }))
      .toEqual({ a: 3, b: 2, c: 1 });
  });
});

describe('composeOverallBoard', () => {
  it('single week: points = weekly whole points, no movement', () => {
    const board = composeOverallBoard({
      1: { alpha: 350, boost: 440, churn: 555 },
    });
    expect(board).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 55, rank: 1 },
    });
  });

  it('movement vs the standings before the latest week; new managers omit it', () => {
    // Hand math: totals a 35+60=95(r1), b 44+10=54(r3), c 55+20=75(r2),
    // d 40(r4, new). Previous (week 1 only): a r3, b r2, c r1.
    // movement = prevRank - rank: a +2, b -1, c -1, d omitted.
    const board = composeOverallBoard({
      1: { a: 350, b: 440, c: 555 },
      2: { a: 600, b: 100, c: 200, d: 400 },
    });
    expect(board).toEqual({
      a: { points: 95, rank: 1, movement: 2 },
      b: { points: 54, rank: 3, movement: -1 },
      c: { points: 75, rank: 2, movement: -1 },
      d: { points: 40, rank: 4 },
    });
    expect('movement' in board['d']).toBe(false);
  });

  it('negative weeks truncate toward zero per week', () => {
    expect(composeOverallBoard({ 1: { a: -155 } }))
      .toEqual({ a: { points: -15, rank: 1 } });
  });

  it('empty history = empty board', () => {
    expect(composeOverallBoard({})).toEqual({});
  });
});

// Leaderboards/RankHistory/<uid> = { "<gw>": rank } (leaderboard extras
// follow-up): each manager's OVERALL rank after every finalized week.
// Hand math in each test; never copied from output.
describe('composeRankHistory', () => {
  it("single week: every manager gets that week's Overall rank", () => {
    expect(composeRankHistory({ 1: { alpha: 350, boost: 440, churn: 555 } }))
      .toEqual({
        alpha: { '1': 3 },
        boost: { '1': 2 },
        churn: { '1': 1 },
      });
  });

  it('rank after week w = competition rank of the cumulative whole points through w', () => {
    // Week 1: a 35 (r3), b 44 (r2), c 55 (r1).
    // Week 2 cumulative: a 35+60=95 (r1), b 44+10=54 (r3), c 55+20=75 (r2),
    // d 40 (r4, joined in week 2).
    expect(composeRankHistory({
      1: { a: 350, b: 440, c: 555 },
      2: { a: 600, b: 100, c: 200, d: 400 },
    })).toEqual({
      a: { '1': 3, '2': 1 },
      b: { '1': 2, '2': 3 },
      c: { '1': 1, '2': 2 },
      d: { '2': 4 },
    });
  });

  it('agrees with the Overall board: latest entry = rank, movement = previous entry - rank', () => {
    const history = {
      1: { a: 350, b: 440, c: 555 },
      2: { a: 600, b: 100, c: 200, d: 400 },
      3: { a: 0, b: 900, c: 100, d: 50 },
    };
    const board = composeOverallBoard(history);
    const ranks = composeRankHistory(history);
    expect(Object.keys(ranks).sort()).toEqual(Object.keys(board).sort());
    for (const [uid, row] of Object.entries(board)) {
      expect(ranks[uid]['3'], uid).toBe(row.rank);
      if (row.movement !== undefined) {
        expect(ranks[uid]['2'] - row.rank, uid).toBe(row.movement);
      }
    }
  });

  it('ties share the smaller rank (1,1,3) — also when only the TRUNCATED points tie', () => {
    // Week 1: x 10, y 10, z 5 -> x 1, y 1, z 3.
    // Week 2 cumulative: x 10, y 11, z 11 -> y 1, z 1, x 3.
    expect(composeRankHistory({
      1: { x: 100, y: 100, z: 50 },
      2: { x: 0, y: 10, z: 60 },
    })).toEqual({
      x: { '1': 1, '2': 3 },
      y: { '1': 1, '2': 1 },
      z: { '1': 3, '2': 1 },
    });
    // 109 and 101 tenths are both 10 whole points; -155 / -150 both -15.
    expect(composeRankHistory({ 1: { p: 109, q: 101 } }))
      .toEqual({ p: { '1': 1 }, q: { '1': 1 } });
    expect(composeRankHistory({ 1: { m: -155, n: -150 } }))
      .toEqual({ m: { '1': 1 }, n: { '1': 1 } });
  });

  it('a manager who joined in week 3 has no entries before week 3', () => {
    // Week 1: a 10, b 20 -> b 1, a 2. Week 2: a 20, b 20 -> both 1.
    // Week 3: a 20, b 20, n 50 -> n 1, a 2, b 2.
    const ranks = composeRankHistory({
      1: { a: 100, b: 200 },
      2: { a: 100, b: 0 },
      3: { a: 0, b: 0, n: 500 },
    });
    expect(ranks).toEqual({
      a: { '1': 2, '2': 1, '3': 2 },
      b: { '1': 1, '2': 1, '3': 2 },
      n: { '3': 1 },
    });
    expect(Object.keys(ranks['n'])).toEqual(['3']);
  });

  it('a week a manager skipped still ranks him on his running total', () => {
    // Week 2 has no entry for a (no squad that week): a keeps 30 and is
    // still ranked after week 2 (b 10+25=35 r1, a 30 r2).
    expect(composeRankHistory({
      1: { a: 300, b: 100 },
      2: { b: 250 },
    })).toEqual({
      a: { '1': 1, '2': 2 },
      b: { '1': 2, '2': 1 },
    });
  });

  it('weeks run in NUMERIC order (week 10 after week 9) and reruns are identical', () => {
    const history = {
      10: { a: 0, b: 300 },
      9: { a: 200, b: 100 },
    };
    // Week 9: a 20 r1, b 10 r2. Week 10: a 20 r2, b 40 r1.
    const expected = {
      a: { '9': 1, '10': 2 },
      b: { '9': 2, '10': 1 },
    };
    expect(composeRankHistory(history)).toEqual(expected);
    expect(composeRankHistory(history)).toEqual(composeRankHistory(history));
  });

  it('empty history = empty node', () => {
    expect(composeRankHistory({})).toEqual({});
  });
});

describe('pickDreamTeam', () => {
  const players: Record<string, MarketPlayer> = {
    G1: { position: 'GK', eligible: true },
    G2: { position: 'GK', eligible: true },
    D1: { position: 'DEF', eligible: true },
    D2: { position: 'DEF', eligible: true },
    D3: { position: 'DEF', eligible: true },
    A1: { position: 'ATT', eligible: true },
    A2: { position: 'ATT', eligible: true },
    A3: { position: 'ATT', eligible: false }, // guest: never picked
  };

  /** Everyone played unless listed in [absent]. */
  const weekOf = (points: Record<string, number>, absent: string[] = []) =>
    Object.fromEntries(Object.entries(points).map(([n, p]) =>
      [n, { points: p, played: !absent.includes(n) }]));

  it('config formation, points desc, eligible only, name asc on ties', () => {
    const team = pickDreamTeam(
      weekOf({ G1: 5, G2: 8, D1: 7, D2: 7, D3: 9, A1: 4, A2: 4, A3: 99 }),
      players, cfg, 42);
    expect(team).toEqual({
      Players: [
        { name: 'G2', position: 'GK', points: 8 },
        { name: 'D3', position: 'DEF', points: 9 },
        { name: 'D1', position: 'DEF', points: 7 }, // D1 before D2 on the tie
        { name: 'A1', position: 'ATT', points: 4 }, // A1 before A2 on the tie
        { name: 'A2', position: 'ATT', points: 4 },
      ],
      ComputedAt: 42,
      Auto: true,
    });
  });

  it('short positions fill fewer slots', () => {
    const team = pickDreamTeam(weekOf({ G1: 1 }),
      { G1: { position: 'GK', eligible: true } }, cfg, 1);
    expect(team.Players).toEqual([{ name: 'G1', position: 'GK', points: 1 }]);
  });

  it('only players who PLAYED: a no-game 0 never beats a keeper who played', () => {
    // S15 GW12: Brandon Zaya's team (Babylon) had no game, so his 0 was the
    // "best" GK score while every keeper who played went negative. He must
    // not appear; the best keeper who PLAYED does (even below zero).
    // G1 no game (absent from the week map), G2 played -2. D1 played,
    // D2 absent (played false, 0), D3 no entry. A1 played, A2 played.
    const team = pickDreamTeam({
      G2: { points: -2, played: true },
      D1: { points: 3, played: true },
      D2: { points: 0, played: false },
      A1: { points: 6, played: true },
      A2: { points: 1, played: true },
    }, players, cfg, 7);
    expect(team.Players).toEqual([
      { name: 'G2', position: 'GK', points: -2 },
      { name: 'D1', position: 'DEF', points: 3 }, // only 1 DEF played: 1 slot
      { name: 'A1', position: 'ATT', points: 6 },
      { name: 'A2', position: 'ATT', points: 1 },
    ]);
  });

  it('a position nobody played leaves its slot empty', () => {
    const team = pickDreamTeam(
      weekOf({ G1: 0, D1: 5, D2: 4, A1: 2, A2: 1 }, ['G1']), players, cfg, 1);
    expect(team.Players.map((r) => r.name)).toEqual(['D1', 'D2', 'A1', 'A2']);
  });
});

describe('computeGameweekFinalize over the golden gameweek', () => {
  const out = computeGameweekFinalize(baseInput());

  it('player weeks = base + bonus (hand math)', () => {
    expect(out.playerWeeks).toEqual(WEEK_POINTS);
  });

  it('History entries: squad snapshot + NET TotalTenths + Breakdown', () => {
    expect(Object.keys(out.historyByUid).sort())
      .toEqual(['alpha', 'boost', 'churn']);
    const alpha = out.historyByUid['alpha'];
    // squadFromMap-compatible part survives verbatim.
    expect(alpha['captainId']).toBe('Ezra');
    expect(alpha['viceId']).toBe('Alex');
    expect((alpha['picks'] as unknown[]).length).toBe(7);
    expect(alpha['TotalTenths']).toBe(350);
    expect(out.historyByUid['boost']['TotalTenths']).toBe(440);
    // churn: 595 gross - 4 pts transfer cost * 10 = 555 net.
    expect(out.historyByUid['churn']['TotalTenths']).toBe(555);
    // Breakdown, slot by slot in pick order (hand math): Eli 0 played,
    // Dana 130, Eva -30, Ezra absent 0, Alex armband 12*2*10=240,
    // Will bench half -4*50~/10=-20, Wren bench auto-subbed FULL 30.
    expect(alpha['Breakdown']).toEqual([
      { playerId: 'Eli', countedTenths: 0, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Dana', countedTenths: 130, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Eva', countedTenths: -30, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Ezra', countedTenths: 0, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Alex', countedTenths: 240, multiplier: 2, autoSubbedIn: false },
      { playerId: 'Will', countedTenths: -20, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Wren', countedTenths: 30, multiplier: 1, autoSubbedIn: true },
    ]);
  });

  it('gameweek board: whole net points, competition ranks', () => {
    expect(out.gameweekBoard).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 55, rank: 1 },
    });
  });

  it('overall board after the first week: same points, movement omitted', () => {
    expect(out.overallBoard).toEqual({
      alpha: { points: 35, rank: 3 },
      boost: { points: 44, rank: 2 },
      churn: { points: 55, rank: 1 },
    });
  });

  it('player totals: season points + ownership of 3 managers', () => {
    // Holdings (hand count over the three squads): Eva/Ezra/Wren in all 3
    // (100), Dana/Will/Bea/Ben in 2 (round(200/3)=67), Eli/Alex/Sam/Bo in 1
    // (round(100/3)=33), Wes in none (0).
    // One finalized week: form (tenths) = 10 x that week's points; every
    // player but absent Ezra played one game, so ppg (tenths) = form.
    expect(out.playerTotals['Eva']).toEqual({
      points: -3, ownershipPct: 100, form: -30, ppg: -30, games: 1,
    });
    expect(out.playerTotals['Ezra']).toEqual({
      points: 0, ownershipPct: 100, form: 0, ppg: 0, games: 0,
    });
    expect(out.playerTotals['Wren']).toEqual({
      points: 3, ownershipPct: 100, form: 30, ppg: 30, games: 1,
    });
    expect(out.playerTotals['Dana']).toEqual({
      points: 13, ownershipPct: 67, form: 130, ppg: 130, games: 1,
    });
    expect(out.playerTotals['Ben']).toEqual({
      points: 9, ownershipPct: 67, form: 90, ppg: 90, games: 1,
    });
    expect(out.playerTotals['Bo']).toEqual({
      points: 12, ownershipPct: 33, form: 120, ppg: 120, games: 1,
    });
    expect(out.playerTotals['Wes']).toEqual({
      points: 1, ownershipPct: 0, form: 10, ppg: 10, games: 1,
    });
    expect(Object.keys(out.playerTotals).length).toBe(12);
  });

  it('dream team: top 1 GK + 2 DEF + 2 ATT by week points', () => {
    // GK: Bo 12 (Sam 9, Wes 1, Eli 0). DEF: Bea 15, Dana 13. ATT: Alex 12,
    // Ben 9 (Wren 3, Ezra 0).
    expect(out.dreamTeam).toEqual({
      Players: [
        { name: 'Bo', position: 'GK', points: 12 },
        { name: 'Bea', position: 'DEF', points: 15 },
        { name: 'Dana', position: 'DEF', points: 13 },
        { name: 'Alex', position: 'ATT', points: 12 },
        { name: 'Ben', position: 'ATT', points: 9 },
      ],
      ComputedAt: 1_750_000_000_000,
      Auto: true,
    });
  });

  it('no squads were skipped', () => {
    expect(out.skippedSquadUids).toEqual([]);
  });

  it('is deterministic (rerun = identical output)', () => {
    expect(computeGameweekFinalize(baseInput())).toEqual(out);
  });
});

describe('computeGameweekFinalize edges', () => {
  it('Phase E seam defaults to zero transfer costs', () => {
    const input = baseInput();
    delete input.transferCostPointsByUid;
    const out = computeGameweekFinalize(input);
    expect(out.historyByUid['churn']['TotalTenths']).toBe(595); // gross
    expect(out.gameweekBoard['churn']).toEqual({ points: 59, rank: 1 });
  });

  it('malformed squads are skipped and reported, never crash', () => {
    const input = baseInput();
    input.squadsByUid['junk'] = { picks: 'nope' };
    input.squadsByUid['junk2'] = 7;
    const out = computeGameweekFinalize(input);
    expect(out.skippedSquadUids.sort()).toEqual(['junk', 'junk2']);
    expect(Object.keys(out.gameweekBoard).sort())
      .toEqual(['alpha', 'boost', 'churn']);
  });

  it('History rows copy realizedTenths in both branches (scored and invalid)', () => {
    const input = baseInput();
    const sq = input.squadsByUid as Record<string, Record<string, unknown>>;
    sq['alpha']['realizedTenths'] = 12; // scored
    sq['boost']['realizedTenths'] = -4;
    sq['boost']['Invalid'] = ['overBudget']; // invalid
    sq['churn']['realizedTenths'] = 'nope'; // not a number: not copied
    const out = computeGameweekFinalize(input);
    expect(out.historyByUid['alpha']['realizedTenths']).toBe(12);
    expect(Array.isArray(out.historyByUid['alpha']['Breakdown'])).toBe(true);
    expect(out.historyByUid['boost']).toMatchObject(
      { TotalTenths: 0, Invalid: ['overBudget'], realizedTenths: -4 });
    expect('realizedTenths' in out.historyByUid['churn']).toBe(false);
    // A rerun from the History rows keeps them.
    const again = computeGameweekFinalize(
      { ...baseInput(), squadsByUid: out.historyByUid });
    expect(again.historyByUid['alpha']['realizedTenths']).toBe(12);
    expect(again.historyByUid['boost']['realizedTenths']).toBe(-4);
  });

  it('admin-edited dream team (Auto false) is preserved (null output)', () => {
    const input = baseInput();
    input.dreamTeamAuto = false;
    expect(computeGameweekFinalize(input).dreamTeam).toBeNull();
  });

  it('our own earlier dream team (Auto true) is recomputed', () => {
    const input = baseInput();
    input.dreamTeamAuto = true;
    expect(computeGameweekFinalize(input).dreamTeam).not.toBeNull();
  });

  it('resums Overall across stored weeks on a later gameweek', () => {
    // Pretend week 1 stored the golden nets; week 2 replays the same games
    // with no transfer costs: nets 350/440/595 -> +35/+44/+59.
    // Totals: alpha 70, boost 88, churn 55+59=114 -> churn r1, boost r2,
    // alpha r3 — unchanged places, so movement is 0 (neutral), not omitted.
    const input = baseInput();
    input.gw = 2;
    input.transferCostPointsByUid = {};
    input.historyTenthsByWeek = { 1: { alpha: 350, boost: 440, churn: 555 } };
    const out = computeGameweekFinalize(input);
    expect(out.overallBoard).toEqual({
      alpha: { points: 70, rank: 3, movement: 0 },
      boost: { points: 88, rank: 2, movement: 0 },
      churn: { points: 114, rank: 1, movement: 0 },
    });
  });

  it('resums PlayerTotals across stored player weeks', () => {
    const input = baseInput();
    input.gw = 2;
    input.playerWeeksByWeek = { 1: { Bea: 15, Bo: 12 } };
    const out = computeGameweekFinalize(input);
    expect(out.playerTotals['Bea'].points).toBe(30); // 15 + 15
    expect(out.playerTotals['Bo'].points).toBe(24); // 12 + 12
    expect(out.playerTotals['Sam'].points).toBe(9); // no week-1 entry
  });

  it('a guest outside the market consumes a bonus slot but earns no week', () => {
    // One game, A 2-0 B. Gus (not in the market) scores twice: BPS
    // 2*12+5=29; Ann scores once: 12+5=17 -> bonus Gus 3, Ann 2.
    // Ann week = plays 1 + goal 4 + CS 2 + bonus 2 = 9.
    const out = computeGameweekFinalize({
      cfg,
      gw: 1,
      games: [{
        node: {
          team1: 'A', team2: 'B', team1score: 2, team2score: 0, status: 2,
          team1activity: {
            "1'": [{ Goal: 'Gus' }, { Goal: 'Gus' }],
            "2'": [{ Goal: 'Ann' }],
          },
        },
        attendance: null,
      }],
      players: { Ann: { position: 'ATT', eligible: true } },
      squadsByUid: {},
      playerWeeksByWeek: {},
      playedGamesByWeek: {},
      historyTenthsByWeek: {},
      dreamTeamAuto: null,
      nowMs: 1,
    });
    expect(out.playerWeeks).toEqual({ Ann: 9 });
    expect('Gus' in out.playerTotals).toBe(false);
  });

  it('a VOIDED week: zero for everyone (cost waived), marker, real Breakdown', () => {
    // Golden week 1 with churn's 4-point cost, voided. Hand math: every net
    // is 0 (churn NOT -40: the cost is waived with the week) -> weekly
    // whole points 0, all tied at rank 1; Overall = this lone zero week
    // (no earlier week -> movement omitted). PlayerTotals skip the week:
    // every points 0, ownership still this week's real holdings (Bea 2/3
    // = 67, Bo 1/3 = 33, Eva 3/3 = 100). PlayerWeeks keep the real points.
    const input = baseInput();
    input.voidedWeeks = [1];
    const out = computeGameweekFinalize(input);
    expect(out.voided).toBe(true);
    for (const uid of ['alpha', 'boost', 'churn']) {
      expect(out.historyByUid[uid]['TotalTenths']).toBe(0);
      expect(out.historyByUid[uid]['Voided']).toBe(true);
    }
    // The squad viewer still has the squad + the would-have-counted slots.
    expect(out.historyByUid['alpha']['captainId']).toBe('Ezra');
    expect(out.historyByUid['alpha']['Breakdown']).toEqual([
      { playerId: 'Eli', countedTenths: 0, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Dana', countedTenths: 130, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Eva', countedTenths: -30, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Ezra', countedTenths: 0, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Alex', countedTenths: 240, multiplier: 2, autoSubbedIn: false },
      { playerId: 'Will', countedTenths: -20, multiplier: 1, autoSubbedIn: false },
      { playerId: 'Wren', countedTenths: 30, multiplier: 1, autoSubbedIn: true },
    ]);
    expect(out.gameweekBoard).toEqual({
      alpha: { points: 0, rank: 1 },
      boost: { points: 0, rank: 1 },
      churn: { points: 0, rank: 1 },
    });
    expect(out.overallBoard).toEqual({
      alpha: { points: 0, rank: 1 },
      boost: { points: 0, rank: 1 },
      churn: { points: 0, rank: 1 },
    });
    expect(out.playerWeeks).toEqual(WEEK_POINTS);
    // A voided week is excluded from form/games too: nothing non-voided
    // is left, so form 0, games 0, ppg 0.
    const none = { form: 0, ppg: 0, games: 0 };
    expect(out.playerTotals['Bea'])
      .toEqual({ points: 0, ownershipPct: 67, ...none });
    expect(out.playerTotals['Bo'])
      .toEqual({ points: 0, ownershipPct: 33, ...none });
    expect(out.playerTotals['Eva'])
      .toEqual({ points: 0, ownershipPct: 100, ...none });
    expect(out.dreamTeam).toBeNull();
    expect(out.removeAutoDreamTeam).toBe(false); // nothing of ours existed
  });

  it('voided week Dream Team: ours is taken down, an admin edit is not', () => {
    const ours = baseInput();
    ours.voidedWeeks = [1];
    ours.dreamTeamAuto = true;
    const a = computeGameweekFinalize(ours);
    expect(a.dreamTeam).toBeNull();
    expect(a.removeAutoDreamTeam).toBe(true);

    const admin = baseInput();
    admin.voidedWeeks = [1];
    admin.dreamTeamAuto = false;
    const b = computeGameweekFinalize(admin);
    expect(b.dreamTeam).toBeNull();
    expect(b.removeAutoDreamTeam).toBe(false);

    // A normal week never removes anything.
    const normal = baseInput();
    normal.dreamTeamAuto = true;
    expect(computeGameweekFinalize(normal).removeAutoDreamTeam).toBe(false);
  });

  it('an EARLIER voided week resums as zero even if its stored values are not', () => {
    // Week 1 stored nets 350/440/555 and player weeks Bea 15 / Bo 12, but
    // week 1 is voided. Week 2 replays the golden games with no costs:
    // nets 350/440/595 -> 35/44/59. Overall = 0 + week 2 = 35/44/59 ->
    // ranks alpha 3, boost 2, churn 1. Standings before week 2 = the voided
    // week, all 0 -> everyone rank 1 -> movement = 1 - rank: alpha -2,
    // boost -1, churn 0. (Without the void: 70/88/114, movement 0.)
    // PlayerTotals = week 2 only: Bea 15, Bo 12, Sam 9.
    const input = baseInput();
    input.gw = 2;
    input.transferCostPointsByUid = {};
    input.historyTenthsByWeek = { 1: { alpha: 350, boost: 440, churn: 555 } };
    input.playerWeeksByWeek = { 1: { Bea: 15, Bo: 12 } };
    input.voidedWeeks = [1];
    const out = computeGameweekFinalize(input);
    expect(out.voided).toBe(false);
    expect('Voided' in out.historyByUid['alpha']).toBe(false);
    expect(out.historyByUid['churn']['TotalTenths']).toBe(595);
    expect(out.overallBoard).toEqual({
      alpha: { points: 35, rank: 3, movement: -2 },
      boost: { points: 44, rank: 2, movement: -1 },
      churn: { points: 59, rank: 1, movement: 0 },
    });
    expect(out.playerTotals['Bea'].points).toBe(15);
    expect(out.playerTotals['Bo'].points).toBe(12);
    expect(out.playerTotals['Sam'].points).toBe(9);
    expect(out.dreamTeam).not.toBeNull();
  });

  it('a rerun of an OLDER week measures ownership over the latest week', () => {
    // Golden week 1 re-scored after week 2 finalized. Week 2's squads (the
    // latest): alpha + boost only (a malformed one is skipped, not counted).
    // Hand count over those two: Bea boost only -> 50 (week 1 said 67), Bo
    // nobody -> 0 (week 1: 33), Sam boost -> 50 (week 1: 33), Eva both ->
    // 100. Points are untouched by this.
    const input = baseInput();
    const latest = fixtureSquads();
    delete latest['churn'];
    input.ownershipSquadsByUid = { ...latest, junk: { picks: 'nope' } };
    const out = computeGameweekFinalize(input);
    const plain = computeGameweekFinalize(baseInput());
    const pick = (n: string) => {
      const { points, ownershipPct } = out.playerTotals[n];
      return { points, ownershipPct };
    };
    expect(pick('Bea')).toEqual({ points: 15, ownershipPct: 50 });
    expect(pick('Bo')).toEqual({ points: 12, ownershipPct: 0 });
    expect(pick('Sam')).toEqual({ points: 9, ownershipPct: 50 });
    expect(pick('Eva')).toEqual({ points: -3, ownershipPct: 100 });
    // Everything except ownership is identical to a plain run.
    expect(out.historyByUid).toEqual(plain.historyByUid);
    expect(out.dreamTeam).toEqual(plain.dreamTeam);
  });

  it('rankHistory: a VOIDED current week holds every rank (it counts zero)', () => {
    // Stored week 1: alpha 10, boost 20, churn 5 -> boost 1, alpha 2,
    // churn 3. Week 2 voided -> +0 for all -> the same ranks after week 2.
    const input = baseInput();
    input.gw = 2;
    input.transferCostPointsByUid = {};
    input.historyTenthsByWeek = { 1: { alpha: 100, boost: 200, churn: 50 } };
    input.voidedWeeks = [2];
    expect(computeGameweekFinalize(input).rankHistory).toEqual({
      alpha: { '1': 2, '2': 2 },
      boost: { '1': 1, '2': 1 },
      churn: { '1': 3, '2': 3 },
    });
    // Not voided: week 2 nets 350/440/595 -> 35/44/59, cumulative alpha 45,
    // boost 64, churn 64 -> boost 1, churn 1 (tied), alpha 3.
    input.voidedWeeks = [];
    expect(computeGameweekFinalize(input).rankHistory).toEqual({
      alpha: { '1': 2, '2': 3 },
      boost: { '1': 1, '2': 1 },
      churn: { '1': 3, '2': 1 },
    });
  });

  it('rankHistory: an EARLIER voided week counts zero whatever its stored tenths say', () => {
    // Week 1 stored 350/440/555 but voided -> all 0 -> everyone rank 1.
    // Week 2 (no costs) 35/44/59 -> alpha 3, boost 2, churn 1 — the same
    // places the Overall board's movement -2/-1/0 implies.
    const input = baseInput();
    input.gw = 2;
    input.transferCostPointsByUid = {};
    input.historyTenthsByWeek = { 1: { alpha: 350, boost: 440, churn: 555 } };
    input.voidedWeeks = [1];
    expect(computeGameweekFinalize(input).rankHistory).toEqual({
      alpha: { '1': 1, '2': 3 },
      boost: { '1': 1, '2': 2 },
      churn: { '1': 1, '2': 1 },
    });
  });

  it('rankHistory: rerun-identical, and a rerun of an OLDER week rebuilds the whole season', () => {
    // Golden week 1 (nets 350/440/555) re-scored after week 2 stored
    // 600/100/200: the history covers both weeks exactly as composing the
    // two weeks directly would. Week 1: alpha 3, boost 2, churn 1.
    // Week 2 cumulative: alpha 95 r1, boost 54 r3, churn 75 r2.
    const input = baseInput();
    input.historyTenthsByWeek = { 2: { alpha: 600, boost: 100, churn: 200 } };
    const out = computeGameweekFinalize(input);
    expect(out.rankHistory).toEqual({
      alpha: { '1': 3, '2': 1 },
      boost: { '1': 2, '2': 3 },
      churn: { '1': 1, '2': 2 },
    });
    expect(computeGameweekFinalize(input).rankHistory).toEqual(out.rankHistory);
  });

  it('zero managers: boards empty, player data still computed', () => {
    const input = baseInput();
    input.squadsByUid = {};
    const out = computeGameweekFinalize(input);
    expect(out.historyByUid).toEqual({});
    expect(out.gameweekBoard).toEqual({});
    expect(out.overallBoard).toEqual({});
    expect(out.rankHistory).toEqual({});
    expect(out.playerWeeks).toEqual(WEEK_POINTS);
    expect(out.playerTotals['Bea']).toEqual(
      { points: 15, ownershipPct: 0, form: 150, ppg: 150, games: 1 });
  });
});

// ── Round 3 (spec 2026-10-29 §3.1/§3.3): per-player weekly records + the
// richer PlayerTotals. Expected values below are hand math. ──

/** One-game world: A 1-0 B and Ann (A's ATT) the lone scorer. Hand math:
 *  plays 1 + goal 4 + clean sheet 2 + bonus 3 (she is the only one with
 *  BPS) = 10 points, 1 game played. */
function annWeek(overrides: Partial<FinalizeInput> = {}): FinalizeInput {
  return {
    cfg,
    gw: 5,
    games: [{
      node: {
        team1: 'A', team2: 'B', team1score: 1, team2score: 0, status: 2,
        team1activity: { "1'": [{ Goal: 'Ann' }] },
      },
      attendance: null,
    }],
    players: { Ann: { position: 'ATT', eligible: true, teamName: 'A' } },
    squadsByUid: {},
    playerWeeksByWeek: {},
    playedGamesByWeek: {},
    historyTenthsByWeek: {},
    dreamTeamAuto: null,
    nowMs: 1,
    ...overrides,
  };
}

describe('PlayerWeekStats (spec §3.1)', () => {
  const out = computeGameweekFinalize(baseInput());

  it('PlayerWeekStats lines sum to Pts for every player in the golden week', () => {
    expect(Object.keys(out.playerWeekStats).sort())
      .toEqual(Object.keys(WEEK_POINTS).sort());
    for (const [name, entry] of Object.entries(out.playerWeekStats)) {
      const sum = Object.values(entry.Lines ?? {}).reduce((a, l) => a + l.P, 0);
      expect(sum, `${name} lines`).toBe(entry.Pts);
      expect(entry.Pts, `${name} Pts`).toBe(out.playerWeeks[name]);
    }
  });

  it('hand-computed Lines/GP/Games for golden players', () => {
    // Dana (DEF, Sharks 3-1 Wolves): plays 1 + goal 6 + assist 4 (dpl 1 < 5,
    // conceded 1: no CS, no deduction) + bonus 2 = 13.
    expect(out.playerWeekStats['Dana']).toEqual({
      Pts: 13, Played: true, GP: 1,
      Games: [{ Vs: 'Wolves', For: 3, Against: 1 }],
      Lines: {
        plays: { N: 1, P: 1 }, goals: { N: 1, P: 6 },
        assists: { N: 1, P: 4 }, bonus: { N: 2, P: 2 },
      },
    });
    // Bea (DEF, Bulls 2-0 Eagles; the "2" score is a String in the node):
    // plays 1 + assist 4 + clean sheet 5 + dpl(5) 2 + bonus 3 = 15.
    expect(out.playerWeekStats['Bea']).toEqual({
      Pts: 15, Played: true, GP: 1,
      Games: [{ Vs: 'Eagles', For: 2, Against: 0 }],
      Lines: {
        plays: { N: 1, P: 1 }, assists: { N: 1, P: 4 },
        cleanSheet: { N: 1, P: 5 }, dpl: { N: 5, P: 2 },
        bonus: { N: 3, P: 3 },
      },
    });
    // Sam (GK): plays 1 + saves 4 (3 Save + the PenSaved pairs) -> 2 +
    // penalty save 5 + bonus 1 = 9.
    expect(out.playerWeekStats['Sam'].Lines).toEqual({
      plays: { N: 1, P: 1 }, saves: { N: 4, P: 2 },
      penSaved: { N: 1, P: 5 }, bonus: { N: 1, P: 1 },
    });
    // Eva (DEF, Eagles 0-2 Bulls): plays 1 - conceded 2 (2 -> -1) - yellow 1
    // - own goal 2 = -3; no bonus line (zero lines are omitted).
    expect(out.playerWeekStats['Eva'].Lines).toEqual({
      plays: { N: 1, P: 1 }, conceded: { N: 2, P: -1 },
      yellow: { N: 1, P: -1 }, ownGoals: { N: 1, P: -2 },
    });
    // Will (DEF, Wolves): plays 1, conceded 3 -> -1, yellow -1, red -3 = -4.
    expect(out.playerWeekStats['Will'].Lines).toEqual({
      plays: { N: 1, P: 1 }, conceded: { N: 3, P: -1 },
      yellow: { N: 1, P: -1 }, red: { N: 1, P: -3 },
    });
    // Wren (ATT, Wolves): plays 1 + goal 4 + pen miss -2 = 3.
    expect(out.playerWeekStats['Wren'].Lines).toEqual({
      plays: { N: 1, P: 1 }, goals: { N: 1, P: 4 },
      penMissed: { N: 1, P: -2 },
    });
  });

  it('absent player (team played, he did not): Played false, GP 0, no Lines', () => {
    // Ezra is marked absent on the Eagles' game: 0 points, but the team's
    // game still appears in his Games.
    expect(out.playerWeekStats['Ezra']).toStrictEqual({
      Pts: 0, Played: false, GP: 0,
      Games: [{ Vs: 'Bulls', For: 0, Against: 2 }],
    });
  });

  it('PlayerWeekStats Games lists opponent and score from the player team view', () => {
    // Team A 4-2 B. A's players see {Vs:B, For:4, Against:2}; B's players see
    // it from their side.
    const out2 = computeGameweekFinalize(annWeek({
      games: [{
        node: { team1: 'A', team2: 'B', team1score: 4, team2score: 2, status: 2 },
        attendance: { A: { Ann: true }, B: { Bob: true } },
      }],
      players: {
        Ann: { position: 'ATT', eligible: true, teamName: 'A' },
        Bob: { position: 'DEF', eligible: true, teamName: 'B' },
      },
    }));
    expect(out2.playerWeekStats['Ann'].Games[0])
      .toStrictEqual({ Vs: 'B', For: 4, Against: 2 });
    expect(out2.playerWeekStats['Bob'].Games[0])
      .toStrictEqual({ Vs: 'A', For: 2, Against: 4 });
  });

  it('Games read String and legacy team1Score/team2Score scores too', () => {
    const out2 = computeGameweekFinalize(annWeek({
      games: [{
        node: { team1: 'A', team2: 'B', team1Score: '3', team2Score: 1, status: 2 },
        attendance: { A: { Ann: true }, B: {} },
      }],
    }));
    expect(out2.playerWeekStats['Ann'].Games)
      .toStrictEqual([{ Vs: 'B', For: 3, Against: 1 }]);
  });

  it('two games in the week: both listed in order, GP and lines sum', () => {
    const second = {
      node: {
        team1: 'C', team2: 'A', team1score: 0, team2score: 2, status: 2,
        team2activity: { "3'": [{ Goal: 'Ann' }, { Goal: 'Ann' }] },
      },
      attendance: null,
    };
    const input = annWeek();
    input.games = [...input.games, second];
    const e = computeGameweekFinalize(input).playerWeekStats['Ann'];
    expect(e.Games).toStrictEqual([
      { Vs: 'B', For: 1, Against: 0 },
      { Vs: 'C', For: 2, Against: 0 },
    ]);
    expect(e.GP).toBe(2);
    expect(e.Lines!['plays']).toStrictEqual({ N: 2, P: 2 });
    expect(e.Lines!['goals']).toStrictEqual({ N: 3, P: 12 });
    expect(e.Lines!['cleanSheet']).toStrictEqual({ N: 2, P: 4 });
    expect(Object.values(e.Lines!).reduce((a, l) => a + l.P, 0)).toBe(e.Pts);
  });

  it('forfeit: the team that showed up gets Plays only; the forfeiter did not play', () => {
    const o = computeGameweekFinalize(annWeek({
      games: [{
        node: {
          team1: 'A', team2: 'B', team1score: 0, team2score: 0, status: 2,
          forfeitedBy: 2,
        },
        attendance: { A: { Ann: true }, B: { Bob: true } },
      }],
      players: {
        Ann: { position: 'ATT', eligible: true, teamName: 'A' },
        Bob: { position: 'DEF', eligible: true, teamName: 'B' },
      },
    }));
    expect(o.playerWeekStats['Ann']).toStrictEqual({
      Pts: 1, Played: true, GP: 1,
      Games: [{ Vs: 'B', For: 0, Against: 0, Forfeit: 'won' }],
      Lines: { plays: { N: 1, P: 1 } },
    });
    expect(o.playerWeekStats['Bob']).toStrictEqual({
      Pts: 0, Played: false, GP: 0,
      Games: [{ Vs: 'A', For: 0, Against: 0, Forfeit: 'lost' }],
    });
  });

  it('voided week writes Pts 0, Voided true, no Lines', () => {
    const input = baseInput();
    input.voidedWeeks = [1];
    const v = computeGameweekFinalize(input);
    expect(Object.keys(v.playerWeekStats).length).toBe(12);
    for (const [name, e] of Object.entries(v.playerWeekStats)) {
      expect(e.Pts, name).toBe(0);
      expect(e.Voided, name).toBe(true);
      expect('Lines' in e, `${name} has no Lines`).toBe(false);
    }
    // What happened on court is still recorded (Played + Games), exactly
    // like the History Breakdown of a voided week; PlayerWeeks keeps real
    // points, as before.
    expect(v.playerWeekStats['Dana'].Played).toBe(true);
    expect(v.playerWeekStats['Dana'].Games)
      .toStrictEqual([{ Vs: 'Wolves', For: 3, Against: 1 }]);
    expect(v.playerWeekStats['Ezra'].Played).toBe(false);
    expect(v.playerWeeks).toEqual(WEEK_POINTS);
    // A normal week never carries the marker.
    expect('Voided' in out.playerWeekStats['Dana']).toBe(false);
  });

  it('player with no game this week: {Pts:0, Played:false, GP:0, Games:[]}', () => {
    const input = baseInput();
    input.players['Zed'] = { position: 'ATT', eligible: true, teamName: 'Nobody' };
    input.players['Nox'] = { position: 'DEF', eligible: true }; // no teamName
    const o = computeGameweekFinalize(input);
    expect(o.playerWeekStats['Zed'])
      .toStrictEqual({ Pts: 0, Played: false, GP: 0, Games: [] });
    expect(o.playerWeekStats['Nox'])
      .toStrictEqual({ Pts: 0, Played: false, GP: 0, Games: [] });
  });

  it('guests outside the market get no entry', () => {
    const o = computeGameweekFinalize(annWeek({ players: {} }));
    expect(o.playerWeekStats).toEqual({});
  });

  it('rerun is identical', () => {
    const input = annWeek({
      playerWeeksByWeek: { 1: { Ann: 3 }, 2: { Ann: 5 } },
      playedGamesByWeek: { 1: { Ann: 1 }, 2: { Ann: 2 } },
    });
    const a = computeGameweekFinalize(input);
    const b = computeGameweekFinalize(input); // the SAME input object again
    expect(b).toEqual(a);
    expect(JSON.stringify(b)).toBe(JSON.stringify(a));
    expect(computeGameweekFinalize(baseInput()).playerWeekStats)
      .toEqual(out.playerWeekStats);
  });
});

describe('PlayerTotals form / ppg / games (spec §3.3)', () => {
  it('Ann alone scores 10 over 1 game (the scenario every case below uses)', () => {
    const o = computeGameweekFinalize(annWeek());
    expect(o.playerWeeks).toEqual({ Ann: 10 });
    expect(o.playerWeekStats['Ann'].GP).toBe(1);
  });

  it('form averages the 3 latest non-voided weeks', () => {
    // Weeks 1..5 Pts [2,4,6,8,10], week 4 voided: the 3 highest NON-voided
    // are 5, 3, 2 -> (10 + 6 + 4) / 3 = 6.667 -> 67 tenths.
    const o = computeGameweekFinalize(annWeek({
      playerWeeksByWeek: {
        1: { Ann: 2 }, 2: { Ann: 4 }, 3: { Ann: 6 }, 4: { Ann: 8 },
      },
      voidedWeeks: [4],
    }));
    expect(o.playerTotals['Ann'].form).toBe(67);
  });

  it('form: "highest-numbered" is numeric (week 10 beats week 9, not lexical)', () => {
    // gw 11 (Ann 10) + week 10 (4) + week 9 (2) -> 16 / 3 = 5.33 -> 53;
    // week 2 (100) must NOT count.
    const o = computeGameweekFinalize(annWeek({
      gw: 11,
      playerWeeksByWeek: { 2: { Ann: 100 }, 9: { Ann: 2 }, 10: { Ann: 4 } },
    }));
    expect(o.playerTotals['Ann'].form).toBe(53);
  });

  it('form: fewer than 3 weeks averages just those; a week without the player counts 0', () => {
    // gw 2 + week 1 (5): (10 + 5) / 2 = 7.5 -> 75.
    const two = computeGameweekFinalize(annWeek({
      gw: 2, playerWeeksByWeek: { 1: { Ann: 5 } },
    }));
    expect(two.playerTotals['Ann'].form).toBe(75);
    // gw 4, week 3 exists but without Ann (0), week 2 (6): (10 + 0 + 6) / 3
    // = 5.33 -> 53; week 1 (9) is outside the window.
    const miss = computeGameweekFinalize(annWeek({
      gw: 4, playerWeeksByWeek: { 1: { Ann: 9 }, 2: { Ann: 6 }, 3: { Bob: 5 } },
    }));
    expect(miss.playerTotals['Ann'].form).toBe(53);
  });

  it('form: no non-voided week at all -> 0', () => {
    const o = computeGameweekFinalize(annWeek({ gw: 1, voidedWeeks: [1] }));
    expect(o.playerTotals['Ann']).toEqual(
      { points: 0, ownershipPct: 0, form: 0, ppg: 0, games: 0 });
  });

  it('ppg is 0 when no games', () => {
    // Zed's team never plays: no game this week, and the stored week has
    // points but no GP record -> games 0, ppg 0 (never NaN / Infinity).
    // Form: weeks 5 (0) and 1 (5) -> 2.5 -> 25 tenths.
    const o = computeGameweekFinalize(annWeek({
      players: {
        Zed: { position: 'ATT', eligible: true, teamName: 'Nobody' },
      },
      playerWeeksByWeek: { 1: { Zed: 5 } },
    }));
    expect(o.playerTotals['Zed'])
      .toEqual({ points: 5, ownershipPct: 0, form: 25, ppg: 0, games: 0 });
  });

  it('ppg = round(10 × points / games)', () => {
    // Points 6 + 7 + 10 = 23 over games 2 + 1 + 1 = 4 -> 5.75 -> 58 tenths.
    const o = computeGameweekFinalize(annWeek({
      playerWeeksByWeek: { 1: { Ann: 6 }, 2: { Ann: 7 } },
      playedGamesByWeek: { 1: { Ann: 2 }, 2: { Ann: 1 } },
    }));
    expect(o.playerTotals['Ann'].points).toBe(23);
    expect(o.playerTotals['Ann'].games).toBe(4);
    expect(o.playerTotals['Ann'].ppg).toBe(58);
  });

  it('games and ppg skip voided weeks like points do', () => {
    // Week 3 (50 points, 5 games) is voided: points 6 + 10 = 16, games
    // 2 + 1 = 3 -> 5.33 -> 53. Form: weeks 5 (10) and 1 (6) -> 8 -> 80.
    const o = computeGameweekFinalize(annWeek({
      playerWeeksByWeek: { 1: { Ann: 6 }, 3: { Ann: 50 } },
      playedGamesByWeek: { 1: { Ann: 2 }, 3: { Ann: 5 } },
      voidedWeeks: [3],
    }));
    expect(o.playerTotals['Ann'])
      .toEqual({ points: 16, ownershipPct: 0, form: 80, ppg: 53, games: 3 });
  });

  it('this week replaces any stale stored GP for the same gameweek', () => {
    const o = computeGameweekFinalize(annWeek({
      playedGamesByWeek: { 5: { Ann: 9 } },
    }));
    expect(o.playerTotals['Ann'].games).toBe(1);
  });
});

// ── Live design 2026-11-03 §1: stages 1–4 are the exported scoreWeekCore,
// which the live week will reuse. With no pendingTeams it IS finalize's
// scoring — the pending rule itself lives in week_core_pending.test.ts. ──
describe('scoreWeekCore = computeGameweekFinalize stages 1–4', () => {
  /** The core's input for a finalize input (finalize never passes
   *  pendingTeams). */
  const coreOf = (f: FinalizeInput) => scoreWeekCore({
    cfg: f.cfg,
    gw: f.gw,
    games: f.games,
    players: f.players,
    squadsByUid: f.squadsByUid,
    transferCostPointsByUid: f.transferCostPointsByUid,
    voided: (f.voidedWeeks ?? []).includes(f.gw),
  });

  it('golden week: hand-math week points, net tenths, holders and managers', () => {
    const core = coreOf(baseInput());
    expect(core.playerWeeks).toEqual(WEEK_POINTS);
    for (const [name, points] of Object.entries(WEEK_POINTS)) {
      expect(core.week[name], name).toEqual(
        { points, played: name !== 'Ezra' }); // Ezra was marked absent
    }
    expect(core.weekTenthsByUid).toEqual({ alpha: 350, boost: 440, churn: 555 });
    // Holdings (the same hand count as the ownership test above).
    expect(core.holders).toEqual({
      Eva: 3, Ezra: 3, Wren: 3, Dana: 2, Will: 2, Bea: 2, Ben: 2,
      Eli: 1, Alex: 1, Sam: 1, Bo: 1,
    });
    expect(core.scoredValid).toBe(3);
    expect(core.skippedSquadUids).toEqual([]);
    // Every golden game is Final: no bonus is provisional.
    expect(core.bonusProvisional.size).toBe(0);
  });

  it('finalize publishes exactly the core\'s player weeks, stats and History (normal + voided)', () => {
    for (const voidedWeeks of [[], [1]]) {
      const input = baseInput();
      input.voidedWeeks = voidedWeeks;
      input.squadsByUid['junk'] = 7; // the skip list passes through too
      const core = coreOf(input);
      const fin = computeGameweekFinalize(input);
      expect(fin.playerWeeks).toEqual(core.playerWeeks);
      expect(fin.playerWeekStats).toEqual(core.playerWeekStats);
      expect(fin.historyByUid).toEqual(core.historyByUid);
      expect(fin.skippedSquadUids).toEqual(core.skippedSquadUids);
      expect(fin.skippedSquadUids).toEqual(['junk']);
    }
  });
});
