// Pure per-sport "background stat" timeline filter (League Experience L6).
// NO Flutter/Firebase imports — unit-tested directly.

/// True when [activityType] is a BACKGROUND stat for [sportKey] that is
/// captured (and undoable, and feeds derived stats like basketball shot%)
/// but must NOT appear as its own row on the fan match timeline.
///
/// Per-sport, extensible: basketball hides misses; flag football hides only
/// QBInc (a QB incompletion — no owner-facing icon/value). RECMiss/
/// PAT1Miss/TwoPTMiss (L6.1) now render on the timeline with their own
/// icons (stat_icon.dart); RECMiss additionally feeds the Catch % derived
/// stat. Every other sport (futsal, soccer/tournament) hides nothing.
/// Case-insensitive.
bool isHiddenLeagueTimelineActivity(String sportKey, String activityType) {
  final t = activityType.toLowerCase().trim();
  switch (sportKey) {
    case 'Basketball':
      return t == 'miss';
    case 'Flag Football':
      return t == 'qbinc';
    default:
      return false;
  }
}
