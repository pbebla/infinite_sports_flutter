// The in-season Infinite Fantasy home banner (P6, spec §10/§10b hub
// entries): a slim strip on the front page's league tab — the shared
// FantasyBanner brand surface with the logo, "Fantasy is live — set your
// squad" and a deadline countdown chip while the current gameweek is open
// under the automatic lock. Tapping opens the hub (the league entry card's
// push). Shown while `Fantasy/<sport>/<season>/Config` exists — the same
// live stream gate as the league page's Fantasy tab — and gone otherwise,
// so the front page carries NO per-user state (not dismissible by design).
//
// Once the league's own `Finished` flag is set (FantasySeasonFinishedFeed —
// Opus audit Minor 8) the copy reads "Season over — see the final
// standings", the deadline chip goes and a tap opens the hub on
// Leaderboards (Overall). The banner waits for that flag too (session-cached,
// a failing feed = not finished), so its copy never flips after it shows.
//
// "Set your squad" only while saving is actually possible (owner's wording
// 2026-11-04): once the current gameweek locks the banner says so — "GW2
// locked · games today" on match day (league time), plain "GW2 locked" the
// next morning until the next week opens (the hub's own chip), and "Squads
// locked by the league" under the owner's lock override.
//
// Once that locked week has SETTLED (finalize ran) the title is his final
// result instead — `GW2 final · 34 pts · #5`, exactly My Team's settled strip
// (finalBannerLine) — from match night until the next week opens. His own
// `History/<gw>/<uid>` and Overall row are listened to only while the week is
// locked (one node each), and they join the first reveal (bounded 2 s) with
// the schedule, so a cold open never shows "set your squad" or "locked" first.
//
// Live everywhere (Task 6): while the manager's gameweek is being played the
// banner reads `GW3 live · 34 pts · #5` (his own row of the live board —
// liveBannerLine) with the shared LIVE pill in place of "Fantasy is live — set
// your squad" (the squad is locked then). The live feed joins the banner's
// reveal (bounded at the global 2 s), so the first frame the banner shows
// already carries the live line — it never pops in or flips afterwards. A
// manager with no squad scored this week, nobody signed in, no live week or a
// week the owner VOIDED (the Voided set — the live board says 0 pts · #1 for
// everyone then) leaves the banner exactly as it was; a Voided set that is
// unknown (failed, or silent past the bound) never calls a week live.
// Subscribed only with someone signed in.
//
// House rules: streams only; theme-safe both modes via the single-sourced
// brand surface; text wraps, never underlined; the countdown line is
// INFORMATION (a 60s refresh, nothing animates per tick, timer cancelled on
// dispose — reconnects can't replay anything).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/answer_gate.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/league_time.dart'
    show lockInstantUtc;
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart'
    show finalBannerLine, liveBannerLine;
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

/// The season-over call to action, shared by this banner ("Season over —
/// see the final standings") and the Search hub's Fantasy card.
const String kFantasySeasonOverCta = 'see the final standings';

/// The neutral line for a season whose state could not be read (fix round
/// 1, I2 — a failed read is not a fact): claims neither "live" nor "over".
String fantasySeasonNeutralLine(String sport, String season) =>
    '$sport Season $season · Open Infinite Fantasy';

/// The Search hub's Fantasy card line (release report #16, fix round 1 I2):
/// "is live" only while the league season is RUNNING and "is over" only once
/// it is OVER — both read from the SAME [FantasySeasonFinishedFeed.phase]
/// this banner uses — and the neutral line while that is unknown.
String fantasyEntryCardSubtitle(
        String sport, String season, FantasySeasonPhase phase) =>
    switch (phase) {
      FantasySeasonPhase.over =>
        '$sport Season $season is over — $kFantasySeasonOverCta',
      FantasySeasonPhase.running =>
        'Pick your seven — $sport Season $season is live',
      FantasySeasonPhase.unknown => fantasySeasonNeutralLine(sport, season),
    };

class FantasyHomeBanner extends StatefulWidget {
  const FantasyHomeBanner({
    super.key,
    required this.sport,
    required this.season,
    this.configStates,
    this.gameweeksStates,
    this.finishedStates,
    this.liveStates,
    this.voidedStates,
    this.historyWeekFor,
    this.overallStates,
    this.signedInUid,
    this.onOpen,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// Test seams — null = the real FantasyService streams.
  final Stream<FantasyConfigState?>? configStates;
  final Stream<List<Gameweek>>? gameweeksStates;

  /// The league's `Finished` flag (`FantasyService.watchLeagueSeasonFinished`).
  final Stream<bool>? finishedStates;

  /// Replaces `FantasyLiveFeed.watch` (the season's live gameweek).
  final Stream<FantasyLiveState>? liveStates;

  /// Replaces `FantasyService.watchVoidedWeeks` (the owner-voided weeks).
  final Stream<Set<int>>? voidedStates;

  /// Replace `FantasyService.watchHistoryWeek` / `watchOverallStanding` (his
  /// own settled week and Overall row, for the final line).
  final Stream<HistoryWeek?> Function(int week)? historyWeekFor;
  final Stream<OverallStanding?>? overallStates;

  /// The signed-in uid (null / empty = nobody); null seam = FirebaseAuth.
  final String? Function()? signedInUid;

  /// Test seam replacing the real `Navigator.push(... FantasyHubPage ...)`:
  /// receives the tab the hub would open on.
  final void Function(FantasyHubTab tab)? onOpen;

  /// Test seam: injected clock. Production leaves it null (real UTC now).
  final DateTime Function()? nowUtc;

  @override
  State<FantasyHomeBanner> createState() => _FantasyHomeBannerState();
}

class _FantasyHomeBannerState extends State<FantasyHomeBanner> {
  /// Config → schedule gameweeks (the shared wiring: lock-hour resubscribe,
  /// a removed Config clears the schedule, errors logged with the last good
  /// value kept — offline before any config, the banner stays hidden).
  late final FantasyScheduleFeed<Object> _schedule = FantasyScheduleFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyHomeBanner',
    onChanged: () {
      _syncFinalWeek();
      if (mounted) setState(() {});
    },
    configStates: widget.configStates,
    gameweekStates: widget.gameweeksStates,
    nowUtc: widget.nowUtc,
  );

  /// The league's season-over flag (shared feed, session-cached): the
  /// banner shows only once it has answered, so "Fantasy is live" never
  /// flips to "Season over" in front of the fan.
  late final FantasySeasonFinishedFeed _seasonFinished =
      FantasySeasonFinishedFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyHomeBanner',
    onChanged: () {
      if (mounted) setState(() {});
    },
    finishedStates: widget.finishedStates,
  );
  Timer? _ticker;

  // ── The live gameweek (joins the reveal) ──────────────────────────────
  StreamSubscription<FantasyLiveState>? _liveSub;
  StreamSubscription<Set<int>>? _voidedSub;
  FantasyLiveState _live = FantasyLiveState.none;

  /// The owner-voided weeks, and whether a REAL answer has said so (a failed
  /// or silent feed leaves them unknown — then no week is called live).
  Set<int> _voided = const {};
  bool _voidedKnown = false;

  /// The live feed and the Voided set join the banner's single reveal: ready
  /// once each has answered (or failed, or there is nobody to ask — nothing is
  /// registered then), or once the 2 s global bound passed with one of them
  /// still silent (show without; a late value lands in place).
  late final AnswerGate _liveGate = AnswerGate(
    owner: 'FantasyHomeBanner',
    onChanged: () {
      // Both answered: the bound has nothing left to bound.
      _liveGate.settle();
      if (mounted) setState(() {});
    },
  );
  String? _uid;

  bool get _liveReady => _liveGate.ready;

  // ── The settled week's final line (joins the first reveal) ────────────
  int? _finalWeek; // the locked week listened to (null = none)
  AnswerGate? _finalGate;
  StreamSubscription<HistoryWeek?>? _historySub;
  StreamSubscription<OverallStanding?>? _overallSub;
  HistoryWeek? _history;
  OverallStanding? _overall;

  /// The banner has shown once: later waits never hide it again.
  bool _revealed = false;

  /// The schedule's first answer joins the first reveal, bounded like the
  /// live feeds: a silent schedule never holds the banner back.
  Timer? _scheduleWait;
  bool _scheduleWaitPassed = false;

  FantasyConfigState? get _config => _schedule.config;
  List<Gameweek> get _gameweeks => _schedule.gameweeks ?? const [];

  @override
  void initState() {
    super.initState();
    _schedule.start();
    _seasonFinished.start();
    _startLive();
    _syncFinalWeek();
    _scheduleWait = Timer(kLiveJoinWait, () {
      _scheduleWaitPassed = true;
      if (mounted && _schedule.gameweeks == null) setState(() {});
    });
    // 60s refresh keeps the countdown text honest (information, not
    // decoration — no per-tick animation); cancelled in dispose.
    _ticker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _config != null) {
        _syncFinalWeek(); // the lock / the next week opening moves it
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _schedule.dispose();
    _seasonFinished.dispose();
    _ticker?.cancel();
    _liveGate.dispose();
    _liveSub?.cancel();
    _voidedSub?.cancel();
    _cancelFinal();
    _scheduleWait?.cancel();
    super.dispose();
  }

  /// Best-effort (utility.dart convention): widget tests never touch
  /// FirebaseAuth — no seam means "signed out", never a throw.
  String? _signedInUid() {
    final seam = widget.signedInUid;
    if (seam != null) return seam();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Subscribes to the live gameweek, only with someone signed in (the line
  /// is HIS row). Nobody to ask = nothing to wait for. A failing feed is
  /// logged and counts as answered (the banner shows as before); the 2 s
  /// bound keeps a silent one from holding the banner back, and a late value
  /// lands in place.
  void _startLive() {
    final uid = _signedInUid();
    if (uid == null || uid.isEmpty) return;
    _uid = uid;
    _liveGate.start();
    _liveSub = _liveGate.listen<FantasyLiveState>(
      'live feed',
      () =>
          widget.liveStates ?? FantasyLiveFeed.watch(widget.sport, widget.season),
      onData: (state) => _live = state,
    );
    // An error leaves the set UNKNOWN, not "none voided": no week is called
    // live without it.
    _voidedSub = _liveGate.listen<Set<int>>(
      'voided feed',
      () =>
          widget.voidedStates ??
          FantasyService.watchVoidedWeeks(widget.sport, widget.season),
      onData: (weeks) {
        _voided = weeks;
        _voidedKnown = true;
      },
    );
    // A feed that could not even be created already answered.
    _liveGate.settle();
  }

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  void _openHub() {
    // Season over: straight to the final standings.
    final tab = _seasonFinished.finished
        ? FantasyHubTab.leaderboards
        : FantasyHubTab.myTeam;
    final open = widget.onOpen;
    if (open != null) {
      open(tab);
      return;
    }
    // Root navigator, matching the front page's other header pushes.
    Navigator.push(
      mainContext ?? context,
      MaterialPageRoute(
        builder: (_) => FantasyHubPage(
            sport: widget.sport, season: widget.season, initialTab: tab),
      ),
    );
  }

  /// The current gameweek while it is LOCKED under the automatic lock (its
  /// deadline → the next week opening); null otherwise.
  Gameweek? _lockedGameweek() {
    if (_config?.lockOverride != FantasyLockOverride.auto) return null;
    final now = _now;
    final gw = currentGameweek(_gameweeks, now);
    return gw != null && gw.statusAt(now) == GameweekStatus.locked ? gw : null;
  }

  /// Listens to his own `History/<gw>/<uid>` and Overall row while the
  /// current gameweek is locked and someone is signed in — the only time the
  /// final line can show. A week change drops the old week's numbers at once;
  /// an error keeps the last good value (a final score stays true).
  void _syncFinalWeek() {
    final uid = _uid;
    final week = uid == null ? null : _lockedGameweek()?.number;
    if (week == _finalWeek) return;
    _cancelFinal();
    _finalWeek = week;
    if (uid == null || week == null) return;
    late final AnswerGate gate;
    gate = AnswerGate(
      owner: 'FantasyHomeBanner',
      onChanged: () {
        gate.settle();
        if (mounted) setState(() {});
      },
    );
    _finalGate = gate..start();
    _historySub = gate.listen<HistoryWeek?>(
      'history feed',
      () =>
          widget.historyWeekFor?.call(week) ??
          FantasyService.watchHistoryWeek(
              widget.sport, widget.season, uid, week),
      onData: (v) => _history = v,
    );
    _overallSub = gate.listen<OverallStanding?>(
      'overall feed',
      () =>
          widget.overallStates ??
          FantasyService.watchOverallStanding(
              widget.sport, widget.season, uid),
      onData: (v) => _overall = v,
    );
    // A feed that could not even be created already answered.
    gate.settle();
  }

  void _cancelFinal() {
    _historySub?.cancel();
    _overallSub?.cancel();
    _historySub = null;
    _overallSub = null;
    _finalGate?.dispose();
    _finalGate = null;
    _history = null;
    _overall = null;
  }

  /// "GW3 locks in 2d 4h" while the current gameweek is OPEN under the
  /// automatic lock; null in every other state (the banner stays slim) —
  /// and always once the season is over.
  String? _deadlineText() {
    final config = _config;
    if (config == null ||
        config.lockOverride != FantasyLockOverride.auto ||
        _seasonFinished.finished) {
      return null;
    }
    final now = _now;
    final gw = currentGameweek(_gameweeks, now);
    if (gw == null || gw.statusAt(now) != GameweekStatus.open) return null;
    return 'GW${gw.number} locks in '
        '${formatCountdown(gw.lockUtc.difference(now))}';
  }

  /// The title whenever there is no live line: never "set your squad" while
  /// the squad can't be saved.
  String _restingTitle() {
    if (_seasonFinished.finished) {
      return 'Season over — $kFantasySeasonOverCta';
    }
    // "Fantasy is live" only when the league flag SAYS the season is
    // running; a failed read gets the neutral line (fix round 1, I2).
    final setYourSquad =
        _seasonFinished.phase == FantasySeasonPhase.running
            ? 'Fantasy is live — set your squad'
            : fantasySeasonNeutralLine(widget.sport, widget.season);
    switch (_config?.lockOverride ?? FantasyLockOverride.auto) {
      case FantasyLockOverride.open:
        return setYourSquad;
      case FantasyLockOverride.locked:
        return 'Squads locked by the league';
      case FantasyLockOverride.auto:
        final gw = _lockedGameweek();
        if (gw == null) return setYourSquad;
        // Hour 24 = the midnight that ends match day, league time.
        final matchDay = _now.isBefore(lockInstantUtc(gw.date, hour: 24));
        return matchDay
            ? 'GW${gw.number} locked · games today'
            : 'GW${gw.number} locked';
    }
  }

  @override
  Widget build(BuildContext context) {
    // The FIRST reveal also waits for the schedule (the title depends on it)
    // and a locked week's final numbers (each bounded 2 s), so its first frame
    // already says the right thing; after it, late values land in place.
    final firstFrameReady =
        (_schedule.gameweeks != null || _scheduleWaitPassed) &&
            (_finalGate?.ready ?? true);
    if (_config == null ||
        !_seasonFinished.ready ||
        !_liveReady ||
        (!_revealed && !firstFrameReady)) {
      return const SizedBox.shrink();
    }
    _revealed = true;
    final accent = FantasyBanner.accent(context);
    final finished = _seasonFinished.finished;
    // The live line (never once the season is over): his row of the live
    // board, null = the banner as before.
    final liveLine = finished || !_voidedKnown
        ? null
        : liveBannerLine(live: _live, uid: _uid, voidedWeeks: _voided);
    // Once the locked week has settled: his final result (never over a live
    // line, never once the season is over, never with the Voided set unknown).
    final finalWeek = _finalWeek;
    final finalLine =
        liveLine != null || finished || !_voidedKnown || finalWeek == null
            ? null
            : finalBannerLine(
                week: finalWeek,
                uid: _uid,
                history: _history,
                overall: _overall,
                voidedWeeks: _voided);
    final deadline = liveLine == null ? _deadlineText() : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 4, 19, 0),
      child: Container(
        decoration: FantasyBanner.cardDecoration(context, radius: 16),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const ValueKey('fantasy_home_banner'),
            borderRadius: BorderRadius.circular(16),
            onTap: _openHub,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  FantasyBanner.logo(
                    context,
                    height: 30,
                    backdropPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (liveLine != null)
                          // The pill, then the line; the line wraps under the
                          // pill when the strip is narrow.
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              const FantasyLivePill(),
                              Text(
                                liveLine,
                                key: const ValueKey(
                                    'fantasy_home_banner_title'),
                                softWrap: true,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  color: FantasyBanner.foreground(context),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            finalLine ?? _restingTitle(),
                            key: const ValueKey('fantasy_home_banner_title'),
                            // Wraps, never underlined (house rules).
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: FantasyBanner.foreground(context),
                            ),
                          ),
                        if (deadline != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            key: const ValueKey(
                                'fantasy_home_banner_deadline'),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: accent.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined,
                                    size: 13, color: accent),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    deadline,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          FantasyBanner.foreground(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 20,
                      color: FantasyBanner.foregroundMuted(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
