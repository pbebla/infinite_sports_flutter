// The data behind the Infinite profile's Fantasy tab (round 3, spec §7).
//
// `ProfilePage(uid)` gets a third tab when, for the current fantasy season,
// the uid maps to a fantasy PLAYER (the rosters join — team AND name, eligible
// market players only: a guest never gets a tab) and/or is a fantasy MANAGER
// (`Managers/<uid>`). [FantasyProfileSource] owns that decision and the feeds
// the tab's two sections read, so the page can decide the tab count BEFORE it
// builds its TabBar and the tab widget (fantasy_profile_tab.dart) stays a thin
// view over it.
//
// Flow (all live streams, never an RTDB get(); `once()` only inside the season
// resolver):
//   1. the season — `resolveFantasySeason()` (the home banner's resolution;
//      a real "none" is remembered a few minutes, a failed read is not), or
//      this session's last resolved one;
//   2. the DECISION feeds: Players + league rosters + `Managers/<uid>` →
//      [fantasyProfileAccess]. The first answer completes [decision] (the
//      page waits for it, bounded by [kFantasyTabDecisionGrace]); live
//      changes re-decide afterwards. The per-uid answer is cached for the
//      session, so a revisit decides in its first frame;
//   3. only for a uid WITH access, the CONTENT feeds: Config → schedule
//      gameweeks, and per role the player's PlayerTotals / every PriceChanges
//      week / his PlayerWeekStats (one listener per schedule gameweek), or
//      the Leaderboards. [contentReady] flips once every feed that applies
//      has landed (one fade reveal in the tab); a failing feed degrades to
//      "no data" instead of holding the skeleton.
//
// The pure parts — [fantasyProfileAccess], [managerStanding],
// [visibleTeamName] — are unit-tested in
// test/profile/fantasy_profile_tab_test.dart.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_season_resolver.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_account_link.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart'
    show managerNames;
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart'
    show FantasyProfileOpener;
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart'
    show isSignedInUid;
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

/// How long the profile page waits (after its own identity load) for the
/// Fantasy-tab decision before it reveals with two tabs; a later answer still
/// adds the tab, faded in. Cached/seeded decisions are instant, so this only
/// bites on a cold, slow connection.
const Duration kFantasyTabDecisionGrace = Duration(milliseconds: 500);

/// Test seams — every field null = the real FantasyService / LeagueService /
/// navigation. Passed to `ProfilePage(fantasySeams:)` (mirrors the other
/// profile seams `loadOverride` / `careerLoadOverride`).
class FantasyProfileSeams {
  const FantasyProfileSeams({
    this.resolveSeason,
    this.playersStates,
    this.rosterStates,
    this.managerStates,
    this.configStates,
    this.gameweekStates,
    this.gameweeksFor,
    this.totalsStates,
    this.priceChangeStates,
    this.weekStatsFor,
    this.leaderboardsStates,
    this.selfUidOverride,
    this.openInFantasy,
    this.viewerPublishedStates,
    this.viewerHistoryStates,
    this.viewerSquadStates,
    this.profileOpener,
  });

  final Future<FantasySeasonKey?> Function()? resolveSeason;
  final Stream<List<FantasyPlayer>>? playersStates;
  final Stream<Map<String, List<TournamentPlayer>>>? rosterStates;
  final Stream<FantasyManager?>? managerStates;
  final Stream<FantasyConfigState?>? configStates;

  /// Replaces the config-derived schedule gameweeks.
  final Stream<List<Gameweek>>? gameweekStates;

  /// Replaces `FantasyService.watchGameweeks(sport, season, config)` ONLY
  /// (the config → schedule wiring itself still runs): lets a test drive the
  /// real lock-hour resubscribe / cache / clear branch. Ignored when
  /// [gameweekStates] is given.
  final Stream<List<Gameweek>> Function(FantasyConfig config)? gameweeksFor;
  final Stream<Map<String, FantasyPlayerTotals>?>? totalsStates;
  final Stream<Map<int, Map<String, int>>>? priceChangeStates;
  final Stream<Map<int, PlayerWeekStats>> Function(
      String playerName, List<int> weeks)? weekStatsFor;
  final Stream<FantasyLeaderboards>? leaderboardsStates;

  /// The signed-in uid ('' = signed out); null = FirebaseAuth.
  final String? selfUidOverride;

  /// "Open in Fantasy": receives the hub route (Players tab + his name).
  /// null = pushes `fantasyHubPageRoute(route)`.
  final void Function(BuildContext context, FantasyHubRoute route)?
      openInFantasy;

  /// The squad viewer's own feeds (the tab's "View team" builds the real
  /// [ManagerSquadViewerPage]; these replace its Firebase streams).
  final Stream<Map<int, FantasySquad>>? viewerPublishedStates;
  final Stream<Map<int, FantasySquad>>? viewerHistoryStates;
  final Stream<FantasySquad?>? viewerSquadStates;

  /// What a viewer court chip opens (`openFantasyPlayerProfile`'s shape).
  final FantasyProfileOpener? profileOpener;
}

// ── Pure logic ──────────────────────────────────────────────────────────────

/// Who a uid is in one fantasy season.
class FantasyProfileAccess {
  const FantasyProfileAccess({
    required this.sport,
    required this.season,
    this.player,
    this.manager,
  });

  final String sport;
  final String season;

  /// The eligible market player linked to this account (rosters join).
  final FantasyPlayer? player;

  /// `Managers/<uid>` — the fantasy team (its name may be flagged).
  final FantasyManager? manager;

  bool get hasTab => player != null || manager != null;
}

/// The join: null when [uid] is neither a fantasy player nor a manager.
/// [players] is the whole market — guests (`eligible == false`) are dropped
/// here, so an ineligible player never produces a Fantasy tab
/// (`fantasyPlayerForUid` itself does not filter on `eligible`).
FantasyProfileAccess? fantasyProfileAccess({
  required String sport,
  required String season,
  required String uid,
  required List<FantasyPlayer> players,
  required Map<String, List<TournamentPlayer>> rosters,
  required FantasyManager? manager,
}) {
  final player = fantasyPlayerForUid(
    uid,
    [
      for (final p in players)
        if (p.eligible) p
    ],
    rosters,
  );
  if (player == null && manager == null) return null;
  return FantasyProfileAccess(
    sport: sport,
    season: season,
    player: player,
    manager: manager,
  );
}

/// A manager's place on the Overall board: rank / points / movement
/// (positive = climbed). All null = no entry yet (no finalized gameweek, or
/// he has not scored) — the tab then shows copy, never made-up zeros.
class FantasyManagerStanding {
  const FantasyManagerStanding({this.rank, this.points, this.movement});

  static const FantasyManagerStanding unranked = FantasyManagerStanding();

  final int? rank;
  final int? points;
  final int? movement;

  bool get ranked => rank != null;
}

/// `Leaderboards/Overall/<uid>`: the functions-written rank when present,
/// else the list position (the leaderboard rows' own rule).
FantasyManagerStanding managerStanding(FantasyLeaderboards boards, String uid) {
  for (final (i, e) in boards.overall.indexed) {
    if (e.uid == uid) {
      return FantasyManagerStanding(
        rank: e.rank ?? i + 1,
        points: e.points,
        movement: e.movement,
      );
    }
  }
  return FantasyManagerStanding.unranked;
}

/// The team name that may be shown: null when it is flagged (never shown
/// publicly) or blank — the leaderboard's own rule (`managerNames`).
String? visibleTeamName(String uid, FantasyManager manager) => managerNames(
      uid: uid,
      managers: {uid: manager},
      profiles: const {},
    ).teamName;

// ── The source ──────────────────────────────────────────────────────────────

class _DecisionSeed {
  const _DecisionSeed({this.player, this.manager});
  final FantasyPlayer? player;
  final FantasyManager? manager;
}

class FantasyProfileSource extends ChangeNotifier {
  FantasyProfileSource({required this.uid, FantasyProfileSeams? seams})
      : seams = seams ?? const FantasyProfileSeams();

  final String uid;
  final FantasyProfileSeams seams;

  // ── Session caches (instant revisits) ───────────────────────────────────
  // `<sport>|<season>|<uid>` → what the uid was last decided to be; the
  // schedule per `<sport>|<season>`. The Fantasy/League services seed their
  // own streams; these two are the pieces they don't.
  static final Map<String, _DecisionSeed> _decisionSession = {};
  static final Map<String, List<Gameweek>> _gameweeksSession = {};

  /// Clears the session caches (sign-out hygiene, tests).
  static void clearSessionCaches() {
    _decisionSession.clear();
    _gameweeksSession.clear();
    _resolving = null;
    _noSeasonAt = null;
  }

  // ── Shared season resolution ────────────────────────────────────────────
  // The resolver memoizes only a SUCCESS ([lastResolvedFantasySeason]); with
  // no fantasy season in reach it would otherwise re-probe ~30 Config nodes
  // on EVERY profile open. So a REAL "none" answer is remembered for a few
  // minutes, and simultaneous opens share one in-flight resolution. A FAILED
  // resolve (a network blip) is logged and never remembered — it means "no
  // tab this time", and the very next open asks again.
  static Future<FantasySeasonKey?>? _resolving;
  static DateTime? _noSeasonAt;

  /// How long a "no fantasy season" answer is trusted before asking again.
  static const Duration kNoSeasonRecheck = Duration(minutes: 5);

  /// [resolver] (the real [resolveFantasySeason] in the app), shared: one
  /// in-flight call at a time; only a real "none" is cached, for
  /// [kNoSeasonRecheck]; an error (returned or thrown) is logged and not
  /// cached. Resolves to the season, or null for none / error. Public so the
  /// memoization is unit-testable.
  static Future<FantasySeasonKey?> resolveSeasonShared(
    Future<FantasySeasonResolution> Function() resolver, {
    DateTime Function()? now,
  }) {
    final clock = now ?? DateTime.now;
    final none = _noSeasonAt;
    if (none != null && clock().difference(none) < kNoSeasonRecheck) {
      return Future<FantasySeasonKey?>.value(null);
    }
    return _resolving ??= _runResolve(resolver, clock);
  }

  static Future<FantasySeasonKey?> _runResolve(
    Future<FantasySeasonResolution> Function() resolver,
    DateTime Function() clock,
  ) async {
    FantasySeasonResolution result;
    try {
      result = await resolver();
    } catch (e) {
      result = FantasySeasonResolution.failed(e);
    }
    _resolving = null;
    if (result.failed) {
      _log('season resolver', result.error!);
      _noSeasonAt = null; // unknown ≠ none: retried on the next open
    } else {
      _noSeasonAt = result.isNone ? clock() : null;
    }
    return result.season;
  }

  /// Failures degrade to "no data" for the reader but are never silent.
  static void _log(String what, Object error) =>
      debugPrint('FantasyProfileSource: $what failed: $error');

  bool _started = false;
  bool _disposed = false;
  FantasySeasonKey? _season;
  FantasyProfileAccess? _access;
  bool _decided = false;
  final Completer<void> _decision = Completer<void>();

  // Decision feeds. `*Real` = the feed has delivered an actual emission (not
  // an error fallback); only an all-real decision is cached for the session.
  List<FantasyPlayer>? _players;
  Map<String, List<TournamentPlayer>>? _rosters;
  bool _managerLoaded = false;
  FantasyManager? _manager;
  bool _playersReal = false;
  bool _rostersReal = false;
  bool _managerReal = false;

  /// The decision on screen came from the session seed (and no all-real
  /// answer has replaced it yet): error fallbacks must not override it.
  bool _seeded = false;

  // Content feeds.
  bool _configSubscribed = false;
  FantasyConfigState? _config;
  bool _configLoaded = false;

  /// A REAL emission said the season has no Config node (fantasy removed).
  /// A Config ERROR is not this: it keeps the last good config and the tab.
  bool _configAbsent = false;
  List<Gameweek>? _gameweeks;
  int? _gameweeksLockHour;
  bool _playerFeedsSubscribed = false;
  Map<String, FantasyPlayerTotals>? _totals;
  bool _totalsLoaded = false;
  Map<int, Map<String, int>>? _changes;
  Map<int, PlayerWeekStats>? _weeks;
  List<int>? _weekNumbers;
  String? _weeksPlayer;
  bool _boardsSubscribed = false;
  FantasyLeaderboards? _boards;

  final List<StreamSubscription<Object?>> _subs = [];
  StreamSubscription<List<Gameweek>>? _gameweeksSub;
  StreamSubscription<Map<int, PlayerWeekStats>>? _weeksSub;

  // ── Public state ────────────────────────────────────────────────────────

  /// The first decision (tab or no tab) has been made.
  bool get decided => _decided;

  /// Completes with the first decision (immediately for a seeded revisit).
  Future<void> get decision => _decision.future;

  /// Who this uid is in the resolved season; null = no Fantasy tab.
  FantasyProfileAccess? get access => _access;

  /// Whether the profile shows a Fantasy tab right now. A season whose
  /// Config is really gone (an emission, not an error) no longer counts.
  bool get hasTab => _decided && _access != null && !_configAbsent;

  /// The signed-in user viewing his OWN profile (the squad viewer then shows
  /// his live squad, not the lock-published copy).
  bool get isSelf {
    final override = seams.selfUidOverride;
    if (override != null) return override.isNotEmpty && override == uid;
    return isSignedInUid(uid);
  }

  /// The live market (the squad viewer's photo source).
  List<FantasyPlayer> get players => _players ?? const [];
  FantasyConfig? get config => _config?.config;
  List<Gameweek> get gameweeks => _gameweeks ?? const [];

  /// The player section's model (Task 5's pure builder): null without a
  /// player role. `priceHistory` is not shown here, so it is left empty.
  FantasyProfileModel? get playerModel {
    final player = _access?.player;
    if (player == null) return null;
    return buildProfileModel(
      player: player,
      totals: _totals?[player.name],
      weeks: _weeks ?? const {},
      priceHistory: const {},
      priceChanges: _changes ?? const {},
    );
  }

  /// The manager section's standing (null without a manager role).
  FantasyManagerStanding? get standing =>
      _access?.manager == null || _boards == null
          ? null
          : managerStanding(_boards!, uid);

  /// Every feed that applies to this uid's roles has landed: the tab fades
  /// its content in once, never piece by piece.
  bool get contentReady {
    final a = _access;
    if (a == null || !_configLoaded || _gameweeks == null) return false;
    if (a.player != null &&
        !(_totalsLoaded && _changes != null && _weeks != null)) {
      return false;
    }
    if (a.manager != null && _boards == null) return false;
    return true;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Begins resolving the season and the decision. Safe to call once; never
  /// throws (any failure = no Fantasy tab).
  void start() {
    if (_started || _disposed) return;
    _started = true;
    try {
      final resolver = seams.resolveSeason;
      // Real feeds: this session's last resolved season starts everything in
      // this very frame; a seamed resolver is always awaited.
      final memo = resolver == null ? lastResolvedFantasySeason : null;
      if (memo != null) {
        _begin(memo);
      } else {
        unawaited(_resolveThenBegin(
            resolver ?? () => resolveSeasonShared(resolveFantasySeason)));
      }
    } catch (e) {
      _log('start', e);
      _settle();
    }
  }

  Future<void> _resolveThenBegin(
      Future<FantasySeasonKey?> Function() resolve) async {
    FantasySeasonKey? season;
    try {
      season = await resolve();
    } catch (e) {
      _log('season', e);
      season = null;
    }
    if (_disposed) return;
    if (season == null) {
      _settle();
      _notify();
      return;
    }
    try {
      _begin(season);
    } catch (e) {
      _log('begin', e);
      _settle();
      _notify();
    }
  }

  String _seedKey(FantasySeasonKey season) =>
      '${season.sport}|${season.season}|$uid';

  void _begin(FantasySeasonKey season) {
    _season = season;
    final seed = _decisionSession[_seedKey(season)];
    if (seed != null) {
      _manager = seed.manager;
      _managerLoaded = true;
      _access = seed.player == null && seed.manager == null
          ? null
          : FantasyProfileAccess(
              sport: season.sport,
              season: season.season,
              player: seed.player,
              manager: seed.manager,
            );
      _seeded = true;
      _settle();
    }
    final cachedWeeks = _gameweeksSession['${season.sport}|${season.season}'];
    if (cachedWeeks != null) _gameweeks = cachedWeeks;

    _listen<List<FantasyPlayer>>(
      () =>
          seams.playersStates ??
          FantasyService.watchPlayers(season.sport, season.season),
      (p) {
        _players = p;
        _playersReal = true;
        _recompute();
      },
      onFail: () {
        _players ??= const [];
        _recompute();
      },
      label: 'players',
    );
    _listen<Map<String, List<TournamentPlayer>>>(
      () =>
          seams.rosterStates ??
          LeagueService.watchRosters(season.sport, season.season),
      (r) {
        _rosters = r;
        _rostersReal = true;
        _recompute();
      },
      onFail: () {
        _rosters ??= const {};
        _recompute();
      },
      label: 'rosters',
    );
    _listen<FantasyManager?>(
      () =>
          seams.managerStates ??
          FantasyService.watchManager(season.sport, season.season, uid),
      (m) {
        _manager = m;
        _managerLoaded = true;
        _managerReal = true;
        _recompute();
      },
      onFail: () {
        // Keeps a seeded / earlier-real manager; a never-loaded one is null.
        _managerLoaded = true;
        _recompute();
      },
      label: 'manager',
    );
    if (seed != null) {
      _ensureContent();
      _notify();
    }
  }

  /// Subscribes defensively: a stream that cannot even be created (no
  /// Firebase app in a widget test) or that errors degrades to [onFail] —
  /// and is logged under [label] (a feed error is never silent).
  void _listen<T>(
    Stream<T> Function() make,
    void Function(T value) onData, {
    required void Function() onFail,
    required String label,
  }) {
    try {
      _subs.add(make().listen((v) {
        if (!_disposed) onData(v);
      }, onError: (Object e) {
        _log('$label feed', e);
        if (!_disposed) onFail();
      }));
    } catch (e) {
      _log('$label feed', e);
      onFail();
    }
  }

  void _settle() {
    _decided = true;
    if (!_decision.isCompleted) _decision.complete();
  }

  void _recompute() {
    if (_disposed) return;
    final season = _season;
    if (season != null &&
        _players != null &&
        _rosters != null &&
        _managerLoaded) {
      final real = _playersReal && _rostersReal && _managerReal;
      // A decision made from an error fallback may decide THIS paint, but it
      // never overrides a seeded decision (a shown tab must not drop on an
      // error) and is never cached: only an all-real answer is remembered, so
      // the next open re-decides.
      if (real || !_seeded) {
        _access = fantasyProfileAccess(
          sport: season.sport,
          season: season.season,
          uid: uid,
          players: _players!,
          rosters: _rosters!,
          manager: _manager,
        );
        if (real) {
          _seeded = false;
          _decisionSession[_seedKey(season)] = _DecisionSeed(
            player: _access?.player,
            manager: _access?.manager,
          );
        }
        _settle();
      }
    }
    _ensureContent();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Content feeds (only for a uid with access) ──────────────────────────

  void _ensureContent() {
    final access = _access;
    final season = _season;
    if (access == null || season == null) return;

    if (!_configSubscribed) {
      _configSubscribed = true;
      _subscribeConfig(season);
    }
    if (access.player != null) {
      if (!_playerFeedsSubscribed) {
        _playerFeedsSubscribed = true;
        _listen<Map<String, FantasyPlayerTotals>?>(
          () =>
              seams.totalsStates ??
              FantasyService.watchPlayerTotals(season.sport, season.season),
          (t) {
            _totals = t;
            _totalsLoaded = true;
            _notify();
          },
          onFail: () {
            _totalsLoaded = true;
            _notify();
          },
          label: 'totals',
        );
        _listen<Map<int, Map<String, int>>>(
          () =>
              seams.priceChangeStates ??
              FantasyService.watchAllPriceChanges(season.sport, season.season),
          (c) {
            _changes = c;
            _notify();
          },
          onFail: () {
            _changes ??= const {};
            _notify();
          },
          label: 'price changes',
        );
      }
      _syncWeeks(season, access.player!.name);
    }
    if (access.manager != null && !_boardsSubscribed) {
      _boardsSubscribed = true;
      _listen<FantasyLeaderboards>(
        () =>
            seams.leaderboardsStates ??
            FantasyService.watchLeaderboards(season.sport, season.season),
        (b) {
          _boards = b;
          _notify();
        },
        onFail: () {
          _boards ??= FantasyLeaderboards.empty;
          _notify();
        },
        label: 'leaderboards',
      );
    }
  }

  void _subscribeConfig(FantasySeasonKey season) {
    final gameweekSeam = seams.gameweekStates;
    if (gameweekSeam != null) {
      _gameweeksSub = _subscribeGameweeks(gameweekSeam, season, cache: false);
    }
    _listen<FantasyConfigState?>(
      () =>
          seams.configStates ??
          FantasyService.watchConfig(season.sport, season.season),
      (state) {
        _config = state;
        _configAbsent = state == null;
        _configLoaded = true;
        if (state == null) {
          // Fantasy removed for the season: nothing stale may seed a revisit.
          _gameweeksSession.remove('${season.sport}|${season.season}');
          _decisionSession.remove(_seedKey(season));
        }
        if (gameweekSeam == null) {
          if (state == null) {
            // No fantasy config → no schedule-derived weeks.
            _gameweeksSub?.cancel();
            _gameweeksSub = null;
            _gameweeksLockHour = null;
            _gameweeks = const [];
          } else if (_gameweeksLockHour != state.config.lockHour) {
            _gameweeksLockHour = state.config.lockHour;
            _gameweeksSub?.cancel();
            _gameweeksSub = _subscribeGameweeks(
              seams.gameweeksFor?.call(state.config) ??
                  FantasyService.watchGameweeks(
                      season.sport, season.season, state.config),
              season,
              cache: true,
            );
          }
        }
        _recomputeWeeks();
        _notify();
      },
      onFail: () {
        // The LAST GOOD config stays (and the tab with it): an error is not
        // "fantasy removed". With no config ever loaded the player section
        // still renders; View team says it can't open (see the tab).
        _configLoaded = true;
        _gameweeks ??= const [];
        _recomputeWeeks();
        _notify();
      },
      label: 'config',
    );
  }

  StreamSubscription<List<Gameweek>>? _subscribeGameweeks(
    Stream<List<Gameweek>> stream,
    FantasySeasonKey season, {
    required bool cache,
  }) {
    try {
      return stream.listen((gws) {
        if (_disposed) return;
        if (cache) {
          _gameweeksSession['${season.sport}|${season.season}'] = gws;
        }
        _gameweeks = gws;
        _recomputeWeeks();
        _notify();
      }, onError: (Object e) {
        // A failed schedule read: no weeks to listen to (never cached — the
        // next visit retries), unless a schedule is already showing.
        _log('schedule feed', e);
        if (_disposed) return;
        _gameweeks ??= const [];
        _recomputeWeeks();
        _notify();
      });
    } catch (e) {
      _log('schedule feed', e);
      _gameweeks ??= const [];
      return null;
    }
  }

  void _recomputeWeeks() {
    final access = _access;
    final season = _season;
    if (access?.player == null || season == null) return;
    _syncWeeks(season, access!.player!.name);
  }

  /// One PlayerWeekStats listener per schedule gameweek; resubscribes only
  /// when the player or the week numbers change (a config re-emit that keeps
  /// them never flickers the tab).
  void _syncWeeks(FantasySeasonKey season, String playerName) {
    final gws = _gameweeks;
    if (gws == null) return;
    final weeks = [for (final g in gws) g.number];
    final known = _weekNumbers;
    if (_weeksPlayer == playerName &&
        known != null &&
        known.length == weeks.length &&
        Iterable<int>.generate(weeks.length)
            .every((i) => known[i] == weeks[i])) {
      return;
    }
    if (_weeksPlayer != playerName) _weeks = null; // never another player's
    _weeksPlayer = playerName;
    _weekNumbers = weeks;
    _weeksSub?.cancel();
    try {
      final source = seams.weekStatsFor?.call(playerName, weeks) ??
          FantasyService.watchPlayerWeekStatsFor(
              season.sport, season.season, playerName, weeks);
      _weeksSub = source.listen((w) {
        if (_disposed) return;
        _weeks = w;
        _notify();
      }, onError: (Object e) {
        _log('week stats feed', e);
        if (_disposed) return;
        _weeks ??= const {};
        _notify();
      });
    } catch (e) {
      _log('week stats feed', e);
      _weeks ??= const {};
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _gameweeksSub?.cancel();
    _weeksSub?.cancel();
    super.dispose();
  }
}
