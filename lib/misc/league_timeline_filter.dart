// Pure per-sport "background stat" timeline filter (League Experience L6).
// NO Flutter/Firebase imports — unit-tested directly.

/// True when [activityType] is a BACKGROUND stat for [sportKey] that is
/// captured (and undoable, and feeds derived stats like basketball shot%)
/// but must NOT appear as its own row on the fan match timeline.
///
/// Per-sport, extensible: basketball hides misses. Flag football's hidden
/// set is now EMPTY (L6.2 Task 6): QBInc (QB incompletion) used to be
/// hidden here but now renders on the timeline with its own icon
/// (stat_icon.dart), same as RECMiss/PAT1Miss/TwoPTMiss before it (L6.1) —
/// RECMiss additionally feeds the Catch % derived stat. Every other sport
/// (futsal, soccer/tournament) hides nothing. Case-insensitive.
bool isHiddenLeagueTimelineActivity(String sportKey, String activityType) {
  final t = activityType.toLowerCase().trim();
  switch (sportKey) {
    case 'Basketball':
      return t == 'miss';
    default:
      return false;
  }
}
