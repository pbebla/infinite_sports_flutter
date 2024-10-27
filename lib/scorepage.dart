import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/misc/navigation_controls.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/model/basketballplayerstats.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/model/futsalplayerstats.dart';
import 'package:infinite_sports_flutter/model/gameactivity.dart';
import 'package:infinite_sports_flutter/model/playerstats.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/soccergame.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:infinite_sports_flutter/model/game.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:palette_generator/palette_generator.dart';

Map<String, String> stringToGameText = {
  "OnePointer": "FT",
  "TwoPointer": "FG",
  "ThreePointer": "3PT",
  "Rebound": "REB",
  "Foul": "Foul",
  "Goal": "Goal",
  "Assist": "Assist",
  "Yellow": "Yellow",
  "Blue": "Blue",
  "Red": "Red"
};

Map<String,Widget> stringToGameAction = {
  "OnePointer": Image.asset("assets/onepointer.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "TwoPointer": Image.asset("assets/twopointer.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "ThreePointer": Image.asset("assets/threepointer.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Rebound": Image.asset("assets/rebound.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Foul": Image.asset("assets/foul.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Goal": Image.asset("assets/goal.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Assist": Image.asset("assets/assist.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Yellow": Image.asset("assets/yellow.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Blue": Image.asset("assets/blue.png", height: windowsDefaultIconSize.toDouble()/1.5,),
  "Red": Image.asset("assets/red.png", height: windowsDefaultIconSize.toDouble()/1.5,),
};

typedef TitleCallback = void Function(String value);

class ScorePage extends StatefulWidget {
  const ScorePage({super.key, required this.sport, required this.season, required this.times, required this.game, required this.refreshCallback});
  //final TitleCallback onTitleSelect;

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;
  final String sport;
  final String season;
  final Map<String, Map<String, int>> times;
  final Game game;
  final VoidCallback refreshCallback;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {

  List<Widget> items = List.empty(growable: true);
  List<PlayerStats> team1Players = List.empty(growable: true);
  List<PlayerStats> team2Players = List.empty(growable: true);
  List<GameActivity> activities = List.empty(growable: true);
  Color team1color = Colors.white;
  Color team2color = Colors.white;
  int? table1SortColumnIndex;
  int? table2SortColumnIndex;
  bool table1isAscending = false;
  bool table2isAscending = false;
  SingleChildScrollView? table1;
  SingleChildScrollView? table2;
  late Future<int> _loadingGame;
  Game? game;

  @override
  void initState() {
    game = widget.game;
    _loadingGame = getGameData();
    super.initState();
  }

  Future<int> getGameData() async {
    if (game!.team1SourcePath != "") {
      var palette = await PaletteGenerator.fromImageProvider(NetworkImage(game!.team1SourcePath));
      team1color = palette.dominantColor?.color ?? const Color.fromARGB(255, 124, 124, 124);
    }
    if (game!.team2SourcePath != "") {
      var palette = await PaletteGenerator.fromImageProvider(NetworkImage(game!.team2SourcePath));
      team2color = palette.dominantColor?.color ?? const Color.fromARGB(255, 124, 124, 124);
    }
    if (widget.sport == "Futsal") {
      buildTeamPlayers(team1Players, (game as FutsalGame).team1lineup, game!.team1activity, team1color, game!.team1SourcePath);
      buildTeamPlayers(team2Players, (game as FutsalGame).team2lineup, game!.team2activity, team2color, game!.team2SourcePath);
    } else if (widget.sport == "AFC San Jose") {
      buildTeamPlayers(team1Players, (game as SoccerGame).team1lineup, game!.team1activity, team1color, game!.team1SourcePath);
      buildTeamPlayers(team2Players, (game as SoccerGame).team2lineup, game!.team2activity, team2color, game!.team2SourcePath);
    } else if (widget.sport == "Basketball") {
      buildTeamPlayers(team1Players, (game as BasketballGame).team1lineup, game!.team1activity, team1color, game!.team1SourcePath);
      buildTeamPlayers(team2Players, (game as BasketballGame).team2lineup, game!.team2activity, team2color, game!.team2SourcePath);
    }
    populateActivities(widget.game.team1activity, team1Players, activities, team1color, widget.game.team1SourcePath);
    populateActivities(widget.game.team2activity, team2Players, activities, team2color, widget.game.team2SourcePath);
    if (widget.sport == "AFC San Jose") {
      if (game!.team1 == "AFC San Jose") {
        sortTable(table1SortColumnIndex ?? 2, table1isAscending, team1Players);
      } else {
        sortTable(table2SortColumnIndex ?? 2, table2isAscending, team2Players);
      }
    } else {
      sortTable(table1SortColumnIndex ?? 2, table1isAscending, team1Players);
      sortTable(table2SortColumnIndex ?? 2, table2isAscending, team2Players);
    }
    return 1;
  }

  PlayerStats getTeamLeaderInStat(teamPlayers, stat) {
    PlayerStats result = teamPlayers[0];
    if (stat == "Points") {
      teamPlayers.forEach((player) {
        if (player.total > (result as BasketballPlayerStats).total) {
          result = player;
        }
      });
    } else if (stat == "Assists") {
      teamPlayers.forEach((player) {
        if (player.assists > (result as FutsalPlayerStats).assists) {
          result = player;
        }
      });
    } else if (stat == "Rebounds") {
      teamPlayers.forEach((player) {
        if (player.rebounds > (result as BasketballPlayerStats).rebounds) {
          result = player;
        }
      });
    } else if (stat == "Goals") {
      teamPlayers.forEach((player) {
        if (player.goals > (result as FutsalPlayerStats).goals) {
          result = player;
        }
      });
    }
    return result;
  }

  Card buildTeamLeaders() {
    String stat1 = "";
    String stat2 = "";
    PlayerStats team1Stat1 = team1Players[0];
    PlayerStats team1Stat2 = team1Players[0];
    PlayerStats team2Stat1 = team2Players[0];
    PlayerStats team2Stat2 = team2Players[0];
    String team1Stat1Val = "";
    String team2Stat1Val = "";
    String team1Stat2Val = "";
    String team2Stat2Val = "";
    if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
      stat1 = "Goals";
      stat2 = "Assists";
      team1Stat1 = getTeamLeaderInStat(team1Players, "Goals");
      team1Stat2 = getTeamLeaderInStat(team1Players, "Assists");
      team2Stat1 = getTeamLeaderInStat(team2Players, "Goals");
      team2Stat2 = getTeamLeaderInStat(team2Players, "Assists");
      team1Stat1Val = (team1Stat1 as FutsalPlayerStats).goals.toString();
      team2Stat1Val = (team2Stat1 as FutsalPlayerStats).goals.toString();
      team1Stat2Val = (team1Stat2 as FutsalPlayerStats).assists.toString();
      team2Stat2Val = (team2Stat2 as FutsalPlayerStats).assists.toString();
    } else if (widget.sport == "Basketball") {
      stat1 = "Points";
      stat2 = "Rebounds";
      team1Stat1 = getTeamLeaderInStat(team1Players, "Points");
      team1Stat2 = getTeamLeaderInStat(team1Players, "Rebounds");
      team2Stat1 = getTeamLeaderInStat(team2Players, "Points");
      team2Stat2 = getTeamLeaderInStat(team2Players, "Rebounds");
      team1Stat1Val = (team1Stat1 as BasketballPlayerStats).total.toString();
      team2Stat1Val = (team2Stat1 as BasketballPlayerStats).total.toString();
      team1Stat2Val = (team1Stat2 as BasketballPlayerStats).rebounds.toString();
      team2Stat2Val = (team2Stat2 as BasketballPlayerStats).rebounds.toString();
    }
    return Card(
      elevation: 2,
      child: Container(
          padding: const EdgeInsets.all(13),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(3),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(4),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              const TableRow(
                children: [
                  Text(""),
                  Text(""),
                  TableCell(verticalAlignment: TableCellVerticalAlignment.top, child: Text("Leaders", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold),)),
                  Text(""),
                  Text("")
                ]
              ),
              TableRow(
                children: [
                  Text(team1Stat1.name, textAlign: TextAlign.left),
                  Text(team1Stat1Val, textAlign: TextAlign.center),
                  Text(stat1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold),),
                  Text(team2Stat1Val, textAlign: TextAlign.center),
                  Text(team2Stat1.name, textAlign: TextAlign.right),
                ]
              ),
              const TableRow(
                children: [
                  Text(""),
                  Text(""),
                  Text(""),
                  Text(""),
                  Text("")
                ]
              ),
              TableRow(
                children: [
                  Text(team1Stat2.name, textAlign: TextAlign.left),
                  Text(team1Stat2Val, textAlign: TextAlign.center),
                  Text(stat2, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold),),
                  Text(team2Stat2Val, textAlign: TextAlign.center),
                  Text(team2Stat2.name, textAlign: TextAlign.right),
                ]
              ),
            ],
          )
        ), //Padding
    );
  }

  void populateActivities(Map<dynamic, dynamic> teamActivity, List<PlayerStats> teamPlayers, List<GameActivity> activities, Color color, String sourcePath) {
    teamActivity.forEach((k, v) {
      for (var history in v) {
        for (var action in history.keys) {
          activities.add(GameActivity(history[action], action, k, color, sourcePath));
        }
      }
    });
  }

  List<Widget> buildActivityList() {
    List<Widget> rows = List.empty(growable: true);
    activities.sort((a, b) {
      return compareValues(int.parse(a.time.substring(0, a.time.length-1)), int.parse(b.time.substring(0, b.time.length-1)), false);
    },);
    for (var activity in activities) {
      rows.add(Container(
        color: activity.color,
        child: Row(
          children: [
            Text(activity.time, style: TextStyle(color: activity.color.computeLuminance() > 0.5 ? Colors.black : Colors.white)), 
            Image.network(activity.teamImagePath, errorBuilder: (context, error, stackTrace) {
                          return const Text("");
                        }, width: windowsDefaultIconSize.toDouble()/1.5 , fit: BoxFit.scaleDown, alignment: FractionalOffset.centerLeft),
            Text(activity.name, style: TextStyle(color: activity.color.computeLuminance() > 0.5 ? Colors.black : Colors.white)),
            const Spacer(),
            Row(
              children: [
                Text(stringToGameText[activity.action]!, style: TextStyle(color: activity.color.computeLuminance() > 0.5 ? Colors.black : Colors.white)),
                stringToGameAction[activity.action]!
              ],
            )
          ]
        )
      ));
      rows.add(Divider(height: 1, thickness: 1, color: Theme.of(context).dividerColor,));
    }
    return rows;
  }

  void buildTeamPlayers(teamPlayers, teamLineup, teamActivity, Color teamColor, teamSourcePath) {
    if (teamPlayers.isEmpty) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        teamLineup.forEach((name, profile) {
          int goals = 0;
          int assists = 0;
          teamActivity.forEach((k, v) {
            for(var history in v) {
              for(var action in history.keys) {
                if (history[action] == name) {
                  if (action == "Goal") {
                    goals+=1;
                  } else if (action == "Assist") {
                    assists+=1;
                  }
                }
              }
            }
          });
          teamPlayers.add(FutsalPlayerStats(name, profile.number, profile.uid, goals, assists));
        });
      } else if (widget.sport == "Basketball") {
        teamLineup.forEach((name, profile) {
          int ones = 0;
          int twos = 0;
          int threes = 0;
          int fouls = 0;
          int rebounds = 0;
          teamActivity.forEach((k, v) {
            for(var history in v) {
              for(var action in history.keys) {
                if (history[action] == name) {
                  if (action == "OnePointer") {
                    ones+=1;
                  } else if (action == "TwoPointer") {
                    twos+=1;
                  } else if (action == "ThreePointer") {
                    threes+=1;
                  } else if (action == "Foul") {
                    fouls+=1;
                  } else if (action == "Rebound") {
                    rebounds+=1;
                  }
                }
              }
            }
          });
          teamPlayers.add(BasketballPlayerStats(name.toString(), profile.number, profile.uid, ones, twos, threes, fouls, rebounds));
        });
      }
    }
  }

  DataTable buildStatsTable(teamName, teamSourcePath, teamLineup, Color teamColor, teamActivity, teamPlayers, tableSortColumnIndex, tableIsAscending, onSort, setState) {
    if (teamPlayers.isEmpty) {
        buildTeamPlayers(teamPlayers, teamLineup, teamActivity, teamColor, teamSourcePath);
        sortTable(tableSortColumnIndex ?? 2, tableIsAscending, teamPlayers);
      }
    if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
      return DataTable(
        sortColumnIndex: tableSortColumnIndex,
        sortAscending: tableIsAscending,
        columnSpacing: 0,
        headingTextStyle: TextStyle(color: teamColor.computeLuminance() > 0.5 ? Colors.black : Colors.white),
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return teamColor; // Use the default value.
        }),
        columns: [
          DataColumn(label: Image.network(teamSourcePath, errorBuilder: (context, error, stackTrace) {
                          return const Text("");
                        }, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.centerLeft,)),
          DataColumn(label: Text(teamName), onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("Goals"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("Assists"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
        ], 
        rows: (teamPlayers as List).map((key) {
          return DataRow(cells: [
            DataCell(Text(key.number)),
            DataCell(Text(key.name), onTap: () {
              Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (mainContext) {
                      return PlayerPage(uid: key.uid);
                    })],
                )));
            },),
            DataCell(Text(key.goals.toString())),
            DataCell(Text(key.assists.toString())),
          ]);
        }).toList(),
      );
    } else if (widget.sport == "Basketball") {
      return DataTable(
        sortColumnIndex: tableSortColumnIndex,
        sortAscending: tableIsAscending,
        columnSpacing: 0,
        headingTextStyle: TextStyle(color: teamColor.computeLuminance() > 0.5 ? Colors.black : Colors.white),
        horizontalMargin: 10,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return teamColor; // Use the default value.
        }),
        columns: [
          const DataColumn(label: Text("")),
          DataColumn(label: Image.network(teamSourcePath, errorBuilder: (context, error, stackTrace) {
                          return const Text("");
                        }, width: windowsDefaultIconSize.toDouble(), alignment: FractionalOffset.center), onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("PTS"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("REB"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("2PM"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("3PM"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("FTM"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn(label: const Text("PF"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
        ], 
        rows: (teamPlayers as List).map((key) => DataRow(cells: [
            DataCell(Text(key.number)),
            DataCell(Text(key.name), onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (context) {
                      return PlayerPage(uid: key.uid);
                    })],
                )));
            },),
            DataCell(Text(key.total.toString())),
            DataCell(Text(key.rebounds.toString())),
            DataCell(Text(key.twos.toString())),
            DataCell(Text(key.threes.toString())),
            DataCell(Text(key.ones.toString())),
            DataCell(Text(key.fouls.toString())),
          ])).toList(),
      );
    }
    return DataTable(columns: const [DataColumn(label: Spacer())], rows: const []);
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return FutureBuilder(
      future: _loadingGame, 
      builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        List<Widget> tabs = List.empty(growable: true);
        List<Tab> tabNames = List.empty(growable: true);
        tabs.add(StatefulBuilder(
          builder: (context, setState) {
            return RefreshIndicator(
              onRefresh: () async {
                return _refreshData(setState);
              },
              child: ListView(
                    padding: const EdgeInsets.all(15),
                    children: buildItemList()
                )
              );
          },
        )
        );
        tabNames.add(Tab(text: game!.date));
        if (game is FutsalGame || game is BasketballGame || (game is SoccerGame && widget.game.team1 == "AFC San Jose")) {
          tabs.add(StatefulBuilder(
            builder: (context, setState) {
              buildTeamTables(setState);
              return RefreshIndicator(
                onRefresh: () async {
                  return _refreshData(setState);
                },
                child: ListView(children: [table1 ?? const Text("")],)
                );
            }
            )
          );
          tabNames.add(Tab(text: game!.team1));
        }
        if (game is FutsalGame || game is BasketballGame || (game is SoccerGame && widget.game.team2 == "AFC San Jose")) {
          tabs.add(StatefulBuilder(
            builder: (context, setState) {
              buildTeamTables(setState);
              return RefreshIndicator(
                onRefresh: () async {
                  return _refreshData(setState);
                },
                child: ListView(children: [table2 ?? const Text("")],)
                );
            }
            )
          );
          tabNames.add(Tab(text: game!.team2));
        }
        return DefaultTabController(
          length: tabs.length, 
          child: Scaffold(
            appBar: AppBar(
              title:  RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                    text: widget.sport,
                    style: TextStyle(fontSize: 20, color: Theme.of(context).colorScheme.inverseSurface),
                    children: <TextSpan>[
                      TextSpan(
                        text: '\n${widget.season}',
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ]
                ),
              ),
              actions: [
                IconButton(
                  onPressed: game!.link == "" ? null : () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                    initialEntries: [OverlayEntry(
                      builder: (context) {
                        WebViewController webController = WebViewController()
                          ..setBackgroundColor(const Color(0x00000000))
                          ..loadRequest(Uri.parse(game!.link));
                        return Scaffold(
                          appBar: AppBar(
                            title: const Text(""),
                            actions: [
                              NavigationControls(controller: webController)
                            ],
                          ),
                        body: WebViewStack(controller: webController,)
                        );
                      })],
                    )));
                  },
                icon: const ImageIcon(AssetImage('assets/watch.png')),
                )
              ],
              bottom: TabBar(
                tabs: tabNames,
                isScrollable: false,
                )
            ),
            body: TabBarView(
              children: tabs,
            )
          )
        );
      }
    );
  }

  Future<int> buildTeamTables(setState) async {
    if (widget.sport == "Futsal") {
      table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team1, game!.team1SourcePath, (game! as FutsalGame).team1lineup, team1color, game!.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
      table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team2, game!.team2SourcePath, (game! as FutsalGame).team2lineup, team2color, game!.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
    } else if (widget.sport == "AFC San Jose") {
      table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team1, game!.team1SourcePath, (game! as SoccerGame).team1lineup, team1color, game!.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
      table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team2, game!.team2SourcePath, (game! as SoccerGame).team2lineup, team2color, game!.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
    } else if (widget.sport == "Basketball") {
      table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team1, game!.team1SourcePath, (game! as BasketballGame).team1lineup, team1color, game!.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
      table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(game!.team2, game!.team2SourcePath, (game! as BasketballGame).team2lineup, team2color, game!.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
    } 
    return 1;
  }

  List<Widget> buildItemList() {
    if (game == null) {
      return List<Widget>.empty();
    }
    List<Widget> items = List<Widget>.empty(growable: true);
    List<Widget> informationRows = [
      Row(
        children: <Widget>[
          Expanded(child:Text(game!.stringStatus,textAlign: TextAlign.left, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: game!.statusColor))),
          Expanded(child:Text(game is SoccerGame && (game! as SoccerGame).startTime != "" ? (game! as SoccerGame).startTime : '${game!.Time.toString()}:00PM',textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
        ],
      ),
      Row(
        children: <Widget>[
          Column(
            children: <Widget>[
              Image.network(width: 70, game!.team1SourcePath, errorBuilder: (context, error, stackTrace) {
                return const Text("");
              },),
              SizedBox(width: 100, child: Text(game!.team1, textAlign: TextAlign.center,),),
            ],
          ),
          Expanded(
            child:
              Text(
                '${game!.team1score}-${game!.team2score}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 35,
                  fontWeight: FontWeight.bold,
                ))),
          Column(
            children: <Widget>[
              Image.network(width: 70, game!.team2SourcePath, errorBuilder: (context, error, stackTrace) {
                return const Text("");
              },),
              SizedBox(width: 100, child: Text(game!.team2, textAlign: TextAlign.center,),),
            ],
          ),
        ],
      ),
    ];
    if (game! is SoccerGame && widget.sport == "AFC San Jose") {
      informationRows.add(
        Row(
          children: [
            SizedBox(width: 150, child: Text((game! as SoccerGame).location, textAlign: TextAlign.left,),),
            Expanded(child: SizedBox(width: 150, child: Text((game! as SoccerGame).type, textAlign: TextAlign.right,),),)
          ],
        )
      );
    } else {
      informationRows.add(
        Row(
          children: <Widget>[
            CircularPercentIndicator(
                  radius: 30,
                  lineWidth: 4.0,
                  percent: game!.finalvote1,
                  center: Text(game!.percvote1),
                  progressColor: infiniteSportsPrimaryColor,
            ),
            Expanded(
              child: Visibility(
              maintainSize: true, 
              maintainAnimation: true,
              maintainState: true,
              visible: signedIn && !game!.voted && game!.status == 0,
              child: Column(
                children: <Widget>[
                  const Text('Poll', textAlign: TextAlign.center),
                  Container(
                    height: 40,
                    width: 80,
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                    child: TextButton(
                      onPressed: () {
                        showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => Dialog(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  TextButton(onPressed: () async {
                                    DatabaseReference newClient = FirebaseDatabase.instance.refFromURL("${game!.UrlPath}/${game!.GameNum}/team1vote/");
                                    await newClient.child(currentUser!.uid).set(1);
                                    Navigator.pop(context);
                                    await _refreshData(setState);
                                  }, child: Text(game!.team1),),
                                  TextButton(onPressed: () async {
                                    DatabaseReference newClient = FirebaseDatabase.instance.refFromURL("${game!.UrlPath}/${game!.GameNum}/team2vote/");
                                    await newClient.child(currentUser!.uid).set(1);
                                    Navigator.pop(context);
                                    await _refreshData(setState);
                                  }, child: Text(game!.team2),),
                                  const SizedBox(width: 15, height: 15,),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          ),);
                      },
                      child: const Text(
                        'Vote',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ),
            CircularPercentIndicator(
                  radius: 30,
                  lineWidth: 4.0,
                  percent: game!.finalvote2,
                  center: Text(game!.percvote2),
                  progressColor: infiniteSportsPrimaryColor,
            )
          ],
        )
      );
    }
    items.add(buildScoreCard(informationRows));
    if (game!.status != 0 && team1Players.isNotEmpty && team2Players.isNotEmpty) {
      items.add(buildTeamLeaders());
    }
    items.add(Padding(padding: const EdgeInsets.all(5), child: Column(children: buildActivityList()),));   
    return items;
  }

  Card buildScoreCard(informationRows) {
    return Card(
      elevation: 2,
      child: SizedBox(
        width: 300,
        height: 240,
        child: Container(
          padding: const EdgeInsets.all(13),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: informationRows
          )
        ), //Padding
      ), //SizedBox
    );
  }

  Future<void> _refreshData(localSetState) async { 
    // Add new items or update the data here 
    team1Players.clear();
    team2Players.clear();
    activities.clear();
    game = await getGame(widget, widget.sport, widget.season, convertStringDateToDatabase(game!.date), widget.times, game!.GameNum);
    _loadingGame = getGameData();
    await _loadingGame;
    await buildTeamTables(localSetState);
    if (mounted) {
      localSetState(() {});
    }
    widget.refreshCallback();
  } 

  void sortTable(int columnIndex, bool ascending, players) {
    if (columnIndex == 1) {
      players.sort((a, b) => 
        compareValues(a.name, b.name, ascending));
    } else if (columnIndex == 2) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        players.sort((a, b) => a.goals == b.goals ? compareValues(a.assists, b.assists, ascending) : compareValues(a.goals, b.goals, ascending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => a.total == b.total ? compareValues(a.rebounds, b.rebounds, ascending) : compareValues((a as BasketballPlayerStats).total, (b as BasketballPlayerStats).total, ascending));
      } 
    } else if (columnIndex == 3) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        players.sort((a, b) => a.assists == b.assists ? compareValues(a.goals, b.goals, ascending) : compareValues(a.assists, b.assists, ascending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => a.rebounds == b.rebounds ? compareValues(a.total, b.total, ascending) : compareValues((a as BasketballPlayerStats).rebounds, (b as BasketballPlayerStats).rebounds, ascending));
      }
    } else if (columnIndex == 4) {
      if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).twos, (b as BasketballPlayerStats).twos, ascending));
      }
    } else if (columnIndex == 5) {
      if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).threes, (b as BasketballPlayerStats).threes, ascending));
      }
    } else if (columnIndex == 6) {
      if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).ones, (b as BasketballPlayerStats).ones, ascending));
      }
    } else if (columnIndex == 7) {
      if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).fouls, (b as BasketballPlayerStats).fouls, ascending));
      }
    }
  }

  void onSort1(int columnIndex, bool ascending, setState) {
    setState(() {
      table1SortColumnIndex = columnIndex;
      table1isAscending = ascending;
    });
    sortTable(columnIndex, ascending, team1Players);
  }

  void onSort2(int columnIndex, bool ascending, setState) {
    setState(() {
      table2SortColumnIndex = columnIndex;
      table2isAscending = ascending;
    });
    sortTable(columnIndex, ascending, team2Players);
  }
}
