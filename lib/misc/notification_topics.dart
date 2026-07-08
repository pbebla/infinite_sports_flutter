/// FCM topic naming for follow bells.
/// MUST stay in parity with functions/src/lib/decide.ts (sanitizeId,
/// tournamentTopic, teamTopic) — the Watcher addresses these exact topics.
String sanitizeTopicId(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

String tournamentTopic(String tournamentId) =>
    'tournament_${sanitizeTopicId(tournamentId)}';

String teamTopic(String tournamentId, String teamId) =>
    'tournament_${sanitizeTopicId(tournamentId)}_team_${sanitizeTopicId(teamId)}';

/// League team follow topic (League Experience P2). Bell UI + FollowStore
/// subscribe this today; NO pushes are addressed to it until the P3
/// functions watcher lands — extend functions/src/lib/decide.ts with this
/// EXACT builder before sending league notifications.
String leagueTeamTopic(String sport, String season, String teamName) =>
    'league_${sanitizeTopicId(sport)}_${sanitizeTopicId(season)}_team_${sanitizeTopicId(teamName)}';
