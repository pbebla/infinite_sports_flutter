// One player's raw stats in one real game — the engine's only input shape.
// `present` comes from the attendance step; `teamConceded` from the final
// score. Everything else from captured activities.
//
// Faithful port of lib/fantasy/engine/player_game_stats.dart.

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
}

/** Mirrors the Dart const constructor's defaults (all zero, present). */
export function playerGameStats(
  partial: Partial<PlayerGameStats> = {},
): PlayerGameStats {
  return {
    goals: 0, assists: 0, saves: 0, penSaved: 0, penMissed: 0,
    ownGoals: 0, yellows: 0, reds: 0, dpl: 0, teamConceded: 0,
    present: true,
    ...partial,
  };
}
