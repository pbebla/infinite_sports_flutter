// A point count as text — the ONE place a count's unit agrees with it (final
// review of the fantasy live plan: "1 pts" showed on court chips, banners, the
// leaderboard, league tables…; the copies that already pluralized were folded
// in here). Exactly ±1 is singular ("1 pt", "-1 pt"); everything else is plural
// — 0 ("0 pts") and a decimal such as a bench player's half points ("2.5 pts").
// Fantasy's tenths of a point go through fantasy_format.dart's
// pointsTenthsText, which uses [pointsUnit].

/// The unit that agrees with [points]: "pt" for exactly ±1, else "pts".
/// [long] spells it out: "point" / "points".
String pointsUnit(num points, {bool long = false}) {
  final one = points.abs() == 1;
  if (long) return one ? 'point' : 'points';
  return one ? 'pt' : 'pts';
}

/// A whole point count with its unit: "34 pts", "1 pt", "-1 pt", "0 pts"
/// ([long]: "1 point", "4 points").
String pointsText(int points, {bool long = false}) =>
    '$points ${pointsUnit(points, long: long)}';
