// Golden FORFEIT gameweek — the cross-engine contract for spec §8a.
//
// Loads test/fantasy/fixtures/golden_forfeit.json FROM THE REPO (not a copy)
// and replays it exactly as test/fantasy/golden_forfeit_test.dart does on
// the Dart side (mapper -> scoring -> bps/bonus -> player weeks -> squad
// weeks), then once more through the finalizer's pure pipeline
// (computeGameweekFinalize) so the server composition is pinned too. The
// expectations were hand-computed BEFORE either engine ran (the fixture's
// _notes) — if this replay disagrees, the TS port is wrong; never copy
// actual values into the file.

import { describe, expect, it } from 'vitest';
import { awardBonus, bpsScore } from './bps';
import { FantasyPosition, futsalDefault, parsePosition } from './fantasy_config';
import { computeGameweekFinalize, MarketPlayer } from './finalize_core';
import { Json, loadFantasyFixture } from './golden_fixture';
import { PlayerGameStats } from './player_game_stats';
import { scorePlayerGame, scorePlayerWeek } from './scoring';
import { squadFromMap, validateSquad } from './squad';
import { PlayerWeek, scoreSquadWeek, totalTenths } from './squad_week';
import { mapGameToStats } from './stats_mapper';

const fixture: Json = loadFantasyFixture('golden_forfeit.json');
const cfg = futsalDefault(); // fixture: "config": "futsalDefault"

const players: Json[] = fixture['players'];
const posOf: Record<string, FantasyPosition> = {};
for (const p of players) posOf[p['id']] = parsePosition(p['position']);
const games: Json[] = fixture['games'];
const expected: Json = fixture['expected'];

/** Dart: raw.map((k, v) => MapEntry(k.toString(), v == true)). */
function attendanceOf(raw: Json | null | undefined): Record<string, boolean> | null {
  if (raw === null || raw === undefined) return null;
  const out: Record<string, boolean> = {};
  for (const [k, v] of Object.entries(raw)) out[k] = v === true;
  return out;
}

// ---- Stage 1: mapper (both teams of every game) ----
const statsByGame: Record<string, PlayerGameStats>[] = [];
for (const g of games) {
  const node: Json = g['node'];
  const merged: Record<string, PlayerGameStats> = {};
  for (const team of [node['team1'] as string, node['team2'] as string]) {
    Object.assign(merged, mapGameToStats(node, {
      teamName: team, attendance: attendanceOf(g['attendance']?.[team]),
    }));
  }
  statsByGame.push(merged);
}

// ---- Stage 2: per-game base points, BPS, bonus ----
const baseByGame: Record<string, number>[] = [];
const bpsByGame: Record<string, number>[] = [];
const bonusByGame: Record<string, number>[] = [];
for (const stats of statsByGame) {
  const base: Record<string, number> = {};
  const bps: Record<string, number> = {};
  for (const [id, s] of Object.entries(stats)) {
    base[id] = scorePlayerGame(s, posOf[id], cfg).total;
    bps[id] = bpsScore(s, cfg);
  }
  baseByGame.push(base);
  bpsByGame.push(bps);
  bonusByGame.push(awardBonus(bps));
}

// ---- Stage 3: player weeks (base + bonus) ----
const week: Record<string, PlayerWeek> = {};
for (const id of Object.keys(posOf)) {
  const wk = scorePlayerWeek(
    statsByGame.filter((stats) => id in stats).map((stats) => stats[id]),
    posOf[id],
    cfg,
  );
  const bonus = bonusByGame.reduce((a, b) => a + (b[id] ?? 0), 0);
  week[id] = { points: wk.total + bonus, played: wk.played };
}

describe('golden forfeit replay (cross-engine contract, spec §8a)', () => {
  it('mapper: forfeit side per player; stray-event-only players excluded', () => {
    const exp: Json[] = expected['forfeitByGame'];
    expect(statsByGame.length).toBe(exp.length);
    for (let i = 0; i < exp.length; i++) {
      const sides: Record<string, string> = {};
      for (const [id, s] of Object.entries(statsByGame[i])) {
        sides[id] = s.forfeit ?? 'none';
      }
      expect(sides, `game ${i}`).toEqual(exp[i]);
    }
    for (const s of Object.values(statsByGame[0])) {
      expect(s.goals + s.assists + s.saves + s.yellows + s.reds + s.dpl).toBe(0);
    }
    expect('Gus' in statsByGame[0]).toBe(false);
  });

  it('per-game base points match hand math', () => {
    const exp: Json[] = expected['basePointsByGame'];
    expect(baseByGame.length).toBe(exp.length);
    for (let i = 0; i < exp.length; i++) {
      expect(baseByGame[i], `game ${i}`).toEqual(exp[i]);
    }
  });

  it('per-game BPS (0 for the whole forfeited game) and bonus', () => {
    const expBps: Json[] = expected['bpsByGame'];
    const expBonus: Json[] = expected['bonusByGame'];
    for (let i = 0; i < expBps.length; i++) {
      expect(bpsByGame[i], `game ${i}`).toEqual(expBps[i]);
      expect(bonusByGame[i], `game ${i} bonus`).toEqual(expBonus[i]);
    }
  });

  it('per-player week points and played flags (forfeiters did not play)', () => {
    const exp: Json = expected['playerWeeks'];
    expect(Object.keys(week).sort()).toEqual(Object.keys(exp).sort());
    for (const [id, e] of Object.entries<any>(exp)) {
      expect(week[id].points, id).toBe(e['points']);
      expect(week[id].played, `${id} played`).toBe(e['played']);
    }
  });

  it('squad weeks: forfeiting captain -> vice armband, auto-subs, ' +
    'no-armband week', () => {
    const expSquads: Json = expected['squads'];
    for (const s of fixture['squads'] as Json[]) {
      const name: string = s['name'];
      const squad = squadFromMap(s['squad']);
      expect(validateSquad(squad, cfg), `${name} legality`).toEqual([]);

      const exp: Json = expSquads[name];
      const result = scoreSquadWeek(squad, week, cfg);
      expect(totalTenths(result), name).toBe(exp['totalTenths']);
      const counted: Record<string, number> = {};
      for (const slot of result.slots) counted[slot.playerId] = slot.countedTenths;
      expect(counted, `${name} slots`).toEqual(exp['countedTenths']);

      const armbands = result.slots
        .filter((slot) => slot.multiplier > 1)
        .map((slot) => slot.playerId);
      const armband: string | null = exp['armband'];
      expect(armbands, `${name} armband`)
        .toEqual(armband === null ? [] : [armband]);
      if (armband !== null) {
        expect(result.slots.find((x) => x.playerId === armband)!.multiplier,
          `${name} armband multiplier`).toBe(exp['armbandMultiplier']);
      }
      const promoted = result.slots
        .filter((slot) => slot.autoSubbedIn)
        .map((slot) => slot.playerId);
      expect(promoted.sort(), `${name} auto-subs`)
        .toEqual([...(exp['autoSubbedIn'] as string[])].sort());
    }
  });

  it('finalizer pipeline (computeGameweekFinalize): same player weeks, ' +
    'History totals and a Dream Team with no forfeiter', () => {
    const market: Record<string, MarketPlayer> = {};
    for (const p of players) {
      market[p['id']] = {
        position: parsePosition(p['position']), eligible: true,
        teamName: p['team'],
      };
    }
    const squadsByUid: Record<string, unknown> = {};
    for (const s of fixture['squads'] as Json[]) squadsByUid[s['name']] = s['squad'];
    const out = computeGameweekFinalize({
      cfg,
      gw: 1,
      games: games.map((g) => ({
        node: g['node'],
        attendance: Object.fromEntries(
          Object.entries(g['attendance'] as Json).map(
            ([team, raw]) => [team, attendanceOf(raw)])),
      })),
      players: market,
      squadsByUid,
      playerWeeksByWeek: {},
      playedGamesByWeek: {},
      historyTenthsByWeek: {},
      dreamTeamAuto: null,
      nowMs: 0,
    });

    const expWeeks: Json = expected['playerWeeks'];
    for (const [id, e] of Object.entries<any>(expWeeks)) {
      expect(out.playerWeeks[id], id).toBe(e['points']);
    }
    for (const [name, e] of Object.entries<any>(expected['squads'])) {
      expect(out.historyByUid[name]['TotalTenths'], name).toBe(e['totalTenths']);
    }
    expect(out.dreamTeam?.Players).toEqual(expected['dreamTeam']);

    // PlayerWeekStats on the forfeit fixture (hand math from the notes: Lions
    // showed up and won 5-0 by forfeit — Plays only; Tigers forfeited — did
    // not play; Lena was absent; Hana's real 2-1 win carries real lines).
    const stats = out.playerWeekStats;
    expect(stats['Luca']).toStrictEqual({
      Pts: 1, Played: true, GP: 1,
      Games: [{ Vs: 'Tigers', For: 5, Against: 0, Forfeit: 'won' }],
      Lines: { plays: { N: 1, P: 1 } },
    });
    expect(stats['Lena']).toStrictEqual({
      Pts: 0, Played: false, GP: 0,
      Games: [{ Vs: 'Tigers', For: 5, Against: 0, Forfeit: 'won' }],
    });
    expect(stats['Tom']).toStrictEqual({
      Pts: 0, Played: false, GP: 0,
      Games: [{ Vs: 'Lions', For: 0, Against: 5, Forfeit: 'lost' }],
    });
    // Every player's lines sum to Pts. Hana (DEF, Hawks 2-1 Foxes): plays 1 +
    // goal 6 + assist 4 = 11 base, + bonus 3 = 14.
    for (const [name, e] of Object.entries(stats)) {
      const sum = Object.values(e.Lines ?? {}).reduce((a, l) => a + l.P, 0);
      expect(sum, name).toBe(e.Pts);
      expect(e.Pts, name).toBe(out.playerWeeks[name]);
    }
    expect(stats['Hana'].Games).toStrictEqual([{ Vs: 'Foxes', For: 2, Against: 1 }]);
    expect(stats['Hana'].Lines!['bonus']).toStrictEqual({ N: 3, P: 3 });
  });
});
