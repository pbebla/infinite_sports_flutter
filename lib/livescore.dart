import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/model/basketballplayer.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/model/futsalplayer.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:infinite_sports_flutter/scorepage.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/model/game.dart';

typedef TitleCallback = void Function(String value);

class LiveScorePage extends StatefulWidget {
  const LiveScorePage({super.key, required this.onTitleSelect, required this.sport, required this.season, required this.date});
  final TitleCallback onTitleSelect;

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
  final String date;

  @override
  State<LiveScorePage> createState() => _LiveScorePageState();
}

class _LiveScorePageState extends State<LiveScorePage> {
  Map<String, Map<String, int>> times = {};
  var cardList = <GestureDetector>[];

  List<GestureDetector> populateCardList(List<Game> gamesList) {
    List<GestureDetector> cardList = [];
    if (gamesList.isEmpty) {
      cardList.add(GestureDetector(
        child: Card(child: Center(child: Text("No Upcoming Games, Stay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold),),)),
        onTap: () {
        },
      ));
    } 
    for (var game in gamesList) {
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
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child:Text(game.stringStatus,textAlign: TextAlign.left, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: game.statusColor))),
                    Expanded(child:Text('${game.Time.toString()}:00PM',textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        Image.network(width: 70, game.team1SourcePath, errorBuilder: (context, error, stackTrace) {
                          return Text("");
                        },),
                        Text(game.team1, textAlign: TextAlign.center),
                      ],
                    ),
                    Expanded(
                      child:
                        Text(
                          '${game.team1score}-${game.team2score}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 35,
                            fontWeight: FontWeight.bold,
                          ))),
                    Column(
                      children: <Widget>[
                        Image.network(width: 70, game.team2SourcePath, errorBuilder: (context, error, stackTrace) {
                          return Text("");
                        },),
                        Text(game.team2, textAlign: TextAlign.center),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    CircularPercentIndicator(
                          radius: 30,
                          lineWidth: 4.0,
                          percent: game.finalvote1,
                          center: Text(game.percvote1),
                          progressColor: infiniteSportsPrimaryColor,
                    ),
                    Expanded(
                      child: Visibility(
                      maintainSize: true, 
                      maintainAnimation: true,
                      maintainState: true,
                      visible: game.status == 0,
                      child: Column(
                        children: <Widget>[
                          Text('Poll', textAlign: TextAlign.center),
                          Container(
                            height: 40,
                            width: 80,
                            decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                            child: TextButton(
                              onPressed: () {
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
                          percent: game.finalvote2,
                          center: Text(game.percvote2),
                          progressColor: infiniteSportsPrimaryColor,
                    )
                  ],
                ),
              ],
            )
          ), //Padding
        ), //SizedBox
      );
      cardList.add(GestureDetector(
        child: card,
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => Overlay(
            initialEntries: [OverlayEntry(
              builder: (context) {
                return ScorePage(sport: widget.sport, season: widget.season, game: game, times: times);
              })],
          )));
        },
      ));
    }
    return cardList;
  }

  Future<void> _refreshData(setState) async { 
    // Add new items or update the data here 
    List<Game> gamesList = await getGames(widget.sport, widget.season, widget.date, times);
    cardList = populateCardList(gamesList); 
    setState(() {
    }); 
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
      future: getGames(widget.sport, widget.season, widget.date, times), 
      builder:(context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            )
          );
        }
        if (!snapshot.hasData) {
          return Center(child: Card(child: Text("No Upcoming Games, Stay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold),),),);
        }
        List<Game> gamesList = snapshot.data as List<Game>;
        //widget.onTitleSelect(gamesList[0].date);
        cardList = populateCardList(gamesList); 
        return StatefulBuilder(
          builder: (context, setState) {
            return RefreshIndicator(
              onRefresh: () async {
                return _refreshData(setState);
              },
              child: ListView(
                padding: const EdgeInsets.all(15),
                children: cardList,
              )
            );
          }
        );
      }
    );
  }
}
