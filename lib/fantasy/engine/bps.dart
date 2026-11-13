import 'fantasy_config.dart';
import 'player_game_stats.dart';

/// Raw bonus-points-system score for one player in one game (published
/// formula, spec §7 — shown verbatim on the Rules page). A forfeited game
/// (either side, spec §8a) scores 0 for everyone, so [awardBonus] — which
/// only rewards positive BPS — hands out no bonus from it.
int bpsScore(PlayerGameStats s, FantasyConfig cfg) {
  if (!s.present || s.forfeit != GameForfeit.none) return 0;
  final w = cfg.bps;
  return s.goals * w.goal +
      s.assists * w.assist +
      s.saves * w.save +
      s.dpl * w.dpl +
      (s.teamConceded == 0 ? w.cleanSheet : 0) +
      s.penSaved * w.penSave +
      s.penMissed * w.penMiss +
      s.ownGoals * w.ownGoal +
      s.yellows * w.yellow +
      s.reds * w.red;
}

/// 3/2/1 to the best BPS scores in a match, FPL tie rule: equal scores share
/// the higher bonus and consume the slots below it. Only positive BPS counts.
Map<String, int> awardBonus(Map<String, int> bpsByPlayer) {
  final entries = bpsByPlayer.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  const ladder = [3, 2, 1];
  final out = <String, int>{};
  var slot = 0;
  var i = 0;
  while (i < entries.length && slot < ladder.length) {
    final tied = entries.where((e) => e.value == entries[i].value).toList();
    for (final e in tied) {
      out[e.key] = ladder[slot];
    }
    i += tied.length;
    slot += tied.length;
  }
  return out;
}
