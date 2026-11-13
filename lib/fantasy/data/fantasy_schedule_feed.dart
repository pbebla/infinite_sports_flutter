// ONE wiring for the fantasy schedule every Fantasy screen needs (final
// review A/B) — and its sibling for the league games behind the "next game"
// lines:
//
//   [FantasyScheduleFeed]: `Fantasy/<sport>/<season>/Config` → the schedule's
//   gameweeks (derived from the league's dates, the server's frozen weeks and
//   the legacy start time, WITH the config's lock hour and the owner's
//   schedule overrides — `FantasyService.watchGameweeks`) → optionally ONE
//   per-gameweek listener (a player's weekly records, the manager's chip
//   history).
//
//   [FantasyLeagueGamesFeed]: the season's legacy start hour → the league
//   games derived with it.
//
//   [FantasySeasonFinishedFeed]: the league's own `Finished` flag — the
//   screens drop their price arrows once the season is over.
//
// This used to be hand-wired four times (home banner, hub, player profile,
// the Infinite profile's Fantasy tab) plus twice for the games (market,
// player profile), and the copies had drifted. One behaviour now, for every
// caller:
//   • a REAL null Config (fantasy removed) clears the schedule, cancels its
//     listener and drops the cached schedule (an error is NOT "removed");
//   • every stream has an error handler: logged with debugPrint, the last
//     good value kept; with nothing good yet the gates still open ("no
//     data"), never an eternal skeleton; a stream that cannot even be
//     created (no Firebase app in a widget test) degrades the same way;
//   • the schedule resubscribes only when the lock hour or the owner's
//     schedule overrides change (moved deadlines, skipped days, the kickoff
//     margin — every one of them moves a week); the per-week listener only
//     when the week numbers (or its key) change, and keeps its last data
//     until the new listener answers;
//   • the per-week listener covers only the weeks UP TO the current
//     gameweek (`currentGameweek`; all of them once the season is over) —
//     a week that hasn't locked can't have History / PlayerWeekStats yet, so
//     listening to it is a wasted read on every open. A timer re-syncs at
//     the current week's day end, so the list grows as the season advances
//     even while the screen stays open;
//   • session caches make a revisit paint at once — the games cache stores
//     whether the games were DERIVED with a real start hour, so a revisit
//     after a failed-then-successful hour read never shows "0 PM" (it drops
//     the derived time until the re-derived games arrive).
//
// Plain Dart (no widgets): the owner passes `onChanged` (its setState /
// notifyListeners), calls `start()` once (initState) and `dispose()`.
// `start()` never notifies synchronously — the owner reads the seeded state
// right after it returns.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// `<owner>: <what> failed: <error>` — the fantasy screens' log line shape.
void _logFailure(String owner, String what, Object error) =>
    debugPrint('$owner: $what failed: $error');

/// Listens defensively: a stream that errors, or that cannot even be created,
/// is logged under [what] and reported through [onError] — never thrown.
StreamSubscription<T>? _listenLogged<T>({
  required String owner,
  required String what,
  required Stream<T> Function() make,
  required bool Function() disposed,
  required void Function(T value) onData,
  required void Function() onError,
}) {
  try {
    return make().listen((v) {
      if (!disposed()) onData(v);
    }, onError: (Object e) {
      _logFailure(owner, what, e);
      if (!disposed()) onError();
    });
  } catch (e) {
    _logFailure(owner, what, e);
    onError();
    return null;
  }
}

/// Config → schedule gameweeks → (optionally) one per-gameweek listener of
/// type [W]. See the file header for the shared rules.
class FantasyScheduleFeed<W> {
  FantasyScheduleFeed({
    required this.sport,
    required this.season,
    required this.owner,
    required this.onChanged,
    this.onConfig,
    this.configStates,
    this.gameweekStates,
    this.gameweeksFor,
    Stream<W> Function(List<int> weeks)? weekFeed,
    this.weekLabel = 'week feed',
    this.nowUtc,
  }) : _weekFeed = weekFeed;

  final String sport;
  final String season;

  /// The log prefix (the owning screen / source).
  final String owner;

  /// Something changed (after start): repaint.
  final VoidCallback onChanged;

  /// Every REAL Config emission (null = the node is absent), after the feed
  /// applied it and right before [onChanged]. Errors never reach it.
  final void Function(FantasyConfigState? state)? onConfig;

  /// Test seam — null = `FantasyService.watchConfig`.
  final Stream<FantasyConfigState?>? configStates;

  /// Test seam REPLACING the config-derived schedule: listened to once at
  /// start, independent of the Config (never written to the session cache).
  final Stream<List<Gameweek>>? gameweekStates;

  /// Test seam replacing ONLY `FantasyService.watchGameweeks(sport, season,
  /// config, overrides)` — the Config → schedule wiring itself still runs
  /// (lock-hour / overrides resubscribe, clear on a null Config, the session
  /// cache). Ignored when [gameweekStates] is given.
  final Stream<List<Gameweek>> Function(
      FantasyConfig config, ScheduleOverrides overrides)? gameweeksFor;

  /// The per-week listener's name in log lines ("week stats feed").
  final String weekLabel;

  /// Clock seam for the "weeks up to the current gameweek" trim (null =
  /// real UTC now).
  final DateTime Function()? nowUtc;

  DateTime _now() => (nowUtc ?? () => DateTime.now().toUtc())();

  /// Longest single wait of the week-boundary timer: a far-off boundary is
  /// re-checked daily instead of one huge timer.
  static const Duration _maxBoundaryWait = Duration(days: 1);

  // ── Session cache: the derived schedule per `<sport>|<season>` ──────────
  static final Map<String, List<Gameweek>> _gameweeksSession = {};

  /// Clears the shared schedule cache (sign-out hygiene, tests).
  static void clearSessionCache() => _gameweeksSession.clear();

  String get _sessionKey => '$sport|$season';
  bool get _derived => gameweekStates == null;

  bool _started = false;
  bool _starting = false;
  bool _disposed = false;

  FantasyConfigState? _config;
  bool _configLoaded = false;
  bool _configAbsent = false;
  List<Gameweek>? _gameweeks;
  // What the derived schedule listens with: the lock hour and the owner's
  // overrides (null = not listening). Records compare by value, and
  // ScheduleOverrides has value equality, so an equal re-emit is a no-op.
  (int, ScheduleOverrides)? _scheduleKey;

  Stream<W> Function(List<int> weeks)? _weekFeed;
  Object? _weekKey;
  List<int>? _weekNumbers; // the weeks the per-week listener listens to
  W? _weekData;
  bool _weekLoaded = false;

  StreamSubscription<FantasyConfigState?>? _configSub;
  StreamSubscription<List<Gameweek>>? _gameweeksSub;
  StreamSubscription<W>? _weekSub;
  Timer? _weekBoundary; // re-syncs the week list when the current week ends

  // ── State ────────────────────────────────────────────────────────────────

  /// The last good Config (null: none yet, or a REAL emission said absent).
  FantasyConfigState? get config => _config;

  /// The Config feed has answered (an emission or an error).
  bool get configLoaded => _configLoaded;

  /// A REAL emission said the season has no Config (fantasy removed). A
  /// Config ERROR never sets this.
  bool get configAbsent => _configAbsent;

  /// The schedule; null until it is known (an emission, the session cache,
  /// or an error / null Config → empty).
  List<Gameweek>? get gameweeks => _gameweeks;

  /// The per-week listener's last good value (null: none yet).
  W? get weekData => _weekData;

  /// The per-week listener has answered (data or an error) since its key
  /// last changed.
  bool get weekLoaded => _weekLoaded;

  /// The per-week listener answered with an ERROR and has no good value to
  /// fall back on ([weekData] null): what it would have said is UNKNOWN.
  /// Distinct from answering with an empty map ("nothing there"), from an
  /// error after good data (the last good value is kept), and from not having
  /// answered yet ([weekLoaded] false). A consumer that must not guess —
  /// e.g. "which chips are spent" — reads this instead of treating the null
  /// [weekData] as empty.
  bool get weekUnknown => _weekLoaded && _weekData == null;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Seeds from the session cache and subscribes. Call once; never throws
  /// and never notifies synchronously.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _starting = true;
    try {
      final cached = _gameweeksSession[_sessionKey];
      if (cached != null) _gameweeks = cached;
      _syncWeeks(); // a cached schedule starts the week listener at once
      final seam = gameweekStates;
      if (seam != null) _listenSchedule(() => seam);
      _configSub = _listenLogged<FantasyConfigState?>(
        owner: owner,
        what: 'config feed',
        make: () => configStates ?? FantasyService.watchConfig(sport, season),
        disposed: () => _disposed,
        onData: _onConfig,
        onError: _onConfigError,
      );
    } finally {
      _starting = false;
    }
  }

  /// Points the per-week listener at [make] under [key] (e.g. the player's
  /// name). The same key again is a no-op; a NEW key drops the previous
  /// key's data at once (never another player's weeks) and resubscribes.
  /// The caller repaints.
  void setWeekFeed(Object? key, Stream<W> Function(List<int> weeks) make) {
    if (_disposed) return;
    if (_weekFeed != null && key == _weekKey) return;
    if (key != _weekKey) {
      _weekSub?.cancel();
      _weekSub = null;
      _weekData = null;
      _weekLoaded = false;
    }
    _weekKey = key;
    _weekFeed = make;
    _weekNumbers = null;
    if (_started) _syncWeeks();
  }

  void dispose() {
    _disposed = true;
    _configSub?.cancel();
    _gameweeksSub?.cancel();
    _weekSub?.cancel();
    _weekBoundary?.cancel();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed && !_starting) onChanged();
  }

  void _onConfig(FantasyConfigState? state) {
    _config = state;
    _configLoaded = true;
    _configAbsent = state == null;
    if (state == null) {
      // Fantasy removed for the season: nothing stale may seed a revisit.
      _gameweeksSession.remove(_sessionKey);
      if (_derived) {
        _gameweeksSub?.cancel();
        _gameweeksSub = null;
        _scheduleKey = null;
        _gameweeks = const [];
      }
    } else if (_derived) {
      // Weeks and deadlines move only with the lock hour and the owner's
      // schedule overrides: other config tweaks keep the running schedule
      // listener.
      final key = (state.config.lockHour, state.schedule);
      if (_scheduleKey != key) {
        _scheduleKey = key;
        _gameweeksSub?.cancel();
        final config = state.config;
        final overrides = state.schedule;
        _listenSchedule(() =>
            gameweeksFor?.call(config, overrides) ??
            FantasyService.watchGameweeks(sport, season, config, overrides));
      }
    }
    onConfig?.call(state);
    _syncWeeks();
    _notify();
  }

  /// The LAST GOOD config stays: an error is not "fantasy removed". With no
  /// schedule yet none can be derived — an empty one keeps gates open.
  void _onConfigError() {
    _configLoaded = true;
    if (_derived) _gameweeks ??= const [];
    _syncWeeks();
    _notify();
  }

  void _listenSchedule(Stream<List<Gameweek>> Function() make) {
    _gameweeksSub = null;
    _gameweeksSub = _listenLogged<List<Gameweek>>(
      owner: owner,
      what: 'schedule feed',
      make: make,
      disposed: () => _disposed,
      onData: (gws) {
        if (_derived) _gameweeksSession[_sessionKey] = gws;
        _gameweeks = gws;
        _syncWeeks();
        _notify();
      },
      onError: () {
        // Never cached; a schedule already showing stays.
        _gameweeks ??= const [];
        _syncWeeks();
        _notify();
      },
    );
  }

  void _syncWeeks() {
    final make = _weekFeed;
    final gws = _gameweeks;
    _weekBoundary?.cancel();
    _weekBoundary = null;
    if (make == null || gws == null || _disposed) return;
    // Only weeks up to the current one can hold records (none past it has
    // locked); season over (no current week) = every week.
    final now = _now();
    final current = currentGameweek(gws, now);
    final weeks = [
      for (final g in gws)
        if (current == null || g.number <= current.number) g.number,
    ];
    if (current != null) {
      // currentGameweek moves on at the end of the current week's lock day.
      var wait = current.lockUtc.add(const Duration(hours: 24)).difference(now);
      if (wait > _maxBoundaryWait) wait = _maxBoundaryWait;
      if (wait < Duration.zero) wait = Duration.zero;
      _weekBoundary = Timer(wait, () {
        _weekBoundary = null;
        if (!_disposed) _syncWeeks();
      });
    }
    if (_weekNumbers != null && listEquals(_weekNumbers, weeks)) return;
    _weekNumbers = weeks;
    _weekSub?.cancel();
    _weekSub = null;
    _weekSub = _listenLogged<W>(
      owner: owner,
      what: weekLabel,
      make: () => make(weeks),
      disposed: () => _disposed,
      onData: (w) {
        _weekData = w;
        _weekLoaded = true;
        _notify();
      },
      onError: () {
        _weekLoaded = true; // last good data kept
        _notify();
      },
    );
  }
}

/// The league games behind the "next game" lines, derived with the season's
/// legacy start hour. A legacy game without a stored time derives it from
/// that hour, so the hour is read first; `LeagueService.getStartHour`
/// returns 0 for an absent node AND a failed read — 0 = unknown, never
/// cached, and [startHourKnown] then tells the line to drop a derived time
/// (`nextGameText`) instead of showing "0 PM".
///
/// The hour read is a one-shot `once()` inside the first visit's reveal
/// gate, and RTDB `once()` never answers on a cold OFFLINE client — so it is
/// bounded ([kRevealReadTimeout], logged): no answer by then counts as 0
/// (unknown), the games are derived without it and the line reads
/// "vs Nimrod · Sun" — never an eternal skeleton.
class FantasyLeagueGamesFeed {
  FantasyLeagueGamesFeed({
    required this.sport,
    required this.season,
    required this.owner,
    required this.onChanged,
    this.gamesStates,
    this.gamesFor,
    Future<int> Function()? loadStartHour,
  }) : _loadStartHour = loadStartHour ??
            (gamesStates != null
                ? null
                : () => LeagueService.getStartHour(sport, season));

  final String sport;
  final String season;
  final String owner;
  final VoidCallback onChanged;

  /// Test seam REPLACING the league games (fed games carry their own times;
  /// with no hour loader they count as known).
  final Stream<List<TournamentMatch>>? gamesStates;

  /// Test seam replacing ONLY `LeagueService.watchGames(sport, season,
  /// startHour:)` — the hour → games wiring and its caches still run.
  final Stream<List<TournamentMatch>> Function(int startHour)? gamesFor;

  /// null only for fed games without a loader seam.
  final Future<int> Function()? _loadStartHour;

  // ── Session caches per `<sport>|<season>` ───────────────────────────────
  /// The last games AND whether they were derived with a real hour.
  static final Map<String, ({List<TournamentMatch> games, bool hourKnown})>
      _gamesSession = {};

  /// Only a REAL start hour (> 0): absent / failed is retried next visit.
  static final Map<String, int> _startHourSession = {};

  /// Clears the shared games caches (sign-out hygiene, tests).
  static void clearSessionCache() {
    _gamesSession.clear();
    _startHourSession.clear();
  }

  String get _sessionKey => '$sport|$season';

  bool _started = false;
  bool _starting = false;
  bool _disposed = false;

  List<TournamentMatch> _games = const [];
  bool _gamesLoaded = false;
  bool _gamesHourKnown = false;
  bool _hourPending = false;
  int? _hour; // the latest start hour read (0 = unknown)

  StreamSubscription<List<TournamentMatch>>? _gamesSub;

  /// The games on screen (empty until loaded, or none).
  List<TournamentMatch> get games => _games;

  /// The games have landed (or failed) and no first-visit hour read is
  /// pending — joins the owner's reveal gate.
  bool get ready => _gamesLoaded && !_hourPending;

  /// Whether the games ON SCREEN were derived with a real start hour (fed
  /// games: whether the loaded hour is real). false → a derived time must be
  /// dropped, never shown as "0 PM".
  bool get startHourKnown => _gamesHourKnown;

  /// Seeds from the session and subscribes. A first visit waits for the
  /// hour inside the reveal; a revisit paints at once from the session (with
  /// the hour its games were derived with) and refreshes in place.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _starting = true;
    try {
      final snap = _gamesSession[_sessionKey];
      if (snap != null) {
        _games = snap.games;
        _gamesHourKnown = snap.hourKnown;
        _gamesLoaded = true;
      }
      final seam = gamesStates;
      if (seam != null) {
        _listenGames(() => seam,
            hourKnown: () => _loadStartHour == null || (_hour ?? 0) > 0);
      }
      final load = _loadStartHour;
      if (load == null) {
        if (seam != null) _gamesHourKnown = true;
        return;
      }
      final cachedHour = _startHourSession[_sessionKey];
      if (cachedHour != null) {
        _applyHour(cachedHour);
        return;
      }
      if (!_gamesLoaded) _hourPending = true;
      Future<int>.sync(load)
          .bounded('$owner: start hour', orElse: () => 0)
          .then((h) => h, onError: (Object e) {
        _logFailure(owner, 'start hour', e);
        return 0;
      }).then(_onHour);
    } finally {
      _starting = false;
    }
  }

  void dispose() {
    _disposed = true;
    _gamesSub?.cancel();
  }

  void _notify() {
    if (!_disposed && !_starting) onChanged();
  }

  void _onHour(int hour) {
    if (_disposed) return;
    if (hour > 0) _startHourSession[_sessionKey] = hour;
    _hourPending = false;
    _applyHour(hour);
    _notify();
  }

  void _applyHour(int hour) {
    _hour = hour;
    if (gamesStates != null) {
      // Fed games carry their own times: the hour applies to them as-is.
      _gamesHourKnown = hour > 0;
      return;
    }
    // Re-derive with this hour. Until the new games arrive the ones on
    // screen keep the hour they were derived with (no "0 PM" flash).
    _gamesSub?.cancel();
    _listenGames(
      () =>
          gamesFor?.call(hour) ??
          LeagueService.watchGames(sport, season, startHour: hour),
      hourKnown: () => hour > 0,
    );
  }

  void _listenGames(Stream<List<TournamentMatch>> Function() make,
      {required bool Function() hourKnown}) {
    _gamesSub = null;
    _gamesSub = _listenLogged<List<TournamentMatch>>(
      owner: owner,
      what: 'games feed',
      make: make,
      disposed: () => _disposed,
      onData: (games) {
        _games = games;
        _gamesHourKnown = hourKnown();
        _gamesLoaded = true;
        _gamesSession[_sessionKey] = (games: games, hourKnown: _gamesHourKnown);
        _notify();
      },
      onError: () {
        _gamesLoaded = true; // the last good games stay
        _notify();
      },
    );
  }
}

/// The league's own season-over flag (`/<sport>/<season>/Finished`) behind the
/// screens that drop their price arrows once the season is over (the Players
/// market, the player profile's stat strip, the Infinite profile's Fantasy
/// tab). One wiring, one behaviour:
///   • [ready] joins the owner's reveal gate — nothing paints the arrows
///     before the flag has answered (no arrow flashing in then out);
///   • an error (or a stream that cannot even be created — no Firebase app in
///     a widget test) is logged with debugPrint and opens the gate: "not
///     finished" unless an earlier real answer says otherwise (last good kept);
///   • the last answer is session-cached per `<sport>|<season>`, so a revisit
///     paints at once and the live stream then refreshes it in place.
class FantasySeasonFinishedFeed {
  FantasySeasonFinishedFeed({
    required this.sport,
    required this.season,
    required this.owner,
    required this.onChanged,
    this.finishedStates,
  });

  final String sport;
  final String season;
  final String owner;
  final VoidCallback onChanged;

  /// Test seam REPLACING `FantasyService.watchLeagueSeasonFinished`.
  final Stream<bool>? finishedStates;

  /// The last answer per `<sport>|<season>` (written by every real emission).
  static final Map<String, bool> _session = {};

  /// Clears the shared flag cache (sign-out hygiene, tests).
  static void clearSessionCache() => _session.clear();

  String get _sessionKey => '$sport|$season';

  bool _started = false;
  bool _starting = false;
  bool _disposed = false;
  bool _finished = false;
  bool _loaded = false;
  StreamSubscription<bool>? _sub;

  /// The season is over (false until the flag says so).
  bool get finished => _finished;

  /// The flag has answered (or failed) — joins the owner's reveal gate.
  bool get ready => _loaded;

  /// Seeds from the session and subscribes. Never notifies synchronously —
  /// the owner reads the seeded state right after it returns.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _starting = true;
    try {
      final seed = _session[_sessionKey];
      if (seed != null) {
        _finished = seed;
        _loaded = true;
      }
      _sub = _listenLogged<bool>(
        owner: owner,
        what: 'season finished feed',
        make: () =>
            finishedStates ??
            FantasyService.watchLeagueSeasonFinished(sport, season),
        disposed: () => _disposed,
        onData: (finished) {
          _session[_sessionKey] = finished;
          _finished = finished;
          _loaded = true;
          _notify();
        },
        onError: () {
          _loaded = true; // the last good answer stays; none = not finished
          _notify();
        },
      );
    } finally {
      _starting = false;
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
  }

  void _notify() {
    if (!_disposed && !_starting) onChanged();
  }
}
