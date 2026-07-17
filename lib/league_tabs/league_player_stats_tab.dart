import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Season leaders per stat (League Experience P2) — the league version of
/// the tournament PlayerStatsTab, driven by the live Line Ups season
/// totals. Categories are hardcoded fan-side, per sport (see
/// misc/top_stats.dart header) — the P1 engine twin carries no
/// leaderboard-defs field and stays byte-pinned; adding one there would
/// churn the twin for data the Manager never reads.
class LeaguePlayerStatsTab extends StatefulWidget {
  final String sport;
  final Map<String, List<TournamentPlayer>> rosters;
  final Map<String, TournamentTeam> teams;
  final void Function(String teamName)? onOpenTeam;

  const LeaguePlayerStatsTab({
    super.key,
    required this.sport,
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
  /// the tournament tab's iconless Clean Sheets). Per-sport, fan-side by
  /// convention (see top_stats.dart header) — the config twin carries no
  /// leaderboard defs.
  static const Map<String, List<Map<String, String>>> _categoriesBySport = {
    'Futsal': [
      {'label': 'Top Scorer', 'stat': 'goals', 'icon': 'goal'},
      {'label': 'Assists', 'stat': 'assists', 'icon': 'assist'},
      {'label': 'Saves', 'stat': 'saves', 'icon': 'save'},
      {'label': 'Defensive Plays (DPL)', 'stat': 'dpl', 'icon': 'dpl'},
      {'label': 'Clean Sheets', 'stat': 'cleanSheets', 'icon': ''},
      {'label': 'Yellow Cards', 'stat': 'yellowCards', 'icon': 'yellow'},
      {'label': 'Red Cards', 'stat': 'redCards', 'icon': 'red'},
    ],
    'Basketball': [
      {'label': 'Points', 'stat': 'points', 'icon': ''},
      {'label': 'Rebounds', 'stat': 'rebounds', 'icon': 'rebound'},
      {'label': 'Assists', 'stat': 'assists', 'icon': 'assist'},
      {'label': '3-Pointers', 'stat': 'threePointers', 'icon': 'threepointer'},
      {'label': 'Steals', 'stat': 'steals', 'icon': ''},
      {'label': 'Blocks', 'stat': 'blocks', 'icon': ''},
    ],
    'Flag Football': [
      {'label': 'Touchdowns', 'stat': 'touchdowns', 'icon': ''},
      {'label': 'Receptions', 'stat': 'receptions', 'icon': ''},
      {'label': 'Pass TDs', 'stat': 'passTouchdowns', 'icon': ''},
      {'label': 'Interceptions', 'stat': 'interceptions', 'icon': ''},
      {'label': 'Flag Pulls', 'stat': 'flagPulls', 'icon': ''},
      {'label': 'Sacks', 'stat': 'sacks', 'icon': ''},
    ],
  };

  List<Map<String, String>> get _categories =>
      _categoriesBySport[widget.sport] ?? _categoriesBySport['Futsal']!;

  @override
  Widget build(BuildContext context) {
    final anyStats = _categories.any(
        (c) => sortedLeagueLeaders(widget.rosters, c['stat']!).isNotEmpty);
    if (!anyStats) {
      return const Center(child: Text('No player stats yet'));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
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
                      _categoryIcon(stat, icon),
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

  /// Category header icon. Badge sports (basketball / later FF) resolve gold
  /// badge art by the stat key via [leagueStatIcon] (covers Points/Steals/
  /// Blocks that had no icon before); other sports keep the line-art chip
  /// keyed by the category's icon field ('' = no icon, e.g. Clean Sheets).
  Widget _categoryIcon(String stat, String iconKey) {
    if (isBadgeLeagueSport(widget.sport)) {
      final ic = leagueStatIcon(widget.sport, stat);
      if (ic.asset == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: StatIcon(asset: ic.asset, size: 18, badge: ic.badge),
      );
    }
    if (iconKey.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: StatIcon(asset: statIconAsset(iconKey), size: 18),
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
