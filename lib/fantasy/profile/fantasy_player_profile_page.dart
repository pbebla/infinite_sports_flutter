// The full-screen fantasy player profile (round 3, spec §4; owner mockup
// docs/superpowers/specs/assets/2026-10-29-fantasy-round3/
// mockup-player-profile.webp). Replaces the market's bottom sheet: hero
// (photo + gradient / initials over the team colour, team logo badge, name,
// "Team · Position"), watchlist star, stat strip (price + this week's move —
// or a muted "Final price" once the season is over — total pts, PPG, owned
// %), tabs Overview · Stats · Matches · Price, and a bottom bar — Add to
// Team / Remove under the market's exact rules (edits the hub's SHARED
// draft; saving stays on My Team) or "Open in Fantasy" when opened from
// outside the hub — plus "See full profile" for a linked account only.
//
// Data (all live streams, no RTDB get()): Config + schedule gameweeks (lock
// state + which weeks to listen to), Players (his live price), PlayerTotals,
// the league's season-over flag (`Finished`), every PriceChanges /
// PriceHistory week, his PlayerWeekStats (one listener per schedule
// gameweek), league rosters (season stats, shirt number, the account link —
// team AND name), league games (next game; startHour passed so legacy times
// never read "0 PM"), the Teams node (jersey colour) and, signed in, his own
// watchlist. ONE fade reveal once every feed has landed (the season-over
// flag included — no move line flashing in then out); any failing feed
// degrades to "no data" rather than holding the skeleton.
// The FantasyService/LeagueService feeds are session-cache seeded; the
// schedule (Config → gameweeks → his weekly records) and the league games
// (start hour → games) come from the shared feeds in
// fantasy_schedule_feed.dart, which cache them for the session too, so a
// revisit paints at once.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_schedule_feed.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/data/next_game.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_account_link.dart';
import 'package:infinite_sports_flutter/fantasy/data/player_week_stats.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_draft.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_hero.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_stat_strip.dart';
import 'package:infinite_sports_flutter/fantasy/profile/profile_tabs.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

/// The shape of [openFantasyPlayerProfile] — the seam type for every caller
/// that opens a profile (the hub's one opener, the match page's rows): tests
/// inject a recorder to assert the sport/season/name/draft/outside-hub flag.
typedef FantasyProfileOpener = Future<void> Function(
  BuildContext context, {
  required String sport,
  required String season,
  required String playerName,
  SquadDraftController? draft,
  bool fromOutsideHub,
});

/// Opens [playerName]'s fantasy profile full-screen. Inside the hub pass the
/// hub's shared [draft] (Add/Remove edit it); from outside the hub (the
/// Infinite profile's Fantasy tab, the match page) pass [fromOutsideHub] —
/// the primary button is then "Open in Fantasy".
Future<void> openFantasyPlayerProfile(
  BuildContext context, {
  required String sport,
  required String season,
  required String playerName,
  SquadDraftController? draft,
  bool fromOutsideHub = false,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FantasyPlayerProfilePage(
        sport: sport,
        season: season,
        playerName: playerName,
        draft: draft,
        fromOutsideHub: fromOutsideHub,
      ),
    ),
  );
}

class FantasyPlayerProfilePage extends StatefulWidget {
  const FantasyPlayerProfilePage({
    super.key,
    required this.sport,
    required this.season,
    required this.playerName,
    this.draft,
    this.fromOutsideHub = false,
    this.configStates,
    this.gameweekStates,
    this.playersStates,
    this.totalsStates,
    this.priceHistoryStates,
    this.priceChangeStates,
    this.weekStatsFor,
    this.rosterStates,
    this.gamesStates,
    this.leagueGamesFor,
    this.teamsStates,
    this.watchlistStates,
    this.seasonFinishedStates,
    this.selfUidOverride,
    this.setWatchlisted,
    this.loadLogoUrls,
    this.loadStartHour,
    this.openFullProfile,
    this.openInFantasy,
    this.nowUtc,
  });

  final String sport;
  final String season;

  /// The market player's name (his fantasy id).
  final String playerName;

  /// The hub's shared draft; null outside the hub (no Add/Remove).
  final SquadDraftController? draft;

  /// Opened from outside the hub: the primary button is "Open in Fantasy".
  final bool fromOutsideHub;

  // ── Test seams — null = the real FantasyService / LeagueService feeds ──
  final Stream<FantasyConfigState?>? configStates;

  /// Replaces the config-derived schedule gameweeks.
  final Stream<List<Gameweek>>? gameweekStates;
  final Stream<List<FantasyPlayer>>? playersStates;
  final Stream<Map<String, FantasyPlayerTotals>?>? totalsStates;
  final Stream<Map<int, Map<String, int>>>? priceHistoryStates;
  final Stream<Map<int, Map<String, int>>>? priceChangeStates;
  final Stream<Map<int, PlayerWeekStats>> Function(List<int> weeks)?
      weekStatsFor;
  final Stream<Map<String, List<TournamentPlayer>>>? rosterStates;
  final Stream<List<TournamentMatch>>? gamesStates;

  /// Replaces ONLY `LeagueService.watchGames(sport, season, startHour:)`:
  /// the start hour → games wiring and its session caches still run.
  /// Ignored when [gamesStates] is given.
  final Stream<List<TournamentMatch>> Function(int startHour)? leagueGamesFor;
  final Stream<List<TournamentTeam>>? teamsStates;
  final Stream<Set<String>>? watchlistStates;

  /// The league's `Finished` flag (`FantasyService.watchLeagueSeasonFinished`).
  final Stream<bool>? seasonFinishedStates;

  /// '' = signed out (the star hides).
  final String? selfUidOverride;
  final Future<void> Function(String name, bool on)? setWatchlisted;
  final Future<Map<String, String>> Function()? loadLogoUrls;

  /// The season's legacy start hour (`LeagueService.getStartHour`; 0 =
  /// absent or a failed read). Null with a [gamesStates] seam = treated as
  /// known (the fed games carry their own times).
  final Future<int> Function()? loadStartHour;
  final void Function(BuildContext context, String uid, String name)?
      openFullProfile;
  /// "Open in Fantasy" (from outside the hub): receives the hub route that
  /// lands on the Players tab and then THIS player's profile
  /// ([fantasyRouteForPlayer]). null = pushes [fantasyHubPageRoute] for it.
  final void Function(BuildContext context, FantasyHubRoute route)?
      openInFantasy;
  final DateTime Function()? nowUtc;

  // ── Session caches (instant revisits) for the feeds the services don't
  // cache themselves: the team colours here, keyed `<sport>|<season>`; the
  // derived schedule and the league games + their start hour live in the
  // shared feeds (fantasy_schedule_feed.dart).
  static final Map<String, Map<String, Color>> _teamColorsSession = {};

  /// Clears the page's session caches (sign-out hygiene, tests) — including
  /// the shared schedule / games / season-over caches it paints from.
  static void clearSessionCaches() {
    _teamColorsSession.clear();
    FantasyScheduleFeed.clearSessionCache();
    FantasyLeagueGamesFeed.clearSessionCache();
    FantasySeasonFinishedFeed.clearSessionCache();
  }

  @override
  State<FantasyPlayerProfilePage> createState() =>
      _FantasyPlayerProfilePageState();
}

/// The profile's status-bar style: ONLY the status bar (icon brightness on
/// Android, bar brightness on iOS, transparent like the app's M3 AppBars) —
/// never the system navigation bar, which the presets `.light`/`.dark`
/// would force black on Android < 15.
SystemUiOverlayStyle profileStatusBarStyle({required bool lightIcons}) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness: lightIcons ? Brightness.dark : Brightness.light,
    );

/// The hero's height: ~42% of the screen, clamped for tiny/huge screens.
double _heroHeightFor(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.42).clamp(260.0, 380.0);

/// Height of the row the floating back/star buttons sit in, below the status
/// bar: 6 px gap + 48 px IconButton + 6 px gap.
const double _kButtonRowHeight = 60;

class _FantasyPlayerProfilePageState extends State<FantasyPlayerProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  int _tabIndex = 0;

  /// The page scroll; [_pastHero] flips once the hero's bottom edge scrolls
  /// up into the back/star row — the solid pinned bar then backs the
  /// status bar and both buttons, so content never shows under them
  /// (release report #3), and the status-bar icons follow the theme.
  final ScrollController _scroll = ScrollController();
  bool _pastHero = false;

  /// Config (lock state) → schedule gameweeks (which weeks to listen to) →
  /// his PlayerWeekStats, one listener per schedule gameweek — the shared
  /// wiring (fantasy_schedule_feed.dart): lock-hour / week-number
  /// resubscribe, a removed Config clears the schedule, errors logged with
  /// the last good value kept, the schedule session-cached.
  late final FantasyScheduleFeed<Map<int, PlayerWeekStats>> _schedule =
      FantasyScheduleFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyPlayerProfilePage',
    onChanged: _repaint,
    configStates: widget.configStates,
    gameweekStates: widget.gameweekStates,
    weekFeed: (weeks) =>
        widget.weekStatsFor?.call(weeks) ??
        FantasyService.watchPlayerWeekStatsFor(
            widget.sport, widget.season, widget.playerName, weeks),
    weekLabel: 'week stats feed',
    // Weeks up to the current gameweek only (the feed's trim) — same clock
    // as the page.
    nowUtc: widget.nowUtc,
  );

  /// The league games for the Next line, derived with the season start hour
  /// (the shared sibling feed: the hour joins the first visit's reveal gate,
  /// a revisit paints from the session, and an unknown hour drops a derived
  /// time — never "0 PM", not even on a revisit after a failed read).
  late final FantasyLeagueGamesFeed _leagueGames = FantasyLeagueGamesFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyPlayerProfilePage',
    onChanged: _repaint,
    gamesStates: widget.gamesStates,
    gamesFor: widget.leagueGamesFor,
    loadStartHour: widget.loadStartHour,
  );

  /// The league's season-over flag (shared feed): its answer joins the reveal
  /// gate so the move line never flashes in and out; once true the stat strip
  /// shows "Final price" instead of the move.
  late final FantasySeasonFinishedFeed _seasonFinished =
      FantasySeasonFinishedFeed(
    sport: widget.sport,
    season: widget.season,
    owner: 'FantasyPlayerProfilePage',
    onChanged: _repaint,
    finishedStates: widget.seasonFinishedStates,
  );

  FantasyConfigState? get _config => _schedule.config;
  List<Gameweek>? get _gameweeks => _schedule.gameweeks;
  Map<int, PlayerWeekStats>? get _weeks => _schedule.weekData;

  List<FantasyPlayer>? _players;
  Map<String, FantasyPlayerTotals>? _totals;
  bool _totalsLoaded = false;
  Map<int, Map<String, int>>? _priceHistory;
  Map<int, Map<String, int>>? _priceChanges;
  Map<String, List<TournamentPlayer>> _rosters = const {};
  bool _rostersLoaded = false;
  Map<String, Color> _teamColors = const {};
  bool _teamsLoaded = false;
  Set<String> _watchlist = const {};
  bool _watchlistLoaded = false;

  /// The tapped star's state until the watchlist stream echoes it.
  bool? _starOverride;
  Map<String, String> _logoUrls = const {};

  StreamSubscription<List<FantasyPlayer>>? _playersSub;
  StreamSubscription<Map<String, FantasyPlayerTotals>?>? _totalsSub;
  StreamSubscription<Map<int, Map<String, int>>>? _historySub;
  StreamSubscription<Map<int, Map<String, int>>>? _changesSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rostersSub;
  StreamSubscription<List<TournamentTeam>>? _teamsSub;
  StreamSubscription<Set<String>>? _watchlistSub;
  Timer? _lockTicker;

  String get _sessionKey => '${widget.sport}|${widget.season}';

  DateTime get _nowUtc => (widget.nowUtc ?? () => DateTime.now().toUtc())();

  // Best-effort (leaderboards convention): widget tests never touch
  // FirebaseAuth — a missing seam degrades to "signed out", not a throw.
  late final String _selfUid = () {
    final override = widget.selfUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }();

  bool get _ready =>
      _schedule.configLoaded &&
      _schedule.gameweeks != null &&
      _players != null &&
      _totalsLoaded &&
      _priceHistory != null &&
      _priceChanges != null &&
      _schedule.weekLoaded &&
      _seasonFinished.ready &&
      _rostersLoaded &&
      _leagueGames.ready &&
      _teamsLoaded &&
      _watchlistLoaded;

  void _repaint() {
    if (mounted) setState(() {});
  }

  bool get _showsDraftAction => !widget.fromOutsideHub && widget.draft != null;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index != _tabIndex && mounted) {
        setState(() => _tabIndex = _tabs.index);
      }
    });
    _scroll.addListener(() {
      if (!mounted || !_scroll.hasClients) return;
      final past = _scroll.offset >
          _heroHeightFor(context) -
              MediaQuery.paddingOf(context).top -
              _kButtonRowHeight;
      if (past != _pastHero) setState(() => _pastHero = past);
    });
    _seedFromSession();
    _schedule.start();
    _seasonFinished.start();
    _subscribeMarketFeeds();
    _subscribeLeagueFeeds();
    _subscribeWatchlist();
    (widget.loadLogoUrls ??
            () => LeagueService.leagueLogoUrls(widget.sport, widget.season))()
        .then((urls) {
      if (mounted) setState(() => _logoUrls = urls);
    }, onError: (Object _) {});
    if (_showsDraftAction) {
      // Keeps the editable/locked flip honest around the deadline (the
      // market's cadence).
      _lockTicker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Seeds the team colours from this session (real feed only); the
  /// schedule and the games seed themselves (the shared feeds).
  void _seedFromSession() {
    final key = _sessionKey;
    if (widget.teamsStates == null &&
        FantasyPlayerProfilePage._teamColorsSession[key] != null) {
      _teamColors = FantasyPlayerProfilePage._teamColorsSession[key]!;
      _teamsLoaded = true;
    }
  }

  void _subscribeMarketFeeds() {
    _playersSub = (widget.playersStates ??
            FantasyService.watchPlayers(widget.sport, widget.season))
        .listen((p) {
      if (mounted) setState(() => _players = p);
    }, onError: (Object _) {
      if (mounted) setState(() => _players ??= const []);
    });
    _totalsSub = (widget.totalsStates ??
            FantasyService.watchPlayerTotals(widget.sport, widget.season))
        .listen((t) {
      if (!mounted) return;
      setState(() {
        _totals = t;
        _totalsLoaded = true;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _totalsLoaded = true);
    });
    _historySub = (widget.priceHistoryStates ??
            FantasyService.watchPriceHistory(widget.sport, widget.season))
        .listen((h) {
      if (mounted) setState(() => _priceHistory = h);
    }, onError: (Object _) {
      if (mounted) setState(() => _priceHistory ??= const {});
    });
    _changesSub = (widget.priceChangeStates ??
            FantasyService.watchAllPriceChanges(widget.sport, widget.season))
        .listen((c) {
      if (mounted) setState(() => _priceChanges = c);
    }, onError: (Object _) {
      if (mounted) setState(() => _priceChanges ??= const {});
    });
  }

  void _subscribeLeagueFeeds() {
    _rostersSub = (widget.rosterStates ??
            LeagueService.watchRosters(widget.sport, widget.season))
        .listen((r) {
      if (!mounted) return;
      setState(() {
        _rosters = r;
        _rostersLoaded = true;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _rostersLoaded = true);
    });

    _teamsSub = (widget.teamsStates ??
            LeagueService.watchStandings(widget.sport, widget.season, const {}))
        .listen((teams) {
      if (!mounted) return;
      final colors = <String, Color>{
        for (final t in teams)
          if (t.homeColor != null) t.name.trim(): t.homeColor!,
      };
      if (widget.teamsStates == null) {
        FantasyPlayerProfilePage._teamColorsSession[_sessionKey] = colors;
      }
      setState(() {
        _teamColors = colors;
        _teamsLoaded = true;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _teamsLoaded = true);
    });

    _leagueGames.start();
  }

  void _subscribeWatchlist() {
    if (_selfUid.isEmpty) {
      _watchlistLoaded = true; // signed out: no star, nothing to wait for
      return;
    }
    _watchlistSub = (widget.watchlistStates ??
            FantasyService.watchWatchlist(
                widget.sport, widget.season, _selfUid))
        .listen((names) {
      if (!mounted) return;
      setState(() {
        _watchlist = names;
        _watchlistLoaded = true;
        _starOverride = null;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _watchlistLoaded = true);
    });
  }

  @override
  void dispose() {
    _schedule.dispose();
    _seasonFinished.dispose();
    _leagueGames.dispose();
    _playersSub?.cancel();
    _totalsSub?.cancel();
    _historySub?.cancel();
    _changesSub?.cancel();
    _rostersSub?.cancel();
    _teamsSub?.cancel();
    _watchlistSub?.cancel();
    _lockTicker?.cancel();
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  bool get _starred => _starOverride ?? _watchlist.contains(widget.playerName);

  Future<void> _toggleStar() async {
    final uid = _selfUid;
    if (uid.isEmpty) return;
    final on = !_starred;
    setState(() => _starOverride = on);
    try {
      await (widget.setWatchlisted ??
          (name, on) => FantasyService.setWatchlisted(
              widget.sport, widget.season, uid, name, on))(
        widget.playerName,
        on,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _starOverride = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text("Couldn't update your watchlist — try again.")));
    }
  }

  void _openFullProfile(String uid, String name) {
    final open = widget.openFullProfile;
    if (open != null) {
      open(context, uid, name);
      return;
    }
    openPlayerProfileById(context, uid: uid, name: name);
  }

  /// "Open in Fantasy": the hub on its Players tab, which then pushes THIS
  /// player's profile (with the hub's shared draft) once it is ready.
  void _openInFantasy() {
    final route = fantasyRouteForPlayer(
      sport: widget.sport,
      season: widget.season,
      playerName: widget.playerName,
    );
    final open = widget.openInFantasy;
    if (open != null) {
      open(context, route);
      return;
    }
    Navigator.push(context, fantasyHubPageRoute(route));
  }

  /// open / locked / unknown — unknown = the schedule read failed (review 6,
  /// I2): Add/Remove stay off and say the deadline can't be checked.
  SquadEditState get _editState {
    final config = _config;
    if (config == null) return SquadEditState.locked;
    return squadEditState(
      lockOverride: config.lockOverride,
      gameweeks: _gameweeks ?? const [],
      nowUtc: _nowUtc,
      scheduleUnknown: _schedule.scheduleUnknown,
    );
  }

  bool get _editable => _editState == SquadEditState.open;

  // ── Build ───────────────────────────────────────────────────────────────

  FantasyPlayer? get _player {
    for (final p in _players ?? const <FantasyPlayer>[]) {
      if (p.name == widget.playerName) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ready = _ready;
    final player = ready ? _player : null;
    final Widget body;
    if (!ready) {
      body = const _ProfileSkeleton(key: ValueKey('fantasy_profile_skeleton'));
    } else if (player == null) {
      body = const _ProfileMissing(key: ValueKey('fantasy_profile_missing'));
    } else {
      body = _content(context, player);
    }
    final top = MediaQuery.paddingOf(context).top;
    final starred = _starred;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Light status-bar icons while the hero's dark top scrim is under them;
    // once it scrolls away (or there is no hero) they follow the theme.
    final onHero = player != null && !_pastHero;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: profileStatusBarStyle(lightIcons: onHero || isDark),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                child: body,
              ),
            ),
            // Solid pinned bar once the hero has scrolled up to the button
            // row: backs the status bar AND the back/star buttons, so the
            // stat strip / tabs never run under the clock or the buttons
            // (release report #3 — the star used to cover "Owned").
            Positioned(
              key: const ValueKey('profile_pinned_bar'),
              top: 0,
              left: 0,
              right: 0,
              height: top + _kButtonRowHeight,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pastHero ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: DecoratedBox(
                    key: const ValueKey('profile_bar_fill'),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: top + 6,
              left: 8,
              child: _HeroIconButton(
                key: const ValueKey('profile_back'),
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            // Signed out → no star at all.
            if (_selfUid.isNotEmpty && player != null)
              Positioned(
                top: top + 6,
                right: 8,
                child: _HeroIconButton(
                  key: const ValueKey('profile_star'),
                  icon:
                      starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: starred ? TournamentColors.gold : Colors.white,
                  tooltip:
                      starred ? 'Remove from watchlist' : 'Add to watchlist',
                  onPressed: _toggleStar,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, FantasyPlayer player) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final model = buildProfileModel(
      player: player,
      totals: _totals?[player.name],
      weeks: _weeks ?? const {},
      priceHistory: _priceHistory ?? const {},
      priceChanges: _priceChanges ?? const {},
    );
    final roster = rosterRowFor(player, _rosters);
    final uid = uidForFantasyPlayer(player, _rosters);
    final next = nextGameForTeam(
        player.teamName, _leagueGames.games, _nowUtc.toLocal());
    final teamColor = _teamColors[player.teamName.trim()] ??
        fallbackTeamColor(player.teamName);
    final heroHeight = _heroHeightFor(context);

    final Widget tab = switch (_tabIndex) {
      1 => ProfileStatsTab(model: model),
      2 => ProfileMatchesTab(model: model),
      3 => ProfilePriceTab(model: model),
      _ => ProfileOverviewTab(
          model: model,
          season: widget.season,
          nextGameText: next == null
              ? null
              : nextGameText(next,
                  startHourKnown: _leagueGames.startHourKnown),
          seasonStats: roster,
        ),
    };

    return Column(
      key: const ValueKey('fantasy_profile_ready'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('profile_scroll'),
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FantasyProfileHero(
                  player: player,
                  teamColor: teamColor,
                  height: heroHeight,
                  logoUrl: _logoUrls[player.teamName.trim()],
                  shirtNumber: roster?.number,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: FantasyProfileStatStrip(
                    model: model,
                    seasonFinished: _seasonFinished.finished,
                  ),
                ),
                const SizedBox(height: 6),
                TabBar(
                  controller: _tabs,
                  labelColor: accent,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: accent,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(
                        key: ValueKey('profile_tab_overview'),
                        text: 'Overview'),
                    Tab(key: ValueKey('profile_tab_stats'), text: 'Stats'),
                    Tab(key: ValueKey('profile_tab_matches'), text: 'Matches'),
                    Tab(key: ValueKey('profile_tab_price'), text: 'Price'),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: tab,
                ),
              ],
            ),
          ),
        ),
        _bottomBar(context, player, uid),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, FantasyPlayer player, String? uid) {
    final scheme = Theme.of(context).colorScheme;
    final draft = widget.draft;
    final Widget? primary;
    if (widget.fromOutsideHub) {
      primary = _PrimaryButton(
        buttonKey: const ValueKey('profile_open_in_fantasy'),
        label: 'Open in Fantasy',
        onPressed: _openInFantasy,
      );
    } else if (draft != null) {
      primary = ListenableBuilder(
        listenable: draft,
        builder: (context, _) => _DraftAction(
          player: player,
          draft: draft,
          editable: _editable,
          deadlineUnknown: _editState == SquadEditState.unknown,
          // Given up retrying (re-review 6b, item 2): "Try again" here.
          onRetrySchedule: _schedule.scheduleRetry == FantasyFeedRetry.gaveUp
              ? _schedule.restart
              : null,
        ),
      );
    } else {
      primary = null;
    }
    if (primary == null && uid == null) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('profile_bottom_bar'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 8 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (primary != null) primary,
          if (uid != null)
            TextButton.icon(
              key: const ValueKey('profile_full_profile'),
              onPressed: () => _openFullProfile(uid, player.name),
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('See full profile'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// The big rounded primary button (mockup: the gold "Add to Team").
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.subdued = false,
  });

  /// Lands on the FilledButton itself (tests read its onPressed).
  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  /// The Remove face: a neutral surface instead of the accent.
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FilledButton(
      key: buttonKey,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor:
            subdued ? scheme.surfaceContainerHigh : fantasyAccent(context),
        // Gold needs dark text; light mode's primary red takes onPrimary.
        foregroundColor: subdued
            ? scheme.onSurface
            : (isDark ? Colors.black : scheme.onPrimary),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Add to Team / Remove under the market's exact rules (market_logic), with
/// the reason line when neither is available — edits the shared draft only.
class _DraftAction extends StatelessWidget {
  const _DraftAction({
    required this.player,
    required this.draft,
    required this.editable,
    this.deadlineUnknown = false,
    this.onRetrySchedule,
  });

  final FantasyPlayer player;
  final SquadDraftController draft;
  final bool editable;
  final bool deadlineUnknown;
  final VoidCallback? onRetrySchedule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final availability = marketAddState(
      player: player,
      slots: draft.slots,
      slotPicks: draft.picks,
      // The shared draft's money (FPL selling, spec §4).
      remainingTenths: draft.remainingTenths,
      priceOf: draft.addCostOf,
      editable: editable,
      unplaced: draft.unplaced,
      deadlineUnknown: deadlineUnknown,
    );
    final inSquad = availability == MarketAddAvailability.inSquad;
    final addable = availability == MarketAddAvailability.addable;
    final retry = availability == MarketAddAvailability.deadlineUnknown
        ? onRetrySchedule
        : null;
    final reason = availability == MarketAddAvailability.deadlineUnknown &&
            retry != null
        ? "Couldn't check the deadline."
        : marketAddReason(availability, player.position);
    // An owned baseline player's Remove says what he was bought at and
    // what selling him banks; anyone bought this week has no such line.
    // Only once the draft's money is real (never a stale sell price).
    final showSale = inSquad && draft.moneyReady;
    final bought = showSale ? draft.boughtPriceOf(player.name) : null;
    final sells = showSale ? draft.sellPriceOf(player.name) : null;

    void onPressed() {
      if (inSquad) {
        final message = draft.removePlayer(player.name);
        if (message != null && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      } else {
        draft.addPlayer(player);
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrimaryButton(
          buttonKey: ValueKey(inSquad ? 'profile_remove' : 'profile_add'),
          label: inSquad ? 'Remove from Team' : 'Add to Team',
          subdued: inSquad,
          onPressed: addable || inSquad ? onPressed : null,
        ),
        if (bought != null && sells != null) ...[
          const SizedBox(height: 6),
          Text(
            sellsForLine(boughtTenths: bought, sellsTenths: sells),
            key: const ValueKey('profile_sells_for'),
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (reason != null) ...[
          const SizedBox(height: 6),
          Text(
            reason,
            key: const ValueKey('profile_add_reason'),
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: availability == MarketAddAvailability.unaffordable
                  ? fantasyDownRed(context)
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (retry != null)
            TextButton(
              key: const ValueKey('profile_deadline_retry'),
              onPressed: retry,
              child: const Text('Try again'),
            ),
        ] else if (draft.dirty) ...[
          const SizedBox(height: 6),
          Text(
            'Changes save from the My Team tab.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A round dark-scrim icon button floating over the hero: white (or gold)
/// on a translucent black disc reads on any photo, light or dark theme.
class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color, size: 24),
        onPressed: onPressed,
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final heroHeight = _heroHeightFor(context);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(width: double.infinity, height: heroHeight, radius: 0),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonBox(width: double.infinity, height: 72, radius: 16),
                SizedBox(height: 18),
                SkeletonLines(count: 2),
                SizedBox(height: 18),
                SkeletonBox(width: double.infinity, height: 170, radius: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMissing extends StatelessWidget {
  const _ProfileMissing({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined,
                size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              "This player isn't in the fantasy market anymore.",
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
