import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

class LeaderboardEntry {
  final String uid;
  final String name;
  final int points;
  final int exact;

  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.points,
    required this.exact,
  });

  factory LeaderboardEntry.fromFirebase(String uid, dynamic raw) {
    final data = (raw is Map) ? raw : const <dynamic, dynamic>{};
    return LeaderboardEntry(
      uid: uid,
      name: firstNonNull(data, ['Name', 'name'])?.toString() ?? 'Player',
      points: parseInt(firstNonNull(data, ['Points', 'points'])),
      exact: parseInt(firstNonNull(data, ['Exact', 'exact'])),
    );
  }
}

/// Sort: points desc, then exact desc, then name asc (stable, case-insensitive).
int compareLeaderboard(LeaderboardEntry a, LeaderboardEntry b) {
  if (a.points != b.points) return b.points.compareTo(a.points);
  if (a.exact != b.exact) return b.exact.compareTo(a.exact);
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
