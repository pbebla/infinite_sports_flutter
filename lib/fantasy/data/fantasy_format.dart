// Fantasy display formatting (P3a Task 1) — pure helpers shared by the hub
// header, Rules tab and (P3b) squad builder. Money is engine tenths
// ($0.1M units); times are LEAGUE time (America/Los_Angeles, spec §5) — the
// Pacific offset in force at the instant, never the phone's timezone.

import 'package:intl/intl.dart';

import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/misc/points_text.dart';

export 'package:infinite_sports_flutter/misc/points_text.dart';

/// 85 → "$8.5M", 500 → "$50.0M".
String formatMoneyTenths(int tenths) =>
    '\$${(tenths / 10).toStringAsFixed(1)}M';

/// A player's form (tenths of a point per game over his last weeks): 250 →
/// "25.0", 67 → "6.7". "—" when he has played no games (null / 0) or the
/// server wrote no form — never a made-up "0.0". The ONE source for the
/// market rows' "6.7 form" line and the profile's Form cell.
String formatFormTenths(int? formTenths, {required int? games}) =>
    (games == null || games == 0 || formTenths == null)
        ? '—'
        : (formTenths / 10).toStringAsFixed(1);

/// Tenths of a point → its number: "8", "2.5", "-0.5" — one decimal only
/// when not whole (a bench player's half points).
String formatPointsTenths(int tenths) =>
    tenths % 10 == 0 ? '${tenths ~/ 10}' : (tenths / 10).toStringAsFixed(1);

/// Tenths of a point with the unit that agrees (pointsUnit): "8 pts",
/// "1 pt", "-1 pt", "2.5 pts", "0 pts".
String pointsTenthsText(int tenths) =>
    '${formatPointsTenths(tenths)} ${pointsUnit(tenths / 10)}';

/// League-local lock hour → "3:00 PM" (cfg.lockHour is league wall-clock).
String formatLockHour(int hour) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:00 ${hour < 12 ? 'AM' : 'PM'}';
}

/// The first Sunday on or after [month]/[day] of [year], as a UTC date.
DateTime _sundayOnOrAfter(int year, int month, int day) {
  var d = DateTime.utc(year, month, day);
  while (d.weekday != DateTime.sunday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// True when Pacific Daylight Time is in force at the UTC INSTANT [utc]: from
/// 02:00 PST (10:00 UTC) on the 2nd Sunday of March to 02:00 PDT (09:00 UTC)
/// on the 1st Sunday of November. An instant — not a calendar date — decides:
/// a deadline the league moves across a clock change must read the wall clock
/// it really is.
bool _isPdtAt(DateTime utc) {
  final u = utc.toUtc();
  final start =
      _sundayOnOrAfter(u.year, 3, 8).add(const Duration(hours: 10));
  final end = _sundayOnOrAfter(u.year, 11, 1).add(const Duration(hours: 9));
  return !u.isBefore(start) && u.isBefore(end);
}

/// A UTC instant as league wall-clock (America/Los_Angeles): a UTC DateTime
/// whose fields read the Pacific time at that instant — format it with
/// DateFormat, never `.toLocal()` (that would be the PHONE's zone).
DateTime leagueWallClock(DateTime utc) =>
    utc.toUtc().subtract(Duration(hours: _isPdtAt(utc) ? 7 : 8));

/// A gameweek's lock instant as league wall-clock. The offset comes from the
/// lock INSTANT itself, never from the gameweek's match date: the league can
/// move a deadline onto another day, across a clock change.
DateTime leagueLocalLock(Gameweek gw) => leagueWallClock(gw.lockUtc);

/// The full English weekday of [utc] in league time ("Monday") — when a week
/// opens is a league-midnight instant, and the weekday it falls on is the
/// league's, not the phone's.
String formatLeagueWeekday(DateTime utc) =>
    DateFormat('EEEE').format(leagueWallClock(utc));

/// The weekday a gameweek opens on ("Monday"): the league day its
/// [Gameweek.opensUtc] belongs to. That instant is "league midnight", which
/// the engine places with the offset of the calendar DATE — on the two
/// clock-change days that is an hour early (23:00 the night before when the
/// clocks spring forward) — so the day is read an hour past it: always the
/// day the week really opens.
String formatOpensWeekday(DateTime opensUtc) =>
    formatLeagueWeekday(opensUtc.add(const Duration(hours: 1)));

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
