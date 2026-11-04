import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/rtdb_emulator.dart';

/// Records every call the switch makes on the database. Any other method
/// (ref, setPersistenceEnabled, ...) throws via [Fake], so "nothing" really
/// means nothing.
class _RecordingDb extends Fake implements FirebaseDatabase {
  final List<String> calls = [];

  @override
  void useDatabaseEmulator(String host, int port,
      {bool automaticHostMapping = true}) {
    calls.add('useDatabaseEmulator($host, $port)');
  }
}

void main() {
  test('the normal build (no RTDB_EMULATOR define) leaves the switch off', () {
    expect(useRtdbEmulator, isFalse);
  });

  test('the define turns the switch on as 1 or true, nothing else', () {
    // `--dart-define=RTDB_EMULATOR=1` is the documented demo command;
    // bool.fromEnvironment alone would read "1" as false.
    expect(rtdbEmulatorRequested('1'), isTrue);
    expect(rtdbEmulatorRequested('true'), isTrue);
    expect(rtdbEmulatorRequested(''), isFalse);
    expect(rtdbEmulatorRequested('0'), isFalse);
    expect(rtdbEmulatorRequested('false'), isFalse);
    expect(rtdbEmulatorRequested('yes'), isFalse);
  });

  test('without the define, the database is not touched at all', () {
    final db = _RecordingDb();
    connectRtdbEmulatorIfRequested(db);
    expect(db.calls, isEmpty);
  });

  test('switched off explicitly, the database is not touched at all', () {
    final db = _RecordingDb();
    connectRtdbEmulatorIfRequested(db, enabled: false);
    expect(db.calls, isEmpty);
  });

  test('switched on, it points the database at the host emulator once', () {
    final db = _RecordingDb();
    connectRtdbEmulatorIfRequested(db, enabled: true);
    expect(db.calls, ['useDatabaseEmulator(10.0.2.2, 9000)']);
  });
}
