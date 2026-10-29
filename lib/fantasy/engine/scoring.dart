import 'fantasy_config.dart';
import 'player_game_stats.dart';

/// One line of a player's per-game score breakdown. [label] is the display
/// text; [key] is the stable machine key and [count] how many of that source
/// (1 for plays/cleanSheet, otherwise the raw stat count) — the server's
/// PlayerWeekStats sums lines by [key] (functions/src/lib/fantasy/scoring.ts).
class ScoreLine {
  const ScoreLine(this.label, this.points,
      {required this.key, required this.count});
  final String label;
  final int points;

  /// plays | goals | assists | cleanSheet | saves | penSaved | penMissed |
  /// conceded | dpl | yellow | red | ownGoals (the TS `ScoreKey`).
  final String key;
  final int count;
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
  // Absent, or on the team that forfeited (spec §8a): nothing at all — no
  // appearance, no goals-conceded penalty.
  if (!s.played) return const GameScore(0, []);
  final r = cfg.scoring[pos]!;
  // The team that showed up to a forfeit: the appearance point ONLY — no
  // clean sheet, and any stray recorded stats never count.
  if (s.forfeit == GameForfeit.won) {
    return GameScore(
        r.plays, [ScoreLine('Plays', r.plays, key: 'plays', count: 1)]);
  }
  final lines = <ScoreLine>[
    ScoreLine('Plays', r.plays, key: 'plays', count: 1),
    if (s.goals > 0)
      ScoreLine('Goals ×${s.goals}', s.goals * r.goal,
          key: 'goals', count: s.goals),
    if (s.assists > 0)
      ScoreLine('Assists ×${s.assists}', s.assists * r.assist,
          key: 'assists', count: s.assists),
    if (s.teamConceded == 0 && r.cleanSheet != 0)
      ScoreLine('Clean sheet', r.cleanSheet, key: 'cleanSheet', count: 1),
    if (r.per2Saves != 0 && s.saves >= 2)
      ScoreLine('Saves ×${s.saves}', (s.saves ~/ 2) * r.per2Saves,
          key: 'saves', count: s.saves),
    if (s.penSaved > 0 && r.penSave != 0)
      ScoreLine('Penalty saves ×${s.penSaved}', s.penSaved * r.penSave,
          key: 'penSaved', count: s.penSaved),
    if (s.penMissed > 0)
      ScoreLine('Penalty misses ×${s.penMissed}', s.penMissed * r.penMiss,
          key: 'penMissed', count: s.penMissed),
    if (r.per2Conceded != 0 && s.teamConceded >= 2)
      ScoreLine('Conceded ${s.teamConceded}',
          (s.teamConceded ~/ 2) * r.per2Conceded,
          key: 'conceded', count: s.teamConceded),
    if (r.dplThreshold != null && s.dpl >= r.dplThreshold!)
      ScoreLine('Defensive plays ${s.dpl}', r.dplBonus,
          key: 'dpl', count: s.dpl),
    if (s.yellows > 0)
      ScoreLine('Yellow ×${s.yellows}', s.yellows * r.yellow,
          key: 'yellow', count: s.yellows),
    if (s.reds > 0)
      ScoreLine('Red ×${s.reds}', s.reds * r.red, key: 'red', count: s.reds),
    if (s.ownGoals > 0)
      ScoreLine('Own goals ×${s.ownGoals}', s.ownGoals * r.ownGoal,
          key: 'ownGoals', count: s.ownGoals),
  ];
  return GameScore(lines.fold(0, (a, l) => a + l.points), lines);
}

WeekScore scorePlayerWeek(
    List<PlayerGameStats> games, FantasyPosition pos, FantasyConfig cfg) {
  final scored = [for (final g in games) scorePlayerGame(g, pos, cfg)];
  return WeekScore(
    scored.fold(0, (a, g) => a + g.total),
    // A forfeiting team's players did not play (spec §8a) — exactly like
    // absent players for auto-subs and the vice-captain armband.
    games.any((g) => g.played),
    scored,
  );
}
