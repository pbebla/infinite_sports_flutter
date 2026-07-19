import 'package:firebase_database/firebase_database.dart';

/// The shared, owner-editable list of categories ("areas of interest").
/// Stored at RTDB `/Categories` as an ordered array of names, managed from the
/// manager app's Categories screen. Drives event categories, calendar filter
/// chips, favorite-sports onboarding, notification settings toggles, and
/// campaign targeting — one list, everywhere.
///
/// When the node is absent (fresh database) both apps fall back to
/// [kDefaultCategories]; the manager seeds the node on first edit.

/// Fallback / seed list. 'Community' must stay present — it's the bucket for
/// uncategorized events (see kDefaultCategory in event_utils).
const List<String> kDefaultCategories = [
  'Futsal',
  'Basketball',
  'Flag Football',
  'Soccer',
  'Volleyball',
  'Pickleball',
  'Tournaments',
  'Community',
];

/// Parses the raw `/Categories` value into a clean ordered name list.
/// Accepts an array (normal) or a map (RTDB may return index-keyed maps).
/// Drops blanks/dupes; returns the defaults when nothing usable is present.
List<String> parseCategories(dynamic value) {
  final names = <String>[];
  void add(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isNotEmpty && !names.contains(s)) names.add(s);
  }

  if (value is List) {
    for (final v in value) {
      add(v);
    }
  } else if (value is Map) {
    final keys = value.keys.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.toString());
        final bi = int.tryParse(b.toString());
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.toString().compareTo(b.toString());
      });
    for (final k in keys) {
      add(value[k]);
    }
  }
  return names.isEmpty ? List<String>.from(kDefaultCategories) : names;
}

/// One-shot read of the category list (falls back to defaults on any error).
Future<List<String>> getCategories() async {
  try {
    final snap = await FirebaseDatabase.instance.ref('Categories').get();
    return parseCategories(snap.value);
  } catch (_) {
    return List<String>.from(kDefaultCategories);
  }
}

/// Live category list — re-emits whenever the owner edits it in the manager.
Stream<List<String>> watchCategories() {
  return FirebaseDatabase.instance
      .ref('Categories')
      .onValue
      .map((e) => parseCategories(e.snapshot.value));
}
