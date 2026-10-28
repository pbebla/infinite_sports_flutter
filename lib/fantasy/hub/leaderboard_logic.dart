// Pure logic for the Leaderboards tab, mini-leagues and the manager squad
// viewer (P3d) — no Flutter imports, fully unit-tested
// (test/fantasy/leaderboard_logic_test.dart). The widgets in
// leaderboards_tab.dart / leaderboard_rows.dart / mini_leagues_view.dart /
// manager_squad_viewer.dart stay thin over these helpers: row composition
// with the Managers-then-PublicProfiles name fallback, movement direction,
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
    required this.name,
    required this.points,
    required this.displayRank,
    this.movement,
    required this.isSelf,
    this.photoUrl,
  });

  final String uid;

  /// The manager's fantasy TEAM name (Managers node), falling back to the
  /// PublicProfiles first+last name, then 'Unnamed manager'.
  final String name;
  final int points;

  /// 1-based: the functions-written rank when present, else list position.
  final int displayRank;

  /// Overall movement (+up / −down); null = no arrow data (neutral "—").
  final int? movement;
  final bool isSelf;

  /// PublicProfiles photo; null → initials avatar (photos never gate).
  final String? photoUrl;
}

/// Name resolution (spec §10b): the fantasy team name wherever one exists —
/// but a FLAGGED name is never shown publicly (the owner flagged it as
/// inappropriate), so flagged managers fall back like unnamed ones: the
/// public profile's real name, then 'Unnamed manager'.
String managerDisplayName({
  required String uid,
  required Map<String, FantasyManager> managers,
  required Map<String, PublicProfile> profiles,
}) {
  final manager = managers[uid];
  if (manager != null && !manager.nameFlagged) return manager.teamName;
  final fullName = profiles[uid]?.fullName ?? '';
  return fullName.isEmpty ? 'Unnamed manager' : fullName;
}

String? _photoFor(String uid, Map<String, PublicProfile> profiles) {
  final url = profiles[uid]?.profileUrl ?? '';
  return url.isEmpty ? null : url;
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
        LeaderboardRowData(
          uid: e.uid,
          name:
              managerDisplayName(uid: e.uid, managers: managers, profiles: profiles),
          points: e.points,
          displayRank: e.rank ?? i + 1,
          movement: showMovement ? e.movement : null,
          isSelf: selfUid.isNotEmpty && e.uid == selfUid,
          photoUrl: _photoFor(e.uid, profiles),
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
    ranked.add(LeaderboardRowData(
      uid: e.uid,
      name: managerDisplayName(uid: e.uid, managers: managers, profiles: profiles),
      points: e.points,
      displayRank: ranked.length + 1,
      isSelf: selfUid.isNotEmpty && e.uid == selfUid,
      photoUrl: _photoFor(e.uid, profiles),
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
    ranked.add(LeaderboardRowData(
      uid: m.uid,
      name: m.name,
      points: 0,
      displayRank: ranked.length + 1,
      isSelf: selfUid.isNotEmpty && m.uid == selfUid,
      photoUrl: _photoFor(m.uid, profiles),
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
