// Pure parsers for the Fantasy RTDB nodes (P3a Task 1) — no Flutter/Firebase
// imports, fully unit-tested (test/fantasy/fantasy_parsers_test.dart), with
// the usual RTDB Map/List-coercion tolerance. FantasyService wraps these in
// onValue streams.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/parse_ints.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/league_time.dart';
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
/// Rules page renders from (spec §10a) plus the lock override — and the
/// paid-access block (`Config/Access`, spec 2026-11-01 §3), which rides the
/// same subscription so the hub's gate needs no second listener.
class FantasyConfigState {
  const FantasyConfigState({
    required this.config,
    required this.lockOverride,
    this.access = FantasyAccessConfig.free,
  });
  final FantasyConfig config;

  /// The EFFECTIVE override (automation spec 2026-10-28 §2): an open/locked
  /// override whose `lockOverrideUntil` has passed already counts as auto.
  final FantasyLockOverride lockOverride;

  /// Free / season pass (absent block = free, today's behaviour).
  final FantasyAccessConfig access;
}

/// null when the node is absent/malformed — absence is meaningful: it gates
/// the league page's Fantasy tab (no config = no fantasy this season).
/// [now] is a test seam (defaults to the real clock).
FantasyConfigState? configStateFromNode(Object? node, {DateTime? now}) {
  if (node is! Map) return null;
  return FantasyConfigState(
    config: FantasyConfig.fromMap(node),
    lockOverride: _effectiveLockOverride(node, now ?? DateTime.now()),
    access: accessConfigFromNode(node['Access']),
  );
}

/// Spec §2 effective override — server parity with `lockOverrideOf`
/// (functions orchestration_db.ts): open/locked with a numeric
/// `lockOverrideUntil` (epoch ms) at or before [now] → auto. A missing or
/// non-numeric until means "no automatic return" (the override stands). The
/// sweep also flips the stored value to auto within 15 minutes.
FantasyLockOverride _effectiveLockOverride(Map node, DateTime now) {
  final raw = FantasyLockOverride.parse(node['lockOverride']);
  if (raw == FantasyLockOverride.auto) return raw;
  final until = node['lockOverrideUntil'];
  if (until is num &&
      until.isFinite &&
      now.millisecondsSinceEpoch >= until) {
    return FantasyLockOverride.auto;
  }
  return raw;
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
  const FantasyPlayerTotals({
    required this.points,
    this.ownershipPct,
    this.formTenths,
    this.ppgTenths,
    this.games,
    this.live = false,
  });

  /// Total fantasy points across finalized gameweeks (the live overlay adds
  /// the in-progress gameweek's provisional points — see [live]).
  final int points;

  /// Share of managers holding the player (0–100); null when the functions
  /// haven't written one.
  final double? ownershipPct;

  /// Round 3 (spec §3.3), all null when the server hasn't written them (an
  /// old-shape node) — the UI then shows "—", never a made-up 0.0.
  ///
  /// Form, in tenths: mean points of the last 3 non-voided finalized weeks.
  final int? formTenths;

  /// Points per game, in tenths (0 when he has played no games — callers
  /// show "—" for [games] == 0, not "0.0").
  final int? ppgTenths;

  /// Games played this season.
  final int? games;

  /// These numbers are the LIVE gameweek's provisional ones (the `Live/
  /// Players` overlay, fantasy_live.dart), not the finalized ones. Always
  /// false for a parsed `PlayerTotals` row.
  final bool live;
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
        formTenths: tolerantInt(raw['form']),
        ppgTenths: tolerantInt(raw['ppg']),
        games: tolerantInt(raw['games']),
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

/// `<gw>` → `{name: int}` week nodes of [node] (the `PriceHistory` /
/// `PriceChanges` shape). Gameweek keys are small ints, so RTDB WILL
/// list-coerce the node (index = gameweek, holes null) — a List and an
/// int-keyed Map both parse; non-int week keys and non-Map week nodes are
/// skipped. Within a week, children that aren't ints (numeric strings are
/// coerced; booleans such as the `Manual`/`Voided` flags, junk, nulls are
/// not) are skipped; with [skipZero] zero values are skipped too. A week
/// whose node IS a Map is kept even when nothing usable is left in it unless
/// [dropEmptyWeeks].
Map<int, Map<String, int>> _weeklyIntsFromNode(
  Object? node, {
  required bool skipZero,
  required bool dropEmptyWeeks,
  bool allowDeltaMap = false,
}) {
  final out = <int, Map<String, int>>{};
  void take(int week, Object? weekNode) {
    if (weekNode is! Map) return;
    final names = <String, int>{};
    weekNode.forEach((name, raw) {
      final Object? value = (allowDeltaMap && raw is Map) ? raw['delta'] : raw;
      // A bare bool is a flag, not a number (and must not parse as one).
      if (value is bool) return;
      final n = tolerantInt(value);
      if (n == null || (skipZero && n == 0)) return;
      names[name.toString()] = n;
    });
    if (names.isEmpty && dropEmptyWeeks) return;
    out[week] = names;
  }

  if (node is Map) {
    node.forEach((gw, weekNode) {
      final week = int.tryParse(gw.toString());
      if (week != null) take(week, weekNode);
    });
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      take(i, node[i]);
    }
  }
  return out;
}

/// `PriceHistory/<gw>/<name>` (round 3, spec §3.2): the price in tenths each
/// player had DURING each gameweek, snapshotted at that week's lock. A week
/// with no usable price is omitted.
Map<int, Map<String, int>> priceHistoryFromNode(Object? node) =>
    _weeklyIntsFromNode(node, skipZero: false, dropEmptyWeeks: true);

/// `PriceChanges/<gw>` for EVERY gameweek (round 3): `{name: deltaTenths}`
/// per reprice. The server's `Manual` / `Voided` boolean flag keys and zero
/// moves are ignored; a week that only carried flags stays in the map as an
/// empty entry ("a reprice ran, nothing moved"). The existing
/// [latestPriceChangesFromNode] keeps serving the market's latest-week strip.
Map<int, Map<String, int>> allPriceChangesFromNode(Object? node) =>
    _weeklyIntsFromNode(node,
        skipZero: true, dropEmptyWeeks: false, allowDeltaMap: true);

/// `Watchlists/<uid>` (round 3): `{name: true}` → the starred names. Only an
/// exact `true` counts (the rules only ever allow `true`).
Set<String> watchlistFromNode(Object? node) {
  if (node is! Map) return <String>{};
  return {
    for (final e in node.entries)
      if (e.value == true) e.key.toString(),
  };
}

/// The league's own season-over flag, `/<sport>/<season>/Finished`: only an
/// exact `true` means the season is over (absent / false / malformed → not
/// finished). After it the price arrows go away (follow-up C).
bool seasonFinishedFromNode(Object? node) => node == true;

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

// ── Gameweek schedule nodes (season setup + schedule changes) ──────────────
// Twin of functions/src/lib/fantasy/orchestration_db.ts (lockedWeeksOf,
// scheduleOverridesOf, firstKickoffByDateOf): same shapes, same junk rules.

final _dbDateShape = RegExp(r'^\d{8}$');
final _digitsOnly = RegExp(r'^\d+$');
final _hhmmShape = RegExp(r'^(\d{1,2}):(\d{2})$');

/// Largest integer both twins (Dart ints, JS numbers) hold exactly.
const _maxSafeInt = 9007199254740991;

/// True for a string that is a real MMDDYYYY calendar date.
bool _isDbDate(Object? raw) {
  if (raw is! String || !_dbDateShape.hasMatch(raw)) return false;
  final d = parseDbDate(raw);
  return d.month == int.parse(raw.substring(0, 2)) &&
      d.day == int.parse(raw.substring(2, 4));
}

/// A positive epoch-milliseconds NUMBER (an int, or a double on the web) as a
/// UTC instant; null for anything else (strings, bools, NaN, <= 0, or past
/// the DateTime range) so a junk node is skipped, never thrown on.
DateTime? _epochMsToUtc(Object? raw) {
  if (raw is! num || !raw.isFinite || raw <= 0 || raw > 8640000000000000) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
}

/// The children of a node RTDB may hand back as a List (null-padded, index =
/// key) or an int-keyed Map, with their numeric index. Non-numeric Map keys
/// have no index and are skipped.
Iterable<MapEntry<int, Object?>> _indexedChildren(Object? node) sync* {
  if (node is List) {
    for (var i = 0; i < node.length; i++) {
      yield MapEntry(i, node[i]);
    }
  } else if (node is Map) {
    for (final e in node.entries) {
      final key = e.key.toString();
      final index = _digitsOnly.hasMatch(key) ? int.tryParse(key) : null;
      if (index != null) yield MapEntry(index, e.value);
    }
  }
}

/// `Fantasy/<sport>/<season>/LockedWeeks` — the frozen-week ledger:
/// `<n>` → `{Date: 'MMDDYYYY', LockAtUtc: <epoch ms>, Scored?: true}`.
/// Gameweek numbers are small ints, so RTDB list-coerces the node (index =
/// week, index 0 null); a List and an int-keyed Map both parse. An entry that
/// isn't week >= 1, isn't a map, has no valid Date or no numeric LockAtUtc is
/// skipped; `Scored` counts only as a literal `true`.
Map<int, LockedWeek> lockedWeeksFromNode(Object? node) {
  final out = <int, LockedWeek>{};
  for (final e in _indexedChildren(node)) {
    final week = e.value;
    if (e.key < 1 || week is! Map) continue;
    final date = week['Date'];
    final lockUtc = _epochMsToUtc(week['LockAtUtc']);
    if (!_isDbDate(date) || lockUtc == null) continue;
    out[e.key] = LockedWeek(
      date: date as String,
      lockUtc: lockUtc,
      scored: week['Scored'] == true,
    );
  }
  return out;
}

/// The schedule bits of `Fantasy/<sport>/<season>/Config`:
/// `SkippedDates/<MMDDYYYY> = true` (only a literal `true` counts),
/// `Deadlines/<MMDDYYYY> = <epoch ms number>` (anything else is ignored) and
/// `deadlineMinutesBeforeKickoff` (an integer, default 60, clamped 0..240; a
/// non-integer reads as the default).
ScheduleOverrides scheduleOverridesFromConfigNode(Object? configNode) {
  if (configNode is! Map) return const ScheduleOverrides();
  final skipped = <String>{};
  final skippedNode = configNode['SkippedDates'];
  if (skippedNode is Map) {
    skippedNode.forEach((date, v) {
      if (v == true && _isDbDate(date)) skipped.add(date as String);
    });
  }
  final deadlines = <String, DateTime>{};
  final deadlinesNode = configNode['Deadlines'];
  if (deadlinesNode is Map) {
    deadlinesNode.forEach((date, v) {
      final at = _epochMsToUtc(v);
      if (at != null && _isDbDate(date)) deadlines[date as String] = at;
    });
  }
  var minutes = 60;
  final rawMinutes = configNode['deadlineMinutesBeforeKickoff'];
  if (rawMinutes is num &&
      rawMinutes.isFinite &&
      rawMinutes.abs() <= _maxSafeInt &&
      rawMinutes == rawMinutes.truncate()) {
    final n = rawMinutes.toInt();
    minutes = n < 0 ? 0 : (n > 240 ? 240 : n);
  }
  return ScheduleOverrides(
    skippedDates: skipped,
    deadlineOverrides: deadlines,
    minutesBeforeKickoff: minutes,
  );
}

/// League-time instant of a valid 'H:mm' / 'HH:mm' (24 h) string on [date];
/// null when [hhmm] is not a valid time.
DateTime? _kickoffFromHHmm(String date, String hhmm) {
  final m = _hhmmShape.firstMatch(hhmm.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return leagueInstantUtc(date, h, min);
}

/// The earliest kickoff of each match date of a season's
/// `/<sport>/<season>/Date` node (the input of
/// [GameweekSchedule.firstKickoffUtc]). A game's kickoff is its stored `Time`
/// ('HH:mm', 24 h, league time) when valid; otherwise — only when
/// [startHour] (the season Start Time) is > 0 — the legacy derived time
/// [legacyKickoffHHmm] of its index (List position, or the numeric key of an
/// index-keyed Map); otherwise it has none. A date with no kickoff at all is
/// left out, as are non-date keys and non-map games.
Map<String, DateTime> firstKickoffByDateFromNode(
  Object? dateNode, {
  int startHour = 0,
}) {
  final out = <String, DateTime>{};
  if (dateNode is! Map) return out;
  for (final day in dateNode.entries) {
    final rawDate = day.key;
    if (!_isDbDate(rawDate)) continue;
    final date = rawDate as String;
    DateTime? first;
    for (final g in _indexedChildren(day.value)) {
      final game = g.value;
      if (game is! Map) continue;
      final legacy = legacyKickoffHHmm(startHour, g.key);
      final kickoff =
          _kickoffFromHHmm(date, (game['Time'] ?? '').toString()) ??
              (legacy == null ? null : _kickoffFromHHmm(date, legacy));
      if (kickoff != null && (first == null || kickoff.isBefore(first))) {
        first = kickoff;
      }
    }
    if (first != null) out[date] = first;
  }
  return out;
}

// ── Leaderboards (P3d) — THE PINNED NODE SHAPE ─────────────────────────────
// The P4 functions write `Fantasy/<sport>/<season>/Leaderboards` to EXACTLY
// this contract (the client read side here is the source of truth):
//
//   Leaderboards/
//     Overall/<uid>        = { points: int, rank: int, movement: int }
//     Gameweek/<gw>/<uid>  = { points: int, rank: int }
//     RankHistory/<uid>    = { "<gw>": rank, ... }
//
// - points:   total fantasy points (Overall = season-to-date across finalized
//             gameweeks; Gameweek = that week alone).
// - rank:     1-based rank among all managers (ties share the smaller rank).
//             The client trusts it when present and falls back to points-desc
//             ordering when absent/malformed.
// - movement: places gained on Overall since the PREVIOUS gameweek finalized
//             (positive = climbed, negative = dropped, 0 = held). Omitted for
//             brand-new managers — absent/0 renders the neutral "—".
// - RankHistory: each manager's OVERALL rank after every finalized week
//             (finalize_core.ts composeRankHistory) — the fan's "Your rank
//             this season" line. The latest entry is the Overall rank. A
//             manager has no entries before his first finalized week.
// - <gw> is the gameweek number (1-based int). RTDB WILL list-coerce the
//   Gameweek node and a uid's RankHistory map (small int keys), so the
//   parser accepts a List for both; uid keys never coerce but are guarded
//   anyway.
// - Node absent entirely = no finalized gameweek yet → the tab's friendly
//   empty state.

/// One manager's row in a leaderboard scope.
class FantasyLeaderboardEntry {
  const FantasyLeaderboardEntry({
    required this.uid,
    required this.points,
    this.rank,
    this.movement,
    this.live = false,
  });

  final String uid;
  final int points;

  /// 1-based, functions-written; null = absent (order falls back to points).
  final int? rank;

  /// Places gained since last week (+up / −down); null/0 = neutral "—".
  final int? movement;

  /// This row is the LIVE gameweek's provisional number (the `Live/Board`
  /// overlay, fantasy_live.dart), not the finalized one. Always false for a
  /// parsed `Leaderboards` row.
  final bool live;
}

/// The whole streamed `Leaderboards` node. Both sides empty = node absent
/// (no finalized gameweek yet — the tab shows its friendly empty state).
class FantasyLeaderboards {
  const FantasyLeaderboards({
    required this.overall,
    required this.byWeek,
    this.rankHistory = const {},
    this.liveRankPoints = const {},
  });

  static const FantasyLeaderboards empty =
      FantasyLeaderboards(overall: [], byWeek: {});

  /// Season standings, sorted (rank asc, nulls last, then points desc, uid).
  final List<FantasyLeaderboardEntry> overall;

  /// Gameweek standings by week number, each list sorted the same way.
  final Map<int, List<FantasyLeaderboardEntry>> byWeek;

  /// uid → {gameweek → Overall rank after that week}. Empty until the
  /// functions write it; a uid with no usable entries is absent.
  final Map<String, Map<int, int>> rankHistory;

  /// The [rankHistory] points that are LIVE (provisional, from the `Live/
  /// Board` overlay): uid → gameweeks. Empty for the official node. Read
  /// through [isLiveRankPoint].
  final Map<String, Set<int>> liveRankPoints;

  /// [rankHistory]`[uid][gw]` is the live gameweek's provisional rank.
  bool isLiveRankPoint(String uid, int gw) =>
      liveRankPoints[uid]?.contains(gw) ?? false;

  /// Standings only — a RankHistory with no standings is still "no board".
  bool get isEmpty => overall.isEmpty && byWeek.isEmpty;
}

/// The board order every leaderboard list uses: rank asc (unranked last),
/// then points desc, then uid. Sorts [entries] in place and returns it.
List<FantasyLeaderboardEntry> sortLeaderboardEntries(
    List<FantasyLeaderboardEntry> entries) {
  entries.sort((a, b) {
    if (a.rank != null || b.rank != null) {
      if (a.rank == null) return 1;
      if (b.rank == null) return -1;
      final byRank = a.rank!.compareTo(b.rank!);
      if (byRank != 0) return byRank;
    }
    final byPoints = b.points.compareTo(a.points);
    return byPoints != 0 ? byPoints : a.uid.compareTo(b.uid);
  });
  return entries;
}

/// One scope's `{uid: {points, rank, movement}}` map → sorted entries.
/// Malformed children are skipped, never crash.
List<FantasyLeaderboardEntry> leaderboardEntriesFromNode(Object? node) {
  final out = <FantasyLeaderboardEntry>[];
  if (node is! Map) return out;
  node.forEach((uid, raw) {
    if (raw is! Map) return;
    out.add(FantasyLeaderboardEntry(
      uid: uid.toString(),
      points: tolerantInt(raw['points']) ?? 0,
      rank: tolerantInt(raw['rank']),
      movement: tolerantInt(raw['movement']),
    ));
  });
  return sortLeaderboardEntries(out);
}

/// One manager's `RankHistory/<uid>` → {gameweek → rank}. Accepts the
/// List-coerced form (index = gameweek); weeks/ranks below 1 and junk values
/// are skipped, never crash.
Map<int, int> rankHistoryFromNode(Object? node) {
  final out = <int, int>{};
  void put(Object? gw, Object? raw) {
    final week = int.tryParse(gw.toString());
    final rank = raw is Map || raw is List ? null : tolerantInt(raw);
    if (week == null || week < 1 || rank == null || rank < 1) return;
    out[week] = rank;
  }

  if (node is Map) {
    node.forEach(put);
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      put(i, node[i]);
    }
  }
  return out;
}

/// The whole `Leaderboards` node. Tolerates the Gameweek child (and each
/// uid's RankHistory) arriving as a List (RTDB small-int-key coercion:
/// index = gameweek number).
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
  final rankHistory = <String, Map<int, int>>{};
  final rawHistory = node['RankHistory'];
  if (rawHistory is Map) {
    rawHistory.forEach((uid, raw) {
      final history = rankHistoryFromNode(raw);
      if (history.isNotEmpty) rankHistory[uid.toString()] = history;
    });
  }
  return FantasyLeaderboards(
      overall: overall, byWeek: byWeek, rankHistory: rankHistory);
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

// ── Per-player points of a squad week (live everywhere, Task 4) ────────────
// The SAME slot rows live in two places, written by the same scoring core
// (finalize_core.ts scoreWeekCore): settled in `History/<gw>/<uid>.Breakdown`
// = [{playerId, countedTenths, multiplier, autoSubbedIn}] (finalize; unread
// by the app before the live work) and live in `Live/Squads/<uid>.Slots` =
// [{p, c, x, s?}] (live_core.ts) — one model, so a squad screen renders a
// past week and the live week with the same code. One row per pick, in pick
// order. An invalid squad has no rows (RTDB drops the empty list).

/// One squad slot's points for a gameweek: what the player counted for the
/// squad (the captain's multiplier, the bench factor and any auto-sub are
/// already applied) and why.
///
/// Named for the live feed (it is the `Live/Squads` slot); fantasy_live.dart
/// re-exports it, and the settled [historyBreakdownFromNode] returns the same
/// rows.
class LiveSlot {
  const LiveSlot({
    required this.playerId,
    required this.countedTenths,
    required this.multiplier,
    this.autoSubbedIn = false,
  });

  final String playerId;

  /// What the slot added to the squad total, in tenths of a point (a bench
  /// player who did not come on counts at the bench factor).
  final int countedTenths;

  /// The armband's multiplier on this slot: 1 normal, 2 captain, 3 triple
  /// captain (the captain only while he played; else 1).
  final int multiplier;

  /// Filled by an automatic substitution this week.
  final bool autoSubbedIn;
}

/// A list-ish node's children in index order: a List as-is, an index-keyed
/// Map (RTDB hole collapsing) sorted numerically with non-index keys ignored.
List<Object?> _rowsInOrder(Object? node) {
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

/// Settled slot rows from `History/<gw>/<uid>.Breakdown` — or from the whole
/// History entry, whose `Breakdown` child is then read. Rows missing the
/// player, the counted tenths or the multiplier are skipped (never a made-up
/// 0); absent / junk → empty (an invalid squad has no Breakdown).
List<LiveSlot> historyBreakdownFromNode(Object? node) {
  final rows = node is Map && node.containsKey('Breakdown')
      ? node['Breakdown']
      : node;
  return [
    for (final raw in _rowsInOrder(rows))
      if (_slotFromRow(raw, 'playerId', 'countedTenths', 'multiplier',
              'autoSubbedIn')
          case final slot?)
        slot,
  ];
}

/// One manager's settled week — `History/<gw>/<uid>` (written whole by
/// finalize): the net squad-week tenths, the per-pick Breakdown and the two
/// verdicts that void a week for him. The locked My Team reads exactly this
/// node (never the whole History) once the week has settled.
class HistoryWeek {
  const HistoryWeek({
    required this.slots,
    this.totalTenths,
    this.voided = false,
    this.invalid = false,
    this.squad,
  });

  /// The squad that SCORED the week — the picks, the armband and the chip
  /// honored at the lock, exactly as finalize wrote them (`History/<gw>/<uid>`
  /// is the squad map plus the verdict). Unlike `Squads/<uid>`, which the
  /// server rewrites after finalize (the spent chip switched off, a Free Hit
  /// week's squad restored to last week's). null when the node carries no
  /// readable squad.
  final FantasySquad? squad;

  /// The Breakdown rows in pick order (empty for an invalid squad).
  final List<LiveSlot> slots;

  /// `TotalTenths`: the NET week (transfer hits taken off); null when the
  /// node lacks it (never a made-up 0).
  final int? totalTenths;

  /// A literal `Voided: true`: the owner voided the week; it counted 0.
  final bool voided;

  /// The `Invalid` marker (a non-empty list of issues): the lock judged the
  /// squad illegal and it scored 0.
  final bool invalid;
}

/// `History/<gw>/<uid>` → the settled week; null when absent or not a map (no
/// finalized squad that week).
HistoryWeek? historyWeekFromNode(Object? node) {
  if (node is! Map) return null;
  final issues = node['Invalid'];
  return HistoryWeek(
    slots: historyBreakdownFromNode(node),
    totalTenths: tolerantInt(node['TotalTenths']),
    voided: node['Voided'] == true,
    invalid: (issues is List && issues.isNotEmpty) ||
        (issues is Map && issues.isNotEmpty),
    squad: squadFromNode(node),
  );
}

/// One manager's official Overall standing — `Leaderboards/Overall/<uid>`:
/// his rank and the places he climbed ([movement]; null for a manager new
/// this week).
class OverallStanding {
  const OverallStanding({required this.rank, this.movement});

  final int rank;
  final int? movement;
}

/// `Leaderboards/Overall/<uid>` → his standing; null when absent or without a
/// usable rank (never rank 0).
OverallStanding? overallStandingFromNode(Object? node) {
  if (node is! Map) return null;
  final rank = tolerantInt(node['rank']);
  if (rank == null || rank < 1) return null;
  return OverallStanding(rank: rank, movement: tolerantInt(node['movement']));
}

/// Live slot rows from `Live/Squads/<uid>.Slots` ([{p, c, x, s?}]): the same
/// rules as [historyBreakdownFromNode] over the live node's short keys.
List<LiveSlot> liveSlotsFromNode(Object? node) => [
      for (final raw in _rowsInOrder(node))
        if (_slotFromRow(raw, 'p', 'c', 'x', 's') case final slot?) slot,
    ];

LiveSlot? _slotFromRow(
    Object? raw, String id, String tenths, String multiplier, String sub) {
  if (raw is! Map) return null;
  final playerId = raw[id]?.toString().trim() ?? '';
  final counted = tolerantInt(raw[tenths]);
  final x = tolerantInt(raw[multiplier]);
  if (playerId.isEmpty || counted == null || x == null) return null;
  return LiveSlot(
    playerId: playerId,
    countedTenths: counted,
    multiplier: x,
    autoSubbedIn: raw[sub] == true,
  );
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
    createdAtMs: tolerantInt(node['CreatedAt']),
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

// ── News feed (P3d, spec §13; News desk 2.0, spec 2026-10-28 §4.1/§4.2) ────
// `News/Published/<id>` = {Title, Body, At, PhotoUrl?, Template?, Gw?,
//   Players?: {"0": PlayerCard, ...}, Push?, PushedAt?, PushSent?, EditedAt?}
// (Manager/autopilot-published; public read in the rules). `At` is epoch
// millis. Push/PushedAt/PushSent/EditedAt are server/Manager bookkeeping the
// fan feed never needs. Players are SNAPSHOTS taken when the post was built
// (functions news_cards.ts / Manager news_cards.dart) — the feed renders them
// as-is with no extra listeners. Players' small int keys list-coerce, so the
// node arrives as a List or an index-keyed Map.

/// One tagged-player snapshot (spec §4.1 PlayerCard). The server OMITS an
/// optional field when it is unknown — those parse as null and render "–".
class NewsPlayerCard {
  const NewsPlayerCard({
    required this.name,
    required this.position,
    required this.team,
    this.photoUrl,
    required this.priceTenths,
    this.priceDeltaTenths,
    this.gw,
    this.gwPoints,
    this.seasonPoints,
    this.ownershipPct,
    this.goals = 0,
    this.assists = 0,
  });

  final String name;
  final FantasyPosition position;

  /// Team name; '' when the snapshot had none.
  final String team;
  final String? photoUrl;

  /// Price in $0.1M units at snapshot time.
  final int priceTenths;

  /// Latest repricing move (signed tenths); null = no move recorded.
  final int? priceDeltaTenths;

  /// Latest finalized gameweek of the season at snapshot time.
  final int? gw;

  /// This player's points in [gw]; null when he had no entry that week.
  final int? gwPoints;
  final int? seasonPoints;

  /// Share of managers holding him (0–100).
  final double? ownershipPct;
  final int goals;
  final int assists;
}

/// One PlayerCard child → card; null when unusable (no name, an unknown
/// position or no price — skipped, never a crash).
NewsPlayerCard? newsPlayerCardFromNode(Object? node) {
  if (node is! Map) return null;
  final name = node['name']?.toString().trim() ?? '';
  if (name.isEmpty) return null;
  final FantasyPosition position;
  try {
    position = FantasyPosition.parse(node['position']?.toString().trim() ?? '');
  } on ArgumentError {
    return null;
  }
  final price = tolerantInt(node['priceTenths']);
  if (price == null) return null;
  final photo = node['photoUrl']?.toString().trim();
  final rawPct = node['ownershipPct'];
  final pct = rawPct is num
      ? rawPct.toDouble()
      : double.tryParse(rawPct?.toString() ?? '');
  return NewsPlayerCard(
    name: name,
    position: position,
    team: node['team']?.toString().trim() ?? '',
    photoUrl: (photo == null || photo.isEmpty) ? null : photo,
    priceTenths: price,
    priceDeltaTenths: tolerantInt(node['priceDeltaTenths']),
    gw: tolerantInt(node['gw']),
    gwPoints: tolerantInt(node['gwPoints']),
    seasonPoints: tolerantInt(node['seasonPoints']),
    ownershipPct: (pct == null || !pct.isFinite) ? null : pct,
    goals: tolerantInt(node['goals']) ?? 0,
    assists: tolerantInt(node['assists']) ?? 0,
  );
}

/// A post's `Players` node in display order: a List (RTDB coercion) in index
/// order, an index-keyed Map sorted numerically by key (non-index keys
/// ignored). Holes and malformed cards are skipped.
List<NewsPlayerCard> newsPlayerCardsFromNode(Object? node) => [
      for (final raw in _rowsInOrder(node))
        if (newsPlayerCardFromNode(raw) case final card?) card,
    ];

/// The fan-facing card header label for a post template (spec §4.2).
/// 'free', 'ai' and anything unknown read as plain "News".
String newsTemplateLabel(String template) => switch (template) {
      'spotlight' => 'Spotlight',
      'star' => 'Star of the week',
      'price' => 'Price watch',
      'h2h' => 'Head to head',
      'dreamteam' => 'Team of the week',
      _ => 'News',
    };

class FantasyNewsPost {
  const FantasyNewsPost({
    required this.id,
    required this.title,
    required this.body,
    required this.atMs,
    this.photoUrl,
    this.template = 'free',
    this.gw,
    this.players = const [],
  });

  final String id;
  final String title;
  final String body;
  final int atMs;
  final String? photoUrl;

  /// 'spotlight' | 'star' | 'price' | 'h2h' | 'free' | 'dreamteam' | 'ai'
  /// (absent = 'free'; unknown values kept, labelled "News").
  final String template;

  /// The gameweek the story is about; null for undated owner posts.
  final int? gw;

  /// Tagged-player snapshots in display order (0–5).
  final List<NewsPlayerCard> players;

  /// The card's header line: "Spotlight · GW7", or just the label.
  String get headerText {
    final label = newsTemplateLabel(template);
    return gw == null ? label : '$label · GW$gw';
  }
}

/// Published news, NEWEST FIRST (At desc, ties by id desc — push ids sort
/// chronologically). Children without a title are skipped — including the
/// rare server leftover where a push stamp (PushedAt/PushSent) lands after
/// the post was deleted.
List<FantasyNewsPost> newsPostsFromNode(Object? node) {
  final out = <FantasyNewsPost>[];
  if (node is! Map) return out;
  node.forEach((id, raw) {
    if (raw is! Map) return;
    final title = raw['Title']?.toString().trim() ?? '';
    if (title.isEmpty) return;
    final photo = raw['PhotoUrl']?.toString().trim();
    final template = raw['Template']?.toString().trim() ?? '';
    final gw = tolerantInt(raw['Gw']);
    out.add(FantasyNewsPost(
      id: id.toString(),
      title: title,
      body: raw['Body']?.toString() ?? '',
      atMs: tolerantInt(raw['At']) ?? 0,
      photoUrl: (photo == null || photo.isEmpty) ? null : photo,
      template: template.isEmpty ? 'free' : template,
      gw: (gw == null || gw <= 0) ? null : gw,
      players: newsPlayerCardsFromNode(raw['Players']),
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
    this.live = false,
  });

  /// GK first, then DEF, then ATT (the functions' write order is preserved).
  final List<FantasyDreamTeamPlayer> players;
  final int? computedAtMs;

  /// The LIVE gameweek's Team of the Week so far (the `Live/TeamOfWeek`
  /// overlay, fantasy_live.dart), not the finalized one. Always false for a
  /// parsed `DreamTeam` week.
  final bool live;
}

/// One `DreamTeam/<gw>` child → team; null when unusable (no parsable
/// players — the week then simply doesn't render). The Players list
/// tolerates the index-keyed Map shape RTDB hands back after a hole.
FantasyDreamTeam? dreamTeamFromNode(Object? node) {
  if (node is! Map) return null;
  final players = <FantasyDreamTeamPlayer>[];
  // A List as-is; an index-keyed Map keeps the functions' write order.
  for (final raw in _rowsInOrder(node['Players'])) {
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
      points: tolerantInt(raw['points']) ?? 0,
    ));
  }
  if (players.isEmpty) return null;
  return FantasyDreamTeam(
    players: players,
    computedAtMs: tolerantInt(node['ComputedAt']),
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
//
// The SAME node carries the server's integrity verdict (squad hardening,
// audit I2 — functions/src/lib/fantasy/squad_integrity.ts):
//
//   SquadAlerts/<uid> = { Gw: int, Kind: 'invalid',
//                         Issues: ['duplicatePlayer'|'tooManyPlayers'|
//                                  'unknownPlayer'|'ineligiblePlayer'|
//                                  'overBudget', ...], CreatedAt: int }
//
// "Your Gameweek Gw team didn't count" — the lock judged the squad invalid
// and scored it zero; cleared by the next clean save or the next clean
// lock. Lower-case field names (kind/issues/gameweek) are tolerated too.
//
// ...and the open window's over-budget PREVIEW (FPL selling, spec §4 —
// squad_integrity.ts THE OVER-BUDGET PREVIEW):
//
//   SquadAlerts/<uid> = { Gw: int, Kind: 'preview', Issues: ['overBudget'],
//                         OverTenths: int, CreatedAt: int }
//
// "Your team is $X over budget after this week's price changes" — the
// 15-minute sweep judged the SAVED squad at the coming lock's prices; it
// clears once the squad is back within budget (a clean save, the next
// sweep, or the lock — where an Invalid verdict replaces it).

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

/// Which of the alerts sharing `SquadAlerts/<uid>` this is.
enum FantasySquadAlertKind {
  /// A position change broke the formation (spec §3 holder protection).
  positionChange,

  /// The lock judged the squad invalid; that gameweek scored zero.
  invalid,

  /// The open window's warning: at the coming lock's prices the saved squad
  /// is over budget (FPL selling, spec §4) — fix it or the week won't count.
  overBudgetPreview,
}

/// "Your team needs rearranging" / "Your Gameweek N team didn't count" /
/// "Your team is $X over budget" — the hub banner's source.
class FantasySquadAlert {
  const FantasySquadAlert({
    required this.gameweek,
    this.changes = const [],
    this.kind = FantasySquadAlertKind.positionChange,
    this.issues = const [],
    this.overTenths = 0,
  });

  /// The gameweek the alert is for (the free swap's week; the zeroed week
  /// for an integrity alert; the open week for a preview).
  final int gameweek;
  final List<FantasyPositionChange> changes;
  final FantasySquadAlertKind kind;

  /// Integrity alerts only: the server's issue names, as written (unknown
  /// names kept — the banner words the ones it knows).
  final List<String> issues;

  /// Preview only: how far over budget, in tenths of $1M (0 = unknown).
  final int overTenths;

  bool get isInvalid => kind == FantasySquadAlertKind.invalid;
  bool get isOverBudgetPreview =>
      kind == FantasySquadAlertKind.overBudgetPreview;
}

/// `SquadAlerts/<uid>` → alert; null when absent or carrying no usable
/// change (an empty alert renders nothing). Tolerates the index-keyed Map
/// shape RTDB hands back for a holed Changes list.
FantasySquadAlert? squadAlertFromNode(Object? node) {
  if (node is! Map) return null;
  final kind = (node['Kind'] ?? node['kind'])?.toString().trim();
  if (kind == 'invalid' || kind == 'preview') {
    // An integrity verdict (or the preview): shown even with no
    // recognisable issue name (the Invalid banner then says "it broke the
    // squad rules"; the preview banner words no amount without one).
    final rawIssues = node['Issues'] ?? node['issues'];
    final issues = <String>[
      for (final v in [
        if (rawIssues is List) ...rawIssues,
        if (rawIssues is Map) ...rawIssues.values,
      ])
        if (v is String && v.trim().isNotEmpty) v.trim(),
    ];
    final preview = kind == 'preview';
    return FantasySquadAlert(
      gameweek: tolerantInt(node['Gw'] ?? node['gameweek']) ?? 0,
      kind: preview
          ? FantasySquadAlertKind.overBudgetPreview
          : FantasySquadAlertKind.invalid,
      issues: issues,
      overTenths:
          preview ? tolerantInt(node['OverTenths'] ?? node['overTenths']) ?? 0 : 0,
    );
  }
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
    gameweek: tolerantInt(node['Gw']) ?? 0,
    changes: changes,
  );
}

/// The own `TransferState/<uid>` node as the fan app reads it (spec §5,
/// functions-written; the server's TransferState in transfer_state.ts — the
/// SAME fields, so the app's live counter and the lock's recount can never
/// disagree). The node being absent is NOT a view: [parseTransferState]
/// returns null for it (a first team — the preview decides).
class TransferStateView {
  const TransferStateView({
    this.free,
    this.usedThisGw = 0,
    this.countFromGw,
    this.countFrom,
    this.freeSwapsGw,
    this.freeSwaps = const [],
  });

  /// Free transfers available this gameweek (`Free`); null = the FIELD is
  /// absent (the preview then uses the config's weekly allowance, as the
  /// server's tolerant parse does).
  final int? free;

  /// The server's own count for the last counted save (`UsedThisGw`).
  /// RESERVED: parsed (so the view mirrors the node) but displayed nowhere —
  /// the app previews the count itself, from [countFrom] and the live draft,
  /// so it can never disagree with the lock's recount.
  final int usedThisGw;

  /// The gameweek [countFrom] is the baseline for (`CountFromGw`); null = no
  /// baseline published (an older node), or a half-written `CountFrom`.
  final int? countFromGw;

  /// The player ids of the squad the manager came into [countFromGw] with
  /// (`CountFrom`). null with a [countFromGw] = no squad to count from: a
  /// first team, nothing counts. Always null when [countFromGw] is null.
  final List<String>? countFrom;

  /// Holder-protection free swaps (spec §3): selling any of [freeSwaps] in
  /// gameweek [freeSwapsGw] costs no transfer. [freeSwaps] empty and
  /// [freeSwapsGw] null = none (the server writes both or neither).
  final int? freeSwapsGw;
  final List<String> freeSwaps;

  @override
  bool operator ==(Object other) =>
      other is TransferStateView &&
      other.free == free &&
      other.usedThisGw == usedThisGw &&
      other.countFromGw == countFromGw &&
      other.freeSwapsGw == freeSwapsGw &&
      _sameIds(other.countFrom, countFrom) &&
      _sameIds(other.freeSwaps, freeSwaps);

  @override
  int get hashCode => Object.hash(free, usedThisGw, countFromGw, freeSwapsGw,
      countFrom == null ? null : Object.hashAll(countFrom!),
      Object.hashAll(freeSwaps));

  @override
  String toString() => 'TransferStateView(free: $free, used: $usedThisGw, '
      'countFromGw: $countFromGw, countFrom: $countFrom, '
      'freeSwapsGw: $freeSwapsGw, freeSwaps: $freeSwaps)';
}

bool _sameIds(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// `TransferState/<uid>` → view; null ONLY when the node is absent (a
/// first team — never a stand-in for "not read yet" or "read failed", the
/// caller's job). A present node that is not a Map is unreadable: it reads
/// as a node with no baseline (the preview hides), never as absent. Mirrors
/// the server's parseTransferState: tolerates the null-padded List / index-
/// keyed Map RTDB hands back for a holed list; `CountFromGw` is the anchor
/// (without it `CountFrom` is half-written and reads as none; with it and
/// no ids, [TransferStateView.countFrom] is null = a first team), and
/// `FreeSwaps` / `FreeSwapsGw` count only as a pair.
TransferStateView? parseTransferState(Object? node) {
  if (node == null) return null;
  if (node is! Map) return const TransferStateView();
  final free = node['Free'];
  final countFromGw = _positiveInt(node['CountFromGw']);
  final countFromIds =
      countFromGw == null ? const <String>[] : _idList(node['CountFrom']);
  final swapsGw = _positiveInt(node['FreeSwapsGw']);
  final swaps = swapsGw == null ? const <String>[] : _idList(node['FreeSwaps']);
  return TransferStateView(
    free: free is num ? free.toInt() : null,
    usedThisGw: tolerantInt(node['UsedThisGw']) ?? 0,
    countFromGw: countFromGw,
    countFrom: countFromIds.isEmpty ? null : countFromIds,
    freeSwapsGw: swaps.isEmpty ? null : swapsGw,
    freeSwaps: swaps,
  );
}

int? _positiveInt(Object? raw) {
  final n = tolerantInt(raw);
  return n != null && n > 0 ? n : null;
}

/// The non-blank string children of a node RTDB may hand back as a List
/// (null-padded) OR an index-keyed Map.
List<String> _idList(Object? raw) => [
      for (final v in [
        if (raw is List) ...raw,
        if (raw is Map) ...raw.values,
      ])
        if (v is String && v.isNotEmpty) v,
    ];

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
