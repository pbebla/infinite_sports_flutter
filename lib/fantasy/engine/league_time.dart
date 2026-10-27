/// League wall-clock → UTC. The league runs on America/Los_Angeles; deadlines
/// are league-local (spec §5), never the phone's timezone.
library;

DateTime parseDbDate(String mmddyyyy) => DateTime.utc(
      int.parse(mmddyyyy.substring(4, 8)),
      int.parse(mmddyyyy.substring(0, 2)),
      int.parse(mmddyyyy.substring(2, 4)),
    );

/// Nth (1-based) given weekday of a month, as a UTC date.
DateTime _nthWeekday(int year, int month, int weekday, int n) {
  var d = DateTime.utc(year, month, 1);
  final first = (weekday - d.weekday + 7) % 7;
  return DateTime.utc(year, month, 1 + first + 7 * (n - 1));
}

/// True if this local-calendar date is inside US daylight saving time
/// (2nd Sunday of March through the day before the 1st Sunday of November).
bool isPacificDst(DateTime localDate) {
  final start = _nthWeekday(localDate.year, 3, DateTime.sunday, 2);
  final end = _nthWeekday(localDate.year, 11, DateTime.sunday, 1);
  final d = DateTime.utc(localDate.year, localDate.month, localDate.day);
  return !d.isBefore(start) && d.isBefore(end);
}

/// UTC instant of [hour]:00 league time on a database date (MMDDYYYY).
DateTime lockInstantUtc(String mmddyyyy, {required int hour}) {
  final d = parseDbDate(mmddyyyy);
  final offset = isPacificDst(d) ? 7 : 8; // PDT -7, PST -8
  return DateTime.utc(d.year, d.month, d.day, hour + offset);
}
