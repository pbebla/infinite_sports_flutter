import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/bounded_read.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart' show SharePng;
import 'package:infinite_sports_flutter/misc/share_profile_service.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart'
    show catchPercentage;
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/award.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/flagfootballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_source.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_tab.dart';
import 'package:infinite_sports_flutter/profile/profile_hero.dart';
import 'package:infinite_sports_flutter/profile/profile_tab.dart';
import 'package:infinite_sports_flutter/profile/stats_tab.dart';
import 'package:infinite_sports_flutter/widgets/share_profile_card.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/misc/fresh_follow.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

// ─── Human-readable labels for stat keys (shared across ProfileTab + StatsTab) ─
const Map<String, String> _statLabel = {
  'games': 'Games',
  'goals': 'Goals',
  'assists': 'Assists',
  'saves': 'Saves',
  'cleanSheets': 'Clean Sheets',
  'dpl': 'DPL',
  'points': 'Points',
  'rebounds': 'Rebounds',
  'threePointers': '3PM',
  'twoPointers': '2PM',
  'freeThrows': 'FTM',
  'passTouchdowns': 'Pass TDs',
  'receivingTouchdowns': 'Rec TDs',
  'receptions': 'Receptions',
  'catchPercentage': 'Catch %',
  'interceptions': 'INTs',
  'flagPulls': 'Flag Pulls',
  'sacks': 'Sacks',
  'passBreakups': 'PBUs',
};

/// Profile stat values render as plain counts except Catch % (L6.1),
/// which carries a % suffix.
String formatProfileStatValue(String key, num value) =>
    key == 'catchPercentage' ? '$value%' : value.toString();

/// The full tabbed player profile page.
///
/// Loads data from Firebase via [getProfileData] (mirrors the old
/// PlayerPage.getPlayerData logic, extended with tournament history).
///
/// Callers that previously used `PlayerPage(uid: uid)` now get this page
/// via the thin `PlayerPage` wrapper in playerpage.dart.
///
/// For players without a linked account, use [ProfilePage.limited].
class ProfilePage extends StatefulWidget {
  final String uid;

  /// When true, this instance was constructed via [ProfilePage.limited].
  /// Only a name is available — no Firebase load is performed.
  final bool _isLimited;
  final String _limitedName;

  /// Test seam: replaces the Firebase profile load when non-null (mirrors
  /// the insiderStream seam on ProfileTab). Loaded fields keep their
  /// defaults, so tests can pump the tab scaffold without Firebase.
  final Future<int> Function()? loadOverride;

  /// Test seam for phase 2 (career), mirroring [loadOverride]: when set, the
  /// career-dependent sections stay in their loading state until this future
  /// resolves. Only observed when [loadOverride] is also set; without it,
  /// [loadOverride] alone resolves the full page (both phases at once).
  final Future<void> Function()? careerLoadOverride;

  /// Test seams for the Fantasy tab (round 3): the fantasy feeds and the
  /// tab's navigation. null = the real FantasyService / LeagueService feeds.
  /// A limited profile never has a Fantasy tab, so it takes none.
  final FantasyProfileSeams? fantasySeams;

  /// Test seam (second review, Important 1): replaces the career reads —
  /// the profile node / team nodes / TournamentsPlayed, tournament bundles
  /// and AFC seasons + rosters — so the real load AND the in-place reload
  /// run without Firebase. null = Firebase.
  final ProfileCareerSources? careerSources;

  /// Test seam: replaces the system share sheet behind the app-bar Share
  /// icon (it receives the PNG, the caption and the icon's iPad popover
  /// anchor). null = the real share sheet.
  final SharePng? share;

  const ProfilePage(
      {super.key,
      required this.uid,
      this.loadOverride,
      this.careerLoadOverride,
      this.careerSources,
      this.fantasySeams,
      this.share})
      : _isLimited = false,
        _limitedName = '';

  /// Stub for Task 8: renders just the name with "not linked" message.
  const ProfilePage.limited({super.key, required String name})
      : uid = '',
        _isLimited = true,
        _limitedName = name,
        loadOverride = null,
        careerLoadOverride = null,
        careerSources = null,
        fantasySeams = null,
        share = null;

  /// Clears the session career cache (mirrors
  /// TournamentService.clearProfileUrlCache). Call after a sign-out or when
  /// profile data must be refetched; tests call it between cases.
  static void clearCareerCache() => _careerCache.clear();

  /// Whether a newer server value at [path] can change a career built from
  /// [reads] (the normalized paths it read — second review, Important 1:
  /// this player's own profile node, team nodes, AFC rosters and
  /// tournaments, not every roster in the app). A newer value AT a read
  /// path, ABOVE one (an ancestor another screen follows) or BELOW one
  /// counts.
  @visibleForTesting
  static bool careerReadsAffected(Set<String> reads, String path) {
    if (path.isEmpty) return false;
    for (final r in reads) {
      if (r == path || r.startsWith('$path/') || path.startsWith('$r/')) {
        return true;
      }
    }
    return false;
  }

  /// Session cache drop (survey list B): a newer value drops only the
  /// cached careers that were built from it, so their next visit re-reads.
  /// App lifetime; started by the first profile (lazy static).
  static final VoidCallback _careerCacheFollow =
      FreshReads.onNewerUnder('', (path, _) {
    for (final uid in _careerReads.keys.toList()) {
      if (careerReadsAffected(_careerReads[uid]!, path)) {
        _careerReads.remove(uid);
        _careerCache.remove(uid);
      }
    }
  });

  /// Minimum time between two in-place reloads of an open profile (a live
  /// game changes Line Ups every few seconds; the profile must not thrash).
  static const Duration kProfileReloadGap = Duration(seconds: 2);

  /// Test seam: the league goals of the first Futsal season competition in
  /// [uid]'s CACHED career (null = not cached / none).
  @visibleForTesting
  static num? debugCachedLeagueGoals(String uid) =>
      _leagueGoals(_careerCache[uid]?.competitions);

  /// Test seam: the same, from the most recently opened profile's SHOWN
  /// career.
  @visibleForTesting
  static num? debugShownLeagueGoals() => _leagueGoals(_debugShown?.call());

  static List<CompetitionStats> Function()? _debugShown;

  static num? _leagueGoals(List<CompetitionStats>? competitions) {
    if (competitions == null) return null;
    for (final c in competitions) {
      if (c.label.contains('· Season')) return c.stats['goals'];
    }
    return null;
  }

  /// Test seam: the cached career's sizes for [uid] (null = not cached).
  @visibleForTesting
  static ({int stints, int competitions, int appearances})? debugCachedCounts(
      String uid) {
    final c = _careerCache[uid];
    if (c == null) return null;
    return (
      stints: c.stints.length,
      competitions: c.competitions.length,
      appearances: c.tournamentAppearances.length,
    );
  }

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

// ─────────────────────────────────────────────────────────────────────────────

/// Index of the Fantasy tab when it is shown (Profile, Career, Fantasy).
const int _kFantasyTabIndex = 2;

// TickerProviderStateMixin (not Single…): a late Fantasy-tab decision swaps
// in a second TabController while the first is still alive for the fade.
class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  /// The Fantasy tab's data (null on limited profiles / without a uid).
  FantasyProfileSource? _fantasy;

  /// Whether the TabBar currently has the third (Fantasy) tab.
  bool _showFantasyTab = false;

  /// True while the Fantasy tab is the selected one (the Share action — which
  /// only knows the Profile / Career cards — hides).
  bool _fantasyTabSelected = false;

  /// Controllers replaced by a late tab-count change: kept alive until the
  /// page disposes so the outgoing TabBar can finish its cross-fade.
  final List<TabController> _retiredTabControllers = [];

  // ── Raw loaded data ──────────────────────────────────────────────────────
  String _firstName = '';
  String _lastName = '';
  String _profileUrl = '';
  Map<dynamic, dynamic> _information = {};
  Map<dynamic, dynamic> _rawPlayed = {};
  List<Award> _awards = [];

  /// Phase 2 (career) done — career-dependent sections swap their skeletons
  /// for real content once this flips.
  bool _careerLoaded = false;
  /// Set when any bounded career read timed out (offline). A degraded
  /// career is shown for this visit but NEVER cached — the next open
  /// refetches instead of restoring an empty career for the session.
  bool _careerDegraded = false;

  // ── Share state ──────────────────────────────────────────────────────────
  /// Tracks which competition is currently selected in the Career tab, so the
  /// Share button on that tab knows which card to build.
  int _selectedStatsIndex = 0;

  // sport → seasonNum → (teamName, teamColor, Player)
  Map<String, Map<String, (String, Color, Player)>> _tableEntries = {};
  Map<String, String> _sportPositions = {};

  /// Normalized database paths the shown career was built from (second
  /// review, Important 1): only a newer value at one of them (or above /
  /// below one) reloads the profile.
  Set<String> _readPaths = {};

  // ── Built data structures ───────────────────────────────────────────────
  List<ParticipationStint> _stints = [];
  List<CompetitionStats> _competitions = [];
  ParticipationStint? _current;
  Color? _teamColor;
  List<({String label, String value})> _headlineStats = [];
  String? _currentTeamNumber;
  String? _currentStatsLabel;

  /// Stops the in-place repaint follower (fresh reads, Task 4).
  VoidCallback? _stopNewerFollow;
  Timer? _repaintDebounce;

  /// One reload at a time; a newer value during one queues exactly one
  /// more; reloads at most every [ProfilePage.kProfileReloadGap] (second review,
  /// Important 1 / Minor 4).
  late final CoalescedRefresh _reload =
      CoalescedRefresh(_repaintInPlace, minGap: ProfilePage.kProfileReloadGap);

  /// Fresh reads (Task 4, survey list C): while this profile is open, a
  /// newer server value for a path THIS career was built from (or its own
  /// profile node) reloads it IN PLACE — identity and career are rebuilt
  /// into fresh collections and swapped in with one setState; scroll and
  /// tab are kept. Debounced (300 ms) and coalesced.
  void _onNewerPath(String path, Object? _) {
    final own = normalizeFreshPath(profileNodePathFor(widget.uid));
    final mine = path == own || path.startsWith('$own/');
    final building = _building;
    final affects = mine ||
        ProfilePage.careerReadsAffected(_readPaths, path) ||
        (building != null &&
            ProfilePage.careerReadsAffected(building.readPaths, path));
    if (!affects) return;
    _careerCache.remove(widget.uid);
    _careerReads.remove(widget.uid);
    if (!_careerLoaded) {
      // Final round, item 1: a newer value during the FIRST load (the
      // career is not on screen yet) is remembered; one reload runs right
      // after the first commit (_loadCareer).
      _newerDuringFirstLoad = true;
      return;
    }
    _scheduleReload();
  }

  /// The same debounced, coalesced path every reload takes.
  void _scheduleReload() {
    _repaintDebounce?.cancel();
    _repaintDebounce =
        Timer(const Duration(milliseconds: 300), _reload.request);
  }

  /// The career build in progress (its read paths count for newer values
  /// that arrive while it runs).
  _CareerWork? _building;

  /// A newer value arrived before the first career appeared.
  bool _newerDuringFirstLoad = false;

  /// Test seam target (ProfilePage.debugShownLeagueGoals).
  List<CompetitionStats> _shownCompetitions() => _competitions;

  Future<void> _repaintInPlace() async {
    if (!mounted || !_careerLoaded) return;
    final read = await _readIdentity();
    final id = read.identity;
    // A failed or timed-out identity read keeps what is on screen.
    if (!mounted || id == null) return;
    await _loadCareer(identity: id); // one setState at its end
  }

  @override
  void initState() {
    super.initState();
    ProfilePage._careerCacheFollow;
    ProfilePage._debugShown = _shownCompetitions;
    if (!widget._isLimited &&
        widget.uid.trim().isNotEmpty &&
        widget.loadOverride == null) {
      _stopNewerFollow = FreshReads.onNewerUnder('', _onNewerPath);
    }
    // The Fantasy tab (round 3) exists only on full (uid) profiles. start()
    // runs BEFORE the listener is attached so a synchronous (session-cached)
    // decision never calls setState inside initState — it is simply read
    // here, and the TabController is built with the right length at once.
    if (!widget._isLimited && widget.uid.trim().isNotEmpty) {
      final fantasy =
          FantasyProfileSource(uid: widget.uid, seams: widget.fantasySeams)
            ..start();
      fantasy.addListener(_onFantasyChanged);
      _fantasy = fantasy;
      _showFantasyTab = fantasy.hasTab;
    }
    _tabController = _newTabController(0);
  }

  TabController _newTabController(int initialIndex) {
    final length = _showFantasyTab ? 3 : 2;
    return TabController(
      length: length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, length - 1),
    )..addListener(_onTabTick);
  }

  /// The Share action hides on the Fantasy tab; rebuild only when that flips
  /// (this fires on every animation tick of a tab change).
  void _onTabTick() {
    final selected =
        _showFantasyTab && _tabController.index == _kFantasyTabIndex;
    if (selected != _fantasyTabSelected && mounted) {
      setState(() => _fantasyTabSelected = selected);
    }
  }

  void _onFantasyChanged() {
    final fantasy = _fantasy;
    if (!mounted || fantasy == null || !fantasy.decided) return;
    _applyFantasyTab(fantasy.hasTab);
  }

  /// Gives the TabBar / TabBarView the new tab count. Before the page has
  /// revealed this is invisible (the skeleton is up); after it, the TabBar
  /// cross-fades between its two- and three-tab faces (see build) and the
  /// selected tab is kept. No-op when the count is unchanged.
  void _applyFantasyTab(bool show) {
    if (show == _showFantasyTab || !mounted) return;
    final old = _tabController;
    old.removeListener(_onTabTick);
    _retiredTabControllers.add(old);
    _showFantasyTab = show;
    _tabController = _newTabController(old.index);
    setState(() {
      _fantasyTabSelected =
          show && _tabController.index == _kFantasyTabIndex;
    });
  }

  @override
  void dispose() {
    _stopNewerFollow?.call();
    _repaintDebounce?.cancel();
    _reload.dispose();
    if (ProfilePage._debugShown == _shownCompetitions) {
      ProfilePage._debugShown = null;
    }
    _fantasy
      ?..removeListener(_onFantasyChanged)
      ..dispose();
    _tabController.dispose();
    for (final c in _retiredTabControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Helper: extract league player stats ───────────────────────────────

  Future<(String, Color, Player)> _extractHelper(_CareerWork w,
      String sport, String season, String team) async {
    // Logos are cosmetic: a read with no answer (offline) never holds the
    // career reveal — the stint just has no logo.
    await getAllTeamLogo()
        .bounded('ProfilePage: team logos', orElse: () {});
    // Color extraction is deferred — we only decode the CURRENT stint's logo
    // once, after w.current is determined. Use a placeholder here so we don't
    // download + decode every logo for every season.
    const Color placeholder = Color(0xFFD00000);
    (String, Color, Player) data;
    if (sport == 'Basketball') {
      data = ('', placeholder, BasketballPlayer());
      final entries = basketballLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (w.firstName.isEmpty && info.name.contains(' ')) {
              w.firstName = info.name.split(' ')[0];
              w.lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    } else if (sport == 'Futsal') {
      data = ('', placeholder, FutsalPlayer());
      final entries = futsalLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (w.firstName.isEmpty && info.name.contains(' ')) {
              w.firstName = info.name.split(' ')[0];
              w.lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    } else {
      // Flag Football
      data = ('', placeholder, FlagFootballPlayer());
      final entries = flagFootballLineups[season]?[team]?.entries;
      if (entries != null) {
        for (final entry in entries) {
          final info = entry.value;
          if (info.uid == widget.uid) {
            final logoUrl =
                (teamLogos[sport]?[season]?[team])?.toString() ?? '';
            info.teamPath = logoUrl;
            if (w.firstName.isEmpty && info.name.contains(' ')) {
              w.firstName = info.name.split(' ')[0];
              w.lastName = info.name.split(' ').sublist(1).join(' ');
            }
            data = (team, placeholder, info);
            break;
          }
        }
      }
    }
    return data;
  }

  Future<(String, Color, Player)> _extractPlayerStats(_CareerWork w,
      String sport, String season, String team) async {
    var val = await _extractHelper(w, sport, season, team);
    if (val.$1 != '') return val;

    // Try other teams in case player transferred
    if (sport == 'Basketball') {
      for (final other in (basketballLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(w, sport, season, other);
        if (val.$1 != '') return val;
      }
    } else if (sport == 'Futsal') {
      for (final other in (futsalLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(w, sport, season, other);
        if (val.$1 != '') return val;
      }
    } else if (sport == 'Flag Football') {
      for (final other in (flagFootballLineups[season] ?? {}).keys) {
        if (other == team) continue;
        val = await _extractHelper(w, sport, season, other);
        if (val.$1 != '') return val;
      }
    }
    return val;
  }

  Future<void> _extractAFCStats(_CareerWork w) async {
    try {
      // Bounded one-shot reads (bounded_read.dart): offline, no answer =
      // no AFC stints, never a held career reveal.
      final src = widget.careerSources;
      w.readPaths.add('AFC San Jose/Seasons');
      final seasons = await (src != null
              ? src.afcSeasons()
              : getSoccerSeasons('AFC San Jose'))
          .bounded('ProfilePage: AFC seasons');
      // Each season's roster read is independent — fetch them concurrently.
      await Future.wait(seasons.map((season) async {
        w.readPaths.add('AFC San Jose/Seasons/$season/Roster');
        final roster = await (src != null
                ? src.afcRoster(season)
                : getSoccerRoster('AFC San Jose', season))
            .bounded(
            'ProfilePage: AFC roster $season',
            orElse: () => <String, SoccerPlayer>{});
        roster.forEach((name, info) {
          if (info.uid == widget.uid) {
            w.tableEntries['AFC San Jose'] ??= {};
            w.tableEntries['AFC San Jose']![season] =
                (season, Colors.white, info);
          }
        });
      }));
    } on TimeoutException {
      w.degraded = true;
    } catch (_) {
      // A swallowed failure: a RELOAD with it does not commit.
      w.failed = true;
    }
  }

  // ─── Stat map builders ──────────────────────────────────────────────────

  Map<String, num> _futsalStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int goals = 0, assists = 0, saves = 0;
    for (final e in seasons.values) {
      final p = e.$3 as FutsalPlayer;
      goals += p.goals;
      assists += p.assists;
      saves += p.saves;
    }
    return {'goals': goals, 'assists': assists, 'saves': saves};
  }

  Map<String, num> _basketballStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int points = 0, rebounds = 0, threePointers = 0, twoPointers = 0,
        freeThrows = 0;
    for (final e in seasons.values) {
      final p = e.$3 as BasketballPlayer;
      points += p.total;
      rebounds += p.rebounds;
      threePointers += p.threePoints;
      twoPointers += p.twoPoints;
      freeThrows += p.onePoint;
    }
    return {
      'points': points,
      'rebounds': rebounds,
      'threePointers': threePointers,
      'twoPointers': twoPointers,
      'freeThrows': freeThrows,
    };
  }

  Map<String, num> _flagFootballStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int receptions = 0, receptionMisses = 0, receivingTDs = 0, passTDs = 0,
        interceptions = 0, flagPulls = 0, sacks = 0, passBreakups = 0;
    for (final e in seasons.values) {
      final p = e.$3 as FlagFootballPlayer;
      receptions += p.receptions;
      receptionMisses += p.receptionMisses;
      receivingTDs += p.receivingTouchdowns;
      passTDs += p.passingTouchdowns;
      interceptions += p.interceptions;
      flagPulls += p.flagPulls;
      sacks += p.sacks;
      passBreakups += p.passBreakups;
    }
    // Career Catch % (L6.1) from career REC/RECMiss. No minTargets gate —
    // the player's own profile shows their real rate; null (zero targets)
    // omits the row entirely instead of showing a misleading 0%.
    final catchPct = catchPercentage(receptions, receptionMisses);
    return {
      'receptions': receptions,
      if (catchPct != null) 'catchPercentage': catchPct,
      'receivingTouchdowns': receivingTDs,
      'passTouchdowns': passTDs,
      'interceptions': interceptions,
      'flagPulls': flagPulls,
      'sacks': sacks,
      'passBreakups': passBreakups,
    };
  }

  Map<String, num> _soccerStatMap(
      Map<String, (String, Color, Player)> seasons) {
    int goals = 0, assists = 0, saves = 0;
    for (final e in seasons.values) {
      final p = e.$3 as SoccerPlayer;
      goals += p.goals;
      assists += p.assists;
      saves += p.saves;
    }
    return {'goals': goals, 'assists': assists, 'saves': saves};
  }

  Map<String, num> _tournamentPlayerStatMap(TournamentPlayer p) {
    final m = <String, num>{};
    if (p.goals > 0) m['goals'] = p.goals;
    if (p.assists > 0) m['assists'] = p.assists;
    if (p.saves > 0) m['saves'] = p.saves;
    if (p.cleanSheets > 0) m['cleanSheets'] = p.cleanSheets;
    if (p.dpl > 0) m['dpl'] = p.dpl;
    return m;
  }

  // ─── Team logo URL helper ────────────────────────────────────────────────

  String _teamLogoUrl(String sport, String season, String team) {
    try {
      if (sport == 'AFC San Jose') {
        final afcVal = teamLogos['AFC San Jose'];
        if (afcVal is String) return afcVal;
        return '';
      }
      final url = teamLogos[sport]?[season]?[team];
      return url?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ─── Main data load ──────────────────────────────────────────────────────

  List<({String label, String value})> _buildHeadlineStats(_CareerWork w) {
    if (w.current == null) return [];

    Map<String, num> statMap;
    String sport;
    String position;

    if (w.current!.isTournament) {
      final ta = _findTournamentAppearance(w, w.current!.scopeId);
      if (ta == null) return [];
      statMap = _tournamentPlayerStatMap(ta.player);
      sport = ta.sport;
      position = ta.position;
    } else {
      sport = w.current!.sport;
      position = w.current!.position;
      final seasons = w.tableEntries[sport];
      if (seasons == null || seasons.isEmpty) return [];
      // Show only the current season stats, not career totals
      final currentSeasonEntry = seasons[w.current!.label];
      if (currentSeasonEntry != null) {
        statMap = _buildStatMapForSingleEntry(sport, currentSeasonEntry.$3);
      } else {
        statMap = _buildStatMapForSport(sport, seasons);
      }
    }

    final group = positionGroup(sport, position);
    final priority = profileStatPriority(sport, group);

    // Priority stats first, then any other non-zero stat; never padded
    // with a "—" column (release report #2) — two stats → two columns.
    return [
      for (final key in pickHeadlineStatKeys(priority, statMap))
        (
          label: _statLabel[key] ?? key,
          value: formatProfileStatValue(key, statMap[key]!),
        ),
    ];
  }

  /// Build stat map from a single Player entry (for current season card).
  Map<String, num> _buildStatMapForSingleEntry(String sport, Player player) {
    switch (sport) {
      case 'Futsal':
        final p = player as FutsalPlayer;
        return {'goals': p.goals, 'assists': p.assists, 'saves': p.saves};
      case 'Basketball':
        final p = player as BasketballPlayer;
        return {
          'points': p.total,
          'rebounds': p.rebounds,
          'threePointers': p.threePoints,
          'twoPointers': p.twoPoints,
          'freeThrows': p.onePoint,
        };
      case 'Flag Football':
        final p = player as FlagFootballPlayer;
        // Season Catch % (L6.1) — same no-gate/no-data semantics as the
        // career map above.
        final catchPct = catchPercentage(p.receptions, p.receptionMisses);
        return {
          'receptions': p.receptions,
          if (catchPct != null) 'catchPercentage': catchPct,
          'receivingTouchdowns': p.receivingTouchdowns,
          'passTouchdowns': p.passingTouchdowns,
          'interceptions': p.interceptions,
          'flagPulls': p.flagPulls,
          'sacks': p.sacks,
          'passBreakups': p.passBreakups,
        };
      case 'AFC San Jose':
        final p = player as SoccerPlayer;
        return {'goals': p.goals, 'assists': p.assists, 'saves': p.saves};
      default:
        return {};
    }
  }

  Map<String, num> _buildStatMapForSport(
      String sport, Map<String, (String, Color, Player)> seasons) {
    switch (sport) {
      case 'Futsal':
        return _futsalStatMap(seasons);
      case 'Basketball':
        return _basketballStatMap(seasons);
      case 'Flag Football':
        return _flagFootballStatMap(seasons);
      case 'AFC San Jose':
        return _soccerStatMap(seasons);
      default:
        return _futsalStatMap(seasons);
    }
  }

  _TournamentAppearance? _findTournamentAppearance(
      _CareerWork w, String tournamentId) {
    return w.appearances
        .where((ta) => ta.tournamentId == tournamentId)
        .firstOrNull;
  }

  // The shown career's tournament appearances (swapped in whole by
  // _applyCareer — a reload never appends to it).
  List<_TournamentAppearance> _tournamentAppearancesCache = [];

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── Limited (no-account) state ────────────────────────────────────────
    if (widget._isLimited) {
      return Scaffold(
        appBar: _appBar(context),
        body: Column(
          children: [
            ProfileHero(
              photoUrl: '',
              fullName: widget._limitedName,
              teamColor: null,
            ),
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    "This player isn't linked to an account yet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Full profile ─────────────────────────────────────────────────────
    return Scaffold(
      appBar: _appBar(context),
      body: FutureBuilder<int>(
        future: _loadOnce(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _ProfileSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Could not load profile. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            );
          }

          final fullName =
              '$_firstName $_lastName'.trim().isNotEmpty
                  ? '$_firstName $_lastName'.trim()
                  : 'Player';

          return Column(
            children: [
              // Fixed hero above the tabs
              ProfileHero(
                photoUrl: _profileUrl,
                fullName: fullName,
                teamColor: _teamColor,
              ),
              // Tab bar — PR #10: Stats + Career merged into one Career tab
              // (the enhanced StatsTab). Round 3 adds Fantasy as a third tab
              // for a fantasy player / manager. Its presence is decided
              // before this is first built; a late decision cross-fades the
              // two faces (keyed by tab count) instead of jumping.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: TabBar(
                  key: ValueKey('profile_tabbar_${_tabController.length}'),
                  controller: _tabController,
                  tabs: [
                    const Tab(text: 'Profile'),
                    const Tab(text: 'Career'),
                    if (_showFantasyTab) const Tab(text: 'Fantasy'),
                  ],
                ),
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ProfileTab(
                      uid: widget.uid,
                      information: _information,
                      awards: _awards,
                      careerLoading: !_careerLoaded,
                      current: _current,
                      currentTeamNumber: _currentTeamNumber,
                      currentStatsLabel: _currentStatsLabel,
                      currentStats: _headlineStats,
                    ),
                    // The skeleton→content swap fades (~250ms) so the reveal
                    // feels deliberate, not popped-in.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _careerLoaded
                          ? StatsTab(
                              key: const ValueKey('career-content'),
                              competitions: _competitions,
                              initialIndex: _selectedStatsIndex,
                              onCompetitionChanged: (i) =>
                                  setState(() => _selectedStatsIndex = i),
                            )
                          // Career data still loading — placeholders keep the
                          // tab from flashing "No stats yet.".
                          : ListView(
                              key: const ValueKey('career-skeleton'),
                              padding: const EdgeInsets.all(16),
                              children: const [
                                SkeletonBox(width: 200, height: 20),
                                SizedBox(height: 16),
                                SkeletonBox(
                                    width: double.infinity, height: 110),
                                SizedBox(height: 12),
                                SkeletonBox(
                                    width: double.infinity, height: 110),
                              ],
                            ),
                    ),
                    if (_showFantasyTab)
                      FantasyProfileTab(
                        source: _fantasy!,
                        // The profile owner's real name ('' until known) —
                        // the squad viewer's title fallback.
                        personName: '$_firstName $_lastName'.trim(),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: const Text('Profile'),
      // No Share on the Fantasy tab: the share cards only cover the Profile
      // (trophy cabinet) and Career (stats) tabs.
      actions: (widget._isLimited || _fantasyTabSelected)
          ? null
          : [
              // Builder: the iPad share popover anchors to THIS icon.
              Builder(
                builder: (buttonContext) => IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: 'Share',
                  onPressed: () => _onShareTap(buttonContext),
                ),
              ),
            ],
    );
  }

  /// Builds and shares the appropriate profile card for the active tab.
  /// [context] is the tapped Share icon's own context (the iPad popover
  /// anchor — never the page's).
  Future<void> _onShareTap(BuildContext context) async {
    final fullName =
        '$_firstName $_lastName'.trim().isNotEmpty
            ? '$_firstName $_lastName'.trim()
            : 'Player';

    final tab = _tabController.index;

    if (tab == 0) {
      // ── Profile tab → Trophy Cabinet card ──────────────────────────────
      final currentLabel = _current != null
          ? '${_current!.team} · ${_current!.sport}'
          : '';
      final n = _awards.length;
      await shareProfileCard(
        context,
        ShareProfileCabinetCard(
          name: fullName,
          photoUrl: _profileUrl,
          currentLabel: currentLabel,
          awards: _awards,
        ),
        shareText:
            "$fullName's trophy cabinet — $n ${n == 1 ? 'trophy' : 'trophies'}"
            ' on Infinite Sports',
        share: widget.share,
      );
    } else {
      // ── Career tab → Stats card for currently selected competition ──────
      if (_competitions.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('No stats to share yet.')),
        );
        return;
      }
      final idx = _selectedStatsIndex.clamp(0, _competitions.length - 1);
      final comp = _competitions[idx];

      // Build ordered stat rows the same way StatsTab does.
      final group = positionGroup(comp.sport, comp.position);
      final priority = profileStatPriority(comp.sport, group);
      final orderedKeys = <String>[
        for (final k in priority)
          if (comp.stats.containsKey(k)) k,
        for (final k in comp.stats.keys)
          if (!priority.contains(k)) k,
      ];
      final statRows = orderedKeys
          .take(5)
          .map((k) => (
                label: _statLabel[k] ?? k,
                value: formatProfileStatValue(k, comp.stats[k]!),
              ))
          .toList();

      await shareProfileCard(
        context,
        ShareProfileStatsCard(
          name: fullName,
          photoUrl: _profileUrl,
          competitionLabel: comp.label,
          stats: statRows,
        ),
        shareText:
            "$fullName · ${comp.label} — Infinite Sports",
        share: widget.share,
      );
    }
  }

  // Ensure the profile load runs only once even if FutureBuilder rebuilds.
  // The future gates ONLY phase 1 (identity) — phase 2 (career) runs behind
  // it and fills the career-dependent sections in via setState when done.
  Future<int>? _loadFuture;
  Future<int> _loadOnce() {
    _loadFuture ??= _fantasy == null ? _doLoad() : _doLoadThenFantasy();
    return _loadFuture!;
  }

  /// Identity first, then the Fantasy tab's decision — bounded: the TabBar's
  /// tab count is decided BEFORE the TabBar is built, so the reveal never
  /// shows two tabs and then three. A decision that misses the grace window
  /// still lands later (a faded tab swap); an already-cached one costs
  /// nothing.
  Future<int> _doLoadThenFantasy() async {
    final value = await _doLoad();
    final fantasy = _fantasy;
    if (fantasy != null && !fantasy.decided) {
      await fantasy.decision.timeout(kFantasyTabDecisionGrace, onTimeout: () {});
    }
    if (fantasy != null && fantasy.decided) _applyFantasyTab(fantasy.hasTab);
    return value;
  }

  Future<int> _doLoad() async {
    // Session cache: a completed career load for this uid renders the FULL
    // page from the first frame — no skeletons, no reveal needed. Phase 1's
    // single cheap Users/{uid} read still refreshes identity behind it.
    final cached = _careerCache[widget.uid];
    if (cached != null) {
      _restoreCareer(cached);
      _careerLoaded = true;
      if (widget.loadOverride != null) return widget.loadOverride!();
      unawaited(_refreshIdentity());
      return 1;
    }
    if (widget.loadOverride != null) {
      final v = await widget.loadOverride!();
      if (widget.careerLoadOverride != null) {
        unawaited(_runCareerOverride());
      } else {
        // loadOverride alone resolves both phases at once — tests using only
        // this seam expect the full page as soon as the future completes.
        _careerLoaded = true;
      }
      return v;
    }
    _tournamentAppearancesCache = [];
    // Phase 1 (fast): identity — the only thing gating first paint.
    await _loadIdentity();
    // Phase 2 (slow): career — deliberately not awaited.
    unawaited(_loadCareer());
    return 1;
  }

  Future<void> _runCareerOverride() async {
    await widget.careerLoadOverride!();
    // Mirrors the real phase-2 completion, cache write included, so tests
    // can exercise the cache-hit render path through the seams alone.
    _careerCache[widget.uid] = _snapshotCareer();
    if (!mounted) return;
    setState(() => _careerLoaded = true);
  }

  /// Cache-hit path only: refresh name/photo/info quietly and keep the
  /// cached snapshot's identity fresh for the next visit.
  Future<void> _refreshIdentity() async {
    await _loadIdentity();
    if (_careerCache.containsKey(widget.uid)) {
      _careerCache[widget.uid] = _snapshotCareer();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _restoreCareer(_CareerSnapshot snap) {
    _firstName = snap.firstName;
    _lastName = snap.lastName;
    _profileUrl = snap.profileUrl;
    _information = snap.information;
    _awards = snap.awards;
    _tableEntries = Map.of(snap.tableEntries);
    _sportPositions = Map.of(snap.sportPositions);
    _tournamentAppearancesCache = List.of(snap.tournamentAppearances);
    _readPaths = Set.of(_careerReads[widget.uid] ?? const <String>{});
    _stints = snap.stints;
    _competitions = snap.competitions;
    _current = snap.current;
    _teamColor = snap.teamColor;
    _headlineStats = snap.headlineStats;
    _currentTeamNumber = snap.currentTeamNumber;
    _currentStatsLabel = snap.currentStatsLabel;
  }

  _CareerSnapshot _snapshotCareer() => _CareerSnapshot(
        firstName: _firstName,
        lastName: _lastName,
        profileUrl: _profileUrl,
        information: _information,
        awards: List.of(_awards),
        tableEntries: Map.of(_tableEntries),
        sportPositions: Map.of(_sportPositions),
        tournamentAppearances: List.of(_tournamentAppearancesCache),
        stints: _stints,
        competitions: _competitions,
        current: _current,
        teamColor: _teamColor,
        headlineStats: _headlineStats,
        currentTeamNumber: _currentTeamNumber,
        currentStatsLabel: _currentStatsLabel,
      );

  // ─── Phase 1: identity ────────────────────────────────────────────────────

  /// Reads a value: through [ProfilePage.careerSources] in tests, else a
  /// refreshing read (fresh reads, Task 4).
  Future<Object?> _readValue(String path) async {
    final src = widget.careerSources;
    if (src != null) return src.read(normalizeFreshPath(path));
    return (await refreshingOnce(FirebaseDatabase.instance.ref(path)))
        .snapshot
        .value;
  }

  /// Phase 1, read only: the profile node as an [_Identity] (null = failed
  /// read; `timedOut` = no answer within the bound).
  Future<({_Identity? identity, bool timedOut})> _readIdentity() async {
    // DB lockdown B1: Users/{uid} stays for the viewer's OWN profile (its
    // owner may always read it); any other uid reads the PublicProfiles
    // mirror, which carries the exact same keys this page uses (First/Last
    // Name, ProfileUrl, Information, Played, Awards).
    final Map rawUser;
    try {
      // Bounded (bounded_read.dart): this read gates the page's first paint
      // and a cold offline read may never answer. No answer — or a failed
      // read — keeps whatever identity is already on screen (a cache-hit
      // refresh must never blank the cached name); a first visit then shows
      // the empty page instead of a skeleton forever.
      final value = await _readValue(profileNodePathFor(widget.uid))
          .bounded('ProfilePage: profile node');
      rawUser = value as Map? ?? {};
    } on TimeoutException {
      return (identity: null, timedOut: true);
    } catch (_) {
      return (identity: null, timedOut: false);
    }
    // Awards live inside the profile node already fetched above, so the
    // trophy cabinet renders with phase 1 at no extra read.
    var awards = <Award>[];
    try {
      if (rawUser['Awards'] is Map) {
        awards = (rawUser['Awards'] as Map)
            .entries
            .where((e) => e.value is Map)
            .map((e) => Award.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ))
            .toList();
      }
    } catch (_) {
      awards = [];
    }
    return (
      identity: _Identity(
        firstName: (rawUser['First Name'] ?? '').toString(),
        lastName: (rawUser['Last Name'] ?? '').toString(),
        profileUrl: (rawUser['ProfileUrl'] ?? '').toString(),
        information: (rawUser['Information'] is Map)
            ? rawUser['Information'] as Map
            : {},
        rawPlayed: (rawUser['Played'] is Map) ? rawUser['Played'] as Map : {},
        awards: rawUser['Awards'] is Map ? awards : null,
      ),
      timedOut: false,
    );
  }

  void _applyIdentity(_Identity id) {
    _firstName = id.firstName;
    _lastName = id.lastName;
    _profileUrl = id.profileUrl;
    _information = id.information;
    // Kept for phase 2's league-appearance fetches.
    _rawPlayed = id.rawPlayed;
    final awards = id.awards;
    if (awards != null) _awards = awards;
  }

  Future<void> _loadIdentity() async {
    final read = await _readIdentity();
    if (read.timedOut) _careerDegraded = true;
    final id = read.identity;
    if (id != null) _applyIdentity(id);
  }

  // ─── Phase 2: career ──────────────────────────────────────────────────────

  /// Phase 2 (and every in-place reload): the whole career is built into a
  /// FRESH [_CareerWork] — never appended to what is on screen — and swapped
  /// in (with [identity], when a reload re-read it) in ONE setState (second
  /// review, Important 1). A failed build keeps what is shown.
  Future<void> _loadCareer({_Identity? identity}) async {
    final w = _CareerWork(
      rawPlayed: identity?.rawPlayed ?? _rawPlayed,
      information: identity?.information ?? _information,
      firstName: identity?.firstName ?? _firstName,
      lastName: identity?.lastName ?? _lastName,
    )..degraded = identity == null ? _careerDegraded : false;
    w.readPaths.add(normalizeFreshPath(profileNodePathFor(widget.uid)));
    _building = w;
    var ok = true;
    Future<Color?>? colorFuture;
    Color? color;
    try {
      // The three data groups are independent — run them concurrently.
      await Future.wait([
        _loadLeagueAppearances(w),
        _extractAFCStats(w),
        _loadTournamentAppearances(w),
      ]);
      await _buildCareer(w);
      // Team color joins the same reveal: the logo decode gets a short grace
      // window, then we reveal with the default tint and never flip it later
      // — a late tint change is exactly the staged look the single reveal
      // exists to avoid.
      colorFuture = _resolveTeamColor(w);
      color = await colorFuture.timeout(
          const Duration(milliseconds: 300), onTimeout: () => null);
    } catch (_) {
      ok = false;
    }
    // Final round, item 2: a RELOAD commits only when every read it needed
    // succeeded; otherwise the career on screen stays as it was (an error is
    // not a fact) and the next newer value or the next visit tries again.
    // The FIRST load keeps its existing behaviour (shows what it has).
    final isReload = identity != null;
    if (isReload && (!ok || w.failed || w.degraded)) {
      if (identical(_building, w)) _building = null;
      return;
    }
    void apply() {
      if (identity != null) _applyIdentity(identity);
      if (ok) _applyCareer(w, color);
      _careerDegraded = w.degraded;
      _careerLoaded = true;
    }

    // Single reveal / single swap: career sections, hero stats and tint all
    // land in this one setState.
    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
    if (identical(_building, w)) _building = null;
    if (_newerDuringFirstLoad) {
      // Final round, item 1: the first career is already older than the
      // server — do not cache it; reload once, in place (the reload caches).
      _newerDuringFirstLoad = false;
      _careerCache.remove(widget.uid);
      _careerReads.remove(widget.uid);
      if (mounted) _scheduleReload();
      return;
    }
    if (!ok || _careerDegraded) {
      // A failed or timed-out (offline) career is shown but never cached —
      // the next visit refetches instead of restoring an empty career.
      _careerCache.remove(widget.uid);
      _careerReads.remove(widget.uid);
      return;
    }
    _careerCache[widget.uid] = _snapshotCareer();
    _careerReads[widget.uid] = Set.of(_readPaths);
    if (color == null && colorFuture != null) {
      // Too late for this visit's reveal, but cache hits render the tint
      // from their first frame.
      unawaited(colorFuture.then((c) {
        final snap = _careerCache[widget.uid];
        if (c != null && snap != null) snap.teamColor = c;
      }));
    }
  }

  /// Swaps a finished [_CareerWork] in as the shown career.
  void _applyCareer(_CareerWork w, Color? color) {
    _firstName = w.firstName;
    _lastName = w.lastName;
    _tableEntries = w.tableEntries;
    _sportPositions = w.sportPositions;
    _tournamentAppearancesCache = w.appearances;
    _readPaths = w.readPaths;
    _stints = w.stints;
    _current = w.current;
    _currentTeamNumber = w.currentTeamNumber;
    _competitions = w.competitions;
    _currentStatsLabel = w.currentStatsLabel;
    _headlineStats = w.headlineStats;
    if (color != null) _teamColor = color;
  }

  Future<void> _loadLeagueAppearances(_CareerWork w) async {
    try {
      final tasks = <Future<void>>[];
      for (final entry in w.rawPlayed.entries) {
        final sport = entry.key.toString();
        final seasons = entry.value;
        if (seasons is! Map) continue;
        for (final entry2 in seasons.entries) {
          final seasonRaw = entry2.key.toString();
          final team = entry2.value.toString();
          final parts = seasonRaw.split(' ');
          final seasonNum = parts.last;
          if (sport == 'Futsal' ||
              sport == 'Basketball' ||
              sport == 'Flag Football') {
            w.sportPositions[sport] =
                (w.information['${sport}Position'] ?? '').toString();
            tasks.add(_loadLeagueSeason(w, sport, seasonNum, team));
          }
        }
      }
      // Distinct (sport, season) pairs write distinct lineup-cache keys
      // (futsalLineups[season] etc. in utility.dart), so the fetches are
      // safe to run in parallel instead of the old sequential forEach.
      await Future.wait(tasks);
    } catch (_) {
      // A swallowed failure: a RELOAD with it does not commit.
      w.failed = true;
    }
  }

  Future<void> _loadLeagueSeason(_CareerWork w,
      String sport, String seasonNum, String team) async {
    try {
      // Targeted read first: phase 1's Played map already names the player's
      // team per (sport, season), so one team node is enough — the shared
      // getAll* caches download the whole season's Line Ups (every team,
      // every player) just to extract this one row.
      // (A team read with no answer — offline — throws, skipping the
      // whole-season fallback too: it would hang the same way.)
      final targeted = await _extractFromTeamNode(w, sport, seasonNum, team);
      if (targeted != null) {
        w.tableEntries[sport] ??= {};
        w.tableEntries[sport]![seasonNum] = targeted;
        return;
      }
      // Fallback (team renamed / legacy data / player transferred): the old
      // whole-season fetch through the shared lineup caches, which also
      // searches the season's other teams. Bounded like every career read.
      final what = 'ProfilePage: $sport $seasonNum Line Ups';
      w.readPaths.add('$sport/$seasonNum/Line Ups');
      if (sport == 'Futsal') {
        await getAllFutsalLineUps(seasonNum).bounded(what);
      } else if (sport == 'Basketball') {
        await getAllBasketballLineUps(seasonNum).bounded(what);
      } else {
        await getAllFlagFootballLineUps(seasonNum).bounded(what);
      }
      w.tableEntries[sport] ??= {};
      w.tableEntries[sport]![seasonNum] =
          await _extractPlayerStats(w, sport, seasonNum, team);
    } on TimeoutException {
      w.degraded = true;
    } catch (_) {
      // A swallowed failure: a RELOAD with it does not commit.
      w.failed = true;
    }
  }

  /// Reads `/<Sport>/<season>/Line Ups/<team>` (one team's node) and pulls
  /// this player's row out of it. Returns null when the node is missing or
  /// the player isn't on it — callers fall back to the whole-season path. A
  /// read with no answer (offline, bounded) THROWS [TimeoutException] so the
  /// caller skips that fallback too.
  Future<(String, Color, Player)?> _extractFromTeamNode(_CareerWork w,
      String sport, String season, String team) async {
    try {
      w.readPaths.add('$sport/$season/Line Ups/$team');
      final node = await _readValue('/$sport/$season/Line Ups/$team')
          .bounded('ProfilePage: $sport $season $team');
      if (node is! Map) return null;
      for (final e in node.entries) {
        final info = e.value;
        if (info is! Map) continue;
        if ((info['UID'] ?? '') != widget.uid) continue;
        await getAllTeamLogo()
            .bounded('ProfilePage: team logos', orElse: () {});
        final logoUrl = (teamLogos[sport]?[season]?[team])?.toString() ?? '';
        final player =
            _parseLeaguePlayer(sport, e.key.toString(), info, logoUrl);
        if (w.firstName.isEmpty && player.name.contains(' ')) {
          w.firstName = player.name.split(' ')[0];
          w.lastName = player.name.split(' ').sublist(1).join(' ');
        }
        // Same placeholder color as _extractHelper — the real decode is the
        // current stint's only, in _resolveTeamColor.
        return (team, const Color(0xFFD00000), player);
      }
      return null;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Profile-local player parsing for a targeted team read. Mirrors the
  /// field mapping in utility.dart's `getAll<Sport>LineUps` parsers — those
  /// stay untouched because other screens depend on their season caches.
  Player _parseLeaguePlayer(
      String sport, String name, Map info, String logoUrl) {
    if (sport == 'Basketball') {
      final p = BasketballPlayer();
      p.number = (info['number'] ?? '0').toString();
      p.uid = info['UID'] ?? '0';
      p.name = name;
      p.onePoint = info['OnePoint'] ?? 0;
      p.twoPoints = info['TwoPoints'] ?? 0;
      p.threePoints = info['ThreePoints'] ?? 0;
      p.total = info['Total'] ??
          p.onePoint + (p.twoPoints * 2) + (p.threePoints * 3);
      p.misses = info['Misses'] ?? 0;
      p.rebounds = info['Rebounds'] ?? 0;
      p.getPercentage();
      p.teamPath = logoUrl;
      return p;
    }
    if (sport == 'Flag Football') {
      final p = FlagFootballPlayer();
      p.name = name;
      p.number = info['number']?.toString() ?? '0';
      p.uid = info['UID'] ?? '0';
      // P4 FF stat-key fix (as in getAllFlagFootballLineUps): the Manager
      // writes SHORT keys; the legacy long names still read for
      // pre-Manager seasons.
      p.receptions = info['REC'] ?? info['Receptions'] ?? 0;
      p.receivingTouchdowns =
          info['RECTD'] ?? info['Receiving Touchdowns'] ?? 0;
      p.receptionMisses = info['RECMiss'] ?? info['Receiver Miss'] ?? 0;
      p.passingTouchdowns =
          info['PassTD'] ?? info['Passing Touchdowns'] ?? 0;
      p.qbCompletions = info['QBComp'] ?? info['QB Completions'] ?? 0;
      p.qbIncompletions = info['QBInc'] ?? info['QB Incomplete'] ?? 0;
      p.interceptions = info['INT'] ?? info['Interceptions'] ?? 0;
      p.flagPulls = info['FP'] ?? info['Flag Pulls'] ?? 0;
      p.passBreakups = info['PBU'] ?? info['Pass Breakups'] ?? 0;
      p.sacks = info['Sack'] ?? info['Sacks'] ?? 0;
      p.passingInterceptions = info['PassINT'] ?? 0;
      p.rushingTouchdowns = info['RushTD'] ?? 0;
      p.interceptionTouchdowns = info['INTTD'] ?? 0;
      p.pointAfterTouchdownMakes = info['PAT1'] ?? 0;
      p.pointAfterTouchdownMisses = info['PAT1Miss'] ?? 0;
      p.twoPointConversions = info['TwoPT'] ?? 0;
      p.getCompletionPercentage();
      p.getCatchRate();
      p.teamPath = logoUrl;
      return p;
    }
    // Futsal
    final p = FutsalPlayer();
    p.assists = info['Assists'] ?? 0;
    p.goals = info['Goals'] ?? 0;
    p.number = info['number'] ?? '0';
    p.saves = info['Saves'] ?? 0;
    p.uid = info['UID'] ?? '0';
    p.name = name;
    p.teamPath = logoUrl;
    return p;
  }

  Future<void> _loadTournamentAppearances(_CareerWork w) async {
    try {
      // TournamentsPlayed index (written by the Manager when a roster entry
      // is linked): Users/<uid>/TournamentsPlayed/<tournamentId>: true.
      // A missing/empty node means no appearances — roster entries without a
      // linked UID never matched the old all-tournaments scan either — so
      // nothing at all is fetched in that (common) case.
      // Lockdown B1: own profile reads Users, visited profiles read the
      // PublicProfiles mirror (TournamentsPlayed is mirrored verbatim).
      // Bounded like every career read: no answer = no appearances.
      final idxPath = '${profileNodePathFor(widget.uid)}/TournamentsPlayed';
      w.readPaths.add(normalizeFreshPath(idxPath));
      final index = await _readValue(idxPath)
          .bounded('ProfilePage: TournamentsPlayed');
      if (index is! Map) return;
      // Fetch only the indexed tournaments, concurrently. Ids that no longer
      // resolve (deleted tournaments) are skipped.
      await Future.wait(index.keys.map((id) async {
        try {
          // One whole-node read per tournament (iOS overlapping-get() fix —
          // see TournamentService.getTournamentBundle). Parallel ACROSS
          // tournaments stays fine: different ids never overlap.
          w.readPaths.add('Tournaments/$id');
          final src = widget.careerSources;
          final bundle = await (src != null
                  ? src.tournamentBundle(id.toString())
                  : TournamentService.getTournamentBundle(id.toString()))
              .bounded('ProfilePage: tournament $id');
          final tournament = bundle.tournament;
          if (tournament == null) return;
          final teams = bundle.teams;
          // Photos never gate: no answer keeps the rosters as they are.
          final rosters = src != null
              ? bundle.rosters
              : await TournamentService.enrichRosterPhotos(bundle.rosters)
                  .bounded('ProfilePage: tournament $id photos',
                      orElse: () => bundle.rosters);
          for (final entry in rosters.entries) {
            for (final player in entry.value) {
              if (player.uid == widget.uid) {
                w.appearances.add(_TournamentAppearance(
                  tournamentId: tournament.id,
                  tournamentName: tournament.name,
                  sport: tournament.sport,
                  edition: tournament.edition,
                  finished: tournament.finished,
                  logoUrl: tournament.logoUrl ?? '',
                  teamName: player.teamName,
                  teamLogoUrl: teams[entry.key]?.logoUrl ?? '',
                  position: player.position ?? '',
                  number: player.number ?? '',
                  player: player,
                ));
                break;
              }
            }
          }
        } catch (_) {
          w.failed = true; // a RELOAD with it does not commit
        }
      }));
    } on TimeoutException {
      w.degraded = true;
    } catch (_) {
      // A swallowed failure: a RELOAD with it does not commit.
      w.failed = true;
    }
  }

  Future<void> _buildCareer(_CareerWork w) async {
    // ── 6. Build stints ──────────────────────────────────────────────────
    final stints = <ParticipationStint>[];

    // Memoize getCurrentSeason results — avoids one await per (sport × season).
    final Map<String, String> cachedCurrentSeason = {};

    for (final sportEntry in w.tableEntries.entries) {
      final sport = sportEntry.key;

      // Fetch current season ONCE per sport.
      if (!cachedCurrentSeason.containsKey(sport)) {
        try {
          cachedCurrentSeason[sport] = await (sport == 'AFC San Jose'
                  ? getAFCCurrentSeason()
                  : getCurrentSeason(sport))
              .bounded('ProfilePage: $sport current season');
        } catch (_) {
          cachedCurrentSeason[sport] = '';
          w.failed = true; // a RELOAD with it does not commit
        }
      }
      final currentSeasonForSport = cachedCurrentSeason[sport] ?? '';

      for (final seasonEntry in sportEntry.value.entries) {
        final seasonNum = seasonEntry.key;
        final info = seasonEntry.value;
        if (info.$1.isEmpty) continue;

        final sortKey = int.tryParse(seasonNum) ?? 0;
        bool isActive = false;
        // Only run the finished-check for the one matching season, not all.
        if (currentSeasonForSport == seasonNum) {
          try {
            isActive = !(await (sport == 'AFC San Jose'
                    ? isAFCSeasonFinished(seasonNum)
                    : isSeasonFinished(sport, seasonNum))
                .bounded('ProfilePage: $sport $seasonNum Finished'));
          } catch (_) {
            w.failed = true; // a RELOAD with it does not commit
          }
        }

        final position = w.sportPositions[sport] ??
            (sport == 'AFC San Jose'
                ? (w.information['SoccerPosition'] ?? '').toString()
                : (w.information['${sport}Position'] ?? '').toString());

        stints.add(ParticipationStint(
          sport: sport,
          label: seasonNum,
          sortKey: sortKey,
          team: info.$1,
          position: position,
          isActive: isActive,
        ));
      }
    }

    for (final ta in w.appearances) {
      final sortKey =
          int.tryParse(ta.edition.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      stints.add(ParticipationStint(
        sport: ta.sport,
        label: ta.edition,
        sortKey: sortKey,
        team: ta.teamName,
        position: ta.position,
        isActive: !ta.finished,
        isTournament: true,
        scopeId: ta.tournamentId,
      ));
    }

    w.stints = stints;
    w.current = currentParticipation(w.stints);

    // ── 8. Jersey number for current team ────────────────────────────────
    if (w.current != null) {
      if (w.current!.isTournament) {
        final ta = _findTournamentAppearance(w, w.current!.scopeId);
        if (ta != null && ta.number.isNotEmpty) {
          w.currentTeamNumber = ta.number;
        }
      } else {
        // League players all have a `number` field on the Player model.
        final entry =
            w.tableEntries[w.current!.sport]?[w.current!.label];
        if (entry != null && entry.$1.isNotEmpty) {
          final player = entry.$3;
          // All league player models implement Player which has `number`.
          if (player is FutsalPlayer && player.number.isNotEmpty) {
            w.currentTeamNumber = player.number;
          } else if (player is BasketballPlayer && player.number.isNotEmpty) {
            w.currentTeamNumber = player.number;
          } else if (player is FlagFootballPlayer &&
              player.number.isNotEmpty) {
            w.currentTeamNumber = player.number;
          } else if (player is SoccerPlayer && player.number.isNotEmpty) {
            w.currentTeamNumber = player.number;
          }
        }
      }
    }

    // ── 9. CompetitionStats (per-season + per-tournament, latest first) ────
    final competitions = <CompetitionStats>[];

    // League seasons — one entry per season per sport.
    for (final sportEntry in w.tableEntries.entries) {
      final sport = sportEntry.key;
      final seasonMap = sportEntry.value;
      final position = sport == 'AFC San Jose'
          ? (w.information['SoccerPosition'] ?? '').toString()
          : (w.sportPositions[sport] ?? '');

      for (final seasonEntry in seasonMap.entries) {
        final seasonNum = seasonEntry.key;
        final player = seasonEntry.value.$3;
        final sortKey = int.tryParse(seasonNum) ?? 0;

        final String label;
        if (sport == 'AFC San Jose') {
          label = 'AFC San Jose · Season $seasonNum';
        } else {
          label = '$sport · Season $seasonNum';
        }

        // AFC entries store the season string in $1 (club, not a team map),
        // so the club name itself is the team identity there.
        final team =
            sport == 'AFC San Jose' ? 'AFC San Jose' : seasonEntry.value.$1;

        competitions.add(CompetitionStats(
          label: label,
          sport: sport,
          position: position,
          team: team,
          teamLogoUrl: _teamLogoUrl(sport, seasonNum, team),
          stats: _buildStatMapForSingleEntry(sport, player),
          sortKey: sortKey,
        ));
      }
    }

    // Tournament appearances — one entry per appearance.
    for (final ta in w.appearances) {
      final sortKey =
          int.tryParse(ta.edition.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      competitions.add(CompetitionStats(
        label: ta.tournamentName,
        sport: ta.sport,
        position: ta.position,
        team: ta.teamName,
        teamLogoUrl: ta.teamLogoUrl,
        stats: _tournamentPlayerStatMap(ta.player),
        sortKey: sortKey,
      ));
    }

    // Sort latest first.
    competitions.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    w.competitions = competitions;

    // ── 10. Current-season stats label + headline stats ───────────────────
    if (w.current != null) {
      if (w.current!.isTournament) {
        final ta = _findTournamentAppearance(w, w.current!.scopeId);
        w.currentStatsLabel = ta?.tournamentName ?? w.current!.label;
      } else {
        final sport = w.current!.sport;
        final seasonNum = w.current!.label;
        if (sport == 'AFC San Jose') {
          w.currentStatsLabel = 'AFC San Jose Season $seasonNum';
        } else {
          w.currentStatsLabel = '$sport League Season $seasonNum';
        }
      }
    }
    w.headlineStats = _buildHeadlineStats(w);
  }

  // ─── Team color (hero tint) ───────────────────────────────────────────────

  // ── 7. Team color ──────────────────────────────────────────────────────
  // Decode the logo image ONCE — only for the current stint. All the
  // _extractHelper calls stored a placeholder color; this single real
  // ColorScheme decode replaces it. Never setStates on its own — _loadCareer
  // races it against a grace window so the tint is part of the one reveal.
  Future<Color?> _resolveTeamColor(_CareerWork w) async {
    if (w.current == null || w.current!.isTournament) return null;
    final entry = w.tableEntries[w.current!.sport]?[w.current!.label];
    if (entry == null || entry.$1.isEmpty) return null;
    final logoUrl = entry.$3 is FutsalPlayer
        ? (entry.$3 as FutsalPlayer).teamPath
        : entry.$3 is BasketballPlayer
            ? (entry.$3 as BasketballPlayer).teamPath
            : entry.$3 is FlagFootballPlayer
                ? (entry.$3 as FlagFootballPlayer).teamPath
                : entry.$3 is SoccerPlayer
                    ? (entry.$3 as SoccerPlayer).teamPath
                    : '';
    Color color = const Color(0xFFD00000);
    if (logoUrl.isNotEmpty) {
      try {
        final cs = await ColorScheme.fromImageProvider(
            provider: NetworkImage(logoUrl));
        color = cs.primary;
      } catch (_) {}
    }
    return color;
  }
}

// ─── Session career cache ─────────────────────────────────────────────────────
// Mirrors TournamentService._profileUrlCache: in-memory, session-scoped,
// keyed by uid. A completed career load is small, so revisiting a profile
// renders the full page from the first frame while phase 1's single
// Users/{uid} read refreshes identity behind it. Never persisted to disk.

final Map<String, _CareerSnapshot> _careerCache = {};

/// The paths each cached career was built from (uid → normalized paths).
final Map<String, Set<String>> _careerReads = {};

/// Test seam: the reads behind a profile's career.
class ProfileCareerSources {
  const ProfileCareerSources({
    required this.read,
    required this.tournamentBundle,
    required this.afcSeasons,
    required this.afcRoster,
  });

  /// A value by normalized path (profile node, team node, TournamentsPlayed).
  final Future<Object?> Function(String path) read;
  final Future<TournamentBundle> Function(String id) tournamentBundle;
  final Future<List<String>> Function() afcSeasons;
  final Future<Map<String, SoccerPlayer>> Function(String season) afcRoster;
}

/// Phase 1's data, read before it is applied.
class _Identity {
  const _Identity({
    required this.firstName,
    required this.lastName,
    required this.profileUrl,
    required this.information,
    required this.rawPlayed,
    required this.awards,
  });
  final String firstName;
  final String lastName;
  final String profileUrl;
  final Map<dynamic, dynamic> information;
  final Map<dynamic, dynamic> rawPlayed;

  /// null = the node had no Awards map (the shown awards are kept, as
  /// before).
  final List<Award>? awards;
}

/// One career build, into FRESH collections (second review, Important 1):
/// swapped in whole by _applyCareer, never appended to what is shown.
class _CareerWork {
  _CareerWork({
    required this.rawPlayed,
    required this.information,
    required this.firstName,
    required this.lastName,
  });
  final Map<dynamic, dynamic> rawPlayed;
  final Map<dynamic, dynamic> information;
  String firstName;
  String lastName;
  bool degraded = false;

  /// A sub-read failed and was swallowed (the first load still shows what
  /// it has; a reload with it does not commit — final round, item 2).
  bool failed = false;
  final Set<String> readPaths = {};
  final Map<String, Map<String, (String, Color, Player)>> tableEntries = {};
  final Map<String, String> sportPositions = {};
  final List<_TournamentAppearance> appearances = [];
  List<ParticipationStint> stints = [];
  ParticipationStint? current;
  String? currentTeamNumber;
  List<CompetitionStats> competitions = [];
  String? currentStatsLabel;
  List<({String label, String value})> headlineStats = [];
}

class _CareerSnapshot {
  final String firstName;
  final String lastName;
  final String profileUrl;
  final Map<dynamic, dynamic> information;
  final List<Award> awards;
  final Map<String, Map<String, (String, Color, Player)>> tableEntries;
  final Map<String, String> sportPositions;
  final List<_TournamentAppearance> tournamentAppearances;
  final List<ParticipationStint> stints;
  final List<CompetitionStats> competitions;
  final ParticipationStint? current;

  /// Mutable: a decode that missed the reveal's grace window still lands
  /// here, so the NEXT visit renders the tint from its first frame.
  Color? teamColor;
  final List<({String label, String value})> headlineStats;
  final String? currentTeamNumber;
  final String? currentStatsLabel;

  _CareerSnapshot({
    required this.firstName,
    required this.lastName,
    required this.profileUrl,
    required this.information,
    required this.awards,
    required this.tableEntries,
    required this.sportPositions,
    required this.tournamentAppearances,
    required this.stints,
    required this.competitions,
    required this.current,
    required this.teamColor,
    required this.headlineStats,
    required this.currentTeamNumber,
    required this.currentStatsLabel,
  });
}

// ─── Skeleton placeholder shown while the profile loads ──────────────────────

class _ProfileSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Hero block
        Container(
          width: double.infinity,
          height: 180,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 64, height: 64, radius: 32),
              SizedBox(height: 12),
              SkeletonBox(width: 160, height: 18),
              SizedBox(height: 8),
              SkeletonBox(width: 100, height: 12),
            ],
          ),
        ),
        // Tab bar placeholder
        const SizedBox(height: 48),
        // Card blocks
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: const [
              SkeletonBox(width: double.infinity, height: 80),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 80),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 80),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Internal data holder for tournament appearances ─────────────────────────

class _TournamentAppearance {
  final String tournamentId;
  final String tournamentName;
  final String sport;
  final String edition;
  final bool finished;
  final String logoUrl;
  final String teamName;
  final String teamLogoUrl;
  final String position;
  final String number;
  final TournamentPlayer player;

  _TournamentAppearance({
    required this.tournamentId,
    required this.tournamentName,
    required this.sport,
    required this.edition,
    required this.finished,
    required this.logoUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.position,
    required this.number,
    required this.player,
  });
}
