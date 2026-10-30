// The full-screen fantasy player profile's pure model (round 3, spec §4) —
// no Flutter/Firebase imports, unit-tested in
// test/fantasy/fantasy_player_profile_logic_test.dart. The page and its tab
// widgets stay thin over [buildProfileModel]; the Infinite profile's Fantasy
// tab (Task 9) reuses the same model for its price/move/form/bars summary.
//
// Inputs are the Task 4 feeds: the player's weekly records
// (`PlayerWeekStats/<gw>/<name>`), `PlayerTotals/<name>`, and the whole
// `PriceHistory` / `PriceChanges` week maps. A voided week scores zero
// everywhere: it keeps its Matches row ("Week voided — 0"), its form bar
// (flagged) and its price row, but never counts toward a season total.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// How many recent gameweeks the form bars show.
const int kProfileFormBarCount = 6;

/// The Overview copy before any finalized week (spec §4).
const String kPointsStartCopy = 'Points start after Gameweek 1';

/// One recent-form bar: a gameweek he has a record for.
class FormBar {
  const FormBar({required this.gw, required this.points, required this.voided});
  final int gw;

  /// Bonus-inclusive week points (0 for a voided week).
  final int points;
  final bool voided;
}

/// One source of points ("Goals ×13 — 52 pts"): a week's line, or the
/// season sum of a line key over non-voided weeks.
class SourceTotal {
  const SourceTotal({
    required this.key,
    required this.count,
    required this.points,
  });

  /// The stable server line key (`goals`, `plays`, `bonus`, …).
  final String key;
  final int count;
  final int points;

  String get label => scoreSourceLabel(key);
}

/// One Matches-tab row (newest first in the model).
class MatchRow {
  const MatchRow({
    required this.gw,
    required this.opponentsText,
    required this.points,
    required this.seasonToDate,
    required this.lines,
    required this.voided,
    required this.played,
  });

  final int gw;

  /// "vs Nimrod 3–2 · vs Kings (forfeit win)"; "No game" when his team had
  /// no game that week.
  final String opponentsText;

  /// The week's points (0 for a voided week).
  final int points;

  /// Season points through this week — voided weeks add nothing.
  final int seasonToDate;

  /// The week's breakdown (zero-point lines dropped, |points| desc); empty
  /// for a voided week.
  final List<SourceTotal> lines;
  final bool voided;

  /// He played at least one game that week.
  final bool played;
}

/// One Price-tab row: the price he had DURING [gw] (snapshotted at that
/// week's lock) and the Monday move after it.
class PriceRow {
  const PriceRow({
    required this.gw,
    required this.priceTenths,
    this.moveAfterTenths,
  });

  final int gw;
  final int priceTenths;

  /// The reprice after [gw]: signed tenths, 0 = the reprice ran and he
  /// didn't move, null = no reprice has run for that week yet.
  final int? moveAfterTenths;
}

/// Everything the profile renders, derived from the live feeds.
class FantasyProfileModel {
  const FantasyProfileModel({
    required this.player,
    required this.latestMoveTenths,
    required this.totalPoints,
    required this.games,
    required this.ppgTenths,
    required this.formTenths,
    required this.ownershipPct,
    required this.hasWeeks,
    required this.formBars,
    required this.sourceTotals,
    required this.matchRows,
    required this.priceRows,
    required this.startPriceTenths,
    required this.highTenths,
    required this.lowTenths,
  });

  final FantasyPlayer player;

  /// Current price (tenths) — the live market value.
  int get priceTenths => player.priceTenths;

  /// His move in the LATEST reprice: null before any reprice ran (show
  /// nothing), 0 when that reprice ran without moving him ("No change").
  final int? latestMoveTenths;

  /// `PlayerTotals/<name>`: null when the node (or his entry) is absent.
  final int? totalPoints;
  final int? games;
  final int? ppgTenths;
  final int? formTenths;
  final double? ownershipPct;

  /// At least one weekly record exists (a finalized gameweek with him in
  /// the market). False → "Points start after Gameweek 1".
  final bool hasWeeks;

  /// The last [kProfileFormBarCount] weeks he has a record for, oldest →
  /// newest.
  final List<FormBar> formBars;

  /// Season points by source over non-voided weeks.
  final List<SourceTotal> sourceTotals;

  /// One row per week he has a record for, newest first.
  final List<MatchRow> matchRows;

  /// One row per week he was priced in, newest first.
  final List<PriceRow> priceRows;

  /// Price history summary; null while no week has priced him.
  final int? startPriceTenths;
  final int? highTenths;
  final int? lowTenths;

  bool get _noGames => games == null || games == 0;

  String get totalPointsText => totalPoints?.toString() ?? '—';

  /// "5.3"; "—" when he has played no games (never "0.0", spec §4).
  String get ppgText =>
      (_noGames || ppgTenths == null) ? '—' : _tenthsText(ppgTenths!);

  /// "6.7"; "—" when he has played no games.
  String get formText =>
      (_noGames || formTenths == null) ? '—' : _tenthsText(formTenths!);

  String get gamesText => games?.toString() ?? '—';

  String get ownedText =>
      ownershipPct == null ? '—' : '${ownershipPct!.toStringAsFixed(0)}%';

  /// The stat strip's line under the price (null = show nothing).
  String? get moveText => moveThisWeekText(latestMoveTenths);
}

String _tenthsText(int tenths) => (tenths / 10).toStringAsFixed(1);

/// Canonical source order (spec §3.1 line keys) — the tie-break after
/// |points|; unknown keys sort after these, by key.
const List<String> _sourceOrder = [
  'plays',
  'goals',
  'assists',
  'cleanSheet',
  'saves',
  'penSaved',
  'penMissed',
  'conceded',
  'dpl',
  'yellow',
  'red',
  'ownGoals',
  'bonus',
];

int _sourceRank(String key) {
  final i = _sourceOrder.indexOf(key);
  return i < 0 ? _sourceOrder.length : i;
}

/// Sums [lineMaps] per key, drops zero-point keys, sorts |points| desc.
List<SourceTotal> _sumSources(Iterable<Map<String, ScoreSourceLine>> lineMaps) {
  final counts = <String, int>{};
  final points = <String, int>{};
  for (final lines in lineMaps) {
    lines.forEach((key, line) {
      counts[key] = (counts[key] ?? 0) + line.count;
      points[key] = (points[key] ?? 0) + line.points;
    });
  }
  final out = [
    for (final key in points.keys)
      if (points[key] != 0)
        SourceTotal(key: key, count: counts[key]!, points: points[key]!),
  ];
  out.sort((a, b) {
    final byPoints = b.points.abs().compareTo(a.points.abs());
    if (byPoints != 0) return byPoints;
    final byRank = _sourceRank(a.key).compareTo(_sourceRank(b.key));
    return byRank != 0 ? byRank : a.key.compareTo(b.key);
  });
  return out;
}

/// Builds the profile model. [weeks] = his `PlayerWeekStats` records by
/// gameweek; [priceHistory] / [priceChanges] = the whole season's week maps
/// (`{gw: {name: tenths}}`, Task 4 parsers).
FantasyProfileModel buildProfileModel({
  required FantasyPlayer player,
  FantasyPlayerTotals? totals,
  required Map<int, PlayerWeekStats> weeks,
  required Map<int, Map<String, int>> priceHistory,
  required Map<int, Map<String, int>> priceChanges,
}) {
  final name = player.name;
  final gws = weeks.keys.toList()..sort();

  // Form bars: the last N weeks present, oldest → newest.
  final barWeeks = gws.length <= kProfileFormBarCount
      ? gws
      : gws.sublist(gws.length - kProfileFormBarCount);
  final formBars = [
    for (final gw in barWeeks)
      FormBar(
        gw: gw,
        points: weeks[gw]!.voided ? 0 : weeks[gw]!.points,
        voided: weeks[gw]!.voided,
      ),
  ];

  // Season sources: non-voided weeks only.
  final sourceTotals = _sumSources([
    for (final gw in gws)
      if (!weeks[gw]!.voided) weeks[gw]!.lines,
  ]);

  // Matches: running season total ascending, rendered newest first.
  final rows = <MatchRow>[];
  var running = 0;
  for (final gw in gws) {
    final w = weeks[gw]!;
    if (!w.voided) running += w.points;
    rows.add(MatchRow(
      gw: gw,
      opponentsText: opponentsText(w.games),
      points: w.voided ? 0 : w.points,
      seasonToDate: running,
      lines: w.voided ? const [] : _sumSources([w.lines]),
      voided: w.voided,
      played: w.played,
    ));
  }

  // Price rows: every week that priced him, with the move after it.
  final priced = [
    for (final gw in priceHistory.keys)
      if (priceHistory[gw]!.containsKey(name)) gw,
  ]..sort();
  final priceRows = <PriceRow>[
    for (final gw in priced.reversed)
      PriceRow(
        gw: gw,
        priceTenths: priceHistory[gw]![name]!,
        moveAfterTenths: priceChanges.containsKey(gw)
            ? (priceChanges[gw]![name] ?? 0)
            : null,
      ),
  ];
  int? start, high, low;
  if (priced.isNotEmpty) {
    start = priceHistory[priced.first]![name]!;
    final all = [for (final r in priceRows) r.priceTenths, player.priceTenths];
    high = all.reduce((a, b) => a > b ? a : b);
    low = all.reduce((a, b) => a < b ? a : b);
  }

  // This week's move: the latest reprice that ran.
  int? latestMove;
  if (priceChanges.isNotEmpty) {
    final latest = priceChanges.keys.reduce((a, b) => a > b ? a : b);
    latestMove = priceChanges[latest]![name] ?? 0;
  }

  return FantasyProfileModel(
    player: player,
    latestMoveTenths: latestMove,
    totalPoints: totals?.points,
    games: totals?.games,
    ppgTenths: totals?.ppgTenths,
    formTenths: totals?.formTenths,
    ownershipPct: totals?.ownershipPct,
    hasWeeks: gws.isNotEmpty,
    formBars: formBars,
    sourceTotals: sourceTotals,
    matchRows: rows.reversed.toList(),
    priceRows: priceRows,
    startPriceTenths: start,
    highTenths: high,
    lowTenths: low,
  );
}

/// A week's games from his team's side: "vs Nimrod 3–2 · vs Kings (forfeit
/// win)"; "No game" when there were none.
String opponentsText(List<PlayerWeekGame> games) {
  if (games.isEmpty) return 'No game';
  return [
    for (final g in games)
      switch (g.forfeit) {
        'won' => 'vs ${g.vs} (forfeit win)',
        'lost' => 'vs ${g.vs} (forfeit loss)',
        _ => 'vs ${g.vs} ${g.goalsFor}–${g.goalsAgainst}',
      },
  ].join(' · ');
}

/// "Goals ×13"; the bonus line's count IS its points, so it reads "Bonus".
String sourceLineLabel(SourceTotal s) =>
    s.key == 'bonus' ? s.label : '${s.label} ×${s.count}';

/// "52 pts" / "1 pt" / "-1 pt".
String pointsText(int points) => '$points ${points.abs() == 1 ? 'pt' : 'pts'}';

/// The stat strip's move line: "▲ $0.5M this week" / "▼ $0.5M this week" /
/// "No change"; null before the first reprice (show nothing).
String? moveThisWeekText(int? moveTenths) {
  if (moveTenths == null) return null;
  if (moveTenths == 0) return 'No change';
  return '${moveTenths > 0 ? '▲' : '▼'} '
      '${formatMoneyTenths(moveTenths.abs())} this week';
}

/// A Price-tab row's move: "▲ $0.3M" / "▼ $1.2M" / "No change"; "—" while
/// that week's reprice hasn't run.
String priceMoveText(int? moveTenths) {
  if (moveTenths == null) return '—';
  if (moveTenths == 0) return 'No change';
  return '${moveTenths > 0 ? '▲' : '▼'} ${formatMoneyTenths(moveTenths.abs())}';
}

/// "Goalkeeper" / "Defender" / "Attacker" (the hero's "Team · Position").
String positionLabel(FantasyPosition p) => switch (p) {
      FantasyPosition.gk => 'Goalkeeper',
      FantasyPosition.def => 'Defender',
      FantasyPosition.att => 'Attacker',
    };

/// His league roster row (season stats, shirt number): team AND name, the
/// same join as the account link (player_account_link.dart) — the same name
/// on another team is a different person and never his row (Review Focus
/// 1). null when his team has no such row (the tiles then dash).
/// [rosters] = `LeagueService.watchRosters`' {team: [players]}.
TournamentPlayer? rosterRowFor(
    FantasyPlayer p, Map<String, List<TournamentPlayer>> rosters) {
  final team = p.teamName.trim();
  final name = p.name.trim();
  for (final e in rosters.entries) {
    if (e.key.trim() != team) continue;
    for (final r in e.value) {
      if (r.name.trim() == name) return r;
    }
  }
  return null;
}
