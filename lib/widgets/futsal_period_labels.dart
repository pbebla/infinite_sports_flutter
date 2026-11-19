import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/futsal_periods.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Copy for the half a live futsal game is in.
String futsalPeriodLabel(FutsalPeriod period) {
  switch (period) {
    case FutsalPeriod.firstHalf:
      return '1st half';
    case FutsalPeriod.halfTime:
      return 'Half time';
    case FutsalPeriod.secondHalf:
      return '2nd half';
    case FutsalPeriod.extraTime:
      return 'Extra time';
  }
}

/// Whether the score header shows the half and team fouls: live games whose
/// node has a `Period` only (old games, other sports, upcoming and final
/// games show nothing new).
bool showsFutsalPeriod(TournamentMatch match) =>
    match.matchStatus.isLive && match.periodInfo?.period != null;

/// The half label under the live clock. Empty when not applicable.
class FutsalHalfLabel extends StatelessWidget {
  const FutsalHalfLabel({super.key, required this.match});

  final TournamentMatch match;

  @override
  Widget build(BuildContext context) {
    if (!showsFutsalPeriod(match)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        futsalPeriodLabel(match.periodInfo!.period!),
        key: const ValueKey('futsal_half_label'),
        style: TextStyle(
          color: TournamentColors.headerForegroundMuted(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// `Fouls <n>` under a team in the header (team 1 or 2). Empty when not
/// applicable.
class FutsalTeamFouls extends StatelessWidget {
  const FutsalTeamFouls({super.key, required this.match, required this.team});

  final TournamentMatch match;
  final int team;

  @override
  Widget build(BuildContext context) {
    if (!showsFutsalPeriod(match)) return const SizedBox.shrink();
    final n = teamFoulsShown(
        team == 1 ? match.team1Activity : match.team2Activity,
        match.periodInfo!);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Fouls $n',
        key: ValueKey('futsal_team_fouls_$team'),
        style: TextStyle(
          color: TournamentColors.headerForegroundMuted(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
