import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/model/event.dart';

/// Parses the legacy Events node keyed by true list index. RTDB hands back a
/// List normally, but a Map with numeric keys once rows have been nulled out
/// (manager deletes), so both shapes are handled.
Map<int, Event> parseLegacyEvents(dynamic value) {
  final result = <int, Event>{};
  void addAt(int index, dynamic row) {
    if (row is! Map) return;
    final event = Event();
    event.address = row["Address"]?.toString() ?? "";
    event.date = row["Date"]?.toString() ?? "";
    event.eventDate = row["EventDate"]?.toString() ?? "";
    event.imageUrl = row["ImageUrl"]?.toString() ?? "";
    event.info = row["Info"]?.toString() ?? "";
    event.location = row["Location"]?.toString() ?? "";
    event.startTime = row["StartTime"]?.toString() ?? "";
    event.endTime = row["EndTime"]?.toString() ?? "";
    event.title = row["Title"]?.toString() ?? "";
    if (row.containsKey("Attendees") && row["Attendees"] is Map) {
      event.attendees = {};
      (row["Attendees"] as Map).forEach((uid, v) {
        event.attendees![uid.toString()] = v.toString();
      });
    }
    try {
      event.format();
    } catch (_) {
      return;
    }
    if (event.imageUrl != null && event.imageUrl!.isEmpty) {
      event.imageSrc = null;
    }
    result[index] = event;
  }

  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      addAt(i, value[i]);
    }
  } else if (value is Map) {
    value.forEach((key, row) {
      final index = int.tryParse(key.toString());
      if (index != null) addAt(index, row);
    });
  }
  return result;
}

/// Merges EventsV2 records with index-keyed legacy events. Legacy rows that
/// are mirrors of a V2 event (index appears as a LegacyIndex) are dropped so
/// the event doesn't show twice; remaining legacy events keep their true
/// index (EventPage addresses them by index).
List<Event> mergeEventsIndexed(
    Map<dynamic, dynamic> v2Records, Map<int, Event> legacy) {
  final events = <Event>[];
  final mirrored = <int>{};

  v2Records.forEach((id, json) {
    if (json is! Map) return;
    final event = Event.fromV2(id.toString(), json);
    if (event == null) return;
    if (event.legacyIndex != null) mirrored.add(event.legacyIndex!);
    events.add(event);
  });

  final indexes = legacy.keys.toList()..sort();
  for (final i in indexes) {
    if (mirrored.contains(i)) continue;
    legacy[i]!.legacyIndex = i;
    events.add(legacy[i]!);
  }
  return events;
}

/// List-based convenience wrapper (legacy indexes = list positions).
List<Event> mergeEvents(Map<dynamic, dynamic> v2Records, List<Event> legacy) {
  return mergeEventsIndexed(
      v2Records, {for (var i = 0; i < legacy.length; i++) i: legacy[i]});
}

/// All events for the calendar: EventsV2 + unmirrored legacy rows.
/// Either source failing alone doesn't take the calendar down.
Future<List<Event>> getAllEvents() async {
  Map<dynamic, dynamic> v2 = {};
  try {
    final snapshot = await FirebaseDatabase.instance.ref('EventsV2').get();
    if (snapshot.value is Map) v2 = snapshot.value as Map;
  } catch (_) {}
  Map<int, Event> legacy = {};
  try {
    final snapshot = await FirebaseDatabase.instance.ref('Events').get();
    legacy = parseLegacyEvents(snapshot.value);
  } catch (_) {}
  return mergeEventsIndexed(v2, legacy);
}

/// Live merged event list: re-emits whenever EventsV2 or the legacy Events
/// node changes, so calendars/lists update without a refresh (with disk
/// persistence on, the first emission arrives near-instantly from cache).
Stream<List<Event>> watchAllEvents() {
  final controller = StreamController<List<Event>>();
  Map<dynamic, dynamic> v2 = {};
  Map<int, Event> legacy = {};
  var emitted = false;

  void emit() {
    emitted = true;
    if (!controller.isClosed) controller.add(mergeEventsIndexed(v2, legacy));
  }

  final subs = <StreamSubscription>[];
  subs.add(FirebaseDatabase.instance.ref('EventsV2').onValue.listen((e) {
    v2 = e.snapshot.value is Map ? e.snapshot.value as Map : {};
    emit();
  }, onError: (_) {
    if (!emitted) emit();
  }));
  subs.add(FirebaseDatabase.instance.ref('Events').onValue.listen((e) {
    legacy = parseLegacyEvents(e.snapshot.value);
    emit();
  }, onError: (_) {
    if (!emitted) emit();
  }));
  controller.onCancel = () {
    for (final s in subs) {
      s.cancel();
    }
  };
  return controller.stream;
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

/// Live single event — V2 by id, or a legacy row by index. Emits null when
/// the record is missing/unparseable.
Stream<Event?> watchEvent({String? v2Id, int? legacyIndex}) {
  if (v2Id != null) {
    return FirebaseDatabase.instance.ref('EventsV2/$v2Id').onValue.map((e) {
      if (e.snapshot.value is! Map) return null;
      return Event.fromV2(v2Id, e.snapshot.value as Map);
    });
  }
  return FirebaseDatabase.instance
      .ref('Events/$legacyIndex')
      .onValue
      .map((e) => parseLegacyEvents({legacyIndex.toString(): e.snapshot.value})[legacyIndex]);
}
