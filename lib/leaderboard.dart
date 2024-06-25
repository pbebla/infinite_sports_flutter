import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/botnavbar.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/leaguemenu.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/showleague.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key, required this.sport, required this.season});

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

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  Future<List<Player>> getPlayersList() async {
    if (widget.sport == "Futsal") {
      await getAllFutsalLineUps(widget.season);
      var players = <FutsalPlayer>[];
      var lineups = futsalLineups[widget.season];
      for (var team in lineups!.keys) {
        for (var player in lineups[team]!.keys) {
          lineups[team]![player]!.name = player;
          lineups[team]![player]!.teamPath = teamLogos["Futsal"][widget.season][team];
          players.add(lineups[team]![player]!);
        }
      }
      return players;
    } else {
      await getAllBasketballLineUps(widget.season);
      var players = <BasketballPlayer>[];
      var lineups = basketballLineups[widget.season];
      for (String team in lineups!.keys) {
        for (String player in lineups[team]!.keys) {
          lineups![team]![player]!.name = player;
          lineups[team]![player]!.teamPath = teamLogos["Basketball"][widget.season][team];
          players.add(lineups[team]![player]!);
        }
      }
      return players;
    }
  }

  sortTable(List<DataRow> playersList) {
    if (widget.sport == "Futsal") {
      playersList.sort((a, b) {
        int intA = int.parse((a.cells[2].child as Text).textSpan!.toPlainText());
        int intB = int.parse((b.cells[2].child as Text).textSpan!.toPlainText());
        int result = intB.compareTo(intA);
        if (result == 0) {
          intA = int.parse((a.cells[3].child as Text).textSpan!.toPlainText());
          intB = int.parse((b.cells[3].child as Text).textSpan!.toPlainText());
          return intB.compareTo(intA);
        } else {
          return result;
        }
        } 
      );
    } else {
      playersList.sort((a, b) {
        int intA = int.parse((a.cells[2].child as Text).data!);
        int intB = int.parse((b.cells[2].child as Text).data!);
        int result = intB.compareTo(intA);
        if (result == 0) {
          double doubleA = double.parse((a.cells[4].child as Text).data!.toString());
          double doubleB = double.parse((b.cells[4].child as Text).data!.toString());
          return doubleB.compareTo(doubleA);
        } else {
          return result;
        }
        } 
      );
    }
  }

  DataTable buildLeaderboard(List<Player> data) {
    if (widget.sport == "Futsal") {
      List<DataRow> teamsList = data.map((key) => DataRow(cells: [
        DataCell(Image.network((key as FutsalPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)),
        DataCell(Text(key.name.toString())),
        DataCell(Text(key.goals.toString())),
        DataCell(Text(key.assists.toString())),
        DataCell(Text(key.saves.toString())),
      ])).toList();
      sortTable(teamsList);
      return DataTable(
        sortColumnIndex: 2,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Name")),
          DataColumn(label: Text("Goals (G)")),
          DataColumn(label: Text("Assists (A)")),
          DataColumn(label: Text("Saves (S)")),
        ], 
        rows: teamsList,
      );
    } else if (widget.sport == "Basketball") {
      List<DataRow> teamsList = data.map((key) => DataRow(cells: [
        DataCell(Image.network((key as BasketballPlayer).teamPath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)),
        DataCell(Text(key.name.toString())),
        DataCell(Text(key.total.toString())),
        DataCell(Text(key.rebounds.toString())),
        DataCell(Text(key.shotPercentage)),
      ])).toList();
      sortTable(teamsList);
      return DataTable(
        sortColumnIndex: 2,
        sortAscending: false,
        columnSpacing: 0,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: const [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Name")),
          DataColumn(label: Text("Points (P)")),
          DataColumn(label: Text("Rebounds (R)")),
          DataColumn(label: Text("Field Goal Percentage (FG%)")),
        ], 
        rows: teamsList,
      );
    } 
    return DataTable(columns: [], rows: []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.sport} ${widget.season} Leaderboard"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: getPlayersList(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Text("Loading");
          }
          List<Player> data = snapshot.data!;
          return InteractiveViewer(
            constrained: false,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: buildLeaderboard(data)
            )
          );
        }
      )
    );
  }
}