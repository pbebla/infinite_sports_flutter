// A reveal gate over a handful of streams (live everywhere, Task 7): the
// screen shows its skeleton until every stream it registered has ANSWERED, then
// reveals once — and never goes back to the skeleton.
//
//   • [expect] registers a stream by name (the same name again is a no-op);
//   • [answer] records its first answer — data OR an error: a failing feed is
//     "no data", it never holds the screen — so the caller reads what it has
//     and treats a failed feed as unknown, never as a fact;
//   • [listen] is THE defensive gated listen (final review: it used to exist
//     four times — the squad viewer, the match tab, the locked-week feed and
//     the home banner): expect → listen → answer on a value, an error or a
//     stream that cannot even be created → repaint. It also says which feeds'
//     last word was a failure ([anyFailed]);
//   • [ready] is true once everything registered has answered, or [bound]
//     after [start] (the global 2 s live bound: a silent feed never keeps the
//     fan on the skeleton; whatever it says later lands in place). An owner
//     that registers every stream up front calls [settle] to stop the bound's
//     clock once everything has answered (no stray timer);
//   • LATCHED: once ready it stays ready, so a stream registered later (a
//     gameweek that locks while the page is open) can never bring the skeleton
//     back.
//
// Plain Dart (no widgets): the owner passes `onChanged` (its setState — called
// when the bound passes and after every answer [listen] delivers), calls
// [start] once and [dispose]. Unit-tested in test/fantasy/answer_gate_test.dart.

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart'
    show kLiveJoinWait;

class AnswerGate {
  AnswerGate({
    required this.onChanged,
    this.bound = kLiveJoinWait,
    this.owner = 'AnswerGate',
  });

  /// Something changed — an answer [listen] delivered, or the bound passed
  /// with a feed still silent: repaint.
  final VoidCallback onChanged;

  /// How long [ready] waits for the first answers.
  final Duration bound;

  /// Who owns the gate, for the failure log (`'<owner>: <name> failed: …'`).
  final String owner;

  final Set<String> _expected = {};
  final Set<String> _answered = {};
  final Set<String> _failed = {};
  Timer? _timer;
  bool _boundPassed = false;
  bool _latched = false;
  bool _disposed = false;

  /// Starts the bound's clock (once).
  void start() {
    if (_timer != null || _disposed) return;
    _timer = Timer(bound, () {
      _timer = null;
      _boundPassed = true;
      if (!_disposed) onChanged();
    });
  }

  /// Everything registered has answered: the bound has nothing left to bound
  /// — stop its clock (no stray timer, no repaint at the bound) and open the
  /// gate for good. A no-op while a stream is still silent. For owners that
  /// register every stream up front (call it after registering, and after
  /// each answer); an owner that may register streams later relies on the
  /// bound instead.
  void settle() {
    if (_expected.isNotEmpty) return;
    _timer?.cancel();
    _timer = null;
    _latched = true;
  }

  /// Registers stream [name]; already registered or answered = no-op.
  void expect(String name) {
    if (_answered.contains(name)) return;
    _expected.add(name);
  }

  /// Stream [name] has answered (data or error).
  void answer(String name) {
    _answered.add(name);
    _expected.remove(name);
  }

  /// Listens to the stream [make] creates as feed [name], defensively — it
  /// never throws:
  ///   • registers [name] ([expect]);
  ///   • a VALUE: [onData] stores it, the feed answers (and is no longer
  ///     failed), [onChanged] repaints;
  ///   • an ERROR: logged, [onError] (e.g. forget what the feed last said —
  ///     omit it to keep the last good value), the feed answers as FAILED
  ///     until its next value, [onChanged] repaints;
  ///   • [make] THROWS (no Firebase app in a widget test): logged, [onError],
  ///     answered as failed at once WITHOUT repainting (initState must never
  ///     be notified) — returns null.
  /// Nothing is delivered once the gate is disposed.
  StreamSubscription<T>? listen<T>(
    String name,
    Stream<T> Function() make, {
    required void Function(T value) onData,
    VoidCallback? onError,
  }) {
    expect(name);
    void fail(Object e) {
      debugPrint('$owner: $name failed: $e');
      onError?.call();
      answer(name);
      _failed.add(name);
    }

    try {
      return make().listen((value) {
        if (_disposed) return;
        onData(value);
        answer(name);
        _failed.remove(name);
        onChanged();
      }, onError: (Object e) {
        if (_disposed) return;
        fail(e);
        onChanged();
      });
    } catch (e) {
      fail(e);
      return null;
    }
  }

  /// Every registered stream has answered (data or error) — unlike [ready],
  /// not opened by the bound and not latched.
  bool get allAnswered => _expected.isEmpty;

  /// Some feed [listen] runs has an error (or failed to start) as its last
  /// word: what it holds is unknown, not a fact.
  bool get anyFailed => _failed.isNotEmpty;

  /// Every registered stream has answered, or the bound passed. Latched.
  bool get ready {
    if (!_latched && (_boundPassed || _expected.isEmpty)) _latched = true;
    return _latched;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
