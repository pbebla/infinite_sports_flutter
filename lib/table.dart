import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballteaminfo.dart';
import 'package:infinite_sports_flutter/model/flagfootballteaminfo.dart';
import 'package:infinite_sports_flutter/model/futsalteaminfo.dart';
import 'package:infinite_sports_flutter/model/soccerteaminfo.dart';
import 'package:infinite_sports_flutter/model/teaminfo.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_launcher_icons/constants.dart';

class TablePage extends StatefulWidget {
  const TablePage({super.key, required this.sport, required this.season});

  final String sport;
  final String season;

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  Map<dynamic, dynamic> teams = {};
  static const int numItems = 6;
  List<bool> selected = List<bool>.generate(numItems, (int index) => false);
  Future<Map<String, TeamInfo>> getSeasonTable() async {
    DatabaseReference newClient =
        FirebaseDatabase.instance.ref("/${widget.sport}/${widget.season}");
    Map<String, TeamInfo> lineUp = <String, TeamInfo>{};
    var league = teamLogos;
    var sport = league[widget.sport];
    if (widget.sport == "Futsal") {
      var logos = sport![widget.season];
      Map<String, FutsalTeamInfo> gottenLineUp = <String, FutsalTeamInfo>{};
      final event = await newClient.child("Teams").get();
      Map eventData = event.value as Map;
      eventData.forEach((key, value) {
        var temp = FutsalTeamInfo();
        temp.imagePath = logos![key]!;
        temp.draws = value["Draws"];
        temp.gc = value["GC"];
        temp.gd = value["GD"];
        temp.gp = value["GP"];
        temp.gs = value["GS"];
        temp.wins = value["Wins"];
        temp.losses = value["Losses"];
        temp.points = value["Points"];
        gottenLineUp[key] = temp;
      });
      for (var team in gottenLineUp.keys) {
        lineUp[team] = gottenLineUp[team] as TeamInfo;
      }
    } else if (widget.sport == "AFC San Jose") {
      newClient =
          FirebaseDatabase.instance.ref("/${widget.sport}/Seasons/${widget.season}");
      Map<String, SoccerTeamInfo> gottenLineUp = <String, SoccerTeamInfo>{};
      final event = await newClient.child("Table").get();
      Map eventData = event.value as Map;
      eventData.forEach((key, value) {
        var temp = SoccerTeamInfo();
        temp.draws = value["Draws"];
        temp.gc = value["GA"];
        temp.gs = value["GF"];
        temp.wins = value["Wins"];
        temp.losses = value["Losses"];
        temp.gp = temp.wins + temp.losses + temp.draws;
        temp.gd = temp.gs - temp.gc;
        temp.points = (temp.wins * 3) + temp.draws;
        gottenLineUp[key] = temp;
      });
      for (var team in gottenLineUp.keys) {
        lineUp[team] = gottenLineUp[team] as TeamInfo;
      }
    } else if (widget.sport == "Flag Football") {
      var logos = sport![widget.season];
      Map<String, FlagFootballTeamInfo> gottenLineUp = <String, FlagFootballTeamInfo>{};
      final event = await newClient.child("Teams").get();
      Map eventData = event.value as Map;
      eventData.forEach((key, value) {
        var temp = FlagFootballTeamInfo();
        temp.wins = value["Wins"];
        temp.losses = value["Losses"];
        temp.pointsFor = value["PF"];
        temp.pointsAgainst = value["PA"];
        temp.imagePath = logos![key]!;
        gottenLineUp[key] = temp;
      });
      for (var team in gottenLineUp.keys) {
        lineUp[team] = gottenLineUp[team] as TeamInfo;
      }
    } else {
      var logos = sport![widget.season];
      Map<String, BasketballTeamInfo> gottenLineUp =
      <String, BasketballTeamInfo>{};
      final event = await newClient.child("Teams").get();
      Map eventData = event.value as Map;
      eventData.forEach((key, value) {
        var temp = BasketballTeamInfo();
        temp.imagePath = logos![key]!;
        temp.ppg = value["PPG"].toDouble();
        temp.pcpg = value["PCPG"].toDouble();
        temp.pd = value["PD"].toDouble();
        temp.gp = value["GP"];
        temp.wins = value["Wins"];
        temp.losses = value["Losses"];
        temp.pct = (temp.gp > 0 ? (temp.wins / temp.gp) : 0).toStringAsFixed(3);
        gottenLineUp[key] = temp;
      });
      for (var team in gottenLineUp.keys) {
        lineUp[team] = gottenLineUp[team] as TeamInfo;
      }
    }
    return lineUp;
  }

  DataTable buildTable() {
    sortTable();
    if (widget.sport == "Futsal") {
      List<DataRow> teamsList = teams.entries
          .map((key) => DataRow(cells: [
        DataCell(Image.network(key.value.imagePath,
            width: windowsDefaultIconSize.toDouble()/1.25,
            height: windowsDefaultIconSize.toDouble()/1.25,
            alignment: FractionalOffset.center,
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(width: 0, height: 0);
            })),
        DataCell(Text(key.key.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).gp.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).draws.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).gs.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).gc.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).gd.toString())),
        DataCell(Text.rich(TextSpan(
            text: key.value.points.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)))),
      ]))
          .toList();
      return DataTable(
        sortColumnIndex: 6,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
              return Theme.of(context)
                  .colorScheme.surfaceContainerHighest; // Use the default value.
            }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("D"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("GF"), numeric: true),
          DataColumn(label: Text("GA"), numeric: true),
          DataColumn(label: Text("GD"), numeric: true),
          DataColumn(label: Text("P"), numeric: true),
        ],
        rows: teamsList,
      );
    } else if (widget.sport == "AFC San Jose") {
      List<DataRow> teamsList = teams.entries
          .map((key) => DataRow(cells: [
        DataCell(Text(key.key.toString(), style: const TextStyle(fontWeight: FontWeight.bold),)),
        DataCell(Text((key.value as SoccerTeamInfo).gp.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text((key.value as SoccerTeamInfo).draws.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text((key.value as SoccerTeamInfo).gs.toString())),
        DataCell(Text((key.value as SoccerTeamInfo).gc.toString())),
        DataCell(Text((key.value as SoccerTeamInfo).gd.toString())),
        DataCell(Text.rich(TextSpan(
            text: key.value.points.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold)))),
      ]))
          .toList();
      return DataTable(
        sortColumnIndex: 5,
        sortAscending: false,
        columnSpacing: 15,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
              return Theme.of(context)
                  .colorScheme.surfaceContainerHighest; // Use the default value.
            }),
        columns: const [
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("D"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("GF"), numeric: true),
          DataColumn(label: Text("GA"), numeric: true),
          DataColumn(label: Text("GD"), numeric: true),
          DataColumn(label: Text("P"), numeric: true),
        ],
        rows: teamsList,
      );
    } else if (widget.sport == "Flag Football") {
      List<DataRow> teamsList = teams.entries
          .map((key) => DataRow(cells: [
        DataCell(Image.network(key.value.imagePath,
            width: windowsDefaultIconSize.toDouble()/1.25,
            height: windowsDefaultIconSize.toDouble()/1.25,
            alignment: FractionalOffset.center, errorBuilder:(context, error, stackTrace) => const Text(""))),
        DataCell(Text(key.key.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text((key.value as FlagFootballTeamInfo).pointsFor.toString())),
        DataCell(Text((key.value as FlagFootballTeamInfo).pointsAgainst.toString())),
        DataCell(Text((key.value as FlagFootballTeamInfo).pointDifferential.toString())),
      ]))
          .toList();
      return DataTable(
        sortColumnIndex: 2,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
              return Theme.of(context)
                  .colorScheme.surfaceContainerHighest; // Use the default value.
            }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("PF"), numeric: true),
          DataColumn(label: Text("PA"), numeric: true),
          DataColumn(label: Text("PD"), numeric: true)
        ],
        rows: teamsList,
      );
    } else {
      List<DataRow> teamsList = teams.entries
          .map((key) => DataRow(cells: [
        DataCell(Image.network(key.value.imagePath,
            width: windowsDefaultIconSize.toDouble()/1.25,
            height: windowsDefaultIconSize.toDouble()/1.25,
            alignment: FractionalOffset.center, errorBuilder:(context, error, stackTrace) => const Text(""))),
        DataCell(Text(key.key.toString())),
        DataCell(Text((key.value as BasketballTeamInfo).gp.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text(key.value.ppg.toString())),
        DataCell(Text(key.value.pcpg.toString())),
        DataCell(Text(
            (key.value as BasketballTeamInfo).pd.toStringAsFixed(1))),
        DataCell(Text.rich(TextSpan(
            text: key.value.pct,
            style: const TextStyle(fontWeight: FontWeight.bold)))),
      ]))
          .toList();
      return DataTable(
        sortColumnIndex: 5,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
              return Theme.of(context)
                  .colorScheme.surfaceContainerHighest; // Use the default value.
            }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("PPG"), numeric: true),
          DataColumn(label: Text("OPPG"), numeric: true),
          DataColumn(label: Text("APD"), numeric: true),
          DataColumn(label: Text("Pct"), numeric: true),
        ],
        rows: teamsList,
      );
    }
  }

  void sortTable() {
    if (widget.sport == "Futsal") {
      teams = Map.fromEntries(teams.entries.toList()
        ..sort(
              (a, b) {
            int value = (b.value as FutsalTeamInfo)
                .points
                .compareTo((a.value as FutsalTeamInfo).points);
            if (value == 0) {
              value = (b.value as FutsalTeamInfo)
                  .gd
                  .compareTo((a.value as FutsalTeamInfo).gd);
            }
            return value;
          },
        ));
    }
    else if (widget.sport == "AFC San Jose") {
      teams = Map.fromEntries(teams.entries.toList()
        ..sort(
              (a, b) {
            int value = (b.value as SoccerTeamInfo)
                .points
                .compareTo((a.value as SoccerTeamInfo).points);
            if (value == 0) {
              value = (b.value as SoccerTeamInfo)
                  .gd
                  .compareTo((a.value as SoccerTeamInfo).gd);
            }
            return value;
          },
        ));
    }
    else if (widget.sport == "Basketball") {
      teams = Map.fromEntries(teams.entries.toList()
        ..sort(
              (a, b) {
            int value = double.parse((b.value as BasketballTeamInfo).pct)
                .compareTo(double.parse((a.value as BasketballTeamInfo).pct));
            if (value == 0) {
              value = (b.value as BasketballTeamInfo)
                  .pd
                  .compareTo((a.value as BasketballTeamInfo).pd);
            }
            return value;
          },
        ));
    } else if (widget.sport == "Flag Football") {
      teams = Map.fromEntries(teams.entries.toList()
        ..sort(
              (a, b) {
            int value = b.value.wins.compareTo(a.value.wins);
            if (value == 0) {
              value = (b.value as FlagFootballTeamInfo).pointDifferential.compareTo((a.value as FlagFootballTeamInfo).pointDifferential);
            }
            if (value == 0) {
              value = (b.value as FlagFootballTeamInfo).pointsFor.compareTo((a.value as FlagFootballTeamInfo).pointsFor);
            }
            if (value == 0) {
              value = (a.value as FlagFootballTeamInfo).pointsAgainst.compareTo((b.value as FlagFootballTeamInfo).pointsAgainst);
            }
            return value;
          },
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
                text: widget.sport,
                style: TextStyle(fontSize: Theme.of(context).textTheme.headlineSmall!.fontSize),
                children: <TextSpan>[
                  TextSpan(
                    text: '\n${widget.season} Table',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                    ),
                  ),
                ]
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: FutureBuilder(
            future: getSeasonTable(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ));
              }
              teams = snapshot.data as Map<String, TeamInfo>;
              return SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: buildTable());
            }));
  }
}
