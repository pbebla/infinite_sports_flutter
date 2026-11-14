// Newer-value followers for screens (fresh reads; second review, Minor 1).
//
// A screen that follows a path with FreshReads.onNewer must register only
// while it is mounted and must remove the callback in dispose. Registering
// after an `await` without a mounted check leaked the callback (and the
// disposed State it captures) for the app's lifetime. This mixin makes the
// pattern impossible to get wrong: [followNewer] / [followNewerUnder] do
// nothing once the State is unmounted, and every registration is removed
// in dispose.

import 'package:flutter/widgets.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

mixin FreshFollowers<T extends StatefulWidget> on State<T> {
  final Map<String, VoidCallback> _followers = {};

  /// Follows newer values at [path] (exact) under [id] — a second call with
  /// the same id replaces the first. No-op when unmounted.
  void followNewer(String id, String path, void Function(Object? value) cb) {
    if (!mounted) return;
    _followers.remove(id)?.call();
    _followers[id] = FreshReads.onNewer(path, cb);
  }

  /// [followNewer] for every path under [prefix].
  void followNewerUnder(
      String id, String prefix, void Function(String path, Object? value) cb) {
    if (!mounted) return;
    _followers.remove(id)?.call();
    _followers[id] = FreshReads.onNewerUnder(prefix, cb);
  }

  @override
  void dispose() {
    for (final stop in _followers.values) {
      stop();
    }
    _followers.clear();
    super.dispose();
  }
}

/// Runs an in-place refresh so that a newer value arriving WHILE one is in
/// flight is never dropped (second review, Minor 4): it queues exactly one
/// more run after the current one (coalesced — any number of arrivals
/// during a run make one extra run). Optional [minGap] spaces runs out (a
/// live game must not make a screen thrash).
class CoalescedRefresh {
  CoalescedRefresh(this._run, {this.minGap = Duration.zero});

  final Future<void> Function() _run;
  final Duration minGap;
  bool _running = false;
  bool _queued = false;
  bool _disposed = false;
  DateTime? _lastStart;

  /// Asks for a refresh: now, or one queued run after the current one.
  void request() {
    if (_disposed) return;
    if (_running) {
      _queued = true;
      return;
    }
    _start();
  }

  Future<void> _start() async {
    _running = true;
    try {
      final last = _lastStart;
      if (last != null && minGap > Duration.zero) {
        final wait = minGap - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      if (_disposed) return;
      _lastStart = DateTime.now();
      await _run();
    } catch (_) {
      // The refresh keeps what is on screen on failure.
    } finally {
      _running = false;
    }
    if (_queued && !_disposed) {
      _queued = false;
      _start();
    }
  }

  /// Whether a run is in flight (tests).
  bool get running => _running;

  void dispose() => _disposed = true;
}
