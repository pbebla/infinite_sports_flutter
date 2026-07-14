import 'package:infinite_sports_flutter/model/event.dart';

/// Events grouped by calendar day (midnight-normalized), keyed by their
/// original index in the Events list (EventPage addresses events by index).
Map<DateTime, List<MapEntry<int, Event>>> eventsByDay(List<Event> events) {
  final result = <DateTime, List<MapEntry<int, Event>>>{};
  for (var i = 0; i < events.length; i++) {
    final when = events[i].eventDateTime;
    if (when == null) continue;
    final day = DateTime(when.year, when.month, when.day);
    result.putIfAbsent(day, () => []).add(MapEntry(i, events[i]));
  }
  return result;
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
