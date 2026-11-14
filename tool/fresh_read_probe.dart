// Fresh-read probe (plan 2026-11-13-fresh-reads.md, Task 0).
//
// A throwaway diagnostic app, NOT part of the fan app. It measures when a
// Realtime Database read answers from the phone's saved copy and when it
// answers from the server. It only READS (never writes) and never uses
// `.get()`.
//
//   build:  flutter build apk --debug -t tool/fresh_read_probe.dart
//   reset:  add --dart-define=PROBE_RESET=1  (that launch only resets the
//           launch counter; the next launch of a normal build is phase 1)
//   force:  add --dart-define=PROBE_PHASE=<1..8>  (runs that phase; the
//           launch counter is not advanced)
//
// Every measurement is one line, printed (logcat tag `flutter`) and shown on
// screen:
//   PROBE|<launch>|<phase>|<step>|<value|ERR:<type>|TIMEOUT>|<step ms>|<app ms>
//
// Run sheet: docs/superpowers/plans/assets/2026-11-13-fresh-read-probe.md
//
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:infinite_sports_flutter/firebase_options.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';
import 'package:infinite_sports_flutter/misc/rtdb_emulator.dart';
import 'package:infinite_sports_flutter/misc/server_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _counterKey = 'freshProbeLaunch';
const _lastPhase = 8;
const _valuePath = 'SyncProbe/value';
const _barrierPath = 'SyncProbe/barrier';

final Stopwatch _app = Stopwatch();
final ValueNotifier<List<String>> _lines = ValueNotifier(<String>[]);
int _launch = 0;
int _phase = 0;

/// Prints one PROBE line and adds it to the on-screen list.
void _log(String step, String value, [int stepMs = 0]) {
  final line = 'PROBE|$_launch|$_phase|$step|${_clean(value)}|$stepMs|'
      '${_app.elapsedMilliseconds}';
  print(line);
  _lines.value = [..._lines.value, line];
}

/// Keeps a value on one line and free of the field separator.
String _clean(String s) =>
    s.replaceAll('|', '/').replaceAll('\n', ' ').replaceAll('\r', ' ');

String _show(DataSnapshot s) => s.exists ? '${s.value}' : 'null';

String _err(Object e) => 'ERR:${e.runtimeType}';

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

DatabaseReference get _value => FirebaseDatabase.instance.ref(_valuePath);

// ---------------------------------------------------------------- start-up

Future<void> main() async {
  _app.start();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
  // Same database start-up order as lib/main.dart: env config, Firebase,
  // emulator switch, server-time listener, on-disk cache. Nothing else.
  try {
    await FlutterConfig.loadEnvVariables();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    connectRtdbEmulatorIfRequested(FirebaseDatabase.instance);
    initServerTimeOffset();
    enableRtdbPersistenceUnlessEmulator(FirebaseDatabase.instance);
  } catch (e) {
    _log('init', _err(e));
    _log('DONE', 'init failed');
    return;
  }
  await _run();
}

Future<void> _run() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getInt(_counterKey) ?? 0;

  if (const String.fromEnvironment('PROBE_RESET') == '1') {
    await prefs.setInt(_counterKey, 0);
    _log('START', 'reset build: counter was $stored, now 0');
    _log('DONE', 'reset only; install a normal build, next launch = phase 1');
    return;
  }

  _launch = stored + 1;
  final forced = int.tryParse(const String.fromEnvironment('PROBE_PHASE'));
  String note;
  if (forced != null && forced >= 1 && forced <= _lastPhase) {
    _phase = forced;
    note = 'phase=$_phase forced (counter not advanced)';
  } else {
    await prefs.setInt(_counterKey, _launch);
    _phase = _launch > _lastPhase ? _lastPhase : _launch;
    note = _launch > _lastPhase
        ? 'phase=$_phase (launch $_launch > $_lastPhase: repeating phase 8)'
        : 'phase=$_phase';
  }
  _log('START', note);
  _watchConnected();

  try {
    switch (_phase) {
      case 1:
        await _phase1();
      case 2:
        await _phase2();
      case 3:
        await _phase3();
      case 4:
        await _phase4();
      case 5:
        await _phase5();
      case 6:
        await _phase6();
      case 7:
        await _phase7();
      default:
        await _phase8();
    }
  } catch (e) {
    _log('phase', _err(e)); // a step should never get here; logged anyway
  }
  _log('DONE', 'phase=$_phase');
}

// ------------------------------------------------------------ connection

bool? _connected;
Completer<void> _connectedTrue = Completer<void>();

/// Logs `.info/connected` at start and on every change (local path).
void _watchConnected() {
  FirebaseDatabase.instance.ref('.info/connected').onValue.listen((e) {
    final now = e.snapshot.value == true;
    if (now != _connected) {
      _connected = now;
      _log('connected', '$now');
    }
    if (now && !_connectedTrue.isCompleted) _connectedTrue.complete();
    if (!now && _connectedTrue.isCompleted) _connectedTrue = Completer<void>();
  }, onError: (Object e) => _log('connected', _err(e)));
}

Future<void> _waitConnected(String label) async {
  final sw = Stopwatch()..start();
  if (_connected == true) {
    _log(label, 'true (already)', sw.elapsedMilliseconds);
    return;
  }
  try {
    await _connectedTrue.future.timeout(kRevealReadTimeout);
    _log(label, 'true', sw.elapsedMilliseconds);
  } on TimeoutException {
    _log(label, 'TIMEOUT', sw.elapsedMilliseconds);
  }
}

// ----------------------------------------------------------------- steps

/// One bounded `once()`. A timed-out read that answers later is logged as
/// `<label> late`.
Future<void> _once(String label, DatabaseReference ref) async {
  final sw = Stopwatch()..start();
  var timedOut = false;
  final read = ref.once();
  try {
    final e = await read.timeout(kRevealReadTimeout);
    _log(label, _show(e.snapshot), sw.elapsedMilliseconds);
  } on TimeoutException {
    timedOut = true;
    _log(label, 'TIMEOUT', sw.elapsedMilliseconds);
  } catch (e) {
    _log(label, _err(e), sw.elapsedMilliseconds);
  }
  if (timedOut) {
    read.then(
        (e) => _log('$label late', _show(e.snapshot), sw.elapsedMilliseconds),
        onError: (Object e) =>
            _log('$label late', _err(e), sw.elapsedMilliseconds));
  }
}

/// An `onValue` listener on the value that logs every event. Cancelled by
/// [cancel], which logs it.
class _Listener {
  _Listener(this.label) {
    _sub = _value.onValue.listen((e) {
      events++;
      latest = _show(e.snapshot);
      _log('$label event#$events', latest!, sw.elapsedMilliseconds);
      if (!first.isCompleted) first.complete();
    }, onError: (Object e) {
      _log('$label error', _err(e), sw.elapsedMilliseconds);
      if (!first.isCompleted) first.complete();
    });
  }

  final String label;
  final Stopwatch sw = Stopwatch()..start();
  final Completer<void> first = Completer<void>();
  late final StreamSubscription<DatabaseEvent> _sub;
  int events = 0;
  String? latest;

  /// Waits (bounded) for the first event; logs TIMEOUT if none comes.
  Future<bool> waitFirst() async {
    try {
      await first.future.timeout(kRevealReadTimeout);
      return events > 0;
    } on TimeoutException {
      _log('$label first-event', 'TIMEOUT', sw.elapsedMilliseconds);
      return false;
    }
  }

  Future<void> cancel() async {
    await _sub.cancel();
    _log('$label cancel', 'events=$events latest=$latest',
        sw.elapsedMilliseconds);
  }
}

/// Attach onValue, log every event for 6 s, cancel.
Future<void> _listenFor6s(String label) async {
  final l = _Listener(label);
  await _wait(6000);
  await l.cancel();
}

/// Attach onValue, cancel 300 ms after the first event (or after the bound).
Future<void> _linger(String label) async {
  final l = _Listener(label);
  if (await l.waitFirst()) await _wait(300);
  await l.cancel();
}

/// Barrier: onValue on the value; at its first event, `once()` on each
/// barrier child in turn; after each, log the latest value event.
Future<void> _barrier(String label, List<String> children) async {
  final l = _Listener('$label onValue');
  await l.waitFirst();
  for (var i = 0; i < children.length; i++) {
    final child = children[i];
    await _once('$label barrier#${i + 1} $child',
        FirebaseDatabase.instance.ref('$_barrierPath/$child'));
    _log('$label value-at-barrier#${i + 1}',
        'events=${l.events} latest=${l.latest}', l.sw.elapsedMilliseconds);
  }
  await l.cancel();
}

String _freshChild() =>
    FirebaseDatabase.instance.ref(_barrierPath).push().key ?? 'nokey';

// ---------------------------------------------------------------- phases

// 1. once() primes the saved copy.
Future<void> _phase1() => _once('once', _value);

// 2. once() at start → 3 s → once() → 3 s → once().
Future<void> _phase2() async {
  await _once('once#1', _value);
  await _wait(3000);
  await _once('once#2 (+3s)', _value);
  await _wait(3000);
  await _once('once#3 (+3s)', _value);
}

// 3. Wait for .info/connected, then once() → 3 s → once().
Future<void> _phase3() async {
  await _waitConnected('wait-connected');
  await _once('once#1 (connected)', _value);
  await _wait(3000);
  await _once('once#2 (+3s)', _value);
}

// 4. onValue for 6 s, cancel, then once().
Future<void> _phase4() async {
  await _listenFor6s('onValue6s');
  await _once('once after onValue', _value);
}

// 5. Linger: onValue cancelled 300 ms after its first event, then once().
Future<void> _phase5() async {
  await _linger('linger');
  await _once('once after linger', _value);
}

// 6. once() (baseline: did phase 5 renew the saved copy?), then barrier on a
//    never-loaded child.
Future<void> _phase6() async {
  await _once('once (baseline)', _value);
  await _barrier('fresh', [_freshChild()]);
}

// 7. once() baseline, then barrier on the FIXED child twice in a row.
Future<void> _phase7() async {
  await _once('once (baseline)', _value);
  await _barrier('fixed', ['fixed', 'fixed']);
}

// 8. Airplane mode: every variant above, each bounded.
Future<void> _phase8() async {
  await _once('8a once', _value);
  await _waitConnected('8b wait-connected');
  await _once('8c once', _value);
  await _listenFor6s('8d onValue6s');
  await _once('8d once after onValue', _value);
  await _linger('8e linger');
  await _once('8e once after linger', _value);
  await _barrier('8f fresh', [_freshChild()]);
  await _barrier('8g fixed', ['fixed', 'fixed']);
}

// -------------------------------------------------------------------- UI

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fresh read probe',
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Fresh read probe')),
        body: SafeArea(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: _lines,
            builder: (context, lines, _) => _LineList(lines: lines),
          ),
        ),
      ),
    );
  }
}

class _LineList extends StatefulWidget {
  const _LineList({required this.lines});
  final List<String> lines;

  @override
  State<_LineList> createState() => _LineListState();
}

class _LineListState extends State<_LineList> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _LineList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Newest at the bottom: follow it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemCount: widget.lines.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(widget.lines[i],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
      ),
    );
  }
}
