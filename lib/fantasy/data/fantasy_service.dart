// Thin live-stream layer over the Fantasy RTDB paths (P3a Task 1) — the
// fantasy mirror of LeagueService: onValue streams + pure mapping
// (fantasy_parsers.dart), no logic. Firebase-touching: no unit tests (repo
// convention — the logic lives pure in fantasy_parsers.dart).
//
// House rules: streams only (RTDB .get() banned); session snapshot caches
// seed first frames so a revisited hub paints instantly while the live
// snapshot loads behind it (same stale-while-refresh idea as
// LeagueService.watchRosters).
//
// THE LIVE OVERLAY (live everywhere, fantasy_live.dart): the leaderboards,
// player totals, dream teams and a player's weekly records join their
// official stream with the live gameweek (FantasyLiveFeed) while one is being
// played — the pure `mergeLive…` overlays decide, these wrappers only join
// (joinWithLive: one emission once live answers, official alone after 2 s).
// The session caches below keep the OFFICIAL values (never the overlay), so a
// cached seed can never present a stale live number as official.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_access.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_live.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/per_week_stream.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/selling.dart';
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
  // The hub's own-user feeds (Opus audit item 3 — the hub's reveal gate
  // waits on every one of them, so each seeds a revisit), keyed
  // `<root>|<uid>`. A known-ABSENT node is cached too (null value, present
  // key): "no alert" / "no squad yet" paints at once on a revisit.
  static final Map<String, Map<int, ChipHistoryEntry>> _chipHistoryCache = {};
  static final Map<String, FantasySquadAlert?> _squadAlertCache = {};
  static final Map<String, FantasySquad?> _mySquadCache = {};
  static final Map<String, FantasyManager?> _managerByUidCache = {};
  // Paid access (spec 2026-11-01 §6): the own `Access/<uid>` record, keyed
  // `<root>|<uid>` — it joins the hub's reveal gate, so a revisit must not
  // wait on the network for it. A known-absent record caches as none.
  static final Map<String, FantasyAccessState> _accessCache = {};
  // FPL selling (spec §4): the own `Baselines/<uid>` state, keyed
  // `<root>|<uid>` — the squad draft's money. A known-absent node (a first
  // squad) caches as loaded-with-no-baseline.
  static final Map<String, SaleBaselineState> _saleBaselineCache = {};
  // Transfers (plan 2026-11-03): the own `TransferState/<uid>` view, keyed
  // `<root>|<uid>` — the draft's transfers line, so a revisit must not
  // flash "Transfer count updating…". A known-ABSENT node (a first team)
  // caches as null (present key); a failed read caches nothing.
  static final Map<String, TransferStateView?> _transferStateCache = {};
  // The season's owner-voided gameweeks (`Voided`), keyed `<root>`.
  static final Map<String, Set<int>> _voidedWeeksCache = {};
  // The league's own season-over flag, keyed `<sport>/<season>`.
  static final Map<String, bool> _seasonFinishedCache = {};
  // Achievement badges: the GLOBAL catalog, a season's whole Badges node
  // (keyed `<root>`) and one manager's awards (keyed `<root>|<uid>`).
  static FantasyBadgeCatalog? _badgeCatalogCache;
  static final Map<String, Map<String, List<FantasyBadgeAward>>> _badgesCache =
      {};
  static final Map<String, List<FantasyBadgeAward>> _badgesForCache = {};
  // Live everywhere: one manager's `Live/Squads/<uid>` (keyed `<root>|<uid>`);
  // a known-ABSENT node (no live week / not scored) caches as null. The
  // season-wide live state is FantasyLiveFeed's own session cache.
  static final Map<String, LiveSquad?> _liveSquadCache = {};
  // The locked My Team's settled week: one manager's `History/<gw>/<uid>`
  // (keyed `<root>|<uid>|<gw>`) and his `Leaderboards/Overall/<uid>` row
  // (keyed `<root>|<uid>`); a known-ABSENT node caches as null.
  static final Map<String, HistoryWeek?> _historyWeekCache = {};
  // The squad that was LOCKED: one manager's `PublishedPicks/<gw>/<uid>`
  // (keyed `<root>|<uid>|<gw>`).
  static final Map<String, FantasySquad?> _publishedPicksWeekCache = {};
  static final Map<String, OverallStanding?> _overallStandingCache = {};

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
    _chipHistoryCache.clear();
    _squadAlertCache.clear();
    _mySquadCache.clear();
    _managerByUidCache.clear();
    _accessCache.clear();
    _saleBaselineCache.clear();
    _transferStateCache.clear();
    _voidedWeeksCache.clear();
    _seasonFinishedCache.clear();
    _badgeCatalogCache = null;
    _badgesCache.clear();
    _badgesForCache.clear();
    _liveSquadCache.clear();
    _historyWeekCache.clear();
    _publishedPicksWeekCache.clear();
    _overallStandingCache.clear();
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

  /// Live season totals (`PlayerTotals`, P4 functions-written) with the live
  /// gameweek overlaid while one is being played ([mergeLivePlayerTotals]:
  /// rows with `live: true`). null = no official node (no finalized
  /// gameweeks yet) and no live week — the market hides its points/ownership
  /// column and the Points sort on null (P3c Task 4).
  static Stream<Map<String, FantasyPlayerTotals>?> watchPlayerTotals(
          String sport, String season) =>
      joinWithLive<Map<String, FantasyPlayerTotals>?,
          Map<String, FantasyPlayerTotals>?>(
        _watchOfficialPlayerTotals(sport, season),
        FantasyLiveFeed.watch(sport, season),
        mergeLivePlayerTotals,
      );

  static Stream<Map<String, FantasyPlayerTotals>?> _watchOfficialPlayerTotals(
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
  /// (the shared [perWeekStream], like [watchChipHistoryFor]). Emits only
  /// once EVERY week has answered (no piecemeal pops), then on every change;
  /// weeks without a record are simply absent from the map. Seeded from the
  /// session cache (`<root>|<name>`) so a revisited profile paints
  /// instantly. Callers (FantasyScheduleFeed) pass only weeks up to the
  /// current gameweek and resubscribe when that list changes.
  ///
  /// While a gameweek is live, that week's record (when it is among [weeks])
  /// is the live one ([mergeLivePlayerWeekStats]: `live: true`, provisional
  /// bonus flagged) — even though no official record exists yet.
  static Stream<Map<int, PlayerWeekStats>> watchPlayerWeekStatsFor(
      String sport, String season, String name, List<int> weeks) {
    final official =
        _watchOfficialPlayerWeekStatsFor(sport, season, name, weeks);
    // No weeks, nothing to overlay: no live listeners either.
    if (weeks.isEmpty) return official;
    return joinWithLive<Map<int, PlayerWeekStats>, Map<int, PlayerWeekStats>>(
      official,
      FantasyLiveFeed.watch(sport, season),
      (stats, live) =>
          mergeLivePlayerWeekStats(stats, live, name: name, weeks: weeks),
    );
  }

  static Stream<Map<int, PlayerWeekStats>> _watchOfficialPlayerWeekStatsFor(
      String sport, String season, String name, List<int> weeks) {
    final root = _root(sport, season);
    return perWeekStream<PlayerWeekStats>(
      weeks: weeks,
      cache: _playerWeekStatsCache,
      cacheKey: '$root|$name',
      watchWeek: (w) => _ref('$root/PlayerWeekStats/$w/$name')
          .onValue
          .map((event) => event.snapshot.value),
      parse: playerWeekStatsFromNode,
    );
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

  // ── Achievement badges (spec 2026-10-30 §3/§5) ─────────────────────────

  /// Live GLOBAL badge catalog (`Fantasy/BadgeCatalog`, public read): the
  /// stored entries over the starter set (fantasy_badges.dart) — an absent
  /// node still emits (the starter set). Seeded from the session cache.
  static Stream<FantasyBadgeCatalog> watchBadgeCatalog() async* {
    final seed = _badgeCatalogCache;
    if (seed != null) yield seed;
    await for (final event in _ref('Fantasy/BadgeCatalog').onValue) {
      final catalog = badgeCatalogFromNode(event.snapshot.value);
      _badgeCatalogCache = catalog;
      yield catalog;
    }
  }

  /// Live season `Badges` node, whole (public read): uid → awards — the
  /// leaderboard's badge counts. Absent = an empty map (still emits).
  static Stream<Map<String, List<FantasyBadgeAward>>> watchBadges(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _badgesCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Badges').onValue) {
      final byUid = badgesByUidFromNode(event.snapshot.value);
      _badgesCache[key] = byUid;
      yield byUid;
    }
  }

  /// Live `Badges/<uid>` — one manager's awards, oldest first (the badge
  /// shelf). Absent = an empty list (still emits).
  static Stream<List<FantasyBadgeAward>> watchBadgesFor(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    final seed = _badgesForCache[key];
    if (seed != null) yield seed;
    await for (final event
        in _ref('${_root(sport, season)}/Badges/$uid').onValue) {
      final awards = badgeAwardsFromNode(event.snapshot.value);
      _badgesForCache[key] = awards;
      yield awards;
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
  /// stream is the single source of truth after a write). Seeded from the
  /// session cache (`<root>|<uid>`, absent cached as null) so the hub's
  /// reveal gate opens at once on a revisit.
  static Stream<FantasySquad?> watchMySquad(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_mySquadCache.containsKey(key)) yield _mySquadCache[key];
    await for (final event
        in _ref('${_root(sport, season)}/Squads/$uid').onValue) {
      final squad = squadFromNode(event.snapshot.value);
      _mySquadCache[key] = squad;
      yield squad;
    }
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

  /// Live own sale baseline (`Baselines/<uid>`, functions-written at each
  /// lock: `{ForGw, RealizedTenths, Prices}` — last week's locked purchase
  /// prices and the running sale profit/loss; rules: read own uid only).
  /// Absent = a first squad (`baseline: null, loaded: true`). Seeded from
  /// the session cache (`<root>|<uid>`). Error ≠ fact: a failed read keeps
  /// the last known state; with none known it emits `degraded` and the
  /// draft never claims a budget. A signed-out session streams a single
  /// "no baseline" (nothing to sell).
  static Stream<SaleBaselineState> watchMySaleBaseline(
      String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<SaleBaselineState>.value(
          const SaleBaselineState(loaded: true));
    }
    return watchSaleBaseline(sport, season, uid);
  }

  /// [watchMySaleBaseline] for an explicit uid.
  static Stream<SaleBaselineState> watchSaleBaseline(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    final seed = _saleBaselineCache[key];
    if (seed != null) yield seed;
    try {
      await for (final event
          in _ref('${_root(sport, season)}/Baselines/$uid').onValue) {
        final state = saleBaselineStateFromNode(event.snapshot.value);
        if (state.degraded) {
          debugPrint('FantasyService: unreadable Baselines/$uid node');
        }
        _saleBaselineCache[key] = state;
        yield state;
      }
    } catch (e) {
      debugPrint('FantasyService: sale baseline feed failed: $e');
      yield _saleBaselineCache[key] ?? const SaleBaselineState(degraded: true);
    }
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
  /// Seeded from the session cache (`<root>|<uid>`, "no alert" cached as
  /// null) — it joins the hub's reveal gate, so a revisit must not wait on
  /// the network for it.
  static Stream<FantasySquadAlert?> watchMySquadAlert(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_squadAlertCache.containsKey(key)) yield _squadAlertCache[key];
    await for (final event
        in _ref('${_root(sport, season)}/SquadAlerts/$uid').onValue) {
      final alert = squadAlertFromNode(event.snapshot.value);
      _squadAlertCache[key] = alert;
      yield alert;
    }
  }

  /// [watchMySquadAlert] for the signed-in user; a signed-out session
  /// streams a single null (same convention as [watchMySquadAuto]).
  static Stream<FantasySquadAlert?> watchMySquadAlertAuto(
      String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<FantasySquadAlert?>.value(null);
    return watchMySquadAlert(sport, season, uid);
  }

  /// Live own transfer state (`TransferState/<uid>`, spec §5, functions-
  /// written: `{Free, UsedThisGw, FreeSwaps?, CountFrom?, CountFromGw?, …}`;
  /// rules: read own uid only). Emits the parsed view, or null while the
  /// node is ABSENT (a first team). Seeded from the session cache
  /// (`<root>|<uid>`, absent cached as null).
  ///
  /// Error ≠ fact: a failed read ERRORS the stream — it never emits null,
  /// because a failed read is not a first team. The consumer treats an
  /// error (and the time before the first emission) as "not answered" —
  /// `transferPreview(answered: false)` then says "Transfer count
  /// updating…" instead of hiding a real cost. Live `onValue` only, never
  /// a one-shot get (iOS parity).
  static Stream<TransferStateView?> watchMyTransferState(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_transferStateCache.containsKey(key)) yield _transferStateCache[key];
    try {
      await for (final event
          in _ref('${_root(sport, season)}/TransferState/$uid').onValue) {
        final view = parseTransferState(event.snapshot.value);
        _transferStateCache[key] = view;
        yield view;
      }
    } catch (e) {
      debugPrint('FantasyService: transfer state feed failed: $e');
      rethrow;
    }
  }

  /// [watchMyTransferState] for the signed-in user; a signed-out session
  /// streams a single null (same convention as [watchMySquadAlertAuto] — a
  /// signed-out user has no team to count).
  static Stream<TransferStateView?> watchMyTransferStateAuto(
      String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream<TransferStateView?>.value(null);
    return watchMyTransferState(sport, season, uid);
  }

  /// Live `Managers/<uid>` entry (spec §10b): team name + moderation flag.
  /// null until the manager names their team. Seeded from the session cache
  /// (`<root>|<uid>`, unnamed cached as null) for the hub's reveal gate.
  static Stream<FantasyManager?> watchManager(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_managerByUidCache.containsKey(key)) yield _managerByUidCache[key];
    await for (final event
        in _ref('${_root(sport, season)}/Managers/$uid').onValue) {
      final manager = managerFromNode(event.snapshot.value);
      _managerByUidCache[key] = manager;
      yield manager;
    }
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

  // ── Paid access (season pass, spec 2026-11-01 §4/§6) ───────────────────

  /// Live own `Access/<uid>` record (rules: read own uid or admin). Emits a
  /// [FantasyAccessState]: none / pending / active / revoked. Seeded from
  /// the session cache (`<root>|<uid>`) so the hub's reveal gate opens at
  /// once on a revisit. Error ≠ fact: a failed read keeps the last known
  /// value; with none known it emits none WITH `degraded` so the card shows
  /// a retry line rather than the pay methods as if unpaid. A signed-out
  /// session streams a single none (the auth wall keeps that theoretical).
  static Stream<FantasyAccessState> watchMyAccess(
      String sport, String season) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Stream<FantasyAccessState>.value(FantasyAccessState.none);
    }
    return watchAccess(sport, season, uid);
  }

  /// [watchMyAccess] for an explicit uid.
  static Stream<FantasyAccessState> watchAccess(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    final seed = _accessCache[key];
    if (seed != null) yield seed;
    try {
      await for (final event
          in _ref('${_root(sport, season)}/Access/$uid').onValue) {
        final state = accessStateFromNode(event.snapshot.value);
        _accessCache[key] = state;
        yield state;
      }
    } catch (e) {
      debugPrint('FantasyService: access feed failed: $e');
      yield _accessCache[key] ?? const FantasyAccessState(degraded: true);
    }
  }

  /// "I sent it": one push under `AccessClaims/<uid>` with the shape the
  /// rules validate (create-only by the owner uid; `At` is the server
  /// clock). The server's claim trigger flips `Access/<uid>` to pending —
  /// the live stream above shows it; nothing here polls.
  static Future<void> submitAccessClaim(
    String sport,
    String season, {
    required FantasyAccessMethod method,
    required double amountDollars,
    required String note,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.error(StateError('Not signed in'));
    return _ref('${_root(sport, season)}/AccessClaims/$uid').push().set(
        accessClaimPayload(
            method: method,
            amountDollars: amountDollars,
            note: note,
            at: ServerValue.timestamp));
  }

  /// "Pay by card": asks the server for a Stripe Checkout link
  /// (`createFantasyCheckoutSession`, the amount is the SERVER's). null =
  /// already active (the card dismisses on its own). Throws on failure —
  /// the card shows a friendly line + retry.
  static Future<Uri?> createCheckoutUrl(String sport, String season) async {
    final callable = FirebaseFunctions.instance
        .httpsCallable('createFantasyCheckoutSession');
    final result = await callable
        .call<Object?>({'sport': sport, 'season': season});
    return checkoutUrlFromResult(result.data);
  }

  // ── Leaderboards, transparency, mini-leagues, news (P3d) ──────────────

  /// Live `Leaderboards` node (P4 functions-written; shape pinned in
  /// fantasy_parsers.dart) with the live gameweek overlaid while one is being
  /// played ([mergeLiveLeaderboards]: Overall, that week's rows and the rank
  /// history's last point are the live ones, flagged `live`). Empty = absent
  /// (no finalized gameweek yet, no live week) — the tab shows its friendly
  /// empty state.
  static Stream<FantasyLeaderboards> watchLeaderboards(
          String sport, String season) =>
      joinWithLive<FantasyLeaderboards, FantasyLeaderboards>(
        _watchOfficialLeaderboards(sport, season),
        FantasyLiveFeed.watch(sport, season),
        mergeLiveLeaderboards,
      );

  static Stream<FantasyLeaderboards> _watchOfficialLeaderboards(
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
  /// season's History of every manager (the shared [perWeekStream]). Emits
  /// only once EVERY week has answered (no piecemeal "1 left" → "Used"
  /// pops), then on every change; weeks without an entry are simply absent.
  /// Seeded from the session cache (`<root>|<uid>`) so the hub's reveal gate
  /// opens at once on a revisit. Callers (FantasyScheduleFeed) pass only
  /// weeks up to the current gameweek — a future week can't have History —
  /// and resubscribe when that list changes.
  static Stream<Map<int, ChipHistoryEntry>> watchChipHistoryFor(
      String sport, String season, String uid, List<int> weeks) {
    final root = _root(sport, season);
    return perWeekStream<ChipHistoryEntry>(
      weeks: weeks,
      cache: _chipHistoryCache,
      cacheKey: '$root|$uid',
      watchWeek: (w) => _ref('$root/History/$w/$uid')
          .onValue
          .map((event) => event.snapshot.value),
      parse: chipHistoryEntryFromNode,
    );
  }

  /// Live owner-voided gameweeks (`Voided/<gw> = true`, public read, spec
  /// §15) — the node the server's chip refund reads (transfer_state.ts
  /// priorChipsOfUid), so the chip row refunds a voided week's chip at once
  /// instead of waiting for the re-finalize to mirror it into History (Opus
  /// audit item 4). Absent = empty (still emits). Seeded from the session
  /// cache (`<root>`) — it joins the hub's reveal gate.
  static Stream<Set<int>> watchVoidedWeeks(
      String sport, String season) async* {
    final key = _root(sport, season);
    final seed = _voidedWeeksCache[key];
    if (seed != null) yield seed;
    await for (final event in _ref('$key/Voided').onValue) {
      final weeks = voidedWeeksFromNode(event.snapshot.value);
      _voidedWeeksCache[key] = weeks;
      yield weeks;
    }
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
  /// Week}, functions-written at finalize and admin-overridable — with the
  /// live gameweek's Team of the Week so far overlaid while one is being
  /// played ([mergeLiveDreamTeams], `live: true`). Empty = node absent (no
  /// finalized gameweek yet, no live team) — the hub hides the card.
  static Stream<Map<int, FantasyDreamTeam>> watchDreamTeams(
          String sport, String season) =>
      joinWithLive<Map<int, FantasyDreamTeam>, Map<int, FantasyDreamTeam>>(
        _watchOfficialDreamTeams(sport, season),
        FantasyLiveFeed.watch(sport, season),
        mergeLiveDreamTeams,
      );

  static Stream<Map<int, FantasyDreamTeam>> _watchOfficialDreamTeams(
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

  /// One manager's live squad points (`Live/Squads/<uid>`): the net tenths,
  /// the week's whole points and every slot's counted points while a
  /// gameweek is being played. A single small child (read by any signed-in
  /// user) — never the whole `Squads` node of every manager. null = no live
  /// squad for that manager (no live week, or not scored): callers still gate
  /// on [liveAppliesTo] over the [FantasyLiveFeed] meta. Seeded from the
  /// session cache (`<root>|<uid>`, a known-absent node included); a stream
  /// error is "no live" (null, logged, never cached).
  static Stream<LiveSquad?> watchLiveSquad(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_liveSquadCache.containsKey(key)) yield _liveSquadCache[key];
    try {
      await for (final event
          in _ref('${_root(sport, season)}/Live/Squads/$uid').onValue) {
        final squad = liveSquadFromNode(event.snapshot.value);
        _liveSquadCache[key] = squad;
        yield squad;
      }
    } catch (e) {
      debugPrint('FantasyService: live squad feed failed: $e');
      _liveSquadCache.remove(key);
      yield null;
    }
  }

  /// One manager's settled gameweek (`History/<gw>/<uid>`: net tenths, the
  /// per-pick Breakdown, the Voided / Invalid verdicts) — the locked My Team's
  /// numbers once the week has settled. A single small node (public read):
  /// NEVER the whole `History` of every manager. null = no finalized squad
  /// that week. Seeded from the session cache (`<root>|<uid>|<gw>`, a
  /// known-absent node included); a stream error is forwarded to the caller
  /// (the locked-week feed counts it as "no data") and never cached.
  static Stream<HistoryWeek?> watchHistoryWeek(
      String sport, String season, String uid, int week) async* {
    final key = '${_root(sport, season)}|$uid|$week';
    if (_historyWeekCache.containsKey(key)) yield _historyWeekCache[key];
    await for (final event
        in _ref('${_root(sport, season)}/History/$week/$uid').onValue) {
      final settled = historyWeekFromNode(event.snapshot.value);
      _historyWeekCache[key] = settled;
      yield settled;
    }
  }

  /// The squad that was LOCKED for one gameweek (`PublishedPicks/<gw>/<uid>`:
  /// the lock's snapshot — picks, armband and the chip HONORED at the lock) —
  /// the locked My Team's court while the week is being played, since
  /// `Squads/<uid>` still holds a chip the lock may have voided and is
  /// rewritten at finalize. A single small node (readable after the lock):
  /// NEVER the whole `PublishedPicks` of every manager. null = no squad that
  /// week (or not locked yet). Seeded from the session cache
  /// (`<root>|<uid>|<gw>`, a known-absent node included); errors are
  /// forwarded to the caller and never cached.
  static Stream<FantasySquad?> watchPublishedPicksWeek(
      String sport, String season, String uid, int week) async* {
    final key = '${_root(sport, season)}|$uid|$week';
    if (_publishedPicksWeekCache.containsKey(key)) {
      yield _publishedPicksWeekCache[key];
    }
    await for (final event in _ref(
            '${_root(sport, season)}/PublishedPicks/$week/$uid')
        .onValue) {
      final squad = squadFromNode(event.snapshot.value);
      _publishedPicksWeekCache[key] = squad;
      yield squad;
    }
  }

  /// One manager's official Overall standing (`Leaderboards/Overall/<uid>`:
  /// rank + movement) — the locked My Team's "#R" once the week has settled.
  /// A single small child of the public `Leaderboards` node, not the whole
  /// board. null = not on the board yet. Seeded from the session cache
  /// (`<root>|<uid>`); errors are forwarded and never cached.
  static Stream<OverallStanding?> watchOverallStanding(
      String sport, String season, String uid) async* {
    final key = '${_root(sport, season)}|$uid';
    if (_overallStandingCache.containsKey(key)) {
      yield _overallStandingCache[key];
    }
    await for (final event in _ref(
            '${_root(sport, season)}/Leaderboards/Overall/$uid')
        .onValue) {
      final standing = overallStandingFromNode(event.snapshot.value);
      _overallStandingCache[key] = standing;
      yield standing;
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
