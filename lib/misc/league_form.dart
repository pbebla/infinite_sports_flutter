// Pure team results/form helpers over adapted league matches (League
// Experience P2). NO Flutter/Firebase imports.

import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Chronological comparator for MMDDYYYY league date keys.
int compareLeagueDates(String a, String b) {
  String iso(String d) =>
      d.length == 8 ? '${d.substring(4)}${d.substring(0, 4)}' : d;
  return iso(a).compareTo(iso(b));
}

/// [team]'s games (home or away) sorted chronologically — date first, then
/// in-day order.
List<TournamentMatch> teamLeagueMatches(
    String team, List<TournamentMatch> matches) {
  return matches
      .where((m) => m.team1Id == team || m.team2Id == team)
      .toList()
    ..sort((a, b) {
      final byDate = compareLeagueDates(a.date, b.date);
      if (byDate != 0) return byDate;
      return a.bracketPosition.compareTo(b.bracketPosition);
    });
}

/// 'W' / 'D' / 'L' from [team]'s perspective (call on finished games).
String teamResultLetter(String team, TournamentMatch m) {
  final isTeam1 = m.team1Id == team;
  final us = isTeam1 ? m.team1Score : m.team2Score;
  final them = isTeam1 ? m.team2Score : m.team1Score;
  if (us > them) return 'W';
  if (us < them) return 'L';
  return 'D';
}

/// Last [count] results OLDEST → NEWEST (render left to right). Finished
/// games only; friendlies excluded — they never count toward records.
List<String> teamLeagueForm(String team, List<TournamentMatch> matches,
    {int count = 5}) {
  final finished = teamLeagueMatches(team, matches)
      .where((m) =>
          m.matchStatus.isFinished && m.stage.toLowerCase() != 'friendly')
      .toList();
  final tail = finished.length <= count
      ? finished
      : finished.sublist(finished.length - count);
  return [for (final m in tail) teamResultLetter(team, m)];
}
