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
  competitionRanks, composeOverallBoard, computeGameweekFinalize,
  FinalizeGame, FinalizeInput, MarketPlayer, pickDreamTeam, wholePoints,
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
    out[p['id']] = { position: parsePosition(p['position']), eligible: true };
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

  it('config formation, points desc, eligible only, name asc on ties', () => {
    const team = pickDreamTeam(
      { G1: 5, G2: 8, D1: 7, D2: 7, D3: 9, A1: 4, A2: 4, A3: 99 },
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
    const team = pickDreamTeam({ G1: 1 },
      { G1: { position: 'GK', eligible: true } }, cfg, 1);
    expect(team.Players).toEqual([{ name: 'G1', position: 'GK', points: 1 }]);
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
    expect(out.playerTotals['Eva']).toEqual({ points: -3, ownershipPct: 100 });
    expect(out.playerTotals['Ezra']).toEqual({ points: 0, ownershipPct: 100 });
    expect(out.playerTotals['Wren']).toEqual({ points: 3, ownershipPct: 100 });
    expect(out.playerTotals['Dana']).toEqual({ points: 13, ownershipPct: 67 });
    expect(out.playerTotals['Ben']).toEqual({ points: 9, ownershipPct: 67 });
    expect(out.playerTotals['Bo']).toEqual({ points: 12, ownershipPct: 33 });
    expect(out.playerTotals['Wes']).toEqual({ points: 1, ownershipPct: 0 });
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
      historyTenthsByWeek: {},
      dreamTeamAuto: null,
      nowMs: 1,
    });
    expect(out.playerWeeks).toEqual({ Ann: 9 });
    expect('Gus' in out.playerTotals).toBe(false);
  });

  it('zero managers: boards empty, player data still computed', () => {
    const input = baseInput();
    input.squadsByUid = {};
    const out = computeGameweekFinalize(input);
    expect(out.historyByUid).toEqual({});
    expect(out.gameweekBoard).toEqual({});
    expect(out.overallBoard).toEqual({});
    expect(out.playerWeeks).toEqual(WEEK_POINTS);
    expect(out.playerTotals['Bea'])
      .toEqual({ points: 15, ownershipPct: 0 });
  });
});
