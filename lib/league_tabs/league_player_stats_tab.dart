import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Season leaders per stat (League Experience P2) — the league version of
/// the tournament PlayerStatsTab, driven by the live Line Ups season
/// totals. Categories are hardcoded fan-side this slice: the P1 engine
/// twin has no leaderboard-defs field yet, and adding one would break the
/// byte-for-byte twin — P4 adds it to BOTH repos.
class LeaguePlayerStatsTab extends StatefulWidget {
  final Map<String, List<TournamentPlayer>> rosters;
  final Map<String, TournamentTeam> teams;
  final void Function(String teamName)? onOpenTeam;

  const LeaguePlayerStatsTab({
    super.key,
    required this.rosters,
    required this.teams,
    this.onOpenTeam,
  });

  @override
  State<LeaguePlayerStatsTab> createState() => _LeaguePlayerStatsTabState();
}

class _LeaguePlayerStatsTabState extends State<LeaguePlayerStatsTab> {
  final Set<String> _expanded = {};

  /// label → statByName key → statIconAsset key ('' = no icon, matching
  /// the tournament tab's iconless Clean Sheets).
  static const List<Map<String, String>> _categories = [
    {'label': 'Top Scorer', 'stat': 'goals', 'icon': 'goal'},
    {'label': 'Assists', 'stat': 'assists', 'icon': 'assist'},
    {'label': 'Saves', 'stat': 'saves', 'icon': 'save'},
    {'label': 'Defensive Plays (DPL)', 'stat': 'dpl', 'icon': 'dpl'},
    {'label': 'Clean Sheets', 'stat': 'cleanSheets', 'icon': ''},
    {'label': 'Yellow Cards', 'stat': 'yellowCards', 'icon': 'yellow'},
    {'label': 'Red Cards', 'stat': 'redCards', 'icon': 'red'},
  ];

  @override
  Widget build(BuildContext context) {
    final anyStats = _categories.any(
        (c) => sortedLeagueLeaders(widget.rosters, c['stat']!).isNotEmpty);
    if (!anyStats) {
      return const Center(child: Text('No player stats yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        final label = cat['label']!;
        final stat = cat['stat']!;
        final icon = cat['icon']!;
        final leaders = sortedLeagueLeaders(widget.rosters, stat);
        if (leaders.isEmpty) return const SizedBox.shrink();
        final isExpanded = _expanded.contains(stat);
        final displayed = isExpanded ? leaders : leaders.take(3).toList();

        return GestureDetector(
          onTap: () {
            setState(() {
              if (!_expanded.remove(stat)) _expanded.add(stat);
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
                      if (icon.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child:
                              StatIcon(asset: statIconAsset(icon), size: 18),
                        ),
                      Text(
                        label,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                  ...displayed.asMap().entries.map((entry) =>
                      _buildPlayerRow(
                          context, entry.value, stat, entry.key)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerRow(
      BuildContext context, TournamentPlayer player, String stat, int rank) {
    final team = widget.teams[player.teamId];
    final value = player.statByName(stat);
    final canOpenTeam = widget.onOpenTeam != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Avatar with team-crest overlay (league lineups carry no player
          // photos — the person fallback renders).
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              children: [
                TeamLogo(
                  url: player.photoUrl,
                  size: 36,
                  fallbackIcon: Icons.person,
                ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openPlayerProfileById(context,
                      uid: player.uid, name: player.name),
                  child: Text(
                    player.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: canOpenTeam
                      ? () => widget.onOpenTeam!(player.teamId)
                      : null,
                  child: Text(
                    player.teamName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                      decoration:
                          canOpenTeam ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          rank == 0
              ? Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$value',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
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
