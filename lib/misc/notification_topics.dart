/// FCM topic naming for follow bells.
/// MUST stay in parity with functions/src/lib/decide.ts (sanitizeId,
/// tournamentTopic, teamTopic) — the Watcher addresses these exact topics.
String sanitizeTopicId(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

String tournamentTopic(String tournamentId) =>
    'tournament_${sanitizeTopicId(tournamentId)}';

String teamTopic(String tournamentId, String teamId) =>
    'tournament_${sanitizeTopicId(tournamentId)}_team_${sanitizeTopicId(teamId)}';

/// League team follow topic (League Experience P2). MUST stay in parity with
/// functions/src/lib/league_decide.ts leagueTeamTopic — the league watcher
/// addresses this exact topic in its FCM conditions.
String leagueTeamTopic(String sport, String season, String teamName) =>
    'league_${sanitizeTopicId(sport)}_${sanitizeTopicId(season)}_team_${sanitizeTopicId(teamName)}';

/// Season-wide league follow topic (League Experience P3.3): every game
/// alert for the whole season, tournament-bell parity. A strict
/// prefix-sibling of [leagueTeamTopic] ('league_{sport}_{season}' vs
/// 'league_{sport}_{season}_team_{team}'). MUST stay in parity with
/// functions/src/lib/league_decide.ts leagueSeasonTopic.
String leagueSeasonTopic(String sport, String season) =>
    'league_${sanitizeTopicId(sport)}_${sanitizeTopicId(season)}';
