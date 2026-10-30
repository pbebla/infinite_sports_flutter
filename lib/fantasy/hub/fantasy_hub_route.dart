// Where a fantasy push tap lands (automation spec 2026-10-28 §4.2) — pure,
// no Flutter/Firebase imports, unit-tested in
// test/fantasy/fantasy_hub_route_test.dart.
//
// Every fantasy push carries data `{type:'fantasy', sport, season, gw}`;
// news-post pushes add `postId`. A postId opens the hub's News tab scrolled
// to that post; everything else (deadline reminder, weekly recap, position
// alerts, owner messages) opens My Team.
//
// "Open in Fantasy" (round 3, spec §7) uses the same route value: the Players
// tab plus [FantasyHubRoute.initialPlayerName], which makes the hub push that
// player's profile (with the hub's shared draft) once it is ready.

/// The hub's tabs, in TabBar order (the index IS the tab position).
enum FantasyHubTab { myTeam, players, leaderboards, news, rules }

/// A resolved fantasy push tap: which hub to open and where.
class FantasyHubRoute {
  const FantasyHubRoute({
    required this.sport,
    required this.season,
    required this.initialTab,
    this.focusPostId,
    this.initialPlayerName,
  });

  final String sport;
  final String season;
  final FantasyHubTab initialTab;

  /// The news post to scroll to; null for non-news pushes.
  final String? focusPostId;

  /// A player whose fantasy profile the hub opens once it is ready ("Open in
  /// Fantasy"); null for push taps and ordinary entries.
  final String? initialPlayerName;
}

/// "Open in Fantasy" from a player's profile (the Infinite profile's Fantasy
/// tab, the match tab): the hub on its Players tab, then that player's
/// profile on top — back lands on the market.
FantasyHubRoute fantasyRouteForPlayer({
  required String sport,
  required String season,
  required String playerName,
}) =>
    FantasyHubRoute(
      sport: sport,
      season: season,
      initialTab: FantasyHubTab.players,
      initialPlayerName: playerName,
    );

/// null when [data] is not a fantasy push or lacks sport/season (the tap
/// then does nothing — it must never crash the app). FCM data values are
/// strings; anything else is stringified.
FantasyHubRoute? fantasyRouteFromPayload(Map<dynamic, dynamic> data) {
  if (data['type']?.toString() != 'fantasy') return null;
  final sport = data['sport']?.toString().trim() ?? '';
  final season = data['season']?.toString().trim() ?? '';
  if (sport.isEmpty || season.isEmpty) return null;
  final postId = data['postId']?.toString().trim() ?? '';
  return FantasyHubRoute(
    sport: sport,
    season: season,
    initialTab: postId.isEmpty ? FantasyHubTab.myTeam : FantasyHubTab.news,
    focusPostId: postId.isEmpty ? null : postId,
  );
}
