// Pure per-sport "background stat" timeline filter (League Experience L6).
// NO Flutter/Firebase imports — unit-tested directly.

/// True when [activityType] is a BACKGROUND stat for [sportKey] that is
/// captured (and undoable, and feeds derived stats like basketball shot%)
/// but must NOT appear as its own row on the fan match timeline.
///
/// Per-sport, extensible: basketball hides misses; flag football's negatives
/// (QBInc / RECMiss / PAT1Miss / TwoPTMiss) are added in Group F. Every other
/// sport (futsal, soccer/tournament) hides nothing. Case-insensitive.
bool isHiddenLeagueTimelineActivity(String sportKey, String activityType) {
  final t = activityType.toLowerCase().trim();
  switch (sportKey) {
    case 'Basketball':
      return t == 'miss';
    case 'Flag Football':
      return t == 'qbinc' ||
          t == 'recmiss' ||
          t == 'pat1miss' ||
          t == 'twoptmiss';
    default:
      return false;
  }
}
