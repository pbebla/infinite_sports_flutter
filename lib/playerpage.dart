
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/botnavbar.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/basketballplayerstats.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayerstats.dart';
import 'package:infinite_sports_flutter/model/leaguemenu.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/showleague.dart';

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
  List<String> sports = ["Futsal", "Basketball"];
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
          var color = await ColorScheme.fromImageProvider(provider: NetworkImage(teamLogos[sport][season][team]));
          info.teamPath = teamLogos[sport][season][team];
          if (firstName.isEmpty) {
            firstName = info.name.split(' ')[0];
            lastName = info.name.split(' ')[1];
          }
          data = (team, color.inversePrimary, info);
          
        }
      });
    } else if (sport == "Futsal") {
      await Future.forEach((futsalLineups[season]![team]!.entries), (entry) async {
        var name = entry.key;
        var info = entry.value;
        if (info.uid == widget.uid) {
          var color = await ColorScheme.fromImageProvider(provider: NetworkImage(teamLogos[sport][season][team]));
          info.teamPath = teamLogos[sport][season][team];
          if (firstName.isEmpty) {
            firstName = info.name.split(' ')[0];
            lastName = info.name.split(' ')[1];
          }
          data = (team, color.inversePrimary, info);
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
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: getPlayerData(), 
      builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text("Profile"),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Row(
                children: [
                  Expanded(child: profileImagePath != "" ? Image.network(profileImagePath, ) : Image.asset("assets/portraitplaceholder.png")),
                  Expanded(child: Column(children: [
                    FittedBox(fit: BoxFit.fitWidth, child: Text(firstName, style: TextStyle(fontSize: Theme.of(context).textTheme.displayMedium!.fontSize)),),
                    FittedBox(fit: BoxFit.fitWidth, child: Text(lastName, style: TextStyle(fontSize: Theme.of(context).textTheme.displaySmall!.fontSize))),
                    Text("$height")
                  ],))
                ],
              ),
              Expanded(child: SizedBox(width: MediaQuery.of(context).size.width, child: ListView.builder(
                itemCount: sports.length,
                itemBuilder: (context, index) {
                  if (sports[index] == "Basketball") {
                    if (tableEntries.containsKey(sports[index])) {
                      List<DataRow> rows = List.empty(growable: true);
                      tableEntries[sports[index]]!.forEach((season, info) {
                        rows.add(DataRow(cells: [
                          DataCell(Text(season)),
                          DataCell(Container(color: info.$2, child: Row(children: [Image.network((info.$3 as BasketballPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), errorBuilder:(context, error, stackTrace) => Text("")), Text(info.$1)],),)),
                          //DataCell(Text(info.$3.number)),
                          DataCell(Text((info.$3 as BasketballPlayer).total.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).rebounds.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).twoPoints.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).threePoints.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).onePoint.toString())),
                          DataCell(Text((info.$3 as BasketballPlayer).shotPercentage)),
                        ]));
                      });
                      rows.sort((a, b) => (int.parse((b.cells[0].child as Text).data.toString() ?? '0').compareTo(int.parse((a.cells[0].child as Text).data.toString() ?? '0'),)));
                      return Column(children: [
                        Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                        Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                        DataTable(
                          horizontalMargin: 5,
                          columnSpacing: 5,
                          columns: [
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
                        Divider(thickness: 0.5, color: Colors.black,)
                      ],
                      );
                    }
                  }
                  else if (sports[index] == "Futsal") {
                    if (tableEntries.containsKey(sports[index])) {
                      List<DataRow> rows = List.empty(growable: true);
                      tableEntries[sports[index]]!.forEach((season, info) {
                          rows.add(DataRow(cells: [
                            DataCell(Text(season)),
                            DataCell(Container(color: info.$2, constraints: BoxConstraints.expand(), child: Row(children: [Image.network((info.$3 as FutsalPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), errorBuilder:(context, error, stackTrace) => Text(""),), Text(info.$1)],),)),
                            //DataCell(Text(info.$3.number)),
                            DataCell(Text((info.$3 as FutsalPlayer).goals.toString())),
                            DataCell(Text((info.$3 as FutsalPlayer).assists.toString())),
                            DataCell(Text((info.$3 as FutsalPlayer).saves.toString())),
                          ]));
                      });
                      rows.sort((a, b) => (int.parse((b.cells[0].child as Text).data.toString() ?? '0').compareTo(int.parse((a.cells[0].child as Text).data.toString() ?? '0'),)));
                      return Column(children: [
                        Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                        Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                        DataTable(
                          horizontalMargin: 5,
                          columnSpacing: 5,
                          columns: [
                            DataColumn(label: Text("Season"), numeric: true),
                            DataColumn(label: Text("Team")),
                            //DataColumn(label: Text("#"), numeric: true),
                            DataColumn(label: Text("Goals"), numeric: true),
                            DataColumn(label: Text("Assists"), numeric: true),
                            DataColumn(label: Text("Saves"), numeric: true),
                          ], 
                          rows: rows
                        ),
                        Divider(thickness: 0.5, color: Colors.black,)
                      ],
                      );
                    }
                  }
                  return Text("");
                }
              ),
            )
          )
              ]
            )
        );
      }
    );
  }
}