// Golden gameweek — the cross-engine contract (P4 Phase A).
//
// Loads test/fantasy/fixtures/golden_gameweek.json FROM THE REPO (not a
// copy) and replays the FULL pipeline exactly as test/fantasy/golden_test.dart
// does on the Dart side:
//   mapper -> scoring -> bps/bonus -> player weeks -> squad weeks ->
//   transfer costs -> reprice deltas,
// asserting every expected number. The expectations were hand-computed from
// futsalDefault() BEFORE either pipeline ran (the hand math is documented in
// the fixture's _notes) — if this replay ever disagrees, the TS port is
// wrong; never copy actual values into the file.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { awardBonus, bpsScore } from './bps';
import {
  FANTASY_POSITIONS, FantasyPosition, futsalDefault, parsePosition,
} from './fantasy_config';
import { PlayerGameStats } from './player_game_stats';
import { repriceDeltas } from './pricing';
import { scorePlayerGame, scorePlayerWeek } from './scoring';
import { squadFromMap, validateSquad } from './squad';
import { PlayerWeek, scoreSquadWeek, totalTenths } from './squad_week';
import { mapGameToStats } from './stats_mapper';
import { transferCost } from './transfers';

/** The fixture lives in the Flutter repo root's test tree; vitest runs from
 *  functions/, but resolve robustly by walking up to the directory that
 *  holds pubspec.yaml (the repo root), wherever the runner starts. */
function fixturePath(): string {
  let dir = process.cwd();
  for (; ;) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) {
      return path.join(
        dir, 'test', 'fantasy', 'fixtures', 'golden_gameweek.json');
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(
        'Could not find the Flutter repo root (pubspec.yaml) above ' +
        process.cwd());
    }
    dir = parent;
  }
}

type Json = Record<string, any>;

const fixture: Json = JSON.parse(fs.readFileSync(fixturePath(), 'utf8'));
const cfg = futsalDefault(); // fixture: "config": "futsalDefault"

const players: Json[] = fixture['players'];
const posOf: Record<string, FantasyPosition> = {};
for (const p of players) posOf[p['id']] = parsePosition(p['position']);
const games: Json[] = fixture['games'];
const expected: Json = fixture['expected'];

// ---- Stage 1: mapper (both teams of every game) ----
const statsByGame: Record<string, PlayerGameStats>[] = [];
for (const g of games) {
  const node: Json = g['node'];
  const attendanceByTeam: Json | null = g['attendance'] ?? null;
  const merged: Record<string, PlayerGameStats> = {};
  for (const team of [node['team1'] as string, node['team2'] as string]) {
    const raw: Json | null = attendanceByTeam?.[team] ?? null;
    let attendance: Record<string, boolean> | null = null;
    if (raw !== null) {
      attendance = {};
      // Dart: raw.map((k, v) => MapEntry(k.toString(), v == true))
      for (const [k, v] of Object.entries(raw)) attendance[k] = v === true;
    }
    Object.assign(merged, mapGameToStats(node, { teamName: team, attendance }));
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

// ---- Stage 3: player weeks (base + bonus; reprice reads these too) ----
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

describe('golden gameweek replay (cross-engine contract)', () => {
  it('per-game base points match hand math', () => {
    const exp: Json[] = expected['basePointsByGame'];
    expect(baseByGame.length).toBe(exp.length);
    for (let i = 0; i < exp.length; i++) {
      expect(baseByGame[i], `game ${i}`).toEqual(exp[i]);
    }
  });

  it('per-game BPS and 3/2/1 bonus awards match hand math', () => {
    const expBps: Json[] = expected['bpsByGame'];
    const expBonus: Json[] = expected['bonusByGame'];
    for (let i = 0; i < expBps.length; i++) {
      expect(bpsByGame[i], `game ${i}`).toEqual(expBps[i]);
      expect(bonusByGame[i], `game ${i} bonus`).toEqual(expBonus[i]);
    }
  });

  it('per-player week points (base + bonus) and played flags', () => {
    const exp: Json = expected['playerWeeks'];
    expect(Object.keys(week).sort()).toEqual(Object.keys(exp).sort());
    for (const [id, e] of Object.entries<any>(exp)) {
      expect(week[id].points, id).toBe(e['points']);
      expect(week[id].played, `${id} played`).toBe(e['played']);
    }
  });

  it('squad weeks: armband fallback, bench boost, auto-subs, transfers', () => {
    const expSquads: Json = expected['squads'];
    for (const s of fixture['squads'] as Json[]) {
      const name: string = s['name'];
      const squad = squadFromMap(s['squad']);
      expect(validateSquad(squad, cfg), `${name} legality`).toEqual([]);

      const exp: Json = expSquads[name];
      const result = scoreSquadWeek(squad, week, cfg);
      expect(totalTenths(result), name).toBe(exp['totalTenths']);

      const transfers: Json = s['transfers'];
      const cost = transferCost({
        used: transfers['used'], free: transfers['free'], cfg,
      });
      expect(cost, `${name} cost`).toBe(exp['transferCostPoints']);
      expect(totalTenths(result) - cost * 10, `${name} net`)
        .toBe(exp['netTenths']);

      // Armband holder is the slot with multiplier > 1 (exactly one, or
      // none when neither captain nor vice played).
      const armbands = result.slots
        .filter((slot) => slot.multiplier > 1)
        .map((slot) => slot.playerId);
      expect(armbands, `${name} armband`).toEqual([exp['armband']]);
      const promoted = result.slots
        .filter((slot) => slot.autoSubbedIn)
        .map((slot) => slot.playerId);
      expect(promoted.sort(), `${name} auto-subs`)
        .toEqual([...(exp['autoSubbedIn'] as string[])].sort());
    }
  });

  it('reprice deltas per position group (absent players at real score)', () => {
    const exp: Json = expected['repriceDeltas'];
    for (const pos of FANTASY_POSITIONS) {
      const group: Record<string, number> = {};
      for (const [id, w] of Object.entries(week)) {
        if (posOf[id] === pos) group[id] = w.points;
      }
      expect(repriceDeltas(group, cfg), pos).toEqual(exp[pos]);
    }
  });
});
