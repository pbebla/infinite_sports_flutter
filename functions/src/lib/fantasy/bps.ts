// Bonus-points system. Faithful port of lib/fantasy/engine/bps.dart.

import { FantasyConfig } from './fantasy_config';
import { PlayerGameStats } from './player_game_stats';

/** Raw bonus-points-system score for one player in one game (published
 *  formula, spec §7 — shown verbatim on the Rules page). A forfeited game
 *  (either side, spec §8a) scores 0 for everyone, so awardBonus — which
 *  only rewards positive BPS — hands out no bonus from it. */
export function bpsScore(s: PlayerGameStats, cfg: FantasyConfig): number {
  if (!s.present || (s.forfeit ?? 'none') !== 'none') return 0;
  const w = cfg.bps;
  return s.goals * w.goal +
    s.assists * w.assist +
    s.saves * w.save +
    s.dpl * w.dpl +
    (s.teamConceded === 0 ? w.cleanSheet : 0) +
    s.penSaved * w.penSave +
    s.penMissed * w.penMiss +
    s.ownGoals * w.ownGoal +
    s.yellows * w.yellow +
    s.reds * w.red;
}

/** 3/2/1 to the best BPS scores in a match, FPL tie rule: equal scores share
 *  the higher bonus and consume the slots below it. Only positive BPS counts. */
export function awardBonus(
  bpsByPlayer: Record<string, number>,
): Record<string, number> {
  const entries = Object.entries(bpsByPlayer)
    .filter(([, v]) => v > 0)
    .sort((a, b) => b[1] - a[1]);
  const ladder = [3, 2, 1];
  const out: Record<string, number> = {};
  let slot = 0;
  let i = 0;
  while (i < entries.length && slot < ladder.length) {
    const tied = entries.filter(([, v]) => v === entries[i][1]);
    for (const [key] of tied) out[key] = ladder[slot];
    i += tied.length;
    slot += tied.length;
  }
  return out;
}
