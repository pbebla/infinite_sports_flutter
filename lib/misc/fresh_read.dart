// Fresh reads (plan 2026-11-13-fresh-reads.md, Task 1).
//
// The app keeps a saved copy of the database on the phone (on-disk cache,
// `enableRtdbPersistenceUnlessEmulator`). Measured on the emulator
// (docs/superpowers/plans/assets/2026-11-13-fresh-read-probe.md):
//   • a one-shot `once()` on a path loaded before answers from the saved
//     copy and does not reliably renew it (`Logo Urls`, `Futsal/15/Line Ups`
//     stayed stale across five cold starts);
//   • a listener that STAYS attached receives the server's value a few
//     hundred ms after the connection is up;
//   • a short fixed linger is useless: it can end before the connection is
//     up and then renews nothing;
//   • the barrier works: when a `once()` on a never-loaded, UNIQUE child
//     returns, every listener attached before it already holds the server's
//     value (a fixed child is answered from the saved copy the second time,
//     so the child must be new every time: `SyncBarrier/<push id>`);
//   • offline everything answers from the saved copy at once, while waiting
//     for the connection or for the barrier never ends — so every wait here
//     is bounded.
//
// Two helpers, both built on live `onValue` listeners (never `get()`, which
// returns wrong data on iOS; in this plugin version `once()` itself is
// `onValue.first`):
//
//   • [refreshingOnce] — for DISPLAY: answers with the first event at once
//     (the saved copy when there is one, so opening stays instant) and keeps
//     ONE shared listener per path attached until the server has answered
//     (the barrier returned) or [kLingerFor] has passed, so the server's
//     version lands in the saved copy. A different value arriving meanwhile
//     is handed to [FreshReads.onNewer] callbacks.
//   • [serverFirstOnce] / [serverFirstValue] — for DECISIONS: waits for the
//     connection, then the barrier, bounded by [kRevealReadTimeout]; the
//     value held at that moment is the server's (`fromServer: true`). Past
//     the bound (offline), or when the barrier read fails, it answers with
//     the saved copy marked `fromServer: false`; with no saved copy at all it
//     throws the usual [TimeoutException]. A stream error is thrown — a
//     failed read is not a fact.
//
// Listeners are shared per path (reference-counted by the reads in flight)
// and ALWAYS cancelled: when the server has answered, when [kLingerFor]
// passes, on an error, or by [FreshReads.cancelUserScoped] at sign-out for
// per-user paths. Reads that begin within [kBarrierBatchWindow] share one
// barrier read. One permanent `.info/connected` listener (a local path, no
// network cost) tells the engine when the connection is up.
//
// Test seams: [FreshReadEngine] takes the value-event stream, the barrier
// read and the connection state as functions (test/fresh_read_test.dart);
// [FreshReads.serverFirstValueOverride] lets call-site tests answer
// [serverFirstValue] by path without Firebase.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';

/// Longest a refreshing read keeps its listener after answering when the
/// server has not answered yet (probe decision: until the barrier returned or
/// 15 s, whichever is first).
const Duration kLingerFor = Duration(seconds: 15);

/// Reads that begin within this window share one barrier read.
const Duration kBarrierBatchWindow = Duration(milliseconds: 5);

/// The public, never-written node whose unique children are the barrier.
const String kSyncBarrierNode = 'SyncBarrier';

/// What a server-first read answered with: the event and whether it is
/// proven to be the server's value (false = the phone's saved copy, because
/// the server could not be reached in time).
class FreshOutcome<E> {
  const FreshOutcome(this.event, {required this.fromServer});
  final E event;
  final bool fromServer;
}

/// [serverFirstOnce]'s answer.
class FreshResult {
  const FreshResult(this.snapshot, {required this.fromServer});
  final DataSnapshot snapshot;
  final bool fromServer;
}

/// [serverFirstValue]'s answer: just the value (null = no data at the path).
class FreshValue {
  const FreshValue(this.value, {required this.fromServer});
  final Object? value;
  final bool fromServer;
  bool get exists => value != null;
}

/// A database path with empty segments dropped: `ref('/AFC San Jose/')
/// .child('Seasons').path` is `/AFC San Jose//Seasons` in this plugin — the
/// sharing key and the onNewer key are `AFC San Jose/Seasons`.
String normalizeFreshPath(String path) =>
    path.split('/').where((s) => s.isNotEmpty).join('/');

/// The sharing key of a read (review m4): a plain reference shares by its
/// normalized path; a query with parameters (orderBy/limit/equalTo — the
/// plugin does not expose them) NEVER shares, so a filtered read can never
/// receive an unfiltered listener's events or vice versa. Debug builds
/// assert that only plain references are used (all of lib/ does).
String freshShareKey(String path,
        {required bool plainRef, required Object identity}) =>
    plainRef
        ? normalizeFreshPath(path)
        : '${normalizeFreshPath(path)}#query${identityHashCode(identity)}';

/// Per-user paths whose lingering listeners must not outlive a sign-out.
bool isUserScopedPath(String path) {
  final p = normalizeFreshPath(path);
  return p.startsWith('Users/') ||
      p.startsWith('ReferredUsers/') ||
      p.startsWith('Insiders/') ||
      p.startsWith('Support/UserTickets/') ||
      p.contains('/Submissions/');
}

/// Deep equality for database values (maps, lists, scalars).
bool freshValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !freshValuesEqual(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!freshValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

class _Entry<E> {
  _Entry(this.key);
  final String key;
  StreamSubscription<E>? sub;
  Timer? lingerTimer;
  bool lingerExpired = false;
  bool closed = false;

  bool hasValue = false;
  E? latest;

  /// The value last handed to a caller or an onNewer callback.
  bool delivered = false;
  Object? deliveredValue;

  bool syncRequested = false;

  /// A barrier sent after this listener attached has returned: [latest] is
  /// the server's value (and stays current while the listener is attached).
  bool synced = false;

  /// The last barrier read failed: freshness cannot be proven.
  bool syncFailed = false;

  /// Server-first reads in progress.
  int holds = 0;
  final List<Completer<E>> firstWaiters = [];
  final List<Completer<FreshOutcome<E>>> serverWaiters = [];
}

/// The engine behind [refreshingOnce] and [serverFirstOnce], generic over
/// the query type [Q] and the event type [E] so it can be tested without
/// Firebase.
class FreshReadEngine<Q, E> {
  FreshReadEngine({
    required this.valueEvents,
    required this.keyOf,
    required this.valueOf,
    required this.barrier,
    required this.connection,
    this.lingerFor = kLingerFor,
    this.batchWindow = kBarrierBatchWindow,
    this.onAnyNewer,
  });

  /// Called for EVERY newer value on any key (after the per-key callbacks)
  /// — FreshReads' path/prefix dispatch.
  final void Function(String key, E event)? onAnyNewer;

  /// The live value-event stream for a query (`onValue`).
  final Stream<E> Function(Q query) valueEvents;

  /// The sharing key of a query (its path).
  final String Function(Q query) keyOf;

  /// The plain value of an event (for "is it newer?").
  final Object? Function(E event) valueOf;

  /// One barrier read on a never-loaded unique child.
  final Future<void> Function() barrier;

  /// The connection state (`.info/connected`).
  final Stream<bool> Function() connection;

  final Duration lingerFor;
  final Duration batchWindow;

  final Map<String, _Entry<E>> _entries = {};
  final Map<String, List<void Function(E event)>> _newer = {};

  // ---------------------------------------------------------- public API

  /// The first event for [query] (the saved copy when there is one); the
  /// shared listener then stays until the server has answered or
  /// [lingerFor] passed. Not bounded (like `once()`); callers bound it.
  Future<E> refreshing(Q query) {
    final entry = _acquire(query);
    if (entry.hasValue) {
      final e = entry.latest as E;
      _markDelivered(entry, e);
      return Future<E>.value(e);
    }
    final c = Completer<E>();
    entry.firstWaiters.add(c);
    // Second review, Minor 2: EVERY reader gets its own bound from the
    // moment it joins (a reader joining after the entry's linger pass used
    // to wait for the connection).
    Timer(lingerFor, () {
      if (c.isCompleted || !entry.firstWaiters.remove(c)) return;
      c.completeError(
          TimeoutException('Fresh read ${entry.key}: no answer', lingerFor));
      _maybeClose(entry);
    });
    return c.future;
  }

  /// The server's value for [query] when it can be had within [timeout];
  /// otherwise the saved copy marked not-from-server; with neither, a
  /// [TimeoutException]. A stream error is rethrown.
  Future<FreshOutcome<E>> serverFirst(Q query,
      {Duration timeout = kRevealReadTimeout}) async {
    final entry = _acquire(query);
    entry.holds++;
    final c = Completer<FreshOutcome<E>>();
    if (entry.synced && entry.hasValue) {
      c.complete(FreshOutcome(entry.latest as E, fromServer: true));
    } else {
      if (entry.syncFailed) {
        // A previous barrier failed: try again for this read.
        entry.syncFailed = false;
        entry.syncRequested = false;
        _requestSync(entry);
      }
      entry.serverWaiters.add(c);
    }
    final timer = Timer(timeout, () {
      if (c.isCompleted) return;
      entry.serverWaiters.remove(c);
      if (entry.hasValue) {
        debugPrint('Fresh read ${entry.key}: server not reached in '
            '${timeout.inMilliseconds}ms — using the saved copy');
        c.complete(FreshOutcome(entry.latest as E, fromServer: false));
      } else {
        c.completeError(
            TimeoutException('Fresh read ${entry.key}: no answer', timeout));
      }
    });
    try {
      final out = await c.future;
      _markDelivered(entry, out.event);
      return out;
    } finally {
      timer.cancel();
      entry.holds--;
      _maybeClose(entry);
    }
  }

  /// Calls [callback] when a lingering listener on [key] receives a value
  /// different from the one last handed out. Returns the remover.
  VoidCallback onNewer(String key, void Function(E event) callback) {
    final list = _newer.putIfAbsent(key, () => []);
    list.add(callback);
    return () {
      list.remove(callback);
      if (list.isEmpty && identical(_newer[key], list)) _newer.remove(key);
    };
  }

  /// Cancels every listener whose key matches [test]; reads still waiting on
  /// them fail with a [StateError].
  void cancelWhere(bool Function(String key) test) {
    for (final entry in _entries.values.toList()) {
      if (test(entry.key)) {
        _fail(entry, StateError('Fresh read ${entry.key}: cancelled'),
            StackTrace.current);
      }
    }
  }

  /// Number of attached listeners (diagnostics/tests).
  int get liveListeners => _entries.length;

  /// Cancels everything (tests).
  void debugReset() {
    for (final entry in _entries.values.toList()) {
      _close(entry);
    }
    _entries.clear();
    _newer.clear();
    _connSub?.cancel();
    _connSub = null;
    _connected = false;
    _connectedWaiter = null;
    _nextBarrier = null;
  }

  // ------------------------------------------------------------ listeners

  _Entry<E> _acquire(Q query) {
    final key = keyOf(query);
    final existing = _entries[key];
    if (existing != null && !existing.closed) return existing;
    final entry = _Entry<E>(key);
    _entries[key] = entry;
    entry.lingerTimer = Timer(lingerFor, () {
      entry.lingerTimer = null;
      entry.lingerExpired = true;
      // Review m3 / second review Minor 2: past the linger the entry closes
      // as soon as it has no waiters and no holders. Each first-reader and
      // each server-first read carries its own bound (refreshing: lingerFor
      // from joining; server-first: its timeout), so that always happens.
      _maybeClose(entry);
    });
    try {
      entry.sub = valueEvents(query).listen(
        (e) => _onEvent(entry, e),
        onError: (Object error, StackTrace st) => _fail(entry, error, st),
      );
    } catch (error, st) {
      scheduleMicrotask(() => _fail(entry, error, st));
    }
    // The barrier is requested at the FIRST EVENT (_onEvent), not here: an
    // event proves the native listener is attached, so the barrier's own
    // listen request is guaranteed to reach the database after it (review:
    // attach order). This is the sequence the probe measured (phase 6).
    return entry;
  }

  void _onEvent(_Entry<E> entry, E e) {
    if (entry.closed) return;
    entry.latest = e;
    entry.hasValue = true;
    _requestSync(entry); // no-op once requested
    final v = valueOf(e);
    if (entry.delivered && !freshValuesEqual(v, entry.deliveredValue)) {
      entry.deliveredValue = v;
      for (final cb in List.of(_newer[entry.key] ?? const [])) {
        try {
          cb(e);
        } catch (err) {
          debugPrint('Fresh read ${entry.key}: onNewer callback failed: $err');
        }
      }
      try {
        onAnyNewer?.call(entry.key, e);
      } catch (err) {
        debugPrint('Fresh read ${entry.key}: onNewer dispatch failed: $err');
      }
    }
    if (entry.firstWaiters.isNotEmpty) {
      final waiters = List.of(entry.firstWaiters);
      entry.firstWaiters.clear();
      _markDelivered(entry, e);
      for (final w in waiters) {
        w.complete(e);
      }
    }
    if (entry.serverWaiters.isNotEmpty && (entry.synced || entry.syncFailed)) {
      _answerServerWaiters(entry, fromServer: entry.synced);
    }
    _maybeClose(entry);
  }

  void _markDelivered(_Entry<E> entry, E e) {
    entry.delivered = true;
    entry.deliveredValue = valueOf(e);
  }

  void _answerServerWaiters(_Entry<E> entry, {required bool fromServer}) {
    if (!entry.hasValue) return; // answered by the next event
    final waiters = List.of(entry.serverWaiters);
    entry.serverWaiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) {
        w.complete(FreshOutcome(entry.latest as E, fromServer: fromServer));
      }
    }
  }

  void _requestSync(_Entry<E> entry) {
    if (entry.syncRequested || !entry.hasValue) return;
    entry.syncRequested = true;
    _barrierAfterNow().then((ok) {
      if (entry.closed) return;
      if (ok) {
        entry.synced = true;
        _answerServerWaiters(entry, fromServer: true);
      } else {
        entry.syncFailed = true;
        _answerServerWaiters(entry, fromServer: false);
      }
      _maybeClose(entry);
    });
  }

  void _maybeClose(_Entry<E> entry) {
    if (entry.closed) return;
    if (entry.holds > 0 ||
        entry.firstWaiters.isNotEmpty ||
        entry.serverWaiters.isNotEmpty) {
      return;
    }
    if (entry.synced || entry.lingerExpired) _close(entry);
  }

  void _close(_Entry<E> entry) {
    if (entry.closed) return;
    entry.closed = true;
    entry.lingerTimer?.cancel();
    entry.lingerTimer = null;
    entry.sub?.cancel();
    entry.sub = null;
    if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
  }

  void _fail(_Entry<E> entry, Object error, StackTrace st) {
    if (entry.closed) return;
    final first = List.of(entry.firstWaiters);
    final server = List.of(entry.serverWaiters);
    entry.firstWaiters.clear();
    entry.serverWaiters.clear();
    _close(entry);
    for (final w in first) {
      w.completeError(error, st);
    }
    for (final w in server) {
      if (!w.isCompleted) w.completeError(error, st);
    }
  }

  // ------------------------------------------------- connection + barrier

  StreamSubscription<bool>? _connSub;
  bool _connected = false;
  Completer<void>? _connectedWaiter;

  void _ensureConnection() {
    if (_connSub != null) return;
    try {
      _connSub = connection().listen((up) {
        _connected = up;
        if (up) {
          _connectedWaiter?.complete();
          _connectedWaiter = null;
        }
      }, onError: (Object e) {
        // Cannot tell: let the barrier itself wait for the server.
        debugPrint('Fresh read: connection state failed: $e');
        _connSub?.cancel();
        _connSub = null;
        _connectedWaiter?.complete();
        _connectedWaiter = null;
      });
    } catch (e) {
      debugPrint('Fresh read: connection state unavailable: $e');
      _connSub = null;
      _connected = true; // fall through to the barrier (bounded by callers)
    }
  }

  Future<void> _whenConnected() {
    _ensureConnection();
    if (_connected) return Future<void>.value();
    return (_connectedWaiter ??= Completer<void>()).future;
  }

  Completer<bool>? _nextBarrier;

  /// Completes true when a barrier read SENT AFTER this call has returned
  /// (false when it failed). Calls within [batchWindow] — and any made while
  /// waiting for the connection — share one barrier read.
  Future<bool> _barrierAfterNow() {
    final pending = _nextBarrier;
    if (pending != null) return pending.future;
    final c = Completer<bool>();
    _nextBarrier = c;
    _ensureConnection();
    Timer(batchWindow, () async {
      await _whenConnected();
      // From here, later requests need a later barrier: this one is sent
      // now, after every listener that joined it was attached.
      if (identical(_nextBarrier, c)) _nextBarrier = null;
      if (c.isCompleted) return; // reset by debugReset
      Future<void> read;
      try {
        read = barrier();
      } catch (e) {
        debugPrint('Fresh read: barrier read failed: $e');
        c.complete(false);
        return;
      }
      read.then((_) {
        if (!c.isCompleted) c.complete(true);
      }, onError: (Object e) {
        debugPrint('Fresh read: barrier read failed: $e');
        if (!c.isCompleted) c.complete(false);
      });
    });
    return c.future;
  }
}

// ------------------------------------------------------------- Firebase

FreshReadEngine<Query, DatabaseEvent> _firebaseEngine() =>
    FreshReadEngine<Query, DatabaseEvent>(
      valueEvents: (q) => q.onValue,
      keyOf: (q) {
        assert(q is DatabaseReference,
            'fresh reads support plain references only (see freshShareKey)');
        return freshShareKey(q.path,
            plainRef: q is DatabaseReference, identity: q);
      },
      valueOf: (e) => e.snapshot.value,
      onAnyNewer: (key, e) => FreshReads._dispatchNewer(key, e.snapshot.value),
      barrier: () async {
        // push() only makes a new unique key on the phone; nothing is
        // written. The literal node name keeps the rules-contract scan
        // (functions/src/rules_contract.test.ts) aware of it.
        final child = FirebaseDatabase.instance.ref('SyncBarrier').push();
        await child.once();
      },
      connection: () => FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .map((e) => e.snapshot.value == true),
    );

/// The app's fresh-read engine and its seams.
class FreshReads {
  FreshReads._();

  static FreshReadEngine<Query, DatabaseEvent>? _engine;
  static FreshReadEngine<Query, DatabaseEvent> get engine =>
      _engine ??= _firebaseEngine();

  /// Test seam: answers [serverFirstValue] by path (null = real).
  @visibleForTesting
  static Future<FreshValue> Function(String path)? serverFirstValueOverride;

  /// Test seam: answers [refreshingValue] by path (null = real).
  @visibleForTesting
  static Future<Object?> Function(String path)? refreshingValueOverride;

  static final Map<String, List<void Function(Object? value)>> _exact = {};
  static final List<(String, void Function(String path, Object? value))>
      _under = [];

  /// Calls [callback] with the newer value when a lingering refreshing
  /// listener on [path] receives a value different from the one last handed
  /// out (drop/refill a session cache, repaint an open screen). Returns the
  /// remover. Paths are compared normalized ([normalizeFreshPath]).
  static VoidCallback onNewer(
      String path, void Function(Object? value) callback) {
    final key = normalizeFreshPath(path);
    final list = _exact.putIfAbsent(key, () => []);
    list.add(callback);
    return () {
      list.remove(callback);
      if (list.isEmpty && identical(_exact[key], list)) _exact.remove(key);
    };
  }

  /// [onNewer] for every path under [prefix] (e.g. `PublicProfiles/`,
  /// `Futsal/`): [callback] gets the normalized path and the newer value.
  static VoidCallback onNewerUnder(
      String prefix, void Function(String path, Object? value) callback) {
    final p = normalizeFreshPath(prefix);
    final entry = (p, callback);
    _under.add(entry);
    return () => _under.remove(entry);
  }

  /// Number of registered newer-value callbacks (leak checks in tests).
  @visibleForTesting
  static int get debugNewerCallbackCount =>
      _exact.values.fold(0, (n, l) => n + l.length) + _under.length;

  static void _dispatchNewer(String path, Object? value) {
    final key = normalizeFreshPath(path);
    for (final cb in List.of(_exact[key] ?? const [])) {
      try {
        cb(value);
      } catch (e) {
        debugPrint('Fresh read $key: onNewer callback failed: $e');
      }
    }
    for (final (prefix, cb) in List.of(_under)) {
      if (prefix.isEmpty || key == prefix || key.startsWith('$prefix/')) {
        try {
          cb(key, value);
        } catch (e) {
          debugPrint('Fresh read $key: onNewerUnder callback failed: $e');
        }
      }
    }
  }

  /// Test seam: reports [value] as newer at [path], as a lingering listener
  /// would.
  @visibleForTesting
  static void debugReportNewer(String path, Object? value) =>
      _dispatchNewer(path, value);

  /// Cancels lingering listeners on per-user paths ([isUserScopedPath]).
  /// Called at sign-out (session_sign_out.dart).
  static void cancelUserScoped() => _engine?.cancelWhere(isUserScopedPath);
}

/// DISPLAY read: the first event at once (the saved copy when there is one);
/// the listener stays shared until the server has answered or [kLingerFor].
Future<DatabaseEvent> refreshingOnce(Query q) =>
    FreshReads.engine.refreshing(q);

/// DECISION read: the server's value when online (bounded by [timeout]),
/// else the saved copy with `fromServer: false`; with neither, a
/// [TimeoutException].
Future<FreshResult> serverFirstOnce(Query q,
    {Duration timeout = kRevealReadTimeout}) async {
  final out = await FreshReads.engine.serverFirst(q, timeout: timeout);
  return FreshResult(out.event.snapshot, fromServer: out.fromServer);
}

/// [refreshingOnce] by path, answering just the value (testable through
/// [FreshReads.refreshingValueOverride]).
Future<Object?> refreshingValue(String path) async {
  final key = normalizeFreshPath(path);
  final override = FreshReads.refreshingValueOverride;
  if (override != null) return override(key);
  return (await refreshingOnce(FirebaseDatabase.instance.ref(key)))
      .snapshot
      .value;
}

/// [serverFirstOnce] by path, answering just the value (testable through
/// [FreshReads.serverFirstValueOverride]).
Future<FreshValue> serverFirstValue(String path,
    {Duration timeout = kRevealReadTimeout}) async {
  final key = normalizeFreshPath(path);
  final override = FreshReads.serverFirstValueOverride;
  if (override != null) return override(key);
  final r = await serverFirstOnce(FirebaseDatabase.instance.ref(key),
      timeout: timeout);
  return FreshValue(r.snapshot.value, fromServer: r.fromServer);
}
