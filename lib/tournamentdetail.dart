import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _loadError;
  Tournament? _tournament;
  Map<String, TournamentTeam> _teams = {};
  List<TournamentMatch> _matches = [];
  StreamSubscription<List<TournamentMatch>>? _matchesSub;
  Map<String, List<TournamentPlayer>> _rosters = {};

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

  @override
  void dispose() {
    _matchesSub?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        TournamentService.getTournamentHeader(widget.tournamentId),
        TournamentService.getTeams(widget.tournamentId),
        TournamentService.getMatches(widget.tournamentId),
      ]);

      final tournament = results[0] as Tournament?;
      final teams = results[1] as Map<String, TournamentTeam>;
      final matches = results[2] as List<TournamentMatch>;

      final rosters =
          await TournamentService.getRosters(widget.tournamentId, teams);

      final config =
          await TournamentService.getPredictionConfig(widget.tournamentId);
      final tabs = <Tab>[..._baseTabs];
      if (config.open) tabs.add(const Tab(text: 'Predict'));

      if (!mounted) return;
      setState(() {
        _tournament = tournament;
        _teams = teams;
        _matches = matches;
        _rosters = rosters;
        _isLoading = false;
        _loadError = null;
        _predictionConfig = config;
        _tabs = tabs;
        _predictIndex = config.open ? tabs.length - 1 : -1;
        _tabController = TabController(length: tabs.length, vsync: this);
      });

      // Keep matches live after the initial paint: scores, clock, standings and
      // the bracket all update in place without a manual refresh.
      _matchesSub?.cancel();
      _matchesSub =
          TournamentService.watchMatches(widget.tournamentId).listen((live) {
        if (!mounted || live.isEmpty) return;
        setState(() => _matches = live);
      });
    } catch (e, st) {
      debugPrint('TournamentDetailPage._loadData error: $e\n$st');
      if (!mounted) return;
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
                // Placeholder for the navy scoreboard/header area.
                Container(height: 150, color: const Color(0xFF1A237E)),
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
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
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
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      indicatorWeight: 3,
                      tabAlignment: TabAlignment.start,
                    ),
                  ),
                ];
              },
              body: Builder(builder: (context) {
                final stats = computeTournamentStats(
                  matches: _matches,
                  rosters: _rosters,
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
                  ),
                  TeamsTab(
                    teams: _teams,
                    matches: _matches,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                    stats: stats,
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
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
                fallbackBackground: Colors.white.withValues(alpha: 0.15),
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
                      style: const TextStyle(
                        color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    if (tournament?.finished == true &&
                        tournament?.champion != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.emoji_events,
                              size: 14, color: Color(0xFFFFD700)),
                          const SizedBox(width: 4),
                          Text(
                            tournament!.champion!,
                            style: const TextStyle(
                              color: Colors.white,
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
                    border: Border.all(color: Colors.white60),
                  ),
                  child: Text(
                    tournament!.status,
                    style: const TextStyle(
                        color: Colors.white,
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

