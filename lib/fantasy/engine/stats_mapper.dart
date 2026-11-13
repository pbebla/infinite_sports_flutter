/// Maps one real futsal game node (`Futsal/<season>/Date/<MMDDYYYY>/<i>`)
/// into per-player [PlayerGameStats] for ONE team — the bridge between
/// captured activities and the fantasy engine. Pure Dart: takes
/// already-decoded Map/List values, no Flutter/Firebase imports.
///
/// Shape notes (mirrors the proven parsers — scorepage.populateActivities,
/// single_match_tallies, tournament_stats_engine):
/// - `team1activity`/`team2activity` are minute-keyed maps of leaf buckets,
///   but RTDB array coercion can hand EITHER level over as a (possibly
///   null-padded) List — both levels accept List or Map here.
/// - Each leaf is `{activityType: playerName}` plus optional metadata keys
///   (`_t` insertion stamps); activity_entry.dart is the shared
///   metadata-skipping source of truth.
/// - Scores may be int or String (utility.dart tolerates both), with the
///   legacy `team1Score`/`team2Score` spelling as fallback.
///
/// Counting rules (spec §7/§8, league conventions verified in
/// league_sport_config.dart + tournament_stats_engine.dart):
/// - goals = Goal + PenGoal (league statKeys pair PenGoal with Goals).
/// - yellows = Yellow only; reds = Red + SecondYellow (the second yellow IS
///   the red — statKeys ['SecondYellow', 'Red'] — so a 2nd-yellow player
///   nets first Yellow + one red, never two yellows).
/// - PenSaved lives on the KEEPER'S OWN team list and credits the keeper;
///   the league pairs it with Saves (statKeys ['PenSaved', 'Saves']), so it
///   bumps BOTH penSaved and saves, exactly like the match tally engines.
/// - teamConceded = the opposing team's final score.
/// - present comes from the attendance map (spec §8): a missing map or a
///   missing player entry defaults to present.
/// - forfeit comes from the game's `forfeitedBy` marker (see FORFEITS).
/// - inGoal (spec §7 stand-in goalkeeper) is decided per player per game:
///   ≥1 Save or PenSaved on his own team list (only a keeper makes saves in
///   futsal), OR his name keyed `true` in his side's `team{1,2}keepers`
///   marker (the Manager's attendance-step "In goal" switch — same name
///   keys as `team{1,2}attendance`, List/Map coercion tolerated, only a
///   literal `true` counts). The marker only flags players already in the
///   result — it never adds one. Position-blind: scoring ignores it for a
///   listed GK.
/// - Foul, Substitution and unknown/legacy types (e.g. 'Blue') carry no
///   fantasy counter and are skipped — same as the tally engines.
///
/// FORFEITS (spec §8a, owner Option B): a game carrying `forfeitedBy: 1|2`
/// (misc/forfeit.dart parseForfeitedBy — the Manager's Forfeit button) maps
/// every entry with [GameForfeit.won] (this team showed up) or
/// [GameForfeit.lost] (this team forfeited), and its activity events are
/// IGNORED ENTIRELY — stray stats recorded on a forfeited game never count,
/// and a player known only from such an event is not in the result at all
/// (nobody is inGoal: the keepers marker is ignored too — a forfeit scores
/// the appearance point or nothing).
/// The player set is then exactly the [attendance] keys, so CALLERS MUST
/// PASS THE FULL ROSTER-COMPOSED ATTENDANCE (every rostered player → true,
/// absentees → false: the finalizer's fullAttendance, the match tab's
/// composeAttendance) — with no attendance map a forfeit yields no players
/// and nobody gets the appearance point.
library;

import 'package:infinite_sports_flutter/misc/activity_entry.dart';
import 'package:infinite_sports_flutter/misc/forfeit.dart';

import 'player_game_stats.dart';

/// Game-node key of one side's stand-in keeper marker
/// (`team1keepers` / `team2keepers` = `{<player name>: true}`). Private on
/// purpose: the Manager twin's importers also see its UI-side
/// services/attendance.dart parseKeepers, so the engine adds no public name.
String _keepersKey(int side) => 'team${side}keepers';

/// The names marked in goal by a `team{1,2}keepers` node: keys whose value
/// is exactly `true`. A Map is read by key; a List (RTDB coercion of
/// numeric-name keys) by index; null padding, empty keys, any other value
/// and any other shape are ignored. TS twin: stats_mapper.ts
/// keeperMarkerNames.
Set<String> _keeperMarkerNames(Object? raw) {
  final out = <String>{};
  void add(String key, Object? value) {
    if (key.isNotEmpty && value == true) out.add(key);
  }

  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      add(i.toString(), raw[i]);
    }
  } else if (raw is Map) {
    raw.forEach((k, v) => add(k.toString(), v));
  }
  return out;
}

/// Per-player stats for [teamName]'s side of [gameNode]. The player set is
/// everyone who has an activity event PLUS everyone keyed in [attendance]
/// (so a present player with zero events still earns the appearance point,
/// and the attendance step can list the full roster) — on a FORFEITED game
/// only the [attendance] keys (see the library doc). Throws
/// [ArgumentError] when [teamName] is neither team1 nor team2.
Map<String, PlayerGameStats> mapGameToStats(
  Map gameNode, {
  required String teamName,
  Map<String, bool>? attendance,
}) {
  final Object? ownActivity;
  final int conceded;
  final int side;
  if (teamName == gameNode['team1']?.toString()) {
    ownActivity = gameNode['team1activity'];
    conceded = _score(gameNode['team2score'] ?? gameNode['team2Score']);
    side = 1;
  } else if (teamName == gameNode['team2']?.toString()) {
    ownActivity = gameNode['team2activity'];
    conceded = _score(gameNode['team1score'] ?? gameNode['team1Score']);
    side = 2;
  } else {
    throw ArgumentError.value(
        teamName, 'teamName', 'is neither team1 nor team2 of this game node');
  }

  final forfeitedBy = parseForfeitedBy(gameNode[kForfeitedByKey]);
  if (forfeitedBy != null) {
    final forfeit = forfeitedBy == side ? GameForfeit.lost : GameForfeit.won;
    return {
      for (final name in attendance?.keys ?? const <String>[])
        name: PlayerGameStats(
          teamConceded: conceded,
          present: attendance![name] ?? true,
          forfeit: forfeit,
        ),
    };
  }

  final tallies = <String, _Tally>{};
  _forEachLeaf(ownActivity, (leaf) {
    final event = activityEventOf(leaf);
    if (event == null) return;
    final player = event.value?.toString() ?? '';
    if (player.isEmpty) return;
    final t = tallies.putIfAbsent(player, _Tally.new);
    // Case-insensitive like single_match_tallies, with the legacy spaced
    // tournament spellings accepted alongside the canonical league ones.
    switch (event.key.toLowerCase().trim()) {
      case 'goal' || 'pengoal' || 'penalty goal':
        t.goals++;
      case 'assist':
        t.assists++;
      case 'save':
        t.saves++;
      case 'pensaved' || 'penalty saved':
        t.penSaved++;
        t.saves++; // league pairing: a penalty save is also a save
      case 'penmissed' || 'penalty missed':
        t.penMissed++;
      case 'owngoal' || 'own goal':
        t.ownGoals++;
      case 'dpl':
        t.dpl++;
      case 'yellow' || 'yellow card':
        t.yellows++;
      case 'secondyellow' || 'second yellow' || 'red' || 'red card':
        t.reds++;
      default:
        break; // Foul, Substitution, unknown/legacy: no fantasy counter
    }
  });

  final names = <String>{...tallies.keys, ...?attendance?.keys};
  final keepers = _keeperMarkerNames(gameNode[_keepersKey(side)]);
  return {
    for (final name in names)
      name: (tallies[name] ?? _Tally()).toStats(
        teamConceded: conceded,
        present: attendance?[name] ?? true, // spec §8 default: present
        // Stand-in keeper (spec §7): the Manager's "In goal" marker (a save
        // or penalty save also puts him in goal — see toStats).
        markedInGoal: keepers.contains(name),
      ),
  };
}

/// Walks every activity leaf, tolerating RTDB array coercion at BOTH levels
/// (activity → buckets, bucket → leaves) and null padding at either.
void _forEachLeaf(Object? activity, void Function(Map leaf) fn) {
  void eachBucket(Object? bucket) {
    if (bucket is List) {
      for (final leaf in bucket) {
        if (leaf is Map) fn(leaf);
      }
    } else if (bucket is Map) {
      for (final leaf in bucket.values) {
        if (leaf is Map) fn(leaf);
      }
    }
  }

  if (activity is List) {
    activity.forEach(eachBucket);
  } else if (activity is Map) {
    activity.values.forEach(eachBucket);
  }
}

int _score(Object? v) =>
    v is num ? v.toInt() : int.tryParse(v?.toString().trim() ?? '') ?? 0;

class _Tally {
  int goals = 0, assists = 0, saves = 0, penSaved = 0, penMissed = 0;
  int ownGoals = 0, yellows = 0, reds = 0, dpl = 0;

  PlayerGameStats toStats({
    required int teamConceded,
    required bool present,
    bool markedInGoal = false,
  }) =>
      PlayerGameStats(
        goals: goals, assists: assists, saves: saves, penSaved: penSaved,
        penMissed: penMissed, ownGoals: ownGoals, yellows: yellows,
        reds: reds, dpl: dpl, teamConceded: teamConceded, present: present,
        // Only a keeper makes saves (PenSaved bumps saves too).
        inGoal: saves > 0 || penSaved > 0 || markedInGoal,
      );
}
