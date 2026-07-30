import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/misc/prediction_scope.dart';
import 'package:infinite_sports_flutter/misc/tab_swap.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_tab.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
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

// TickerProviderStateMixin (not Single…): the P3.2 tab swap keeps the old
// and new TabController alive for one frame during the 5↔6 transition.
class _LeagueDetailPageState extends State<LeagueDetailPage>
    with TickerProviderStateMixin {
  static const List<Tab> _baseTabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Playoffs'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Teams'),
  ];

  List<Tab> _tabs = _baseTabs;
  late TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  PredictionConfig? _predictionConfig;
  bool get _predictionsOpen => _predictionConfig?.open ?? false;
  int get _predictTabIndex => _baseTabs.length; // 6th tab when open

  LeaguePredictionScope get _predictionScope =>
      LeaguePredictionScope(sport: widget.sport, season: widget.season);

  /// Rebuilds tabs + controller when the Predict tab toggles (live config).
  ///
  /// P3.2 fix: never dispose a controller the mounted TabBar still
  /// references — doing that mid-swap broke the SliverAppBar chrome (TabBar
  /// and back arrow stopped painting, RenderFlex overflow under the header).
  /// [swapTabController] creates the replacement first and disposes the old
  /// controller post-frame, and [build] keys the NestedScrollView by tab
  /// count so the tabbed subtree remounts cleanly on 5↔6. The selected index
  /// carries over, clamped so removing the Predict tab while it's selected
  /// never crashes.
  void _applyPredictionConfig(PredictionConfig config) {
    final tabs = <Tab>[
      ..._baseTabs,
      if (config.open) const Tab(text: 'Predict'),
    ];
    if (tabs.length == _tabs.length) {
      setState(() => _predictionConfig = config);
      return;
    }
    final controller = swapTabController(
      old: _tabController,
      newLength: tabs.length,
      vsync: this,
    );
    setState(() {
      _predictionConfig = config;
      _tabs = tabs;
      _tabController = controller;
    });
  }

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
  StreamSubscription<PredictionConfig>? _configSub;

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
    _configSub = LeagueService.watchPredictionConfig(widget.sport, widget.season)
        .listen((config) {
      if (mounted) _applyPredictionConfig(config);
    });
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
    _configSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Map<String, TournamentTeam> get _teamsById =>
      leagueTeamsById(_standings ?? const [], _logos);

  String get _leagueName =>
      widget.sport == 'Futsal' ? 'Futsal League' : widget.sport;

  /// Header crest per sport (P4) — matches the exact asset paths
  /// `_sportIconAsset` in `lib/leagues.dart` already uses on the leagues menu.
  String get _leagueCrestAsset {
    switch (widget.sport) {
      case 'Basketball':
        return 'assets/BasketLeague.png';
      case 'Flag Football':
        return 'assets/FlagFootballLeague.png';
      default:
        return 'assets/FutsalLeague.png';
    }
  }

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
                // Skeleton header keeps a visible back arrow too — theme-
                // aware since P4.1: dark on the white light-mode header,
                // white on the dark grey (P2.1 Task A3 back-arrow audit).
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: TournamentColors.headerBackground(context),
                    border: TournamentColors.headerHairline(context),
                  ),
                  alignment: Alignment.topLeft,
                  child: SafeArea(
                    bottom: false,
                    child: BackButton(
                        color: TournamentColors.headerForeground(context)),
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
              // P3.2: remount the tabbed subtree whenever the tab count
              // changes (Predict toggling live) so TabBar/TabBarView attach
              // to the new controller fresh — see swapTabController.
              key: ValueKey(_tabs.length),
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  expandedHeight: 160,
                  pinned: true,
                  backgroundColor: TournamentColors.headerBackground(context),
                  foregroundColor: TournamentColors.headerForeground(context),
                  // Theme-aware header foreground (P4.1): dark arrows/icons
                  // on the white light-mode header, white on the dark grey —
                  // the back arrow stays visible in both modes (P2.1 A3).
                  iconTheme: IconThemeData(
                      color: TournamentColors.headerForeground(context)),
                  actionsIconTheme: IconThemeData(
                      color: TournamentColors.headerForeground(context)),
                  // Season-wide follow bell (P3.3): tournament-page parity —
                  // one bell on the hub header subscribes every game alert
                  // (kickoff/goal/full-time) for this sport + season.
                  actions: [
                    FollowBell(
                      topic: leagueSeasonTopic(widget.sport, widget.season),
                      label: '$_leagueName Season ${widget.season}',
                      kind: 'league',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: _buildHeader(context),
                  ),
                  bottom: TabBar(
                    controller: _tabController,
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
                    onTeamTap: (team) => _openTeam(team.id),
                    predictionsOpen: _predictionsOpen,
                    onOpenPredict: _predictionsOpen
                        ? () => _tabController.animateTo(_predictTabIndex)
                        : null,
                  ),
                  _standings == null
                      ? _tabSkeleton()
                      : LeagueTableTab(
                          sport: widget.sport,
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
                          onOpenTeam: _openTeam,
                        ),
                  _rosters == null
                      ? _tabSkeleton()
                      : LeaguePlayerStatsTab(
                          sport: widget.sport,
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
                  if (_predictionsOpen)
                    PredictTab(
                      matches: matches
                          .where((m) => m.stage != 'friendly')
                          .toList(),
                      teams: _teamsById,
                      tournamentId: '',
                      scope: _predictionScope,
                      config: _predictionConfig!,
                      currentUid: FirebaseAuth.instance.currentUser?.uid,
                      rosters: _rosters ?? const {},
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final champion = _playoffs?.champion ?? '';
    final leagueName = _leagueName;
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
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: TournamentColors.headerChipFill(context),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  _leagueCrestAsset,
                  color: fg,
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
                      'Season ${widget.season}',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    if (champion.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.emoji_events,
                              size: 14,
                              color: TournamentColors.championGold(context)),
                          const SizedBox(width: 4),
                          Text(
                            champion,
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
            ],
          ),
        ),
      ),
    );
  }
}
