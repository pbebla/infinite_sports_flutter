import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballteaminfo.dart';
import 'package:infinite_sports_flutter/model/futsalteaminfo.dart';
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
  static const int numItems = 6;
  List<bool> selected = List<bool>.generate(numItems, (int index) => false);
  Future<Map<String, TeamInfo>> getSeasonTable() async {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/${widget.sport}/${widget.season}");
    Map<String, TeamInfo> lineUp = <String, TeamInfo>{};
    var league = teamLogos;
    var sport = league[widget.sport];
    if (widget.sport == "Futsal")
    {
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
      for (var team in gottenlineUp.keys)
      {
        lineUp[team] = gottenlineUp[team] as TeamInfo;
      }
    }
    else
    {
      var logos = sport![widget.season];
      Map<String, BasketballTeamInfo> gottenlineUp = <String, BasketballTeamInfo>{};
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
        temp.points = value["Points"];
        gottenlineUp[key] = temp;
      });
      for (var team in gottenlineUp.keys)
      {
        lineUp[team] = gottenlineUp[team] as TeamInfo;
      }
    }
    return lineUp;
  }

  sortTable(List<DataRow> teamsList) {
    if (widget.sport == "Futsal") {
      teamsList.sort((a, b) {
        int intA = int.parse((a.cells[6].child as Text).textSpan!.toPlainText());
        int intB = int.parse((b.cells[6].child as Text).textSpan!.toPlainText());
        int result = intB.compareTo(intA);
        if (result == 0) {
          intA = int.parse((a.cells[7].child as Text).textSpan!.toPlainText());
          intB = int.parse((b.cells[7].child as Text).textSpan!.toPlainText());
          return intB.compareTo(intA);
        } else {
          return result;
        }
        } 
      );
    } else {
      teamsList.sort((a, b) {
        int intA = int.parse((a.cells[5].child as Text).textSpan!.toPlainText());
        int intB = int.parse((b.cells[5].child as Text).textSpan!.toPlainText());
        int result = intB.compareTo(intA);
        if (result == 0) {
          double doubleA = double.parse((a.cells[6].child as Text).data!.toString());
          double doubleB = double.parse((b.cells[6].child as Text).data!.toString());
          return doubleB.compareTo(doubleA);
        } else {
          return result;
        }
        } 
      );
    }
  }

  DataTable buildTable(Map<String, TeamInfo> data) {
    if (widget.sport == "Futsal") {
      List<DataRow> teamsList = data.entries.map((key) => DataRow(cells: [
        DataCell(Image.network(key.value.imagePath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)),
        DataCell(Text(key.key.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).gp.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text((key.value as FutsalTeamInfo).draws.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text.rich(TextSpan(text: key.value.points.toString(), style: TextStyle(fontWeight: FontWeight.bold)))),
        DataCell(Text((key.value as FutsalTeamInfo).gd.toString())),
      ])).toList();
      sortTable(teamsList);
      return DataTable(
        columnSpacing: 0,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP")),
          DataColumn(label: Text("W")),
          DataColumn(label: Text("D")),
          DataColumn(label: Text("L")),
          DataColumn(label: Text("P")),
          DataColumn(label: Text("GD")),
        ], 
        rows: teamsList,
      );
    } else {
      List<DataRow> teamsList = data.entries.map((key) => DataRow(cells: [
        DataCell(Image.network(key.value.imagePath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)),
        DataCell(Text(key.key.toString())),
        DataCell(Text((key.value as BasketballTeamInfo).gp.toString())),
        DataCell(Text(key.value.wins.toString())),
        DataCell(Text(key.value.losses.toString())),
        DataCell(Text.rich(TextSpan(text: key.value.points.toString(), style: TextStyle(fontWeight: FontWeight.bold)))),
        DataCell(Text((key.value as BasketballTeamInfo).pd.toStringAsFixed(1))),
      ])).toList();
      sortTable(teamsList);
      return DataTable(
        columnSpacing: 0,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Team")),
          DataColumn(label: Text("GP")),
          DataColumn(label: Text("W")),
          DataColumn(label: Text("L")),
          DataColumn(label: Text("P")),
          DataColumn(label: Text("APD")),
        ], 
        rows: teamsList,
      );
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
        title: Text("Table"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: getSeasonTable(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Text("Loading");
          }
          Map<String, TeamInfo> data = snapshot.data as Map<String, TeamInfo>;
          return SizedBox(
            width: MediaQuery.of(context).size.width,
            child: buildTable(data));
        }
      )
    );
  }
}