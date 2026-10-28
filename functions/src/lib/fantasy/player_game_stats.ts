// One player's raw stats in one real game — the engine's only input shape.
// `present` comes from the attendance step; `teamConceded` from the final
// score; `forfeit` from the game's `forfeitedBy` marker. Everything else
// from captured activities (always zero on a forfeited game — the mapper
// ignores its events).
//
// Faithful port of lib/fantasy/engine/player_game_stats.dart.

/** How a forfeit touched one player's game (spec §8a, owner Option B) —
 *  Dart `GameForfeit` (the enum's `.name` values):
 *  - 'none': a normal game.
 *  - 'won': the player's team SHOWED UP (the other team forfeited) — a
 *    present player earns ONLY the appearance point; no clean sheet, no
 *    stat points, no bonus (the game contributes nothing to BPS).
 *  - 'lost': the player's team FORFEITED — 0 points, no goals-conceded
 *    penalty, and the player did NOT play (auto-subs and the vice-captain
 *    treat him exactly like an absent player). */
export type GameForfeit = 'none' | 'won' | 'lost';

export interface PlayerGameStats {
  goals: number;
  assists: number;
  saves: number;
  penSaved: number;
  penMissed: number;
  ownGoals: number;
  yellows: number;
  reds: number;
  dpl: number;
  teamConceded: number;
  present: boolean;
  /** Absent = 'none' (the Dart default). */
  forfeit?: GameForfeit;
}

/** Mirrors the Dart const constructor's defaults (all zero, present, no
 *  forfeit). */
export function playerGameStats(
  partial: Partial<PlayerGameStats> = {},
): PlayerGameStats {
  return {
    goals: 0, assists: 0, saves: 0, penSaved: 0, penMissed: 0,
    ownGoals: 0, yellows: 0, reds: 0, dpl: 0, teamConceded: 0,
    present: true, forfeit: 'none',
    ...partial,
  };
}

/** Dart `PlayerGameStats.played`: whether the player took part in this
 *  game — the week's `played` flag (auto-subs, the vice-captain armband,
 *  the Dream Team). Absent players did not play, and neither did a
 *  forfeiting team's players. */
export function playedGame(s: PlayerGameStats): boolean {
  return s.present && (s.forfeit ?? 'none') !== 'lost';
}
