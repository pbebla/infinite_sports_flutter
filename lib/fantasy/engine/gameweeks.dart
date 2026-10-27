import 'fantasy_config.dart';
import 'league_time.dart';

enum GameweekStatus { upcoming, open, locked }

class Gameweek {
  const Gameweek({
    required this.number,
    required this.date,
    required this.lockUtc,
    required this.opensUtc,
  });
  final int number;
  final String date; // MMDDYYYY
  final DateTime lockUtc;
  final DateTime? opensUtc; // null = open from launch (gw1)

  GameweekStatus statusAt(DateTime nowUtc) {
    if (opensUtc != null && nowUtc.isBefore(opensUtc!)) {
      return GameweekStatus.upcoming;
    }
    return nowUtc.isBefore(lockUtc)
        ? GameweekStatus.open
        : GameweekStatus.locked;
  }
}

List<Gameweek> deriveGameweeks(List<String> matchDates, FantasyConfig cfg) {
  final sorted = [...matchDates]
    ..sort((a, b) => parseDbDate(a).compareTo(parseDbDate(b)));
  final out = <Gameweek>[];
  for (var i = 0; i < sorted.length; i++) {
    DateTime? opens;
    if (i > 0) {
      final prev = parseDbDate(sorted[i - 1]).add(const Duration(days: 1));
      final mm = prev.month.toString().padLeft(2, '0');
      final dd = prev.day.toString().padLeft(2, '0');
      opens = lockInstantUtc('$mm$dd${prev.year}', hour: 0);
    }
    out.add(Gameweek(
      number: i + 1,
      date: sorted[i],
      lockUtc: lockInstantUtc(sorted[i], hour: cfg.lockHour),
      opensUtc: opens,
    ));
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
