// Per-game scoring breakdown + week totals. Faithful port of
// lib/fantasy/engine/scoring.dart: absent -> zero (empty breakdown), every
// line's label and points match the Dart engine character for character.

import { FantasyConfig, FantasyPosition } from './fantasy_config';
import { PlayerGameStats } from './player_game_stats';

export interface ScoreLine {
  label: string;
  points: number;
}

export interface GameScore {
  total: number;
  breakdown: ScoreLine[];
}

export interface WeekScore {
  total: number;
  played: boolean;
  games: GameScore[];
}

/** Dart `~/` (integer division truncating toward zero). Every operand here is
 *  a non-negative count, so trunc == floor, but trunc is the faithful port. */
function intDiv(a: number, b: number): number {
  return Math.trunc(a / b);
}

export function scorePlayerGame(
  s: PlayerGameStats, pos: FantasyPosition, cfg: FantasyConfig,
): GameScore {
  if (!s.present) return { total: 0, breakdown: [] };
  const r = cfg.scoring[pos];
  const lines: ScoreLine[] = [{ label: 'Plays', points: r.plays }];
  if (s.goals > 0) {
    lines.push({ label: `Goals ×${s.goals}`, points: s.goals * r.goal });
  }
  if (s.assists > 0) {
    lines.push({ label: `Assists ×${s.assists}`, points: s.assists * r.assist });
  }
  if (s.teamConceded === 0 && r.cleanSheet !== 0) {
    lines.push({ label: 'Clean sheet', points: r.cleanSheet });
  }
  if (r.per2Saves !== 0 && s.saves >= 2) {
    lines.push({
      label: `Saves ×${s.saves}`,
      points: intDiv(s.saves, 2) * r.per2Saves, // Dart: (s.saves ~/ 2)
    });
  }
  if (s.penSaved > 0 && r.penSave !== 0) {
    lines.push({
      label: `Penalty saves ×${s.penSaved}`, points: s.penSaved * r.penSave,
    });
  }
  if (s.penMissed > 0) {
    lines.push({
      label: `Penalty misses ×${s.penMissed}`, points: s.penMissed * r.penMiss,
    });
  }
  if (r.per2Conceded !== 0 && s.teamConceded >= 2) {
    lines.push({
      label: `Conceded ${s.teamConceded}`,
      points: intDiv(s.teamConceded, 2) * r.per2Conceded, // Dart: ~/ 2
    });
  }
  if (r.dplThreshold !== null && s.dpl >= r.dplThreshold) {
    lines.push({ label: `Defensive plays ${s.dpl}`, points: r.dplBonus });
  }
  if (s.yellows > 0) {
    lines.push({ label: `Yellow ×${s.yellows}`, points: s.yellows * r.yellow });
  }
  if (s.reds > 0) {
    lines.push({ label: `Red ×${s.reds}`, points: s.reds * r.red });
  }
  if (s.ownGoals > 0) {
    lines.push({
      label: `Own goals ×${s.ownGoals}`, points: s.ownGoals * r.ownGoal,
    });
  }
  return {
    total: lines.reduce((a, l) => a + l.points, 0),
    breakdown: lines,
  };
}

export function scorePlayerWeek(
  games: PlayerGameStats[], pos: FantasyPosition, cfg: FantasyConfig,
): WeekScore {
  const scored = games.map((g) => scorePlayerGame(g, pos, cfg));
  return {
    total: scored.reduce((a, g) => a + g.total, 0),
    played: games.some((g) => g.present),
    games: scored,
  };
}
