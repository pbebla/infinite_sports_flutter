// Pure per-sport "background stat" timeline filter (League Experience L6).
// NO Flutter/Firebase imports — unit-tested directly.

/// True when [activityType] must NOT appear as its own row on the fan match
/// timeline. [sportKey] is null for tournament matches.
///
/// Two groups, both still captured and counted everywhere else (box score,
/// player stats, Match Leaders, fantasy read counters/tallies, never the
/// timeline):
///  - Saves and defense plays (`Save`/`DPL` league, `save`/`dpl` tournament),
///    every sport, league and tournament: they made the timeline very long.
///    Penalty saves (`PenSaved` / `penalty saved`) are NOT hidden.
///  - Basketball `Miss` (background stat feeding shot%).
/// Flag football's hidden set is otherwise empty (QBInc etc. render with their
/// own icons). Case-insensitive.
bool isHiddenTimelineActivity(String? sportKey, String activityType) {
  final t = activityType.toLowerCase().trim();
  if (t == 'save' || t == 'dpl') return true;
  return sportKey == 'Basketball' && t == 'miss';
}
