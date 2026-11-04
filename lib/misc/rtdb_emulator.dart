import 'package:firebase_database/firebase_database.dart';

/// Demo switch (owner decision S3): a build made with
/// `--dart-define=RTDB_EMULATOR=1` reads and writes the LOCAL Realtime
/// Database emulator on the development machine instead of the live
/// database, so live fantasy points can be shown moving without touching
/// real data. Sign-in stays on the real project.
///
/// The normal build has no define, so this is `false` at compile time and
/// [connectRtdbEmulatorIfRequested] does nothing at all.
bool get useRtdbEmulator =>
    rtdbEmulatorRequested(const String.fromEnvironment('RTDB_EMULATOR'));

/// Whether the define's raw value asks for the emulator: `1` or `true`.
/// (`bool.fromEnvironment` alone would read the documented `=1` as false.)
bool rtdbEmulatorRequested(String define) => define == '1' || define == 'true';

/// The development machine as seen from the Android emulator.
const String rtdbEmulatorHost = '10.0.2.2';

/// The database emulator's port (`firebase.json` → emulators.database).
const int rtdbEmulatorPort = 9000;

/// Points [db] at the local database emulator when the demo define is set.
/// Must run right after `Firebase.initializeApp` and before any database
/// use. [enabled] exists for tests; the app passes nothing.
void connectRtdbEmulatorIfRequested(FirebaseDatabase db, {bool? enabled}) {
  if (!(enabled ?? useRtdbEmulator)) return;
  db.useDatabaseEmulator(rtdbEmulatorHost, rtdbEmulatorPort);
}
