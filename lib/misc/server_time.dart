import 'package:firebase_database/firebase_database.dart';

/// Offset (ms) to add to the device clock to approximate Firebase server time.
/// Live match clocks store StartedAt as a SERVER timestamp, so elapsed time must
/// be measured against server-aligned "now", not the raw device clock.
int _serverTimeOffsetMs = 0;

/// Server-aligned current time in ms. Falls back to the device clock (offset 0)
/// until the offset listener delivers its first value.
int serverNowMs() => DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

/// Start listening to `.info/serverTimeOffset`. Call once at app startup after
/// Firebase is initialized. Safe to call before any clock is shown.
void initServerTimeOffset() {
  FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen((event) {
    final v = event.snapshot.value;
    if (v is int) {
      _serverTimeOffsetMs = v;
    } else if (v is num) {
      _serverTimeOffsetMs = v.toInt();
    }
  }, onError: (_) {});
}
