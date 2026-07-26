import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class PlayerStatsTab extends StatefulWidget {
  final Map<String, List<TournamentPlayer>> rosters;
  final Map<String, TournamentTeam> teams;
  final String? tournamentId;
  final ComputedTournamentStats stats;
  final String sport;

  const PlayerStatsTab({
    super.key,
    required this.rosters,
    required this.teams,
    required this.stats,
    required this.sport,
    this.tournamentId,
  });

  @override
  State<PlayerStatsTab> createState() => _PlayerStatsTabState();
}

class _PlayerStatsTabState extends State<PlayerStatsTab> {
  final Set<String> _expanded = {};

  /// label / statByName key / suffix, per sport — identical lists to the
  /// league Player Stats tab (lib/league_tabs/league_player_stats_tab.dart
  /// _categoriesBySport), read only, never modified here.
  static const Map<String, List<Map<String, String>>> _categoriesBySport = {
    'Basketball': [
      {'label': 'Points', 'stat': 'points'},
      {'label': '3-Pointers', 'stat': 'threePointers'},
      {'label': '2-Pointers', 'stat': 'twoPointers'},
      {'label': 'Free Throws Made', 'stat': 'freeThrows'},
      {'label': 'Rebounds', 'stat': 'rebounds'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Steals', 'stat': 'steals'},
      {'label': 'Blocks', 'stat': 'blocks'},
      {'label': 'Turnovers', 'stat': 'turnovers'},
      {'label': 'Fouls', 'stat': 'fouls'},
    ],
    'Flag Football': [
      {'label': 'Touchdowns', 'stat': 'touchdowns'},
      {'label': 'Receptions', 'stat': 'receptions'},
      {'label': 'Catch %', 'stat': 'catchPercentage', 'suffix': '%'},
      {'label': 'Pass TDs', 'stat': 'passTouchdowns'},
      {'label': 'Interceptions', 'stat': 'interceptions'},
      {'label': 'Flag Pulls', 'stat': 'flagPulls'},
      {'label': 'Sacks', 'stat': 'sacks'},
    ],
  };

  static const List<Map<String, String>> _futsalCategories = [
    {'label': 'Top Scorer', 'stat': 'goals'},
    {'label': 'Assists', 'stat': 'assists'},
    {'label': 'Saves', 'stat': 'saves'},
    {'label': 'Defensive Plays (DPL)', 'stat': 'dpl'},
    {'label': 'Clean Sheets', 'stat': 'cleanSheets'},
    {'label': 'Yellow Cards', 'stat': 'yellowCards'},
    {'label': 'Red Cards', 'stat': 'redCards'},
  ];

  List<Map<String, String>> get _categories =>
      _categoriesBySport[widget.sport] ?? _futsalCategories;

  /// Category header icon: badge sports (basketball/flag football) resolve
  /// gold-badge art by stat key via [leagueStatIcon]; futsal/soccer keep
  /// the existing white-chip line-art via [statIconAsset], mapped from the
  /// stat key to its matching activity-type token (unchanged behavior).
  Widget? _categoryIcon(String stat) {
    if (isBadgeLeagueSport(widget.sport)) {
      final ic = leagueStatIcon(widget.sport, stat);
      if (ic.asset == null) return null;
      return StatIcon(asset: ic.asset, size: 18, badge: ic.badge);
    }
    // Clean Sheets: the owner's gold badge (2026-07-26) — self-contained
    // art, rendered badge-style (no white chip) despite being a futsal stat.
    if (stat == 'cleanSheets') {
      return const StatIcon(asset: cleanSheetBadgeAsset, size: 18, badge: true);
    }
    final eventType = _eventTypeForStat(stat);
    if (eventType == null) return null;
    return StatIcon(asset: statIconAsset(eventType), size: 18);
  }

  /// Maps a futsal/soccer stat key to the event-type string [statIconAsset]
  /// understands. Returns null when there is no suitable icon.
  String? _eventTypeForStat(String stat) {
    switch (stat) {
      case 'goals':
        return 'goal';
      case 'assists':
        return 'assist';
      case 'saves':
        return 'save';
      case 'dpl':
        return 'dpl';
      case 'yellowCards':
        return 'yellow card';
      case 'redCards':
        return 'red card';
      default:
        return null;
    }
  }

  List<TournamentPlayer> _getSortedByAll(String stat) {
    final allPlayers = TournamentService.getAllPlayers(widget.rosters);
    int valueOf(TournamentPlayer p) =>
        widget.stats.statByName(p.teamId, p.name, stat);
    final filtered = allPlayers.where((p) => valueOf(p) > 0).toList();
    filtered.sort((a, b) => valueOf(b).compareTo(valueOf(a)));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        final label = cat['label']!;
        final stat = cat['stat']!;
        final allPlayers = _getSortedByAll(stat);
        final isExpanded = _expanded.contains(stat);
        final displayed =
            isExpanded ? allPlayers : allPlayers.take(3).toList();

        if (allPlayers.isEmpty) {
          return const SizedBox.shrink();
        }

        // Theme-staleness fix (F3.1): itemBuilder's own `context` can go
        // stale after a theme toggle (same SliverChildBuilderDelegate reuse
        // quirk as fixtures_tab.dart, F3 Fix 1) — the label Text and
        // _buildPlayerRow below read Theme.of(context) directly, so wrap
        // the row content in a Builder for a live, dependency-tracked
        // context.
        return Builder(builder: (context) {
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
                      Builder(builder: (context) {
                        final icon = _categoryIcon(stat);
                        if (icon == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: icon,
                        );
                      }),
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
                    final value = widget.stats.statByName(player.teamId, player.name, stat);
                    final team = widget.teams[player.teamId];
                    return _buildPlayerRow(
                        context, player, team, value, rank,
                        suffix: cat['suffix'] ?? '');
                  }),
                ],
              ),
            ),
          ),
        );
        });
      },
    );
  }

  Widget _buildPlayerRow(
    BuildContext context,
    TournamentPlayer player,
    TournamentTeam? team,
    int value,
    int rank, {
    String suffix = '',
  }) {
    return GestureDetector(
      onTap: () => openPlayerProfileById(context, uid: player.uid, name: player.name),
      child: Padding(
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
                                preloadedTeams: widget.teams,
                                preloadedRosters: widget.rosters,
                                sport: widget.sport,
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
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$value$suffix',
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
                      '$value$suffix',
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
      ),
    );
  }
}

