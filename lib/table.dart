import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballteaminfo.dart';
import 'package:infinite_sports_flutter/model/futsalteaminfo.dart';
import 'package:infinite_sports_flutter/model/soccerteaminfo.dart';
import 'package:infinite_sports_flutter/model/teaminfo.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_launcher_icons/constants.dart';

class TablePage extends StatefulWidget {
  const TablePage({super.key, required this.sport, required this.season});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".
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
      Map<String, FutsalTeamInfo> gottenlineUp = <String, FutsalTeamInfo>{};
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
        gottenlineUp[key] = temp;
      });
      for (var team in gottenlineUp.keys) {
        lineUp[team] = gottenlineUp[team] as TeamInfo;
      }
    } else if (widget.sport == "AFC San Jose") {
      newClient =
        FirebaseDatabase.instance.ref("/${widget.sport}/Seasons/${widget.season}");
        Map<String, SoccerTeamInfo> gottenlineUp = <String, SoccerTeamInfo>{};
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
          gottenlineUp[key] = temp;
        });
        for (var team in gottenlineUp.keys) {
          lineUp[team] = gottenlineUp[team] as TeamInfo;
        }
    } else {
      var logos = sport![widget.season];
      Map<String, BasketballTeamInfo> gottenlineUp =
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
        gottenlineUp[key] = temp;
      });
      for (var team in gottenlineUp.keys) {
        lineUp[team] = gottenlineUp[team] as TeamInfo;
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
                    width: windowsDefaultIconSize.toDouble(),
                    fit: BoxFit.scaleDown,
                    alignment: FractionalOffset.center,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text("");
                    })),
                DataCell(Text(key.key.toString())),
                DataCell(Text((key.value as FutsalTeamInfo).gp.toString())),
                DataCell(Text(key.value.wins.toString())),
                DataCell(Text((key.value as FutsalTeamInfo).draws.toString())),
                DataCell(Text(key.value.losses.toString())),
                DataCell(Text.rich(TextSpan(
                    text: key.value.points.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold)))),
                DataCell(Text((key.value as FutsalTeamInfo).gd.toString())),
              ]))
          .toList();
      return DataTable(
        sortColumnIndex: 6,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
          return Theme.of(context)
              .colorScheme
              .inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("D"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("P"), numeric: true),
          DataColumn(label: Text("GD"), numeric: true),
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
                DataCell(Text.rich(TextSpan(
                    text: key.value.points.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold)))),
                DataCell(Text((key.value as SoccerTeamInfo).gd.toString())),
              ]))
          .toList();
      return DataTable(
        sortColumnIndex: 5,
        sortAscending: false,
        columnSpacing: 15,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
          return Theme.of(context)
              .colorScheme
              .inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("D"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("P"), numeric: true),
          DataColumn(label: Text("GD"), numeric: true),
        ],
        rows: teamsList,
      );
    } else {
      List<DataRow> teamsList = teams.entries
          .map((key) => DataRow(cells: [
                DataCell(Image.network(key.value.imagePath,
                    width: windowsDefaultIconSize.toDouble(),
                    fit: BoxFit.scaleDown,
                    alignment: FractionalOffset.center)),
                DataCell(Text(key.key.toString())),
                DataCell(Text((key.value as BasketballTeamInfo).gp.toString())),
                DataCell(Text(key.value.wins.toString())),
                DataCell(Text(key.value.losses.toString())),
                DataCell(Text.rich(TextSpan(
                    text: key.value.pct,
                    style: const TextStyle(fontWeight: FontWeight.bold)))),
                DataCell(Text(
                    (key.value as BasketballTeamInfo).pd.toStringAsFixed(1))),
              ]))
          .toList();
      return DataTable(
        sortColumnIndex: 5,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
          return Theme.of(context)
              .colorScheme
              .inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP"), numeric: true),
          DataColumn(label: Text("W"), numeric: true),
          DataColumn(label: Text("L"), numeric: true),
          DataColumn(label: Text("Pct"), numeric: true),
          DataColumn(label: Text("APD"), numeric: true),
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
    }
  }

/*
  var teamInfos = await FirebaseGetter.getSeasonTable(leagueFromDB, seasonFromDB);
  var teams = teamInfo.Keys;
  var information = new List<FutsalTeamInfo>(teamInfos.Values);

  int num = 0;

  if(teams.Count % 2 == 0){
      num = teams.Count - 2;
  }
  else if(teams.Count % 2 == 1 && teams.Count > 3){
      num = teams.Count - 3;
  }
  else{
      num = teams.Count - 1;
  }

  Message.Text = "Top " + num + " Teams will advance";

  futsalinfo.HeightRequest = 50 * information.Count;

  getFutsalLogos(information, teams);
*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("${widget.sport} ${widget.season} Table"),
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
