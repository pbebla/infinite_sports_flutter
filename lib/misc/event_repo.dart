import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/event.dart';

/// Merges EventsV2 records with the legacy Events list. Legacy rows that are
/// mirrors of a V2 event (their index appears as a LegacyIndex) are dropped
/// so the event doesn't show twice. Remaining legacy events keep their true
/// list index (EventPage addresses them by index).
List<Event> mergeEvents(Map<dynamic, dynamic> v2Records, List<Event> legacy) {
  final events = <Event>[];
  final mirrored = <int>{};

  v2Records.forEach((id, json) {
    if (json is! Map) return;
    final event = Event.fromV2(id.toString(), json);
    if (event == null) return;
    if (event.legacyIndex != null) mirrored.add(event.legacyIndex!);
    events.add(event);
  });

  for (var i = 0; i < legacy.length; i++) {
    if (mirrored.contains(i)) continue;
    legacy[i].legacyIndex = i;
    events.add(legacy[i]);
  }
  return events;
}

/// All events for the calendar: EventsV2 + unmirrored legacy rows.
/// Either source failing alone doesn't take the calendar down.
Future<List<Event>> getAllEvents() async {
  Map<dynamic, dynamic> v2 = {};
  try {
    final snapshot = await FirebaseDatabase.instance.ref('EventsV2').get();
    if (snapshot.value is Map) v2 = snapshot.value as Map;
  } catch (_) {}
  List<Event> legacy = [];
  try {
    legacy = await getEvents();
  } catch (_) {}
  return mergeEvents(v2, legacy);
}

/// Single V2 event by id (fresh read so attendees are current).
Future<Event?> getEventV2(String id) async {
  try {
    final snapshot = await FirebaseDatabase.instance.ref('EventsV2/$id').get();
    if (snapshot.value is! Map) return null;
    return Event.fromV2(id, snapshot.value as Map);
  } catch (_) {
    return null;
  }
}
