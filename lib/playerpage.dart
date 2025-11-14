
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/flagfootballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/model/soccerplayer.dart';
import 'package:palette_generator/palette_generator.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.uid});

  final String uid;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  List<String> sports = ["Futsal", "Basketball", "Flag Football", "AFC San Jose"];
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
    (String, Color, Player) data;
    if (sport == "Basketball") {
      data = ("", Colors.black, BasketballPlayer());
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
      data = ("", Colors.black, FutsalPlayer());
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
          data = (team, color.dominantColor?.color ?? Color.fromARGB(255, 124, 124, 124), info);
        }
      });
    } else {
      data = ("", Colors.black, FlagFootballPlayer());
      await Future.forEach((flagFootballLineups[season]![team]!.entries), (entry) async {
        var name = entry.key;
        var info = entry.value;
        if (info.uid == widget.uid) {
          var color = await PaletteGenerator.fromImageProvider(NetworkImage(teamLogos[sport][season][team]));
          info.teamPath = teamLogos[sport][season][team];
          if (firstName.isEmpty) {
            firstName = info.name.split(' ')[0];
            lastName = info.name.split(' ')[1];
          }
          data = (team, color.dominantColor?.color ?? Color.fromARGB(255, 124, 124, 124), info);
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
    } else if (sport == "Flag Football") {
      for (var other in flagFootballLineups[season]!.keys) {
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
        } else if (sport == "Flag Football") {
          sportPositions[sport] = player["Information"]["${sport}Position"] ?? "";
          await getAllFlagFootballLineUps(seasonNum);
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
        centerTitle: true,
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
          return LayoutBuilder(
            builder: (context, constraints) {
              return Column(
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: 125,
                  child: Padding(padding: EdgeInsets.fromLTRB(13, 0, 13, 0), child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(child: profileImagePath != "" ?
                          Center(child: CircleAvatar(backgroundImage: NetworkImage(profileImagePath), radius: 50),) :
                          Center(child: CircleAvatar(backgroundImage: AssetImage("assets/portraitplaceholder.png"), radius: 50),),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(13, 0, 0, 0),
                          child: Container(
                            alignment: Alignment.bottomCenter,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                FittedBox(fit: BoxFit.fitWidth, child: Text(firstName, style: TextStyle(fontSize: Theme.of(context).textTheme.displayMedium!.fontSize)),),
                                FittedBox(fit: BoxFit.fitWidth, child: Text(lastName, style: TextStyle(fontSize: Theme.of(context).textTheme.displaySmall!.fontSize))),
                                //Text(height)
                              ],
                            ),
                          )
                        )
                      )
                    ],
                  ),),
                ),
              ),
              Expanded(
                child: ListView.builder(
                    itemCount: sports.length,
                    itemBuilder: (context, index) {
                      if (sports[index] == "Basketball") {
                        if (tableEntries.containsKey(sports[index])) {
                          List<DataRow> rows = List.empty(growable: true);
                          BasketballPlayer career = BasketballPlayer();
                          tableEntries[sports[index]]!.forEach((season, info) {
                            rows.add(DataRow(
                              color: WidgetStateProperty.resolveWith((value) {
                                return info.$2;
                              }),
                              cells: [
                                DataCell(Center(child: Text(season, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Image.network((info.$3 as BasketballPlayer).teamPath, width: windowsDefaultIconSize.toDouble()/1.5, height: windowsDefaultIconSize.toDouble()/1.5, errorBuilder:(context, error, stackTrace) => const Text("")),),
                                DataCell(Text(info.$1, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).total.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).rebounds.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).twoPoints.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).threePoints.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).onePoint.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                DataCell(Center(child: Text((info.$3 as BasketballPlayer).shotPercentage, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                            ]));
                            career.onePoint += (info.$3 as BasketballPlayer).onePoint;
                            career.twoPoints += (info.$3 as BasketballPlayer).twoPoints;
                            career.threePoints += (info.$3 as BasketballPlayer).threePoints;
                            career.total += (info.$3 as BasketballPlayer).total;
                            career.rebounds += (info.$3 as BasketballPlayer).rebounds;
                            career.misses += (info.$3 as BasketballPlayer).misses;
                          });
                          rows.sort((a, b) => (int.parse(((a.cells[0].child as Center).child as Text).data.toString() ?? '0').compareTo(int.parse(((b.cells[0].child as Center).child as Text).data.toString() ?? '0'),)));
                          career.getPercentage();
                          rows.add(DataRow(cells: [
                            const DataCell(Text("")),
                            const DataCell(Text("")),
                            const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                            DataCell(Center(child: Text(career.total.toString()))),
                            DataCell(Center(child: Text(career.rebounds.toString()))),
                            DataCell(Center(child: Text(career.twoPoints.toString()))),
                            DataCell(Center(child: Text(career.threePoints.toString()))),
                            DataCell(Center(child: Text(career.onePoint.toString()))),
                            DataCell(Center(child: Text(career.shotPercentage))),
                          ]));
                          return Column(children: [
                              Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                              Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                              DataTable(
                                columnSpacing: 5,
                                columns: const [
                                  DataColumn(label: Text("Season"), numeric: true),
                                  DataColumn(label: Text(""), numeric: true),
                                  DataColumn(label: Text("Team")),
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
                          );
                        }
                      }
                      else if (sports[index] == "Futsal") {
                        if (tableEntries.containsKey(sports[index])) {
                          List<DataRow> rows = List.empty(growable: true);
                          FutsalPlayer career = FutsalPlayer();
                          tableEntries[sports[index]]!.forEach((season, info) {
                              rows.add(DataRow(
                                color: WidgetStateProperty.resolveWith((value) {
                                  return info.$2;
                                }),
                                cells: [
                                  DataCell(Center(child: Text(season, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Image.network((info.$3 as FutsalPlayer).teamPath, width: windowsDefaultIconSize.toDouble()/1.5, height: windowsDefaultIconSize.toDouble()/1.5, errorBuilder:(context, error, stackTrace) => const Text(""),)),
                                  DataCell(Text(info.$1, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white))),
                                  DataCell(Center(child: Text((info.$3 as FutsalPlayer).goals.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FutsalPlayer).assists.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FutsalPlayer).saves.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                ]));
                              career.goals += (info.$3 as FutsalPlayer).goals;
                              career.assists += (info.$3 as FutsalPlayer).assists;
                              career.saves += (info.$3 as FutsalPlayer).saves;
                          });
                          rows.sort((a, b) => (int.parse(((a.cells[0].child as Center).child as Text).data.toString() ?? '0').compareTo(int.parse(((b.cells[0].child as Center).child as Text).data.toString() ?? '0'),)));
                          rows.add(DataRow(cells: [
                              const DataCell(Text("")),
                              const DataCell(Text("")),
                              const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                              DataCell(Center(child: Text(career.goals.toString()),)),
                              DataCell(Center(child: Text(career.assists.toString()),)),
                              DataCell(Center(child: Text(career.saves.toString()),)),
                            ]));
                          return Column(children: [
                              Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                              Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                              DataTable(
                                columnSpacing: 16,
                                columns: const [
                                  DataColumn(label: Text("Season"), numeric: true),
                                  DataColumn(label: Text(""), numeric: true),
                                  DataColumn(label: Text("Team")),
                                  DataColumn(label: Text("Goals"), numeric: true),
                                  DataColumn(label: Text("Assists"), numeric: true),
                                  DataColumn(label: Text("Saves"), numeric: true),
                                ], 
                                rows: rows
                              ),
                          ],
                          );
                        }
                      }
                      else if (sports[index] == "Flag Football") {
                        if (tableEntries.containsKey(sports[index])) {
                          List<DataRow> rows = List.empty(growable: true);
                          FlagFootballPlayer career = FlagFootballPlayer();
                          tableEntries[sports[index]]!.forEach((season, info) {
                              rows.add(DataRow(
                                color: WidgetStateProperty.resolveWith((value) {
                                  return info.$2;
                                }),
                                cells: [
                                  DataCell(Center(child: Text(season, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Image.network((info.$3 as FlagFootballPlayer).teamPath, width: windowsDefaultIconSize.toDouble()/1.5, height: windowsDefaultIconSize.toDouble()/1.5, errorBuilder:(context, error, stackTrace) => const Text(""),)),
                                  DataCell(Text(info.$1, style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).receptions.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).receivingTouchdowns.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).passBreakups.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).interceptions.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).passingTouchdowns.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).sacks.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                  DataCell(Center(child: Text((info.$3 as FlagFootballPlayer).flagPulls.toString(), style: TextStyle(color: info.$2.computeLuminance() > 0.5 ? Colors.black : Colors.white)))),
                                ]));
                              career.receptions += (info.$3 as FlagFootballPlayer).receptions;
                              career.receivingTouchdowns += (info.$3 as FlagFootballPlayer).receivingTouchdowns;
                              career.passBreakups += (info.$3 as FlagFootballPlayer).passBreakups;
                              career.interceptions += (info.$3 as FlagFootballPlayer).interceptions;
                              career.passingTouchdowns += (info.$3 as FlagFootballPlayer).passingTouchdowns;
                              career.sacks += (info.$3 as FlagFootballPlayer).sacks;
                              career.flagPulls += (info.$3 as FlagFootballPlayer).flagPulls;
                          });
                          rows.sort((a, b) => (int.parse(((a.cells[0].child as Center).child as Text).data.toString() ?? '0').compareTo(int.parse(((b.cells[0].child as Center).child as Text).data.toString() ?? '0'),)));
                          rows.add(DataRow(cells: [
                              const DataCell(Text("")),
                              const DataCell(Text("")),
                              const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                              DataCell(Center(child: Text(career.receptions.toString()),)),
                              DataCell(Center(child: Text(career.receivingTouchdowns.toString()),)),
                              DataCell(Center(child: Text(career.passBreakups.toString()),)),
                              DataCell(Center(child: Text(career.interceptions.toString()),)),
                              DataCell(Center(child: Text(career.passingTouchdowns.toString()),)),
                              DataCell(Center(child: Text(career.sacks.toString()),)),
                              DataCell(Center(child: Text(career.flagPulls.toString()),)),
                            ]));
                          return Column(children: [
                              Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                              Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                              DataTable(
                                columnSpacing: 16,
                                columns: const [
                                  DataColumn(label: Text("Season"), numeric: true),
                                  DataColumn(label: Text(""), numeric: true),
                                  DataColumn(label: Text("Team")),
                                  DataColumn(label: Text("REC"), numeric: true),
                                  DataColumn(label: Text("REC TD"), numeric: true),
                                  DataColumn(label: Text("PBU"), numeric: true),
                                  DataColumn(label: Text("INT"), numeric: true),
                                  DataColumn(label: Text("PASS TD"), numeric: true),
                                  DataColumn(label: Text("SACK"), numeric: true),
                                  DataColumn(label: Text("FP"), numeric: true),
                                ], 
                                rows: rows
                              ),
                          ],
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
                                DataCell(Center(child: Text((info.$3 as SoccerPlayer).goals.toString()))),
                                DataCell(Center(child: Text((info.$3 as SoccerPlayer).assists.toString()))),
                                DataCell(Center(child: Text((info.$3 as SoccerPlayer).saves.toString()))),
                              ]));
                              career.goals += (info.$3 as SoccerPlayer).goals;
                              career.assists += (info.$3 as SoccerPlayer).assists;
                              career.saves += (info.$3 as SoccerPlayer).saves;
                          });
                          rows.add(DataRow(cells: [
                              const DataCell(Text("Career", style: TextStyle(fontWeight: FontWeight.bold),)),
                              DataCell(Center(child: Text(career.goals.toString()))),
                              DataCell(Center(child: Text(career.assists.toString()))),
                              DataCell(Center(child: Text(career.saves.toString()))),
                            ]));
                          return Column(
                            children: [
                              Text(sports[index], style: TextStyle(fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineLarge!.fontSize), ),
                              Text(sportPositions[sports[index]] ?? "", style: TextStyle(fontSize: Theme.of(context).textTheme.bodySmall!.fontSize), ),
                              DataTable(
                                columnSpacing: 10,
                                columns: const [
                                  DataColumn(label: Text("Season")),
                                  DataColumn(label: Text("Goals"), numeric: true),
                                  DataColumn(label: Text("Assists"), numeric: true),
                                  DataColumn(label: Text("Saves"), numeric: true),
                                ], 
                                rows: rows
                              ),
                            ],
                          );
                        }
                      }
                      return const Text("");
                    }
                  ),
          )
              ]
            );
          }
          );
        }
      )
      
    );
  }
}
