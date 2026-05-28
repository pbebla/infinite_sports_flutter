import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:intl/intl.dart';

class MatchH2HTab extends StatefulWidget {
  final String team1Id;
  final String team2Id;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final String currentTournamentId;
  final Future<List<Map<String, dynamic>>> preloadedFuture;
  /// Called when user taps a past match. Provides the match, teams map, and tournamentId.
  final void Function(TournamentMatch match, Map<String, TournamentTeam> teams, String tournamentId)? onMatchTap;

  const MatchH2HTab({
    super.key,
    required this.team1Id,
    required this.team2Id,
    required this.team1,
    required this.team2,
    required this.currentTournamentId,
    required this.preloadedFuture,
    this.onMatchTap,
  });

  @override
  State<MatchH2HTab> createState() => _MatchH2HTabState();
}

class _MatchH2HTabState extends State<MatchH2HTab> {
  late Future<List<Map<String, dynamic>>> _h2hFuture;

  @override
  void initState() {
    super.initState();
    _h2hFuture = widget.preloadedFuture;
  }

  String _formatDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('MMM d, yyyy').format(dt);
  }

  Widget _smallLogo(String? url) {
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 16,
          height: 16,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.shield, size: 16, color: Colors.grey),
        ),
      );
    }
    return const Icon(Icons.shield, size: 16, color: Colors.grey);
  }

  Widget _buildSummaryBar(BuildContext context, List<Map<String, dynamic>> entries) {
    int team1Wins = 0, draws = 0, team2Wins = 0;
    for (final entry in entries) {
      final m = entry['match'] as TournamentMatch;
      if (m.status != 2) continue;
      // Determine if team1 (as passed to this widget) won or lost
      final myTeamIsTeam1InMatch = m.team1Id == widget.team1Id;
      final myScore = myTeamIsTeam1InMatch ? m.team1Score : m.team2Score;
      final theirScore = myTeamIsTeam1InMatch ? m.team2Score : m.team1Score;
      if (myScore > theirScore) {
        team1Wins++;
      } else if (theirScore > myScore) {
        team2Wins++;
      } else {
        draws++;
      }
    }

    final total = team1Wins + draws + team2Wins;
    final team1Frac = total == 0 ? 0.0 : team1Wins / total;
    final drawFrac = total == 0 ? 0.0 : draws / total;
    final team2Frac = total == 0 ? 0.0 : team2Wins / total;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                _summaryBox(
                  context,
                  team1Wins,
                  widget.team1?.name ?? 'Team 1',
                  const Color(0xFF1A237E),
                ),
                const SizedBox(width: 4),
                _summaryBox(context, draws, 'Draw', Colors.grey),
                const SizedBox(width: 4),
                _summaryBox(
                  context,
                  team2Wins,
                  widget.team2?.name ?? 'Team 2',
                  Colors.deepOrange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (total > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      if (team1Frac > 0)
                        Expanded(
                          flex: (team1Frac * 100).round(),
                          child: Container(color: const Color(0xFF1A237E)),
                        ),
                      if (drawFrac > 0)
                        Expanded(
                          flex: (drawFrac * 100).round(),
                          child: Container(color: Colors.grey),
                        ),
                      if (team2Frac > 0)
                        Expanded(
                          flex: (team2Frac * 100).round(),
                          child: Container(color: Colors.deepOrange),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox(BuildContext context, int count, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(BuildContext context, Map<String, dynamic> entry) {
    final m = entry['match'] as TournamentMatch;
    final tournamentName = entry['tournamentName'] as String;
    final tournamentId = entry['tournamentId'] as String;

    if (m.matchStatus.isPending) return const SizedBox.shrink();

    final myTeamIsTeam1InMatch = m.team1Id == widget.team1Id;
    final myScore = myTeamIsTeam1InMatch ? m.team1Score : m.team2Score;
    final theirScore = myTeamIsTeam1InMatch ? m.team2Score : m.team1Score;
    final isDraw = myScore == theirScore;
    final myTeamWon = myScore > theirScore;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          if (!context.mounted) return;
          if (widget.onMatchTap != null) {
            // Show loading
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const Center(child: CircularProgressIndicator()),
            );
            final pastTeams = await TournamentService.getTeamsForTournament(tournamentId);
            if (!context.mounted) return;
            Navigator.of(context).pop(); // Close loading dialog
            widget.onMatchTap!(m, pastTeams, tournamentId);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    tournamentName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(m.date),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _smallLogo(myTeamIsTeam1InMatch
                            ? widget.team1?.logoUrl
                            : widget.team2?.logoUrl),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.team1?.name ?? m.team1Id ?? 'Team 1',
                            style: TextStyle(
                              fontWeight: (m.matchStatus.isFinished && !isDraw && myTeamIsTeam1InMatch && myTeamWon)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.matchStatus.isFinished
                          ? '${m.team1Score} - ${m.team2Score}'
                          : 'vs',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            widget.team2?.name ?? m.team2Id ?? 'Team 2',
                            style: TextStyle(
                              fontWeight: (m.matchStatus.isFinished && !isDraw && !myTeamIsTeam1InMatch && myTeamWon)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _smallLogo(myTeamIsTeam1InMatch
                            ? widget.team2?.logoUrl
                            : widget.team1?.logoUrl),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _h2hFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snapshot.data ?? [];
        final finished = entries
            .where((e) => (e['match'] as TournamentMatch).status == 2)
            .toList();

        if (finished.isEmpty) {
          return const Center(
            child: Text(
              'No previous meetings',
              style: TextStyle(fontSize: 14),
            ),
          );
        }

        return ListView(
          children: [
            _buildSummaryBar(context, finished),
            ...finished.map((e) => _buildMatchCard(context, e)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
