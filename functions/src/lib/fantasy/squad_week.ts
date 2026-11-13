// One manager's gameweek: armband (incl. vice inheritance and the
// triple-captain multiplier), auto-subs (same-position first-unused-bench),
// and bench tenths. Faithful port of lib/fantasy/engine/squad_week.dart.

import { FantasyConfig, FantasyPosition } from './fantasy_config';
import { FantasySquad, squadBench, squadStarters } from './squad';

export interface PlayerWeek {
  points: number; // whole points from scorePlayerWeek().total (+ bonus)
  played: boolean;
}

export interface SlotResult {
  playerId: string;
  position: FantasyPosition;
  bench: boolean;
  rawPoints: number;
  countedTenths: number;
  multiplier: number; // 1 normal, 2 captain, 3 triple captain
  autoSubbedIn: boolean;
  played: boolean;
}

export interface SquadWeekResult {
  slots: SlotResult[];
}

export function totalTenths(r: SquadWeekResult): number {
  return r.slots.reduce((a, s) => a + s.countedTenths, 0);
}

/** Dart SquadWeekResult.slot: throws when the player holds no slot. */
export function slotOf(r: SquadWeekResult, playerId: string): SlotResult {
  const s = r.slots.find((x) => x.playerId === playerId);
  if (!s) throw new Error(`No slot for ${playerId}`);
  return s;
}

export function scoreSquadWeek(
  squad: FantasySquad,
  week: Record<string, PlayerWeek>,
  cfg: FantasyConfig,
): SquadWeekResult {
  const of = (id: string): PlayerWeek =>
    week[id] ?? { points: 0, played: false };

  // Auto-subs: each absent starter is covered by the first unused bench
  // player of the SAME position who played (spec §2). Covering bench scores
  // FULL; uncovered bench scores half (or full on Bench Boost).
  const promoted = new Set<string>();
  for (const starter of squadStarters(squad)) {
    if (of(starter.playerId).played) continue;
    for (const b of squadBench(squad)) {
      if (b.position === starter.position &&
        !promoted.has(b.playerId) &&
        of(b.playerId).played) {
        promoted.add(b.playerId);
        break;
      }
    }
  }

  // Armband: captain if played, else vice if played, else nobody (spec §2).
  const capMult = squad.chip === 'tripleCaptain'
    ? cfg.tripleCaptainMultiplier
    : cfg.captainMultiplier;
  let armband: string | null = null;
  if (of(squad.captainId).played) {
    armband = squad.captainId;
  } else if (of(squad.viceId).played) {
    armband = squad.viceId;
  }

  const benchBoost = squad.chip === 'benchBoost';
  const slots: SlotResult[] = [];
  for (const p of squad.picks) {
    const w = of(p.playerId);
    const mult = p.playerId === armband ? capMult : 1;
    let counted: number;
    if (!w.played) {
      counted = 0;
    } else if (!p.bench) {
      counted = w.points * mult * 10;
    } else if (benchBoost || promoted.has(p.playerId)) {
      counted = w.points * mult * 10;
    } else {
      // Dart: `w.points * mult * cfg.benchFactorPercent ~/ 10` — integer
      // division truncating TOWARD ZERO (points can be negative: -3 pts on
      // the bench is -150 ~/ 10 = -15 tenths; Math.floor would be wrong for
      // non-multiples, e.g. -155/10 -> trunc -15, floor -16).
      counted = Math.trunc((w.points * mult * cfg.benchFactorPercent) / 10);
    }
    slots.push({
      playerId: p.playerId,
      position: p.position,
      bench: p.bench,
      rawPoints: w.points,
      countedTenths: counted,
      multiplier: p.playerId === armband && w.played ? capMult : 1,
      autoSubbedIn: promoted.has(p.playerId),
      played: w.played,
    });
  }
  return { slots };
}
