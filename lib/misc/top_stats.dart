// "Player's 3 strongest stats" helper (League Experience P2.2, owner item:
// squad rows show each player's top-3 stats as icon+value chips).
// Pure Dart — NO Flutter/Firebase imports; unit-tested in
// test/top_stats_test.dart.
//
// Per-sport lists live in FAN-SIDE maps here, the same precedent as the
// leader categories hardcoded in league_tabs/league_player_stats_tab.dart —
// NOT in league_sport_config.dart, which is a byte-pinned twin of the
// Manager file and must not grow fan-only fields. P4 adds the basketball /
// flag-football entries alongside their league configs.

import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// One "strongest stat" slot: the statByName key + the player's value.
typedef TopStat = ({String stat, int value});

/// Ordered candidate stats per sport. The order doubles as the tie-break
/// (stable: earlier wins on equal values) and intentionally leads with the
/// sport's fallback stats. Cards are NOT candidates — a pile of yellows is
/// not a stat a player is "very good at".
const Map<String, List<String>> leagueTopStatCandidates = {
  'Futsal': ['goals', 'assists', 'dpl', 'saves', 'cleanSheets'],
};

/// Per-sport fallback list (owner: Goals, Assists, DPL for futsal): when a
/// player has fewer than 3 non-zero candidate stats, the remaining slots
/// fill from this list in order — zero values included.
const Map<String, List<String>> leagueTopStatFallbacks = {
  'Futsal': ['goals', 'assists', 'dpl'],
};

/// statByName key -> statIconAsset vocabulary for the squad chips, matching
/// the Player Stats tab's icon mapping ('' = no custom asset, the StatIcon
/// neutral fallback renders — same treatment as Clean Sheets there).
String leagueTopStatIconKey(String stat) {
  switch (stat) {
    case 'goals':
      return 'goal';
    case 'assists':
      return 'assist';
    case 'saves':
      return 'save';
    case 'dpl':
      return 'dpl';
    case 'yellowCards':
      return 'yellow';
    case 'redCards':
      return 'red';
    default:
      return '';
  }
}

/// The player's 3 strongest stats for [sport]:
/// - non-zero candidate stats sorted by value descending, ties stable in
///   the sport's candidate order;
/// - when fewer than 3 are non-zero, the remaining slots fill from the
///   sport's fallback list in order (skipping stats already picked),
///   including zero values.
/// Unknown sports use the futsal lists until P4 registers theirs.
List<TopStat> topThreeStats(Map<String, int> stats, String sport) {
  final candidates =
      leagueTopStatCandidates[sport] ?? leagueTopStatCandidates['Futsal']!;
  final fallback =
      leagueTopStatFallbacks[sport] ?? leagueTopStatFallbacks['Futsal']!;

  final order = {
    for (var i = 0; i < candidates.length; i++) candidates[i]: i,
  };
  final top = <TopStat>[
    for (final s in candidates)
      if ((stats[s] ?? 0) > 0) (stat: s, value: stats[s]!),
  ]..sort((a, b) {
      final v = b.value.compareTo(a.value);
      // List.sort is not stable — the candidate index IS the tie-break.
      return v != 0 ? v : order[a.stat]!.compareTo(order[b.stat]!);
    });
  if (top.length > 3) top.removeRange(3, top.length);

  for (final s in fallback) {
    if (top.length >= 3) break;
    if (top.any((t) => t.stat == s)) continue;
    top.add((stat: s, value: stats[s] ?? 0));
  }
  return top;
}

/// Convenience overload: reads the candidate stats off a roster player via
/// [TournamentPlayer.statByName].
List<TopStat> topThreeStatsForPlayer(TournamentPlayer player, String sport) {
  final candidates =
      leagueTopStatCandidates[sport] ?? leagueTopStatCandidates['Futsal']!;
  return topThreeStats(
    {for (final s in candidates) s: player.statByName(s)},
    sport,
  );
}
