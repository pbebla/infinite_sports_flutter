import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Per-player counters for ONE match (Match Leaders = this game).
class MatchPlayerTally {
  int goals = 0, assists = 0, saves = 0, dpl = 0;

  /// Additive per-sport counters (P4): basketball 'points' (weighted
  /// 1/2/3), 'rebounds', 'steals', 'blocks'; flag football 'touchdowns',
  /// 'passTouchdowns', 'receptions', 'interceptions', 'flagPulls',
  /// 'sacks'. Futsal keeps its named fields.
  final Map<String, int> counts = {};

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
        return counts[stat] ?? 0;
    }
  }
}

void _applyEvent(Map<String, MatchPlayerTally> out, String type, String player) {
  final t = out.putIfAbsent(player, () => MatchPlayerTally());
  switch (type.toLowerCase().trim()) {
    case 'goal':
    case 'penalty goal':
    case 'pengoal': // league PenGoal — one timeline entry, counts as a goal
      t.goals++;
      break;
    case 'assist':
      t.assists++;
      break;
    case 'save':
    case 'penalty saved':
    case 'pensaved': // league PenSaved — keeper credit
      t.saves++;
      break;
    case 'dpl':
      t.dpl++;
      break;
    // Basketball (P4)
    case 'onepointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 1;
      break;
    case 'twopointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 2;
      break;
    case 'threepointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 3;
      break;
    case 'rebound':
      t.counts['rebounds'] = (t.counts['rebounds'] ?? 0) + 1;
      break;
    case 'steal':
      t.counts['steals'] = (t.counts['steals'] ?? 0) + 1;
      break;
    case 'block':
      t.counts['blocks'] = (t.counts['blocks'] ?? 0) + 1;
      break;
    // Flag football (P4)
    case 'receiving td':
    case 'rushing td':
    case 'int td':
      t.counts['touchdowns'] = (t.counts['touchdowns'] ?? 0) + 1;
      break;
    case 'pass td':
      t.counts['passTouchdowns'] =
          (t.counts['passTouchdowns'] ?? 0) + 1;
      break;
    case 'rec':
      t.counts['receptions'] = (t.counts['receptions'] ?? 0) + 1;
      break;
    case 'interception':
      t.counts['interceptions'] =
          (t.counts['interceptions'] ?? 0) + 1;
      break;
    case 'fp':
      t.counts['flagPulls'] = (t.counts['flagPulls'] ?? 0) + 1;
      break;
    case 'sack':
      t.counts['sacks'] = (t.counts['sacks'] ?? 0) + 1;
      break;
    default:
      break;
  }
}

void _scanInto(Map<String, MatchPlayerTally> out, Map<String, dynamic>? activity) {
  if (activity == null) return;
  void addEntry(dynamic entry) {
    if (entry is Map) {
      entry.forEach((k, v) => _applyEvent(out, k.toString(), v.toString()));
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

/// Per-player tallies for a SINGLE team's activity map (keyed by player name).
/// Mirrors the event mapping (goal/penalty goal -> goals, assist -> assists,
/// save/penalty saved -> saves, dpl -> dpl). Pure.
Map<String, MatchPlayerTally> playerTalliesForActivity(
    Map<String, dynamic>? activity) {
  final out = <String, MatchPlayerTally>{};
  _scanInto(out, activity);
  return out;
}

/// Tallies goals/assists/saves/dpl from BOTH teams' activity, keyed by player
/// name. Pure.
Map<String, MatchPlayerTally> singleMatchPlayerTallies(TournamentMatch match) {
  final out = <String, MatchPlayerTally>{};
  _scanInto(out, match.team1Activity);
  _scanInto(out, match.team2Activity);
  return out;
}

/// Player name(s) leading [stat] ('goals'|'assists'|'saves'|'dpl') in this match.
/// Returns the set of names sharing the max (ties included). Empty if nobody has any.
Set<String> matchStatLeaders(TournamentMatch match, String stat) {
  final tallies = singleMatchPlayerTallies(match);
  int max = 0;
  for (final t in tallies.values) {
    final v = t.byStat(stat);
    if (v > max) max = v;
  }
  if (max == 0) return <String>{};
  return {
    for (final e in tallies.entries)
      if (e.value.byStat(stat) == max) e.key
  };
}

/// Match Leaders categories per sport (P4) — the league match page hands
/// these to MatchFactsTab. Futsal = the tab's own tournament default.
List<Map<String, String>> leagueMatchLeaderCategories(String sport) {
  switch (sport) {
    case 'Basketball':
      return const [
        {'label': 'Points', 'stat': 'points'},
        {'label': 'Rebounds', 'stat': 'rebounds'},
        {'label': 'Assists', 'stat': 'assists'},
        {'label': 'Steals', 'stat': 'steals'},
        {'label': 'Blocks', 'stat': 'blocks'},
      ];
    case 'Flag Football':
      return const [
        {'label': 'Touchdowns', 'stat': 'touchdowns'},
        {'label': 'Pass TDs', 'stat': 'passTouchdowns'},
        {'label': 'Receptions', 'stat': 'receptions'},
        {'label': 'Interceptions', 'stat': 'interceptions'},
        {'label': 'Flag Pulls', 'stat': 'flagPulls'},
        {'label': 'Sacks', 'stat': 'sacks'},
      ];
    default: // Futsal
      return const [
        {'label': 'Goals', 'stat': 'goals'},
        {'label': 'Assists', 'stat': 'assists'},
        {'label': 'Saves', 'stat': 'saves'},
        {'label': 'DPL', 'stat': 'dpl'},
      ];
  }
}
