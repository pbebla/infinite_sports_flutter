// Pure display helpers for stored game times + playoff stage tags (L3).
// NO Flutter/Firebase imports — unit-tested directly.

/// Stored-time-first game time text. [storedTime] is the optional 'HH:mm'
/// (24h) string from the game node's 'Time' key; [derivedTime] is the
/// legacy start-hour + index already computed by getGames (game.Time).
/// Invalid/absent stored time falls back to the EXACT legacy rendering
/// `'<derivedTime>:00PM'` so untouched seasons look identical.
String gameTimeText(String storedTime, int derivedTime) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(storedTime.trim());
  if (m != null) {
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h <= 23 && min <= 59) {
      final period = h >= 12 ? 'PM' : 'AM';
      var h12 = h % 12;
      if (h12 == 0) h12 = 12;
      return '$h12:${min.toString().padLeft(2, '0')} $period';
    }
  }
  return '$derivedTime:00PM';
}

/// Fan-facing playoff stage tag; '' means "no chip" (regular-season game).
String stageDisplayName(String stage) {
  switch (stage) {
    case 'quarterfinal':
      return 'Quarterfinal';
    case 'semifinal':
      return 'Semifinal';
    case 'final':
      return 'Championship';
    case 'thirdPlace':
      return '3rd Place';
    default:
      return '';
  }
}

/// True for bracket placeholder names ('Winner of SF1', 'Loser of QF2') —
/// these render with a neutral icon instead of a team-logo lookup.
bool isPlaceholderTeam(String name) =>
    name.startsWith('Winner of ') || name.startsWith('Loser of ');
