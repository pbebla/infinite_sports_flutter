import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/main.dart';
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

Map<String,Widget> stringToGameAction = {
  "OnePointer": Row(children: [const Text("FT"), Image.asset("assets/onepointer.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "TwoPointer": Row(children: [const Text("FG"), Image.asset("assets/twopointer.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "ThreePointer": Row(children: [const Text("3PT"), Image.asset("assets/threepointer.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Rebound": Row(children: [const Text("REB"), Image.asset("assets/rebound.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Foul": Row(children: [const Text("Foul"), Image.asset("assets/foul.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Goal": Row(children: [const Text("Goal"), Image.asset("assets/goal.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Assist": Row(children: [const Text("Assist"), Image.asset("assets/assist.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Yellow": Row(children: [const Text("Yellow"), Image.asset("assets/yellow.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Blue": Row(children: [const Text("Blue"), Image.asset("assets/blue.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
  "Red": Row(children: [const Text("Red"), Image.asset("assets/red.png", height: windowsDefaultIconSize.toDouble()/1.5,)],),
};

typedef TitleCallback = void Function(String value);

class ScorePage extends StatefulWidget {
  ScorePage({super.key, required this.sport, required this.season, required this.game, required this.times});
  //final TitleCallback onTitleSelect;

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;
  Game game;
  final String sport;
  final String season;
  final Map<String, Map<String, int>> times;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  List<Widget> items = List.empty(growable: true);
  List<PlayerStats> team1Players = List.empty(growable: true);
  List<PlayerStats> team2Players = List.empty(growable: true);
  List<GameActivity> activities = List.empty(growable: true);
  ColorScheme team1color  = const ColorScheme.dark();
  ColorScheme team2color = const ColorScheme.dark();
  int? table1SortColumnIndex;
  int? table2SortColumnIndex;
  bool table1isAscending = false;
  bool table2isAscending = false;
  late SingleChildScrollView table1;
  late SingleChildScrollView table2;
  late Widget _player;

  Future<int> getGameData(setState) async {
    if (widget.game.team1SourcePath != "") {
      team1color = await ColorScheme.fromImageProvider(provider: NetworkImage(widget.game.team1SourcePath));
    }
    if (widget.game.team2SourcePath != "") {
      team2color = await ColorScheme.fromImageProvider(provider: NetworkImage(widget.game.team2SourcePath));
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
      shadowColor: Colors.black,
      color: Colors.white,
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
            Text(activity.time), 
            Image.network(activity.teamImagePath, errorBuilder: (context, error, stackTrace) {
                          return const Text("");
                        }, width: windowsDefaultIconSize.toDouble()/1.5 , fit: BoxFit.scaleDown, alignment: FractionalOffset.centerLeft),
            Text(activity.name),
            const Spacer(),
            stringToGameAction[activity.action]!,],
          )
        )
      );
      rows.add(const Divider(height: 1, thickness: 1, color: Colors.black,));
    }
    return rows;
  }

  void buildTeamPlayers(teamPlayers, teamLineup, teamActivity, teamColor, teamSourcePath) {
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
                  activities.add(GameActivity(name, action, k, teamColor.inversePrimary, teamSourcePath));
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
                  activities.add(GameActivity(name.toString(), action, k, teamColor.inversePrimary, teamSourcePath));
                }
              }
            }
          });
          teamPlayers.add(BasketballPlayerStats(name.toString(), profile.number, profile.uid, ones, twos, threes, fouls, rebounds));
        });
      }
    }
  }

  DataTable buildStatsTable(teamName, teamSourcePath, teamLineup, teamColor, teamActivity, teamPlayers, tableSortColumnIndex, tableIsAscending, onSort, setState) {
    if (teamPlayers.isEmpty) {
        buildTeamPlayers(teamPlayers, teamLineup, teamActivity, teamColor, teamSourcePath);
        sortTable(tableSortColumnIndex ?? 2, tableIsAscending, teamPlayers);
      }
    if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
      return DataTable(
        sortColumnIndex: tableSortColumnIndex,
        sortAscending: tableIsAscending,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return teamColor.inversePrimary; // Use the default value.
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (context) {
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
        horizontalMargin: 10,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return teamColor.inversePrimary; // Use the default value.
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
      future: getGameData(setState), 
      builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        if (widget.sport == "Futsal") {
          buildTeamPlayers(team1Players, (widget.game as FutsalGame).team1lineup, widget.game.team1activity, team1color, widget.game.team1SourcePath);
          buildTeamPlayers(team2Players, (widget.game as FutsalGame).team2lineup, widget.game.team2activity, team2color, widget.game.team2SourcePath);
        } else if (widget.sport == "AFC San Jose") {
          if (widget.game.team1 == "AFC San Jose") {
            buildTeamPlayers(team1Players, (widget.game as SoccerGame).team1lineup, widget.game.team1activity, team1color, widget.game.team1SourcePath);
          } else {
            buildTeamPlayers(team2Players, (widget.game as SoccerGame).team2lineup, widget.game.team2activity, team2color, widget.game.team2SourcePath);
          }
        } else if (widget.sport == "Basketball") {
          buildTeamPlayers(team1Players, (widget.game as BasketballGame).team1lineup, widget.game.team1activity, team1color, widget.game.team1SourcePath);
          buildTeamPlayers(team2Players, (widget.game as BasketballGame).team2lineup, widget.game.team2activity, team2color, widget.game.team2SourcePath);
        }
        if (widget.sport == "AFC San Jose") {
          if (widget.game.team1 == "AFC San Jose") {
            sortTable(table1SortColumnIndex ?? 2, table1isAscending, team1Players);
          } else {
            sortTable(table2SortColumnIndex ?? 2, table2isAscending, team2Players);
          }
        } else {
          sortTable(table1SortColumnIndex ?? 2, table1isAscending, team1Players);
          sortTable(table2SortColumnIndex ?? 2, table2isAscending, team2Players);
        }
        buildItemList();
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
                    children: items
                )
              );
          },
        )
        );
        tabNames.add(Tab(text: widget.game.date));
        if (widget.game.status != 0) {
          if (widget.game is SoccerGame) {
            if (widget.game.team1 == "AFC San Jose") {
              tabs.add(StatefulBuilder(
                builder: (context, setState) {
                  buildTeamTables(setState);
                  return RefreshIndicator(
                    onRefresh: () async {
                      return _refreshData(setState);
                    },
                    child: ListView(children: [table1],)
                    );
                }
                )
              );
              tabNames.add(Tab(text: widget.game.team1));
            } else {
              tabs.add(StatefulBuilder(
                builder: (context, setState) {
                  buildTeamTables(setState);
                  return RefreshIndicator(
                    onRefresh: () async {
                      return _refreshData(setState);
                    },
                    child: ListView(children: [table2],)
                    );
                }
                )
              );
              tabNames.add(Tab(text: widget.game.team2));
            }
          } else {
            tabs.add(StatefulBuilder(
              builder: (context, setState) {
                buildTeamTables(setState);
                return RefreshIndicator(
                  onRefresh: () async {
                    return _refreshData(setState);
                  },
                  child: ListView(children: [table1],)
                  );
              }
              )
            );
            tabs.add(StatefulBuilder(
              builder: (context, setState) {
                buildTeamTables(setState);
                return RefreshIndicator(
                  onRefresh: () async {
                    return _refreshData(setState);
                  },
                  child: ListView(children: [table2],)
                  );
              }
              )
            );
            tabNames.add(Tab(text: widget.game.team1));
            tabNames.add(Tab(text: widget.game.team2));
          }
        }
        return DefaultTabController(
          length: tabs.length, 
          child: Scaffold(
            appBar: AppBar(
              title: Text("${widget.sport} Season ${widget.season}"),
              actions: [
                IconButton(
                  onPressed: widget.game.link == "" ? null : () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                    initialEntries: [OverlayEntry(
                      builder: (context) {
                        WebViewController webController = WebViewController()
                          ..setBackgroundColor(const Color(0x00000000))
                          ..loadRequest(Uri.parse(widget.game.link));
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
    if (widget.game.status != 0) {
      if (widget.sport == "Futsal") {
        table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team1, widget.game.team1SourcePath, (widget.game as FutsalGame).team1lineup, team1color, widget.game.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
        table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team2, widget.game.team2SourcePath, (widget.game as FutsalGame).team2lineup, team2color, widget.game.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
      } else if (widget.sport == "AFC San Jose") {
        table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team1, widget.game.team1SourcePath, (widget.game as SoccerGame).team1lineup, team1color, widget.game.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
        table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team2, widget.game.team2SourcePath, (widget.game as SoccerGame).team2lineup, team2color, widget.game.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
      } else if (widget.sport == "Basketball") {
        table1 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team1, widget.game.team1SourcePath, (widget.game as BasketballGame).team1lineup, team1color, widget.game.team1activity, team1Players, table1SortColumnIndex, table1isAscending, onSort1, setState)));
        table2 = SingleChildScrollView(child: ConstrainedBox(constraints: BoxConstraints.expand(width: MediaQuery.of(context).size.width, height: MediaQuery.of(context).size.height), child: buildStatsTable(widget.game.team2, widget.game.team2SourcePath, (widget.game as BasketballGame).team2lineup, team2color, widget.game.team2activity, team2Players, table2SortColumnIndex, table2isAscending, onSort2, setState)));
      }
    } 
    return 1;
  }

  void buildItemList() {
    List<Widget> informationRows = [
        Row(
          children: <Widget>[
            Expanded(child:Text(widget.game.stringStatus,textAlign: TextAlign.left, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: widget.game.statusColor))),
            Expanded(child:Text(widget.game is SoccerGame && (widget.game as SoccerGame).startTime != "" ? (widget.game as SoccerGame).startTime : '${widget.game.Time.toString()}:00PM',textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
          ],
        ),
        Row(
          children: <Widget>[
            Column(
              children: <Widget>[
                Image.network(width: 70, widget.game.team1SourcePath, errorBuilder: (context, error, stackTrace) {
                  return const Text("");
                },),
                SizedBox(width: 100, child: Text(widget.game.team1, textAlign: TextAlign.center,),),
              ],
            ),
            Expanded(
              child:
                Text(
                  '${widget.game.team1score}-${widget.game.team2score}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.bold,
                  ))),
            Column(
              children: <Widget>[
                Image.network(width: 70, widget.game.team2SourcePath, errorBuilder: (context, error, stackTrace) {
                  return const Text("");
                },),
                SizedBox(width: 100, child: Text(widget.game.team2, textAlign: TextAlign.center,),),
              ],
            ),
          ],
        ),
      ];
      if (widget.game is SoccerGame && widget.sport == "AFC San Jose") {
        informationRows.add(
          Row(
            children: [
              SizedBox(width: 150, child: Text((widget.game as SoccerGame).location, textAlign: TextAlign.left,),),
              Expanded(child: SizedBox(width: 150, child: Text((widget.game as SoccerGame).type, textAlign: TextAlign.right,),),)
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
                    percent: widget.game.finalvote1,
                    center: Text(widget.game.percvote1),
                    progressColor: infiniteSportsPrimaryColor,
              ),
              Expanded(
                child: Visibility(
                maintainSize: true, 
                maintainAnimation: true,
                maintainState: true,
                visible: signedIn && !widget.game.voted && widget.game.status == 0,
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
                                      DatabaseReference newClient = FirebaseDatabase.instance.refFromURL("${widget.game.UrlPath}/${widget.game.GameNum}/team1vote/");
                                      await newClient.child(auth.credential!.user!.uid).set(1);
                                      Navigator.pop(context);
                                      await _refreshData(setState);
                                    }, child: Text(widget.game.team1),),
                                    TextButton(onPressed: () async {
                                      DatabaseReference newClient = FirebaseDatabase.instance.refFromURL("${widget.game.UrlPath}/${widget.game.GameNum}/team2vote/");
                                      await newClient.child(auth.credential!.user!.uid).set(1);
                                      Navigator.pop(context);
                                      await _refreshData(setState);
                                    }, child: Text(widget.game.team2),),
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
                    percent: widget.game.finalvote2,
                    center: Text(widget.game.percvote2),
                    progressColor: infiniteSportsPrimaryColor,
              )
            ],
          )
        );
      }

      Card card = Card(
        elevation: 2,
        shadowColor: Colors.black,
        color: Colors.white,
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
    items.add(card);
    if (widget.game.status != 0 && team1Players.isNotEmpty && team2Players.isNotEmpty) {
      items.add(buildTeamLeaders());
      items.add(Column(children: buildActivityList()));   
    }
  }

  Future<void> _refreshData(setState) async { 
    // Add new items or update the data here 
    widget.game = await getGame(widget, widget.sport, widget.season, convertStringDateToDatabase(widget.game.date), widget.times, widget.game.GameNum);
    team1Players = [];
    team2Players = [];
    activities = [];
    await getGameData(setState);
    await buildTeamTables(setState);
    items = [];
    buildItemList();
    setState(() {
    });
  } 

  void sortTable(int columnIndex, bool ascending, players) {
    if (columnIndex == 1) {
      players.sort((a, b) => 
        compareValues(a.name, b.name, ascending));
    } else if (columnIndex == 2) {
      if (widget.sport == "Futsal") {
        players.sort((a, b) => compareValues((a as FutsalPlayerStats).goals, (b as FutsalPlayerStats).goals, ascending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).total, (b as BasketballPlayerStats).total, ascending));
      }
    } else if (columnIndex == 3) {
      if (widget.sport == "Futsal") {
        players.sort((a, b) => compareValues((a as FutsalPlayerStats).assists, (b as FutsalPlayerStats).assists, ascending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayerStats).rebounds, (b as BasketballPlayerStats).rebounds, ascending));
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
