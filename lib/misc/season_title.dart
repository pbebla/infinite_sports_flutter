/// Display title for a league season (release report #6): a bare season
/// number ("15") reads "Season 15"; anything already in words — an AFC San
/// Jose season name, or one that already says "Season" — is shown as-is, so
/// it never becomes "Season Season 15".
String seasonTitle(String season) {
  final s = season.trim();
  if (RegExp(r'^\d+$').hasMatch(s)) return 'Season $s';
  return season;
}
