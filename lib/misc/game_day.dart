/// Computes the "current game day" for a competition from its match dates.
///
/// Dates are Firebase MMDDYYYY strings (e.g. "05292026"). This file is kept
/// dependency-free (no Firebase) so it can be unit-tested in isolation; the
/// parsing mirrors parseDatabaseDate in utility.dart.
DateTime? _parseMMDDYYYY(String value) {
  if (value.length != 8) return null;
  final m = int.tryParse(value.substring(0, 2));
  final d = int.tryParse(value.substring(2, 4));
  final y = int.tryParse(value.substring(4, 8));
  if (m == null || d == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Returns the current game-day key (MMDDYYYY) from [dates]:
/// - today, if any date is today;
/// - otherwise the earliest future date;
/// - otherwise null (all dates in the past, or none valid).
///
/// [now] defaults to DateTime.now(); inject it in tests.
String? currentGameDay(Iterable<String> dates, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);

  String? earliestFutureKey;
  DateTime? earliestFutureDate;

  for (final raw in dates) {
    final parsed = _parseMMDDYYYY(raw);
    if (parsed == null) continue;
    final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
    if (dateOnly == today) return raw;
    if (dateOnly.isAfter(today)) {
      if (earliestFutureDate == null || dateOnly.isBefore(earliestFutureDate)) {
        earliestFutureDate = dateOnly;
        earliestFutureKey = raw;
      }
    }
  }
  return earliestFutureKey;
}

/// Default day for the league Fixtures date strip (League Experience P2.1),
/// from [sortedDays] (ascending MMDDYYYY keys, e.g. from sortedMatchDays)
/// and [liveDays] (days that currently have a live game):
/// - a day with a live game wins (the earliest such day);
/// - otherwise today / the earliest future day ([currentGameDay]);
/// - otherwise the LAST day, so finished seasons open on the final round;
/// - null only when [sortedDays] is empty.
///
/// [now] defaults to DateTime.now(); inject it in tests.
String? defaultFixturesDay(
  List<String> sortedDays,
  Set<String> liveDays, {
  DateTime? now,
}) {
  if (sortedDays.isEmpty) return null;
  for (final day in sortedDays) {
    if (liveDays.contains(day)) return day;
  }
  return currentGameDay(sortedDays, now: now) ?? sortedDays.last;
}
