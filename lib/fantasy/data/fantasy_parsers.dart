// Pure parsers for the Fantasy RTDB nodes (P3a Task 1) — no Flutter/Firebase
// imports, fully unit-tested (test/fantasy/fantasy_parsers_test.dart), with
// the usual RTDB Map/List-coercion tolerance. FantasyService wraps these in
// onValue streams.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';

/// `Config.lockOverride` (plan P3a): the owner's escape hatch over the
/// engine's automatic gameweek lock. Absent/unknown = auto (production).
enum FantasyLockOverride {
  open,
  locked,
  auto;

  static FantasyLockOverride parse(Object? raw) => switch (raw?.toString()) {
        'open' => open,
        'locked' => locked,
        _ => auto,
      };
}

/// The streamed `Fantasy/<sport>/<season>/Config` node: the engine config the
/// Rules page renders from (spec §10a) plus the lock override.
class FantasyConfigState {
  const FantasyConfigState({required this.config, required this.lockOverride});
  final FantasyConfig config;
  final FantasyLockOverride lockOverride;
}

/// null when the node is absent/malformed — absence is meaningful: it gates
/// the league page's Fantasy tab (no config = no fantasy this season).
FantasyConfigState? configStateFromNode(Object? node) {
  if (node is! Map) return null;
  return FantasyConfigState(
    config: FantasyConfig.fromMap(node),
    lockOverride: FantasyLockOverride.parse(node['lockOverride']),
  );
}

/// One `Fantasy/<sport>/<season>/Managers/<uid>` entry (spec §10b): the
/// manager's fantasy team name plus the owner's moderation flag. A true
/// [nameFlagged] freezes that user's fantasy until they rename (the rules
/// enforce the rename server-side).
class FantasyManager {
  const FantasyManager({required this.teamName, required this.nameFlagged});
  final String teamName;
  final bool nameFlagged;
}

/// null when the node is absent/malformed — meaningful: no entry yet means
/// "prompt this manager to name their team".
FantasyManager? managerFromNode(Object? node) {
  if (node is! Map) return null;
  final name = node['TeamName']?.toString().trim() ?? '';
  if (name.isEmpty) return null;
  return FantasyManager(
    teamName: name,
    nameFlagged: node['NameFlagged'] == true,
  );
}

/// Market players from the Players node, unusable entries skipped, sorted by
/// name for a stable render order (tabs re-sort as they need).
List<FantasyPlayer> playersFromNode(Object? node) {
  final out = <FantasyPlayer>[];
  if (node is! Map) return out;
  node.forEach((name, raw) {
    final player = FantasyPlayer.fromNode(name.toString(), raw);
    if (player != null) out.add(player);
  });
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// `Squads/<uid>` → engine FantasySquad; null when absent or malformed
/// (a broken squad renders as "no squad yet", never crashes the hub).
FantasySquad? squadFromNode(Object? node) {
  if (node is! Map) return null;
  try {
    return FantasySquad.fromMap(node);
  } catch (_) {
    return null;
  }
}

/// One player's finalized season totals (P3c) — written by the P4 functions
/// to `Fantasy/<sport>/<season>/PlayerTotals/<name>` as
/// `{points, ownershipPct}`. Until a gameweek finalizes the node is absent
/// and the market hides its points/ownership column entirely.
class FantasyPlayerTotals {
  const FantasyPlayerTotals({required this.points, this.ownershipPct});

  /// Total fantasy points across finalized gameweeks.
  final int points;

  /// Share of managers holding the player (0–100); null when the functions
  /// haven't written one.
  final double? ownershipPct;
}

/// The whole `PlayerTotals` node → name → totals. null when the node is
/// absent/malformed — meaningful: NO finalized gameweeks yet, so the market
/// hides the points column and the Points sort option (never shows zeros).
Map<String, FantasyPlayerTotals>? playerTotalsFromNode(Object? node) {
  if (node is! Map) return null;
  final out = <String, FantasyPlayerTotals>{};
  node.forEach((name, raw) {
    if (raw is Map) {
      final rawPoints = raw['points'];
      final rawPct = raw['ownershipPct'];
      out[name.toString()] = FantasyPlayerTotals(
        points: rawPoints is num
            ? rawPoints.toInt()
            : int.tryParse(rawPoints?.toString() ?? '') ?? 0,
        ownershipPct: rawPct is num
            ? rawPct.toDouble()
            : double.tryParse(rawPct?.toString() ?? ''),
      );
    } else if (raw is num) {
      // Tolerate a bare-points shape.
      out[name.toString()] = FantasyPlayerTotals(points: raw.toInt());
    }
  });
  return out;
}

/// One Monday repricing move (P3c risers & fallers) — a row of
/// `Fantasy/<sport>/<season>/PriceChanges/<gw>` written by the P4 repricing
/// job: `<name>: {delta: <signed tenths>}` (a bare number tolerated).
class FantasyPriceChange {
  const FantasyPriceChange({required this.name, required this.deltaTenths});
  final String name;

  /// Signed move in $0.1M units (+5 = up $0.5M).
  final int deltaTenths;
}

/// The LATEST gameweek's price moves from the whole `PriceChanges` node:
/// risers first (delta desc, ties by name), zero/unparseable moves skipped.
/// Gameweek keys are small ints, so RTDB WILL list-coerce this node — a List
/// takes its last non-null entry, a Map its numerically largest key. Empty
/// when absent/malformed (the strip hides entirely).
List<FantasyPriceChange> latestPriceChangesFromNode(Object? node) {
  Object? latest;
  if (node is List) {
    for (final child in node) {
      if (child != null) latest = child;
    }
  } else if (node is Map) {
    int? bestGw;
    for (final e in node.entries) {
      final gw = int.tryParse(e.key.toString());
      if (gw == null || e.value == null) continue;
      if (bestGw == null || gw > bestGw) {
        bestGw = gw;
        latest = e.value;
      }
    }
  }
  if (latest is! Map) return const [];
  final out = <FantasyPriceChange>[];
  latest.forEach((name, raw) {
    final Object? rawDelta = raw is Map ? raw['delta'] : raw;
    final delta = rawDelta is num
        ? rawDelta.toInt()
        : int.tryParse(rawDelta?.toString() ?? '');
    if (delta == null || delta == 0) return;
    out.add(FantasyPriceChange(name: name.toString(), deltaTenths: delta));
  });
  out.sort((a, b) {
    final byDelta = b.deltaTenths.compareTo(a.deltaTenths);
    return byDelta != 0 ? byDelta : a.name.compareTo(b.name);
  });
  return out;
}

/// Match-day keys (MMDDYYYY) from the season's `/<sport>/<season>/Date` node
/// — the deriveGameweeks input. Date keys never list-coerce (they aren't
/// small ints), but guard anyway.
List<String> dateKeysFromNode(Object? node) {
  if (node is! Map) return const [];
  return [
    for (final e in node.entries)
      if (e.value != null) e.key.toString(),
  ];
}

// ── Leaderboards (P3d) — THE PINNED NODE SHAPE ─────────────────────────────
// The P4 functions write `Fantasy/<sport>/<season>/Leaderboards` to EXACTLY
// this contract (the client read side here is the source of truth):
//
//   Leaderboards/
//     Overall/<uid>        = { points: int, rank: int, movement: int }
//     Gameweek/<gw>/<uid>  = { points: int, rank: int }
//
// - points:   total fantasy points (Overall = season-to-date across finalized
//             gameweeks; Gameweek = that week alone).
// - rank:     1-based rank among all managers (ties share the smaller rank).
//             The client trusts it when present and falls back to points-desc
//             ordering when absent/malformed.
// - movement: places gained on Overall since the PREVIOUS gameweek finalized
//             (positive = climbed, negative = dropped, 0 = held). Omitted for
//             brand-new managers — absent/0 renders the neutral "—".
// - <gw> is the gameweek number (1-based int). RTDB WILL list-coerce the
//   Gameweek node (small int keys), so the parser accepts a List; uid keys
//   never coerce but are guarded anyway.
// - Node absent entirely = no finalized gameweek yet → the tab's friendly
//   empty state.

/// One manager's row in a leaderboard scope.
class FantasyLeaderboardEntry {
  const FantasyLeaderboardEntry({
    required this.uid,
    required this.points,
    this.rank,
    this.movement,
  });

  final String uid;
  final int points;

  /// 1-based, functions-written; null = absent (order falls back to points).
  final int? rank;

  /// Places gained since last week (+up / −down); null/0 = neutral "—".
  final int? movement;
}

/// The whole streamed `Leaderboards` node. Both sides empty = node absent
/// (no finalized gameweek yet — the tab shows its friendly empty state).
class FantasyLeaderboards {
  const FantasyLeaderboards({required this.overall, required this.byWeek});

  static const FantasyLeaderboards empty =
      FantasyLeaderboards(overall: [], byWeek: {});

  /// Season standings, sorted (rank asc, nulls last, then points desc, uid).
  final List<FantasyLeaderboardEntry> overall;

  /// Gameweek standings by week number, each list sorted the same way.
  final Map<int, List<FantasyLeaderboardEntry>> byWeek;

  bool get isEmpty => overall.isEmpty && byWeek.isEmpty;
}

int? _optInt(Object? raw) =>
    raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');

/// One scope's `{uid: {points, rank, movement}}` map → sorted entries.
/// Malformed children are skipped, never crash.
List<FantasyLeaderboardEntry> leaderboardEntriesFromNode(Object? node) {
  final out = <FantasyLeaderboardEntry>[];
  if (node is! Map) return out;
  node.forEach((uid, raw) {
    if (raw is! Map) return;
    out.add(FantasyLeaderboardEntry(
      uid: uid.toString(),
      points: _optInt(raw['points']) ?? 0,
      rank: _optInt(raw['rank']),
      movement: _optInt(raw['movement']),
    ));
  });
  out.sort((a, b) {
    if (a.rank != null || b.rank != null) {
      if (a.rank == null) return 1;
      if (b.rank == null) return -1;
      final byRank = a.rank!.compareTo(b.rank!);
      if (byRank != 0) return byRank;
    }
    final byPoints = b.points.compareTo(a.points);
    return byPoints != 0 ? byPoints : a.uid.compareTo(b.uid);
  });
  return out;
}

/// The whole `Leaderboards` node. Tolerates the Gameweek child arriving as a
/// List (RTDB small-int-key coercion: index = gameweek number).
FantasyLeaderboards leaderboardsFromNode(Object? node) {
  if (node is! Map) return FantasyLeaderboards.empty;
  final overall = leaderboardEntriesFromNode(node['Overall']);
  final byWeek = <int, List<FantasyLeaderboardEntry>>{};
  final rawWeeks = node['Gameweek'];
  if (rawWeeks is Map) {
    rawWeeks.forEach((gw, raw) {
      final week = int.tryParse(gw.toString());
      if (week == null) return;
      final entries = leaderboardEntriesFromNode(raw);
      if (entries.isNotEmpty) byWeek[week] = entries;
    });
  } else if (rawWeeks is List) {
    for (var i = 0; i < rawWeeks.length; i++) {
      final entries = leaderboardEntriesFromNode(rawWeeks[i]);
      if (entries.isNotEmpty) byWeek[i] = entries;
    }
  }
  return FantasyLeaderboards(overall: overall, byWeek: byWeek);
}

/// The whole `Managers` node → {uid: manager} (leaderboard team names).
/// Children without a usable TeamName are skipped (managerFromNode's rule).
Map<String, FantasyManager> managersFromNode(Object? node) {
  final out = <String, FantasyManager>{};
  if (node is! Map) return out;
  node.forEach((uid, raw) {
    final manager = managerFromNode(raw);
    if (manager != null) out[uid.toString()] = manager;
  });
  return out;
}

// ── Pick transparency (P3d, spec §9) ───────────────────────────────────────
// `PublishedPicks/<gw>/<uid>` and `History/<gw>/<uid>` both hold engine
// FantasySquad.toMap snapshots (functions-written at lock / finalize).

/// One manager's squads across a `<gw>/<uid>` node → {week: squad}.
/// Gameweek keys are small ints, so the node may list-coerce (index = week).
/// Malformed squads are skipped (squadFromNode's rule).
Map<int, FantasySquad> squadsByWeekForUid(Object? node, String uid) {
  final out = <int, FantasySquad>{};
  void take(Object? weekNode, int week) {
    if (weekNode is! Map) return;
    final squad = squadFromNode(weekNode[uid]);
    if (squad != null) out[week] = squad;
  }

  if (node is Map) {
    node.forEach((gw, raw) {
      final week = int.tryParse(gw.toString());
      if (week != null) take(raw, week);
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      take(node[i], i);
    }
  }
  return out;
}

// ── Mini-leagues (P3d, spec §10) ───────────────────────────────────────────
// `MiniLeagues/<id>` = {Name, Code (6 chars A-Z0-9), Owner, CreatedAt,
// Members/<uid>: true} — CLIENT-written (creating = push id with own uid as
// Owner + self as first member; joining = own Members/<uid>: true). Codes
// are public-readable BY DESIGN: they only gate joining a social list (no
// payment/PII), so the join lookup matches client-side on this stream.

class FantasyMiniLeague {
  const FantasyMiniLeague({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    this.createdAtMs,
    required this.memberUids,
  });

  final String id;
  final String name;

  /// 6 chars A-Z0-9, upper-case (rules-validated at create).
  final String code;
  final String ownerUid;
  final int? createdAtMs;
  final Set<String> memberUids;

  int get memberCount => memberUids.length;
  bool hasMember(String uid) => memberUids.contains(uid);
}

/// One `MiniLeagues/<id>` child; null when unusable (no name or code — the
/// rules validate both at create, so this only guards hand-edited data).
FantasyMiniLeague? miniLeagueFromNode(String id, Object? node) {
  if (node is! Map) return null;
  final name = node['Name']?.toString().trim() ?? '';
  final code = node['Code']?.toString().trim().toUpperCase() ?? '';
  if (name.isEmpty || code.isEmpty) return null;
  final members = <String>{};
  final rawMembers = node['Members'];
  if (rawMembers is Map) {
    rawMembers.forEach((uid, v) {
      if (v != null && v != false) members.add(uid.toString());
    });
  }
  return FantasyMiniLeague(
    id: id,
    name: name,
    code: code,
    ownerUid: node['Owner']?.toString() ?? '',
    createdAtMs: _optInt(node['CreatedAt']),
    memberUids: members,
  );
}

/// The whole `MiniLeagues` node, sorted by name (case-insensitive, ties by
/// id) for a stable render order.
List<FantasyMiniLeague> miniLeaguesFromNode(Object? node) {
  final out = <FantasyMiniLeague>[];
  if (node is! Map) return out;
  node.forEach((id, raw) {
    final league = miniLeagueFromNode(id.toString(), raw);
    if (league != null) out.add(league);
  });
  out.sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return out;
}

// ── News feed (P3d, spec §13) ──────────────────────────────────────────────
// `News/Published/<id>` = {Title, Body, At, PhotoUrl?} (owner/AI-published in
// P4/P5; public read already in the rules). `At` is epoch millis.

class FantasyNewsPost {
  const FantasyNewsPost({
    required this.id,
    required this.title,
    required this.body,
    required this.atMs,
    this.photoUrl,
  });

  final String id;
  final String title;
  final String body;
  final int atMs;
  final String? photoUrl;
}

/// Published news, NEWEST FIRST (At desc, ties by id desc — push ids sort
/// chronologically). Children without a title are skipped.
List<FantasyNewsPost> newsPostsFromNode(Object? node) {
  final out = <FantasyNewsPost>[];
  if (node is! Map) return out;
  node.forEach((id, raw) {
    if (raw is! Map) return;
    final title = raw['Title']?.toString().trim() ?? '';
    if (title.isEmpty) return;
    final photo = raw['PhotoUrl']?.toString().trim();
    out.add(FantasyNewsPost(
      id: id.toString(),
      title: title,
      body: raw['Body']?.toString() ?? '',
      atMs: _optInt(raw['At']) ?? 0,
      photoUrl: (photo == null || photo.isEmpty) ? null : photo,
    ));
  });
  out.sort((a, b) {
    final byAt = b.atMs.compareTo(a.atMs);
    return byAt != 0 ? byAt : b.id.compareTo(a.id);
  });
  return out;
}

// ── Dream Team of the Week (P6, spec §10/§13) ──────────────────────────────
// `DreamTeam/<gw>` is functions-written at gameweek finalize (admin-editable
// in the Manager approval flow) to EXACTLY this shape (finalize_core.ts):
//
//   DreamTeam/<gw> = { Players: [ {name, position, points}, ... ],
//                      ComputedAt: int, Auto: true? }
//
// Players come listed GK then DEF then ATT (the config formation), points
// desc per position. `Auto` absent/false = admin-edited (display-identical —
// the flag only matters to the finalizer's overwrite rule). <gw> keys are
// small ints, so RTDB WILL list-coerce the whole node.

/// One Dream Team slot: a market player's name, fantasy position and
/// bonus-inclusive week points.
class FantasyDreamTeamPlayer {
  const FantasyDreamTeamPlayer({
    required this.name,
    required this.position,
    required this.points,
  });

  final String name;
  final FantasyPosition position;
  final int points;
}

/// One gameweek's Team of the Week.
class FantasyDreamTeam {
  const FantasyDreamTeam({
    required this.players,
    this.computedAtMs,
  });

  /// GK first, then DEF, then ATT (the functions' write order is preserved).
  final List<FantasyDreamTeamPlayer> players;
  final int? computedAtMs;
}

/// One `DreamTeam/<gw>` child → team; null when unusable (no parsable
/// players — the week then simply doesn't render). The Players list
/// tolerates the index-keyed Map shape RTDB hands back after a hole.
FantasyDreamTeam? dreamTeamFromNode(Object? node) {
  if (node is! Map) return null;
  final rawPlayers = node['Players'];
  final children = <Object?>[];
  if (rawPlayers is List) {
    children.addAll(rawPlayers);
  } else if (rawPlayers is Map) {
    // Index-keyed map: keep the functions' write order by index.
    final entries = rawPlayers.entries
        .map((e) => (index: int.tryParse(e.key.toString()), value: e.value))
        .where((e) => e.index != null)
        .toList()
      ..sort((a, b) => a.index!.compareTo(b.index!));
    children.addAll([for (final e in entries) e.value]);
  }
  final players = <FantasyDreamTeamPlayer>[];
  for (final raw in children) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final FantasyPosition position;
    try {
      position = FantasyPosition.parse(raw['position']?.toString() ?? '');
    } on ArgumentError {
      continue; // malformed slot: skip, never crash
    }
    players.add(FantasyDreamTeamPlayer(
      name: name,
      position: position,
      points: _optInt(raw['points']) ?? 0,
    ));
  }
  if (players.isEmpty) return null;
  return FantasyDreamTeam(
    players: players,
    computedAtMs: _optInt(node['ComputedAt']),
  );
}

/// The whole `DreamTeam` node → {gameweek: team}. Tolerates the List shape
/// (small-int gw keys coerce: index = gameweek number). Empty = node absent
/// (no finalized gameweek yet) — the hub hides the card entirely.
Map<int, FantasyDreamTeam> dreamTeamsFromNode(Object? node) {
  final out = <int, FantasyDreamTeam>{};
  if (node is Map) {
    node.forEach((gw, raw) {
      final week = int.tryParse(gw.toString());
      if (week == null) return;
      final team = dreamTeamFromNode(raw);
      if (team != null) out[week] = team;
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      final team = dreamTeamFromNode(node[i]);
      if (team != null) out[i] = team;
    }
  }
  return out;
}

// ── Squad alerts (spec §3 holder protection) ─────────────────────────────
//
// Functions-written (functions/src/lib/fantasy/position_changes.ts), read
// own uid only:
//
//   SquadAlerts/<uid> = { Gw: int, Changes: [ {player, from, to}, ... ],
//                         CreatedAt: int }
//
// Present while a position change has left this manager's formation
// illegal; the server clears it on the next save whose formation is legal.

/// One position change behind a squad alert.
class FantasyPositionChange {
  const FantasyPositionChange({
    required this.player,
    required this.from,
    required this.to,
  });

  final String player;
  final FantasyPosition from;
  final FantasyPosition to;
}

/// "Your team needs rearranging" — the hub banner's source.
class FantasySquadAlert {
  const FantasySquadAlert({required this.gameweek, required this.changes});

  /// The gameweek the alert (and its free swap) is for.
  final int gameweek;
  final List<FantasyPositionChange> changes;
}

/// `SquadAlerts/<uid>` → alert; null when absent or carrying no usable
/// change (an empty alert renders nothing). Tolerates the index-keyed Map
/// shape RTDB hands back for a holed Changes list.
FantasySquadAlert? squadAlertFromNode(Object? node) {
  if (node is! Map) return null;
  final raw = node['Changes'];
  final children = <Object?>[
    if (raw is List) ...raw,
    if (raw is Map) ...raw.values,
  ];
  final changes = <FantasyPositionChange>[];
  for (final c in children) {
    if (c is! Map) continue;
    final player = c['player']?.toString().trim() ?? '';
    if (player.isEmpty) continue;
    try {
      changes.add(FantasyPositionChange(
        player: player,
        from: FantasyPosition.parse(c['from']?.toString() ?? ''),
        to: FantasyPosition.parse(c['to']?.toString() ?? ''),
      ));
    } on ArgumentError {
      continue; // malformed change: skip, never crash
    }
  }
  if (changes.isEmpty) return null;
  return FantasySquadAlert(
    gameweek: _optInt(node['Gw']) ?? 0,
    changes: changes,
  );
}

/// The lock state the hub actually enforces: the owner's override wins,
/// otherwise the engine's gameweek status. No current gameweek (season over)
/// counts as locked in auto.
GameweekStatus effectiveGameweekStatus({
  required Gameweek? gameweek,
  required FantasyLockOverride override,
  required DateTime nowUtc,
}) =>
    switch (override) {
      FantasyLockOverride.open => GameweekStatus.open,
      FantasyLockOverride.locked => GameweekStatus.locked,
      FantasyLockOverride.auto =>
        gameweek?.statusAt(nowUtc) ?? GameweekStatus.locked,
    };
