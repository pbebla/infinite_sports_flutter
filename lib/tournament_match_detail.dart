import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_h2h_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_lineup_tab.dart';
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
  late Future<List<Map<String, dynamic>>> _h2hFuture;

  @override
  void initState() {
    super.initState();
    if (widget.match.team1Id != null && widget.match.team2Id != null) {
      _h2hFuture = TournamentService.getH2HMatches(
          widget.match.team1Id!, widget.match.team2Id!);
    } else {
      _h2hFuture = Future.value([]);
    }
  }

  String _formatDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('EEEE, MMMM d, yyyy').format(dt);
  }

  Widget _buildScoreboardHeader(BuildContext context) {
    final team1 = widget.match.team1Id != null ? widget.teams[widget.match.team1Id] : null;
    final team2 = widget.match.team2Id != null ? widget.teams[widget.match.team2Id] : null;
    final isLive = widget.match.matchStatus.isLive;
    final isFinished = widget.match.matchStatus.isFinished;

    Widget scoreWidget;
    if (isLive) {
      scoreWidget = Column(
        children: [
          Text(
            '${widget.match.team1Score} - ${widget.match.team2Score}',
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 28,
            ),
          ),
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
        ],
      );
    } else if (isFinished) {
      scoreWidget = Text(
        '${widget.match.team1Score} - ${widget.match.team2Score}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      );
    } else {
      scoreWidget = Column(
        children: [
          const Text(
            'VS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          if (widget.match.time != null)
            Text(
              widget.match.time!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      );
    }

    Widget teamLogo(TournamentTeam? team, {double size = 40}) {
      if (team?.logoUrl != null && team!.logoUrl!.isNotEmpty) {
        return ClipOval(
          child: Image.network(
            team.logoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) =>
                Icon(Icons.shield, size: size, color: Colors.white60),
          ),
        );
      }
      return Icon(Icons.shield, size: size, color: Colors.white60);
    }

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              // Stage label chip centered above teams
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.match.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Team 1
                  Expanded(
                    child: Column(
                      children: [
                        teamLogo(team1),
                        const SizedBox(height: 6),
                        Text(
                          team1?.name ?? widget.match.team1Id ?? 'TBD',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  // Score / VS
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: scoreWidget,
                  ),
                  // Team 2
                  Expanded(
                    child: Column(
                      children: [
                        teamLogo(team2),
                        const SizedBox(height: 6),
                        Text(
                          team2?.name ?? widget.match.team2Id ?? 'TBD',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatDate(widget.match.date),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (widget.match.matchLocation != null && widget.match.matchLocation!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, size: 12, color: Colors.white54),
                    const SizedBox(width: 3),
                    Text(
                      widget.match.matchLocation!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
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
    final team1 = widget.match.team1Id != null ? widget.teams[widget.match.team1Id] : null;
    final team2 = widget.match.team2Id != null ? widget.teams[widget.match.team2Id] : null;
    final team1Players = widget.match.team1Id != null ? (widget.rosters[widget.match.team1Id] ?? []) : <TournamentPlayer>[];
    final team2Players = widget.match.team2Id != null ? (widget.rosters[widget.match.team2Id] ?? []) : <TournamentPlayer>[];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                actions: [
                  if (widget.match.link != null && widget.match.link!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.live_tv, color: Colors.red),
                      tooltip: 'Watch Stream',
                      onPressed: () async {
                        final uri = Uri.tryParse(widget.match.link!);
                        if (uri != null) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                ],
                expandedHeight: 220,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildScoreboardHeader(context),
                ),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Facts'),
                    Tab(text: 'Lineup'),
                    Tab(text: 'H2H'),
                  ],
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2,
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              MatchFactsTab(
                match: widget.match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
              ),
              MatchLineupTab(
                match: widget.match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
                sport: widget.sport,
              ),
              MatchH2HTab(
                team1Id: widget.match.team1Id ?? '',
                team2Id: widget.match.team2Id ?? '',
                team1: team1,
                team2: team2,
                currentTournamentId: widget.tournamentId,
                preloadedFuture: _h2hFuture,
                onMatchTap: (pastMatch, pastTeams, pastTournamentId) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TournamentMatchDetailPage(
                        match: pastMatch,
                        teams: pastTeams,
                        rosters: const {},
                        tournamentId: pastTournamentId,
                        sport: widget.sport,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
