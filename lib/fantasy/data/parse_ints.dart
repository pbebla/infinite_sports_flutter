// The ONE tolerant int reader every fantasy parser shares (fix-the-bug-class:
// it used to be three private copies — fantasy_parsers, fantasy_badges,
// player_week_stats). Pure Dart; unit-tested in test/fantasy/parse_ints_test.dart.

/// A number as RTDB may hand it back — an int, a double, or (hand-edited
/// nodes) a numeric string with padding — or null for anything else. A
/// double truncates toward zero; a non-finite one (NaN, infinity) is null,
/// never a throw.
int? tolerantInt(Object? raw) {
  if (raw is num) return raw.isFinite ? raw.toInt() : null;
  return int.tryParse(raw?.toString().trim() ?? '');
}
