/// One player's raw stats in one real game — the engine's only input shape.
/// `present` comes from the attendance step (P2); `teamConceded` from the
/// final score. Everything else from captured activities.
class PlayerGameStats {
  const PlayerGameStats({
    this.goals = 0, this.assists = 0, this.saves = 0, this.penSaved = 0,
    this.penMissed = 0, this.ownGoals = 0, this.yellows = 0, this.reds = 0,
    this.dpl = 0, this.teamConceded = 0, this.present = true,
  });
  final int goals, assists, saves, penSaved, penMissed, ownGoals;
  final int yellows, reds, dpl, teamConceded;
  final bool present;
}
