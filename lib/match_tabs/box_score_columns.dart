// Pure column/sort layer for the per-team Match Box Score tabs (Match Box
// Score spec, 2026-07-28). No Flutter imports — unit-tested directly.
//
// Column sets are importance-ordered per the owner's spec table. A Fouls
// column exists only for sports whose match capture records foul events:
// soccer/futsal ('Foul'/'foul') and basketball ('Foul') do; flag football
// has no foul event anywhere in its LeagueSportConfig, so it defines none.

import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// One box-score stat column. [valueOf] reads a player's single-match tally
/// (null tally = player with no recorded events this match). A null VALUE
/// means "no data" (rendered as a dash) — only Catch % produces one, for
/// players without targets.
class BoxScoreColumn {
  final String key;

  /// Short header label ('PTS', 'Pass TD').
  final String label;

  final int? Function(MatchPlayerTally? t) valueOf;

  /// Rendered after the value ('%' for Catch %).
  final String suffix;

  const BoxScoreColumn({
    required this.key,
    required this.label,
    required this.valueOf,
    this.suffix = '',
  });
}

int _count(MatchPlayerTally? t, String key) => t?.counts[key] ?? 0;

/// Basketball PTS derived from the made-shot buckets: FT + 2×2PT + 3×3PT.
int _points(MatchPlayerTally? t) =>
    _count(t, 'freeThrows') +
    2 * _count(t, 'twoPointers') +
    3 * _count(t, 'threePointers');

/// FF Catch % — UNGATED, unlike Match Leaders' >=3-target gate: the box
/// score shows a player's real rate whenever they have targets, null (a
/// dash) when they have none.
int? _catchPct(MatchPlayerTally? t) =>
    catchPercentage(_count(t, 'receptions'), _count(t, 'recMisses'));

final List<BoxScoreColumn> _soccerFutsalColumns = [
  BoxScoreColumn(key: 'goals', label: 'Goals', valueOf: (t) => t?.goals ?? 0),
  BoxScoreColumn(
      key: 'assists', label: 'Assists', valueOf: (t) => t?.assists ?? 0),
  BoxScoreColumn(key: 'dpl', label: 'DPL', valueOf: (t) => t?.dpl ?? 0),
  BoxScoreColumn(key: 'saves', label: 'Saves', valueOf: (t) => t?.saves ?? 0),
  BoxScoreColumn(
      key: 'fouls', label: 'Fouls', valueOf: (t) => _count(t, 'fouls')),
  BoxScoreColumn(
      key: 'yellowCards',
      label: 'Yellow',
      valueOf: (t) => _count(t, 'yellowCards')),
  BoxScoreColumn(
      key: 'redCards', label: 'Red', valueOf: (t) => _count(t, 'redCards')),
];

final List<BoxScoreColumn> _basketballColumns = [
  BoxScoreColumn(key: 'points', label: 'PTS', valueOf: _points),
  BoxScoreColumn(
      key: 'rebounds', label: 'REB', valueOf: (t) => _count(t, 'rebounds')),
  BoxScoreColumn(key: 'assists', label: 'AST', valueOf: (t) => t?.assists ?? 0),
  BoxScoreColumn(
      key: 'threePointers',
      label: '3PM',
      valueOf: (t) => _count(t, 'threePointers')),
  BoxScoreColumn(
      key: 'twoPointers',
      label: '2PM',
      valueOf: (t) => _count(t, 'twoPointers')),
  BoxScoreColumn(
      key: 'freeThrows', label: 'FTM', valueOf: (t) => _count(t, 'freeThrows')),
  BoxScoreColumn(
      key: 'steals', label: 'STL', valueOf: (t) => _count(t, 'steals')),
  BoxScoreColumn(
      key: 'blocks', label: 'BLK', valueOf: (t) => _count(t, 'blocks')),
  BoxScoreColumn(
      key: 'turnovers', label: 'TO', valueOf: (t) => _count(t, 'turnovers')),
  BoxScoreColumn(
      key: 'fouls', label: 'Fouls', valueOf: (t) => _count(t, 'fouls')),
];

final List<BoxScoreColumn> _flagFootballColumns = [
  BoxScoreColumn(
      key: 'touchdowns', label: 'TD', valueOf: (t) => _count(t, 'touchdowns')),
  BoxScoreColumn(
      key: 'passTouchdowns',
      label: 'Pass TD',
      valueOf: (t) => _count(t, 'passTouchdowns')),
  BoxScoreColumn(
      key: 'receptions', label: 'REC', valueOf: (t) => _count(t, 'receptions')),
  BoxScoreColumn(
      key: 'interceptions',
      label: 'INT',
      valueOf: (t) => _count(t, 'interceptions')),
  BoxScoreColumn(
      key: 'flagPulls',
      label: 'Flag Pulls',
      valueOf: (t) => _count(t, 'flagPulls')),
  BoxScoreColumn(key: 'sacks', label: 'Sacks', valueOf: (t) => _count(t, 'sacks')),
  BoxScoreColumn(
      key: 'catchPercentage',
      label: 'Catch %',
      valueOf: _catchPct,
      suffix: '%'),
];

/// The sport's full column defs, importance-ordered (first = primary stat =
/// default sort). Returns the SAME list instance per sport so widget-level
/// identity caching works. Unknown sports fall back to the soccer/futsal
/// set (the leagueMatchLeaderCategories convention).
List<BoxScoreColumn> boxScoreColumnsFor(String sport) {
  switch (sport) {
    case 'Basketball':
      return _basketballColumns;
    case 'Flag Football':
      return _flagFootballColumns;
    default: // Soccer / Futsal
      return _soccerFutsalColumns;
  }
}

/// Auto-hide filter: a column renders only if at least one player in the
/// match has a non-null, non-zero value. Callers pass the WHOLE match's
/// tallies (both teams) so the two team tabs always show the same columns.
List<BoxScoreColumn> visibleColumns(
    List<BoxScoreColumn> columns, Iterable<MatchPlayerTally> tallies) {
  return columns
      .where((c) => tallies.any((t) {
            final v = c.valueOf(t);
            return v != null && v != 0;
          }))
      .toList();
}

/// Sorted copy of [roster] for the box score. [column] null = alphabetical
/// ([ascending] true = A-Z). For stat columns, [ascending] false = best
/// first (the default); null values ("no data") sink below every number,
/// and exact ties always break A-Z so the order is deterministic.
List<TournamentPlayer> sortedBoxScoreRows(
  List<TournamentPlayer> roster,
  Map<String, MatchPlayerTally> tallies, {
  BoxScoreColumn? column,
  required bool ascending,
}) {
  int byName(TournamentPlayer a, TournamentPlayer b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final out = [...roster];
  out.sort((a, b) {
    if (column == null) {
      final cmp = byName(a, b);
      return ascending ? cmp : -cmp;
    }
    final av = column.valueOf(tallies[a.name]) ?? -1;
    final bv = column.valueOf(tallies[b.name]) ?? -1;
    final cmp = av.compareTo(bv);
    if (cmp != 0) return ascending ? cmp : -cmp;
    return byName(a, b);
  });
  return out;
}
