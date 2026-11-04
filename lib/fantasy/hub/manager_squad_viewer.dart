// The manager squad viewer (P3d — pick transparency, spec §9): tapping any
// leaderboard row opens that manager's squad on the read-only court. The
// viewer's OWN squad is the live one; anyone else's current week comes from
// `PublishedPicks` (functions-written AT LOCK — before lock the week simply
// isn't there, which is the anti-copying rule enforced by data, not UI), and
// earlier weeks from `History`, browsable forever via the week chips.
// Nothing published yet → "Picks are revealed when the gameweek locks."
// Badges (spec 2026-10-30 §5): the manager's badge shelf sits at the top
// (also above the reveal-at-lock message); nothing earned = no shelf.
// Your OWN team page (isSelf) also carries the "Your rank this season" card
// (rank_history_chart.dart — the line chart + "Share my rank"; it used to
// fold open under your own leaderboard row) just under the shelf. Its data
// is handed in by the opener (the leaderboard tab already holds
// Leaderboards/RankHistory), so it is part of the first paint — it joins the
// same single reveal, never pops in after it.
//
// Live everywhere (Task 7): every court chip carries that player's counted
// points for the week shown, and a line above the court says what the week
// scored — `{W} pts` with the shared LIVE pill while the week is being played,
// `Final · {W} pts` once settled (the manager's own `History/<gw>/<uid>`
// Breakdown), My Team's "Voided" / "didn't count" copy for those weeks.
//   • a LIVE week reads `Live/Squads/<uid>` + the live feed's player statuses;
//   • a SETTLED week reads that one week's `History/<gw>/<uid>` — one small
//     listener per week shown (watchHistoryWeek), never the whole History;
//   • "Voided" comes only from the Voided set (`watchVoidedWeeks`), never from
//     a live per-player record (a live record in a voided week reads "not
//     voided, 0"): while that set is unknown (its feed failed or has not
//     answered) NO points are shown — never a number that may be a voided
//     week's;
//   • the resolver is My Team's ([resolveLockedWeek]), so the two screens can
//     never disagree about a week;
//   • your own "Now" face shows the live points of the week being played when
//     the squad on it IS the squad that was locked (same picks); otherwise
//     they belong to the locked squad and are not drawn on a different one.
// The new streams join the page's single reveal (an [AnswerGate]: every feed
// answered, an error counts as an answer, bounded at the global 2 s; latched,
// so a week that locks while the page is open never brings the skeleton back).
//
// House rules: streams only; single fade reveal (skeleton until every stream
// — the badge feeds included; a failing badge feed counts as "none" — has
// emitted once); theme-safe court (FantasyCourtView, onSlotTap null = no
// editing; a chip tap opens that player's profile — round 3); captain/vice
// armbands shown; names wrap; scrolling clears the glass navbar; initials
// avatar fallback via the court's chips.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/answer_gate.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart'
    show HistoryWeek;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/badge_shelf.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/rank_history_chart.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/match/match_fantasy_logic.dart'
    show captainMultiplierFor;
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

class ManagerSquadViewerPage extends StatefulWidget {
  const ManagerSquadViewerPage({
    super.key,
    required this.sport,
    required this.season,
    required this.uid,
    required this.title,
    required this.isSelf,
    required this.config,
    required this.players,
    required this.gameweeks,
    this.squadStates,
    this.initialSquad,
    this.publishedStates,
    this.historyStates,
    this.nowUtc,
    this.onOpenPlayer,
    this.badgeStates,
    this.badgeCatalogStates,
    this.initialBadges,
    this.initialBadgeCatalog,
    this.rankSeries,
    this.rankStates,
    this.onShareRank,
    this.liveStates,
    this.liveSquadStates,
    this.historyWeekFor,
    this.voidedStates,
    this.liveWait = kLiveJoinWait,
  });

  final String sport;
  final String season;

  /// The viewed manager.
  final String uid;

  /// The manager's fantasy team name (spec: Managers' TeamName as the title).
  final String title;
  final bool isSelf;

  final FantasyConfig config;

  /// The live market — the court's photo source per pick.
  final List<FantasyPlayer> players;
  final List<Gameweek> gameweeks;

  /// The viewer's OWN live squad (re-listen-safe hub broadcast) — only used
  /// when [isSelf]; others never see a live squad (spec §9).
  final Stream<FantasySquad?>? squadStates;
  final FantasySquad? initialSquad;

  /// Test seams — null = the real FantasyService streams for [uid].
  final Stream<Map<int, FantasySquad>>? publishedStates;
  final Stream<Map<int, FantasySquad>>? historyStates;
  final DateTime Function()? nowUtc;

  /// Round 3: tapping a chip on the court opens that player's fantasy
  /// profile (the hub's one opener, bound to its shared draft). The court
  /// itself stays read-only. null = chips inert.
  final void Function(String playerName)? onOpenPlayer;

  /// Badges (spec 2026-10-30 §5) — null = the real
  /// `FantasyService.watchBadgesFor(uid)` / `watchBadgeCatalog()` feeds.
  final Stream<List<FantasyBadgeAward>>? badgeStates;
  final Stream<FantasyBadgeCatalog>? badgeCatalogStates;

  /// What the opener already holds (the profile tab's source, the
  /// leaderboard's season badges): the shelf needs no first emission when
  /// both are given; the live feeds still update it.
  final List<FantasyBadgeAward>? initialBadges;
  final FantasyBadgeCatalog? initialBadgeCatalog;

  /// Your season's Overall rank by gameweek (the opener's
  /// `rankSeries(Leaderboards/RankHistory[uid])`). When [isSelf] and not
  /// null, the page opens with the "Your rank this season" card (an empty /
  /// one-week series = the card's muted "after your second scored
  /// gameweek" note). Ignored for anyone else's page; null = no card.
  final List<RankPoint>? rankSeries;

  /// Live updates to [rankSeries] (the opener's Leaderboards feed mapped to
  /// your RankHistory): a gameweek finalizing while your page is open moves
  /// the chart. Seeded by [rankSeries] for the first paint; a feed that
  /// fails keeps the series as opened. null = the series stays as opened.
  final Stream<List<RankPoint>>? rankStates;

  /// "Share my rank" on that card — renders + shares your rank story, given
  /// the button's context (the iPad share anchor). null = no share action.
  final Future<void> Function(BuildContext buttonContext)? onShareRank;

  // ── Live everywhere (Task 7) — test seams, null = the real feeds ────────

  /// The season's live gameweek ([FantasyLiveFeed.watch]).
  final Stream<FantasyLiveState>? liveStates;

  /// The viewed manager's `Live/Squads/<uid>`
  /// ([FantasyService.watchLiveSquad]).
  final Stream<LiveSquad?>? liveSquadStates;

  /// One week's settled `History/<gw>/<uid>`
  /// ([FantasyService.watchHistoryWeek]) — asked once per week shown.
  final Stream<HistoryWeek?> Function(int week)? historyWeekFor;

  /// The season's owner-voided weeks ([FantasyService.watchVoidedWeeks]).
  final Stream<Set<int>>? voidedStates;

  /// The bound on the new feeds' first answers (the global 2 s).
  final Duration liveWait;

  @override
  State<ManagerSquadViewerPage> createState() => _ManagerSquadViewerPageState();
}

class _ManagerSquadViewerPageState extends State<ManagerSquadViewerPage> {
  Map<int, FantasySquad>? _published;
  Map<int, FantasySquad>? _history;
  FantasySquad? _liveSquad;
  bool _liveLoaded = false;

  /// Selected week; null = the "Now" chip (the live squad — self only).
  /// [_weekChosen] separates "user picked" from "not defaulted yet".
  int? _selectedWeek;
  bool _weekChosen = false;

  StreamSubscription<Map<int, FantasySquad>>? _publishedSub;
  StreamSubscription<Map<int, FantasySquad>>? _historySub;
  StreamSubscription<FantasySquad?>? _liveSub;

  /// This manager's awards + the catalog; null until loaded (a failing feed
  /// loads as "none", never an eternal skeleton).
  List<FantasyBadgeAward>? _badges;
  FantasyBadgeCatalog? _badgeCatalog;
  StreamSubscription<List<FantasyBadgeAward>>? _badgesSub;
  StreamSubscription<FantasyBadgeCatalog>? _badgeCatalogSub;

  /// Your season rank line (isSelf only) — seeded from the opener, then
  /// live from [ManagerSquadViewerPage.rankStates].
  List<RankPoint>? _rankSeries;
  StreamSubscription<List<RankPoint>>? _rankSub;

  // ── Live everywhere (Task 7): the points on the court ───────────────────

  /// The reveal gate over the live feed, the viewed manager's live squad, the
  /// Voided set and one settled record per week shown.
  late final AnswerGate _gate = AnswerGate(
    bound: widget.liveWait,
    owner: 'ManagerSquadViewerPage',
    onChanged: () {
      if (mounted) setState(() {});
    },
  );
  FantasyLiveState _liveState = FantasyLiveState.none;

  /// The viewed manager's `Live/Squads/<uid>`.
  LiveSquad? _liveWeekSquad;

  /// The owner-voided weeks; null = unknown (the feed failed or has not
  /// answered): no points are shown while it is.
  Set<int>? _voided;

  /// Each week shown's settled `History/<gw>/<uid>` (null = none / failed).
  final Map<int, HistoryWeek?> _settled = {};
  final Map<int, StreamSubscription<HistoryWeek?>> _settledSubs = {};
  StreamSubscription<FantasyLiveState>? _liveStateSub;
  StreamSubscription<LiveSquad?>? _liveWeekSquadSub;
  StreamSubscription<Set<int>>? _voidedSub;

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  @override
  void initState() {
    super.initState();
    _gate.start();
    _publishedSub = (widget.publishedStates ??
            FantasyService.watchPublishedPicksFor(
                widget.sport, widget.season, widget.uid))
        .listen((weeks) {
      if (!mounted) return;
      _published = weeks;
      _syncSettledWeeks();
      setState(() {});
    });
    _historySub = (widget.historyStates ??
            FantasyService.watchHistoryFor(
                widget.sport, widget.season, widget.uid))
        .listen((weeks) {
      if (!mounted) return;
      _history = weeks;
      _syncSettledWeeks();
      setState(() {});
    });
    // The points feeds join the reveal through the gate (AnswerGate.listen:
    // an answer — data OR error, or a feed that cannot even be created —
    // opens its slot; an error is logged and leaves what the feed last said
    // unless it resets it).
    _liveStateSub = _gate.listen<FantasyLiveState>(
      'live feed',
      () =>
          widget.liveStates ?? FantasyLiveFeed.watch(widget.sport, widget.season),
      onData: (v) => _liveState = v,
    );
    _liveWeekSquadSub = _gate.listen<LiveSquad?>(
      'live squad feed',
      () =>
          widget.liveSquadStates ??
          FantasyService.watchLiveSquad(
              widget.sport, widget.season, widget.uid),
      onData: (v) => _liveWeekSquad = v,
      onError: () => _liveWeekSquad = null,
    );
    _voidedSub = _gate.listen<Set<int>>(
      'voided feed',
      () =>
          widget.voidedStates ??
          FantasyService.watchVoidedWeeks(widget.sport, widget.season),
      onData: (v) => _voided = v,
    );
    if (widget.isSelf) {
      _liveSquad = widget.initialSquad;
      _liveLoaded = widget.initialSquad != null;
      final states = widget.squadStates;
      if (states != null) {
        _liveSub = states.listen((squad) {
          if (mounted) {
            setState(() {
              _liveSquad = squad;
              _liveLoaded = true;
            });
          }
        });
      } else {
        _liveLoaded = true;
      }
    }
    _badges = widget.initialBadges;
    _badgeCatalog = widget.initialBadgeCatalog;
    _badgesSub = _listenSoft<List<FantasyBadgeAward>>(
      () =>
          widget.badgeStates ??
          FantasyService.watchBadgesFor(
              widget.sport, widget.season, widget.uid),
      (b) => _badges = b,
      () => _badges ??= const [],
      'badges',
    );
    _badgeCatalogSub = _listenSoft<FantasyBadgeCatalog>(
      () => widget.badgeCatalogStates ?? FantasyService.watchBadgeCatalog(),
      (c) => _badgeCatalog = c,
      () => _badgeCatalog ??= badgeCatalogFromNode(null),
      'badge catalog',
    );
    _rankSeries = widget.rankSeries;
    final rankStates = widget.rankStates;
    if (widget.isSelf && rankStates != null) {
      _rankSub = _listenSoft<List<RankPoint>>(
        () => rankStates.where((s) => !_sameSeries(_rankSeries, s)),
        (s) => _rankSeries = s,
        () {},
        'rank history',
      );
    }
  }

  static bool _sameSeries(List<RankPoint>? a, List<RankPoint> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// A badge feed that cannot be created or errors degrades to [onFail]
  /// ("nothing earned" / the starter catalog) — logged, never a skeleton.
  StreamSubscription<T>? _listenSoft<T>(
    Stream<T> Function() make,
    void Function(T value) onData,
    void Function() onFail,
    String label,
  ) {
    void fail(Object e) {
      debugPrint('ManagerSquadViewerPage: $label feed failed: $e');
      if (mounted) setState(onFail);
    }

    try {
      return make().listen((v) {
        if (mounted) setState(() => onData(v));
      }, onError: fail);
    } catch (e) {
      debugPrint('ManagerSquadViewerPage: $label feed failed: $e');
      onFail();
      return null;
    }
  }

  /// One small settled listener per week shown (`History/<gw>/<uid>`): the
  /// weeks the squad streams know. A new week (one that locks while the page
  /// is open) is subscribed at once; a week that vanished is let go.
  void _syncSettledWeeks() {
    final published = _published;
    final history = _history;
    if (published == null || history == null) return;
    final wanted = {...history.keys, ...published.keys};
    for (final week in wanted) {
      if (_settledSubs.containsKey(week)) continue;
      final sub = _gate.listen<HistoryWeek?>(
        'history week $week',
        () =>
            widget.historyWeekFor?.call(week) ??
            FantasyService.watchHistoryWeek(
                widget.sport, widget.season, widget.uid, week),
        onData: (v) => _settled[week] = v,
        onError: () => _settled[week] = null,
      );
      if (sub != null) _settledSubs[week] = sub;
    }
    for (final week in _settledSubs.keys.toList()) {
      if (wanted.contains(week)) continue;
      _settledSubs.remove(week)?.cancel();
      _settled.remove(week);
    }
  }

  @override
  void dispose() {
    _publishedSub?.cancel();
    _historySub?.cancel();
    _liveSub?.cancel();
    _rankSub?.cancel();
    _badgesSub?.cancel();
    _badgeCatalogSub?.cancel();
    _liveStateSub?.cancel();
    _liveWeekSquadSub?.cancel();
    _voidedSub?.cancel();
    for (final sub in _settledSubs.values) {
      sub.cancel();
    }
    _settledSubs.clear();
    _gate.dispose();
    super.dispose();
  }

  bool get _loading =>
      _published == null ||
      _history == null ||
      (widget.isSelf && !_liveLoaded) ||
      _badges == null ||
      _badgeCatalog == null ||
      !_gate.ready;

  /// The badge shelf (with its label) for the top of the page; null when
  /// nothing is earned.
  Widget? _badgeSection(BuildContext context) {
    final badges = _badges ?? const <FantasyBadgeAward>[];
    if (badges.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Badges',
            key: const ValueKey('viewer_badges_label'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          BadgeShelf(
            awards: badges,
            catalog: _badgeCatalog ?? const {},
            season: widget.season,
          ),
        ],
      ),
    );
  }

  /// The "Your rank this season" card for the top of YOUR page; null on
  /// anyone else's, or when the opener passed no series.
  Widget? _rankSection() {
    final series = _rankSeries;
    if (!widget.isSelf || series == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RankHistoryPanel(
        series: series,
        onShare: widget.onShareRank,
      ),
    );
  }

  /// The gameweek whose points the court shows: the week picked on its chip;
  /// on your own "Now" face, the week being played — but only when "Now" IS
  /// the squad that was locked for it (same picks): the live points belong to
  /// that squad and are never drawn on a different one. null = no points.
  int? _pointsWeek(Map<int, FantasySquad> weeks) {
    final picked = _selectedWeek;
    if (picked != null) return picked;
    if (!widget.isSelf) return null;
    final live = liveWeekOf(_liveState.meta);
    if (live == null) return null;
    final locked = weeks[live];
    final now = _liveSquad;
    if (locked == null || now == null) return null;
    Set<String> ids(FantasySquad s) => {for (final p in s.picks) p.playerId};
    final a = ids(now);
    final b = ids(locked);
    return a.length == b.length && a.containsAll(b) ? live : null;
  }

  /// [week]'s points, through My Team's own resolver — null while the Voided
  /// set is unknown (never a number that may be a voided week's).
  LockedWeekModel? _pointsModel(int week, FantasySquad? published) {
    final voided = _voided;
    if (voided == null) return null;
    return resolveLockedWeek(
      week: week,
      uid: widget.uid,
      voidedWeeks: voided,
      sources: LockedWeekSources(
        live: _liveState,
        liveSquad: _liveWeekSquad,
        history: _settled[week],
        published: published,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const _ViewerSkeleton(key: ValueKey('viewer_skeleton'));
    } else {
      body = _content(context);
    }
    return Scaffold(
      appBar: AppBar(
        // The team name wraps rather than truncates (house rule).
        title: Text(widget.title, softWrap: true, maxLines: 2),
      ),
      // Single fade reveal once every stream has emitted.
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: body,
      ),
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weeks =
        mergeManagerWeeks(history: _history!, published: _published!);
    final sortedWeeks = weeks.keys.toList()..sort();
    final badgeSection = _badgeSection(context);
    final rankSection = _rankSection();

    // Nothing browsable for another manager = their current week hasn't
    // locked yet (spec §9's anti-copying, enforced by the data itself).
    // Badges are public whenever earned: the shelf stays above the message.
    if (!widget.isSelf && sortedWeeks.isEmpty) {
      const message = _ViewerMessage(
        key: ValueKey('viewer_unrevealed'),
        icon: Icons.lock_clock,
        message: 'Picks are revealed when the gameweek locks.',
      );
      if (badgeSection == null) return message;
      return SingleChildScrollView(
        key: const ValueKey('viewer_unrevealed_scroll'),
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [badgeSection, message],
        ),
      );
    }

    // Default selection, applied once: self opens on the live squad ("Now");
    // others on the current week when published, else the latest week.
    if (!_weekChosen) {
      _selectedWeek = widget.isSelf
          ? null
          : defaultViewerWeek(
              weeks: weeks.keys.toSet(),
              currentGw: currentGameweek(widget.gameweeks, _now)?.number,
            );
      _weekChosen = true;
    }
    // A week that vanished from the stream falls back to the default face.
    if (_selectedWeek != null && !weeks.containsKey(_selectedWeek)) {
      _selectedWeek = widget.isSelf
          ? null
          : defaultViewerWeek(
              weeks: weeks.keys.toSet(),
              currentGw: currentGameweek(widget.gameweeks, _now)?.number,
            );
    }

    final squad =
        _selectedWeek == null ? _liveSquad : weeks[_selectedWeek];
    // What the week on the court scored (points per player + the week line);
    // null = nothing readable for it — then nothing is drawn.
    final pointsWeek = _pointsWeek(weeks);
    final points = pointsWeek == null
        ? null
        : _pointsModel(pointsWeek, weeks[pointsWeek]);
    final weekLine = points == null ? null : viewerWeekStrip(points.view);
    final photoByName = {
      for (final p in widget.players)
        if (p.photoUrl != null) p.name: p.photoUrl,
    };
    final slots = buildSlots(widget.config);
    final chip = chipLabel(squad?.chip);

    return SingleChildScrollView(
      key: const ValueKey('viewer_content'),
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The manager's badges first (spec 2026-10-30 §5), then (your own
          // page only) your rank this season.
          if (badgeSection != null) badgeSection,
          if (rankSection != null) rankSection,
          // Week browser (spec §9: full history, forever). Self gets the
          // extra "Now" chip for the live squad.
          if (widget.isSelf || sortedWeeks.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.isSelf) ...[
                    ChoiceChip(
                      key: const ValueKey('viewer_week_now'),
                      label: const Text('Now'),
                      visualDensity: VisualDensity.compact,
                      selected: _selectedWeek == null,
                      onSelected: (_) => setState(() {
                        _selectedWeek = null;
                        _weekChosen = true;
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (final week in sortedWeeks) ...[
                    ChoiceChip(
                      key: ValueKey('viewer_week_$week'),
                      label: Text('GW$week'),
                      visualDensity: VisualDensity.compact,
                      selected: _selectedWeek == week,
                      onSelected: (_) => setState(() {
                        _selectedWeek = week;
                        _weekChosen = true;
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (squad == null)
            // Only reachable on the self "Now" face before a first save.
            const _ViewerMessage(
              key: ValueKey('viewer_no_squad'),
              icon: Icons.sports_soccer,
              message: 'No squad saved yet — build one on My Team.',
            )
          else ...[
            if (chip != null) ...[
              _ChipBanner(label: chip),
              const SizedBox(height: 10),
            ],
            if (weekLine != null) ...[
              _WeekStrip(text: weekLine.text, live: weekLine.live),
              const SizedBox(height: 10),
            ],
            // The read-only court: no editing, armbands shown; a chip tap
            // opens that player's profile (round 3).
            FantasyCourtView(
              config: widget.config,
              slots: slots,
              slotPicks: picksToSlots(squad, slots),
              captainId: squad.captainId,
              viceId: squad.viceId,
              // The real armband: ×3 on a Triple Captain week.
              captainMultiplier: captainMultiplierFor(squad, widget.config),
              // Each player's counted points for the week shown.
              weekPointsFor: points?.chipTextFor,
              onSlotTap: null,
              onPlayerTap: widget.onOpenPlayer,
              photoUrlFor: (id) => photoByName[id],
            ),
            const SizedBox(height: 10),
            Text(
              _selectedWeek == null
                  ? 'Current squad'
                  : 'Gameweek $_selectedWeek squad',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The week's line above the court: `{W} pts` with the shared LIVE pill while
/// the week is being played, `Final · {W} pts` once settled, My Team's copy
/// for a voided / invalid week. Scheme colours, wraps — both themes, 360 px.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('viewer_week_strip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (live) ...[
            const FantasyLivePill(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              key: const ValueKey('viewer_week_strip_text'),
              softWrap: true,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The active chip on a viewed week, said out loud (transparency).
class _ChipBanner extends StatelessWidget {
  const _ChipBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    return Container(
      key: ValueKey('viewer_chip_$label'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 15, color: accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '$label active this week',
              softWrap: true,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerMessage extends StatelessWidget {
  const _ViewerMessage({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerSkeleton extends StatelessWidget {
  const _ViewerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: 220, height: 32, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 360, radius: 18),
            SizedBox(height: 12),
            SkeletonLines(count: 2),
          ],
        ),
      ),
    );
  }
}
