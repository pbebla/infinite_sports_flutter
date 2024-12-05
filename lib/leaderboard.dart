import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/model/player.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:data_table_2/data_table_2.dart';

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
    } else if (widget.sport == "AFC San Jose") {
      var roster = await getSoccerRoster(widget.sport, widget.season);
      var players = roster.values.toList();
      return players;
    } else {
      await getAllBasketballLineUps(widget.season);
      var players = <BasketballPlayer>[];
      var lineups = basketballLineups[widget.season];
      for (String team in lineups!.keys) {
        for (String player in lineups[team]!.keys) {
          lineups[team]![player]!.name = player;
          lineups[team]![player]!.teamPath = teamLogos["Basketball"][widget.season][team];
          players.add(lineups[team]![player]!);
        }
      }
      return players;
    }
  }

  void sortTable(int columnIndex, bool ascending) {
    if (columnIndex == 2) {
      players.sort((a, b) => 
        compareValues(a.name, b.name, isAscending));
    } else if (columnIndex == 3) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        players.sort((a, b) => a.goals == b.goals ? compareValues(a.assists, b.assists, isAscending) : compareValues(a.goals, b.goals, isAscending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => a.total == b.total ? compareValues(a.rebounds, b.rebounds, isAscending) : compareValues((a as BasketballPlayer).total, (b as BasketballPlayer).total, isAscending));
      }
    } else if (columnIndex == 4) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        players.sort((a, b) => a.assists == b.assists ? compareValues(a.goals, b.goals, isAscending) : compareValues(a.assists, b.assists, isAscending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => a.rebounds == b.rebounds ? compareValues(a.total, b.total, isAscending) : compareValues((a as BasketballPlayer).rebounds, (b as BasketballPlayer).rebounds, isAscending));
      }
    } else if (columnIndex == 5) {
      if (widget.sport == "Futsal" || widget.sport == "AFC San Jose") {
        players.sort((a, b) => a.saves == b.saves ? compareValues(a.assists, b.assists, isAscending) : compareValues(a.saves, b.saves, isAscending));
      } else if (widget.sport == "Basketball") {
        players.sort((a, b) => int.parse(((a as BasketballPlayer).shotPercentage).replaceFirst('%', '')) == int.parse(((b as BasketballPlayer).shotPercentage).replaceFirst('%', '')) ? compareValues(a.total, b.total, isAscending) : compareValues(int.parse(((a).shotPercentage).replaceFirst('%', '')), int.parse(((b).shotPercentage).replaceFirst('%', '')), isAscending));
      }
    }
  }

  void onSort(int columnIndex, bool ascending, setState) {
    setState(() {
      sortColumnIndex = columnIndex;
      isAscending = ascending;
    });
    sortTable(columnIndex, ascending);
  }

  DataTable2 buildLeaderboard(setState) {
    if (widget.sport == "Futsal") {
      List<DataRow2> teamsList = players.map((key) => DataRow2(cells: [
        DataCell(Center(child: Text(key.number),)),
        DataCell(Padding(padding: EdgeInsets.fromLTRB(5.0, 0, 5.0, 0), child: Image.network(key.teamPath, width: windowsDefaultIconSize.toDouble()/2, height: windowsDefaultIconSize.toDouble()/2, alignment: FractionalOffset.center),)),
        DataCell(Text(key.name.toString(), softWrap: true,), onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (context) {
                      return PlayerPage(uid: key.uid);
                    })],
                )));
        },),
        DataCell(Text(key.goals.toString())),
        DataCell(Text(key.assists.toString())),
        DataCell(Text(key.saves.toString())),
      ])).toList();
      return DataTable2(
        sortColumnIndex: sortColumnIndex,
        sortAscending: isAscending,
        columnSpacing: 0,
        fixedTopRows: 1,
        bottomMargin: 10,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return Theme.of(context).colorScheme.surfaceContainerHighest; // Use the default value.
        }),
        columns: [
          const DataColumn2(fixedWidth: 30.0, label: Text(""), numeric: true),
          DataColumn2(fixedWidth: windowsDefaultIconSize.toDouble()/1.5, label: Text("")),
          DataColumn2(label: const Text("Name"), onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("G"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("A"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("S"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
        ], 
        rows: teamsList,
      );
    } else if (widget.sport == "Basketball") {
      List<DataRow2> teamsList = players.map((key) => DataRow2(cells: [
        DataCell(Center(child: Text(key.number),)),
        DataCell(Padding(padding: EdgeInsets.fromLTRB(5.0, 0, 5.0, 0), child: Image.network(key.teamPath, width: windowsDefaultIconSize.toDouble()/2, height: windowsDefaultIconSize.toDouble()/2, alignment: FractionalOffset.center),)),
        //DataCell(Row(children: [Text(key.number), Spacer(), ])),
        DataCell(Text(key.name.toString(), softWrap: true,), onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (context) {
                      return PlayerPage(uid: key.uid);
                    })],
                )));
        },),
        DataCell(Text(key.total.toString())),
        DataCell(Text(key.rebounds.toString())),
        DataCell(Text(key.shotPercentage)),
      ])).toList();
      return DataTable2(
        sortColumnIndex: sortColumnIndex,
        sortAscending: isAscending,
        columnSpacing: 0,
        fixedTopRows: 1,
        bottomMargin: 10,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return Theme.of(context).colorScheme.surfaceContainerHighest; // Use the default value.
        }),
        columns: [
          const DataColumn2(fixedWidth: 30.0, label: Text(""), numeric: true),
          DataColumn2(fixedWidth: windowsDefaultIconSize.toDouble()/1.5, label: Text("")),
          DataColumn2(label: const Text("Name"), onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("PTS"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("REB"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("FG%"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
        ], 
        rows: teamsList,
      );
    } else if (widget.sport == "AFC San Jose") {
      List<DataRow2> teamsList = players.map((key) => DataRow2(cells: [
        DataCell(Text(key.position)),
        DataCell(Center(child: Text(key.number),)),
        DataCell(Text(key.name.toString(), softWrap: true,), onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
                  initialEntries: [OverlayEntry(
                    builder: (context) {
                      return PlayerPage(uid: key.uid);
                    })],
                )));
        },),
        DataCell(Text(key.goals.toString())),
        DataCell(Text(key.assists.toString())),
        DataCell(Text(key.saves.toString())),
      ])).toList();
      return DataTable2(
        sortColumnIndex: sortColumnIndex,
        sortAscending: isAscending,
        columnSpacing: 0,
        fixedTopRows: 1,
        bottomMargin: 10,
        headingRowColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          return Theme.of(context).colorScheme.surfaceContainerHighest; // Use the default value.
        }),
        columns: [
          const DataColumn2(fixedWidth: 30.0, label: Text("Pos")),
          const DataColumn2(fixedWidth: 30.0, label: Text("#")),
          DataColumn2(label: const Text("Name"), onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("G"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("A"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
          DataColumn2(fixedWidth: 50.0, label: const Text("S"), numeric: true, onSort: (colIndex, asc) {onSort(colIndex, asc, setState);}),
        ], 
        rows: teamsList,
      );
    }
    return DataTable2(columns: const [DataColumn(label: Text("Error"))], rows: const []);
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
                  text: '\n${widget.season} Leaderboard',
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
        future: getPlayersList(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
          }
          if (players.isEmpty) {
            players = snapshot.data!;
            sortTable(3, isAscending);
          }
          return StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: buildLeaderboard(setState),
              );
            }
          );
        }
      )
    );
  }
}