// Pure logic for tool/seed_fantasy.dart (Fantasy P3a Task 0) — everything
// here is deterministic and network-free so test/fantasy/seed_logic_test.dart
// can cover it. The CLI shell (REST reads/writes) stays in seed_fantasy.dart.
//
// Shape notes (verified against live Futsal/15 on 2026-10-27):
// - `<sport>/<season>/Line Ups` = {team: {playerName: {UID, number, stats…}}}
//   — NO position key on the lineup entry; the registration position lives at
//   `Users/<uid>/Information/<sport>Position` as a multi-select string whose
//   separators appear as BOTH ';' and ':' in real data (e.g.
//   "Defender;Midfielder;Striker", "Goal Keeper:Defender:Midfielder:Striker").
//   The FIRST listed position is treated as the player's primary.
// - `<sport>/<season>/Date/<MMDDYYYY>` = list of game nodes (RTDB array
//   coercion), each {team1, team2, team1score, team2score, team1activity,
//   team2activity, …} — exactly what the engine's mapGameToStats consumes.
// - Season 15 predates the attendance step (spec §8), so the seed passes the
//   team's full lineup as "everyone present" — the engine's own documented
//   default for missing attendance — which credits appearance and clean-sheet
//   points to roster players without recorded activities.

import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/pricing.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';
import 'package:infinite_sports_flutter/fantasy/engine/stats_mapper.dart';

/// One lineup row: the market player set comes from Line Ups, never from
/// activities (activity-only names — e.g. 'Guest' — are reported, not seeded).
class LineupEntry {
  const LineupEntry({required this.name, required this.teamName, this.uid});
  final String name;
  final String teamName;
  final String? uid; // null when missing/'0' (unlinked player)
}

/// Tolerant Line Ups parse: skips non-map teams/entries, normalizes UID
/// '0'/''/missing to null (the same rule leaguePlayerFromLineup applies).
List<LineupEntry> parseLineups(Object? lineupsNode) {
  final out = <LineupEntry>[];
  if (lineupsNode is! Map) return out;
  lineupsNode.forEach((team, lineup) {
    if (lineup is! Map) return;
    lineup.forEach((name, info) {
      if (info is! Map) return;
      var uid = info['UID']?.toString().trim();
      if (uid == null || uid.isEmpty || uid == '0') uid = null;
      out.add(LineupEntry(
          name: name.toString(), teamName: team.toString(), uid: uid));
    });
  });
  return out;
}

/// Guests are recorded under the literal player name 'Guest' (league
/// convention — see league_sport_config.dart); they are never selectable
/// in fantasy (spec §3).
bool isGuestName(String name) => name.trim().toLowerCase() == 'guest';

/// Registration position → fantasy position (spec §3 defaults):
/// Goal Keeper→GK, Defender→DEF, Midfielder→ATT, Striker→ATT. Multi-select
/// strings (';' or ':' separated in real data) use the FIRST listed position
/// as primary; missing/unknown registrations default to ATT (the spec's
/// midfielder default — owner-overridable per player in the Manager app).
FantasyPosition mapRegistrationPosition(String? raw) {
  String? first;
  for (final part in (raw ?? '').split(RegExp(r'[;:,/]'))) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) {
      first = trimmed;
      break;
    }
  }
  final p = (first ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (p == 'goalkeeper' || p == 'gk' || p == 'keeper' || p == 'goalie') {
    return FantasyPosition.gk;
  }
  if (p == 'defender' || p == 'defense' || p == 'defence' ||
      p == 'def' || p == 'd') {
    return FantasyPosition.def;
  }
  // Midfielder, Striker, M, S, forward, unknown, missing → ATT.
  return FantasyPosition.att;
}

/// Season aggregation result: per-player fantasy points plus every name that
/// appeared in activities without a lineup entry (guests, misspellings) —
/// those earn no market entry and the CLI surfaces them for the owner.
class SeasonAggregate {
  const SeasonAggregate(
      {required this.pointsByName, required this.activityOnlyNames});
  final Map<String, double> pointsByName;
  final Set<String> activityOnlyNames;
}

/// Replays every finished game node through the engine's stats mapper and
/// scoring table: one season-total of base fantasy points per lineup player,
/// the openingPrices() input. The team's full roster is passed as attendance
/// (all present — see the file header note on pre-attendance seasons).
SeasonAggregate seasonPointsByPlayer({
  required Object? dateNode,
  required Map<String, FantasyPosition> positionByName,
  required Map<String, Set<String>> rosterByTeam,
  required FantasyConfig cfg,
}) {
  final points = <String, double>{
    for (final name in positionByName.keys) name: 0.0,
  };
  final strays = <String>{};

  void scoreGame(Object? gameNode) {
    if (gameNode is! Map) return;
    for (final teamKey in const ['team1', 'team2']) {
      final team = gameNode[teamKey]?.toString();
      if (team == null || team.isEmpty) continue;
      final roster = rosterByTeam[team] ?? const <String>{};
      final stats = mapGameToStats(
        gameNode,
        teamName: team,
        attendance: {for (final name in roster) name: true},
      );
      stats.forEach((name, s) {
        final pos = positionByName[name];
        if (pos == null) {
          strays.add(name);
          return;
        }
        points[name] = (points[name] ?? 0) + scorePlayerGame(s, pos, cfg).total;
      });
    }
  }

  void eachGame(Object? games) {
    if (games is List) {
      games.forEach(scoreGame);
    } else if (games is Map) {
      games.values.forEach(scoreGame);
    }
  }

  if (dateNode is Map) {
    dateNode.values.forEach(eachGame);
  } else if (dateNode is List) {
    dateNode.forEach(eachGame); // defensive: date keys are never list-coerced
  }
  return SeasonAggregate(pointsByName: points, activityOnlyNames: strays);
}

/// Opening prices, grouped BY POSITION before calling the engine's
/// openingPrices() (it maps percentile WITHIN the group — spec §4). Players
/// without a season aggregate are rookies → cfg.rookiePriceTenths.
Map<String, int> buildOpeningPrices({
  required Map<String, FantasyPosition> positionByName,
  required Map<String, double> pointsByName,
  required FantasyConfig cfg,
}) {
  final prices = <String, int>{};
  for (final pos in FantasyPosition.values) {
    final group = <String, double>{};
    for (final e in positionByName.entries) {
      if (e.value != pos) continue;
      final pts = pointsByName[e.key];
      if (pts == null) {
        prices[e.key] = cfg.rookiePriceTenths;
      } else {
        group[e.key] = pts;
      }
    }
    prices.addAll(openingPrices(group, cfg));
  }
  return prices;
}

/// The `Fantasy/<sport>/<season>/Players` node: {name: {position, priceTenths,
/// eligible, teamName, photoUrl?}} — the exact shape the fan app's market
/// parses. [photoUrlByName] (P3b Task 3) carries PublicProfiles ProfileUrls
/// resolved through each lineup entry's UID link; players without a link (or
/// without a public photo) simply omit the key and render initials.
Map<String, Map<String, Object>> buildPlayersNode({
  required List<LineupEntry> lineups,
  required Map<String, FantasyPosition> positionByName,
  required Map<String, int> priceByName,
  required FantasyConfig cfg,
  Map<String, String> photoUrlByName = const {},
}) {
  final node = <String, Map<String, Object>>{};
  for (final entry in lineups) {
    final photo = photoUrlByName[entry.name]?.trim();
    node[entry.name] = {
      'position': (positionByName[entry.name] ?? FantasyPosition.att).db,
      'priceTenths': priceByName[entry.name] ?? cfg.rookiePriceTenths,
      'eligible': !isGuestName(entry.name),
      'teamName': entry.teamName,
      if (photo != null && photo.isNotEmpty) 'photoUrl': photo,
    };
  }
  return node;
}

/// The `Fantasy/<sport>/<season>/Config` node: the engine's own launch
/// defaults plus the test-bed `lockOverride: 'open'` escape hatch (plan P3a
/// task 0 — lets the owner edit squads although every S15 date is past).
Map<String, dynamic> buildConfigNode({String lockOverride = 'open'}) =>
    FantasyConfig.futsalDefault().toMap()..['lockOverride'] = lockOverride;

/// Refusal for the seed CLI: a season that already has a market (or config)
/// must never be overwritten — the PUT would reset every live price. Returns
/// null when the seed may write: both nodes absent, or [force] (throwaway test
/// seasons only). The message is season-agnostic; the CLI prefixes the season
/// path, e.g. `Fantasy/Futsal/16 already has a market (Players) …`.
String? seedRefusal({
  required Object? existingPlayers,
  required Object? existingConfig,
  required bool force,
}) {
  if (force) return null;
  final hasPlayers = existingPlayers != null;
  final hasConfig = existingConfig != null;
  if (!hasPlayers && !hasConfig) return null;
  final what = hasPlayers && hasConfig
      ? 'Players and Config'
      : hasPlayers
          ? 'Players'
          : 'Config';
  final noun = hasPlayers ? 'a market' : 'a season config';
  return 'already has $noun ($what) — refusing to overwrite. '
      'Real seasons start from the Manager (Fantasy → Start fantasy season). '
      'Pass --force-reseed only for a throwaway test season.';
}
