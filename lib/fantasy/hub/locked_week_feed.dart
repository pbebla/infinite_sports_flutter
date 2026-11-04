// The locked My Team's feed (live everywhere, Task 5): the five SMALL streams
// the locked week needs, subscribed only while a week is locked.
//
//   • the season's live gameweek (FantasyLiveFeed: Meta + Board + Players),
//   • the manager's own `Live/Squads/<uid>` (FantasyService.watchLiveSquad),
//   • the squad that was LOCKED: his own `PublishedPicks/<gw>/<uid>`
//     (watchPublishedPicksWeek — one node, NEVER the whole PublishedPicks),
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
//   • [LockedWeekSources.complete] — every stream answered AND none failed (a
//     stream that failed counts again once it delivers). An empty source from
//     an incomplete load says nothing, so the strip never claims "waiting for
//     kickoff" on it.
//   • no locked week (editing open) or nobody signed in: nothing is subscribed
//     and nothing gates (signed out reads nothing, so it is not complete).
//   • a week change cancels everything and drops the previous week's data at
//     once (never last week's squad under this week's title); the services'
//     session seeds make the resubscription instant.
//   • [setWeek] never notifies when asked not to (initState).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/answer_gate.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
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
    this.publishedPicksFor,
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
  final Stream<FantasySquad?> Function(int week)? publishedPicksFor;
  final Stream<OverallStanding?>? overallStates;

  /// How long [ready] waits for the streams' first answers.
  final Duration liveWait;

  int? _week;
  bool _disposed = false;

  FantasyLiveState _live = FantasyLiveState.none;
  LiveSquad? _liveSquad;
  HistoryWeek? _history;
  FantasySquad? _published;
  OverallStanding? _overall;

  /// This week's subscription's gate (AnswerGate — the shared defensive
  /// listen): which streams have answered (data or error), which ones' LAST
  /// event was a failure (a later value clears it), and the [liveWait] bound.
  /// A fresh one per subscribed week; null while nothing is subscribed.
  AnswerGate? _gate;

  final List<StreamSubscription<Object?>> _subs = [];

  /// The locked week being listened to (null = none).
  int? get week => _week;

  /// The hub's reveal gate: nothing to wait for, or every stream has answered
  /// (or the bound passed).
  bool get ready => _week == null || (_gate?.ready ?? true);

  /// What the streams hold right now (see [resolveLockedWeek]).
  LockedWeekSources get sources => LockedWeekSources(
        live: _live,
        liveSquad: _liveSquad,
        history: _history,
        published: _published,
        overall: _overall,
        complete: (_gate?.allAnswered ?? false) && !_gate!.anyFailed,
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
    _published = null;
    _overall = null;
    if (week != null) _subscribe(week);
    if (notify) onChanged();
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }

  void _cancel() {
    _gate?.dispose();
    _gate = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _changed() {
    if (_disposed) return;
    // Everything answered in time: the bound has nothing left to bound.
    _gate?.settle();
    onChanged();
  }

  void _subscribe(int week) {
    // Signed out: no uid, so no own nodes to read — nothing to wait for.
    final me = uid();
    if (me == null) return;
    // One gate per subscribed week, bounded at [liveWait] (its clock stopped
    // by [AnswerGate.settle] once all five answered). A stream that errors —
    // or cannot even be created (no Firebase app in a widget test; answered
    // at once WITHOUT notifying: the caller reads [ready] right after
    // [setWeek], and initState must never be notified) — is logged and
    // counts as answered with no data, but as FAILED until it delivers a
    // value (the last good value, if any, stays).
    final gate = _gate = AnswerGate(
      onChanged: _changed,
      bound: liveWait,
      owner: 'FantasyLockedWeekFeed',
    )..start();
    void open<T>(
        String what, Stream<T> Function() make, void Function(T) store) {
      final sub = gate.listen<T>(what, make, onData: store);
      if (sub != null) _subs.add(sub);
    }

    open<FantasyLiveState>(
      'live feed',
      () => liveStates ?? FantasyLiveFeed.watch(sport, season),
      (v) => _live = v,
    );
    open<LiveSquad?>(
      'live squad feed',
      () => liveSquadStates ?? FantasyService.watchLiveSquad(sport, season, me),
      (v) => _liveSquad = v,
    );
    open<FantasySquad?>(
      'published picks feed',
      () =>
          publishedPicksFor?.call(week) ??
          FantasyService.watchPublishedPicksWeek(sport, season, me, week),
      (v) => _published = v,
    );
    open<HistoryWeek?>(
      'history week feed',
      () =>
          historyWeekFor?.call(week) ??
          FantasyService.watchHistoryWeek(sport, season, me, week),
      (v) => _history = v,
    );
    open<OverallStanding?>(
      'overall standing feed',
      () =>
          overallStates ??
          FantasyService.watchOverallStanding(sport, season, me),
      (v) => _overall = v,
    );
    // A stream that could not even be created already answered.
    gate.settle();
  }
}
