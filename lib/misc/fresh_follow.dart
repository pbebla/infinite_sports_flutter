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
  void followNewerUnder(String id, String prefix,
      void Function(String path, Object? value) cb) {
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
