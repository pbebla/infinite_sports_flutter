import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_form.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/form_chips.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// Teams tab (League Experience P2): standings-ordered team cards (live
/// record + form) → LeagueTeamDetailPage.
class LeagueTeamsTab extends StatelessWidget {
  final String sport;
  final String season;
  final List<TournamentTeam> standings;
  final List<TournamentMatch> matches;

  const LeagueTeamsTab({
    super.key,
    required this.sport,
    required this.season,
    required this.standings,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const Center(child: Text('No teams available'));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + MediaQuery.paddingOf(context).bottom),
      itemCount: standings.length,
      itemBuilder: (context, index) {
        final team = standings[index];
        final form = teamLeagueForm(team.id, matches);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LeagueTeamDetailPage(
                    sport: sport,
                    season: season,
                    teamName: team.id,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  TeamLogo(url: team.logoUrl, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'W${team.wins} D${team.draws} L${team.losses} · ${team.points} pts',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        if (form.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          FormChips(form: form, size: 18),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
