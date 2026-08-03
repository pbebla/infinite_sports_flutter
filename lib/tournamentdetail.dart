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
  StreamSubscription<List<TournamentMatch>>? _matchesSub;
  StreamSubscription<Tournament?>? _tournamentSub;
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
    _loadData();
  }

  /// Cross-tournament bleed fix (owner bug report 2026-07-30): this State
  /// only loaded in initState, so if Flutter reuses the element with a
  /// DIFFERENT tournamentId (position-based reuse in tab/list structures —
  /// reproduced in integration_test/tournament_bleed_test.dart) the page
  /// kept rendering the previous tournament's teams/matches/stats. On an
  /// identity change: drop every stream and every piece of loaded state,
  /// show the skeleton, and reload as if freshly pushed.
  @override
  void didUpdateWidget(covariant TournamentDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tournamentId == widget.tournamentId) return;
    _matchesSub?.cancel();
    _matchesSub = null;
    _tournamentSub?.cancel();
    _tournamentSub = null;
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
    _loadData();
  }

  @override
  void dispose() {
    _matchesSub?.cancel();
    _tournamentSub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Identity guard (bleed fix): if didUpdateWidget swaps the tournament
    // while this load is in flight, every continuation below must drop its
    // results instead of writing tournament A's data into B's page (or
    // re-binding A's live streams over B's).
    final loadId = widget.tournamentId;
    bool stale() => !mounted || loadId != widget.tournamentId;
    try {
      // One read of the whole tournament node (was five parallel get()s:
      // header + Teams/Table + Matches + PredictionConfig + Rosters). The
      // whole-node header get overlapped its own children and firebase-ios-sdk
      // races overlapping get()s — see TournamentService.getTournamentBundle.
      // Everything parses out of the single snapshot; avatar fetches still
      // never gate first paint.
      final bundle = await TournamentService.getTournamentBundle(loadId);

      final tournament = bundle.tournament;
      final teams = bundle.teams;
      final matches = bundle.matches;
      final config = bundle.config;
      final rosters = TournamentService.parseRosters(bundle.rostersNode, teams);

      final tabs = <Tab>[..._baseTabs];
      if (config.open) tabs.add(const Tab(text: 'Predict'));

      if (stale()) return;
      setState(() {
        _tournament = tournament;
        _teams = teams;
        _matches = matches;
        _rosters = rosters;
        _stats = computeTournamentStats(
          matches: matches,
          rosters: rosters,
          sport: tournament?.sport ?? 'Soccer',
        );
        _isLoading = false;
        _loadError = null;
        _predictionConfig = config;
        _tabs = tabs;
        _predictIndex = config.open ? tabs.length - 1 : -1;
        _tabController = TabController(length: tabs.length, vsync: this);
      });

      // Avatars for linked players not yet in the session cache land in a
      // single follow-up update behind the first paint.
      TournamentService.enrichRosterPhotos(rosters).then((enriched) {
        if (stale()) return;
        setState(() {
          _rosters = enriched;
          _stats = computeTournamentStats(
            matches: _matches,
            rosters: enriched,
            sport: _tournament?.sport ?? 'Soccer',
          );
        });
      });

      // Keep matches live after the initial paint: scores, clock, standings and
      // the bracket all update in place without a manual refresh.
      if (stale()) return;
      _matchesSub?.cancel();
      _matchesSub = TournamentService.watchMatches(loadId).listen((live) {
        if (stale() || live.isEmpty) return;
        setState(() {
          _matches = live;
          _stats = computeTournamentStats(
            matches: live,
            rosters: _rosters,
            sport: _tournament?.sport ?? 'Soccer',
          );
        });
      });

      // Keep the header live too: name/status/sport/champion update in place
      // (e.g. the owner flips status or crowns a champion) without a manual
      // refresh. Same mirrored one-shot-then-live shape as matches above; a
      // null emission means the record is momentarily unparseable, so the
      // last good header is kept rather than blanked.
      _tournamentSub?.cancel();
      _tournamentSub = TournamentService.watchTournament(loadId).listen((live) {
        if (stale() || live == null) return;
        setState(() => _tournament = live);
      });
    } catch (e, st) {
      debugPrint('TournamentDetailPage._loadData error: $e\n$st');
      if (stale()) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load tournament. Tap retry.';
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
                  _loadData();
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

