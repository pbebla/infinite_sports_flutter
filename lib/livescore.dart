
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/model/soccergame.dart';
import 'package:infinite_sports_flutter/scorepage.dart';
import 'package:infinite_sports_flutter/misc/schedule_display.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
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
  List<Game>? gamesList;
  late Future<List<Game>> _fetchGamesList;
  final _controller = ScrollController(keepScrollOffset: true);

  @override
  void initState() {
    _fetchGamesList = getGames(widget.sport, widget.season, widget.date, times);
    super.initState();
  }

  List<GestureDetector> populateCardList(List<Game> gamesList, localSetState) {
    List<GestureDetector> cardList = [];
    if (gamesList.isEmpty) {
      cardList.add(GestureDetector(
        child: const Card(child: Center(child: Text("No Upcoming Games, Stay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold),),)),
        onTap: () {
        },
      ));
    } 
    for (var game in gamesList) {
      List<Widget> informationRows = [
        Row(
          children: <Widget>[
            Expanded(child:Text(game.stringStatus,textAlign: TextAlign.left, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: game.statusColor))),
            Expanded(child:Text(game is SoccerGame && game.startTime != "" ? game.startTime : gameTimeText(game.storedTime, game.Time),textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
          ],
        ),
        if (game.stage.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  stageDisplayName(game.stage),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        Row(
          children: <Widget>[
            SizedBox(
              width: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  isPlaceholderTeam(game.team1) ? const Icon(Icons.emoji_events, size: 50) : TeamLogo(url: game.team1SourcePath.isNotEmpty ? game.team1SourcePath : null, size: 70),
                  Center(child: Text(game.team1, textAlign: TextAlign.center,),),
                ],
              ),
            ),
            Expanded(child: Text(game.team1score, textAlign: TextAlign.center, style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold))),
            
           SizedBox(
            width: 25,
            child: Center(child: Text("-", style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold))),
           ),
           Expanded(child: Text(game.team2score, textAlign: TextAlign.center, style: TextStyle(fontSize: 35, fontWeight: FontWeight.bold))),
            
            SizedBox(
              width: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  isPlaceholderTeam(game.team2) ? const Icon(Icons.emoji_events, size: 50) : TeamLogo(url: game.team2SourcePath.isNotEmpty ? game.team2SourcePath : null, size: 70),
                  Center(child: Text(game.team2, textAlign: TextAlign.center),),
                ],
              ),
            )
          ],
        ),
      ];
      if (game is SoccerGame && widget.sport == "AFC San Jose") {
        informationRows.add(
          Row(
            children: [
              SizedBox(width: 150, child: Text(game.location, textAlign: TextAlign.left,),),
              Expanded(child: SizedBox(width: 150, child: Text(game.type, textAlign: TextAlign.right,),),)
            ],
          )
        );
      } else {
        informationRows.add(
          Row(
            children: <Widget>[
              CircularPercentIndicator(
                    radius: 30,
                    lineWidth: 4.0,
                    percent: game.finalvote1,
                    center: Text(game.percvote1),
                    progressColor: Theme.of(context).colorScheme.primary,
              ),
              Expanded(
                child: Visibility(
                maintainSize: true, 
                maintainAnimation: true,
                maintainState: true,
                visible: signedIn && !game.voted && game.status == 0,
                child: Column(
                  children: <Widget>[
                    const Text('Poll', textAlign: TextAlign.center),
                    Container(
                      height: 40,
                      width: 80,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                      child: TextButton(
                        onPressed: () {
                          showCupertinoDialog<String>(
                            context: context,
                            builder: (BuildContext context) => Dialog(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    TextButton(onPressed: () async {
                                      DatabaseReference newClient = game.databaseReference.child(game.GameNum.toString()).child("team1vote");
                                      await newClient.child(FirebaseAuth.instance.currentUser!.uid).set(1);
                                      Navigator.pop(context);
                                      await _refreshData(setState);
                                    }, child: Text(game.team1),),
                                    TextButton(onPressed: () async {
                                      DatabaseReference newClient = game.databaseReference.child(game.GameNum.toString()).child("team2vote");
                                      await newClient.child(FirebaseAuth.instance.currentUser!.uid).set(1);
                                      Navigator.pop(context);
                                      await _refreshData(setState);
                                    }, child: Text(game.team2),),
                                    const SizedBox(width: 15, height: 15,),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              ),
                            ),);
                        },
                        child: Text(
                          'Vote',
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 18),
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
                    progressColor: Theme.of(context).colorScheme.primary,
              )
            ],
          )
        );
      }

      Card card = Card(
        elevation: 2,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - 38,
          height: game.stage.isNotEmpty ? 270 : 240,
          child: Container(
            padding: const EdgeInsets.all(13),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: informationRows
            ),
          ), //Padding
        ), //SizedBox
      );
      cardList.add(GestureDetector(
        child: card,
        onTap: () {
          // League Experience P2/P4: futsal, basketball and flag football
          // league games open the live league match page (game identity =
          // this date + list index, which getGames stores as GameNum). AFC
          // San Jose keeps the legacy ScorePage.
          if (isLeagueEngineSport(widget.sport)) {
            Navigator.push(mainContext!, MaterialPageRoute(builder: (_) =>
              LeagueMatchDetailPage(
                sport: widget.sport,
                season: widget.season,
                dateKey: widget.date,
                gameIndex: game.GameNum,
              ),
            ));
            return;
          }
          Navigator.push(mainContext!, MaterialPageRoute(builder: (_) => Overlay(
            initialEntries: [OverlayEntry(
              builder: (context) {
                return ScorePage(sport: widget.sport, season: widget.season, game: game, times: times, refreshCallback: () async {
                  await _refreshData(localSetState);
                },);
              })],
          )));
        },
      ));
    }
    return cardList;
  }

  Future<void> _refreshData(localsetState) async { 
    // Add new items or update the data here 
    _fetchGamesList = getGames(widget.sport, widget.season, widget.date, times);
    gamesList = await _fetchGamesList;
    if (mounted) {
      localsetState(() {}); 
    }
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
      future: _fetchGamesList, 
      builder:(context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // P2.1: skeleton rows instead of the red spinner while games load.
          return const SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(top: 8),
              child: SkeletonMatchList(count: 6),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: Card(child: Text("No Upcoming Games, Stay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold),),),);
        }
        gamesList = snapshot.data!;
        return StatefulBuilder(
          builder: (context, setState) {
            return RefreshIndicator(
              onRefresh: () async {
                return _refreshData(setState);
              },
              child: ListView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(15),
                children: populateCardList(gamesList!, setState),
              )
            );
          }
        );
      }
    );
  }
}
