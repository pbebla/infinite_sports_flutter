import 'package:firebase_database/firebase_database.dart';
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
  List<dynamic> players = List.empty();
  int? sortColumnIndex;
  bool isAscending = false;

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

  void sortTable(int columnIndex, bool ascending) {
    if (columnIndex == 1) {
      players.sort((a, b) => 
        compareValues(a.name, b.name));
    } else if (columnIndex == 2) {
      if (widget.sport == "Futsal") {
        players.sort((a, b) => compareValues((a as FutsalPlayer).goals, (b as FutsalPlayer).goals));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayer).total, (b as BasketballPlayer).total));
      }
    } else if (columnIndex == 3) {
      if (widget.sport == "Futsal") {
        players.sort((a, b) => compareValues((a as FutsalPlayer).assists, (b as FutsalPlayer).assists));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues((a as BasketballPlayer).rebounds, (b as BasketballPlayer).rebounds));
      }
    } else if (columnIndex == 4) {
      if (widget.sport == "Futsal") {
        players.sort((a, b) => compareValues((a as FutsalPlayer).saves, (b as FutsalPlayer).saves));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => compareValues(int.parse(((a as BasketballPlayer).shotPercentage).replaceFirst('%', '')), int.parse(((b as BasketballPlayer).shotPercentage).replaceFirst('%', ''))));
      }
    }
  }

  void onSort(int columnIndex, bool ascending) {
    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
    sortTable(columnIndex, ascending);
  }

  DataTable buildLeaderboard() {
    if (widget.sport == "Futsal") {
      List<DataRow> teamsList = players.map((key) => DataRow(cells: [
        DataCell(Row(children: [Text(key.number), Spacer(), Image.network(key.teamPath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)])),
        DataCell(Text(key.name.toString())),
        DataCell(Text(key.goals.toString())),
        DataCell(Text(key.assists.toString())),
        DataCell(Text(key.saves.toString())),
      ])).toList();
      return DataTable(
        horizontalMargin: 10,
        sortColumnIndex: sortColumnIndex,
        sortAscending: isAscending,
        columnSpacing: 0,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Name"), onSort: onSort),
          DataColumn(label: Text("Goals"), numeric: true, onSort: onSort),
          DataColumn(label: Text("Assists"), numeric: true, onSort: onSort),
          DataColumn(label: Text("Saves"), numeric: true, onSort: onSort),
        ], 
        rows: teamsList,
      );
    } else if (widget.sport == "Basketball") {
      List<DataRow> teamsList = players.map((key) => DataRow(cells: [
        DataCell(Row(children: [Text(key.number), Spacer(), Image.network(key.teamPath, width: windowsDefaultIconSize.toDouble(), fit: BoxFit.scaleDown, alignment: FractionalOffset.center)])),
        DataCell(Text(key.name.toString())),
        DataCell(Text(key.total.toString())),
        DataCell(Text(key.rebounds.toString())),
        DataCell(Text(key.shotPercentage)),
      ])).toList();
      return DataTable(
        horizontalMargin: 10,
        sortColumnIndex: sortColumnIndex,
        sortAscending: isAscending,
        columnSpacing: 16,
        headingRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) {
          return Theme.of(context).colorScheme.inversePrimary; // Use the default value.
        }),
        columns: [
          DataColumn(label: Text("")),
          DataColumn(label: Text("Name"), onSort: onSort),
          DataColumn(label: Text("PTS"), numeric: true, onSort: onSort),
          DataColumn(label: Text("REB"), numeric: true, onSort: onSort),
          DataColumn(label: Text("FG%"), numeric: true, onSort: onSort),
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
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
          }
          if (players.isEmpty) {
            players = snapshot.data!;
            sortTable(2, isAscending);
          }
          return SingleChildScrollView(child: buildLeaderboard(), scrollDirection: Axis.vertical);
        }
      )
    );
  }
  
  int compareValues(dynamic value1, dynamic value2) =>
      isAscending ? value1.compareTo(value2) : value2.compareTo(value1);
}