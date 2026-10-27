// Fantasy display formatting (P3a Task 1) — pure helpers shared by the hub
// header, Rules tab and (P3b) squad builder. Money is engine tenths
// ($0.1M units); times are LEAGUE time (America/Los_Angeles, spec §5) — the
// engine's league_time offset math, never the phone's timezone.

import 'package:intl/intl.dart';

import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/league_time.dart';

/// 85 → "$8.5M", 500 → "$50.0M".
String formatMoneyTenths(int tenths) =>
    '\$${(tenths / 10).toStringAsFixed(1)}M';

/// League-local lock hour → "3:00 PM" (cfg.lockHour is league wall-clock).
String formatLockHour(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:00 ${hour < 12 ? 'AM' : 'PM'}';
}

/// A gameweek's lock instant as league wall-clock (UTC minus the Pacific
/// offset in force on its match day).
DateTime leagueLocalLock(Gameweek gw) {
  final offset = isPacificDst(parseDbDate(gw.date)) ? 7 : 8;
  return gw.lockUtc.subtract(Duration(hours: offset));
}

/// Absolute deadline text, spec §5's example form: "Sun, Oct 19 · 3:00 PM".
String formatAbsoluteLock(Gameweek gw) {
  final local = leagueLocalLock(gw);
  return '${DateFormat('EEE, MMM d').format(local)} · '
      '${DateFormat('h:mm a').format(local)}';
}

/// Compact countdown: "2d 4h", "3h 12m", "41m", "under a minute". Callers
/// pass a non-negative duration (lock minus now).
String formatCountdown(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d ${d.inHours % 24}h';
}
