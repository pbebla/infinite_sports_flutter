// Shared parsing for one timeline activity leaf (P2.1) — pure Dart, no
// Flutter/Firebase imports, so models and services on both sides of the
// app (and, later, the fan repo) can use it.
//
// A leaf is `{eventType: player}` plus optional METADATA keys that start
// with '_' — today that is the `_t` insertion stamp (epoch ms) that
// TournamentService.appendMatchActivity and GameService.addActivity write
// so same-minute events from different teams can be ordered in true
// record order. Firebase gives NO key-order guarantee inside a map, so
// `entry.keys.first` on a stamped leaf may return `_t` instead of the
// event type. Every leaf parser must go through these helpers instead.

/// True for reserved metadata keys (underscore-prefixed, e.g. `_t`) —
/// never event types.
bool isActivityMetadataKey(Object? key) => key.toString().startsWith('_');

/// The event `{type: player}` of one leaf, skipping metadata keys. null
/// when the leaf holds no event (empty or metadata-only).
MapEntry<String, Object?>? activityEventOf(Map entry) {
  for (final e in entry.entries) {
    final key = e.key.toString();
    if (isActivityMetadataKey(key)) continue;
    return MapEntry(key, e.value);
  }
  return null;
}

/// The event type of one leaf, or null when the leaf holds no event.
String? activityTypeOf(Map entry) => activityEventOf(entry)?.key;

/// True when the leaf's event is exactly [activityType] for [player]
/// (the match rule GameService.removeLastActivity undoes by).
bool activityEventMatches(Map entry, String activityType, String player) {
  final event = activityEventOf(entry);
  return event != null &&
      event.key == activityType &&
      event.value.toString() == player;
}
