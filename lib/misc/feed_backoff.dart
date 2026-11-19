// One bounded re-subscribe schedule for live feeds (an RTDB onValue stream
// ends after an error). Moved out of fantasy_schedule_feed.dart (where the
// schedule and season-finished feeds use it) so the team-logo feed
// (team_logos.dart) can share it — fresh-reads plan, Task 4 / Season 16 fan
// review.

import 'dart:async';

/// Back-off between re-subscriptions after a stream error; the feed gives up
/// after the last one (the next screen open / trigger starts afresh).
const List<Duration> kFeedRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

/// One bounded re-subscribe schedule ([kFeedRetryDelays] by default).
class FeedBackoff {
  FeedBackoff(this._disposed, {List<Duration> delays = kFeedRetryDelays})
      : _delays = delays;
  final bool Function() _disposed;
  final List<Duration> _delays;
  int _tries = 0;
  Timer? _timer;

  /// A retry fired and its answer has not come back yet.
  bool _inFlight = false;

  /// A retry is scheduled or waiting for its answer.
  bool get active => _timer != null || _inFlight;

  /// Runs [again] after the next delay, unless the retries are used up.
  void retry(void Function() again) {
    _inFlight = false;
    if (_disposed() || _tries >= _delays.length) return;
    _timer?.cancel();
    _timer = Timer(_delays[_tries++], () {
      _timer = null;
      if (_disposed()) return;
      _inFlight = true;
      again();
    });
  }

  /// A manual / triggered attempt starts now with a fresh back-off.
  void startNow() {
    cancel();
    _tries = 0;
    _inFlight = true;
  }

  /// A real answer arrived: the next failure starts the back-off afresh.
  void reset() {
    _tries = 0;
    _inFlight = false;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _inFlight = false;
  }
}
