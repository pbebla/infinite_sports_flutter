// A reveal gate over a handful of streams (live everywhere, Task 7): the
// screen shows its skeleton until every stream it registered has ANSWERED, then
// reveals once — and never goes back to the skeleton.
//
//   • [expect] registers a stream by name (the same name again is a no-op);
//   • [answer] records its first answer — data OR an error: a failing feed is
//     "no data", it never holds the screen — so the caller reads what it has
//     and treats a failed feed as unknown, never as a fact;
//   • [ready] is true once everything registered has answered, or [bound]
//     after [start] (the global 2 s live bound: a silent feed never keeps the
//     fan on the skeleton; whatever it says later lands in place);
//   • LATCHED: once ready it stays ready, so a stream registered later (a
//     gameweek that locks while the page is open) can never bring the skeleton
//     back.
//
// Plain Dart (no widgets): the owner passes `onChanged` (its setState — called
// when the bound passes), calls [start] once and [dispose]. Unit-tested in
// test/fantasy/answer_gate_test.dart.

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart'
    show kLiveJoinWait;

class AnswerGate {
  AnswerGate({required this.onChanged, this.bound = kLiveJoinWait});

  /// The bound has passed: repaint (the screen reveals without the silent
  /// streams).
  final VoidCallback onChanged;

  /// How long [ready] waits for the first answers.
  final Duration bound;

  final Set<String> _expected = {};
  final Set<String> _answered = {};
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
