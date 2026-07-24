import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

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

/// Live match days of the current league season.
Stream<Map<DateTime, List<CalendarEntry>>> watchLeagueDays() async* {
  String sport;
  String season;
  try {
    sport = await getCurrentSport();
    season = await getCurrentSeason(sport);
  } catch (_) {
    yield {};
    return;
  }
  yield* FirebaseDatabase.instance
      .ref('$sport/$season/Date')
      .onValue
      .map((e) => leagueDaysFrom(sport, season, e.snapshot.value));
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
