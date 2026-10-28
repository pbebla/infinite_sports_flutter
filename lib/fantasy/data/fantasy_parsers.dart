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
