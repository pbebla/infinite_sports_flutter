import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_home_banner.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/league_detail_page.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';
import 'package:infinite_sports_flutter/misc/season_pointers.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_entry_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournament_tabs/tournament_day_view.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';
import 'package:infinite_sports_flutter/widgets/league_day_view.dart';
import 'package:infinite_sports_flutter/widgets/live_filter_bar.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// One active tournament's data for the home screen. [matches] holds ALL of the
/// tournament's matches (the day strip filters per selected day); [initialDay]
/// is the day to open on — the current game day computed at load time.
class _ActiveTournamentTab {
  final Tournament tournament;
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final Map<String, List<TournamentPlayer>> rosters;
  final String initialDay;
  const _ActiveTournamentTab({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.rosters,
    required this.initialDay,
  });
}

/// One league section of the Matches tab: which season, the day it opens on
/// and whether the season is over.
class _LeagueSection {
  const _LeagueSection({
    required this.sport,
    required this.season,
    required this.date,
    required this.finished,
  });
  final String sport;
  final String season;
  final String date;
  final bool finished;
}

/// What the top-bar Table/Leaderboard target ([headerNotifier]) becomes when
/// the Matches tab's sections move from the old pointers to the new ones, or
/// null to leave it: a header on the old league season follows the league,
/// one on the old AFC season follows AFC, an unset one takes the league.
/// Anything else (another selection) is left alone.
@visibleForTesting
List<String>? followHeader(
  List header, {
  required String oldSport,
  required String oldSeason,
  required String oldAfcSeason,
  required String newSport,
  required String newSeason,
  required String newAfcSeason,
}) {
  final h0 = header.isNotEmpty ? '${header[0]}' : '';
  final h1 = header.length > 1 ? '${header[1]}' : '';
  List<String>? change(List<String> next) =>
      (next[0] == h0 && next[1] == h1) ? null : next;
  if (h0.isEmpty && h1.isEmpty) return change([newSport, newSeason]);
  if (h0 == 'AFC San Jose' && h1 == oldAfcSeason) {
    return change(['AFC San Jose', newAfcSeason]);
  }
  if (h0 == oldSport && h1 == oldSeason) return change([newSport, newSeason]);
  return null;
}

/// The home registration banner (way back, owner-approved 2026-11-14): a
/// registration the fan still owes money on (open OR closed, not removed)
/// takes priority — "Finish your payment: <name>" with the amount, opening
/// that registration's status page; otherwise today's "Registration open"
/// banner; null = no banner. [mine] is null until the fan's own
/// registrations have answered (and for signed-out fans).
@visibleForTesting
({String title, String subtitle, MyRegistration? owing})?
    homeRegistrationBanner({
  required MyRegistrations? mine,
  required Map<String, RegistrationConfig> open,
}) {
  final owing = mine?.firstOwing;
  if (owing != null) {
    return (
      title: 'Finish your payment: ${owing.config.label}',
      subtitle: 'You owe ${formatOwed(owing.owed)} — tap to pay',
      owing: owing,
    );
  }
  if (open.isEmpty) return null;
  return (
    title: open.length == 1
        ? 'Registration open: ${open.values.first.label}'
        : 'Registrations are open',
    subtitle: 'Tap to sign up',
    owing: null,
  );
}

/// The banner card (primary fill, white-on-primary text), both modes.
class HomeRegistrationBanner extends StatelessWidget {
  const HomeRegistrationBanner(
      {super.key, required this.banner, required this.onTap});

  final ({String title, String subtitle, MyRegistration? owing}) banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 4, 19, 0),
      child: Card(
        color: scheme.primary,
        child: ListTile(
          leading: Icon(
              banner.owing != null ? Icons.payments : Icons.how_to_reg,
              color: scheme.onPrimary),
          title: Text(
            banner.title,
            style: TextStyle(
                color: scheme.onPrimary, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(banner.subtitle,
              style:
                  TextStyle(color: scheme.onPrimary.withValues(alpha: 0.7))),
          onTap: onTap,
        ),
      ),
    );
  }
}

class FrontPage extends StatefulWidget {
  const FrontPage({super.key, required this.onTitleSelect});
  final Function(String) onTitleSelect;

  @override
  State<FrontPage> createState() => _FrontPageState();
}

class _FrontPageState extends State<FrontPage> {
  String currentSport = "";
  String currentSeason = "";
  String currentAFCSeason = "";
  String currentDate = "";
  String currentAFCDate = "";
  bool isCurrentFinished = false;
  bool isCurrentAFCFinished = false;
  late Future<int> _loadingPage;
  List<Widget> tabs = List.empty(growable: true);
  List<Tab> tabNames = List.empty(growable: true);

  // Parallel to [tabNames]: true when the tab at that index is a tournament tab.
  List<bool> tabIsTournament = List.empty(growable: true);

  // Parallel to [tabNames]: a stable identity per tab ('league', 'afc',
  // 'tournament:<id>') — the league tab's TITLE changes with the league, so
  // the fan's selected tab is remembered by key (review fix m2).
  final List<String> tabKeys = [];
  String? _selectedTabKey;

  // Active tournaments (not finished, each having a current game day).
  List<_ActiveTournamentTab> activeTournaments = [];

  // Open new-style registrations (regId -> config) for the sign-up banner.
  Map<String, RegistrationConfig> openRegistrations = {};

  // Live tournament-tab discovery (TAS.3 Task 5): the last-seen sorted set
  // of active (unfinished) tournament ids, used to detect when the SET
  // changes rather than reacting to every /Tournaments write (e.g. a score
  // update inside an already-known tournament fires the same stream but
  // must not churn the tabs).
  List<String> _lastActiveTournamentIds = [];
  StreamSubscription<List<Tournament>>? _tournamentsWatchSub;

  /// Matches-tab header for the current-league section, e.g. "Futsal League"
  /// (P2.1 owner feedback: was the hardcoded "Infinite Sports").
  String get _leagueTabTitle => "$currentSport League";

  // Drives whether the app-bar table/leaderboard shortcut buttons are hidden
  // (they are league-only and make no sense on a tournament tab).
  final ValueNotifier<bool> _onTournamentTab = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadingPage = getFrontPageValues();
    // Live discovery: a tournament created (or finished/un-finished) after
    // this page loaded shows up as a home tab without restarting the app.
    _tournamentsWatchSub =
        TournamentService.watchAllTournaments().listen(_onTournamentsChanged);
    // Live season pointers (fresh-reads Task 2): a new league/season set
    // while the app is open (or a stale saved copy corrected by the server
    // right after start) moves the league + AFC sections and the top-bar
    // header in one update, without the first-load skeleton.
    SeasonPointers.listenable.addListener(_onSeasonPointersChanged);
    // Way back: the fan's own registrations, live (signed-in fans only), so
    // the banner can say "Finish your payment" and drops it once paid.
    if (signedIn) {
      try {
        _myRegistrationsSub = watchMyRegistrations().listen((m) {
          if (mounted) setState(() => _myRegistrations = m);
        }, onError: (Object _) {});
      } catch (_) {}
    }
  }

  StreamSubscription<MyRegistrations>? _myRegistrationsSub;
  MyRegistrations? _myRegistrations;

  @override
  void dispose() {
    SeasonPointers.listenable.removeListener(_onSeasonPointersChanged);
    _myRegistrationsSub?.cancel();
    _onTournamentTab.dispose();
    _tournamentsWatchSub?.cancel();
    super.dispose();
  }

  int _pointerFollowGen = 0;

  void _onSeasonPointersChanged() => unawaited(_followSeasonPointers());

  /// Re-reads only the sections whose pointer moved, then applies them in
  /// ONE setState and moves [headerNotifier] with them. Waits for the first
  /// load (which may already have read the new values); a newer change
  /// supersedes an older one still in flight.
  Future<void> _followSeasonPointers() async {
    final gen = ++_pointerFollowGen;
    try {
      await _loadingPage;
    } catch (_) {}
    if (!mounted || gen != _pointerFollowGen) return;
    final now = SeasonPointers.listenable.value;
    final leagueMoved = '${now.currentLeague}' != currentSport ||
        '${now.currentSeason}' != currentSeason;
    final afcMoved = '${now.afcSeason}' != currentAFCSeason;
    if (!leagueMoved && !afcMoved) return;
    final List<_LeagueSection?> sections;
    try {
      sections = await Future.wait<_LeagueSection?>([
        leagueMoved ? _readLeagueSection() : Future.value(null),
        afcMoved ? _readAfcSection() : Future.value(null),
      ]);
    } catch (e) {
      // A failed read is not a fact: the screen stays as it is; the next
      // pointer change or the refresh button tries again.
      debugPrint('FrontPage: following the season pointers failed: $e');
      return;
    }
    if (!mounted || gen != _pointerFollowGen) return;
    final oldSport = currentSport;
    final oldSeason = currentSeason;
    final oldAfc = currentAFCSeason;
    setState(() {
      if (sections[0] != null) _applyLeagueSection(sections[0]!);
      if (sections[1] != null) _applyAfcSection(sections[1]!);
    });
    final next = followHeader(headerNotifier.value as List,
        oldSport: oldSport,
        oldSeason: oldSeason,
        oldAfcSeason: oldAfc,
        newSport: currentSport,
        newSeason: currentSeason,
        newAfcSeason: currentAFCSeason);
    if (next != null) headerNotifier.value = next;
  }

  /// The current league's section values (pointer → date + finished).
  Future<_LeagueSection> _readLeagueSection() async {
    final sport = await getCurrentSport();
    final season = await getCurrentSeason(sport);
    final both = await Future.wait<Object>([
      getCurrentDate(sport, season),
      isSeasonFinished(sport, season),
    ]);
    return _LeagueSection(
        sport: sport,
        season: season,
        date: both[0] as String,
        finished: both[1] as bool);
  }

  /// AFC San Jose's section values (pointer → date + finished).
  Future<_LeagueSection> _readAfcSection() async {
    final season = await getAFCCurrentSeason();
    final both = await Future.wait<Object>([
      getCurrentDate("AFC San Jose", season),
      isAFCSeasonFinished(season),
    ]);
    return _LeagueSection(
        sport: "AFC San Jose",
        season: season,
        date: both[0] as String,
        finished: both[1] as bool);
  }

  void _applyLeagueSection(_LeagueSection s) {
    currentSport = s.sport;
    currentSeason = s.season;
    currentDate = s.date;
    isCurrentFinished = s.finished;
  }

  void _applyAfcSection(_LeagueSection s) {
    currentAFCSeason = s.season;
    currentAFCDate = s.date;
    isCurrentAFCFinished = s.finished;
  }

  /// Reacts to a live /Tournaments update by comparing the sorted active-id
  /// list against the last one seen — routine in-tournament writes (scores,
  /// rosters, ...) re-fire this same stream but leave the active SET
  /// unchanged, so they're guarded against here instead of rebuilding tabs
  /// on every emission.
  void _onTournamentsChanged(List<Tournament> tournaments) {
    final ids = TournamentService.activeTournamentIds(tournaments);
    if (listEquals(ids, _lastActiveTournamentIds)) return;
    _lastActiveTournamentIds = ids;
    _refreshActiveTournamentTabs();
  }

  /// Reloads just the tournament-tab bundles (reusing [_loadActiveTournaments])
  /// and rebuilds — without resetting [_loadingPage], so this never flashes
  /// the first-load skeleton the way the manual pull-to-refresh button does.
  Future<void> _refreshActiveTournamentTabs() async {
    await _loadActiveTournaments();
    if (!mounted) return;
    setState(() {});
  }

  Future<int> getFrontPageValues() async {
    // These reads gate the first paint of the Matches screen, so the four
    // independent chains (league, AFC, tournaments, registrations) run
    // concurrently instead of as one long sequential chain of round trips.
    await Future.wait([
      () async {
        _applyLeagueSection(await _readLeagueSection());
      }(),
      () async {
        _applyAfcSection(await _readAfcSection());
      }(),
      _loadActiveTournaments(),
      () async {
        openRegistrations = await RegistrationService.getOpenRegistrations();
      }(),
    ]);
    return 1;
  }

  /// Loads every active (not-finished) tournament that has a current game day,
  /// keeping ALL of its matches so the home-tab day strip can switch between
  /// days. Tournaments whose games are all in the past (or that have none) are
  /// skipped, so finished games fall off the home screen the same way a
  /// finished league season does.
  Future<void> _loadActiveTournaments() async {
    final tournaments = await TournamentService.getActiveTournaments();
    final tabs = await Future.wait(tournaments.map((t) async {
      // One whole-node read per tournament (iOS overlapping-get() fix —
      // see TournamentService.getTournamentBundle) — also drops two round
      // trips per active tournament off the front-page load.
      final bundle = await TournamentService.getTournamentBundle(t.id);
      final day = currentGameDay(bundle.matches.map((m) => m.date));
      if (day == null) return null;
      final rosters =
          await TournamentService.enrichRosterPhotos(bundle.rosters);
      return _ActiveTournamentTab(
        tournament: t,
        teams: bundle.teams,
        matches: bundle.matches,
        rosters: rosters,
        initialDay: day,
      );
    }));
    activeTournaments = [
      for (final b in tabs)
        if (b != null) b,
    ];
  }

  Widget getSportIcon(String sport) {
    switch (sport) {
      case "Futsal":
        return ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble());
      case "Basketball":
        return ImageIcon(AssetImage('assets/BasketLeague.png'), size: windowsDefaultIconSize.toDouble());
      case "Flag Football":
        return ImageIcon(AssetImage('assets/FlagFootballLeague.png'), size: windowsDefaultIconSize.toDouble());
      default:
        return Icon(Icons.sports);
    }
  }

  /// Banner card shown while any new-style registration is open; tapping it
  /// opens the registration entry page.
  /// The registration banner, or null (see [homeRegistrationBanner]).
  ({String title, String subtitle, MyRegistration? owing})? get _banner =>
      homeRegistrationBanner(mine: _myRegistrations, open: openRegistrations);

  Widget _registrationBanner(BuildContext context) {
    final banner = _banner!;
    return HomeRegistrationBanner(
      banner: banner,
      onTap: () {
        final owing = banner.owing;
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          // Owing: straight to that registration's status page (it follows
          // the live config and submission; closed keeps its pay actions).
          return owing != null
              ? RegistrationStatusPage(
                  regId: owing.regId, config: owing.config)
              : const RegistrationEntryPage();
        }));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: GlobalAppBar(
          title: Image.asset('assets/infinite_mark.png', height: 32),
          height: AppBar().preferredSize.height,
          tableWidget: ValueListenableBuilder<bool>(
            valueListenable: _onTournamentTab,
            builder: (context, onTournament, _) {
              if (onTournament) return const SizedBox.shrink();
              return ValueListenableBuilder(
                valueListenable: headerNotifier,
                builder: (context, value, child) {
                  return IconButton(
                    onPressed: () {
                      Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
                        initialEntries: [OverlayEntry(
                            builder: (context) {
                              return TablePage(sport: value[0], season: value[1]);
                            })],
                      )));
                    },
                    icon: const ImageIcon(AssetImage('assets/table.png')),
                  );
                },
              );
            },
          ),
          leaderboardWidget: ValueListenableBuilder<bool>(
            valueListenable: _onTournamentTab,
            builder: (context, onTournament, _) {
              if (onTournament) return const SizedBox.shrink();
              return ValueListenableBuilder(
                valueListenable: headerNotifier,
                builder: (context, value, child) {
                  return IconButton(
                    onPressed: () {
                      Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
                        initialEntries: [OverlayEntry(
                            builder: (context) {
                              return LeaderboardPage(sport: value[0], season: value[1]);
                            })],
                      )));
                    },
                    icon: const ImageIcon(AssetImage('assets/leader.png')),
                  );
                },
              );
            },
          ),
        ),
        body: FutureBuilder(
            future: _loadingPage,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SingleChildScrollView(
                  physics: NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SkeletonMatchList(count: 8),
                  ),
                );
              }
              tabs.clear();
              tabNames.clear();
              tabIsTournament.clear();
              tabKeys.clear();
              if (!isCurrentFinished) {
                tabNames.add(Tab(text: _leagueTabTitle));
                tabIsTournament.add(false);
                tabKeys.add('league');
                tabs.add(Column(children: [
                  if (_banner != null) _registrationBanner(context),
                  // In-season Infinite Fantasy entry (P6): stream-gates
                  // ITSELF on Fantasy/<sport>/<season>/Config — renders
                  // nothing while the node is absent.
                  // Keyed: a season pointer change remounts it on the new
                  // season (it subscribes in initState).
                  FantasyHomeBanner(
                      key: ValueKey('fantasy|$currentSport|$currentSeason'),
                      sport: currentSport,
                      season: currentSeason),
                  // P3.1 owner feedback: header opens the season hub
                  // (LeagueDetailPage), mirroring the tournament header card
                  // below. Root navigator, matching league_day_view's pushes.
                  // AFC San Jose keeps its own header (separate tab block).
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(mainContext!, MaterialPageRoute(builder: (_) {
                            return LeagueDetailPage(sport: currentSport, season: currentSeason);
                          }));
                        },
                        child: Card(
                          elevation: 2,
                          child: SizedBox(
                            width: constraints.maxWidth - 38,
                            height: 70,
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    getSportIcon(currentSport),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _leagueTabTitle,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor, thickness: 1),
                  // P2.1: live compact day view (the FixturesTab list renders
                  // its own "Friday, June 12" date header, so the old
                  // standalone date line above it is gone).
                  Expanded(
                      child: LeagueDayView(
                          // Keyed: a season pointer change remounts the day
                          // list on the new season (it streams from
                          // initState).
                          key: ValueKey(
                              'day|$currentSport|$currentSeason|$currentDate'),
                          sport: currentSport,
                          season: currentSeason,
                          date: currentDate)
                  )
                ]));
              }
              if (!isCurrentAFCFinished) {
                tabNames.add(Tab(text: "AFC San Jose"));
                tabIsTournament.add(false);
                tabKeys.add('afc');
                tabs.add(Column(children: [
                  LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) {
                              return ShowLeaguePage(sport: "AFC San Jose", season: currentAFCSeason);
                            },));
                          },
                          child: Card(
                              elevation: 2,
                              child: SizedBox(
                                  width: constraints.maxWidth - 38,
                                  height: 70,
                                  child: Container(
                                      padding: const EdgeInsets.all(13),
                                      child: Row(
                                        children: [
                                          Flexible(child: Text(currentAFCSeason, style: const TextStyle(fontWeight: FontWeight.bold))),
                                          ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble()),
                                        ],
                                      )
                                  )
                              )
                          ),
                        );
                      }
                  ),
                  Divider(color: Theme.of(context).dividerColor, thickness: 1),
                  Text(convertDatabaseDateToFormatDate(currentAFCDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                      child: LiveScorePage(
                          // Keyed: follows a new AFC season pointer.
                          key: ValueKey('afc|$currentAFCSeason|$currentAFCDate'),
                          sport: "AFC San Jose", season: currentAFCSeason, date: currentAFCDate, onTitleSelect: (String value) {widget.onTitleSelect(value);})
                  )
                ]));
              }
              for (final data in activeTournaments) {
                tabNames.add(Tab(text: data.tournament.name));
                tabIsTournament.add(true);
                tabKeys.add('tournament:${data.tournament.id}');
                tabs.add(_buildTournamentTab(context, data));
              }
              if (tabs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => executeAfterBuild());
                return HomeTabShell(
                  tabNames: tabNames,
                  tabs: tabs,
                  // Review fix m2: the fan stays on the tab they were on
                  // (by key) when tabs come or go or the league changes.
                  selectedIndex: _selectedIndex,
                  onIndexChanged: _selectTab,
                  onRefresh: () async {
                    await _refreshData();
                  },
                  onTabTap: _selectTab,
                );
              }
              return Column(children: [
                if (_banner != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _registrationBanner(context),
                  ),
                Expanded(
                  child: Center(
                    child: Card(
                      elevation: 2,
                      child: SizedBox(
                        width: 350,
                        height: 70,
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
            }
        )
    );
  }

  /// Builds a home-screen tournament tab: a centered, tappable header card that
  /// opens the full tournament page, followed by a [TournamentDayView] — a
  /// swipeable day strip over that tournament's matches, opening on the current
  /// game day.
  Widget _buildTournamentTab(BuildContext context, _ActiveTournamentTab data) {
    final name = data.tournament.name;
    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) {
                return TournamentDetailPage(
                  tournamentId: data.tournament.id,
                  tournamentName: name,
                );
              }));
            },
            child: Card(
              elevation: 2,
              child: SizedBox(
                width: constraints.maxWidth - 38,
                height: 70,
                child: Container(
                  padding: const EdgeInsets.all(13),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      Divider(color: Theme.of(context).dividerColor, thickness: 1),
      Expanded(child: _HomeTournamentBody(data: data)),
    ]);
  }

  Future<void> _refreshData() async {
    _loadingPage = getFrontPageValues();
    await _loadingPage;
    if (!mounted) return;
    setState(() {});
  }

  /// The selected tab's index in the current tab list (the remembered key,
  /// else the first tab).
  int get _selectedIndex {
    final i = _selectedTabKey == null ? -1 : tabKeys.indexOf(_selectedTabKey!);
    return i < 0 ? 0 : i;
  }

  /// A tab was chosen (tap or swipe): remember it by key and point the
  /// top-bar Table/Leaderboard at it.
  void _selectTab(int index) {
    if (index < 0 || index >= tabKeys.length) return;
    _selectedTabKey = tabKeys[index];
    _applyHeaderFor(index);
  }

  /// [headerNotifier] and the tournament flag for the tab at [index], from
  /// the SAME fields the tab bodies were just built from (review fix m2: the
  /// header changes in the same update as the games).
  void _applyHeaderFor(int index) {
    _onTournamentTab.value = tabIsTournament[index];
    List<String>? next;
    if (tabKeys[index] == 'league') {
      next = [currentSport, currentSeason];
    } else if (tabKeys[index] == 'afc') {
      next = ["AFC San Jose", currentAFCSeason];
    }
    // A tournament tab leaves headerNotifier unchanged: the table and
    // leaderboard buttons it feeds are hidden there (_onTournamentTab).
    if (next != null && !listEquals(headerNotifier.value as List, next)) {
      headerNotifier.value = next;
    }
  }

  void executeAfterBuild() {
    if (!mounted) return;
    if (tabKeys.isEmpty) return;
    // Every build: keep the fan's tab (not tab 0) and its header.
    final index = _selectedIndex;
    _selectedTabKey = tabKeys[index];
    _applyHeaderFor(index);
  }
}

/// The home screen's tab shell: the refresh button + scrollable TabBar in
/// the app bar, and the tab bodies. Its tab count changes LIVE (the
/// /Tournaments listener adds a tab when a tournament starts and drops it
/// when one finishes), so it deliberately uses a plain
/// [DefaultTabController] and does NOT key anything by the count: the
/// surviving tab bodies keep their state (streams, scroll, selected day)
/// across the change. Nothing below it is count-keyed, so the controller
/// swap cannot strand a TabBar (fix round 1, I1 — contrast
/// LiveLengthTabController, which is for pages whose subtree is remounted).
class HomeTabShell extends StatelessWidget {
  const HomeTabShell({
    super.key,
    required this.tabNames,
    required this.tabs,
    required this.onTabTap,
    required this.onRefresh,
    this.selectedIndex,
    this.onIndexChanged,
  });

  final List<Tab> tabNames;
  final List<Widget> tabs;
  final ValueChanged<int> onTabTap;
  final VoidCallback onRefresh;

  /// The tab to show (review fix m2): when tabs come or go, the controller
  /// keeps an index NUMBER, so the fan's tab is moved back to here.
  final int? selectedIndex;

  /// Every settled index change (taps AND swipes).
  final ValueChanged<int>? onIndexChanged;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      child: _SelectedTabKeeper(
        selectedIndex: selectedIndex,
        onIndexChanged: onIndexChanged,
        child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          title: TabBar(
            isScrollable: true,
            tabs: tabNames,
            onTap: onTabTap,
          ),
        ),
        body: TabBarView(children: tabs),
        ),
      ),
    );
  }
}

/// Follows the DefaultTabController above it (it is replaced when the tab
/// count changes): reports settled index changes and moves the controller to
/// [selectedIndex] when it differs (a jump, no animation).
class _SelectedTabKeeper extends StatefulWidget {
  const _SelectedTabKeeper({
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.child,
  });

  final int? selectedIndex;
  final ValueChanged<int>? onIndexChanged;
  final Widget child;

  @override
  State<_SelectedTabKeeper> createState() => _SelectedTabKeeperState();
}

class _SelectedTabKeeperState extends State<_SelectedTabKeeper> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = DefaultTabController.maybeOf(context);
    if (!identical(c, _controller)) {
      _controller?.removeListener(_onChanged);
      _controller = c;
      c?.addListener(_onChanged);
    }
    _keepSelected();
  }

  @override
  void didUpdateWidget(covariant _SelectedTabKeeper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _keepSelected();
  }

  void _onChanged() {
    final c = _controller;
    if (c == null || c.indexIsChanging) return;
    widget.onIndexChanged?.call(c.index);
  }

  void _keepSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _controller;
      final want = widget.selectedIndex;
      if (!mounted || c == null || want == null) return;
      if (want >= 0 && want < c.length && c.index != want) c.index = want;
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Live body of a home-screen tournament tab: streams the tournament's matches
/// so scores/clock update without a refresh, pins live matches in a Happening
/// Now rail, and offers a Live pill that filters to live matches only.
class _HomeTournamentBody extends StatefulWidget {
  final _ActiveTournamentTab data;
  const _HomeTournamentBody({required this.data});

  @override
  State<_HomeTournamentBody> createState() => _HomeTournamentBodyState();
}

class _HomeTournamentBodyState extends State<_HomeTournamentBody> {
  bool _liveOnly = false;
  late final Stream<List<TournamentMatch>> _matchesStream;

  @override
  void initState() {
    super.initState();
    _matchesStream = TournamentService.watchMatches(widget.data.tournament.id);
  }

  String _abbr(String teamId) {
    final name = (widget.data.teams[teamId]?.name ?? teamId).trim();
    if (name.length <= 3) return name.toUpperCase();
    return name.substring(0, 3).toUpperCase();
  }

  void _openMatch(TournamentMatch m) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentMatchDetailPage(
          match: m,
          teams: widget.data.teams,
          rosters: widget.data.rosters,
          tournamentId: widget.data.tournament.id,
          sport: widget.data.tournament.sport,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return StreamBuilder<List<TournamentMatch>>(
      stream: _matchesStream,
      initialData: data.matches,
      builder: (context, snap) {
        final matches = snap.data ?? data.matches;
        final live = liveMatches(matches);
        return Column(
          children: [
            HappeningNowRail(live: live, abbr: _abbr, onTapMatch: _openMatch),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  const Spacer(),
                  LivePill(
                    on: _liveOnly,
                    onChanged: (v) => setState(() => _liveOnly = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _liveOnly
                  ? (live.isEmpty
                      ? const Center(child: Text('No live matches right now'))
                      : FixturesTab(
                          matches: live,
                          teams: data.teams,
                          rosters: data.rosters,
                          tournamentId: data.tournament.id,
                          sport: data.tournament.sport,
                        ))
                  : TournamentDayView(
                      matches: matches,
                      teams: data.teams,
                      rosters: data.rosters,
                      tournamentId: data.tournament.id,
                      sport: data.tournament.sport,
                      initialDay: data.initialDay,
                    ),
            ),
          ],
        );
      },
    );
  }
}
