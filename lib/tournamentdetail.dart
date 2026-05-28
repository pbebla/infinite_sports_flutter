import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/playerstats_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/table_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/teamstats_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/teams_tab.dart';

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
  Tournament? _tournament;
  Map<String, TournamentTeam> _teams = {};
  List<TournamentMatch> _matches = [];
  Map<String, List<TournamentPlayer>> _rosters = {};
  late TabController _tabController;

  static const List<Tab> _tabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Knockout'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Team Stats'),
    Tab(text: 'Teams'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      TournamentService.getTournamentHeader(widget.tournamentId),
      TournamentService.getTeams(widget.tournamentId),
      TournamentService.getMatches(widget.tournamentId),
    ]);

    final tournament = results[0] as Tournament?;
    final teams = results[1] as Map<String, TournamentTeam>;
    final matches = results[2] as List<TournamentMatch>;

    final rosters = await TournamentService.getRosters(widget.tournamentId, teams);

    if (mounted) {
      setState(() {
        _tournament = tournament;
        _teams = teams;
        _matches = matches;
        _rosters = rosters;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    expandedHeight: 160,
                    pinned: true,
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    flexibleSpace: FlexibleSpaceBar(
                      background: _buildHeader(context),
                    ),
                    bottom: TabBar(
                      controller: _tabController,
                      tabs: _tabs,
                      isScrollable: true,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: infiniteSportsPrimaryColor,
                      indicatorWeight: 3,
                      tabAlignment: TabAlignment.start,
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  FixturesTab(
                    matches: _matches,
                    teams: _teams,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                    sport: _tournament?.sport ?? 'Soccer',
                  ),
                  TableTab(
                    teams: _teams,
                    matches: _matches,
                    tournamentId: widget.tournamentId,
                  ),
                  KnockoutTab(
                    matches: _matches,
                    teams: _teams,
                    tournamentId: widget.tournamentId,
                  ),
                  PlayerStatsTab(
                    rosters: _rosters,
                    teams: _teams,
                    tournamentId: widget.tournamentId,
                  ),
                  TeamStatsTab(teams: _teams, rosters: _rosters),
                  TeamsTab(
                    teams: _teams,
                    matches: _matches,
                    rosters: _rosters,
                    tournamentId: widget.tournamentId,
                  ),
                ],
              ),
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
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: tournament?.logoUrl != null &&
                          tournament!.logoUrl!.isNotEmpty
                      ? Image.network(
                          tournament.logoUrl!,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(
                            Icons.emoji_events,
                            size: 30,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.emoji_events,
                          size: 30,
                          color: Colors.white,
                        ),
                ),
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

