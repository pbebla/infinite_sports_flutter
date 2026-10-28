// Thin live-stream layer over the Fantasy RTDB paths (P3a Task 1) — the
// fantasy mirror of LeagueService: onValue streams + pure mapping
// (fantasy_parsers.dart), no logic. Firebase-touching: no unit tests (repo
// convention — the logic lives pure in fantasy_parsers.dart).
//
// House rules: streams only (RTDB .get() banned); session snapshot caches
// seed first frames so a revisited hub paints instantly while the live
// snapshot loads behind it (same stale-while-refresh idea as
// LeagueService.watchRosters).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';

class FantasyService {
  static DatabaseReference _ref(String path) =>
      FirebaseDatabase.instance.ref(path);

  static String _root(String sport, String season) =>
      'Fantasy/$sport/$season';

  // ── Session snapshot caches (instant revisits) ────────────────────────
  static final Map<String, FantasyConfigState> _configCache = {};
  static final Map<String, List<FantasyPlayer>> _playersCache = {};
  static final Map<String, Map<String, FantasyPlayerTotals>> _totalsCache = {};
  static final Map<String, List<FantasyPriceChange>> _priceChangesCache = {};

  /// Clears the session caches (sign-out hygiene, tests).
  static void clearSessionCaches() {
    _configCache.clear();
    _playersCache.clear();
    _totalsCache.clear();
    _priceChangesCache.clear();
  }

  /// Live `Fantasy/<sport>/<season>/Config` → engine FantasyConfig + lock
  /// override. null = node absent (no fantasy this season) — this same
  /// stream gates the league page's Fantasy tab.
  static Stream<FantasyConfigState?> watchConfig(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _configCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Config').onValue) {
      final state = configStateFromNode(event.snapshot.value);
      if (state != null) {
        _configCache[key] = state;
      } else {
        _configCache.remove(key);
      }
      yield state;
    }
  }

  /// Live market players (guests included with eligible=false — the UI
  /// filters where the spec says they're invisible).
  static Stream<List<FantasyPlayer>> watchPlayers(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _playersCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Players').onValue) {
      final players = playersFromNode(event.snapshot.value);
      _playersCache[key] = players;
      yield players;
    }
  }

  /// Live finalized totals (`PlayerTotals`, P4 functions-written). null =
  /// node absent (no finalized gameweeks yet) — the market hides its points/
  /// ownership column and the Points sort on null (P3c Task 4).
  static Stream<Map<String, FantasyPlayerTotals>?> watchPlayerTotals(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _totalsCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/PlayerTotals').onValue) {
      final totals = playerTotalsFromNode(event.snapshot.value);
      if (totals != null) {
        _totalsCache[key] = totals;
      } else {
        _totalsCache.remove(key);
      }
      yield totals;
    }
  }

  /// Live latest-gameweek price moves (`PriceChanges/<gw>`, P4 repricing
  /// job). Empty until the first Monday repricing runs — the risers &
  /// fallers strip hides entirely on empty (P3c Task 5).
  static Stream<List<FantasyPriceChange>> watchPriceChanges(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _priceChangesCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/PriceChanges').onValue) {
      final changes = latestPriceChangesFromNode(event.snapshot.value);
      _priceChangesCache[key] = changes;
      yield changes;
    }
  }

  /// Live own squad (`Squads/<uid>`). null until first save. Re-renders on
  /// every save, including this device's own (self-echo safe by design: the
  /// stream is the single source of truth after a write).
  static Stream<FantasySquad?> watchMySquad(
      String sport, String season, String uid) {
    return _ref('${_root(sport, season)}/Squads/$uid')
        .onValue
        .map((event) => squadFromNode(event.snapshot.value));
  }

  /// Saves the whole squad node (engine FantasySquad.toMap — the exact shape
  /// squadFromNode re-reads).
  static Future<void> saveMySquad(
          String sport, String season, String uid, FantasySquad squad) =>
      _ref('${_root(sport, season)}/Squads/$uid').set(squad.toMap());

  /// [watchMySquad] for the signed-in user; a signed-out session streams a
  /// single null (same convention as [watchMyManager]).
  static Stream<FantasySquad?> watchMySquadAuto(String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<FantasySquad?>.value(null);
    return watchMySquad(sport, season, uid);
  }

  /// [saveMySquad] for the signed-in user (the squad builder's save path).
  static Future<void> saveMySquadAuto(
      String sport, String season, FantasySquad squad) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.error(StateError('Not signed in'));
    return saveMySquad(sport, season, uid, squad);
  }

  /// Live `Managers/<uid>` entry (spec §10b): team name + moderation flag.
  /// null until the manager names their team.
  static Stream<FantasyManager?> watchManager(
      String sport, String season, String uid) {
    return _ref('${_root(sport, season)}/Managers/$uid')
        .onValue
        .map((event) => managerFromNode(event.snapshot.value));
  }

  /// [watchManager] for the signed-in user; a signed-out session streams a
  /// single null (the hub then shows the name prompt's signed-out face).
  static Stream<FantasyManager?> watchMyManager(String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<FantasyManager?>.value(null);
    return watchManager(sport, season, uid);
  }

  /// Saves the signed-in manager's team name. ONE set of the whole node with
  /// `NameFlagged: false` — the live rules only accept a write on a flagged
  /// entry when it changes TeamName AND clears the flag in the same write,
  /// so rename-is-unlock is enforced server-side and this single shape
  /// covers first naming, plain renames and flag-clearing renames alike.
  static Future<void> saveTeamName(
      String sport, String season, String name) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError('Not signed in'));
    }
    return _ref('${_root(sport, season)}/Managers/$uid')
        .set({'TeamName': name.trim(), 'NameFlagged': false});
  }

  /// Live gameweeks derived from the REAL season schedule (one per match
  /// day, spec §5): streams `/<sport>/<season>/Date` keys through the
  /// engine's deriveGameweeks with [config]'s lock hour. Callers resubscribe
  /// when the config changes (the hub does — lockHour moves every deadline).
  static Stream<List<Gameweek>> watchGameweeks(
      String sport, String season, FantasyConfig config) {
    return _ref('/$sport/$season/Date').onValue.map((event) =>
        deriveGameweeks(dateKeysFromNode(event.snapshot.value), config));
  }
}
