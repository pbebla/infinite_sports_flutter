import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/table.dart';

class FrontPage extends StatefulWidget {
  const FrontPage({super.key, required this.onTitleSelect});
  final Function(String) onTitleSelect;

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

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

  @override
  void initState() {
    super.initState();
    _loadingPage = getFrontPageValues();
  }

  Future<int> getFrontPageValues() async {
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    currentAFCSeason = await getAFCCurrentSeason();
    currentDate = await getCurrentDate(currentSport, currentSeason);
    currentAFCDate = await getCurrentDate("AFC San Jose", currentAFCSeason);
    isCurrentFinished = await isSeasonFinished(currentSport, currentSeason);
    isCurrentAFCFinished = await isAFCSeasonFinished(currentAFCSeason);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: GlobalAppBar(
        title: Text("Live Scores"), 
        height: AppBar().preferredSize.height,
        tableWidget: ValueListenableBuilder(
          valueListenable: headerNotifier, 
          builder:(context, value, child) {
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
        ),
        leaderboardWidget: ValueListenableBuilder(
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
          }
        ),
      ),
      body: FutureBuilder(
        future: _loadingPage, 
        builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        tabs.clear();
        tabNames.clear();
        if (!isCurrentFinished || !isCurrentAFCFinished) {
          if (!isCurrentFinished) {
            tabNames.add(Tab(text: "Infinite Sports"));
            tabs.add(Column(children: [
              LayoutBuilder(
                builder:(context, constraints) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder:(context) {
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
                            children: [Text("Assyrian ${currentSport} League Season ${currentSeason}", style: const TextStyle(fontWeight: FontWeight.bold),), const Spacer(), ImageIcon(AssetImage(currentSport == "Futsal" ? 'assets/FutsalLeague.png' : 'assets/BasketLeague.png'), size: windowsDefaultIconSize.toDouble(),)],),),
                      )
                    ),
                  );
                },
              ),
              Divider(color: Theme.of(context).dividerColor),
              Center(child: Text(convertDatabaseDateToFormatDate(currentDate), style: const TextStyle(fontWeight: FontWeight.bold),),),
              Expanded(
                child: LiveScorePage(sport: currentSport, season: currentSeason, date: currentDate ,onTitleSelect: (String value) {widget.onTitleSelect(value); })
              )
            ]
            ));
          }
          if (!isCurrentAFCFinished) {
            tabNames.add(Tab(text: "AFC San Jose"));
            tabs.add(Column(children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder:(context) {
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
                          child: Row(children: [Flexible(child: Text(currentAFCSeason, style: const TextStyle(fontWeight: FontWeight.bold),)), ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble(),)],),),
                      )
                    ),
                  );
                }
              ),
              Divider(color: Theme.of(context).dividerColor),
              Text(convertDatabaseDateToFormatDate(currentAFCDate), style: const TextStyle(fontWeight: FontWeight.bold),),
              Expanded(
                child: LiveScorePage(sport: "AFC San Jose", season: currentAFCSeason, date: currentAFCDate ,onTitleSelect: (String value) {widget.onTitleSelect(value); })
              )
            ]
            ));
          }
          WidgetsBinding.instance
            .addPostFrameCallback((_) => executeAfterBuild());
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
                  tabs: tabNames,
                  onTap: (value) {
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
              child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),),
          )
        ),);
      }
      )
    );
    
  }

  Future<void> _refreshData() async {
    _loadingPage = getFrontPageValues();
    await _loadingPage;
    setState(() {
      
    });
  }

  void executeAfterBuild() {
    if (tabNames.isEmpty) {
      return;
    }
    if (tabNames[0].text == "Infinite Sports") {
      headerNotifier.value = [currentSport, currentSeason];
    } else if (tabNames[0].text == "AFC San Jose") {
      headerNotifier.value = ["AFC San Jose", currentAFCSeason];
    }
  }
}
