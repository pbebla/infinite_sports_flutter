import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/game_day.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:infinite_sports_flutter/tournament_tabs/fixtures_tab.dart';
import 'package:infinite_sports_flutter/tournamentdetail.dart';

/// One active tournament's data for the home screen, with [matches] already
/// filtered down to the tournament's current game day.
class _ActiveTournamentTab {
  final Tournament tournament;
  final Map<String, TournamentTeam> teams;
  final List<TournamentMatch> matches;
  final Map<String, List<TournamentPlayer>> rosters;
  const _ActiveTournamentTab({
    required this.tournament,
    required this.teams,
    required this.matches,
    required this.rosters,
  });
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

  // Active tournaments (not finished, each having a current game day).
  List<_ActiveTournamentTab> activeTournaments = [];

  // Drives whether the app-bar table/leaderboard shortcut buttons are hidden
  // (they are league-only and make no sense on a tournament tab).
  final ValueNotifier<bool> _onTournamentTab = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadingPage = getFrontPageValues();
  }

  @override
  void dispose() {
    _onTournamentTab.dispose();
    super.dispose();
  }

  Future<int> getFrontPageValues() async {
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    currentAFCSeason = await getAFCCurrentSeason();
    currentDate = await getCurrentDate(currentSport, currentSeason);
    currentAFCDate = await getCurrentDate("AFC San Jose", currentAFCSeason);
    isCurrentFinished = await isSeasonFinished(currentSport, currentSeason);
    isCurrentAFCFinished = await isAFCSeasonFinished(currentAFCSeason);
    await _loadActiveTournaments();
    return 1;
  }

  /// Loads every active (not-finished) tournament that has a current game day,
  /// keeping only that day's matches. Tournaments whose games are all in the
  /// past (or that have none) are skipped, so finished games fall off the home
  /// screen the same way a finished league season does.
  Future<void> _loadActiveTournaments() async {
    final tournaments = await TournamentService.getActiveTournaments();
    final bundles = await Future.wait(tournaments.map((t) async {
      final teams = await TournamentService.getTeams(t.id);
      final matches = await TournamentService.getMatches(t.id);
      final day = currentGameDay(matches.map((m) => m.date));
      if (day == null) return null;
      final dayMatches = matches.where((m) => m.date == day).toList();
      final rosters = await TournamentService.getRosters(t.id, teams);
      return _ActiveTournamentTab(
        tournament: t,
        teams: teams,
        matches: dayMatches,
        rosters: rosters,
      );
    }));
    activeTournaments = [
      for (final b in bundles)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: GlobalAppBar(
          title: Text("Matches"),
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
                return Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    )
                );
              }
              tabs.clear();
              tabNames.clear();
              tabIsTournament.clear();
              if (!isCurrentFinished) {
                tabNames.add(Tab(text: "Infinite Sports"));
                tabIsTournament.add(false);
                tabs.add(Column(children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) {
                            return ShowLeaguePage(sport: currentSport, season: currentSeason);
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
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text("Assyrian $currentSport League Season $currentSeason", style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const Spacer(),
                                      getSportIcon(currentSport),
                                    ],
                                  ),
                                )
                            )
                        ),
                      );
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  Center(child: Text(convertDatabaseDateToFormatDate(currentDate), style: const TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                      child: LiveScorePage(sport: currentSport, season: currentSeason, date: currentDate, onTitleSelect: (String value) { widget.onTitleSelect(value); })
                  )
                ]));
              }
              if (!isCurrentAFCFinished) {
                tabNames.add(Tab(text: "AFC San Jose"));
                tabIsTournament.add(false);
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
                  Divider(color: Theme.of(context).dividerColor),
                  Text(convertDatabaseDateToFormatDate(currentAFCDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                      child: LiveScorePage(sport: "AFC San Jose", season: currentAFCSeason, date: currentAFCDate, onTitleSelect: (String value) {widget.onTitleSelect(value);})
                  )
                ]));
              }
              for (final data in activeTournaments) {
                tabNames.add(Tab(text: data.tournament.name));
                tabIsTournament.add(true);
                tabs.add(_buildTournamentTab(context, data));
              }
              if (tabs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => executeAfterBuild());
                return DefaultTabController(
                    length: tabs.length,
                    child: Scaffold(
                      appBar: AppBar(
                        leading: IconButton(
                            onPressed: () async {
                              await _refreshData();
                            },
                            icon: const Icon(Icons.refresh)
                        ),
                        title: TabBar(
                          isScrollable: true,
                          tabs: tabNames,
                          onTap: (value) {
                            _onTournamentTab.value = tabIsTournament[value];
                            if (tabNames[value].text == "Infinite Sports") {
                              headerNotifier.value = [currentSport, currentSeason];
                            } else if (tabNames[value].text == "AFC San Jose") {
                              headerNotifier.value = ["AFC San Jose", currentAFCSeason];
                            }
                          },
                        ),
                      ),
                      body: TabBarView(
                        children: tabs,
                      ),
                    )
                );
              }
              return Center(
                child: Card(
                  elevation: 2,
                  shadowColor: Colors.black,
                  color: Colors.white,
                  child: SizedBox(
                    width: 350,
                    height: 70,
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  ),
                ),
              );
            }
        )
    );
  }

  /// Builds a home-screen tournament tab: a centered, tappable header card that
  /// opens the full tournament page, followed by that tournament's current
  /// game-day matches (reusing the shared FixturesTab).
  Widget _buildTournamentTab(BuildContext context, _ActiveTournamentTab data) {
    final name = data.tournament.name;
    final sport = data.tournament.sport;
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
      Divider(color: Theme.of(context).dividerColor),
      Expanded(
        child: FixturesTab(
          matches: data.matches,
          teams: data.teams,
          rosters: data.rosters,
          tournamentId: data.tournament.id,
          sport: sport,
        ),
      ),
    ]);
  }

  Future<void> _refreshData() async {
    _loadingPage = getFrontPageValues();
    await _loadingPage;
    setState(() {});
  }

  void executeAfterBuild() {
    if (tabNames.isEmpty) return;
    _onTournamentTab.value =
        tabIsTournament.isNotEmpty ? tabIsTournament[0] : false;
    if (tabNames[0].text == "Infinite Sports") {
      headerNotifier.value = [currentSport, currentSeason];
    } else if (tabNames[0].text == "AFC San Jose") {
      headerNotifier.value = ["AFC San Jose", currentAFCSeason];
    }
  }
}
