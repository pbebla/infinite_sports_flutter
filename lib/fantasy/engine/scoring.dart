import 'fantasy_config.dart';
import 'player_game_stats.dart';

class ScoreLine {
  const ScoreLine(this.label, this.points);
  final String label;
  final int points;
}

class GameScore {
  const GameScore(this.total, this.breakdown);
  final int total;
  final List<ScoreLine> breakdown;
}

class WeekScore {
  const WeekScore(this.total, this.played, this.games);
  final int total;
  final bool played;
  final List<GameScore> games;
}

GameScore scorePlayerGame(
    PlayerGameStats s, FantasyPosition pos, FantasyConfig cfg) {
  if (!s.present) return const GameScore(0, []);
  final r = cfg.scoring[pos]!;
  final lines = <ScoreLine>[
    ScoreLine('Plays', r.plays),
    if (s.goals > 0) ScoreLine('Goals ×${s.goals}', s.goals * r.goal),
    if (s.assists > 0) ScoreLine('Assists ×${s.assists}', s.assists * r.assist),
    if (s.teamConceded == 0 && r.cleanSheet != 0)
      ScoreLine('Clean sheet', r.cleanSheet),
    if (r.per2Saves != 0 && s.saves >= 2)
      ScoreLine('Saves ×${s.saves}', (s.saves ~/ 2) * r.per2Saves),
    if (s.penSaved > 0 && r.penSave != 0)
      ScoreLine('Penalty saves ×${s.penSaved}', s.penSaved * r.penSave),
    if (s.penMissed > 0)
      ScoreLine('Penalty misses ×${s.penMissed}', s.penMissed * r.penMiss),
    if (r.per2Conceded != 0 && s.teamConceded >= 2)
      ScoreLine('Conceded ${s.teamConceded}',
          (s.teamConceded ~/ 2) * r.per2Conceded),
    if (r.dplThreshold != null && s.dpl >= r.dplThreshold!)
      ScoreLine('Defensive plays ${s.dpl}', r.dplBonus),
    if (s.yellows > 0) ScoreLine('Yellow ×${s.yellows}', s.yellows * r.yellow),
    if (s.reds > 0) ScoreLine('Red ×${s.reds}', s.reds * r.red),
    if (s.ownGoals > 0)
      ScoreLine('Own goals ×${s.ownGoals}', s.ownGoals * r.ownGoal),
  ];
  return GameScore(lines.fold(0, (a, l) => a + l.points), lines);
}

WeekScore scorePlayerWeek(
    List<PlayerGameStats> games, FantasyPosition pos, FantasyConfig cfg) {
  final scored = [for (final g in games) scorePlayerGame(g, pos, cfg)];
  return WeekScore(
    scored.fold(0, (a, g) => a + g.total),
    games.any((g) => g.present),
    scored,
  );
}
