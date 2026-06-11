/// Pure, dependency-free helpers for working with a tournament's set of match
/// days. Dates are Firebase MMDDYYYY strings (e.g. "05292026"). Kept free of
/// Flutter/Firebase imports (like game_day.dart) so it can be unit-tested in
/// isolation; the parsing mirrors _parseMMDDYYYY in game_day.dart.
DateTime? _parseMMDDYYYY(String value) {
  if (value.length != 8) return null;
  final m = int.tryParse(value.substring(0, 2));
  final d = int.tryParse(value.substring(2, 4));
  final y = int.tryParse(value.substring(4, 8));
  if (m == null || d == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Returns the distinct, valid match-day keys from [dates] in ascending
/// calendar order. Duplicate strings are collapsed and any value that is not a
/// valid 8-char MMDDYYYY date is ignored.
List<String> sortedMatchDays(Iterable<String> dates) {
  final seen = <String>{};
  final valid = <MapEntry<String, DateTime>>[];
  for (final raw in dates) {
    if (seen.contains(raw)) continue;
    final parsed = _parseMMDDYYYY(raw);
    if (parsed == null) continue;
    seen.add(raw);
    valid.add(MapEntry(raw, parsed));
  }
  valid.sort((a, b) => a.value.compareTo(b.value));
  return [for (final e in valid) e.key];
}
