import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Live league standings (League Experience P2; per-sport columns P4).
/// Renders the SORTED rows streamed from the Manager-maintained Teams
/// node. Columns switch on sport:
///   Futsal:        GP W D L GF GA GD P      (exact legacy table.dart)
///   Basketball:    GP W L PPG PCPG PD Pts   (owner-directed)
///   Flag Football: W L PF PA PD             (owner-directed)
/// Sorting happened in the adapter (seedOrder parity). Staged (playoff /
/// friendly) games are already excluded at the source: L3's finalize flow
/// skips standings for games with a Stage. Rows are tappable when
/// [onOpenTeam] is set (P2.1: opens the league team page).
class LeagueTableTab extends StatelessWidget {
  final String sport;
  final List<TournamentTeam> standings;
  final void Function(String teamName)? onOpenTeam;

  const LeagueTableTab({
    super.key,
    required this.sport,
    required this.standings,
    this.onOpenTeam,
  });

  /// One column spec: header label + the cell text for a row.
  List<({String header, String Function(TournamentTeam t) cell})>
      get _columns {
    String n(TournamentTeam t, String key) {
      final v = t.leagueStats[key] ?? 0;
      // Whole numbers print bare; averages keep their 1 decimal.
      return v is int || v == v.roundToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(1);
    }

    switch (sport) {
      case 'Basketball':
        return [
          (header: 'GP', cell: (t) => '${t.gp}'),
          (header: 'W', cell: (t) => '${t.wins}'),
          (header: 'L', cell: (t) => '${t.losses}'),
          (header: 'PPG', cell: (t) => n(t, 'PPG')),
          (header: 'PCPG', cell: (t) => n(t, 'PCPG')),
          (header: 'PD', cell: (t) => n(t, 'PD')),
          (header: 'Pts', cell: (t) => '${t.points}'),
        ];
      case 'Flag Football':
        return [
          (header: 'W', cell: (t) => '${t.wins}'),
          (header: 'L', cell: (t) => '${t.losses}'),
          (header: 'PF', cell: (t) => n(t, 'PF')),
          (header: 'PA', cell: (t) => n(t, 'PA')),
          (header: 'PD', cell: (t) => n(t, 'PD')),
        ];
      default: // Futsal
        return [
          (header: 'GP', cell: (t) => '${t.gp}'),
          (header: 'W', cell: (t) => '${t.wins}'),
          (header: 'D', cell: (t) => '${t.draws}'),
          (header: 'L', cell: (t) => '${t.losses}'),
          (header: 'GF', cell: (t) => '${t.gs}'),
          (header: 'GA', cell: (t) => '${t.gc}'),
          (header: 'GD', cell: (t) => '${t.gd}'),
          (header: 'P', cell: (t) => '${t.points}'),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const Center(child: Text('Table not yet available'));
    }
    final columns = _columns;
    return SingleChildScrollView(
      // Bottom inset keeps the last table row reachable above the floating
      // glass nav bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: DataTable(
          columnSpacing: 0,
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) =>
                  Theme.of(context).colorScheme.surfaceContainerHighest),
          columns: [
            const DataColumn(label: Text('')),
            const DataColumn(label: Text('Team')),
            for (final c in columns)
              DataColumn(label: Text(c.header), numeric: true),
          ],
          rows: [
            for (final team in standings)
              DataRow(
                  onSelectChanged: onOpenTeam == null
                      ? null
                      : (_) => onOpenTeam!(team.id),
                  cells: [
                    DataCell(TeamLogo(url: team.logoUrl, size: 26)),
                    DataCell(Text(team.name)),
                    for (var i = 0; i < columns.length; i++)
                      DataCell(Text(
                        columns[i].cell(team),
                        style: i == columns.length - 1
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      )),
                  ]),
          ],
        ),
      ),
    );
  }
}
