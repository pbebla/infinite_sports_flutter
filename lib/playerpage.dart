
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:palette_generator/palette_generator.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.uid});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;
  final String uid;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  List<String> sports = ["Futsal", "Basketball", "AFC San Jose"];
  //Sport, Season, (Team, Team Color, Player Info)
  Map<String, Map<String, (String, Color, Player)>> tableEntries = {};
  Map<String, String> sportPositions = {};
  String firstName = "";
  String lastName = "";
  String profileImagePath = "";
  String height = "";
  int age = 0;
  Map player = {};

  Future<(String, Color, Player)> extractPlayerStatsHelper(sport, season, team) async {
    await getAllTeamLogo();
    (String, Color, Player) data = ("", Colors.black, BasketballPlayer());
    if (sport == "Basketball") {
      await Future.forEach((basketballLineups[season]![team]!.entries), (entry) async {
        var name = entry.key;
        var info = entry.value;
        if (info.uid == widget.uid) {
          var color = await PaletteGenerator.fromImageProvider(NetworkImage(teamLogos[sport][season][team]));
          info.teamPath = teamLogos[sport][season][team];
          if (firstName.isEmpty) {
            firstName = info.name.split(' ')[0];
            lastName = info.name.split(' ')[1];
          }
          data = (team, color.dominantColor?.color ?? const Color.fromARGB(255, 124, 124, 124), info);
          
        }
      });
    } else if (sport == "Futsal") {
      await Future.forEach((futsalLineups[season]![team]!.entries), (entry) async {
        var name = entry.key;
        var info = entry.value;
        if (info.uid == widget.uid) {
          var color = await PaletteGenerator.fromImageProvider(NetworkImage(teamLogos[sport][season][team]));
          info.teamPath = teamLogos[sport][season][team];
          if (firstName.isEmpty) {
            firstName = info.name.split(' ')[0];
            lastName = info.name.split(' ')[1];
          }
          data = (team, color.dominantColor?.color ?? const Color.fromARGB(255, 124, 124, 124), info);
        }
      });
    }
    return data;
  }

  Future<(String, Color, Player)> extractPlayerStats(sport, season, team) async {
    var val = await extractPlayerStatsHelper(sport, season, team);
    if (val.$1 != "") {
      return val;
    }
    if (sport == "Basketball") {
      for (var other in basketballLineups[season]!.keys) {
        if (other != team) {
          val = await extractPlayerStatsHelper(sport, season, other);
          if (val.$1 != "") {
            return val;
          }
        }
      }
    } else if (sport == "Futsal") {
      for (var other in futsalLineups[season]!.keys) {
        if (other != team) {
          val = await extractPlayerStatsHelper(sport, season, other);
          if (val.$1 != "") {
            return val;
          }
        }
      }
    }
    return val;
  }

  Future<void> extractAFCStats() async {
    var seasons = await getSoccerSeasons("AFC San Jose");
    await Future.forEach(seasons, (season) async {
      var roster = await getSoccerRoster("AFC San Jose", season);
      roster.forEach((name, info) {
        if (info.uid == widget.uid) {
          if (!tableEntries.containsKey("AFC San Jose")) {
            tableEntries["AFC San Jose"] = {};
          }
          tableEntries["AFC San Jose"]![season] = (season, Colors.white, info);
        }
      });
    });

  }

  Future<int> getPlayerData() async {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var event = await newClient.child("Users/${widget.uid}").get();
    player = event.value as Map;
    firstName = player["First Name"] ?? "";
    lastName = player["Last Name"] ?? "";
    profileImagePath = player["ProfileUrl"] ?? "";
    height = player["Information"]["Height"] ?? "";
    age = player["Information"]["Age"] ?? 0;
    await Future.forEach((player["Played"] as Map).entries, (entry) async {
      var sport = entry.key;
      var seasons = entry.value;
      await Future.forEach((seasons as Map).entries, (entry2) async {
        var season = entry2.key;
        var team = entry2.value;
        var seasonNum = season.split(' ')[1];
        if (sport == "Futsal") {
          sportPositions[sport] = player["Information"]["${sport}Position"] ?? "";
          await getAllFutsalLineUps(seasonNum);
          if (!tableEntries.containsKey(sport)) {
            tableEntries[sport] = {};
          }
          tableEntries[sport]![seasonNum] = await extractPlayerStats(sport, seasonNum, team);
        } else if (sport == "Basketball") {
          sportPositions[sport] = player["Information"]["${sport}Position"] ?? "";
          await getAllBasketballLineUps(seasonNum);
          if (!tableEntries.containsKey(sport)) {
              tableEntries[sport] = {};
          }
          tableEntries[sport]![seasonNum] = await extractPlayerStats(sport, seasonNum, team);
        }
      });
    });
    await extractAFCStats();
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: getPlayerData(),
        builder: (context, snapshot) {
          if(snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                )
              );
          }
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: SizedBox.fromSize(
                      size: const Size.fromHeight(200),
                      child: profileImagePath != "" ? Image.network(profileImagePath, fit: BoxFit.contain,) : Image.asset("assets/portraitplaceholder.png"),
                    ),
                  ),),
                  //Expanded(child: profileImagePath != "" ? Image.network(profileImagePath, ) : Image.asset("assets/portraitplaceholder.png")),
                  Expanded(child: Column(children: [
                    FittedBox(fit: BoxFit.fitWidth, child: Text(firstName, style: TextStyle(fontSize: Theme.of(context).textTheme.displayMedium!.fontSize)),),
                    FittedBox(fit: BoxFit.fitWidth, child: Text(lastName, style: TextStyle(fontSize: Theme.of(context).textTheme.displaySmall!.fontSize))),
                    Text(height)
                  ],))
                ],
              ),
              Flexible(child: SizedBox(width: MediaQuery.of(context).size.width, child: ListView.builder(
                itemCount: sports.length,
                itemBuilder: (context, index) {
                  if (sports[index] == "Basketball") {
                    if (tableEntries.containsKey(sports[index])) {
                      List<DataRow> rows = List.empty(growable: true);
                      BasketballPlayer career = BasketballPlayer();
                      tableEntries[sports[index]]!.forEach((season, info) {
                        rows.add(DataRow(cells: [
                          DataCell(Text(season)),
                          DataCell(Container(color: info.$2, child: Row(children: [Image.network((info.$3 as BasketballPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), errorBuilder:(context, error, stackTrace) => const Text("")), Text(info.$1, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white))],),)),
                          //DataCell(Text(info.$3.number)),
                          DataCell(Text((info.$3 as BasketballPlayer).total.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).rebounds.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).twoPoints.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).threePoints.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).onePoint.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).shotPercentage)),
                        ]));
                        career.onePoint += (info.$3 as BasketballPlayer).onePoint;
                        career.twoPoints += (info.$3 as BasketballPlayer).twoPoints;
                        career.threePoints += (info.$3 as BasketballPlayer).threePoints;
                        career.total += (info.$3 as BasketballPlayer).total;
                        career.rebounds += (info.$3 as BasketballPlayer).rebounds;
                        career.misses += (info.$3 as BasketballPlayer).misses;
                      });
                      rows.sort((a, b) => (int.parse((b.cells[0].child as Text).data.toString() ?? '0').compareTo(int.parse((a.cells[0].child as Text).data.toString() ?? '0'),)));
                      career.getPercentage();
                      rows.add(DataRow(cells: [
                        const DataCell(Text("")),
                        const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                        DataCell(Text(career.total.toString())),
                        DataCell(Text(career.rebounds.toString())),
                        DataCell(Text(career.twoPoints.toString())),
                        DataCell(Text(career.threePoints.toString())),
                        DataCell(Text(career.onePoint.toString())),
                        DataCell(Text(career.shotPercentage)),
                      ]));
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Column(children: [
                          Divider(thickness: 0.5, color: Theme.of(context).dividerColor),
                          Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                          Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                          DataTable(
                            horizontalMargin: 5,
                            columnSpacing: 5,
                            columns: const [
                              DataColumn(label: Text("Season"), numeric: true),
                              DataColumn(label: Text("Team")),
                              //DataColumn(label: Text("#"), numeric: true),
                              DataColumn(label: Text("PTS"), numeric: true),
                              DataColumn(label: Text("REB"), numeric: true),
                              DataColumn(label: Text("2PM"), numeric: true),
                              DataColumn(label: Text("3PM"), numeric: true),
                              DataColumn(label: Text("FTM"), numeric: true),
                              DataColumn(label: Text("FG%"), numeric: true),
                            ], 
                            rows: rows
                          ),
                      ],
                      ),
                      );
                    }
                  }
                  else if (sports[index] == "Futsal") {
                    if (tableEntries.containsKey(sports[index])) {
                      List<DataRow> rows = List.empty(growable: true);
                      FutsalPlayer career = FutsalPlayer();
                      tableEntries[sports[index]]!.forEach((season, info) {
                          rows.add(DataRow(cells: [
                            DataCell(Text(season)),
                            DataCell(Container(color: info.$2, constraints: const BoxConstraints.expand(), child: Row(children: [Image.network((info.$3 as FutsalPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), errorBuilder:(context, error, stackTrace) => const Text(""),), Text(info.$1, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white),)],),)),
                            //DataCell(Text(info.$3.number)),
                            DataCell(Text((info.$3 as FutsalPlayer).goals.toString())),
                            DataCell(Text((info.$3 as FutsalPlayer).assists.toString())),
                            DataCell(Text((info.$3 as FutsalPlayer).saves.toString())),
                          ]));
                          career.goals += (info.$3 as FutsalPlayer).goals;
                          career.assists += (info.$3 as FutsalPlayer).assists;
                          career.saves += (info.$3 as FutsalPlayer).saves;
                      });
                      rows.sort((a, b) => (int.parse((b.cells[0].child as Text).data.toString() ?? '0').compareTo(int.parse((a.cells[0].child as Text).data.toString() ?? '0'),)));
                      rows.add(DataRow(cells: [
                          const DataCell(Text("")),
                          const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                          DataCell(Text(career.goals.toString())),
                          DataCell(Text(career.assists.toString())),
                          DataCell(Text(career.saves.toString())),
                        ]));
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Column(children: [
                          Divider(thickness: 0.5, color: Theme.of(context).dividerColor),
                          Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                          Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                          DataTable(
                            horizontalMargin: 5,
                            columnSpacing: 5,
                            columns: const [
                              DataColumn(label: Text("Season"), numeric: true),
                              DataColumn(label: Text("Team")),
                              //DataColumn(label: Text("#"), numeric: true),
                              DataColumn(label: Text("Goals"), numeric: true),
                              DataColumn(label: Text("Assists"), numeric: true),
                              DataColumn(label: Text("Saves"), numeric: true),
                            ], 
                            rows: rows
                          ),
                      ],
                      ),
                      );
                    }
                  }
                  else if (sports[index] == "AFC San Jose") {
                    if (tableEntries.containsKey(sports[index])) {
                      List<DataRow> rows = List.empty(growable: true);
                      SoccerPlayer career = SoccerPlayer();
                      tableEntries[sports[index]]!.forEach((season, info) {
                          rows.add(DataRow(cells: [
                            DataCell(Text(info.$1, softWrap: true,)),
                            //DataCell(Text(info.$3.number)),
                            DataCell(Text((info.$3 as SoccerPlayer).goals.toString())),
                            DataCell(Text((info.$3 as SoccerPlayer).assists.toString())),
                            DataCell(Text((info.$3 as SoccerPlayer).saves.toString())),
                          ]));
                          career.goals += (info.$3 as SoccerPlayer).goals;
                          career.assists += (info.$3 as SoccerPlayer).assists;
                          career.saves += (info.$3 as SoccerPlayer).saves;
                      });
                      rows.add(DataRow(cells: [
                          const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                          DataCell(Text(career.goals.toString())),
                          DataCell(Text(career.assists.toString())),
                          DataCell(Text(career.saves.toString())),
                        ]));
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: Column(children: [
                          Divider(thickness: 0.5, color: Theme.of(context).dividerColor,),
                          Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                          Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                          DataTable(
                            horizontalMargin: 5,
                            columnSpacing: 5,
                            columns: const [
                              DataColumn(label: Text("Season")),
                              //DataColumn(label: Text("#"), numeric: true),
                              DataColumn(label: Text("Goals"), numeric: true),
                              DataColumn(label: Text("Assists"), numeric: true),
                              DataColumn(label: Text("Saves"), numeric: true),
                            ], 
                            rows: rows
                          ),
                        ],
                        ),
                      );
                    }
                  }
                  return const Text("");
                }
              ),
            )
          )
              ]
            );
        }
      )
      
    );
  }
}