import 'package:infinite_sports_flutter/model/event.dart';

/// Categories events can belong to. Shared string keys with the manager
/// app's event form — keep the two lists identical.
const List<String> kEventCategories = [
  'Futsal',
  'Basketball',
  'Flag Football',
  'Soccer',
  'Volleyball',
  'Pickleball',
  'Tournaments',
  'Community',
];

/// Uncategorized (legacy) events are treated as Community for filtering.
const String kDefaultCategory = 'Community';

/// One event's presence on the calendar. Legacy events carry their Events
/// list index (EventPage addresses them by index); V2 events carry their id.
class CalendarEntry {
  const CalendarEntry({required this.event, this.legacyIndex, this.v2Id, this.lastDay});

  final Event event;
  final int? legacyIndex;
  final String? v2Id;

  /// The event's final occurrence day; used to grey out fully-past events.
  final DateTime? lastDay;

  String get category => event.category ?? kDefaultCategory;

  /// True once the event is completely over (its last day is before today).
  bool isPastOn(DateTime today) =>
      lastDay != null && lastDay!.isBefore(DateTime(today.year, today.month, today.day));
}

/// Bound on weekly-repeat expansion (~1 year) so a bad Until date can't
/// flood the calendar.
const int _maxExpansionDays = 370;

DateTime _dayOf(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Every calendar day this event occupies:
/// - single date: that day
/// - range: every day from startDate through endDate inclusive
/// - weekly repeat: the block repeated every 7 days, trimmed to repeatUntil
List<DateTime> occurrenceDays(Event event) {
  final startRaw = event.startDate ?? event.eventDateTime;
  if (startRaw == null) return const [];
  final start = _dayOf(startRaw);
  var end = event.endDate != null ? _dayOf(event.endDate!) : start;
  if (end.isBefore(start)) end = start;
  final blockLength = end.difference(start).inDays;

  final days = <DateTime>[];
  final isWeekly = event.repeatFreq == 'weekly' && event.repeatUntil != null;
  // The base block always shows in full; the until date bounds repeats.
  var until = isWeekly ? _dayOf(event.repeatUntil!) : end;
  if (until.isBefore(end)) until = end;
  final cap = start.add(const Duration(days: _maxExpansionDays));

  var blockStart = start;
  do {
    for (var i = 0; i <= blockLength; i++) {
      final day = blockStart.add(Duration(days: i));
      if (day.isAfter(until)) break;
      days.add(day);
    }
    if (!isWeekly) break;
    blockStart = blockStart.add(const Duration(days: 7));
  } while (!blockStart.isAfter(until) && blockStart.isBefore(cap));

  return days;
}

/// Events happening today or later, soonest first, keyed by their original
/// index in the Events list (EventPage addresses events by list index).
List<MapEntry<int, Event>> upcomingEvents(List<Event> events, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final result = <MapEntry<int, Event>>[];
  for (var i = 0; i < events.length; i++) {
    final when = events[i].eventDateTime;
    if (when == null || when.isBefore(today)) continue;
    result.add(MapEntry(i, events[i]));
  }
  result.sort((a, b) => a.value.eventDateTime!.compareTo(b.value.eventDateTime!));
  return result;
}

/// Calendar entries grouped by day (midnight-normalized), with range and
/// weekly-repeat events expanded onto every day they cover. Events from the
/// legacy list get their index; V2 events (event.id != null) get their id.
Map<DateTime, List<CalendarEntry>> eventsByDay(List<Event> events) {
  final result = <DateTime, List<CalendarEntry>>{};
  var counter = 0;
  for (final event in events) {
    final isV2 = event.id != null;
    final days = occurrenceDays(event);
    // Merged lists carry the true legacy index on the event; plain
    // getEvents() lists are sequential so the counter matches.
    final entry = CalendarEntry(
      event: event,
      legacyIndex: isV2 ? null : (event.legacyIndex ?? counter),
      v2Id: event.id,
      lastDay: days.isEmpty ? null : days.last,
    );
    if (!isV2) counter++;
    for (final day in days) {
      result.putIfAbsent(day, () => []).add(entry);
    }
  }
  return result;
}

/// Keeps only entries in the selected categories. Empty selection = show
/// everything. Days left with no entries are dropped entirely (no dot).
Map<DateTime, List<CalendarEntry>> filterByCategories(
    Map<DateTime, List<CalendarEntry>> byDay, Set<String> selected) {
  if (selected.isEmpty) return byDay;
  final result = <DateTime, List<CalendarEntry>>{};
  byDay.forEach((day, entries) {
    final kept = entries.where((e) => selected.contains(e.category)).toList();
    if (kept.isNotEmpty) result[day] = kept;
  });
  return result;
}
