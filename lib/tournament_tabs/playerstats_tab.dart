import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class PlayerStatsTab extends StatefulWidget {
  final Map<String, List<TournamentPlayer>> rosters;
  final Map<String, TournamentTeam> teams;
  final String? tournamentId;

  const PlayerStatsTab({
    super.key,
    required this.rosters,
    required this.teams,
    this.tournamentId,
  });

  @override
  State<PlayerStatsTab> createState() => _PlayerStatsTabState();
}

class _PlayerStatsTabState extends State<PlayerStatsTab> {
  final Set<String> _expanded = {};

  List<TournamentPlayer> _getSortedByAll(String stat) {
    final allPlayers = TournamentService.getAllPlayers(widget.rosters);
    final filtered =
        allPlayers.where((p) => p.statByName(stat) > 0).toList();
    filtered.sort((a, b) => b.statByName(stat).compareTo(a.statByName(stat)));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      {'label': 'Top Scorer', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'Defensive Plays (DPL)', 'stat': 'dpl'},
      {'label': 'Clean Sheets', 'stat': 'cleanSheets'},
      {'label': 'Yellow Cards', 'stat': 'yellowCards'},
      {'label': 'Red Cards', 'stat': 'redCards'},
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final label = cat['label']!;
        final stat = cat['stat']!;
        final allPlayers = _getSortedByAll(stat);
        final isExpanded = _expanded.contains(stat);
        final displayed =
            isExpanded ? allPlayers : allPlayers.take(3).toList();

        if (allPlayers.isEmpty) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            setState(() {
              if (_expanded.contains(stat)) {
                _expanded.remove(stat);
              } else {
                _expanded.add(stat);
              }
            });
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.chevron_right,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...displayed.asMap().entries.map((entry) {
                    final rank = entry.key;
                    final player = entry.value;
                    final value = player.statByName(stat);
                    final team = widget.teams[player.teamId];
                    return _buildPlayerRow(
                        context, player, team, value, rank);
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerRow(
    BuildContext context,
    TournamentPlayer player,
    TournamentTeam? team,
    int value,
    int rank,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Player photo with team logo overlay
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              children: [
                // Player photo
                TeamLogo(
                  url: player.photoUrl,
                  size: 36,
                  fallbackIcon: Icons.person,
                ),
                // Team logo overlay
                if (team?.logoUrl != null && team!.logoUrl!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: TeamLogo(url: team.logoUrl, size: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Name + team
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                GestureDetector(
                  onTap: (widget.tournamentId != null && team != null)
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TournamentTeamDetailPage(
                                teamId: player.teamId,
                                tournamentId: widget.tournamentId!,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: Text(
                    player.teamName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                      decoration: (widget.tournamentId != null && team != null)
                          ? TextDecoration.underline
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Stat value
          rank == 0
              ? Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: infiniteSportsPrimaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$value',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                )
              : SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

