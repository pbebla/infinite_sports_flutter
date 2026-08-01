// ONE source of truth for "which stat categories does a league screen show
// for this sport", shared by the season Player Stats tab and the team page's
// Stats tab.
//
// Why it lives here: the team page used to carry its own hardcoded futsal
// list, so a basketball team's Stats tab looked for goals/saves that don't
// exist and rendered "No stats recorded yet" while the players had 100+
// points (owner report, PR #11). Any future sport is added ONCE here and
// every league stat surface picks it up.
//
// Keys are the `statByName` keys on TournamentPlayer (extraStats for the
// per-sport ones); 'icon' is a statIconAsset key ('' = resolve by sport
// badge or no icon); optional 'suffix' renders after the value.

const Map<String, List<Map<String, String>>> _bySport = {
  'Futsal': [
    // Season leaderboards frame this as the scoring race; a team page is
    // just listing that team's scorers (teamLabel).
    {'label': 'Top Scorer', 'teamLabel': 'Goals', 'stat': 'goals', 'icon': 'goal'},
    {'label': 'Assists', 'stat': 'assists', 'icon': 'assist'},
    {'label': 'Saves', 'stat': 'saves', 'icon': 'save'},
    {'label': 'Defensive Plays (DPL)', 'stat': 'dpl', 'icon': 'dpl'},
    {'label': 'Clean Sheets', 'stat': 'cleanSheets', 'icon': ''},
    {'label': 'Yellow Cards', 'stat': 'yellowCards', 'icon': 'yellow'},
    {'label': 'Red Cards', 'stat': 'redCards', 'icon': 'red'},
  ],
  // Badge sports (isBadgeLeagueSport): the gold bball_*.png / ff_*.png badge
  // resolves from the stat key via leagueStatIcon(), so 'icon' stays blank.
  'Basketball': [
    {'label': 'Points', 'stat': 'points', 'icon': ''},
    {'label': '3-Pointers', 'stat': 'threePointers', 'icon': ''},
    {'label': '2-Pointers', 'stat': 'twoPointers', 'icon': ''},
    {'label': 'Free Throws Made', 'stat': 'freeThrows', 'icon': ''},
    {'label': 'Rebounds', 'stat': 'rebounds', 'icon': ''},
    {'label': 'Assists', 'stat': 'assists', 'icon': ''},
    {'label': 'Steals', 'stat': 'steals', 'icon': ''},
    {'label': 'Blocks', 'stat': 'blocks', 'icon': ''},
    {'label': 'Turnovers', 'stat': 'turnovers', 'icon': ''},
    {'label': 'Fouls', 'stat': 'fouls', 'icon': ''},
  ],
  'Flag Football': [
    {'label': 'Touchdowns', 'stat': 'touchdowns', 'icon': ''},
    {'label': 'Receptions', 'stat': 'receptions', 'icon': ''},
    // Derived REC/(REC+RECMiss), gated to >=3 targets in the adapter so tiny
    // samples never reach the board.
    {'label': 'Catch %', 'stat': 'catchPercentage', 'icon': '', 'suffix': '%'},
    {'label': 'Pass TDs', 'stat': 'passTouchdowns', 'icon': ''},
    {'label': 'Interceptions', 'stat': 'interceptions', 'icon': ''},
    {'label': 'Flag Pulls', 'stat': 'flagPulls', 'icon': ''},
    {'label': 'Sacks', 'stat': 'sacks', 'icon': ''},
  ],
};

/// Stat categories for [sport]; unknown sports fall back to the futsal set
/// (soccer shares it), matching the adapter's own default branch.
///
/// [forTeamPage] swaps in a category's `teamLabel` where one exists — a
/// team's own page says "Goals" where the season leaderboard says
/// "Top Scorer". Same stats, same order, same icons either way.
List<Map<String, String>> leagueStatCategories(String sport,
    {bool forTeamPage = false}) {
  final cats = _bySport[sport] ?? _bySport['Futsal']!;
  if (!forTeamPage) return cats;
  return [
    for (final c in cats)
      if (c['teamLabel'] == null) c else {...c, 'label': c['teamLabel']!},
  ];
}
