import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class TeamStatsTab extends StatefulWidget {
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;

  const TeamStatsTab({
    super.key,
    required this.teams,
    required this.rosters,
  });

  @override
  State<TeamStatsTab> createState() => _TeamStatsTabState();
}

class _TeamStatsTabState extends State<TeamStatsTab> {
  int _sortColumnIndex = 1; // default: GF
  bool _sortAscending = false;

  int _getCleanSheets(String teamId) {
    final players = widget.rosters[teamId] ?? [];
    return players.fold(0, (sum, p) => sum + p.cleanSheets);
  }

  List<Map<String, dynamic>> _buildRows() {
    return widget.teams.values.map((team) {
      return {
        'team': team,
        'gf': team.gs,
        'ga': team.gc,
        'gd': team.gd,
        'w': team.wins,
        'd': team.draws,
        'l': team.losses,
        'cs': _getCleanSheets(team.id),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      return const Center(child: Text('No team statistics available'));
    }

    final rows = _buildRows();

    final columns = [
      'Team',
      'GF',
      'GA',
      'GD',
      'W',
      'D',
      'L',
      'CS',
    ];

    final keys = ['team', 'gf', 'ga', 'gd', 'w', 'd', 'l', 'cs'];

    rows.sort((a, b) {
      final key = keys[_sortColumnIndex];
      if (key == 'team') {
        final nameA = (a['team'] as TournamentTeam).name;
        final nameB = (b['team'] as TournamentTeam).name;
        return _sortAscending
            ? nameA.compareTo(nameB)
            : nameB.compareTo(nameA);
      }
      final valA = a[key] as int;
      final valB = b[key] as int;
      return _sortAscending ? valA.compareTo(valB) : valB.compareTo(valA);
    });

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header row
          Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                // Team column header
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (_sortColumnIndex == 0) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortColumnIndex = 0;
                        _sortAscending = true;
                      }
                    }),
                    child: Row(
                      children: [
                        const Text('Team',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        if (_sortColumnIndex == 0)
                          Icon(
                            _sortAscending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 12,
                          ),
                      ],
                    ),
                  ),
                ),
                ...columns.skip(1).toList().asMap().entries.map((e) {
                  final colIdx = e.key + 1;
                  final col = e.value;
                  return _headerCell(context, col, colIdx);
                }),
              ],
            ),
          ),
          // Data rows
          ...rows.map((row) => _buildDataRow(context, row)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, String label, int colIdx) {
    return GestureDetector(
      onTap: () => setState(() {
        if (_sortColumnIndex == colIdx) {
          _sortAscending = !_sortAscending;
        } else {
          _sortColumnIndex = colIdx;
          _sortAscending = false;
        }
      }),
      child: SizedBox(
        width: 36,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12)),
              if (_sortColumnIndex == colIdx)
                Icon(
                  _sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 10,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(BuildContext context, Map<String, dynamic> row) {
    final team = row['team'] as TournamentTeam;
    final gd = row['gd'] as int;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                TeamLogo(url: team.logoUrl, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    team.name,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
              width: 36,
              child: Center(
                  child: Text('${row['gf']}',
                      style: const TextStyle(fontSize: 12)))),
          SizedBox(
              width: 36,
              child: Center(
                  child: Text('${row['ga']}',
                      style: const TextStyle(fontSize: 12)))),
          SizedBox(
            width: 36,
            child: Center(
              child: Text(
                gd >= 0 ? '+$gd' : '$gd',
                style: TextStyle(
                  fontSize: 12,
                  color: gd > 0
                      ? Colors.green
                      : gd < 0
                          ? Colors.red
                          : null,
                ),
              ),
            ),
          ),
          SizedBox(
              width: 30,
              child: Center(
                  child: Text('${row['w']}',
                      style: const TextStyle(fontSize: 12)))),
          SizedBox(
              width: 30,
              child: Center(
                  child: Text('${row['d']}',
                      style: const TextStyle(fontSize: 12)))),
          SizedBox(
              width: 30,
              child: Center(
                  child: Text('${row['l']}',
                      style: const TextStyle(fontSize: 12)))),
          SizedBox(
              width: 36,
              child: Center(
                  child: Text('${row['cs']}',
                      style: const TextStyle(fontSize: 12)))),
        ],
      ),
    );
  }
}

