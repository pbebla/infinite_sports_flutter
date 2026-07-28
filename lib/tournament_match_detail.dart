import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_match_card_service.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart'
    show leagueMatchLeaderCategories;
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_lineup_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart'
    show isBadgeLeagueSport;
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';
import 'package:infinite_sports_flutter/widgets/live_clock.dart';
import 'package:infinite_sports_flutter/widgets/score_text.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class TournamentMatchDetailPage extends StatefulWidget {
  final TournamentMatch match;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;
  final String tournamentId;
  final String sport;

  const TournamentMatchDetailPage({
    super.key,
    required this.match,
    required this.teams,
    required this.rosters,
    required this.tournamentId,
    required this.sport,
  });

  @override
  State<TournamentMatchDetailPage> createState() =>
      _TournamentMatchDetailPageState();
}

class _TournamentMatchDetailPageState extends State<TournamentMatchDetailPage> {
  late TournamentMatch _match = widget.match;
  StreamSubscription<TournamentMatch?>? _sub;
  PredictionConfig? _predictionConfig;
  String _tournamentName = '';

  @override
  void initState() {
    super.initState();
    _sub = TournamentService
        .watchMatch(widget.tournamentId, widget.match.id)
        .listen((m) {
      if (mounted && m != null) setState(() => _match = m);
    });
    TournamentService.getPredictionConfig(widget.tournamentId).then((cfg) {
      if (mounted) setState(() => _predictionConfig = cfg);
    });
    TournamentService.getTournamentHeader(widget.tournamentId).then((t) {
      if (mounted && t != null) setState(() => _tournamentName = t.name);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _formatDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('EEEE, MMMM d, yyyy').format(dt);
  }

  /// Score-header team tap → that team's tournament page (team-tap audit,
  /// PR feedback — league match page parity).
  void _openTeam(String teamId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentTeamDetailPage(
          teamId: teamId,
          tournamentId: widget.tournamentId,
          preloadedTeams: widget.teams,
          preloadedRosters: widget.rosters,
          sport: widget.sport,
        ),
      ),
    );
  }

  Widget _buildScoreboardHeader(BuildContext context) {
    final team1 = _match.team1Id != null ? widget.teams[_match.team1Id] : null;
    final team2 = _match.team2Id != null ? widget.teams[_match.team2Id] : null;
    final isLive = _match.matchStatus.isLive;
    final isFinished = _match.matchStatus.isFinished;
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
                  value: _match.team1Score, fontSize: 28, baseColor: fg),
              Text(' - ',
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.bold,
                      fontSize: 28)),
              ScoreText(
                  value: _match.team2Score, fontSize: 28, baseColor: fg),
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
          MatchClockText(clock: _match.clock),
        ],
      );
    } else if (isFinished) {
      scoreWidget = Text(
        '${_match.team1Score} - ${_match.team2Score}',
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
          if (_match.time != null)
            Text(
              _match.time!,
              style: TextStyle(color: muted, fontSize: 13),
            ),
        ],
      );
    }

    Widget teamLogo(TournamentTeam? team, {double size = 40}) {
      return TeamLogo(url: team?.logoUrl, size: size);
    }

    // Header team columns tap through to the team's tournament page
    // (team-tap audit, PR feedback — league match page parity). Unresolved
    // sides ('TBD'/bracket placeholders) stay untappable.
    Widget teamColumn(TournamentTeam? team, String? fallbackId) {
      final column = Column(
        children: [
          teamLogo(team),
          const SizedBox(height: 6),
          Text(
            team?.name ?? fallbackId ?? 'TBD',
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
              // Stage label chip centered above teams
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: TournamentColors.headerChipFill(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _match.label,
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
                  // Team 1
                  Expanded(child: teamColumn(team1, _match.team1Id)),
                  // Score / VS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: scoreWidget,
                  ),
                  // Team 2
                  Expanded(child: teamColumn(team2, _match.team2Id)),
                ],
              ),
              // Date for non-live (scheduled/finished) matches. Location lives
              // only in the Facts tab's Location card now (never the header).
              if (!isLive) ...[
                const SizedBox(height: 10),
                Text(
                  _formatDate(_match.date),
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
    final team1 = _match.team1Id != null ? widget.teams[_match.team1Id] : null;
    final team2 = _match.team2Id != null ? widget.teams[_match.team2Id] : null;
    final team1Players = _match.team1Id != null ? (widget.rosters[_match.team1Id] ?? []) : <TournamentPlayer>[];
    final team2Players = _match.team2Id != null ? (widget.rosters[_match.team2Id] ?? []) : <TournamentPlayer>[];

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                pinned: true,
                backgroundColor: TournamentColors.headerBackground(context),
                foregroundColor: TournamentColors.headerForeground(context),
                // Theme-aware back arrow + actions (P4.1): dark on the white
                // light-mode header, white on the dark grey.
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
                      match: _match,
                      team1: team1,
                      team2: team2,
                      tournamentName: _tournamentName,
                      sport: widget.sport,
                    ),
                  ),
                  if (_match.link != null && _match.link!.isNotEmpty)
                    IconButton(
                      // colorScheme.primary = brand red in light mode, gold
                      // in dark mode (see theme_provider.dart) — matches the
                      // Watch button on match cards.
                      icon: Icon(Icons.live_tv,
                          color: Theme.of(context).colorScheme.primary),
                      tooltip: 'Watch Stream',
                      onPressed: () async {
                        final uri = Uri.tryParse(_match.link!);
                        if (uri != null) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                ],
                // 240 (not 220) leaves headroom so the live header — score,
                // LIVE badge, clock, date AND location — never clips on
                // devices with a tall status bar.
                expandedHeight: 196,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildScoreboardHeader(context),
                ),
                bottom: TabBar(
                  tabs: const [
                    Tab(text: 'Summary'),
                    Tab(text: 'Lineup')
                  ],
                  labelColor: TournamentColors.headerForeground(context),
                  unselectedLabelColor:
                      TournamentColors.headerForegroundMuted(context),
                  // Was Colors.white — invisible on the white light-mode
                  // header, so the indicator follows the foreground (still
                  // white in dark mode).
                  indicatorColor: TournamentColors.headerForeground(context),
                  indicatorWeight: 2,
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              MatchFactsTab(
                match: _match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                tournamentId: widget.tournamentId,
                predictionConfig: _predictionConfig,
                currentUid: FirebaseAuth.instance.currentUser?.uid,
                // Basketball/flag football tournaments get sport-correct
                // timeline icons, Match Leaders, and icon legend via the
                // SAME infrastructure league games already use. Soccer/
                // futsal tournaments pass neither — unchanged behavior.
                leaderCategories: isBadgeLeagueSport(widget.sport)
                    ? leagueMatchLeaderCategories(widget.sport)
                    : null,
                leagueSportKey:
                    isBadgeLeagueSport(widget.sport) ? widget.sport : null,
              ),
              MatchLineupTab(
                match: _match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                sport: widget.sport,
              )
            ],
          ),
        ),
      ),
    );
  }
}
