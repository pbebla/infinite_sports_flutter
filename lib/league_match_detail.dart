import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/match_tabs/box_score_columns.dart';
import 'package:infinite_sports_flutter/match_tabs/team_box_score_tab.dart';
import 'package:infinite_sports_flutter/misc/goal_toast.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/prediction_scope.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/widgets/live_clock.dart';
import 'package:infinite_sports_flutter/widgets/score_text.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Live league match page (League Experience P2) — supersedes the legacy
/// ScorePage for FUTSAL league games; basketball/flag football keep
/// ScorePage until P4. Tournament parity via reuse: live score header +
/// running clock (MatchClockText), icon timeline + Match Leaders + location
/// card (the reused MatchFactsTab), share card (shareMatchCard),
/// stage/Friendly chip, and a stream-driven in-page goal toast.
class LeagueMatchDetailPage extends StatefulWidget {
  final String sport;
  final String season;
  final String dateKey;
  final int gameIndex;

  /// Optional: paints instantly while the stream connects (callers that
  /// already hold the adapted match pass it through).
  final TournamentMatch? initialMatch;

  const LeagueMatchDetailPage({
    super.key,
    this.sport = 'Futsal',
    required this.season,
    required this.dateKey,
    required this.gameIndex,
    this.initialMatch,
  });

  @override
  State<LeagueMatchDetailPage> createState() => _LeagueMatchDetailPageState();
}

class _LeagueMatchDetailPageState extends State<LeagueMatchDetailPage> {
  TournamentMatch? _match;
  Map<String, List<TournamentPlayer>> _rosters = {};
  Map<String, String> _logos = {};
  int _startHour = 0;
  StreamSubscription<TournamentMatch?>? _matchSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rosterSub;
  PredictionConfig? _predictionConfig;
  StreamSubscription<PredictionConfig>? _configSub;

  // Box-score tallies memoized off the live match (tournamentdetail.dart
  // lag-fix rule): recomputed only when a stream event lands, never in build.
  Map<String, MatchPlayerTally> _matchTallies = const {};

  @override
  void initState() {
    super.initState();
    _match = widget.initialMatch;
    if (_match != null) _matchTallies = singleMatchPlayerTallies(_match!);
    // First paint speed (P2.1): subscribe immediately with default seeds;
    // startHour (kick-off fallback text) re-applies via re-subscribe and
    // logos apply at build time when they arrive.
    _subscribeMatch();
    _rosterSub =
        LeagueService.watchRosters(widget.sport, widget.season).listen((r) {
      if (mounted) setState(() => _rosters = r);
    });
    _configSub = LeagueService.watchPredictionConfig(widget.sport, widget.season)
        .listen((config) {
      if (mounted) setState(() => _predictionConfig = config);
    });
    LeagueService.getStartHour(widget.sport, widget.season).then((h) {
      if (!mounted || h == _startHour) return;
      _startHour = h;
      _subscribeMatch();
    });
    LeagueService.leagueLogoUrls(widget.sport, widget.season).then((logos) {
      if (!mounted || logos.isEmpty) return;
      setState(() => _logos = logos);
    });
  }

  void _subscribeMatch() {
    _matchSub?.cancel();
    _matchSub = LeagueService.watchGame(
      widget.sport,
      widget.season,
      widget.dateKey,
      widget.gameIndex,
      startHour: _startHour,
    ).listen(_onMatch);
  }

  /// Live score-increase detection while the page is open → in-app goal
  /// toast (tournament parity; the FCM-driven toast for followed league
  /// teams arrives with the P3 watcher).
  void _onMatch(TournamentMatch? m) {
    if (!mounted || m == null) return;
    final prev = _match;
    if (prev != null) {
      if (m.team1Score > prev.team1Score) {
        _showGoalToast(m, m.team1Id ?? '');
      } else if (m.team2Score > prev.team2Score) {
        _showGoalToast(m, m.team2Id ?? '');
      }
    }
    setState(() {
      _match = m;
      _matchTallies = singleMatchPlayerTallies(m);
    });
  }

  void _showGoalToast(TournamentMatch m, String teamName) {
    GoalToast.show(
      context: context,
      title: 'GOAL! $teamName',
      body: '${m.team1Id} ${m.team1Score}–${m.team2Score} ${m.team2Id}',
      onTap: () {}, // already on the match page
    );
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    _rosterSub?.cancel();
    _configSub?.cancel();
    super.dispose();
  }

  /// Real teams get a name+crest stub; bracket placeholders ('Winner of
  /// SF1') stay null so the header renders their text without a bogus crest
  /// lookup.
  TournamentTeam? _team(String? name) {
    if (name == null || name.isEmpty || isPlaceholderTeam(name)) return null;
    return leagueTeamStub(name, _logos[name]);
  }

  /// Score-header team tap → that team's league page (P2.1 Task A3
  /// tap-through audit).
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

  String _formatDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('EEEE, MMMM d, yyyy').format(dt);
  }

  Widget _buildScoreboardHeader(BuildContext context, TournamentMatch match,
      TournamentTeam? team1, TournamentTeam? team2) {
    final isLive = match.matchStatus.isLive;
    final isFinished = match.matchStatus.isFinished;
    // Theme-aware header foreground (P4.1): dark text on the white
    // light-mode header, white on the dark-mode grey.
    final fg = TournamentColors.headerForeground(context);
    final muted = TournamentColors.headerForegroundMuted(context);

    Widget scoreWidget;
    if (isLive) {
      scoreWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScoreText(
                  value: match.team1Score, fontSize: 28, baseColor: fg),
              Text(' - ',
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.bold,
                      fontSize: 28)),
              ScoreText(
                  value: match.team2Score, fontSize: 28, baseColor: fg),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Running match clock from the game node's Clock (P1). Older
          // games without a Clock shrink this to nothing.
          MatchClockText(clock: match.clock),
        ],
      );
    } else if (isFinished) {
      scoreWidget = Text(
        '${match.team1Score} - ${match.team2Score}',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      );
    } else {
      scoreWidget = Column(
        children: [
          Text(
            'VS',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          if (match.time != null)
            Text(
              match.time!,
              style: TextStyle(color: muted, fontSize: 13),
            ),
        ],
      );
    }

    Widget teamColumn(TournamentTeam? team, String? fallbackName) {
      final placeholder =
          fallbackName != null && isPlaceholderTeam(fallbackName);
      final column = Column(
        children: [
          placeholder
              ? Icon(Icons.emoji_events, size: 40, color: muted)
              : TeamLogo(url: team?.logoUrl, size: 40),
          const SizedBox(height: 6),
          Text(
            team?.name ?? fallbackName ?? 'TBD',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      );
      // Real teams (not 'Winner of SF1' placeholders) tap through to the
      // league team page.
      if (team == null) return column;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openTeam(team.id),
        child: column,
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: TournamentColors.headerGradient(context),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stage chip: 'League', 'Friendly', 'Semifinal',
              // 'Championship', ... (adapter label).
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: TournamentColors.headerChipFill(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    match.label,
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: teamColumn(team1, match.team1Id)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: scoreWidget,
                  ),
                  Expanded(child: teamColumn(team2, match.team2Id)),
                ],
              ),
              if (!isLive) ...[
                const SizedBox(height: 10),
                Text(
                  _formatDate(match.date),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = _match;
    if (match == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: TournamentColors.headerBackground(context),
          foregroundColor: TournamentColors.headerForeground(context),
          // Theme-aware back arrow (P4.1): dark on the white light-mode
          // header, white on the dark grey — always visible (P2.1 A3).
          iconTheme: IconThemeData(
              color: TournamentColors.headerForeground(context)),
          actionsIconTheme: IconThemeData(
              color: TournamentColors.headerForeground(context)),
        ),
        body: const SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(top: 8),
            child: SkeletonMatchList(count: 8),
          ),
        ),
      );
    }

    final team1 = _team(match.team1Id);
    final team2 = _team(match.team2Id);
    final team1Players = match.team1Id != null
        ? (_rosters[match.team1Id] ?? <TournamentPlayer>[])
        : <TournamentPlayer>[];
    final team2Players = match.team2Id != null
        ? (_rosters[match.team2Id] ?? <TournamentPlayer>[])
        : <TournamentPlayer>[];
    // Per-team box score tabs (Match Box Score spec): the Lineup tab is
    // hidden — match_lineup_tab.dart survives for the future on-field view.
    final boxScoreColumns = boxScoreColumnsFor(widget.sport);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                pinned: true,
                backgroundColor: TournamentColors.headerBackground(context),
                foregroundColor: TournamentColors.headerForeground(context),
                // Theme-aware back arrow + actions in BOTH themes (see above).
                iconTheme: IconThemeData(
                    color: TournamentColors.headerForeground(context)),
                actionsIconTheme: IconThemeData(
                    color: TournamentColors.headerForeground(context)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share match',
                    onPressed: () => shareMatchCard(
                      context,
                      match: match,
                      team1: team1,
                      team2: team2,
                      tournamentName:
                          '${widget.sport} Season ${widget.season}',
                      sport: widget.sport,
                    ),
                  ),
                  if (match.link != null && match.link!.isNotEmpty)
                    IconButton(
                      // colorScheme.primary = brand red in light mode, gold
                      // in dark mode (see theme_provider.dart) — matches the
                      // Watch button on match cards.
                      icon: Icon(Icons.live_tv,
                          color: Theme.of(context).colorScheme.primary),
                      tooltip: 'Watch Stream',
                      onPressed: () async {
                        final uri = Uri.tryParse(match.link!);
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                ],
                expandedHeight: 196,
                flexibleSpace: FlexibleSpaceBar(
                  background:
                      _buildScoreboardHeader(context, match, team1, team2),
                ),
                // Summary + per-team box score tabs (parity with the
                // tournament match page).
                bottom: TabBar(
                  // Owner feedback: the three tabs spread evenly across the
                  // full width (scrollable clustered them in the center);
                  // long team names scale down to fit their third.
                  tabs: [
                    const Tab(text: 'Summary'),
                    teamNameTab(team1?.name ?? match.team1Id ?? 'Team 1'),
                    teamNameTab(team2?.name ?? match.team2Id ?? 'Team 2'),
                  ],
                  labelColor: TournamentColors.headerForeground(context),
                  unselectedLabelColor:
                      TournamentColors.headerForegroundMuted(context),
                  indicatorColor: TournamentColors.headerForeground(context),
                  indicatorWeight: 2,
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              // The reused Facts body: icon timeline (all league event types
              // via the Task 2 aliases, minute labels, Guest entries as plain
              // names), Match Leaders (Task 2 tallies), and the §6 location
              // card (renders only when the game node has a Location).
              MatchFactsTab(
                match: match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                // Predict teaser (P3): only on predictable games — config
                // open, both teams real (placeholders resolve to null), not a
                // friendly.
                scope: (match.stage != 'friendly' &&
                        team1 != null &&
                        team2 != null)
                    ? LeaguePredictionScope(
                        sport: widget.sport, season: widget.season)
                    : null,
                predictionConfig: _predictionConfig,
                currentUid: FirebaseAuth.instance.currentUser?.uid,
                leaderCategories: leagueMatchLeaderCategories(widget.sport),
                leagueSportKey: widget.sport,
              ),
              // Per-team box scores: the same rosters already streamed for
              // the Facts tab's Match Leaders / timeline name resolution,
              // tallied from the same live match activity.
              TeamBoxScoreTab(
                roster: team1Players,
                tallies: _matchTallies,
                columns: boxScoreColumns,
              ),
              TeamBoxScoreTab(
                roster: team2Players,
                tallies: _matchTallies,
                columns: boxScoreColumns,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
