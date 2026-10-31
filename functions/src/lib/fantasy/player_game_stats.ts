// One player's raw stats in one real game — the engine's only input shape.
// `present` comes from the attendance step; `teamConceded` from the final
// score; `forfeit` from the game's `forfeitedBy` marker; `inGoal` from his
// saves or the game's `team{1,2}keepers` marker. Everything else from
// captured activities (always zero on a forfeited game — the mapper ignores
// its events).
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
  /** He played in goal this game (spec §7 stand-in goalkeeper): >=1 Save /
   *  PenSaved recorded, or listed `true` in his side's `team{1,2}keepers`
   *  marker. A fact about the GAME, position-blind — scoring applies it only
   *  to a DEF/ATT (his saves, penalty saves, clean sheet and goals conceded
   *  score at the GK rates for this game); a listed GK is unaffected. */
  inGoal: boolean;
}

/** Mirrors the Dart const constructor's defaults (all zero, present, no
 *  forfeit, not in goal). */
export function playerGameStats(
  partial: Partial<PlayerGameStats> = {},
): PlayerGameStats {
  return {
    goals: 0, assists: 0, saves: 0, penSaved: 0, penMissed: 0,
    ownGoals: 0, yellows: 0, reds: 0, dpl: 0, teamConceded: 0,
    present: true, forfeit: 'none', inGoal: false,
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
