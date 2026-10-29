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

  it('zero managers: boards empty, player data still computed', () => {
    const input = baseInput();
    input.squadsByUid = {};
    const out = computeGameweekFinalize(input);
    expect(out.historyByUid).toEqual({});
    expect(out.gameweekBoard).toEqual({});
    expect(out.overallBoard).toEqual({});
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
