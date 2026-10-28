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

/// The live countdown's Days/Hours/Min/Sec breakdown (P3b feedback Task 4).
/// Zero or negative (the lock has passed — the widget flips to its locked
/// face) clamps to all zeros, never negative digits.
({int days, int hours, int minutes, int seconds}) countdownParts(Duration d) {
  if (d <= Duration.zero) return (days: 0, hours: 0, minutes: 0, seconds: 0);
  return (
    days: d.inDays,
    hours: d.inHours % 24,
    minutes: d.inMinutes % 60,
    seconds: d.inSeconds % 60,
  );
}

/// Two-digit box text for the countdown ("04", "59"; 3-digit days pass
/// through unpadded).
String countdownDigits(int v) => v.toString().padLeft(2, '0');
