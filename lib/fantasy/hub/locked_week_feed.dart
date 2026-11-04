// The locked My Team's feed (live everywhere, Task 5): the four SMALL streams
// the locked week needs, subscribed only while a week is locked.
//
//   • the season's live gameweek (FantasyLiveFeed: Meta + Board + Players),
//   • the manager's own `Live/Squads/<uid>` (FantasyService.watchLiveSquad),
//   • his own `History/<gw>/<uid>` (watchHistoryWeek — one node, NEVER the
//     whole History),
//   • his own `Leaderboards/Overall/<uid>` (watchOverallStanding).
//
// Plain Dart (no widgets), like FantasyScheduleFeed: the owner (the hub) passes
// `onChanged` (its setState), calls [setWeek] whenever the locked week may have
// moved and [dispose]. Rules it keeps for the hub's reveal gate:
//
//   • [ready] — every subscribed stream has answered (an ERROR counts as an
//     answer, "no data": a failing feed never holds the screen), so the first
//     painted frame after the reveal already carries live numbers (no
//     "waiting for kickoff" flipping to live); bounded at [liveWait] (the
//     global 2 s live bound) — after it the hub shows what it has and a late
//     value lands in place.
//   • no locked week (editing open) or nobody signed in: nothing is subscribed
//     and nothing gates.
//   • a week change cancels everything and drops the previous week's data at
//     once (never last week's squad under this week's title); the services'
//     session seeds make the resubscription instant.
//   • [setWeek] never notifies when asked not to (initState).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';

class FantasyLockedWeekFeed {
  FantasyLockedWeekFeed({
    required this.sport,
    required this.season,
    required this.uid,
    required this.onChanged,
    this.liveStates,
    this.liveSquadStates,
    this.historyWeekFor,
    this.overallStates,
    this.liveWait = kLiveJoinWait,
  });

  final String sport;
  final String season;

  /// The signed-in user's uid (null = signed out, evaluated at subscription).
  final String? Function() uid;

  /// Something changed: repaint.
  final VoidCallback onChanged;

  // ── Test seams — null = the real FantasyService / FantasyLiveFeed ───────
  final Stream<FantasyLiveState>? liveStates;
  final Stream<LiveSquad?>? liveSquadStates;
  final Stream<HistoryWeek?> Function(int week)? historyWeekFor;
  final Stream<OverallStanding?>? overallStates;

  /// How long [ready] waits for the streams' first answers.
  final Duration liveWait;

  int? _week;
  bool _disposed = false;

  FantasyLiveState _live = FantasyLiveState.none;
  LiveSquad? _liveSquad;
  HistoryWeek? _history;
  OverallStanding? _overall;

  bool _liveAnswered = false;
  bool _squadAnswered = false;
  bool _historyAnswered = false;
  bool _overallAnswered = false;
  bool _boundPassed = false;
  bool _subscribed = false;

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _bound;

  /// The locked week being listened to (null = none).
  int? get week => _week;

  /// The hub's reveal gate: nothing to wait for, or every stream has answered
  /// (or the bound passed).
  bool get ready =>
      _week == null || !_subscribed || _boundPassed || _allAnswered;

  /// What the streams hold right now (see [resolveLockedWeek]).
  LockedWeekSources get sources => LockedWeekSources(
        live: _live,
        liveSquad: _liveSquad,
        history: _history,
        overall: _overall,
      );

  /// Points the feed at locked week [week] (null = editing is open). The same
  /// week again is a no-op; any other week cancels the old streams, clears
  /// their data and subscribes afresh. [notify] false is for initState (no
  /// synchronous onChanged).
  void setWeek(int? week, {bool notify = true}) {
    if (_disposed || week == _week) return;
    _cancel();
    _week = week;
    _live = FantasyLiveState.none;
    _liveSquad = null;
    _history = null;
    _overall = null;
    _liveAnswered =
        _squadAnswered = _historyAnswered = _overallAnswered = false;
    _boundPassed = false;
    _subscribed = false;
    if (week != null) _subscribe(week);
    if (notify) onChanged();
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }

  void _cancel() {
    _bound?.cancel();
    _bound = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  bool get _allAnswered =>
      _liveAnswered && _squadAnswered && _historyAnswered && _overallAnswered;

  /// Everything answered in time: the bound has nothing left to bound.
  void _settleBound() {
    if (!_allAnswered) return;
    _bound?.cancel();
    _bound = null;
  }

  void _changed() {
    if (_disposed) return;
    _settleBound();
    onChanged();
  }

  void _subscribe(int week) {
    // Signed out: no uid, so no own nodes to read — nothing to wait for.
    final me = uid();
    if (me == null) return;
    _subscribed = true;
    _bound = Timer(liveWait, () {
      _bound = null;
      _boundPassed = true;
      if (!_disposed) onChanged();
    });

    _open<FantasyLiveState>(
      'live feed',
      () => liveStates ?? FantasyLiveFeed.watch(sport, season),
      (v) {
        _live = v;
        _liveAnswered = true;
      },
      () => _liveAnswered = true,
    );
    _open<LiveSquad?>(
      'live squad feed',
      () => liveSquadStates ?? FantasyService.watchLiveSquad(sport, season, me),
      (v) {
        _liveSquad = v;
        _squadAnswered = true;
      },
      () => _squadAnswered = true,
    );
    _open<HistoryWeek?>(
      'history week feed',
      () =>
          historyWeekFor?.call(week) ??
          FantasyService.watchHistoryWeek(sport, season, me, week),
      (v) {
        _history = v;
        _historyAnswered = true;
      },
      () => _historyAnswered = true,
    );
    _open<OverallStanding?>(
      'overall standing feed',
      () =>
          overallStates ??
          FantasyService.watchOverallStanding(sport, season, me),
      (v) {
        _overall = v;
        _overallAnswered = true;
      },
      () => _overallAnswered = true,
    );
    // A stream that could not even be created already answered.
    _settleBound();
  }

  /// Listens defensively: a stream that errors, or cannot even be created (no
  /// Firebase app in a widget test), is logged and counts as answered with no
  /// data — the last good value (if any) stays. A failure to create is
  /// answered synchronously WITHOUT notifying (the caller reads [ready]
  /// right after [setWeek]; initState must never be notified).
  void _open<T>(
    String what,
    Stream<T> Function() make,
    void Function(T value) onData,
    void Function() onAnswered,
  ) {
    void log(Object e) => debugPrint('FantasyLockedWeekFeed: $what failed: $e');
    try {
      _subs.add(make().listen((v) {
        if (_disposed) return;
        onData(v);
        _changed();
      }, onError: (Object e) {
        log(e);
        if (_disposed) return;
        onAnswered();
        _changed();
      }));
    } catch (e) {
      log(e);
      onAnswered();
    }
  }
}
