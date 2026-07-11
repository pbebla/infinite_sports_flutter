import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/league_tabs/league_fixtures_tab.dart';
import 'package:infinite_sports_flutter/league_tabs/league_player_stats_tab.dart';
import 'package:infinite_sports_flutter/league_tabs/league_playoffs_tab.dart';
import 'package:infinite_sports_flutter/league_tabs/league_table_tab.dart';
import 'package:infinite_sports_flutter/league_tabs/league_teams_tab.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Tournament-parity league season page (League Experience P2): Fixtures /
/// Table / Playoffs / Player Stats / Teams — all live-streamed (games,
/// standings, Line Ups, Playoffs), with skeleton loaders and the same navy
/// header as TournamentDetailPage. Futsal only until P4; other sports keep
/// ShowLeaguePage.
class LeagueDetailPage extends StatefulWidget {
  final String sport;
  final String season;

  const LeagueDetailPage({
    super.key,
    this.sport = 'Futsal',
    required this.season,
  });

  @override
  State<LeagueDetailPage> createState() => _LeagueDetailPageState();
}

class _LeagueDetailPageState extends State<LeagueDetailPage>
    with SingleTickerProviderStateMixin {
  static const List<Tab> _tabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Playoffs'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Teams'),
  ];

  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  // null = that stream's first snapshot hasn't arrived → tab skeleton.
  List<TournamentMatch>? _matches;
  List<TournamentTeam>? _standings;
  Map<String, List<TournamentPlayer>>? _rosters;
  LeaguePlayoffs? _playoffs;
  bool _playoffsLoaded = false; // null is meaningful (no playoffs yet)
  Map<String, String> _logos = {};
  int _startHour = 0;

  StreamSubscription<List<TournamentMatch>>? _gamesSub;
  StreamSubscription<List<TournamentTeam>>? _standingsSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rostersSub;
  StreamSubscription<LeaguePlayoffs?>? _playoffsSub;

  @override
  void initState() {
    super.initState();
    // First paint speed (P2.1): the 4 streams subscribe IMMEDIATELY with
    // default display seeds (startHour 0, no logos) instead of waiting two
    // round trips; the seeds re-apply below when they arrive.
    _subscribeGames();
    _subscribeStandings();
    _rostersSub =
        LeagueService.watchRosters(widget.sport, widget.season).listen((r) {
      if (mounted) setState(() => _rosters = r);
    });
    _playoffsSub =
        LeagueService.watchPlayoffs(widget.sport, widget.season).listen((p) {
      if (mounted) {
        setState(() {
          _playoffs = p;
          _playoffsLoaded = true;
        });
      }
    });
    _loadDisplaySeeds();
  }

  void _subscribeGames() {
    _gamesSub?.cancel();
    _gamesSub = LeagueService
        .watchGames(widget.sport, widget.season, startHour: _startHour)
        .listen((m) {
      if (mounted) setState(() => _matches = m);
    });
  }

  void _subscribeStandings() {
    _standingsSub?.cancel();
    _standingsSub = LeagueService
        .watchStandings(widget.sport, widget.season, _logos)
        .listen((s) {
      if (mounted) setState(() => _standings = s);
    });
  }

  /// startHour (kick-off fallback text) and logos are cosmetic seeds, not
  /// gates: when each arrives, re-subscribe the stream that maps with it —
  /// Firebase re-emits instantly from its local cache.
  void _loadDisplaySeeds() {
    LeagueService.getStartHour(widget.sport, widget.season).then((h) {
      if (!mounted || h == _startHour) return;
      _startHour = h;
      _subscribeGames();
    });
    LeagueService.leagueLogoUrls(widget.sport, widget.season).then((logos) {
      if (!mounted || logos.isEmpty) return;
      setState(() => _logos = logos);
      _subscribeStandings();
    });
  }

  @override
  void dispose() {
    _gamesSub?.cancel();
    _standingsSub?.cancel();
    _rostersSub?.cancel();
    _playoffsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Map<String, TournamentTeam> get _teamsById =>
      leagueTeamsById(_standings ?? const [], _logos);

  /// Skeleton body for a tab whose stream hasn't emitted yet (P2.1 audit:
  /// skeletons, never spinners, on league first loads).
  Widget _tabSkeleton() => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 8),
          child: SkeletonMatchList(count: 8),
        ),
      );

  void _openMatch(TournamentMatch m) {
    final ref = parseLeagueGameId(m.id);
    if (ref == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeagueMatchDetailPage(
          sport: widget.sport,
          season: widget.season,
          dateKey: ref.dateKey,
          gameIndex: ref.index,
          initialMatch: m,
        ),
      ),
    );
  }

  void _openTeam(String teamName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeagueTeamDetailPage(
          sport: widget.sport,
          season: widget.season,
          teamName: teamName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Scaffold(
      body: matches == null
          ? Column(
              children: [
                // Skeleton header keeps a visible white back arrow too
                // (P2.1 Task A3 back-arrow audit).
                Container(
                  height: 150,
                  color: const Color(0xFF1A237E),
                  alignment: Alignment.topLeft,
                  child: const SafeArea(
                    bottom: false,
                    child: BackButton(color: Colors.white),
                  ),
                ),
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
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 160,
                  pinned: true,
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  // Force the back arrow white in BOTH themes — the global
                  // appBarTheme.iconTheme is onSurface, which goes dark on
                  // this navy header in light mode (P2.1 Task A3 fix).
                  iconTheme: const IconThemeData(color: Colors.white),
                  actionsIconTheme: const IconThemeData(color: Colors.white),
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
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  LeagueFixturesTab(
                    matches: matches,
                    teams: _teamsById,
                    rosters: _rosters ?? const {},
                    sport: widget.sport,
                    onMatchTap: _openMatch,
                  ),
                  _standings == null
                      ? _tabSkeleton()
                      : LeagueTableTab(
                          standings: _standings!,
                          onOpenTeam: _openTeam,
                        ),
                  !_playoffsLoaded
                      ? _tabSkeleton()
                      : LeaguePlayoffsTab(
                          playoffs: _playoffs,
                          matches: matches,
                          teams: _teamsById,
                          season: widget.season,
                          onMatchTap: _openMatch,
                        ),
                  _rosters == null
                      ? _tabSkeleton()
                      : LeaguePlayerStatsTab(
                          rosters: _rosters!,
                          teams: _teamsById,
                          onOpenTeam: _openTeam,
                        ),
                  _standings == null
                      ? _tabSkeleton()
                      : LeagueTeamsTab(
                          sport: widget.sport,
                          season: widget.season,
                          standings: _standings!,
                          matches: matches,
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final champion = _playoffs?.champion ?? '';
    final leagueName = widget.sport == 'Futsal'
        ? 'Assyrian Futsal League'
        : widget.sport;
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
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/FutsalLeague.png',
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leagueName,
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
                      'Season ${widget.season}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                    if (champion.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.emoji_events,
                              size: 14, color: Color(0xFFFFD700)),
                          const SizedBox(width: 4),
                          Text(
                            champion,
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
            ],
          ),
        ),
      ),
    );
  }
}
