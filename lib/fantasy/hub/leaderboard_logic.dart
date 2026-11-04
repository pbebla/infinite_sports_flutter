// Pure logic for the Leaderboards tab, mini-leagues and the manager squad
// viewer (P3d) — no Flutter imports, fully unit-tested
// (test/fantasy/leaderboard_logic_test.dart). The widgets in
// leaderboards_tab.dart / leaderboard_rows.dart / mini_leagues_view.dart /
// manager_squad_viewer.dart stay thin over these helpers: row composition
// with the two-line names (real name from PublicProfiles + the unflagged
// Managers team name under it; no real name → team name alone), movement
// direction/label,
// mini-league code generation/matching, member ranking, and the
// published-vs-history week fallback the squad viewer enforces (spec §9).
// Leaderboard extras (follow-up): the own-row "Your rank this season" series
// (Leaderboards/RankHistory), the week's biggest climber / faller badges, and
// the Gameweek view's week summary.

import 'dart:math' as math;

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/steady_order.dart'
    show positionMoves;
import 'package:infinite_sports_flutter/misc/public_profiles.dart';

// ── Row composition ────────────────────────────────────────────────────────

/// One rendered leaderboard row — everything the tile needs, resolved.
class LeaderboardRowData {
  const LeaderboardRowData({
    required this.uid,
    this.realName,
    this.teamName,
    required this.points,
    required this.displayRank,
    this.movement,
    required this.isSelf,
    this.photoUrl,
  });

  final String uid;

  /// The manager's real name (PublicProfiles first + last); null when no
  /// profile name is known (e.g. the fake test managers).
  final String? realName;

  /// The manager's fantasy TEAM name (Managers node); null when absent or
  /// FLAGGED (a flagged name is never shown publicly).
  final String? teamName;
  final int points;

  /// 1-based: the functions-written rank when present, else list position.
  final int displayRank;

  /// Overall movement (+up / −down); null = no arrow data (neutral "—").
  final int? movement;
  final bool isSelf;

  /// PublicProfiles photo; null → initials avatar (photos never gate).
  final String? photoUrl;

  /// The primary line (and the squad viewer's title): the real name, else the
  /// team name alone, else 'Unnamed manager'.
  String get name => realName ?? teamName ?? 'Unnamed manager';

  /// The second line: the team name UNDER a real name. null when the team
  /// name already IS the primary line (no real name), when there is none, or
  /// when the team is simply named after the manager (same text ignoring case
  /// and surrounding spaces) — the row never repeats the name.
  String? get secondaryName {
    final real = realName;
    final team = teamName;
    if (real == null || team == null) return null;
    if (real.trim().toLowerCase() == team.trim().toLowerCase()) return null;
    return team;
  }

  /// The squad viewer's app-bar title keeps its contract (the manager's
  /// fantasy TEAM name), falling back to [name].
  String get viewerTitle => teamName ?? name;
}

/// Name resolution (spec §6 / §10b): [realName] is the PublicProfiles first +
/// last name; [teamName] the fantasy team name — but a FLAGGED team name is
/// never shown publicly (the owner flagged it as inappropriate), so a flagged
/// manager keeps only the real name. Blank values count as absent.
({String? realName, String? teamName}) managerNames({
  required String uid,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
}) {
  final manager = managers[uid];
  final team = manager != null && !manager.nameFlagged
      ? manager.teamName.trim()
      : '';
  final real = profiles[uid]?.fullName ?? '';
  return (
    realName: real.isEmpty ? null : real,
    teamName: team.isEmpty ? null : team,
  );
}

/// The one-line display name: the real name when known, else the team name
/// alone, else 'Unnamed manager' (what [LeaderboardRowData.name] resolves to).
String managerDisplayName({
  required String uid,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
}) {
  final names = managerNames(uid: uid, managers: managers, profiles: profiles);
  return names.realName ?? names.teamName ?? 'Unnamed manager';
}

String? _photoFor(String uid, Map<String, PublicProfile> profiles) {
  final url = profiles[uid]?.profileUrl ?? '';
  return url.isEmpty ? null : url;
}

/// One resolved row: names, photo and the self flag come from the same lookup
/// everywhere (Overall, Gameweek and mini-league rows can never drift).
LeaderboardRowData _rowFor({
  required String uid,
  required int points,
  required int displayRank,
  int? movement,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
  required String selfUid,
}) {
  final names = managerNames(uid: uid, managers: managers, profiles: profiles);
  return LeaderboardRowData(
    uid: uid,
    realName: names.realName,
    teamName: names.teamName,
    points: points,
    displayRank: displayRank,
    movement: movement,
    isSelf: selfUid.isNotEmpty && uid == selfUid,
    photoUrl: _photoFor(uid, profiles),
  );
}

/// Entries (already sorted by the parser) → rendered rows. [showMovement]
/// false drops arrows entirely (the Gameweek scope's shape carries none).
List<LeaderboardRowData> composeLeaderboardRows({
  required List<FantasyLeaderboardEntry> entries,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
  required String selfUid,
  bool showMovement = true,
}) =>
    [
      for (final (i, e) in entries.indexed)
        _rowFor(
          uid: e.uid,
          points: e.points,
          displayRank: e.rank ?? i + 1,
          movement: showMovement ? e.movement : null,
          managers: managers,
          profiles: profiles,
          selfUid: selfUid,
        ),
    ];

/// Movement arrow semantics: ▲ (green) up, ▼ (red) down, — neutral for
/// 0/absent.
enum MovementDirection { up, down, none }

MovementDirection movementDirection(int? movement) {
  if (movement == null || movement == 0) return MovementDirection.none;
  return movement > 0 ? MovementDirection.up : MovementDirection.down;
}

String movementGlyph(MovementDirection d) => switch (d) {
      MovementDirection.up => '▲',
      MovementDirection.down => '▼',
      MovementDirection.none => '—',
    };

/// The movement cell's text: the arrow + how many places moved ("▲2", "▼1");
/// a bare dash for 0 or no earlier week.
String movementLabel(int? movement) {
  final direction = movementDirection(movement);
  if (direction == MovementDirection.none) return movementGlyph(direction);
  return '${movementGlyph(direction)}${movement!.abs()}';
}

// ── Rank over the season (Leaderboards/RankHistory) ───────────────────────

/// One point of a manager's season rank line. [live] marks the gameweek being
/// played right now (its rank is provisional — the chart draws it hollow, the
/// share image says so); every settled week is `live: false`.
typedef RankPoint = ({int gameweek, int rank, bool live});

/// The line needs two weeks; under that the panel shows a muted note.
const int kRankChartMinWeeks = 2;

/// A manager's RankHistory ({gameweek → Overall rank}) as points in
/// gameweek order. null / empty → no points. [liveWeeks] are the gameweeks
/// whose point is the live (provisional) one — a live week the history does
/// not carry adds no point.
List<RankPoint> rankSeries(Map<int, int>? history,
    {Set<int> liveWeeks = const {}}) {
  if (history == null || history.isEmpty) return const [];
  final weeks = history.keys.toList()..sort();
  return [
    for (final w in weeks)
      (gameweek: w, rank: history[w]!, live: liveWeeks.contains(w)),
  ];
}

/// [uid]'s rank line from the (live-merged) boards: his RankHistory with the
/// live gameweek's point flagged ([FantasyLeaderboards.liveRankPoints]). The
/// ONE place the chart's opener, the squad viewer's feed, the share story and
/// the profile tab all read it, so they can never disagree about "live".
List<RankPoint> rankSeriesFor(FantasyLeaderboards boards, String uid) =>
    rankSeries(boards.rankHistory[uid],
        liveWeeks: boards.liveRankPoints[uid] ?? const {});

/// "#14 → #10": the first recorded rank → the latest (the live gameweek's
/// provisional rank while one is being played). null under
/// [kRankChartMinWeeks] points (no line to label yet).
String? rankJourneyLabel(List<RankPoint> series) =>
    series.length < kRankChartMinWeeks
        ? null
        : '#${series.first.rank} → #${series.last.rank}';

/// The gameweek whose rank is live on this line (the last point, when it is
/// the live one); null when the line is all settled.
int? rankSeriesLiveWeek(List<RankPoint> series) =>
    series.isNotEmpty && series.last.live ? series.last.gameweek : null;

/// The chart's screen-reader text: every week's rank in order.
String rankSeriesSemantics(List<RankPoint> series) =>
    'Your rank by gameweek: '
    '${series.map((p) => 'GW${p.gameweek} #${p.rank}').join(', ')}';

// ── Live boards (live everywhere, Task 6) ──────────────────────────────────

/// The board is the live gameweek's provisional one ([FantasyLiveFeed]'s merge
/// replaces a scope's rows wholesale, so one live row means a live board).
bool entriesAreLive(List<FantasyLeaderboardEntry> entries) =>
    entries.any((e) => e.live);

/// Which rows moved between two emissions, and which way: a row whose RANK
/// NUMBER changed ([before] → [after]; a better, smaller number is up) or,
/// failing that, whose PLACE in the list changed ([beforeOrder] → [afterOrder]
/// — the fan refreshed a held order; moving up the list is up). A row that is
/// new, or held both its number and its place, is absent. The rank change wins
/// when both moved: the data's word over the list's.
Map<String, MovementDirection> movedRows({
  required List<LeaderboardRowData> before,
  required List<LeaderboardRowData> after,
  required List<String> beforeOrder,
  required List<String> afterOrder,
}) {
  final moved = <String, MovementDirection>{};
  for (final e in positionMoves(beforeOrder, afterOrder).entries) {
    moved[e.key] =
        e.value < 0 ? MovementDirection.up : MovementDirection.down;
  }
  final was = {for (final r in before) r.uid: r.displayRank};
  for (final row in after) {
    final previous = was[row.uid];
    if (previous == null || previous == row.displayRank) continue;
    moved[row.uid] = row.displayRank < previous
        ? MovementDirection.up
        : MovementDirection.down;
  }
  return moved;
}

// ── Biggest climber / faller of the week (Overall) ────────────────────────

enum MoverKind { climber, faller }

/// A row's badge: the week's biggest climb or drop, [places] > 0.
class WeeklyMover {
  const WeeklyMover(this.kind, this.places);

  final MoverKind kind;
  final int places;

  @override
  bool operator ==(Object other) =>
      other is WeeklyMover && other.kind == kind && other.places == places;

  @override
  int get hashCode => Object.hash(kind, places);

  @override
  String toString() => 'WeeklyMover($kind, $places)';
}

/// uid → badge. The manager(s) with the largest positive movement are the
/// climbers, the largest negative the fallers; ties badge every tied
/// manager. No climber when nobody climbed (max ≤ 0), no faller when nobody
/// dropped (min ≥ 0) — absent movement (the first week) counts as neither.
Map<String, WeeklyMover> weeklyMovers(List<LeaderboardRowData> rows) {
  var maxUp = 0;
  var maxDown = 0;
  for (final row in rows) {
    final m = row.movement ?? 0;
    if (m > maxUp) maxUp = m;
    if (m < maxDown) maxDown = m;
  }
  return {
    for (final row in rows)
      if (maxUp > 0 && row.movement == maxUp)
        row.uid: WeeklyMover(MoverKind.climber, maxUp)
      else if (maxDown < 0 && row.movement == maxDown)
        row.uid: WeeklyMover(MoverKind.faller, -maxDown),
  };
}

/// The badge's tooltip + semantics text ("Biggest climber this week (▲3)").
String moverLabel(WeeklyMover mover) => switch (mover.kind) {
      MoverKind.climber =>
        'Biggest climber this week (${movementLabel(mover.places)})',
      MoverKind.faller =>
        'Biggest drop this week (${movementLabel(-mover.places)})',
    };

// ── Gameweek week summary ──────────────────────────────────────────────────

/// The Gameweek view's one-line summary of the selected week.
class GameweekSummary {
  const GameweekSummary({
    required this.average,
    required this.highest,
    required this.topNames,
    this.you,
  });

  /// Mean of the week's points, rounded to whole (half away from zero).
  final int average;
  final int highest;

  /// Display names of every manager on [highest], in row (rank) order.
  final List<String> topNames;

  /// The signed-in manager's points that week; null = no row that week.
  final int? you;

  /// "Sweeper Keepers", or "2 managers" on a tie for the top score.
  String get highestWho =>
      topNames.length == 1 ? topNames.single : '${topNames.length} managers';

  /// "Average 48 pts · Highest 96 (Sweeper Keepers) · You 52".
  String get label => [
        'Average $average pts',
        'Highest $highest ($highestWho)',
        if (you != null) 'You $you',
      ].join(' · ');
}

/// The selected week's composed rows → its summary (names follow the row
/// rule: real name, else team name). null for a week with no rows.
GameweekSummary? gameweekSummary(List<LeaderboardRowData> rows) {
  if (rows.isEmpty) return null;
  final total = rows.fold<int>(0, (sum, r) => sum + r.points);
  final highest = rows.map((r) => r.points).reduce(math.max);
  return GameweekSummary(
    average: (total / rows.length).round(),
    highest: highest,
    topNames: [
      for (final r in rows)
        if (r.points == highest) r.name,
    ],
    you: rows.where((r) => r.isSelf).firstOrNull?.points,
  );
}

// ── Mini-leagues ───────────────────────────────────────────────────────────

/// Code generation alphabet: within the rules' A-Z0-9 but skipping the
/// read-aloud confusables (O/0, I/1/L) — a code someone dictates over the
/// bench should land first try. Validation still accepts all of A-Z0-9.
const String miniLeagueCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A fresh 6-char join code.
String generateMiniLeagueCode([math.Random? rng]) {
  final r = rng ?? math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 6; i++)
      miniLeagueCodeAlphabet.codeUnitAt(r.nextInt(miniLeagueCodeAlphabet.length)),
  ]);
}

/// What a typed/pasted code normalizes to before matching: upper-cased with
/// whitespace and dashes dropped (people paste "abc-123" and "ABC 123").
String normalizeMiniLeagueCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

/// Whether [raw] normalizes to a complete, rules-shaped code (6 of A-Z0-9).
bool isCompleteMiniLeagueCode(String raw) =>
    RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizeMiniLeagueCode(raw));

/// The join flow's live lookup: case/format-insensitive code match over the
/// streamed MiniLeagues list. null = no league with that code (yet).
FantasyMiniLeague? findMiniLeagueByCode(
    List<FantasyMiniLeague> leagues, String raw) {
  final code = normalizeMiniLeagueCode(raw);
  if (code.isEmpty) return null;
  for (final league in leagues) {
    if (league.code == code) return league;
  }
  return null;
}

/// The leagues [uid] belongs to, in the stream's (name-sorted) order.
List<FantasyMiniLeague> leaguesForMember(
        List<FantasyMiniLeague> leagues, String uid) =>
    uid.isEmpty
        ? const []
        : [
            for (final league in leagues)
              if (league.hasMember(uid)) league
          ];

/// A mini-league's internal standings: members with Overall totals first, in
/// Overall order (rank asc = points desc); members without totals yet ranked
/// after, by display name, with 0 pts. Display ranks renumber 1..N locally.
/// No movement arrows inside a league (movement is an OVERALL stat — showing
/// it here would imply league-local movement that nothing computes).
List<LeaderboardRowData> composeMiniLeagueRows({
  required FantasyMiniLeague league,
  required List<FantasyLeaderboardEntry> overall,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
  required String selfUid,
}) {
  final ranked = <LeaderboardRowData>[];
  final seen = <String>{};
  for (final e in overall) {
    if (!league.hasMember(e.uid)) continue;
    seen.add(e.uid);
    ranked.add(_rowFor(
      uid: e.uid,
      points: e.points,
      displayRank: ranked.length + 1,
      managers: managers,
      profiles: profiles,
      selfUid: selfUid,
    ));
  }
  final unranked = [
    for (final uid in league.memberUids)
      if (!seen.contains(uid))
        (
          uid: uid,
          name: managerDisplayName(
              uid: uid, managers: managers, profiles: profiles),
        ),
  ]..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.uid.compareTo(b.uid);
    });
  for (final m in unranked) {
    ranked.add(_rowFor(
      uid: m.uid,
      points: 0,
      displayRank: ranked.length + 1,
      managers: managers,
      profiles: profiles,
      selfUid: selfUid,
    ));
  }
  return ranked;
}

/// [uid]'s display rank inside composed league rows; null when absent.
int? miniLeagueRankOf(String uid, List<LeaderboardRowData> rows) {
  for (final row in rows) {
    if (row.uid == uid) return row.displayRank;
  }
  return null;
}

// ── Squad viewer (pick transparency, spec §9) ──────────────────────────────

/// A manager's browsable weeks: finalized History plus the lock-published
/// current week. A week in both takes the PublishedPicks copy (fresher — the
/// finalize job may rewrite History later with auto-subs applied).
Map<int, FantasySquad> mergeManagerWeeks({
  required Map<int, FantasySquad> history,
  required Map<int, FantasySquad> published,
}) =>
    {...history, ...published};

/// The week the viewer opens on: the current gameweek when that week is
/// available (for others that means "published at lock" — before lock it is
/// NOT in the map, anti-copying), else the latest available week, else null
/// (nothing published yet → "Picks are revealed when the gameweek locks.").
int? defaultViewerWeek({required Set<int> weeks, required int? currentGw}) {
  if (weeks.isEmpty) return null;
  if (currentGw != null && weeks.contains(currentGw)) return currentGw;
  return weeks.reduce(math.max);
}

/// The active chip's human label on a viewed squad (engine chip ids).
String? chipLabel(String? chip) => switch (chip) {
      'tripleCaptain' => 'Triple Captain',
      'benchBoost' => 'Bench Boost',
      'wildcard' => 'Wildcard',
      'freeHit' => 'Free Hit',
      _ => null,
    };
