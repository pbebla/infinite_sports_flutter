import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// League sports that follow the "Current League" shape (a `<Sport> Season`
/// pointer + `<Sport>/<Season>/Date` node — see utility.dart getCurrentSport/
/// getCurrentSeason). No single authoritative list of these exists elsewhere
/// in the codebase yet (AFC San Jose/Soccer use a different Seasons-map
/// shape and are intentionally excluded here); defined once here so the
/// calendar can show every league sport's current season, not just whichever
/// one happens to be "Current League" today.
const List<String> kLeagueSports = ['Futsal', 'Basketball', 'Flag Football'];

/// League and tournament match days for the calendar ("everything on the
/// calendar"). Pure parsers below are unit-tested; the watch* wrappers make
/// them live.

/// Sanity cap on the StartDate/EndDate fallback below so a bad or
/// open-ended EndDate can't flood the calendar with entries.
const int _maxTournamentFallbackDays = 14;

/// Distinct tournament match days, one entry per (tournament, day). The
/// whole tournament keeps its accent color until its final day has passed.
/// [tournamentsNode] is the raw /Tournaments map.
///
/// A brand-new tournament has no dated matches yet (bracket not seeded, or
/// the Matches node is absent entirely) — it would otherwise be invisible
/// on the calendar from creation until its first match gets a date. When no
/// dated matches are found, this falls back to the tournament's own header
/// StartDate/EndDate fields (parsed with [parseDatabaseDate]) and adds every
/// day in that inclusive range, capped at [_maxTournamentFallbackDays] days.
/// If only StartDate parses, just that one day is used. Tournaments that DO
/// have dated matches never consult StartDate/EndDate (no double counting).
Map<DateTime, List<CalendarEntry>> tournamentDaysFrom(dynamic tournamentsNode) {
  final result = <DateTime, List<CalendarEntry>>{};
  if (tournamentsNode is! Map) return result;
  tournamentsNode.forEach((tid, tournament) {
    if (tid.toString() == 'Current Tournament') return;
    if (tournament is! Map) return;
    final name = tournament['Name']?.toString() ?? tid.toString();
    // Same default as Tournament.fromFirebase — carried so the calendar's
    // sport filter (Basketball/Futsal/...) can pick this entry up alongside
    // its category, which stays the dedicated 'Tournaments' bucket below.
    final sport =
        firstNonNull(tournament, ['Sport', 'sport'])?.toString() ?? 'Soccer';
    final matches = tournament['Matches'];

    final days = <DateTime>{};
    if (matches is Map) {
      matches.forEach((_, match) {
        if (match is! Map) return;
        // Match records use 'Date' or 'date' depending on era (see
        // TournamentMatch.fromFirebase).
        final raw = match['Date'] ?? match['date'];
        final parsed = parseDatabaseDate(raw?.toString() ?? '');
        if (parsed == null) return;
        days.add(DateTime(parsed.year, parsed.month, parsed.day));
      });
    }

    if (days.isEmpty) {
      final startRaw =
          firstNonNull(tournament, ['StartDate', 'startDate'])?.toString();
      final start =
          startRaw == null ? null : parseDatabaseDate(startRaw);
      if (start == null) return; // no dated matches AND no usable header date
      final startDay = DateTime(start.year, start.month, start.day);

      final endRaw =
          firstNonNull(tournament, ['EndDate', 'endDate'])?.toString();
      final endParsed = endRaw == null ? null : parseDatabaseDate(endRaw);
      var endDay = (endParsed == null || endParsed.isBefore(start))
          ? startDay
          : DateTime(endParsed.year, endParsed.month, endParsed.day);
      final cappedEnd =
          startDay.add(const Duration(days: _maxTournamentFallbackDays - 1));
      if (endDay.isAfter(cappedEnd)) endDay = cappedEnd;

      for (var d = startDay; !d.isAfter(endDay); d = d.add(const Duration(days: 1))) {
        days.add(d);
      }
    }
    if (days.isEmpty) return;
    final lastDay = days.reduce((a, b) => a.isAfter(b) ? a : b);

    for (final day in days) {
      result.putIfAbsent(day, () => []).add(CalendarEntry(
            kind: CalendarKind.tournament,
            title: name,
            categoryOverride: 'Tournaments',
            tournamentId: tid.toString(),
            sport: sport,
            lastDay: lastDay,
          ));
    }
  });
  return result;
}

/// Match days of the current league season. [dateNodeValue] is the raw
/// <Sport>/<Season>/Date node (map keyed by MMDDYYYY). Each day is its own
/// entry and greys out individually once it has passed.
Map<DateTime, List<CalendarEntry>> leagueDaysFrom(
    String sport, String season, dynamic dateNodeValue) {
  final result = <DateTime, List<CalendarEntry>>{};
  if (dateNodeValue is! Map) return result;
  // League days file under their sport's category chip when it exists
  // (Futsal, Basketball, Flag Football...), otherwise Community.
  final category =
      kEventCategories.contains(sport) ? sport : kDefaultCategory;
  dateNodeValue.forEach((key, _) {
    final parsed = parseDatabaseDate(key.toString());
    if (parsed == null) return;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    result.putIfAbsent(day, () => []).add(CalendarEntry(
          kind: CalendarKind.league,
          title: '$sport League',
          categoryOverride: category,
          sport: sport,
          season: season,
          lastDay: day,
        ));
  });
  return result;
}

/// Live tournament days across all tournaments.
Stream<Map<DateTime, List<CalendarEntry>>> watchTournamentDays() {
  return FirebaseDatabase.instance
      .ref('Tournaments')
      .onValue
      .map((e) => tournamentDaysFrom(e.snapshot.value));
}

/// Live match days across EVERY league sport's current season
/// ([kLeagueSports]), merged into one map. Each sport's `<Sport> Season`
/// pointer is read once at subscribe time (same as the old single-sport
/// version), then its `<Sport>/<Season>/Date` node is streamed live; the
/// per-sport maps are merged (via [mergeDayMaps]) and re-emitted whenever
/// any one of them changes. Follows the same manual stream-merge pattern as
/// [watchAllEvents] in event_repo.dart.
Stream<Map<DateTime, List<CalendarEntry>>> watchLeagueDays() {
  final controller = StreamController<Map<DateTime, List<CalendarEntry>>>();
  final perSport = <String, Map<DateTime, List<CalendarEntry>>>{};
  final subs = <StreamSubscription>[];
  var cancelled = false;
  var emitted = false;

  void emit() {
    emitted = true;
    if (!controller.isClosed) controller.add(mergeDayMaps(perSport.values));
  }

  Future<void> watchSport(String sport) async {
    String season;
    try {
      season = await getCurrentSeason(sport);
    } catch (_) {
      return;
    }
    if (cancelled) return;
    subs.add(FirebaseDatabase.instance
        .ref('$sport/$season/Date')
        .onValue
        .map((e) => leagueDaysFrom(sport, season, e.snapshot.value))
        .listen((byDay) {
      perSport[sport] = byDay;
      emit();
    }, onError: (_) {
      if (!emitted) emit();
    }));
  }

  for (final sport in kLeagueSports) {
    watchSport(sport);
  }

  controller.onCancel = () {
    cancelled = true;
    for (final s in subs) {
      s.cancel();
    }
  };
  return controller.stream;
}

/// Overlays several day-maps into one (values concatenated per day).
Map<DateTime, List<CalendarEntry>> mergeDayMaps(
    Iterable<Map<DateTime, List<CalendarEntry>>> maps) {
  final result = <DateTime, List<CalendarEntry>>{};
  for (final map in maps) {
    map.forEach((day, entries) {
      result.putIfAbsent(day, () => []).addAll(entries);
    });
  }
  return result;
}
