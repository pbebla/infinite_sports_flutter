import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// A single player's count for one stat on the share card.
class LeaderEntry {
  final String name;
  final int count;
  const LeaderEntry(this.name, this.count);
}

/// Top [n] players for [stat] ('goals'|'assists'|'saves'|'dpl') on ONE team's
/// side of [match]. [team1] true -> team1Activity, else team2Activity.
/// Sorted by count descending, then name ascending. Zero-count players excluded.
/// Pure.
List<LeaderEntry> topNForStat(
  TournamentMatch match,
  bool team1,
  String stat, {
  int n = 2,
}) {
  final activity = team1 ? match.team1Activity : match.team2Activity;
  final tallies = playerTalliesForActivity(activity);
  final entries = <LeaderEntry>[
    for (final e in tallies.entries)
      if (e.value.byStat(stat) > 0) LeaderEntry(e.key, e.value.byStat(stat))
  ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.name.compareTo(b.name);
    });
  return entries.take(n).toList();
}
