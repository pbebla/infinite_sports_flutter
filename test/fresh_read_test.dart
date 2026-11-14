// Fresh reads (plan 2026-11-13-fresh-reads.md, Task 1): the two read helpers
// that keep the phone's saved copy of the database renewed.
//
// No Firebase here: the engine takes its three inputs through seams — the
// value-event stream for a query, the barrier read and the connection state —
// and these tests drive fakes of all three. The measured device facts the
// engine is built on are in
// docs/superpowers/plans/assets/2026-11-13-fresh-read-probe.md.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

/// A stand-in for a DatabaseEvent: just the value.
class _Ev {
  _Ev(this.value);
  final Object? value;
  @override
  String toString() => '_Ev($value)';
}

/// One fake database path: every listen gets its own controller, so the
/// tests can count listeners and see cancels.
class _Path {
  final List<StreamController<_Ev>> listens = [];
  int cancels = 0;

  Stream<_Ev> open() {
    late StreamController<_Ev> c;
    c = StreamController<_Ev>(onCancel: () {
      cancels++;
      listens.remove(c);
    });
    listens.add(c);
    return c.stream;
  }

  int get live => listens.length;

  /// Delivers a value to every attached listener.
  void emit(Object? v) {
    for (final c in List.of(listens)) {
      c.add(_Ev(v));
    }
  }

  void fail(Object error) {
    for (final c in List.of(listens)) {
      c.addError(error);
    }
  }
}

/// `.info/connected`: like the real one, a new listener first gets the
/// current state.
class _Connection {
  final StreamController<bool> _c = StreamController<bool>.broadcast();
  bool? _current;

  void add(bool up) {
    _current = up;
    _c.add(up);
  }

  Stream<bool> stream() async* {
    final now = _current;
    if (now != null) yield now;
    yield* _c.stream;
  }
}

class _Fakes {
  final Map<String, _Path> paths = {};
  final _Connection connection = _Connection();
  final List<Completer<void>> barriers = [];

  _Path path(String p) => paths.putIfAbsent(p, _Path.new);

  FreshReadEngine<String, _Ev> engine({
    Duration lingerFor = const Duration(seconds: 15),
  }) =>
      FreshReadEngine<String, _Ev>(
        valueEvents: (q) => path(q).open(),
        keyOf: (q) => q,
        valueOf: (e) => e.value,
        barrier: () {
          final c = Completer<void>();
          barriers.add(c);
          return c.future;
        },
        connection: connection.stream,
        lingerFor: lingerFor,
        batchWindow: const Duration(milliseconds: 1),
      );

  /// Answers the oldest unanswered barrier read.
  void answerBarrier() => barriers.firstWhere((c) => !c.isCompleted).complete();

  void failBarrier() => barriers
      .firstWhere((c) => !c.isCompleted)
      .completeError(StateError('permission-denied'));

  int get pendingBarriers => barriers.where((c) => !c.isCompleted).length;
}

/// Lets timers of [ms] and the microtasks behind them run.
Future<void> _tick([int ms = 5]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late _Fakes f;
  late List<String> logs;
  late DebugPrintCallback original;

  setUp(() {
    f = _Fakes();
    logs = [];
    original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() {
    debugPrint = original;
  });

  test('the constants are the ones the probe settled', () {
    expect(kLingerFor, const Duration(seconds: 15));
    expect(kSyncBarrierNode, 'SyncBarrier');
  });

  group('refreshingOnce', () {
    test('answers with the first event (the saved copy) at once', () async {
      final e = f.engine();
      final read = e.refreshing('Logo Urls');
      await _tick(0);
      f.path('Logo Urls').emit('saved');
      expect((await read).value, 'saved');
      e.debugReset();
    });

    test(
        'keeps listening after answering until the server has answered, '
        'then cancels', () async {
      final e = f.engine();
      final p = f.path('Logo Urls');
      final read = e.refreshing('Logo Urls');
      await _tick(0);
      p.emit('saved');
      await read;
      expect(p.live, 1, reason: 'still attached so the saved copy renews');

      f.connection.add(true);
      await _tick();
      expect(f.pendingBarriers, 1, reason: 'barrier only once connected');
      p.emit('server'); // the server's value lands in the saved copy
      f.answerBarrier();
      await _tick();
      expect(p.live, 0, reason: 'server answered: listener cancelled');
      expect(p.cancels, 1);
      e.debugReset();
    });

    test('the barrier waits for the connection', () async {
      final e = f.engine();
      final read = e.refreshing('A');
      await _tick(0);
      f.path('A').emit(1);
      await read;
      await _tick(20);
      expect(f.barriers, isEmpty, reason: 'offline: no barrier read yet');
      f.connection.add(false);
      await _tick();
      expect(f.barriers, isEmpty);
      f.connection.add(true);
      await _tick();
      expect(f.barriers, hasLength(1));
      e.debugReset();
    });

    test('gives up lingering after kLingerFor (offline) and cancels', () async {
      final e = f.engine(lingerFor: const Duration(milliseconds: 30));
      final p = f.path('A');
      final read = e.refreshing('A');
      await _tick(0);
      p.emit('saved');
      await read;
      expect(p.live, 1);
      await _tick(60);
      expect(p.live, 0, reason: 'never connected: cancelled at the bound');
      e.debugReset();
    });

    test(
        'a read waiting for its first event keeps the listener past the '
        'linger bound (like once())', () async {
      final e = f.engine(lingerFor: const Duration(milliseconds: 20));
      final p = f.path('A');
      final read = e.refreshing('A');
      await _tick(50);
      expect(p.live, 1, reason: 'a reader is still waiting');
      p.emit('late');
      expect((await read).value, 'late');
      await _tick(5);
      expect(p.live, 0, reason: 'answered and past the bound: cancelled');
      e.debugReset();
    });

    test('two reads of one path share ONE listener', () async {
      final e = f.engine();
      final p = f.path('Current League');
      final r1 = e.refreshing('Current League');
      final r2 = e.refreshing('Current League');
      await _tick(0);
      expect(p.live, 1);
      p.emit('Futsal');
      expect((await r1).value, 'Futsal');
      expect((await r2).value, 'Futsal');
      // A third read while lingering answers from the held value at once.
      final r3 = await e.refreshing('Current League');
      expect(r3.value, 'Futsal');
      expect(p.live, 1);
      e.debugReset();
    });

    test('onNewer fires only for a changed value, then not after cancel',
        () async {
      final e = f.engine();
      final p = f.path('Futsal Season');
      final seen = <Object?>[];
      final remove = e.onNewer('Futsal Season', (ev) => seen.add(ev.value));
      final read = e.refreshing('Futsal Season');
      await _tick(0);
      p.emit({'n': 15});
      await read;
      p.emit({'n': 15}); // same value again (deep-equal): not newer
      await _tick(0);
      expect(seen, isEmpty);
      p.emit({'n': 16});
      await _tick(0);
      expect(seen, [
        {'n': 16}
      ]);
      remove();
      p.emit({'n': 17});
      await _tick(0);
      expect(seen, hasLength(1), reason: 'removed callback never fires');
      e.debugReset();
    });

    test('nothing fires after the listener is cancelled', () async {
      final e = f.engine();
      final p = f.path('A');
      final seen = <Object?>[];
      e.onNewer('A', (ev) => seen.add(ev.value));
      final read = e.refreshing('A');
      await _tick(0);
      p.emit(1);
      await read;
      f.connection.add(true);
      await _tick();
      p.emit(2);
      f.answerBarrier();
      await _tick();
      expect(seen, [2]);
      expect(p.live, 0);
      p.emit(3); // nobody is listening any more
      await _tick(0);
      expect(seen, [2]);
      e.debugReset();
    });

    test('an error reaches the waiting reader and the listener is dropped',
        () async {
      final e = f.engine();
      final p = f.path('A');
      final read = e.refreshing('A');
      await _tick(0);
      p.fail(StateError('permission-denied'));
      await expectLater(read, throwsStateError);
      expect(p.live, 0);
      // The next read starts a new listener.
      final again = e.refreshing('A');
      await _tick(0);
      expect(p.live, 1);
      p.emit('ok');
      expect((await again).value, 'ok');
      e.debugReset();
    });

    test('reads that begin together share one barrier read', () async {
      final e = f.engine();
      f.connection.add(true);
      await _tick(0);
      final reads = [e.refreshing('A'), e.refreshing('B'), e.refreshing('C')];
      await _tick(0);
      for (final p in ['A', 'B', 'C']) {
        f.path(p).emit(p);
      }
      await Future.wait(reads);
      await _tick();
      expect(f.barriers, hasLength(1));
      f.answerBarrier();
      await _tick();
      expect(f.paths.values.every((p) => p.live == 0), isTrue);
      e.debugReset();
    });

    test('a read that starts after a barrier was sent needs a later barrier',
        () async {
      final e = f.engine();
      f.connection.add(true);
      await _tick(0);
      final a = e.refreshing('A');
      await _tick(0);
      f.path('A').emit(1);
      await a;
      await _tick();
      expect(f.barriers, hasLength(1)); // sent for A
      final b = e.refreshing('B'); // attached after that barrier left
      await _tick(0);
      f.path('B').emit(1);
      await b;
      f.answerBarrier(); // answers A's barrier only
      await _tick();
      expect(f.path('A').live, 0);
      expect(f.path('B').live, 1, reason: "A's barrier proves nothing for B");
      expect(f.pendingBarriers, 1);
      f.answerBarrier();
      await _tick();
      expect(f.path('B').live, 0);
      e.debugReset();
    });
  });

  group('serverFirstOnce', () {
    test('online: the value the listener holds when the barrier returns',
        () async {
      final e = f.engine();
      final p = f.path('Registrations/r/Submissions/u');
      final read = e.serverFirst('Registrations/r/Submissions/u');
      await _tick(0);
      p.emit(null); // the saved copy says "not registered"
      f.connection.add(true);
      await _tick();
      var done = false;
      unawaited(read.then((_) => done = true));
      await _tick();
      expect(done, isFalse, reason: 'the saved copy is not the answer');
      p.emit({'Paid': true}); // the server's value
      f.answerBarrier();
      final r = await read;
      expect(r.event.value, {'Paid': true});
      expect(r.fromServer, isTrue);
      await _tick();
      expect(p.live, 0);
      e.debugReset();
    });

    test('offline: the saved copy, marked not from the server, at the bound',
        () async {
      final e = f.engine();
      final p = f.path('A');
      final read =
          e.serverFirst('A', timeout: const Duration(milliseconds: 30));
      await _tick(0);
      p.emit('saved');
      final r = await read;
      expect(r.event.value, 'saved');
      expect(r.fromServer, isFalse);
      e.debugReset();
    });

    test('no saved copy and no answer: the existing TimeoutException',
        () async {
      final e = f.engine();
      final read =
          e.serverFirst('A', timeout: const Duration(milliseconds: 20));
      await expectLater(read, throwsA(isA<TimeoutException>()));
      e.debugReset();
    });

    test('a stream error is thrown to the caller (a failure is not a fact)',
        () async {
      final e = f.engine();
      final read = e.serverFirst('A');
      await _tick(0);
      f.path('A').fail(StateError('permission-denied'));
      await expectLater(read, throwsStateError);
      expect(f.path('A').live, 0);
      e.debugReset();
    });

    test('a failed barrier: the saved copy, marked not from the server',
        () async {
      final e = f.engine();
      f.connection.add(true);
      await _tick(0);
      final read = e.serverFirst('A');
      await _tick(0);
      f.path('A').emit('saved');
      await _tick();
      f.failBarrier();
      final r = await read;
      expect(r.event.value, 'saved');
      expect(r.fromServer, isFalse);
      e.debugReset();
    });

    test(
        'two server-first reads of one path share one listener and one '
        'barrier', () async {
      final e = f.engine();
      f.connection.add(true);
      await _tick(0);
      final r1 = e.serverFirst('A');
      final r2 = e.serverFirst('A');
      await _tick(0);
      expect(f.path('A').live, 1);
      f.path('A').emit('v1');
      await _tick();
      expect(f.barriers, hasLength(1));
      f.answerBarrier();
      expect((await r1).fromServer, isTrue);
      expect((await r2).fromServer, isTrue);
      await _tick();
      expect(f.path('A').live, 0);
      e.debugReset();
    });

    test('nothing completes after cancelWhere; a waiting read fails', () async {
      final e = f.engine();
      final p = f.path('Users/u1');
      final read = e.serverFirst('Users/u1');
      await _tick(0);
      e.cancelWhere(isUserScopedPath);
      await expectLater(read, throwsStateError);
      expect(p.live, 0);
      e.debugReset();
    });
  });

  group('cancelUserScoped', () {
    test('per-user paths are recognised', () {
      expect(isUserScopedPath('Users/abc'), isTrue);
      expect(isUserScopedPath('Users/abc/Information'), isTrue);
      expect(isUserScopedPath('ReferredUsers/abc'), isTrue);
      expect(isUserScopedPath('Insiders/abc'), isTrue);
      expect(isUserScopedPath('Support/UserTickets/abc'), isTrue);
      expect(isUserScopedPath('Registrations/r1/Submissions/abc'), isTrue);
      expect(isUserScopedPath('Current League'), isFalse);
      expect(isUserScopedPath('Futsal/16/Line Ups'), isFalse);
      expect(isUserScopedPath('RegistrationsPublic'), isFalse);
    });

    test('lingering per-user listeners are cancelled, others kept', () async {
      final e = f.engine();
      final mine = e.refreshing('Users/u1');
      final shared = e.refreshing('Current League');
      await _tick(0);
      f.path('Users/u1').emit({'First Name': 'A'});
      f.path('Current League').emit('Futsal');
      await mine;
      await shared;
      e.cancelWhere(isUserScopedPath);
      expect(f.path('Users/u1').live, 0);
      expect(f.path('Current League').live, 1);
      e.debugReset();
      expect(f.path('Current League').live, 0);
    });
  });

  group('paths and newer-value dispatch (Task 4)', () {
    test('normalizeFreshPath drops empty segments', () {
      expect(
          normalizeFreshPath('/AFC San Jose//Seasons'), 'AFC San Jose/Seasons');
      expect(normalizeFreshPath('Users/u1/'), 'Users/u1');
      expect(normalizeFreshPath('/'), '');
    });

    test('the engine reports every newer value to onAnyNewer', () async {
      final seen = <String>[];
      final e = FreshReadEngine<String, _Ev>(
        valueEvents: (q) => f.path(q).open(),
        keyOf: (q) => q,
        valueOf: (ev) => ev.value,
        barrier: () => Completer<void>().future,
        connection: f.connection.stream,
        onAnyNewer: (key, ev) => seen.add('$key=${ev.value}'),
      );
      final read = e.refreshing('A');
      await _tick(0);
      f.path('A').emit(1);
      await read;
      f.path('A').emit(1);
      f.path('A').emit(2);
      await _tick(0);
      expect(seen, ['A=2']);
      e.debugReset();
    });

    test('FreshReads.onNewer / onNewerUnder by normalized path', () {
      final exact = <Object?>[];
      final under = <String>[];
      final r1 = FreshReads.onNewer('Futsal/16/Line Ups', exact.add);
      final r2 = FreshReads.onNewerUnder(
          'PublicProfiles/', (path, v) => under.add('$path=$v'));
      FreshReads.debugReportNewer('/Futsal/16//Line Ups', {'a': 1});
      FreshReads.debugReportNewer('PublicProfiles/u1/ProfileUrl', 'x');
      FreshReads.debugReportNewer('Futsal/15/Line Ups', 'no');
      expect(exact, [
        {'a': 1}
      ]);
      expect(under, ['PublicProfiles/u1/ProfileUrl=x']);
      r1();
      r2();
      FreshReads.debugReportNewer('Futsal/16/Line Ups', 'gone');
      expect(exact, hasLength(1));
    });

    test('refreshingValue answers through its seam', () async {
      FreshReads.refreshingValueOverride = (path) async => 'v:$path';
      addTearDown(() => FreshReads.refreshingValueOverride = null);
      expect(await refreshingValue('/A//B'), 'v:A/B');
    });
  });
}
