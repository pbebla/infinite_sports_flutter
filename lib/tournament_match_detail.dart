import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_facts_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/match_lineup_tab.dart';
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

  @override
  void initState() {
    super.initState();
    _sub = TournamentService
        .watchMatch(widget.tournamentId, widget.match.id)
        .listen((m) {
      if (mounted && m != null) setState(() => _match = m);
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

  Widget _buildScoreboardHeader(BuildContext context) {
    final team1 = _match.team1Id != null ? widget.teams[_match.team1Id] : null;
    final team2 = _match.team2Id != null ? widget.teams[_match.team2Id] : null;
    final isLive = _match.matchStatus.isLive;
    final isFinished = _match.matchStatus.isFinished;

    Widget scoreWidget;
    if (isLive) {
      scoreWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScoreText(
                  value: _match.team1Score,
                  fontSize: 28,
                  baseColor: Colors.white),
              const Text(' - ',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28)),
              ScoreText(
                  value: _match.team2Score,
                  fontSize: 28,
                  baseColor: Colors.white),
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
          if (_match.time != null)
            Text(
              _match.time!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      );
    }

    Widget teamLogo(TournamentTeam? team, {double size = 40}) {
      return TeamLogo(url: team?.logoUrl, size: size);
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
                    _match.label,
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
                          team1?.name ?? _match.team1Id ?? 'TBD',
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
                          team2?.name ?? _match.team2Id ?? 'TBD',
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
              // For live matches, date and location are rendered inside scoreWidget
              // (above the teams row) so they are never clipped by the fixed
              // SliverAppBar expandedHeight. For non-live we keep them here.
              if (!isLive) ...[
                const SizedBox(height: 10),
                Text(
                  _formatDate(_match.date),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_match.matchLocation != null && _match.matchLocation!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.white54),
                      const SizedBox(width: 3),
                      Text(
                        _match.matchLocation!,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
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
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                actions: [
                  if (_match.link != null && _match.link!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.live_tv, color: Colors.red),
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
                expandedHeight: 240,
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildScoreboardHeader(context),
                ),
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Facts'),
                    Tab(text: 'Lineup')
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
                match: _match,
                team1: team1,
                team2: team2,
                team1Players: team1Players,
                team2Players: team2Players,
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
