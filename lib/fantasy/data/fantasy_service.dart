// Thin live-stream layer over the Fantasy RTDB paths (P3a Task 1) — the
// fantasy mirror of LeagueService: onValue streams + pure mapping
// (fantasy_parsers.dart), no logic. Firebase-touching: no unit tests (repo
// convention — the logic lives pure in fantasy_parsers.dart).
//
// House rules: streams only (RTDB .get() banned); session snapshot caches
// seed first frames so a revisited hub paints instantly while the live
// snapshot loads behind it (same stale-while-refresh idea as
// LeagueService.watchRosters).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
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
  static final Map<String, FantasyLeaderboards> _leaderboardsCache = {};
  static final Map<String, Map<String, FantasyManager>> _managersCache = {};
  static final Map<String, List<FantasyMiniLeague>> _miniLeaguesCache = {};
  static final Map<String, List<FantasyNewsPost>> _newsCache = {};
  static final Map<String, Map<int, FantasyDreamTeam>> _dreamTeamsCache = {};
  // Round 3 (player profiles): keyed `<root>` (season-wide) or
  // `<root>|<name|uid>` (per player / per user).
  static final Map<String, Map<int, Map<String, int>>> _priceHistoryCache = {};
  static final Map<String, Map<int, Map<String, int>>> _allPriceChangesCache =
      {};
  static final Map<String, Map<int, PlayerWeekStats>> _playerWeekStatsCache =
      {};
  static final Map<String, Set<String>> _watchlistCache = {};
  // The league's own season-over flag, keyed `<sport>/<season>`.
  static final Map<String, bool> _seasonFinishedCache = {};

  /// Clears the session caches (sign-out hygiene, tests).
  static void clearSessionCaches() {
    _configCache.clear();
    _playersCache.clear();
    _totalsCache.clear();
    _priceChangesCache.clear();
    _leaderboardsCache.clear();
    _managersCache.clear();
    _miniLeaguesCache.clear();
    _newsCache.clear();
    _dreamTeamsCache.clear();
    _priceHistoryCache.clear();
    _allPriceChangesCache.clear();
    _playerWeekStatsCache.clear();
    _watchlistCache.clear();
    _seasonFinishedCache.clear();
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

  /// Live price moves of EVERY gameweek (`PriceChanges/<gw>/<name>` = delta
  /// tenths, round 3): the profile's Price tab ("the move after each week")
  /// and the market's Risers/Fallers "View all". The `Manual`/`Voided` flag
  /// keys are ignored; empty until the first Monday repricing runs.
  /// [watchPriceChanges] stays the latest-week-only strip feed.
  static Stream<Map<int, Map<String, int>>> watchAllPriceChanges(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _allPriceChangesCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/PriceChanges').onValue) {
      final moves = allPriceChangesFromNode(event.snapshot.value);
      _allPriceChangesCache[key] = moves;
      yield moves;
    }
  }

  /// Live price history (`PriceHistory/<gw>/<name>` = tenths the player had
  /// DURING that gameweek, snapshotted at lock — round 3, spec §3.2). Empty
  /// until the first lock after the functions deploy (no backfill).
  static Stream<Map<int, Map<String, int>>> watchPriceHistory(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _priceHistoryCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/PriceHistory').onValue) {
      final history = priceHistoryFromNode(event.snapshot.value);
      _priceHistoryCache[key] = history;
      yield history;
    }
  }

  /// One player's weekly records (`PlayerWeekStats/<gw>/<name>`, round 3,
  /// spec §3.1): one onValue listener per gameweek in [weeks] on that small
  /// entry (public read) — never the season's whole record for every player
  /// (same multi-listener shape as [watchChipHistoryFor]). Emits only once
  /// EVERY week has answered (no piecemeal pops), then on every change;
  /// weeks without a record are simply absent from the map. Seeded from the
  /// session cache so a revisited profile paints instantly. Callers
  /// resubscribe when the finalized-week list changes.
  static Stream<Map<int, PlayerWeekStats>> watchPlayerWeekStatsFor(
      String sport, String season, String name, List<int> weeks) {
    final wanted = weeks.toSet();
    if (wanted.isEmpty) {
      return Stream<Map<int, PlayerWeekStats>>.value(const {});
    }
    final root = _root(sport, season);
    final cacheKey = '$root|$name';
    final subs = <StreamSubscription<DatabaseEvent>>[];
    final latest = <int, PlayerWeekStats?>{};
    late final StreamController<Map<int, PlayerWeekStats>> controller;
    controller = StreamController<Map<int, PlayerWeekStats>>(
      onListen: () {
        final seed = _playerWeekStatsCache[cacheKey];
        if (seed != null) {
          controller.add({
            for (final e in seed.entries)
              if (wanted.contains(e.key)) e.key: e.value,
          });
        }
        for (final w in wanted) {
          subs.add(_ref('$root/PlayerWeekStats/$w/$name')
              .onValue
              .listen((event) {
            latest[w] = playerWeekStatsFromNode(event.snapshot.value);
            if (latest.length < wanted.length) return; // not all answered yet
            final map = {
              for (final e in latest.entries)
                if (e.value != null) e.key: e.value!,
            };
            _playerWeekStatsCache[cacheKey] = map;
            controller.add(map);
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// Live "season over" flag: the LEAGUE's own `/<sport>/<season>/Finished`
  /// (not under `Fantasy/`; public read like the rest of the league tree).
  /// Only an exact `true` is finished — absent / false → false. After the
  /// season is over the price arrows and the Risers / Fallers card go away
  /// (follow-up C). Seeded from the session cache so a revisit is instant;
  /// cleared with the others by [clearSessionCaches].
  static Stream<bool> watchLeagueSeasonFinished(
      String sport, String season) async* {
    final key = '$sport/$season';
    final seed = _seasonFinishedCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('/$sport/$season/Finished').onValue) {
      final finished = seasonFinishedFromNode(event.snapshot.value);
      _seasonFinishedCache[key] = finished;
      yield finished;
    }
  }

  /// Live own watchlist (`Watchlists/<uid>/<name>` = true, round 3): the
  /// starred player names. Rules: read/write own uid only. Seeded from the
  /// session cache (cleared with the others on sign-out).
  static Stream<Set<String>> watchWatchlist(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    final seed = _watchlistCache[key];
    if (seed != null) yield seed;
    await for (final event
        in _ref('${_root(sport, season)}/Watchlists/$uid').onValue) {
      final names = watchlistFromNode(event.snapshot.value);
      _watchlistCache[key] = names;
      yield names;
    }
  }

  /// Stars ([on] true → `true`) or un-stars (false → the node is removed)
  /// [name] on [uid]'s watchlist. The stream is the single source of truth
  /// after the write (the local echo re-emits at once).
  static Future<void> setWatchlisted(
      String sport, String season, String uid, String name, bool on) {
    // An empty name would address the `Watchlists/<uid>` node itself.
    if (name.trim().isEmpty) {
      return Future.error(
          ArgumentError.value(name, 'name', 'must not be empty'));
    }
    final ref = _ref('${_root(sport, season)}/Watchlists/$uid/$name');
    return on ? ref.set(true) : ref.remove();
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

  /// Live own squad alert (`SquadAlerts/<uid>`, spec §3 holder protection,
  /// functions-written): non-null while a player's position change has
  /// left this manager's formation illegal. Rules: read own uid only.
  static Stream<FantasySquadAlert?> watchMySquadAlert(
      String sport, String season, String uid) {
    return _ref('${_root(sport, season)}/SquadAlerts/$uid')
        .onValue
        .map((event) => squadAlertFromNode(event.snapshot.value));
  }

  /// [watchMySquadAlert] for the signed-in user; a signed-out session
  /// streams a single null (same convention as [watchMySquadAuto]).
  static Stream<FantasySquadAlert?> watchMySquadAlertAuto(
      String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<FantasySquadAlert?>.value(null);
    return watchMySquadAlert(sport, season, uid);
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

  // ── Leaderboards, transparency, mini-leagues, news (P3d) ──────────────

  /// Live `Leaderboards` node (P4 functions-written; shape pinned in
  /// fantasy_parsers.dart). Empty = absent (no finalized gameweek yet) —
  /// the tab shows its friendly empty state.
  static Stream<FantasyLeaderboards> watchLeaderboards(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _leaderboardsCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Leaderboards').onValue) {
      final boards = leaderboardsFromNode(event.snapshot.value);
      _leaderboardsCache[key] = boards;
      yield boards;
    }
  }

  /// Live `Managers` node, whole (public read): {uid: team name + flag} —
  /// the leaderboard rows' name source (spec §10b).
  static Stream<Map<String, FantasyManager>> watchManagers(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _managersCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Managers').onValue) {
      final managers = managersFromNode(event.snapshot.value);
      _managersCache[key] = managers;
      yield managers;
    }
  }

  /// Live `MiniLeagues` node, whole (public read by design — codes only gate
  /// joining a social list). The My Leagues scope filters to membership and
  /// the join flow matches codes client-side on this same stream.
  static Stream<List<FantasyMiniLeague>> watchMiniLeagues(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _miniLeaguesCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/MiniLeagues').onValue) {
      final leagues = miniLeaguesFromNode(event.snapshot.value);
      _miniLeaguesCache[key] = leagues;
      yield leagues;
    }
  }

  /// Live published news feed (`News/Published`, owner-published in P4/P5),
  /// newest first.
  static Stream<List<FantasyNewsPost>> watchNews(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _newsCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/News/Published').onValue) {
      final posts = newsPostsFromNode(event.snapshot.value);
      _newsCache[key] = posts;
      yield posts;
    }
  }

  /// One manager's lock-published picks by week (`PublishedPicks/<gw>/<uid>`,
  /// spec §9: visible to others only AFTER lock — the functions only write
  /// here at lock, so everything readable is fair game).
  static Stream<Map<int, FantasySquad>> watchPublishedPicksFor(
      String sport, String season, String uid) {
    return _ref('${_root(sport, season)}/PublishedPicks').onValue.map(
        (event) => squadsByWeekForUid(event.snapshot.value, uid));
  }

  /// One manager's finalized week-by-week history (`History/<gw>/<uid>`,
  /// spec §9: browsable forever).
  static Stream<Map<int, FantasySquad>> watchHistoryFor(
      String sport, String season, String uid) {
    return _ref('${_root(sport, season)}/History').onValue.map(
        (event) => squadsByWeekForUid(event.snapshot.value, uid));
  }

  /// One manager's finalized chips by gameweek for the chip row's real
  /// counts (chip_usage.dart): one onValue listener per gameweek on the
  /// small `History/<gw>/<uid>` entry (public read) — never the whole
  /// season's History of every manager. Emits only once EVERY week has
  /// answered (no piecemeal "1 left" → "Used" pops), then on every change.
  /// Weeks without an entry are simply absent from the map. Callers
  /// resubscribe when the schedule's gameweek list changes.
  static Stream<Map<int, ChipHistoryEntry>> watchChipHistoryFor(
      String sport, String season, String uid, List<int> weeks) {
    if (weeks.isEmpty) {
      return Stream<Map<int, ChipHistoryEntry>>.value(const {});
    }
    final subs = <StreamSubscription<DatabaseEvent>>[];
    final latest = <int, ChipHistoryEntry?>{};
    late final StreamController<Map<int, ChipHistoryEntry>> controller;
    controller = StreamController<Map<int, ChipHistoryEntry>>(
      onListen: () {
        for (final w in weeks) {
          subs.add(_ref('${_root(sport, season)}/History/$w/$uid')
              .onValue
              .listen((event) {
            latest[w] = chipHistoryEntryFromNode(event.snapshot.value);
            if (latest.length < weeks.length) return; // not all answered yet
            controller.add({
              for (final e in latest.entries)
                if (e.value != null) e.key: e.value!,
            });
          }, onError: controller.addError));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// [watchChipHistoryFor] for the signed-in user; a signed-out session
  /// streams a single empty map (nothing spent).
  static Stream<Map<int, ChipHistoryEntry>> watchMyChipHistoryAuto(
      String sport, String season, List<int> weeks) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<Map<int, ChipHistoryEntry>>.value(const {});
    }
    return watchChipHistoryFor(sport, season, uid, weeks);
  }

  /// Creates a mini-league under a fresh push id: the signed-in user as
  /// Owner AND first member in one write (the shape the rules validate).
  /// Returns the new league id.
  static Future<String> createMiniLeague(
      String sport, String season,
      {required String name, required String code}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    final ref = _ref('${_root(sport, season)}/MiniLeagues').push();
    await ref.set({
      'Name': name.trim(),
      'Code': code,
      'Owner': uid,
      'CreatedAt': ServerValue.timestamp,
      'Members': {uid: true},
    });
    return ref.key!;
  }

  /// Joins a mini-league: writes ONLY the member's own
  /// `Members/<uid>: true` (the rules' member-writes-own path).
  static Future<void> joinMiniLeague(
      String sport, String season, String leagueId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.error(StateError('Not signed in'));
    return _ref('${_root(sport, season)}/MiniLeagues/$leagueId/Members/$uid')
        .set(true);
  }

  /// Live `DreamTeam` node, whole (P6, spec §10/§13): {gameweek: Team of the
  /// Week}, functions-written at finalize and admin-overridable. Empty =
  /// node absent (no finalized gameweek yet) — the hub hides the card.
  static Stream<Map<int, FantasyDreamTeam>> watchDreamTeams(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _dreamTeamsCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/DreamTeam').onValue) {
      final teams = dreamTeamsFromNode(event.snapshot.value);
      _dreamTeamsCache[key] = teams;
      yield teams;
    }
  }

  /// Live RAW game node (P6 match-page Fantasy tab): the undecoded
  /// `/<sport>/<season>/Date/<dateKey>/<gameIndex>` value the stats mapper
  /// replays (activities + attendance + scores). null while absent. The
  /// match page already holds an adapted watchGame listener on this same
  /// path — the SDK dedupes listeners per path, so this costs no extra
  /// server subscription.
  static Stream<Object?> watchGameNode(
      String sport, String season, String dateKey, int gameIndex) {
    return _ref('/$sport/$season/Date/$dateKey/$gameIndex')
        .onValue
        .map((event) => event.snapshot.value);
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
