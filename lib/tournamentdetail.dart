import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/playerstats_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/table_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/teams_tab.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

class TournamentDetailPage extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const TournamentDetailPage({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<TournamentDetailPage> createState() => _TournamentDetailPageState();
}

class _TournamentDetailPageState extends State<TournamentDetailPage>
    // TickerProviderStateMixin (not Single-): the bleed fix recreates the
    // TabController when the tournament identity changes, so this State can
    // legitimately own more than one ticker over its lifetime.
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _loadError;
  Tournament? _tournament;
  Map<String, TournamentTeam> _teams = {};
  List<TournamentMatch> _matches = [];
  StreamSubscription<TournamentBundle?>? _bundleSub;
  Map<String, List<TournamentPlayer>> _rosters = {};
  // Memoized full-tournament aggregation (lag fix): computed only when
  // matches/rosters actually change (_recomputeStats), NEVER in build —
  // recomputing per frame made tab swipes and live-score ticks visibly
  // janky on device.
  ComputedTournamentStats? _stats;

  static const List<Tab> _baseTabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Knockout'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Teams'),
  ];

  PredictionConfig? _predictionConfig;
  List<Tab> _tabs = const [];
  TabController? _tabController;
  int _predictIndex = -1;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  /// Cross-tournament bleed fix (owner bug report 2026-07-30): this State
  /// only subscribed in initState, so if Flutter reuses the element with a
  /// DIFFERENT tournamentId (position-based reuse in tab/list structures —
  /// reproduced in integration_test/tournament_bleed_test.dart) the page
  /// kept rendering the previous tournament's teams/matches/stats. On an
  /// identity change: drop the bundle stream and every piece of loaded
  /// state, show the skeleton, and re-subscribe as if freshly pushed.
  @override
  void didUpdateWidget(covariant TournamentDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tournamentId == widget.tournamentId) return;
    _bundleSub?.cancel();
    _bundleSub = null;
    _tabController?.dispose();
    _tabController = null;
    setState(() {
      _isLoading = true;
      _loadError = null;
      _tournament = null;
      _teams = {};
      _matches = [];
      _rosters = {};
      _stats = null;
      _predictionConfig = null;
      _tabs = const [];
      _predictIndex = -1;
    });
    _subscribe();
  }

  @override
  void dispose() {
    _bundleSub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  /// League-style live bundle (iOS wrong-node fix): ONE onValue listener on
  /// the whole `/Tournaments/<id>` node feeds every tab — the architecture
  /// the league pages use, which never exhibited the bug. The old shape
  /// (one-shot bundle get() + two side streams) was poisoned on iOS: with
  /// FrontPage's permanent /Tournaments root listener up, get() under that
  /// path can return the ROOT map, whose tournament children then rendered
  /// as this page's "teams". Listeners don't share the defect, and the
  /// stream also keeps header/teams/table/rosters/config live in place.
  void _subscribe() {
    // Identity guard (bleed fix): the subscription is per-id — if
    // didUpdateWidget swaps the tournament, late events from the old stream
    // must drop instead of writing tournament A's data into B's page.
    final loadId = widget.tournamentId;
    bool stale() => !mounted || loadId != widget.tournamentId;
    _bundleSub?.cancel();
    _bundleSub =
        TournamentService.watchTournamentBundle(loadId).listen((bundle) {
      if (stale()) return;
      // null = unusable snapshot (missing node, or the root-shape guard in
      // parseTournamentBundle refused a /Tournaments-root payload): keep the
      // last good state — the skeleton on first load — never render garbage.
      if (bundle == null) return;
      _applyBundle(bundle);
    }, onError: (Object e, StackTrace st) {
      debugPrint('TournamentDetailPage bundle stream error: $e\n$st');
      if (stale()) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load tournament. Tap retry.';
      });
    });
  }

  void _applyBundle(TournamentBundle bundle) {
    final loadId = widget.tournamentId;
    final rosters = bundle.rosters;
    final config = bundle.config;
    final tabs = <Tab>[..._baseTabs];
    if (config.open) tabs.add(const Tab(text: 'Predict'));

    setState(() {
      // A momentarily headerless snapshot keeps the last good header rather
      // than blanking it (same rule the old watchTournament stream had).
      _tournament = bundle.tournament ?? _tournament;
      _teams = bundle.teams;
      _matches = bundle.matches;
      _rosters = rosters;
      // Memoized (lag fix): recomputed once per stream event, NEVER in
      // build — per-frame recomputes made tab swipes visibly janky.
      _stats = computeTournamentStats(
        matches: bundle.matches,
        rosters: rosters,
        sport: (bundle.tournament ?? _tournament)?.sport ?? 'Soccer',
      );
      _isLoading = false;
      _loadError = null;
      _predictionConfig = config;
      _tabs = tabs;
      _predictIndex = config.open ? tabs.length - 1 : -1;
      // Predictions can open/close LIVE now: rebuild the controller only
      // when the tab count actually changes, keeping the reader's place
      // (clamped in case they were on the tab that just disappeared).
      if (_tabController == null || _tabController!.length != tabs.length) {
        final old = _tabController;
        final keptIndex = old == null
            ? 0
            : (old.index < tabs.length ? old.index : tabs.length - 1);
        old?.dispose();
        _tabController = TabController(
            length: tabs.length, vsync: this, initialIndex: keptIndex);
      }
    });

    // Avatars for linked players never gate paint (perceived-perf rule) and
    // land in a single follow-up update. Fetch only when some linked uid is
    // missing from the session cache — otherwise every live score tick
    // would spawn a redundant enrichment pass + setState.
    if (TournamentService.rosterPhotosPending(rosters)) {
      TournamentService.enrichRosterPhotos(rosters).then((enriched) {
        if (!mounted || loadId != widget.tournamentId) return;
        // A newer bundle event replaced the rosters while photos were in
        // flight: its own pending-check covers it — don't stomp newer data.
        if (!identical(_rosters, rosters)) return;
        setState(() {
          _rosters = enriched;
          _stats = computeTournamentStats(
            matches: _matches,
            rosters: enriched,
            sport: _tournament?.sport ?? 'Soccer',
          );
        });
      });
    }
  }

  Widget _buildErrorView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tournamentName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _loadError ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                  });
                  // Re-subscribe from scratch: an errored RTDB stream is done.
                  _subscribe();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return _buildErrorView(context);
    }
    return Scaffold(
      body: (_isLoading || _tabController == null)
          ? Column(
              children: [
                // Placeholder for the scoreboard/header area (white in light
                // mode, dark grey in dark mode — P4.1).
                Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: TournamentColors.headerBackground(context),
                      border: TournamentColors.headerHairline(context),
                    )),
                const Expanded(
                  child: SingleChildScrollView(
                    physics: NeverScrollableScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SkeletonMatchList(count: 8),
                    ),
                  ),
                ),
              ],
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    expandedHeight: 160,
                    pinned: true,
                    backgroundColor:
                        TournamentColors.headerBackground(context),
                    foregroundColor:
                        TournamentColors.headerForeground(context),
                    // Theme-aware back arrow + bell (P4.1): dark on the
                    // white light-mode header, white on the dark grey.
                    iconTheme: IconThemeData(
                        color: TournamentColors.headerForeground(context)),
                    actionsIconTheme: IconThemeData(
                        color: TournamentColors.headerForeground(context)),
                    actions: [
                      FollowBell(
                        topic: tournamentTopic(widget.tournamentId),
                        label: _tournament?.name ?? widget.tournamentName,
                        kind: 'tournament',
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHeader(context),
                    ),
                    bottom: TabBar(
                      controller: _tabController!,
                      tabs: _tabs,
                      isScrollable: true,
                      labelColor: TournamentColors.headerForeground(context),
                      unselectedLabelColor:
                          TournamentColors.headerForegroundMuted(context),
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      indicatorWeight: 3,
                      tabAlignment: TabAlignment.start,
                    ),
                  ),
                ];
              },
              body: Builder(builder: (context) {
                // Memoized in state — recomputing here ran the full
                // aggregation on every frame of a tab swipe (lag fix).
                final stats = _stats ??
                    computeTournamentStats(
                      matches: _matches,
                      rosters: _rosters,
                      sport: _tournament?.sport ?? 'Soccer',
                    );
                return TabBarView(
                controller: _tabController!,
                children: [
                  FixturesTab(
                    matches: _matches,
                    teams: _teams,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                    sport: _tournament?.sport ?? 'Soccer',
                    predictionsOpen: _predictionConfig?.open ?? false,
                    onOpenPredict: (_predictIndex >= 0)
                        ? () => _tabController?.animateTo(_predictIndex)
                        : null,
                  ),
                  TableTab(
                    teams: _teams,
                    matches: _matches,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                    sport: _tournament?.sport ?? 'Soccer',
                  ),
                  KnockoutTab(
                    matches: _matches,
                    teams: _teams,
                    tournamentId: widget.tournamentId,
                    rosters: _rosters,
                    sport: _tournament?.sport ?? 'Soccer',
                  ),
                  PlayerStatsTab(
                    rosters: _rosters,
                    teams: _teams,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                    sport: _tournament?.sport ?? 'Soccer',
                  ),
                  TeamsTab(
                    teams: _teams,
                    matches: _matches,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                    stats: stats,
                    sport: _tournament?.sport ?? 'Soccer',
                  ),
                  if (_predictionConfig?.open ?? false)
                    PredictTab(
                      matches: _matches,
                      teams: _teams,
                      tournamentId: widget.tournamentId,
                      config: _predictionConfig!,
                      currentUid: FirebaseAuth.instance.currentUser?.uid,
                      rosters: _rosters,
                    ),
                ],
              );
              }),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tournament = _tournament;
    final fg = TournamentColors.headerForeground(context);
    final muted = TournamentColors.headerForegroundMuted(context);
    return Container(
      decoration: BoxDecoration(
        gradient: TournamentColors.headerGradient(context),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 8, 16, 52),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Tournament logo
              TeamLogo(
                url: tournament?.logoUrl,
                size: 54,
                fallbackIcon: Icons.emoji_events,
                fallbackBackground: TournamentColors.headerChipFill(context),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament?.name ?? widget.tournamentName,
                      style: TextStyle(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (tournament?.sport != null) tournament!.sport,
                        if (tournament?.hostCity != null)
                          tournament!.hostCity!,
                      ].join(' · '),
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                      ),
                    ),
                    if (tournament?.finished == true &&
                        tournament?.champion != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.emoji_events,
                              size: 14,
                              color: TournamentColors.championGold(context)),
                          const SizedBox(width: 4),
                          Text(
                            tournament!.champion!,
                            style: TextStyle(
                              color: fg,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Status chip
              if (tournament?.status != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: muted),
                  ),
                  child: Text(
                    tournament!.status,
                    style: TextStyle(
                        color: fg,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

