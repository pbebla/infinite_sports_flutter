import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Receiver Catch % = REC / (REC + RECMiss), as a rounded whole-number
/// percent (0-100). Pure — reused by the season Player Stats tab
/// (league_adapters.dart), the player profile career stats, and the Match
/// Leaders category below.
///
/// Returns null — "no data", never a misleading 0% — when there is nothing
/// to compute from (zero targets) OR when [minTargets] is set and the
/// sample is too small to trust as a LEADER: callers that show this as a
/// competitive leaderboard entry (season category, Match Leaders) pass
/// [minTargets] (e.g. 3) so a tiny sample like 1/1 can't top the board. The
/// player's own profile page shows their real rate regardless of sample
/// size, so it leaves [minTargets] at the default (0 — only the literal
/// 0-target case is "no data").
int? catchPercentage(int receptions, int recMisses, {int minTargets = 0}) {
  final targets = receptions + recMisses;
  if (targets == 0 || targets < minTargets) return null;
  return ((receptions / targets) * 100).round();
}

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
      // L6.1 Task 3: Catch % for this match, gated to >=3 targets so a
      // tiny sample (e.g. 1/1) can't top Match Leaders. Below the gate (or
      // no targets at all) returns 0, which the Match Leaders "> 0" filter
      // treats the same as "no data".
      case 'catchPercentage':
        return catchPercentage(
              counts['receptions'] ?? 0,
              counts['recMisses'] ?? 0,
              minTargets: 3,
            ) ??
            0;
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
    // Cards + fouls (Box Score): both the league spellings (Yellow/Red/
    // SecondYellow/Foul) and the tournament ones (yellow card/...) land
    // here. SecondYellow counts as a red, never a first yellow — the
    // stats-engine convention (statKeys ['SecondYellow', 'Red']).
    case 'foul':
      t.counts['fouls'] = (t.counts['fouls'] ?? 0) + 1;
      break;
    case 'yellow':
    case 'yellow card':
      t.counts['yellowCards'] = (t.counts['yellowCards'] ?? 0) + 1;
      break;
    case 'red':
    case 'red card':
    case 'secondyellow':
    case 'second yellow':
      t.counts['redCards'] = (t.counts['redCards'] ?? 0) + 1;
      break;
    // Basketball (P4). Made-shot buckets (Box Score) ride alongside the
    // weighted 'points' Match Leaders keep reading.
    case 'onepointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 1;
      t.counts['freeThrows'] = (t.counts['freeThrows'] ?? 0) + 1;
      break;
    case 'twopointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 2;
      t.counts['twoPointers'] = (t.counts['twoPointers'] ?? 0) + 1;
      break;
    case 'threepointer':
      t.counts['points'] = (t.counts['points'] ?? 0) + 3;
      t.counts['threePointers'] = (t.counts['threePointers'] ?? 0) + 1;
      break;
    case 'turnover':
      t.counts['turnovers'] = (t.counts['turnovers'] ?? 0) + 1;
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
    case 'recmiss': // L6.1 Task 3 — feeds Catch %, no timeline-count row.
      t.counts['recMisses'] = (t.counts['recMisses'] ?? 0) + 1;
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
/// An optional 'suffix' renders after the value ('%' for Catch %).
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
        // L6.1: derived from REC/RECMiss with a >=3-target gate inside
        // MatchPlayerTally.byStat, so a 1/1 game can't top the board.
        {'label': 'Catch %', 'stat': 'catchPercentage', 'suffix': '%'},
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
