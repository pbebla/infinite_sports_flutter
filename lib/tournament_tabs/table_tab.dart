import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';

class TableTab extends StatelessWidget {
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final String? tournamentId;

  const TableTab({
    super.key,
    required this.teams,
    required this.matches,
    this.tournamentId,
  });

  Color _qualificationColor(String qualification) {
    switch (qualification.toLowerCase()) {
      case 'qualified':
        return Colors.green;
      case 'can qualify':
        return Colors.amber;
      case 'eliminated':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _teamLogo(String? url) {
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.shield, size: 24, color: Colors.grey),
        ),
      );
    }
    return const Icon(Icons.shield, size: 24, color: Colors.grey);
  }

  List<TournamentTeam> _sortGroup(List<TournamentTeam> group) {
    return group
      ..sort((a, b) {
        if (b.points != a.points) return b.points.compareTo(a.points);
        if (b.gd != a.gd) return b.gd.compareTo(a.gd);
        return b.gs.compareTo(a.gs);
      });
  }

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
                  ...(_sortGroup(grouped[gName]!)).map(
                    (team) => _teamRow(context, team),
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
              itemCount: sorted.length,
              itemBuilder: (context, index) => _teamRow(context, sorted[index]),
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
              color: Theme.of(context).colorScheme.primary,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 4 + 18 + 4 + 24 + 6), // qual bar + seed + logo
          Expanded(
            flex: 5,
            child: Text('Team', style: headerStyle),
          ),
          SizedBox(width: 30, child: Center(child: Text('GP', style: headerStyle))),
          SizedBox(width: 30, child: Center(child: Text('W', style: headerStyle))),
          SizedBox(width: 30, child: Center(child: Text('D', style: headerStyle))),
          SizedBox(width: 30, child: Center(child: Text('L', style: headerStyle))),
          SizedBox(width: 30, child: Center(child: Text('GS', style: headerStyle))),
          SizedBox(width: 30, child: Center(child: Text('GC', style: headerStyle))),
          SizedBox(width: 36, child: Center(child: Text('GD', style: headerStyle))),
          SizedBox(width: 36, child: Center(child: Text('Pts', style: headerStyle))),
        ],
      ),
    );
  }

  Widget _teamRow(BuildContext context, TournamentTeam team) {
    const cellStyle = TextStyle(fontSize: 12);
    final qualColor = _qualificationColor(team.qualification);

    return InkWell(
      onTap: tournamentId != null
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TournamentTeamDetailPage(
                    teamId: team.id,
                    tournamentId: tournamentId!,
                  ),
                ),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
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
          Container(
            width: 4,
            height: 44,
            color: qualColor,
          ),
          const SizedBox(width: 6),
          // Seed badge
          SizedBox(
            width: 18,
            child: team.seed != null
                ? Center(
                    child: Text(
                      '${team.seed}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 4),
          // Team logo
          _teamLogo(team.logoUrl),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: Text(
              team.name,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 30, child: Center(child: Text('${team.gp}', style: cellStyle))),
          SizedBox(width: 30, child: Center(child: Text('${team.wins}', style: cellStyle))),
          SizedBox(width: 30, child: Center(child: Text('${team.draws}', style: cellStyle))),
          SizedBox(width: 30, child: Center(child: Text('${team.losses}', style: cellStyle))),
          SizedBox(width: 30, child: Center(child: Text('${team.gs}', style: cellStyle))),
          SizedBox(width: 30, child: Center(child: Text('${team.gc}', style: cellStyle))),
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                team.gd >= 0 ? '+${team.gd}' : '${team.gd}',
                style: cellStyle.copyWith(
                  color: team.gd > 0
                      ? Colors.green
                      : team.gd < 0
                          ? Colors.red
                          : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                '${team.points}',
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
          _legendItem(Colors.amber, 'Can Qualify'),
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
