import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/league_team_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Route to the live league match page for a league-engine game, or null when
/// [match] is not a league game id (`dateKey#index`).
MaterialPageRoute<void>? leagueMatchRoute({
  required String sport,
  required String season,
  required TournamentMatch match,
}) {
  final ref = parseLeagueGameId(match.id);
  if (ref == null) return null;
  return MaterialPageRoute<void>(
    builder: (_) => LeagueMatchDetailPage(
      sport: sport,
      season: season,
      dateKey: ref.dateKey,
      gameIndex: ref.index,
      initialMatch: match,
    ),
  );
}

/// Route to a league team's page.
MaterialPageRoute<void> leagueTeamRoute({
  required String sport,
  required String season,
  required String teamName,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => LeagueTeamDetailPage(
      sport: sport,
      season: season,
      teamName: teamName,
    ),
  );
}

/// Pushes the league match page. Returns false (pushing nothing) when [match]
/// is not a league game.
bool openLeagueMatch(
  BuildContext context, {
  required String sport,
  required String season,
  required TournamentMatch match,
}) {
  final route = leagueMatchRoute(sport: sport, season: season, match: match);
  if (route == null) return false;
  Navigator.push(context, route);
  return true;
}

/// Pushes a league team's page.
void openLeagueTeam(
  BuildContext context, {
  required String sport,
  required String season,
  required String teamName,
}) {
  Navigator.push(
    context,
    leagueTeamRoute(sport: sport, season: season, teamName: teamName),
  );
}
