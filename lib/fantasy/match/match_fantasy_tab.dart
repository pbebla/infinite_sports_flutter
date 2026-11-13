// The league match page's Fantasy tab (P6, spec §11): real-time fantasy
// points earned IN THIS GAME, recomputed live from the streamed game node as
// stats land during capture. Ranked "+6 · Name (DEF)" rows with avatars, the
// viewer's squad members highlighted (accent border + YOURS tag), the
// captain's "×2 applied" math spelled out, present-but-scoreless players
// collapsed under "No returns yet", absent players omitted, and a button to
// the Hub. Every points row opens that player's fantasy profile (round 3;
// this page is OUTSIDE the hub, so the profile offers "Open in Fantasy").
//
// WHAT THE NUMBERS MEAN (see match_fantasy_logic.dart's header): RAW per-game
// engine points with a labelled captain callout — bench weighting, auto-subs,
// vice promotion and the 3/2/1 bonus are WEEKLY concepts the server applies
// at finalize, so the counted week can differ. The footer says so in-app.
//
// LIVE EVERYWHERE (Task 7):
//   (a) the header says LIVE (the shared pill) or FINAL from the game's own
//       status — live and final used to render identically;
//   (b) the viewer's squad for a game is the squad that was LOCKED for the
//       game's gameweek — `PublishedPicks/<gw>/<uid>`, else `History/<gw>/<uid>`
//       — read per week (one small node each, never the whole PublishedPicks
//       or History); `Squads/<uid>` only for a week that has not locked, and a
//       locked week with no locked squad on record has no viewer layer (the
//       logic is match_fantasy_logic.matchViewerSquad). Before, a past game was
//       scored against whatever he had saved since;
//   (c) while the game's gameweek is live, a strip under the header: `Your
//       gameweek so far: {W} pts · #{R}` from his row of the live board (a
//       voided week and an unknown Voided set say nothing);
//   (d) the footnote gains `Bonus, captain and bench counting show on My
//       Team.` — this tab shows RAW per-game points, My Team the counted ones.
// The new feeds (the schedule that places the game in its gameweek, the locked
// squad, the week's record, the live feed, the Voided set) join the tab's
// single reveal through an [AnswerGate]: an error counts as an answer (the
// viewer layer is then simply absent — never a wrong squad), bounded at the
// global 2 s; a late answer lands in place. Signed out: none of it.
//
// House rules: streams only (no RTDB .get()); SINGLE fade reveal once the
// game node + players + squad streams have all landed; theme-safe both modes
// via colorScheme + the shared fantasy accent; names wrap, never underlined;
// glass-navbar bottom clearance; the earning chip's counter animates 250ms
// on a GENUINE increase only — a stream reconnect or page re-push re-delivers
// the same value and never replays the tween (session memory keyed by game;
// only ever fed REAL values — never one worked out before the locked squad
// was known).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/answer_gate.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/widgets/forfeit_chip.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

class MatchFantasyTab extends StatefulWidget {
  const MatchFantasyTab({
    super.key,
    required this.sport,
    required this.season,
    required this.dateKey,
    required this.gameIndex,
    required this.configState,
    required this.rosterNamesByTeam,
    this.gameNodeStates,
    this.playersStates,
    this.squadStates,
    this.onOpenHub,
    this.earningStore,
    this.profileOpener,
    this.gameweekStates,
    this.publishedPicksFor,
    this.historyWeekFor,
    this.liveStates,
    this.voidedStates,
    this.selfUidOverride,
    this.nowUtc,
    this.liveWait = kLiveJoinWait,
  });

  final String sport;
  final String season;
  final String dateKey;
  final int gameIndex;

  /// The live config the match page's tab gate already streams (this tab
  /// only exists while it's non-null, so the page hands the value down).
  final FantasyConfigState configState;

  /// team name -> roster player names, from the match page's Line Ups stream
  /// — the default-present attendance union (spec §8).
  final Map<String, List<String>> rosterNamesByTeam;

  /// Test seams — null = the real FantasyService streams.
  final Stream<Object?>? gameNodeStates;
  final Stream<List<FantasyPlayer>>? playersStates;
  final Stream<FantasySquad?>? squadStates;

  /// Test seam replacing the real `Navigator.push(... FantasyHubPage ...)`.
  final VoidCallback? onOpenHub;

  /// Test seam for the earning chip's session memory; production uses the
  /// app-lifetime [sessionEarnings] so re-pushes never replay the tween.
  final Map<String, int>? earningStore;

  /// Test seam replacing [openFantasyPlayerProfile] (a points row's tap).
  final FantasyProfileOpener? profileOpener;

  // ── Live everywhere (Task 7) — test seams, null = the real feeds ────────

  /// Replaces the config-derived schedule that places the game in its
  /// gameweek (the shared [FantasyScheduleFeed]).
  final Stream<List<Gameweek>>? gameweekStates;

  /// The squad that was LOCKED for a week: `PublishedPicks/<gw>/<uid>`
  /// ([FantasyService.watchPublishedPicksWeek]).
  final Stream<FantasySquad?> Function(int week)? publishedPicksFor;

  /// That week's settled `History/<gw>/<uid>`
  /// ([FantasyService.watchHistoryWeek]) — the locked squad's fallback.
  final Stream<HistoryWeek?> Function(int week)? historyWeekFor;

  /// The season's live gameweek ([FantasyLiveFeed.watch]).
  final Stream<FantasyLiveState>? liveStates;

  /// The season's owner-voided weeks ([FantasyService.watchVoidedWeeks]).
  final Stream<Set<int>>? voidedStates;

  /// '' = signed out (no viewer layer, nothing of his is read).
  final String? selfUidOverride;

  /// The clock (null = real UTC now): decides whether the game's gameweek has
  /// locked.
  final DateTime Function()? nowUtc;

  /// The bound on the new feeds' first answers (the global 2 s).
  final Duration liveWait;

  /// Last-shown earning value per game this session (see
  /// [recordEarningValue]).
  static final Map<String, int> sessionEarnings = {};

  @override
  State<MatchFantasyTab> createState() => _MatchFantasyTabState();
}

class _MatchFantasyTabState extends State<MatchFantasyTab> {
  Object? _gameNode;
  bool _gameLoaded = false;
  List<FantasyPlayer>? _players;
  FantasySquad? _squad;
  bool _squadLoaded = false;

  StreamSubscription<Object?>? _gameSub;
  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<FantasySquad?>? _squadSub;

  // ── Live everywhere (Task 7) ────────────────────────────────────────────

  /// The signed-in user's uid ('' = signed out). Best-effort (the other
  /// fantasy screens' convention): widget tests never touch FirebaseAuth — a
  /// missing seam degrades to "signed out", not a throw.
  late final String _selfUid = () {
    final override = widget.selfUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }();

  bool get _signedIn => _selfUid.isNotEmpty;

  /// Places the game in its gameweek (the shared Config → schedule feed, which
  /// also session-caches it). Only used while someone is signed in.
  late final FantasyScheduleFeed<Object?> _schedule = FantasyScheduleFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'MatchFantasyTab',
    onChanged: _scheduleChanged,
    gameweekStates: widget.gameweekStates,
    nowUtc: widget.nowUtc,
  );

  /// The reveal gate over the schedule, the locked squad, the week's record,
  /// the live feed and the Voided set.
  late final AnswerGate _gate = AnswerGate(
    bound: widget.liveWait,
    owner: 'MatchFantasyTab',
    onChanged: () {
      if (mounted) _recompute();
    },
  );

  FantasyLiveState _live = FantasyLiveState.none;

  /// The owner-voided weeks; null = unknown (feed failed or not answered yet):
  /// the week strip then says nothing.
  Set<int>? _voided;

  /// The squad that was locked for the game's gameweek, and that week's
  /// settled record (its squad is the fallback).
  FantasySquad? _published;
  HistoryWeek? _historyWeek;

  /// The gameweek the per-week feeds listen to (null = none yet / the game's
  /// date is not on the schedule).
  int? _watchedWeek;
  StreamSubscription<FantasySquad?>? _publishedSub;
  StreamSubscription<HistoryWeek?>? _historySub;
  StreamSubscription<FantasyLiveState>? _liveSub;
  StreamSubscription<Set<int>>? _voidedSub;

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  /// The game's gameweek; null = unknown (schedule not answered, failed, or
  /// the date is not on it).
  Gameweek? get _gameweek =>
      gameweekForDate(_schedule.gameweeks ?? const [], widget.dateKey);

  /// The viewer's squad for THIS game — see [matchViewerSquad]. Nobody signed
  /// in has none.
  FantasySquad? get _viewerSquad {
    if (!_signedIn) return null;
    return matchViewerSquad(
      gameweek: _gameweek,
      gameweeks: _schedule.gameweeks ?? const [],
      lockOverride: widget.configState.lockOverride,
      nowUtc: _now,
      published: _published,
      history: _historyWeek,
      current: _squad,
    ).squad;
  }

  // Memoized off the streams (the tournamentdetail.dart lag-fix rule:
  // recompute on stream events / input changes, never in build).
  FantasySquad? _viewer; // the squad the rows and the chip are about
  MatchFantasyPoints _rows = MatchFantasyPoints.empty;
  String? _forfeitNote; // spec §8a header note; null = a normal game
  int _earning = 0;
  int? _animateFrom; // non-null exactly when a genuine increase just landed
  bool _showScoreless = false;

  String get _gameKey =>
      '${widget.sport}/${widget.season}/${widget.dateKey}/${widget.gameIndex}';

  Map<String, int> get _store =>
      widget.earningStore ?? MatchFantasyTab.sessionEarnings;

  /// The viewer layer (his squad for the game, the week strip) has what it
  /// needs: his saved squad is known and every new feed answered (or the bound
  /// passed). Until then nothing of his is worked out or remembered.
  bool get _viewerLayerReady => _squadLoaded && _gate.ready;

  bool get _ready =>
      _gameLoaded && _players != null && _squadLoaded && _gate.ready;

  @override
  void initState() {
    super.initState();
    if (_signedIn) _startViewerFeeds();
    _gameSub = (widget.gameNodeStates ??
            FantasyService.watchGameNode(widget.sport, widget.season,
                widget.dateKey, widget.gameIndex))
        .listen((node) {
      if (!mounted) return;
      _gameNode = node;
      _gameLoaded = true;
      _recompute();
    });
    _playersSub = (widget.playersStates ??
            FantasyService.watchPlayers(widget.sport, widget.season))
        .listen((players) {
      if (!mounted) return;
      _players = players;
      _recompute();
    });
    _squadSub = (widget.squadStates ??
            FantasyService.watchMySquadAuto(widget.sport, widget.season))
        .listen((squad) {
      if (!mounted) return;
      _squad = squad;
      _squadLoaded = true;
      _recompute();
    }, onError: (Object _) {
      // A permissions/auth hiccup must never hold the tab on the skeleton —
      // it renders without the viewer layer until a re-emit.
      if (!mounted) return;
      _squadLoaded = true;
      _recompute();
    });
  }

  @override
  void didUpdateWidget(covariant MatchFantasyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The match page re-feeds live rosters and config through the
    // constructor — re-derive on any rebuild from above (cheap: one pass
    // over a futsal game's players).
    _recompute();
  }

  @override
  void dispose() {
    _gameSub?.cancel();
    _playersSub?.cancel();
    _squadSub?.cancel();
    _publishedSub?.cancel();
    _historySub?.cancel();
    _liveSub?.cancel();
    _voidedSub?.cancel();
    _schedule.dispose();
    _gate.dispose();
    super.dispose();
  }

  // ── The viewer's feeds (Task 7) ─────────────────────────────────────────

  /// Subscribes what the viewer layer reads, behind the reveal gate: the
  /// schedule (to place the game in its gameweek), the live feed and the Voided
  /// set now, the locked squad and the week's record once the gameweek is
  /// known ([_syncWeekFeeds]).
  void _startViewerFeeds() {
    _gate
      ..expect('schedule')
      ..start();
    _schedule.start(); // seeds from the session cache, never notifies here
    // Each viewer feed answers the gate (AnswerGate.listen: data OR error, or
    // a feed that cannot even be created); an error is logged and leaves what
    // the feed last said (nothing, if it never spoke) — a failed feed is
    // "unknown", never a made-up squad or number.
    _liveSub = _gate.listen<FantasyLiveState>(
      'live feed',
      () =>
          widget.liveStates ?? FantasyLiveFeed.watch(widget.sport, widget.season),
      onData: (v) => _live = v,
    );
    _voidedSub = _gate.listen<Set<int>>(
      'voided feed',
      () =>
          widget.voidedStates ??
          FantasyService.watchVoidedWeeks(widget.sport, widget.season),
      onData: (v) => _voided = v,
    );
    _syncWeekFeeds(); // a cached schedule answers at once
  }

  /// The schedule changed (an emission, an error): place the game again.
  void _scheduleChanged() {
    if (!mounted) return;
    _syncWeekFeeds();
    _recompute();
  }

  /// Once the schedule is known (an error leaves it empty: then no week is
  /// known and there is no viewer layer), listens to the locked squad and the
  /// settled record of the game's OWN gameweek — one small node each, never
  /// the whole `PublishedPicks` / `History`. A different week (the schedule
  /// moved) drops the old week's data at once.
  void _syncWeekFeeds() {
    final gameweeks = _schedule.gameweeks;
    if (gameweeks == null) return; // not answered yet
    _gate.answer('schedule');
    final week = gameweekForDate(gameweeks, widget.dateKey)?.number;
    if (week == _watchedWeek) return;
    _publishedSub?.cancel();
    _historySub?.cancel();
    _publishedSub = _historySub = null;
    _published = null;
    _historyWeek = null;
    _watchedWeek = week;
    if (week == null) return;
    _publishedSub = _gate.listen<FantasySquad?>(
      'published picks feed',
      () =>
          widget.publishedPicksFor?.call(week) ??
          FantasyService.watchPublishedPicksWeek(
              widget.sport, widget.season, _selfUid, week),
      onData: (v) => _published = v,
    );
    _historySub = _gate.listen<HistoryWeek?>(
      'history week feed',
      () =>
          widget.historyWeekFor?.call(week) ??
          FantasyService.watchHistoryWeek(
              widget.sport, widget.season, _selfUid, week),
      onData: (v) => _historyWeek = v,
    );
  }

  void _recompute() {
    final node = _gameNode;
    final players = _players;
    if (node is! Map || players == null) {
      setState(() {});
      return;
    }
    // THE viewer's squad for this game: the one locked for its gameweek.
    final viewer = _viewerSquad;
    final points = matchGamePoints(
      gameNode: node,
      rosterNamesByTeam: widget.rosterNamesByTeam,
      players: players,
      config: widget.configState.config,
    );
    final rows = buildMatchFantasyRows(
      gameNode: node,
      rosterNamesByTeam: widget.rosterNamesByTeam,
      players: players,
      config: widget.configState.config,
      squad: viewer,
    );
    // The chip only exists once the viewer's squad for this game is known (his
    // saved squad has streamed in AND the locked-squad feeds have answered) —
    // and the session store must only ever hold REAL values: recording an
    // interim number worked out from the wrong squad (or an interim 0) would
    // make the next recompute (or the next page open) replay a bogus tween.
    int earning = _earning;
    int? animateFrom = _animateFrom;
    if (_viewerLayerReady && viewer != null) {
      earning = viewerEarningPoints(
        gamePointsByName: points,
        squad: viewer,
        config: widget.configState.config,
      );
      // Genuine-increase detection (house motion rule): the session store
      // remembers the last value per game, so a reconnect/re-push that
      // re-delivers the same number never replays the tween.
      final previous = recordEarningValue(_store, _gameKey, earning);
      animateFrom =
          (previous != null && earning > previous) ? previous : null;
    }
    final forfeitNote = matchForfeitNote(node);
    setState(() {
      _viewer = viewer;
      _rows = rows;
      _forfeitNote = forfeitNote;
      _earning = earning;
      _animateFrom = animateFrom;
    });
  }

  void _openHub() {
    final open = widget.onOpenHub;
    if (open != null) {
      open();
      return;
    }
    // Same push as the league page's Fantasy entry card.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FantasyHubPage(sport: widget.sport, season: widget.season),
      ),
    );
  }

  /// A points row's tap: that player's fantasy profile. This page lives
  /// OUTSIDE the hub (the league match page), so there is no shared draft and
  /// the profile's primary button is "Open in Fantasy".
  void _openPlayer(String name) {
    (widget.profileOpener ?? openFantasyPlayerProfile)(
      context,
      sport: widget.sport,
      season: widget.season,
      playerName: name,
      fromOutsideHub: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (!_ready) {
      body = const _FantasyTabSkeleton(key: ValueKey('match_fantasy_skeleton'));
    } else {
      body = _content(context);
    }
    // Single fade reveal once the three streams have all landed.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: body,
    );
  }

  Widget _content(BuildContext context) {
    final node = _gameNode;
    final scheme = Theme.of(context).colorScheme;
    if (node is! Map || !matchStarted(node['status'])) {
      // Pre-kickoff (or a vanished node): no wall of default appearance
      // points — points land here live once capture starts.
      return _PreKickoffFace(
          key: const ValueKey('match_fantasy_prekickoff'),
          onOpenHub: _openHub);
    }

    // The viewer's squad for THIS game (the one locked for its gameweek).
    final hasChip = _viewer != null;
    final multiplier = captainMultiplierFor(_viewer, widget.configState.config);
    // The gameweek's own line, while it is live (null = nothing to say).
    final weekLine = _signedIn
        ? matchWeekStrip(
            live: _live,
            week: _gameweek?.number,
            uid: _selfUid,
            voidedWeeks: _voided,
          )
        : null;
    return ListView(
      key: const ValueKey('match_fantasy_ready'),
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        // The header: where the game is (LIVE or FINAL), then — while the
        // gameweek is live — what the viewer's gameweek has scored so far.
        _StatusHeader(phase: matchPhase(node['status'])),
        const SizedBox(height: 10),
        if (weekLine != null) ...[
          _WeekStrip(text: weekLine),
          const SizedBox(height: 12),
        ],
        // Forfeit (spec §8a): say so up top, before any "+1" row.
        if (_forfeitNote != null) ...[
          _ForfeitNote(text: _forfeitNote!),
          const SizedBox(height: 12),
        ],
        if (hasChip) ...[
          _EarningChip(
            value: _earning,
            animateFrom: _animateFrom,
            multiplier: multiplier,
          ),
          const SizedBox(height: 12),
        ],
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
            child: Text(
              'No fantasy-listed players in this game yet — points appear '
              'here as stats are captured.',
              key: const ValueKey('match_fantasy_no_players'),
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final row in _rows.scored)
          _PointsRow(row: row, onOpenPlayer: _openPlayer),
        if (_rows.scoreless.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ScorelessSection(
            rows: _rows.scoreless,
            expanded: _showScoreless,
            onToggle: () =>
                setState(() => _showScoreless = !_showScoreless),
            onOpenPlayer: _openPlayer,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          kMatchFootnote,
          key: const ValueKey('match_fantasy_footnote'),
          softWrap: true,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _OpenHubButton(onPressed: _openHub),
      ],
    );
  }
}

/// The tab's header (live everywhere, Task 7): LIVE (the shared pill) while the
/// game is being played, FINAL once it is over — from the game's own status.
/// Live and final used to render identically.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.phase});

  final MatchPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget label;
    if (phase == MatchPhase.live) {
      label = const FantasyLivePill(key: ValueKey('match_fantasy_live_pill'));
    } else {
      // Final: the pill's twin in the neutral ink — it is over, nothing moves.
      final ink = scheme.onSurfaceVariant;
      label = Container(
        key: const ValueKey('match_fantasy_final'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ink.withValues(alpha: 0.45)),
        ),
        child: Text(
          'FINAL',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            height: 1.1,
            color: ink,
          ),
        ),
      );
    }
    return Align(alignment: Alignment.centerLeft, child: label);
  }
}

/// `Your gameweek so far: {W} pts · #{R}` under the header while the gameweek
/// is live: a neutral surface, wraps, both themes.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('match_fantasy_week_strip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        key: const ValueKey('match_fantasy_week_strip_text'),
        softWrap: true,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// The forfeit header note (spec §8a): the shared "Forfeit" pill + one
/// wrapping sentence on a neutral surface — colorScheme only, both themes.
class _ForfeitNote extends StatelessWidget {
  const _ForfeitNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('match_fantasy_forfeit_note'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: ForfeitChip(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              softWrap: true,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "You're earning +N this game" — the viewer-squad sum with the captain
/// multiplied. The number tweens 250ms ONLY on a genuine increase (zero
/// under reduced motion); every other rebuild renders it statically.
class _EarningChip extends StatelessWidget {
  const _EarningChip({
    required this.value,
    required this.animateFrom,
    required this.multiplier,
  });

  final int value;
  final int? animateFrom;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      key: const ValueKey('match_fantasy_earning_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rich text so the sentence WRAPS at narrow widths instead
                // of overflowing (house rule) while the number stays its own
                // animated widget.
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: scheme.onSurface,
                    ),
                    children: [
                      const TextSpan(text: "You're earning "),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: TweenAnimationBuilder<double>(
                          // A fresh key per value restarts the tween exactly
                          // once; animateFrom == null begins at the end
                          // value, so nothing moves.
                          key: ValueKey('earning_$value'),
                          tween: Tween(
                            begin: (animateFrom ?? value).toDouble(),
                            end: value.toDouble(),
                          ),
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          builder: (context, v, _) => Text(
                            '+${v.round()}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: ' this game'),
                    ],
                  ),
                  softWrap: true,
                ),
                const SizedBox(height: 2),
                Text(
                  'Your squad\'s raw points here, captain ×$multiplier.',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One ranked row: "+6" badge · avatar · name (wraps) + "(DEF)" · YOURS tag.
/// The viewer's picks carry the accent border; the viewer's captain adds the
/// "×2 applied" line so the math is never mysterious. The whole row is
/// tappable: it opens that player's fantasy profile (round 3, spec §4).
class _PointsRow extends StatelessWidget {
  const _PointsRow({required this.row, required this.onOpenPlayer});

  final MatchFantasyRow row;
  final void Function(String playerName) onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final pointsText = row.points >= 0 ? '+${row.points}' : '${row.points}';

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              pointsText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: row.points < 0 ? fantasyDownRed(context) : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FantasyAvatar(name: row.name, photoUrl: row.photoUrl, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.name} (${row.position.db})',
                  // Wraps, never underlined or ellipsized (house rules).
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        row.isViewerPick ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                    color: scheme.onSurface,
                  ),
                ),
                if (row.isViewerCaptain)
                  Text(
                    'Captain ×${row.captainMultiplier} applied · '
                    '$pointsText × ${row.captainMultiplier} = '
                    '${row.points >= 0 ? '+' : ''}'
                    '${row.points * row.captainMultiplier} for you',
                    key: ValueKey('captain_math_${row.name}'),
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
              ],
            ),
          ),
          if (row.isViewerPick) ...[
            const SizedBox(width: 8),
            Container(
              key: ValueKey('yours_tag_${row.name}'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'YOURS',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // The ripple lives on its own transparent Material INSIDE the viewer's
    // decorated box, so it paints above the tint instead of behind it.
    final tappable = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('points_row_${row.name}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpenPlayer(row.name),
        child: content,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: row.isViewerPick
          ? Container(
              key: ValueKey('viewer_row_${row.name}'),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: tappable,
            )
          : tappable,
    );
  }
}

/// "No returns yet (N)" — present players on zero points, collapsed behind a
/// tap (they'd otherwise drown the returns the tab exists to show).
class _ScorelessSection extends StatelessWidget {
  const _ScorelessSection({
    required this.rows,
    required this.expanded,
    required this.onToggle,
    required this.onOpenPlayer,
  });

  final List<MatchFantasyRow> rows;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String playerName) onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('match_fantasy_scoreless_toggle'),
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'No returns yet (${rows.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (final row in rows)
            _PointsRow(row: row, onOpenPlayer: onOpenPlayer),
      ],
    );
  }
}

/// Kickoff-pending face: no fake zeros, just where the points will appear.
class _PreKickoffFace extends StatelessWidget {
  const _PreKickoffFace({super.key, required this.onOpenHub});

  final VoidCallback onOpenHub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child:
                Icon(Icons.bolt, size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            'Fantasy points land here live at kickoff.',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _OpenHubButton(onPressed: onOpenHub),
        ],
      ),
    );
  }
}

/// The hub entry button — the league entry card's accent pairing (gold on
/// dark, primary red on light) so the brand stays single-sourced.
class _OpenHubButton extends StatelessWidget {
  const _OpenHubButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey('match_fantasy_open_hub'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: FantasyBanner.accent(context),
          foregroundColor: isDark ? Colors.black : scheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 13),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: const Text('Open Infinite Fantasy'),
      ),
    );
  }
}

class _FantasyTabSkeleton extends StatelessWidget {
  const _FantasyTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: double.infinity, height: 64, radius: 14),
            SizedBox(height: 14),
            SkeletonList(count: 6),
          ],
        ),
      ),
    );
  }
}
