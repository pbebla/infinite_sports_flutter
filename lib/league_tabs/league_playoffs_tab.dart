import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/league_playoffs_view.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/knockout_tab.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

/// League playoffs (League Experience P2): champion hero banner + the
/// REUSED tournament bracket (KnockoutTab: connector lines, final hero,
/// bronze card, 'Winner of SF1' placeholder slots) over the league's
/// stage-tagged games, wired to the league match page via onMatchTap.
class LeaguePlayoffsTab extends StatelessWidget {
  final LeaguePlayoffs? playoffs;
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final String season;
  final void Function(TournamentMatch match) onMatchTap;

  /// Team-tap audit (PR feedback): champion banner tap → the league team
  /// page. The bracket boxes below stay match taps (owner-directed).
  final void Function(String teamName)? onOpenTeam;

  const LeaguePlayoffsTab({
    super.key,
    required this.playoffs,
    required this.matches,
    required this.teams,
    required this.season,
    required this.onMatchTap,
    this.onOpenTeam,
  });

  @override
  Widget build(BuildContext context) {
    final bracket = leagueBracketMatches(playoffs, matches);
    if (bracket.isEmpty) {
      return const Center(child: Text('Playoffs not yet available'));
    }
    final champion = playoffs?.champion ?? '';
    return Column(
      children: [
        if (champion.isNotEmpty) _championBanner(context, champion),
        Expanded(
          child: KnockoutTab(
            matches: bracket,
            teams: teams,
            onMatchTap: onMatchTap,
          ),
        ),
      ],
    );
  }

  /// Fixed gold gradient + white text — reads identically in light and
  /// dark mode (dark-mode rule: fixed shades under white text).
  /// Tapping it opens the champion's team page (team-tap audit).
  Widget _championBanner(BuildContext context, String champion) {
    final team = teams[champion];
    final banner = Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8860B), Color(0xFFDAA520)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEASON $season CHAMPIONS',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  champion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TeamLogo(url: team?.logoUrl, size: 38),
        ],
      ),
    );
    if (onOpenTeam == null) return banner;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenTeam!(champion),
      child: banner,
    );
  }
}
