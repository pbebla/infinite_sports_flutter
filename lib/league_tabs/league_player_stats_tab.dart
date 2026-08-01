import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_stat_categories.dart';
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

  // Lag fix: leaders were re-sorted per category on every rebuild (parent
  // live streams + tab swipes). Cached until the rosters instance changes.
  Map<String, List<TournamentPlayer>>? _leadersCache;
  List<TournamentPlayer> _leaders(String stat) =>
      (_leadersCache ??= {})[stat] ??=
          sortedLeagueLeaders(widget.rosters, stat);

  @override
  void didUpdateWidget(LeaguePlayerStatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rosters, widget.rosters) ||
        oldWidget.sport != widget.sport) {
      _leadersCache = null;
    }
  }

  List<Map<String, String>> get _categories =>
      leagueStatCategories(widget.sport);

  @override
  Widget build(BuildContext context) {
    final anyStats =
        _categories.any((c) => _leaders(c['stat']!).isNotEmpty);
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
        final suffix = cat['suffix'] ?? '';
        final leaders = _leaders(stat);
        if (leaders.isEmpty) return const SizedBox.shrink();
        final isExpanded = _expanded.contains(stat);
        final displayed = isExpanded ? leaders : leaders.take(3).toList();

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
                          context, entry.value, stat, suffix, entry.key)),
                ],
              ),
            ),
          ),
        );
        });
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
    // Clean Sheets: the owner's gold badge (2026-07-26) — self-contained
    // art, rendered badge-style (no white chip) despite being a futsal stat.
    if (stat == 'cleanSheets') {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: StatIcon(asset: cleanSheetBadgeAsset, size: 18, badge: true),
      );
    }
    if (iconKey.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: StatIcon(asset: statIconAsset(iconKey), size: 18),
    );
  }

  Widget _buildPlayerRow(BuildContext context, TournamentPlayer player,
      String stat, String suffix, int rank) {
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
                    // Owner rule: tappable team names stay undecorated —
                    // never underline (too busy).
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
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
                    // Scale down so suffixed values ('100%') still fit the
                    // fixed 32px leader circle.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$value$suffix',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  width: 32,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
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
                ),
        ],
      ),
    );
  }
}
