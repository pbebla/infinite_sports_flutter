/// How a forfeit touched one player's game (spec §8a, owner Option B).
/// - [none]: a normal game.
/// - [won]: the player's team SHOWED UP (the other team forfeited) — a
///   present player earns ONLY the appearance point; no clean sheet, no
///   stat points, no bonus (the game contributes nothing to BPS).
/// - [lost]: the player's team FORFEITED — 0 points, no goals-conceded
///   penalty, and the player did NOT play (auto-subs and the vice-captain
///   treat him exactly like an absent player).
enum GameForfeit { none, won, lost }

/// One player's raw stats in one real game — the engine's only input shape.
/// `present` comes from the attendance step (P2); `teamConceded` from the
/// final score; `forfeit` from the game's `forfeitedBy` marker; `inGoal`
/// from his saves or the game's `team{1,2}keepers` marker. Everything else
/// from captured activities (always zero on a forfeited game — the mapper
/// ignores its events).
class PlayerGameStats {
  const PlayerGameStats({
    this.goals = 0, this.assists = 0, this.saves = 0, this.penSaved = 0,
    this.penMissed = 0, this.ownGoals = 0, this.yellows = 0, this.reds = 0,
    this.dpl = 0, this.teamConceded = 0, this.present = true,
    this.forfeit = GameForfeit.none, this.inGoal = false,
  });
  final int goals, assists, saves, penSaved, penMissed, ownGoals;
  final int yellows, reds, dpl, teamConceded;
  final bool present;
  final GameForfeit forfeit;

  /// He played in goal this game (spec §7 stand-in goalkeeper): ≥1 Save /
  /// PenSaved recorded, or listed `true` in his side's `team{1,2}keepers`
  /// marker. A fact about the GAME, position-blind — scoring applies it
  /// only to a DEF/ATT (his saves, penalty saves, clean sheet and goals
  /// conceded score at the GK rates for this game); a listed GK is
  /// unaffected.
  final bool inGoal;

  /// Whether the player took part in this game — the week's `played` flag
  /// (auto-subs, the vice-captain armband, the Dream Team). Absent players
  /// did not play, and neither did a forfeiting team's players.
  bool get played => present && forfeit != GameForfeit.lost;
}
