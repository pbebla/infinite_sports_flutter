// One-shot reads that gate a reveal must be BOUNDED (Opus audit item 6).
//
// RTDB `once()` on a cold OFFLINE client never completes — it waits for a
// connection that may never come — so a screen whose skeleton waits on one
// sits on that skeleton forever while every stream (which may have answered
// from the disk cache) is long done. Every one-shot read a reveal gate (or a
// shared in-flight memo) waits on goes through [BoundedRead.bounded]: after
// [kRevealReadTimeout] with no answer it is logged with debugPrint and the
// caller's degrade value takes over — or, with no `orElse`, a
// [TimeoutException] is thrown for callers whose failure path already means
// "unknown — ask again next time".
//
// Live streams (onValue) are not bounded here: their gates already open on
// an error, and the disk cache answers them offline.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long a one-shot read that gates a reveal may stay unanswered.
const Duration kRevealReadTimeout = Duration(seconds: 8);

String _describe(Duration d) => d.inMilliseconds % 1000 == 0
    ? '${d.inSeconds}s'
    : '${d.inMilliseconds}ms';

extension BoundedRead<T> on Future<T> {
  /// This read, or — once [timeout] passes with no answer — [orElse]'s
  /// value, logged as `<what>: no answer after 8s — degrading`. Without
  /// [orElse] the timeout throws a [TimeoutException] (logged as
  /// `… — failing`). A late answer (or error) after the timeout is ignored.
  Future<T> bounded(
    String what, {
    FutureOr<T> Function()? orElse,
    Duration timeout = kRevealReadTimeout,
  }) {
    // Hand-rolled rather than Future.timeout: a `Future<Never>` (an
    // `async => throw` read) seen as `Future<T>` would reject a typed
    // onTimeout callback at runtime.
    final result = Completer<T>();
    final timer = Timer(timeout, () {
      if (result.isCompleted) return;
      final after = _describe(timeout);
      if (orElse == null) {
        debugPrint('$what: no answer after $after — failing');
        result.completeError(
            TimeoutException('$what: no answer after $after', timeout));
        return;
      }
      debugPrint('$what: no answer after $after — degrading');
      try {
        result.complete(orElse());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    then((T value) {
      if (result.isCompleted) return;
      timer.cancel();
      result.complete(value);
    }, onError: (Object e, StackTrace s) {
      if (result.isCompleted) return; // a late error is ignored
      timer.cancel();
      result.completeError(e, s);
    });
    return result.future;
  }
}
