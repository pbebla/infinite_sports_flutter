// A player's per-gameweek fantasy record (round 3, spec §3.1) — pure model +
// parser for `Fantasy/<sport>/<season>/PlayerWeekStats/<gw>/<name>`, written
// by the finalize functions (functions/src/lib/fantasy/finalize_core.ts):
//
//   { Pts: int,                      // bonus-inclusive week points
//     Played: bool,                  // played in at least one game
//     GP: int,                       // games actually played (stats by name)
//     Games: [ {Vs, For, Against, Forfeit?: 'won'|'lost'} ],  // team schedule
//     Lines: { <key>: {N: count, P: points} },                // zero lines omitted
//     Voided?: true }                // voided week: Pts 0, no Lines
//
// RTDB DROPS empty arrays/objects, so a missing `Games` means [] and a
// missing `Lines` means {}. `Games` (the TEAM's schedule) and `GP` (stats by
// player name) can disagree for guests / team changes — never assume
// `games.length == gamesPlayed`.
//
// No Flutter/Firebase imports — fully unit-tested
// (test/fantasy/player_week_stats_test.dart).

/// One source of points within a week (a `Lines.<key>` entry): [count] of
/// them worth [points] in total (e.g. goals ×3 → 12 pts). For the bonus line
/// both are the bonus points.
class ScoreSourceLine {
  const ScoreSourceLine({required this.count, required this.points});
  final int count;
  final int points;
}

/// One game of a player's week, seen from his team's side.
class PlayerWeekGame {
  const PlayerWeekGame({
    required this.vs,
    required this.goalsFor,
    required this.goalsAgainst,
    this.forfeit,
  });

  /// Opponent team name.
  final String vs;
  final int goalsFor;
  final int goalsAgainst;

  /// 'won' | 'lost' on a forfeited game (spec §8a), else null.
  final String? forfeit;
}

/// One `PlayerWeekStats/<gw>/<name>` entry.
class PlayerWeekStats {
  const PlayerWeekStats({
    required this.points,
    required this.played,
    required this.gamesPlayed,
    required this.games,
    required this.lines,
    required this.voided,
  });

  /// Bonus-inclusive week points (0 for a voided week — it scores zero
  /// everywhere).
  final int points;

  /// Played in at least one game this week.
  final bool played;

  /// Games he actually played (the server's GP). NOT `games.length`.
  final int gamesPlayed;

  /// The team's games this week, in order (may be empty).
  final List<PlayerWeekGame> games;

  /// Week totals by source key (see [scoreSourceLabel]); empty for a voided
  /// week or one with nothing scored.
  final Map<String, ScoreSourceLine> lines;

  /// The owner voided this gameweek: [points] is 0 and [lines] is empty, but
  /// [played] / [gamesPlayed] / [games] keep the real court record.
  final bool voided;
}

int? _int(Object? raw) {
  if (raw is num) return raw.isFinite ? raw.toInt() : null;
  return int.tryParse(raw?.toString().trim() ?? '');
}

/// Children of a list-ish node in index order: a List as-is, an index-keyed
/// Map (RTDB hole collapsing) sorted numerically by key with non-index keys
/// ignored.
List<Object?> _indexedChildren(Object? node) {
  if (node is List) return node;
  if (node is Map) {
    final entries = node.entries
        .map((e) => (index: int.tryParse(e.key.toString()), value: e.value))
        .where((e) => e.index != null)
        .toList()
      ..sort((a, b) => a.index!.compareTo(b.index!));
    return [for (final e in entries) e.value];
  }
  return const [];
}

PlayerWeekGame? _gameFromNode(Object? raw) {
  if (raw is! Map) return null;
  final vs = raw['Vs']?.toString().trim() ?? '';
  if (vs.isEmpty) return null; // no opponent: nothing to show
  final forfeit = raw['Forfeit']?.toString();
  return PlayerWeekGame(
    vs: vs,
    goalsFor: _int(raw['For']) ?? 0,
    goalsAgainst: _int(raw['Against']) ?? 0,
    forfeit: (forfeit == 'won' || forfeit == 'lost') ? forfeit : null,
  );
}

/// One `PlayerWeekStats/<gw>/<name>` node → stats. null when the node is
/// absent, not a Map, or carries no usable `Pts` — "no record for that week"
/// (the player's team didn't play yet / the week isn't finalized).
PlayerWeekStats? playerWeekStatsFromNode(Object? raw) {
  if (raw is! Map) return null;
  final points = _int(raw['Pts']);
  if (points == null) return null;

  final games = <PlayerWeekGame>[
    for (final g in _indexedChildren(raw['Games']))
      if (_gameFromNode(g) case final game?) game,
  ];

  final lines = <String, ScoreSourceLine>{};
  final rawLines = raw['Lines'];
  if (rawLines is Map) {
    rawLines.forEach((key, line) {
      if (line is! Map) return;
      lines[key.toString()] = ScoreSourceLine(
        count: _int(line['N']) ?? 0,
        points: _int(line['P']) ?? 0,
      );
    });
  }

  // GP is always written by the server; fall back to the plays line (the
  // same number by construction), else 0 — never the schedule length.
  final gamesPlayed = _int(raw['GP']) ?? lines['plays']?.count ?? 0;
  final rawPlayed = raw['Played'];

  return PlayerWeekStats(
    points: points,
    played: rawPlayed is bool ? rawPlayed : gamesPlayed > 0,
    gamesPlayed: gamesPlayed,
    games: games,
    lines: lines,
    voided: raw['Voided'] == true,
  );
}

/// Fan-facing label for a `Lines` key (spec §3.1: keys are stable, the
/// client maps them to labels). An unknown key reads as itself.
String scoreSourceLabel(String key) => switch (key) {
      'plays' => 'Played',
      'goals' => 'Goals',
      'assists' => 'Assists',
      'cleanSheet' => 'Clean sheets',
      'saves' => 'Saves',
      'penSaved' => 'Penalty saves',
      'penMissed' => 'Penalty misses',
      'conceded' => 'Goals conceded',
      'dpl' => 'Defensive plays',
      'yellow' => 'Yellow cards',
      'red' => 'Red cards',
      'ownGoals' => 'Own goals',
      'bonus' => 'Bonus',
      _ => key,
    };
