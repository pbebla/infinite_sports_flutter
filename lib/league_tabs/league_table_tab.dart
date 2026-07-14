import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Live futsal standings (League Experience P2). Renders the SORTED rows
/// streamed from the Manager-maintained Teams node — exact legacy
/// table.dart futsal columns (GP W D L GF GA GD P). Staged (playoff /
/// friendly) games are already excluded at the source: L3's finalize flow
/// skips standings for games with a Stage. Rows are tappable when
/// [onOpenTeam] is set (P2.1: opens the league team page).
class LeagueTableTab extends StatelessWidget {
  final List<TournamentTeam> standings;
  final void Function(String teamName)? onOpenTeam;

  const LeagueTableTab({super.key, required this.standings, this.onOpenTeam});

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const Center(child: Text('Table not yet available'));
    }
    return SingleChildScrollView(
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: DataTable(
          columnSpacing: 0,
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) =>
                  Theme.of(context).colorScheme.surfaceContainerHighest),
          columns: const [
            DataColumn(label: Text('')),
            DataColumn(label: Text('Team')),
            DataColumn(label: Text('GP'), numeric: true),
            DataColumn(label: Text('W'), numeric: true),
            DataColumn(label: Text('D'), numeric: true),
            DataColumn(label: Text('L'), numeric: true),
            DataColumn(label: Text('GF'), numeric: true),
            DataColumn(label: Text('GA'), numeric: true),
            DataColumn(label: Text('GD'), numeric: true),
            DataColumn(label: Text('P'), numeric: true),
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
                    DataCell(Text('${team.gp}')),
                    DataCell(Text('${team.wins}')),
                    DataCell(Text('${team.draws}')),
                    DataCell(Text('${team.losses}')),
                    DataCell(Text('${team.gs}')),
                    DataCell(Text('${team.gc}')),
                    DataCell(Text('${team.gd}')),
                    DataCell(Text(
                      '${team.points}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )),
                  ]),
          ],
        ),
      ),
    );
  }
}
