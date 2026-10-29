// A team's next league game, for the fantasy player profile and market rows
// (round 3, spec §4/§5): "vs Nimrod · Sun 3 PM". Pure — no Flutter/Firebase
// imports; fed the adapted `LeagueService.watchGames` list (the same
// TournamentMatch rows the league pages render), unit-tested in
// test/fantasy/next_game_test.dart.

import 'package:infinite_sports_flutter/misc/league_form.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// The earliest not-yet-final game of a team, seen from that team.
class NextGame {
  const NextGame({
    required this.opponent,
    required this.date,
    required this.timeText,
    required this.placeholder,
  });

  /// Opponent team name (or a bracket placeholder like 'Winner of SF1').
  final String opponent;

  /// The game's calendar day (local midnight).
  final DateTime date;

  /// The game's time as the league pages render it (`gameTimeText`'s
  /// "3:00 PM"); '' when the match carried none.
  final String timeText;

  /// The opponent is a not-yet-decided playoff slot ('Winner of …' /
  /// 'Loser of …') — shown as "Playoffs", never as a team.
  final bool placeholder;
}

/// League date key `MMDDYYYY` → local midnight; null when it isn't one.
DateTime? _dateFromKey(String key) {
  if (!RegExp(r'^\d{8}$').hasMatch(key)) return null;
  final month = int.parse(key.substring(0, 2));
  final day = int.parse(key.substring(2, 4));
  final year = int.parse(key.substring(4));
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  // DateTime rolls 02/30 over to March — reject impossible dates instead.
  if (date.month != month || date.day != day) return null;
  return date;
}

/// [team]'s earliest game that is not final and is dated today or later
/// ([now]'s calendar day), or null when there is none. Live games count (not
/// final yet). Skipped: friendlies (they never settle fantasy points, so
/// they are no "next fantasy game"), rows whose date isn't a valid
/// `MMDDYYYY` key, and rows with no opponent filled in yet.
NextGame? nextGameForTeam(
    String team, List<TournamentMatch> matches, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  // teamLeagueMatches sorts by date, then in-day order (bracketPosition).
  for (final m in teamLeagueMatches(team, matches)) {
    if (m.matchStatus.isFinished) continue;
    if (m.stage.trim().toLowerCase() == 'friendly') continue;
    final date = _dateFromKey(m.date);
    if (date == null || date.isBefore(today)) continue;
    final opponent = ((m.team1Id == team ? m.team2Id : m.team1Id) ?? '').trim();
    if (opponent.isEmpty) continue;
    return NextGame(
      opponent: opponent,
      date: date,
      timeText: (m.time ?? '').trim(),
      placeholder: isPlaceholderTeam(opponent),
    );
  }
  return null;
}

const List<String> _weekdays = [
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', //
];

/// "3:00 PM" / "5:00PM" → "3 PM" / "5 PM"; "3:30 PM" keeps its minutes.
/// Idempotent; anything unrecognised passes through trimmed.
String _compactTime(String text) {
  final t = text.trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$').firstMatch(t);
  if (m == null) return t;
  final minutes = m.group(2)!;
  final period = m.group(3)!.toUpperCase();
  return minutes == '00'
      ? '${m.group(1)} $period'
      : '${m.group(1)}:$minutes $period';
}

/// The one-line fan text: "vs Nimrod · Sun 3 PM"; a placeholder playoff
/// slot reads "Playoffs · Sun" (no opponent, no time — neither is settled).
String formatNextGame(NextGame g) {
  final day = _weekdays[g.date.weekday - 1];
  if (g.placeholder) return 'Playoffs · $day';
  final time = _compactTime(g.timeText);
  return 'vs ${g.opponent} · $day${time.isEmpty ? '' : ' $time'}';
}
