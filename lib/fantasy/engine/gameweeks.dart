import 'fantasy_config.dart';
import 'league_time.dart';

enum GameweekStatus { upcoming, open, locked }

class Gameweek {
  const Gameweek({
    required this.number,
    required this.date,
    required this.lockUtc,
    required this.opensUtc,
    this.frozen = false,
  });
  final int number;
  final String date; // MMDDYYYY
  final DateTime lockUtc;
  final DateTime? opensUtc; // null = open from launch (gw1)

  /// True for a week taken from the stored [LockedWeek] ledger: its date and
  /// lock instant no longer follow the match calendar or the config.
  final bool frozen;

  GameweekStatus statusAt(DateTime nowUtc) {
    if (opensUtc != null && nowUtc.isBefore(opensUtc!)) {
      return GameweekStatus.upcoming;
    }
    return nowUtc.isBefore(lockUtc)
        ? GameweekStatus.open
        : GameweekStatus.locked;
  }
}

/// A gameweek the server has already locked (`LockedWeeks/<n>`): its number,
/// match date and lock instant are frozen so a later schedule edit can never
/// renumber or re-time history. [scored] marks a week whose points are final.
class LockedWeek {
  const LockedWeek({
    required this.date,
    required this.lockUtc,
    this.scored = false,
  });
  final String date; // MMDDYYYY
  final DateTime lockUtc;
  final bool scored;

  @override
  bool operator ==(Object other) =>
      other is LockedWeek &&
      other.date == date &&
      other.lockUtc == lockUtc &&
      other.scored == scored;

  @override
  int get hashCode => Object.hash(date, lockUtc, scored);

  @override
  String toString() =>
      'LockedWeek($date, ${lockUtc.toIso8601String()}, scored: $scored)';
}

/// Everything [deriveGameweeks] needs beyond the match dates and the config.
/// All parts are optional: the empty schedule is the legacy "one gameweek per
/// match date, locking at cfg.lockHour" behaviour.
class GameweekSchedule {
  const GameweekSchedule({
    this.lockedWeeks = const {},
    this.skippedDates = const {},
    this.deadlineOverrides = const {},
    this.firstKickoffUtc = const {},
    this.minutesBeforeKickoff = 60,
  });

  /// Frozen weeks by gameweek number; only the unbroken run 1..L counts.
  final Map<int, LockedWeek> lockedWeeks;

  /// Match dates (MMDDYYYY) that are not a gameweek.
  final Set<String> skippedDates;

  /// Per-date lock instants that beat the automatic deadline.
  final Map<String, DateTime> deadlineOverrides;

  /// The earliest kickoff of each match date (MMDDYYYY).
  final Map<String, DateTime> firstKickoffUtc;

  /// The automatic deadline is this many minutes before the first kickoff
  /// when that is earlier than the config's lock hour.
  final int minutesBeforeKickoff;
}

/// The owner-editable part of a [GameweekSchedule] (`Config/SkippedDates`,
/// `Config/Deadlines`, `Config/deadlineMinutesBeforeKickoff`), with value
/// equality so streams can skip no-op re-emits.
class ScheduleOverrides {
  const ScheduleOverrides({
    this.skippedDates = const {},
    this.deadlineOverrides = const {},
    this.minutesBeforeKickoff = 60,
  });
  final Set<String> skippedDates;
  final Map<String, DateTime> deadlineOverrides;
  final int minutesBeforeKickoff;

  @override
  bool operator ==(Object other) =>
      other is ScheduleOverrides &&
      other.minutesBeforeKickoff == minutesBeforeKickoff &&
      _sameSet(other.skippedDates, skippedDates) &&
      _sameMap(other.deadlineOverrides, deadlineOverrides);

  @override
  int get hashCode => Object.hash(
        minutesBeforeKickoff,
        Object.hashAllUnordered(skippedDates),
        Object.hashAllUnordered(
            deadlineOverrides.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'ScheduleOverrides(skipped: $skippedDates, '
      'deadlines: $deadlineOverrides, minutes: $minutesBeforeKickoff)';
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _sameMap(Map<String, DateTime> a, Map<String, DateTime> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final other = b[e.key];
    if (other == null || other != e.value) return false;
  }
  return true;
}

/// [S2] The legacy derived kickoff 'HH:00' of a game that stores no `Time`:
/// the season Start Time + the game's index, read as PM (h = start + index;
/// if h < 12 then h += 12; if h > 23 then h = 23). No Start Time
/// ([startHour] <= 0) means no derived kickoff (null). Same semantics as the
/// Manager's derivedStoredTime.
String? legacyKickoffHHmm(int startHour, int index) {
  if (startHour <= 0) return null;
  var h = startHour + index;
  if (h < 12) h += 12;
  if (h > 23) h = 23;
  return '${h.toString().padLeft(2, '0')}:00';
}

/// League midnight after the match day [prevDate] (MMDDYYYY): when the next
/// gameweek opens. Null for the first gameweek.
DateTime? _opensAfter(String? prevDate) {
  if (prevDate == null) return null;
  final next = parseDbDate(prevDate).add(const Duration(days: 1));
  final mm = next.month.toString().padLeft(2, '0');
  final dd = next.day.toString().padLeft(2, '0');
  return lockInstantUtc('$mm$dd${next.year}', hour: 0);
}

/// The season's gameweeks, numbered from 1.
///
/// 1. Frozen weeks: [GameweekSchedule.lockedWeeks] entries 1..L while every
///    key 1..L is present (the first gap ends the run; later entries are
///    ignored). They keep their stored date and lock instant.
/// 2. Later weeks: the distinct [matchDates], sorted by calendar date, that
///    are not skipped and fall strictly after the last frozen week's date
///    (a past day added after the fact can never become a gameweek).
///    Their lock is the per-date override if any, else the config lock hour
///    pulled earlier to [GameweekSchedule.minutesBeforeKickoff] before the
///    day's first kickoff when that comes sooner.
/// 3. Every week but the first opens at league midnight after the PREVIOUS
///    week's date, frozen or not.
List<Gameweek> deriveGameweeks(List<String> matchDates, FantasyConfig cfg,
    [GameweekSchedule schedule = const GameweekSchedule()]) {
  final out = <Gameweek>[];
  String? prevDate;

  while (true) {
    final w = schedule.lockedWeeks[out.length + 1];
    if (w == null) break;
    out.add(Gameweek(
      number: out.length + 1,
      date: w.date,
      lockUtc: w.lockUtc,
      opensUtc: _opensAfter(prevDate),
      frozen: true,
    ));
    prevDate = w.date;
  }

  final lastFrozen = prevDate == null ? null : parseDbDate(prevDate);
  final future = [
    for (final d in {...matchDates})
      if (!schedule.skippedDates.contains(d) &&
          (lastFrozen == null || parseDbDate(d).isAfter(lastFrozen)))
        d,
  ]..sort((a, b) => parseDbDate(a).compareTo(parseDbDate(b)));

  for (final d in future) {
    var auto = lockInstantUtc(d, hour: cfg.lockHour);
    final kickoff = schedule.firstKickoffUtc[d];
    if (kickoff != null) {
      final beforeKickoff =
          kickoff.subtract(Duration(minutes: schedule.minutesBeforeKickoff));
      if (beforeKickoff.isBefore(auto)) auto = beforeKickoff;
    }
    out.add(Gameweek(
      number: out.length + 1,
      date: d,
      lockUtc: schedule.deadlineOverrides[d] ?? auto,
      opensUtc: _opensAfter(prevDate),
    ));
    prevDate = d;
  }
  return out;
}

/// The gameweek a manager is editing/watching at [nowUtc]: the first one
/// whose lock is still ahead, else the last locked one while its match day
/// is ongoing (lock day), else null (season over).
Gameweek? currentGameweek(List<Gameweek> gws, DateTime nowUtc) {
  for (final g in gws) {
    final dayEnd = g.lockUtc.add(const Duration(hours: 24));
    if (nowUtc.isBefore(dayEnd)) return g;
  }
  return null;
}
