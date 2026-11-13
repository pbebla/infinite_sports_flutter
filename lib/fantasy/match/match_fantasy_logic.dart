// Pure logic for the match-page Fantasy tab (P6, spec §11) — no Flutter or
// Firebase imports, fully unit-tested (test/fantasy/match_fantasy_logic_test
// .dart). The widget in match_fantasy_tab.dart stays thin over these helpers.
//
// WHAT THIS TAB SHOWS (documented approximation — spec §11 + the P6 brief):
// RAW per-game engine points (stats_mapper → scorePlayerGame), recomputed
// live from the streamed game node. The COUNTED week is the server's job at
// gameweek finalize and differs from these numbers by design:
//   - bench weighting (50%) and auto-subs are WEEKLY concepts — here a bench
//     pick's points show at face value;
//   - vice-captain promotion happens at finalize — an absent captain here
//     simply contributes 0;
//   - the 3/2/1 bonus is awarded at finalize and is not previewed here.
// The one multiplier this tab DOES apply is the viewer's captain (×2, ×3
// while their saved chip is tripleCaptain) — as a labelled callout, never
// silently.
//
// FORFEITS (spec §8a) flow through the SAME engine path (stats_mapper →
// scorePlayerGame) with the roster-composed attendance: the team that
// showed up lists "+1" per present player, the forfeiting team is omitted
// (it did not play), stray recorded events are ignored, and the header
// carries a short note (matchForfeitNote).
//
// LIVE EVERYWHERE (Task 7):
//   - the header says LIVE or FINAL from the game's own status ([matchPhase]);
//   - THE VIEWER'S SQUAD for a game is the squad that was LOCKED for that
//     game's gameweek ([matchViewerSquad]): `PublishedPicks/<gw>/<uid>`, else
//     `History/<gw>/<uid>`'s own squad — never `Squads/<uid>`, which holds
//     whatever the manager saved SINCE (a past game scored against today's
//     squad would highlight players he did not own that week, and a Triple
//     Captain week would read ×2). `Squads/<uid>` only for a week that has
//     not locked yet; a locked week with no locked squad on record has no
//     viewer layer at all;
//   - [gameweekForDate]: a game belongs to the gameweek whose match day is
//     its date (one gameweek per match day, gameweeks.dart);
//   - the footnote gains the My Team sentence ([kMatchFootnote]).

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart'
    show FantasyLockOverride, HistoryWeek;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/player_game_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/scoring.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/engine/stats_mapper.dart';
import 'package:infinite_sports_flutter/misc/forfeit.dart';

/// Whether the match page shows its Fantasy tab: the season's Fantasy Config
/// node exists (stream-gated, like the league page's tab) AND the game isn't
/// a friendly (friendlies never settle fantasy points — the finalizer skips
/// them, so a tab there would only ever show numbers that vanish).
bool showMatchFantasyTab({required bool configExists, required String? stage}) =>
    configExists && stage != 'friendly';

/// Whether the raw game node says the game has started (status 1 live /
/// 2 final; int or String tolerated like the adapters). Pre-kickoff the tab
/// shows its "points land here live" face instead of a wall of default
/// appearance points.
bool matchStarted(Object? status) => matchPhase(status) != MatchPhase.notStarted;

/// Where a game is, from its raw `status` (1 live, 2 final; int or String
/// tolerated like the adapters; anything else has not started). The tab's
/// header reads this: LIVE (the shared pill) or FINAL.
enum MatchPhase { notStarted, live, finished }

MatchPhase matchPhase(Object? status) {
  final s = status is num
      ? status.toInt()
      : int.tryParse(status?.toString().trim() ?? '') ?? 0;
  if (s >= 2) return MatchPhase.finished;
  if (s == 1) return MatchPhase.live;
  return MatchPhase.notStarted;
}

/// The gameweek a game belongs to: the one whose match day is the game's
/// [dateKey] (`MMDDYYYY`, the key it lives under). null = the date is not on
/// the schedule (or the schedule is not known).
Gameweek? gameweekForDate(List<Gameweek> gameweeks, String dateKey) {
  for (final g in gameweeks) {
    if (g.date == dateKey) return g;
  }
  return null;
}

/// Where the viewer's squad for a game came from.
enum MatchSquadSource {
  /// The squad that was LOCKED for the game's gameweek (PublishedPicks, else
  /// History).
  lockedSquad,

  /// `Squads/<uid>`: the week has not locked yet, so what he has saved IS his
  /// squad for it.
  currentSquad,

  /// No viewer squad: the week is locked and none is on record, or the
  /// gameweek is unknown.
  none,
}

typedef MatchViewerSquad = ({FantasySquad? squad, MatchSquadSource source});

/// The viewer's squad for a game in [gameweek]: [published] (the lock's
/// snapshot, `PublishedPicks/<gw>/<uid>`), else [history]'s own squad
/// (`History/<gw>/<uid>`), else — only while the week has not locked yet —
/// [current] (`Squads/<uid>`). A locked week with nothing on record, and a
/// game whose gameweek is unknown, have no viewer squad: never the current one.
///
/// Locked = the clock is at or past the gameweek's lock, or the owner's lock
/// override says "locked" and this is the CURRENT gameweek (an "open" override
/// never makes a past week editable again — and where a locked squad exists it
/// wins whatever the override says).
MatchViewerSquad matchViewerSquad({
  required Gameweek? gameweek,
  required List<Gameweek> gameweeks,
  required FantasyLockOverride lockOverride,
  required DateTime nowUtc,
  FantasySquad? published,
  HistoryWeek? history,
  FantasySquad? current,
}) {
  if (gameweek == null) {
    return (squad: null, source: MatchSquadSource.none);
  }
  final lockedSquad = published ?? history?.squad;
  if (lockedSquad != null) {
    return (squad: lockedSquad, source: MatchSquadSource.lockedSquad);
  }
  final locked = !nowUtc.isBefore(gameweek.lockUtc) ||
      (lockOverride == FantasyLockOverride.locked &&
          currentGameweek(gameweeks, nowUtc)?.number == gameweek.number);
  if (locked) return (squad: null, source: MatchSquadSource.none);
  return (squad: current, source: MatchSquadSource.currentSquad);
}

/// The tab's footnote: the raw-points disclaimer, and (Fable S2) where the
/// counted numbers live.
const String kMatchFootnote =
    'Raw game points, live from the capture. Bench weighting, auto-subs, '
    'vice-captain cover and the 3/2/1 bonus are applied when the gameweek is '
    'finalized — your counted week can differ. Bonus, captain and bench '
    'counting show on My Team.';

/// Port of the Manager's absent-only attendance node (team{n}attendance):
/// ABSENT players only, stored as name -> false (string 'false' tolerated);
/// everything else means present. Tolerates the List shape a numeric-keyed
/// node collapses to (functions/orchestration_db.ts parseAbsentMap parity).
Map<String, bool> absentOnlyFromNode(Object? raw) {
  final out = <String, bool>{};
  void add(String key, Object? value) {
    if (key.isEmpty) return;
    final isFalse = value == false ||
        value?.toString().trim().toLowerCase() == 'false';
    if (isFalse) out[key] = false;
  }

  if (raw is Map) {
    raw.forEach((k, v) => add(k.toString(), v));
  } else if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add(i.toString(), raw[i]);
    }
  }
  return out;
}

/// The FULL attendance map the stats mapper needs (spec §8 default-present):
/// every rostered player true, overridden false by the absent-only node;
/// stray absent keys off the roster stay false so they never score. The
/// roster union is what gives a present, zero-event player their appearance
/// point (functions fullAttendance parity).
Map<String, bool> composeAttendance(
    List<String> roster, Map<String, bool> absent) {
  return {
    for (final name in roster) name: true,
    ...absent,
  };
}

/// One row of the tab's ranked list.
class MatchFantasyRow {
  const MatchFantasyRow({
    required this.name,
    required this.position,
    required this.points,
    this.photoUrl,
    this.isViewerPick = false,
    this.isViewerCaptain = false,
    this.captainMultiplier = 1,
  });

  final String name;
  final FantasyPosition position;

  /// Raw scorePlayerGame total for THIS game (no multipliers).
  final int points;
  final String? photoUrl;

  /// In the viewer's saved squad (starter or bench) — accent highlight.
  final bool isViewerPick;

  /// The viewer's captain — the row shows the "×2 applied" math.
  final bool isViewerCaptain;

  /// 2 (or 3 under tripleCaptain) on the viewer's captain row, 1 elsewhere.
  final int captainMultiplier;
}

/// The tab's list, split per the spec: scored rows ranked desc (ties by
/// name), present-but-zero players collapsed under "No returns yet", absent
/// players omitted entirely.
class MatchFantasyPoints {
  const MatchFantasyPoints({required this.scored, required this.scoreless});

  static const MatchFantasyPoints empty =
      MatchFantasyPoints(scored: [], scoreless: []);

  /// points != 0, sorted points desc then name asc.
  final List<MatchFantasyRow> scored;

  /// Present with exactly 0 points, name asc ("No returns yet").
  final List<MatchFantasyRow> scoreless;

  bool get isEmpty => scored.isEmpty && scoreless.isEmpty;
}

/// Raw per-game points for every PRESENT market player of both teams:
/// activities mapped through the engine's stats_mapper with the composed
/// attendance applied, then scorePlayerGame per player. Players outside the
/// market carry no fantasy position and are skipped; absent players are
/// omitted (spec §11), and so is a forfeiting team (spec §8a — it did not
/// play; the team that showed up scores +1 each). [rosterNamesByTeam] feeds
/// the default-present roster union (a missing roster degrades to
/// activity-event players only — and, on a forfeit, to nobody).
Map<String, int> matchGamePoints({
  required Map gameNode,
  required Map<String, List<String>> rosterNamesByTeam,
  required List<FantasyPlayer> players,
  required FantasyConfig config,
}) {
  final positions = {for (final p in players) p.name: p.position};
  final out = <String, int>{};
  for (final teamKey in const ['team1', 'team2']) {
    final teamName = gameNode[teamKey]?.toString() ?? '';
    if (teamName.isEmpty) continue;
    final attendance = composeAttendance(
      rosterNamesByTeam[teamName] ?? const [],
      absentOnlyFromNode(gameNode['${teamKey}attendance']),
    );
    final Map<String, PlayerGameStats> stats;
    try {
      stats = mapGameToStats(gameNode,
          teamName: teamName,
          attendance: attendance.isEmpty ? null : attendance);
    } on ArgumentError {
      continue; // defensive: a degenerate node never crashes the tab
    }
    stats.forEach((name, s) {
      // Absent, or on a team that forfeited: omitted entirely.
      if (!s.played) return;
      final position = positions[name];
      if (position == null) return; // not a market player: no fantasy points
      out[name] = scorePlayerGame(s, position, config).total;
    });
  }
  return out;
}

/// [matchGamePoints] arranged for the tab, with the viewer's squad applied
/// (highlights + the captain callout). [squad] null = signed out / no squad:
/// plain rows.
MatchFantasyPoints buildMatchFantasyRows({
  required Map gameNode,
  required Map<String, List<String>> rosterNamesByTeam,
  required List<FantasyPlayer> players,
  required FantasyConfig config,
  FantasySquad? squad,
}) {
  final points = matchGamePoints(
    gameNode: gameNode,
    rosterNamesByTeam: rosterNamesByTeam,
    players: players,
    config: config,
  );
  final byName = {for (final p in players) p.name: p};
  final pickIds = {...?squad?.picks.map((p) => p.playerId)};
  final multiplier = captainMultiplierFor(squad, config);

  MatchFantasyRow row(String name, int pts) {
    final isCaptain = squad != null && squad.captainId == name;
    return MatchFantasyRow(
      name: name,
      position: byName[name]!.position,
      points: pts,
      photoUrl: byName[name]!.photoUrl,
      isViewerPick: pickIds.contains(name),
      isViewerCaptain: isCaptain,
      captainMultiplier: isCaptain ? multiplier : 1,
    );
  }

  final scored = <MatchFantasyRow>[];
  final scoreless = <MatchFantasyRow>[];
  points.forEach((name, pts) {
    (pts == 0 ? scoreless : scored).add(row(name, pts));
  });
  scored.sort((a, b) {
    final byPoints = b.points.compareTo(a.points);
    return byPoints != 0 ? byPoints : a.name.compareTo(b.name);
  });
  scoreless.sort((a, b) => a.name.compareTo(b.name));
  return MatchFantasyPoints(scored: scored, scoreless: scoreless);
}

/// The Fantasy tab's header note for a forfeited game (spec §8a), null for
/// a normal one: who forfeited and what that means for points — the team
/// that showed up gets the appearance point only, nothing else counts.
String? matchForfeitNote(Map gameNode) {
  final by = parseForfeitedBy(gameNode[kForfeitedByKey]);
  if (by == null) return null;
  String name(String key) => gameNode[key]?.toString().trim() ?? '';
  final forfeiter = name('team$by');
  final showedUp = name('team${3 - by}');
  final who = forfeiter.isEmpty ? 'A team' : forfeiter;
  final players =
      showedUp.isEmpty ? 'Players who showed up' : '$showedUp players present';
  return '$who forfeited. $players get +1 for the appearance — no other '
      'points or bonus from this game.';
}

/// The viewer's captain multiplier: the config's ×3 while their saved chip
/// is tripleCaptain, else the config's ×2.
int captainMultiplierFor(FantasySquad? squad, FantasyConfig config) =>
    squad?.chip == 'tripleCaptain'
        ? config.tripleCaptainMultiplier
        : config.captainMultiplier;

/// The "You're earning +N this game" chip value: the sum of the raw game
/// points of the viewer's squad members present in this game, captain
/// multiplied (×2, ×3 under tripleCaptain). A DOCUMENTED APPROXIMATION of
/// the counted week (see the file header): bench picks count at face value,
/// no auto-subs or vice promotion, no bonus — finalize owns the real total.
int viewerEarningPoints({
  required Map<String, int> gamePointsByName,
  required FantasySquad? squad,
  required FantasyConfig config,
}) {
  if (squad == null) return 0;
  final multiplier = captainMultiplierFor(squad, config);
  var total = 0;
  for (final pick in squad.picks) {
    final pts = gamePointsByName[pick.playerId];
    if (pts == null) continue; // absent / not in this game
    total += pick.playerId == squad.captainId ? pts * multiplier : pts;
  }
  return total;
}

/// Session memory behind the earning chip's "animate on genuine increase
/// only" rule: records [value] under [gameKey] in [store] and returns the
/// PREVIOUS value (null = first sight this session). The widget animates
/// only when the previous value exists and the new one is strictly greater —
/// a stream reconnect or page re-push re-delivers the same value, returns it
/// unchanged here, and therefore never replays the tween.
int? recordEarningValue(Map<String, int> store, String gameKey, int value) {
  final previous = store[gameKey];
  store[gameKey] = value;
  return previous;
}
