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

import 'dart:math' as math;

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
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
  /// name already IS the primary line (no real name) or there is none.
  String? get secondaryName => realName == null ? null : teamName;

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
