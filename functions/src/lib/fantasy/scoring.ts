// Per-game scoring breakdown + week totals. Faithful port of
// lib/fantasy/engine/scoring.dart: absent -> zero (empty breakdown), every
// line's label and points match the Dart engine character for character.

import { FantasyConfig, FantasyPosition } from './fantasy_config';
import { PlayerGameStats, playedGame } from './player_game_stats';

/** Stable machine key of a score line (the client maps it to a label; the
 *  display `label` is the match tab's text). Mirrors the Dart twin. */
export type ScoreKey =
  | 'plays' | 'goals' | 'assists' | 'cleanSheet' | 'saves' | 'penSaved'
  | 'penMissed' | 'conceded' | 'dpl' | 'yellow' | 'red' | 'ownGoals';

export interface ScoreLine {
  label: string;
  points: number;
  /** Which source of points this line is. */
  key: ScoreKey;
  /** How many of that source: 1 for `plays`/`cleanSheet`, otherwise the raw
   *  stat count (goals, saves, goals conceded, defensive plays, ...). */
  count: number;
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
  // Absent, or on the team that forfeited (spec §8a): nothing at all — no
  // appearance, no goals-conceded penalty.
  if (!playedGame(s)) return { total: 0, breakdown: [] };
  const r = cfg.scoring[pos];
  // The team that showed up to a forfeit: the appearance point ONLY — no
  // clean sheet, and any stray recorded stats never count.
  if (s.forfeit === 'won') {
    return {
      total: r.plays,
      breakdown: [{ label: 'Plays', points: r.plays, key: 'plays', count: 1 }],
    };
  }
  const lines: ScoreLine[] = [
    { label: 'Plays', points: r.plays, key: 'plays', count: 1 },
  ];
  if (s.goals > 0) {
    lines.push({
      label: `Goals ×${s.goals}`, points: s.goals * r.goal,
      key: 'goals', count: s.goals,
    });
  }
  if (s.assists > 0) {
    lines.push({
      label: `Assists ×${s.assists}`, points: s.assists * r.assist,
      key: 'assists', count: s.assists,
    });
  }
  if (s.teamConceded === 0 && r.cleanSheet !== 0) {
    lines.push({
      label: 'Clean sheet', points: r.cleanSheet, key: 'cleanSheet', count: 1,
    });
  }
  if (r.per2Saves !== 0 && s.saves >= 2) {
    lines.push({
      label: `Saves ×${s.saves}`,
      points: intDiv(s.saves, 2) * r.per2Saves, // Dart: (s.saves ~/ 2)
      key: 'saves', count: s.saves,
    });
  }
  if (s.penSaved > 0 && r.penSave !== 0) {
    lines.push({
      label: `Penalty saves ×${s.penSaved}`, points: s.penSaved * r.penSave,
      key: 'penSaved', count: s.penSaved,
    });
  }
  if (s.penMissed > 0) {
    lines.push({
      label: `Penalty misses ×${s.penMissed}`, points: s.penMissed * r.penMiss,
      key: 'penMissed', count: s.penMissed,
    });
  }
  if (r.per2Conceded !== 0 && s.teamConceded >= 2) {
    lines.push({
      label: `Conceded ${s.teamConceded}`,
      points: intDiv(s.teamConceded, 2) * r.per2Conceded, // Dart: ~/ 2
      key: 'conceded', count: s.teamConceded,
    });
  }
  if (r.dplThreshold !== null && s.dpl >= r.dplThreshold) {
    lines.push({
      label: `Defensive plays ${s.dpl}`, points: r.dplBonus,
      key: 'dpl', count: s.dpl,
    });
  }
  if (s.yellows > 0) {
    lines.push({
      label: `Yellow ×${s.yellows}`, points: s.yellows * r.yellow,
      key: 'yellow', count: s.yellows,
    });
  }
  if (s.reds > 0) {
    lines.push({
      label: `Red ×${s.reds}`, points: s.reds * r.red,
      key: 'red', count: s.reds,
    });
  }
  if (s.ownGoals > 0) {
    lines.push({
      label: `Own goals ×${s.ownGoals}`, points: s.ownGoals * r.ownGoal,
      key: 'ownGoals', count: s.ownGoals,
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
    // A forfeiting team's players did not play (spec §8a) — exactly like
    // absent players for auto-subs and the vice-captain armband.
    played: games.some(playedGame),
    games: scored,
  };
}
