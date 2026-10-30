// The hub's Players market tab (P3c, spec §10; redesigned in round 3, spec
// §5 + owner mockup docs/superpowers/specs/assets/2026-10-29-fantasy-round3/
// mockup-players-market.webp). Every player with photo, name (wraps),
// "POS · Team" and his next game; price over total points, the latest price
// move over owned %; and the add/remove control wired to the SAME shared
// draft the My Team court edits (SquadDraftController — nothing here
// auto-saves; a dirty draft shows the "save on My Team" pill). Ineligible
// guests list last under a "Not eligible" divider, dimmed.
//
// Filters: All / GK / DEF / ATT chips, ★ (the signed-in fan's watchlist) and
// search (name or team, behind the search button). Sorts: Total Pts (the
// default once PlayerTotals exists), Form, Price, Ownership — tapping the
// active pill flips its direction; the choice lives in a session cache
// (survives filter changes and tab swipes). Without totals the market reads
// Price and the other pills are dead with a reason.
//
// The Price Risers / Price Fallers card (price_movers_card.dart) follows the
// eligible rows (owner's mockup — the rows stay above the fold), before the
// guests block, once the latest reprice moved somebody. Every row / mover
// tap opens the full fantasy player profile (with the shared draft).
//
// Data, all live streams (no RTDB get()): PlayerTotals, every PriceChanges
// week (the latest is "this week"), the league games (next game; the season
// start hour is passed so legacy times never read "0 PM" — an unknown hour
// drops the time instead) and, signed in, the watchlist. ONE fade reveal
// once every feed has landed; any failing feed degrades to "no data"
// instead of holding the skeleton. Session caches make a revisit paint at
// once.
//
// House rules: colorScheme + fantasy accent both themes (gold on dark, the
// primary red on light); names wrap, never underlined; glass-navbar bottom
// clearance; initials avatar fallback; 250ms fades, zero under reduced
// motion.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/data/next_game.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/price_movers_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_common.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

class FantasyPlayersTab extends StatefulWidget {
  const FantasyPlayersTab({
    super.key,
    required this.sport,
    required this.season,
    required this.players,
    required this.draft,
    required this.lockOverride,
    required this.gameweeks,
    this.totalsStates,
    this.priceChangeStates,
    this.gamesStates,
    this.leagueGamesFor,
    this.loadStartHour,
    this.watchlistStates,
    this.selfUidOverride,
    this.openPlayer,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// The live market (the hub streams it; guests arrive eligible=false).
  final List<FantasyPlayer> players;

  /// The hub's shared draft — the same one the My Team court edits.
  final SquadDraftController draft;

  final FantasyLockOverride lockOverride;
  final List<Gameweek> gameweeks;

  // ── Test seams — null = the real FantasyService / LeagueService feeds ──
  final Stream<Map<String, FantasyPlayerTotals>?>? totalsStates;

  /// Every gameweek's price moves (`FantasyService.watchAllPriceChanges`).
  final Stream<Map<int, Map<String, int>>>? priceChangeStates;
  final Stream<List<TournamentMatch>>? gamesStates;

  /// Replaces ONLY `LeagueService.watchGames(sport, season, startHour:)`:
  /// the start hour → games wiring and its session caches still run.
  /// Ignored when [gamesStates] is given.
  final Stream<List<TournamentMatch>> Function(int startHour)? leagueGamesFor;

  /// The season's legacy start hour (`LeagueService.getStartHour`; 0 =
  /// absent or a failed read). Null with a [gamesStates] seam = treated as
  /// known (the fed games carry their own times).
  final Future<int> Function()? loadStartHour;
  final Stream<Set<String>>? watchlistStates;

  /// '' = signed out (no ★ chip).
  final String? selfUidOverride;

  /// Opens a player (default: the full-screen fantasy profile with the
  /// shared draft).
  final OpenFantasyPlayer? openPlayer;
  final DateTime Function()? nowUtc;

  /// The session-persistent market sort + direction (spec §5: remembered
  /// for the session — survives filter changes and tab swipes). Total Pts,
  /// highest first, until the fan picks another; it reads Price while
  /// totals are absent (effectiveMarketSort). Reset by a fresh app session —
  /// or tests.
  static MarketSort sessionSort = MarketSort.points;
  static bool sessionDescending = true;

  /// Last-seen feed values per `<sport>|<season>` so a revisit paints at
  /// once (the live streams then refresh in place). The league games + start
  /// hour live in the shared games feed's cache (fantasy_schedule_feed.dart).
  static final Map<String, _MarketSession> _sessions = {};

  /// Clears the market's session snapshots (sign-out hygiene, tests) —
  /// including the shared league-games cache it paints from.
  static void clearSessionCaches() {
    _sessions.clear();
    FantasyLeagueGamesFeed.clearSessionCache();
  }

  @override
  State<FantasyPlayersTab> createState() => _FantasyPlayersTabState();
}

/// One season's last-seen market feeds (see [FantasyPlayersTab._sessions]).
class _MarketSession {
  bool totalsLoaded = false;
  Map<String, FantasyPlayerTotals>? totals;
  Map<int, Map<String, int>>? priceChanges;
  String? watchlistUid;
  Set<String>? watchlist;
}

class _FantasyPlayersTabState extends State<FantasyPlayersTab> {
  final TextEditingController _search = TextEditingController();
  bool _searchOpen = false;
  FantasyPosition? _positionFilter;
  bool _watchlistOnly = false;

  /// null = PlayerTotals absent (no finalized gameweeks): no points / owned
  /// text, and only the Price sort is live.
  Map<String, FantasyPlayerTotals>? _totals;
  bool _totalsLoaded = false;

  /// Every reprice by gameweek; null until the feed lands.
  Map<int, Map<String, int>>? _priceChanges;

  /// League games for the next-game lines, derived with the season start
  /// hour — the shared feed (fantasy_schedule_feed.dart): the hour joins a
  /// first visit's reveal gate, a revisit paints from the session, and an
  /// unknown hour drops a derived time — never "0 PM", not even on a
  /// revisit after a failed read.
  late final FantasyLeagueGamesFeed _leagueGames = FantasyLeagueGamesFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyPlayersTab',
    onChanged: () {
      if (mounted) setState(() {});
    },
    gamesStates: widget.gamesStates,
    gamesFor: widget.leagueGamesFor,
    loadStartHour: widget.loadStartHour,
  );
  Set<String> _watchlist = const {};
  bool _watchlistLoaded = false;

  /// The live feed of the "View all" sheet (it mounts its own builder; the
  /// tab's subscriptions fan out here).
  final StreamController<PriceMovesSnapshot?> _movesForSheet =
      StreamController<PriceMovesSnapshot?>.broadcast();

  StreamSubscription<Map<String, FantasyPlayerTotals>?>? _totalsSub;
  StreamSubscription<Map<int, Map<String, int>>>? _priceChangesSub;
  StreamSubscription<Set<String>>? _watchlistSub;
  Timer? _lockTicker;

  String get _sessionKey => '${widget.sport}|${widget.season}';

  _MarketSession get _session =>
      FantasyPlayersTab._sessions.putIfAbsent(_sessionKey, _MarketSession.new);

  DateTime get _now => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  // Best-effort (leaderboards convention): widget tests never touch
  // FirebaseAuth — a missing seam degrades to "signed out", not a throw.
  late final String _selfUid = () {
    final override = widget.selfUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }();

  bool get _ready =>
      _totalsLoaded &&
      _priceChanges != null &&
      _leagueGames.ready &&
      _watchlistLoaded;

  bool get _editable => squadEditable(
        lockOverride: widget.lockOverride,
        gameweeks: widget.gameweeks,
        nowUtc: _now,
      );

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_onDraftChanged);
    _seedFromSession();
    _subscribeMarketFeeds();
    _leagueGames.start();
    _subscribeWatchlist();
    // 30s tick keeps the editable/locked flip honest around the deadline
    // (same cadence as the squad builder); cancelled in dispose.
    _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// A revisit paints at once from this session's last-seen values.
  void _seedFromSession() {
    final s = FantasyPlayersTab._sessions[_sessionKey];
    if (s == null) return;
    if (s.totalsLoaded) {
      _totals = s.totals;
      _totalsLoaded = true;
    }
    _priceChanges = s.priceChanges;
    if (s.watchlist != null && s.watchlistUid == _selfUid) {
      _watchlist = s.watchlist!;
      _watchlistLoaded = true;
    }
  }

  void _subscribeMarketFeeds() {
    _totalsSub = (widget.totalsStates ??
            FantasyService.watchPlayerTotals(widget.sport, widget.season))
        .listen((totals) {
      _session
        ..totals = totals
        ..totalsLoaded = true;
      if (!mounted) return;
      setState(() {
        _totals = totals;
        _totalsLoaded = true;
      });
      _pushMovesForSheet();
    }, onError: (Object _) {
      if (mounted) setState(() => _totalsLoaded = true);
    });
    _priceChangesSub = (widget.priceChangeStates ??
            FantasyService.watchAllPriceChanges(widget.sport, widget.season))
        .listen((changes) {
      _session.priceChanges = changes;
      if (!mounted) return;
      setState(() => _priceChanges = changes);
      _pushMovesForSheet();
    }, onError: (Object _) {
      if (mounted) setState(() => _priceChanges ??= const {});
    });
  }

  void _subscribeWatchlist() {
    if (_selfUid.isEmpty) {
      _watchlistLoaded = true; // signed out: no ★ chip, nothing to wait for
      return;
    }
    _watchlistSub = (widget.watchlistStates ??
            FantasyService.watchWatchlist(
                widget.sport, widget.season, _selfUid))
        .listen((names) {
      _session
        ..watchlist = names
        ..watchlistUid = _selfUid;
      if (!mounted) return;
      setState(() {
        _watchlist = names;
        _watchlistLoaded = true;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _watchlistLoaded = true);
    });
  }

  @override
  void didUpdateWidget(FantasyPlayersTab old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      old.draft.removeListener(_onDraftChanged);
      widget.draft.addListener(_onDraftChanged);
    }
    // The broadcast stream delivers asynchronously — safe mid-build.
    if (old.players != widget.players) _pushMovesForSheet();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.draft.removeListener(_onDraftChanged);
    _totalsSub?.cancel();
    _priceChangesSub?.cancel();
    _leagueGames.dispose();
    _watchlistSub?.cancel();
    _movesForSheet.close();
    _lockTicker?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  ({MarketSort sort, bool descending}) get _sort => effectiveMarketSort(
        FantasyPlayersTab.sessionSort,
        descending: FantasyPlayersTab.sessionDescending,
        hasTotals: _totals != null,
      );

  /// Every move of the latest reprice for players in the market; null
  /// before any reprice or when the latest one moved nobody (the card and
  /// the sheet's content then hide).
  PriceMovesSnapshot? _movesSnapshot() {
    final latest = latestPriceMoves(_priceChanges ?? const {});
    if (latest == null) return null;
    final all = sortedPriceMoves(latest.changes, widget.players, _totals);
    if (all.risers.isEmpty && all.fallers.isEmpty) return null;
    return PriceMovesSnapshot(
      gameweek: latest.gameweek,
      risers: all.risers,
      fallers: all.fallers,
    );
  }

  void _pushMovesForSheet() {
    if (_movesForSheet.hasListener) _movesForSheet.add(_movesSnapshot());
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  void _tapSort(MarketSort tapped) {
    final current = _sort;
    final next = tapMarketSort(
      current: current.sort,
      descending: current.descending,
      tapped: tapped,
    );
    setState(() {
      FantasyPlayersTab.sessionSort = next.sort;
      FantasyPlayersTab.sessionDescending = next.descending;
    });
  }

  void _toggleSearch() {
    setState(() {
      if (_searchOpen) _search.clear();
      _searchOpen = !_searchOpen;
    });
  }

  void _add(FantasyPlayer player) {
    widget.draft.addPlayer(player);
  }

  void _remove(FantasyPlayer player) {
    final message = widget.draft.removePlayer(player.name);
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openPlayer(BuildContext context, String name) {
    final open = widget.openPlayer;
    if (open != null) {
      open(context, name);
      return;
    }
    openFantasyPlayerProfile(
      context,
      sport: widget.sport,
      season: widget.season,
      playerName: name,
      draft: widget.draft,
    );
  }

  void _openAllMoves() {
    final snapshot = _movesSnapshot();
    if (snapshot == null) return;
    showPriceMovesSheet(
      context,
      initial: snapshot,
      updates: _movesForSheet.stream,
      onOpenPlayer: _openPlayer,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _ready
          ? _market(context)
          : const _MarketSkeleton(key: ValueKey('players_market_skeleton')),
    );
  }

  Widget _market(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editable = _editable;
    final sort = _sort;
    final signedIn = _selfUid.isNotEmpty;
    final watchlistOnly = signedIn && _watchlistOnly;
    final market = composeMarket(
      players: widget.players,
      query: _search.text,
      position: _positionFilter,
      sort: sort.sort,
      descending: sort.descending,
      totals: _totals,
      watchlist: _watchlist,
      watchlistOnly: watchlistOnly,
    );
    final latest = latestPriceMoves(_priceChanges ?? const {});
    final moves = _movesSnapshot();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final appear =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 250);

    // One next-game text per team (rows of a team share it).
    final now = _now.toLocal();
    final nextByTeam = <String, String?>{};
    String? nextFor(FantasyPlayer p) => nextByTeam.putIfAbsent(p.teamName, () {
          final next = nextGameForTeam(p.teamName, _leagueGames.games, now);
          return next == null
              ? null
              : nextGameText(next,
                  startHourKnown: _leagueGames.startHourKnown);
        });

    Widget row(FantasyPlayer p) => _row(
          p,
          editable,
          next: nextFor(p),
          latestGameweek: latest?.gameweek,
          move: latest?.changes[p.name],
        );

    // List order (owner's mockup): the eligible rows (or the empty state),
    // then the Price Changes card, then the "Not eligible" guests block —
    // the player rows stay above the fold, the card never splits a section.
    final rowCount = market.eligible.length + market.ineligible.length;
    final mainCount = rowCount == 0 ? 1 : market.eligible.length;
    final cardCount = moves == null ? 0 : 1;
    final guestCount =
        market.ineligible.isEmpty ? 0 : 1 + market.ineligible.length;
    final itemCount = mainCount + cardCount + guestCount;

    return Column(
      key: const ValueKey('players_market'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filters(context, signedIn),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              key: const ValueKey('market_search'),
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search players or teams',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        _sortBar(context, sort),
        // Cross-tab honesty (Task 1): the market edits the draft, the SAVE
        // lives on My Team — say so whenever the draft is dirty.
        AnimatedSwitcher(
          duration: appear,
          child: widget.draft.dirty
              ? Padding(
                  key: const ValueKey('unsaved_pill'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: fantasyAccent(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color:
                              fantasyAccent(context).withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.pending_actions,
                            size: 15, color: fantasyAccent(context)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Unsaved changes — save on My Team',
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
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no_unsaved_pill')),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('market_list'),
            padding: EdgeInsets.fromLTRB(
                0, 4, 0, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: itemCount,
            itemBuilder: (context, i) {
              if (i < mainCount) {
                return rowCount == 0
                    ? _EmptyMarket(
                        watchlistEmpty: watchlistOnly && _watchlist.isEmpty,
                      )
                    : row(market.eligible[i]);
              }
              var k = i - mainCount;
              if (moves != null && k == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: PriceMoversCard(
                    key: const ValueKey('price_movers_card'),
                    gameweek: moves.gameweek,
                    movers: computePriceMovers(
                      latest!.changes,
                      widget.players,
                      _totals,
                      position: _positionFilter?.db,
                    ),
                    position: _positionFilter?.db,
                    onOpenPlayer: _openPlayer,
                    onViewAll: _openAllMoves,
                  ),
                );
              }
              k -= cardCount;
              if (k == 0) return const _NotEligibleDivider();
              return row(market.ineligible[k - 1]);
            },
          ),
        ),
      ],
    );
  }

  /// All / GK / DEF / ATT, ★ (signed in) — scrolls sideways if a big text
  /// scale needs it — and the search button.
  Widget _filters(BuildContext context, bool signedIn) {
    final scheme = Theme.of(context).colorScheme;
    final searchActive = _searchOpen || _search.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (label, pos) in [
                    ('All', null),
                    ('GK', FantasyPosition.gk),
                    ('DEF', FantasyPosition.def),
                    ('ATT', FantasyPosition.att),
                  ]) ...[
                    _FilterPill(
                      key: ValueKey('market_pos_$label'),
                      selected: _positionFilter == pos,
                      semanticsLabel: label == 'All'
                          ? 'All positions'
                          : '${positionLabel(pos!)}s',
                      onTap: () => setState(() => _positionFilter = pos),
                      child: Text(label),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (signedIn)
                    _FilterPill(
                      key: const ValueKey('market_watchlist_chip'),
                      selected: _watchlistOnly,
                      semanticsLabel: 'Watchlist',
                      onTap: () =>
                          setState(() => _watchlistOnly = !_watchlistOnly),
                      child: Icon(
                        _watchlistOnly
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 19,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('market_search_toggle'),
            tooltip: _searchOpen ? 'Close search' : 'Search players or teams',
            onPressed: _toggleSearch,
            icon: Icon(
              _searchOpen ? Icons.close : Icons.search,
              color: searchActive
                  ? fantasyAccent(context)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Total Pts · Form · Price · Ownership; the active pill carries the
  /// direction arrow (↓ highest first, ↑ lowest first).
  Widget _sortBar(
      BuildContext context, ({MarketSort sort, bool descending}) sort) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final s in MarketSort.values)
              Expanded(
                child: _SortPill(
                  key: ValueKey('market_sort_${s.name}'),
                  sortKey: s.name,
                  label: switch (s) {
                    MarketSort.points => 'Total Pts',
                    MarketSort.form => 'Form',
                    MarketSort.price => 'Price',
                    MarketSort.ownership => 'Ownership',
                  },
                  active: sort.sort == s,
                  descending: sort.descending,
                  enabled: !marketSortNeedsTotals(s) || _totals != null,
                  onTap: () => _tapSort(s),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    FantasyPlayer p,
    bool editable, {
    required String? next,
    required int? latestGameweek,
    required int? move,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availability = marketAddState(
      player: p,
      slots: widget.draft.slots,
      slotPicks: widget.draft.picks,
      budgetTenths: widget.draft.config.budgetTenths,
      editable: editable,
      unplaced: widget.draft.unplaced,
    );
    final totals = _totals?[p.name];
    final unaffordable = availability == MarketAddAvailability.unaffordable;
    final pct = totals?.ownershipPct;
    final showMoveColumn = latestGameweek != null || _totals != null;
    final muted = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      child: Row(
        children: [
          FantasyAvatar(name: p.name, photoUrl: p.photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  // Wraps, never ellipsized or underlined (house rules).
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  '${p.position.db} · ${p.teamName}',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (next != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      next,
                      key: ValueKey('market_next_${p.name}'),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoneyTenths(p.priceTenths),
                  key: ValueKey('market_price_${p.name}'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    // Unaffordable = the price itself carries the warning;
                    // otherwise gold on dark (mockup), plain text on light
                    // (the light accent is red — it would read "too dear").
                    color: unaffordable
                        ? fantasyDownRed(context)
                        : (isDark ? fantasyAccent(context) : scheme.onSurface),
                  ),
                ),
                // Points only once finalized totals exist — never a made-up 0.
                if (_totals != null)
                  Text(
                    pointsText(totals?.points ?? 0),
                    key: ValueKey('market_points_${p.name}'),
                    style: muted,
                  ),
              ],
            ),
          ),
          if (showMoveColumn) ...[
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (latestGameweek != null)
                    _moveIcon(
                      context,
                      key: ValueKey('market_move_${p.name}'),
                      move: move,
                      gameweek: latestGameweek,
                    ),
                  if (pct != null)
                    Text(
                      '${pct.toStringAsFixed(0)}%',
                      key: ValueKey('market_owned_${p.name}'),
                      style: muted,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 2),
          _MarketAddControl(
            player: p,
            availability: availability,
            onAdd: () => _add(p),
            onRemove: () => _remove(p),
          ),
        ],
      ),
    );

    return InkWell(
      key: ValueKey('market_row_${p.name}'),
      onTap: () => _openPlayer(context, p.name),
      child: p.eligible ? content : Opacity(opacity: 0.55, child: content),
    );
  }
}

/// The latest reprice's move as an icon: ▲ pitch green / ▼ error red / —
/// muted (not moved). Says it in words to screen readers.
Widget _moveIcon(
  BuildContext context, {
  required Key key,
  required int? move,
  required int gameweek,
}) {
  final m = move ?? 0;
  return Icon(
    m > 0
        ? Icons.arrow_drop_up
        : m < 0
            ? Icons.arrow_drop_down
            : Icons.remove,
    key: key,
    size: m == 0 ? 16 : 24,
    color: profileMoveColor(context, m),
    semanticLabel: m == 0
        ? 'No price change after Gameweek $gameweek'
        : 'Price ${m > 0 ? 'up' : 'down'} '
            '${formatMoneyTenths(m.abs())} after Gameweek $gameweek',
  );
}

/// A position / ★ filter pill: the fantasy accent when selected (gold with
/// black on dark, the primary red with onPrimary on light), a quiet surface
/// otherwise.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.selected,
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected
        ? (isDark ? Colors.black : scheme.onPrimary)
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? accent : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: selected
                ? accent
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One sort pill. Dead (with the reason on tap) while it needs totals that
/// don't exist yet.
class _SortPill extends StatelessWidget {
  const _SortPill({
    super.key,
    required this.sortKey,
    required this.label,
    required this.active,
    required this.descending,
    required this.enabled,
    required this.onTap,
  });

  final String sortKey;
  final String label;
  final bool active;
  final bool descending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = active
        ? (isDark ? Colors.black : scheme.onPrimary)
        : enabled
            ? scheme.onSurfaceVariant
            : scheme.onSurfaceVariant.withValues(alpha: 0.4);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      // A control label, not a name: it may scale down at huge text sizes
      // rather than overflow.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                color: fg,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(
                descending ? Icons.arrow_downward : Icons.arrow_upward,
                key: const ValueKey('market_sort_dir'),
                size: 14,
                color: fg,
              ),
            ],
          ],
        ),
      ),
    );
    if (!enabled) {
      return Tooltip(
        key: ValueKey('market_sort_disabled_$sortKey'),
        message: 'Available once Gameweek 1 is scored.',
        triggerMode: TooltipTriggerMode.tap,
        child: pill,
      );
    }
    return Semantics(
      button: true,
      selected: active,
      label: active
          ? '$label, ${descending ? 'highest first' : 'lowest first'}'
          : 'Sort by $label',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}

/// "No players match." — or, on the ★ filter with nothing starred, how to
/// star someone.
class _EmptyMarket extends StatelessWidget {
  const _EmptyMarket({required this.watchlistEmpty});

  final bool watchlistEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!watchlistEmpty) {
      return Padding(
        key: const ValueKey('market_empty'),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Text(
          'No players match.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      key: const ValueKey('market_watchlist_empty'),
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
      child: Column(
        children: [
          Icon(Icons.star_outline_rounded,
              size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'No starred players yet',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Tap the star on a player's profile to add him to your "
            'watchlist.',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The row's add/remove control (shared rules with the player profile's
/// button via market_logic): live add = accent +, in-squad = accent check
/// (tap removes), everything else = greyed + with a tap-to-see reason.
class _MarketAddControl extends StatelessWidget {
  const _MarketAddControl({
    required this.player,
    required this.availability,
    required this.onAdd,
    required this.onRemove,
  });

  final FantasyPlayer player;
  final MarketAddAvailability availability;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    switch (availability) {
      case MarketAddAvailability.inSquad:
        return IconButton(
          key: ValueKey('market_remove_${player.name}'),
          tooltip: 'In your team — tap to remove',
          icon: Icon(Icons.check_circle, color: accent),
          onPressed: onRemove,
          visualDensity: VisualDensity.compact,
        );
      case MarketAddAvailability.addable:
        return IconButton(
          key: ValueKey('market_add_${player.name}'),
          tooltip: 'Add to team',
          icon: Icon(Icons.add_circle_outline, color: accent),
          onPressed: onAdd,
          visualDensity: VisualDensity.compact,
        );
      case MarketAddAvailability.locked:
      case MarketAddAvailability.ineligible:
      case MarketAddAvailability.positionFull:
      case MarketAddAvailability.unaffordable:
        // Tooltip-style reason on tap (the button is dead, the WHY isn't).
        return Tooltip(
          key: ValueKey('market_add_disabled_${player.name}'),
          message: marketAddReason(availability, player.position)!,
          triggerMode: TooltipTriggerMode.tap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              availability == MarketAddAvailability.locked
                  ? Icons.lock_outline
                  : Icons.add_circle_outline,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.38),
            ),
          ),
        );
    }
  }
}

/// The small divider heading the disabled guest section.
class _NotEligibleDivider extends StatelessWidget {
  const _NotEligibleDivider();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('not_eligible_divider'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(
        children: [
          Text(
            'Not eligible',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// The market's loading shape (filters, sort bar, rows) until every feed
/// has landed — then ONE fade to the real market.
class _MarketSkeleton extends StatelessWidget {
  const _MarketSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      children: [
        const Row(
          children: [
            SkeletonBox(width: 46, height: 34, radius: 11),
            SizedBox(width: 6),
            SkeletonBox(width: 46, height: 34, radius: 11),
            SizedBox(width: 6),
            SkeletonBox(width: 52, height: 34, radius: 11),
            SizedBox(width: 6),
            SkeletonBox(width: 52, height: 34, radius: 11),
          ],
        ),
        const SizedBox(height: 10),
        const SkeletonBox(width: double.infinity, height: 38, radius: 12),
        const SizedBox(height: 8),
        for (var i = 0; i < 7; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                SkeletonBox(width: 44, height: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 140, height: 13),
                      SizedBox(height: 6),
                      SkeletonBox(width: 90, height: 11),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBox(width: 44, height: 28, radius: 8),
              ],
            ),
          ),
      ],
    );
  }
}
