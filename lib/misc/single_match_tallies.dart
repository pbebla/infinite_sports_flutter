import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Per-player counters for ONE match (Match Leaders = this game).
class MatchPlayerTally {
  int goals = 0, assists = 0, saves = 0, dpl = 0;
  int byStat(String stat) {
    switch (stat) {
      case 'goals':
        return goals;
      case 'assists':
        return assists;
      case 'saves':
        return saves;
      case 'dpl':
        return dpl;
      default:
        return 0;
    }
  }
}

/// Tallies goals/assists/saves/dpl from a single match's activity, keyed by
/// player name. Mirrors the Spec-1 engine's event mapping (goal/penalty goal
/// -> goals, assist -> assists, save/penalty saved -> saves, dpl -> dpl); all
/// other events are timeline-only. Pure.
Map<String, MatchPlayerTally> singleMatchPlayerTallies(TournamentMatch match) {
  final out = <String, MatchPlayerTally>{};

  void apply(String type, String player) {
    final t = out.putIfAbsent(player, () => MatchPlayerTally());
    switch (type.toLowerCase().trim()) {
      case 'goal':
      case 'penalty goal':
        t.goals++;
        break;
      case 'assist':
        t.assists++;
        break;
      case 'save':
      case 'penalty saved':
        t.saves++;
        break;
      case 'dpl':
        t.dpl++;
        break;
      default:
        break;
    }
  }

  void scan(Map<String, dynamic>? activity) {
    if (activity == null) return;
    void addEntry(dynamic entry) {
      if (entry is Map) {
        entry.forEach((k, v) => apply(k.toString(), v.toString()));
      }
    }
    activity.forEach((_, bucket) {
      if (bucket is List) {
        for (final e in bucket) {
          addEntry(e);
        }
      } else if (bucket is Map) {
        bucket.forEach((_, e) => addEntry(e));
      }
    });
  }

  scan(match.team1Activity);
  scan(match.team2Activity);
  return out;
}
