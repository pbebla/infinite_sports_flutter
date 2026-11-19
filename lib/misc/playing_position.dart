// A player's own PLAYING position, as chosen at registration (release
// report #11) — e.g. "Goal Keeper", "Defender", "Midfielder", "Striker"
// (futsal), "Point Guard" (basketball); a multi-select answer is stored
// ';'-separated ("Defender;Striker").
//
// Shown as stored, normalised by ONE helper: trimmed, each all-lower-case
// word capitalised (anything already cased — "GK", "QB" — kept), blanks and
// repeats dropped, a list joined as "Defender · Striker". Never translated
// into an Infinite Fantasy group (GK / DEF / ATT — FantasyPosition's display
// getters): those are a different thing, labelled "Fantasy: ATT" wherever
// the two could be confused.

/// "defender;striker" → "Defender · Striker"; '' when nothing is stored.
String formatPlayingPosition(String raw) {
  final seen = <String>{};
  final parts = <String>[];
  for (final piece in raw.split(RegExp(r'[;,]'))) {
    final words = piece.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) continue;
    final text = words.map(_capitalise).join(' ');
    if (seen.add(text.toLowerCase())) parts.add(text);
  }
  return parts.join(' · ');
}

/// "Position: Striker" / "Positions: Defender · Striker"; '' when blank.
/// The label that keeps the playing position apart from a fantasy group.
String playingPositionLabel(String raw) {
  final text = formatPlayingPosition(raw);
  if (text.isEmpty) return '';
  return text.contains(' · ') ? 'Positions: $text' : 'Position: $text';
}

String _capitalise(String w) =>
    w == w.toLowerCase() ? '${w[0].toUpperCase()}${w.substring(1)}' : w;
