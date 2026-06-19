import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class TableTab extends StatelessWidget {
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final String? tournamentId;
  final ComputedTournamentStats stats;

  const TableTab({
    super.key,
    required this.teams,
    required this.matches,
    required this.stats,
    this.tournamentId,
  });

  Color _qualificationColor(String qualification) {
    switch (qualification.toLowerCase()) {
      case 'qualified':
        return Colors.green;
      case 'eliminated':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<TournamentTeam> _sortGroup(List<TournamentTeam> group) {
    return group
      ..sort((a, b) {
        final sa = stats.standingFor(a.id);
        final sb = stats.standingFor(b.id);
        if (sb.pts != sa.pts) return sb.pts.compareTo(sa.pts);
        if (sb.gd != sa.gd) return sb.gd.compareTo(sa.gd);
        return sb.gs.compareTo(sa.gs);
      });
  }

  Set<String> get _liveTeamIds => matches
      .where((m) => m.status == 1)
      .expand((m) => [m.team1Id, m.team2Id])
      .whereType<String>()
      .toSet();

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return const Center(child: Text('No table data available'));
    }

    // Detect if the tournament uses multiple named groups
    final groupNames = teams.values
        .map((t) => t.group)
        .where((g) => g != null && g.isNotEmpty)
        .toSet()
        .cast<String>()
        .toList()
      ..sort();

    final bool hasMultipleGroups = groupNames.length > 1;

    if (hasMultipleGroups) {
      // Build a map from group name → sorted teams
      final Map<String, List<TournamentTeam>> grouped = {};
      for (final gName in groupNames) {
        grouped[gName] = _sortGroup(
          teams.values.where((t) => t.group == gName).toList(),
        );
      }
      // Catch any teams without a group (put them in "Other")
      final ungrouped = teams.values.where((t) => t.group == null || t.group!.isEmpty).toList();
      if (ungrouped.isNotEmpty) {
        grouped['Other'] = _sortGroup(ungrouped);
        if (!groupNames.contains('Other')) groupNames.add('Other');
      }

      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final gName in groupNames) ...[
                  _groupHeader(context, gName),
                  _tableHeader(context),
                  ...(_sortGroup(grouped[gName]!)).asMap().entries.map(
                    (e) => _teamRow(context, e.value, rank: e.key),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          _legend(context),
        ],
      );
    } else {
      // Single group (or no group labels) — original flat table
      final sorted = _sortGroup(teams.values.toList());

      return Column(
        children: [
          _tableHeader(context),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsetsGeometry.all(0),
              itemCount: sorted.length,
              itemBuilder: (context, index) => _teamRow(context, sorted[index], rank: index),
            ),
          ),
          _legend(context),
        ],
      );
    }
  }

  Widget _groupHeader(BuildContext context, String groupName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        groupName,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }

  Widget _tableHeader(BuildContext context) {
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
    );

    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Center(child: Text('Team', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('GP', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('W', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('D', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('L', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('GS', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('GC', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('GD', style: headerStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('Pts', style: headerStyle)),
          ),
        ],
      ),
    );
  }

  Widget _teamRow(BuildContext context, TournamentTeam team, {int rank = 0}) {
    const cellStyle = TextStyle(fontSize: 12);
    final qualColor = _qualificationColor(team.qualification);
    final s = stats.standingFor(team.id);
    final isLive = _liveTeamIds.contains(team.id);

    return InkWell(
      onTap: tournamentId != null
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TournamentTeamDetailPage(
                    teamId: team.id,
                    tournamentId: tournamentId!,
                    preloadedTeams: teams,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: isLive ? const Color(0x1A0A7D2C) : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
        children: [
          // Qualification color bar
          Expanded(
            flex: 7,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 44,
                  color: qualColor,
                ),
                SizedBox(
                  width: 18,
                  child: Center(
                    child: Text(
                      '${rank + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                // Team logo
                TeamLogo(url: team.logoUrl, size: 24),
                const SizedBox(width: 6),
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      if (isLive) ...[
                        const _LiveDot(),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          team.name,
                          style: const TextStyle(fontSize: 13),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
                    ]
                  ),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.gp}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.w}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.d}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.l}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.gs}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(child: Text('${s.gc}', style: cellStyle)),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                s.gd >= 0 ? '+${s.gd}' : '${s.gd}',
                style: cellStyle.copyWith(
                  color: s.gd > 0
                      ? Colors.green
                      : s.gd < 0
                          ? Colors.red
                          : null,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                '${s.pts}',
                style: cellStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _legendItem(Colors.green, 'Qualified'),
          _legendItem(Colors.red, 'Eliminated'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFF0A7D2C), shape: BoxShape.circle),
      ),
    );
  }
}
