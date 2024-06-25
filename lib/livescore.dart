import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/model/futsalgame.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/leagues.dart';
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
  var cardList = <Card>[];

  Future<Map<String, List<FutsalGame>>> getAllFutsalGames() async {
    try
    {
      DatabaseReference newClient = FirebaseDatabase.instance.ref("/${widget.sport}/${widget.season}");
      var games = await newClient.child("Date").get();
      dynamic data = games.value;
      var result = <String, List<FutsalGame>>{};
      data.forEach((key, value) {
        var list = <FutsalGame>[];
        for (var val in value) {
          var game = FutsalGame();
          if (val.containsKey("team1vote")) {
            game.team1vote = val["team1vote"] as Map<dynamic, dynamic>;
          }
          if (val.containsKey("team2vote")) {
            game.team2vote = val["team2vote"] as Map<dynamic, dynamic>;
          }
          //game.team1activity = val["team1activity"];
          //game.team2activity = val["team2activity"];
          game.team1 = val["team1"];
          game.team2 = val["team2"];
          game.team1score = val["team1score"].toString();
          game.team2score = val["team2score"].toString();
          game.date = val["Date"];
          game.status = val["status"];
          list.add(game);
        }
        result[key] = list;
      });
      return result;
    }
    catch (e)
    {
        return {};
    }
  }

  Future<Map<String, List<BasketballGame>>> getAllBasketballGames() async {
    try
    {
      DatabaseReference newClient = FirebaseDatabase.instance.ref("/${widget.sport}/${widget.season}");
      var games = await newClient.child("Date").get();
      dynamic data = games.value;
      var result = <String, List<BasketballGame>>{};
      data.forEach((key, value) {
        var list = <BasketballGame>[];
        for (var val in value) {
          var game = BasketballGame();
          if (val.containsKey("team1vote")) {
            game.team1vote = val["team1vote"] as Map<dynamic, dynamic>;
          }
          if (val.containsKey("team2vote")) {
            game.team2vote = val["team2vote"] as Map<dynamic, dynamic>;
          }
          //game.team1activity = val["team1activity"];
          //game.team2activity = val["team2activity"];
          game.team1 = val["team1"];
          game.team2 = val["team2"];
          game.team1score = val["team1score"].toString();
          game.team2score = val["team2score"].toString();
          game.date = val["Date"];
          game.status = val["status"];
          list.add(game);
        }
        result[key] = list;
      });
      return result;
    }
    catch (e)
    {
        return {};
    }
  }

  Future<Map> getAllTeamLogo() async
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var event = await newClient.child("Logo Urls").once();
    Map urls = event.snapshot.value as Map;

    return urls;
  }

  Future<void> fillInNull(game) async {
    if (game is FutsalGame) {
      try
      {
          //gameF.team1lineup = await getBasketballLineUp(season, game.team1);
          //gameF.team2lineup = await getBasketballLineUp(season, game.team2);

          if (game.team1SourcePath == "")
          {
              var league = await getAllTeamLogo();
              var futsal = league["Futsal"];
              var logos = futsal[widget.season];

              game.team1SourcePath = logos[game.team1];
              game.team2SourcePath = logos[game.team2];
          }
      }
      on Exception catch (_, e)
      {
          var message = e.toString();
      }
    }
    if (game is BasketballGame) {
      try
      {
          //gameF.team1lineup = await getBasketballLineUp(season, game.team1);
          //gameF.team2lineup = await getBasketballLineUp(season, game.team2);

          if (game.team1SourcePath == "")
          {
              var league = await getAllTeamLogo();
              var basketball = league["Basketball"];
              var logos = basketball[widget.season];

              game.team1SourcePath = logos[game.team1];
              game.team2SourcePath = logos[game.team2];
          }
      }
      on Exception catch (_, e)
      {
          var message = e.toString();
      }
    }
  }

  Future<int> getSeasonStartTime() async {
    if (times.containsKey(widget.sport))
    {
        if (times[widget.sport]!.containsKey(widget.season))
        {
            return times[widget.sport]![widget.season]!;
        }
    }

    try
    {
        DatabaseReference newClient = FirebaseDatabase.instance.ref("/${widget.sport}/${widget.season}");
        var event = await newClient.child("Start Time").get();
        int seasonStart = event.value as int;

        if (!times.containsKey(widget.sport))
        {
            var dictionary = <String, int>{};
            dictionary[widget.season] = seasonStart;
            times[widget.sport] = dictionary;
        }
        else
        {
            times[widget.sport]![widget.season] = seasonStart;
        }

        return seasonStart;
    }
    on Exception catch (_, e)
    {
        return 5;
    }
  }

  Future<List<Game>> getGames() async {
    List<Game> allGames = <Game>[];
    //if (!await isSeasonFinished(widget.sport, widget.season))
    List<Game> games = <Game>[];

    if (widget.sport == "Futsal")
    {
      var all = await getAllFutsalGames();
      games = List<Game>.from(all[widget.date] as List<Game>);
    }
    else
    {
      var all = await getAllBasketballGames();
      games = List<Game>.from(all[widget.date] as List<Game>);
    }

    int i = 0;
    for (var game in games)
    {
        await fillInNull(game);
        game.Time = (await getSeasonStartTime()) + i;

        switch (game.status)
        {
            case 0:
                game.stringStatus = "Upcoming";
                game.statusColor = Colors.grey;
                break;
            case 1:
                game.stringStatus = "Live";
                game.statusColor = Colors.red;
                break;
            case 2:
                game.stringStatus = "Final";
                game.statusColor = Colors.green;
                break;
        }

        game.UrlPath = "https://infinite-sports-app.firebaseio.com/${widget.sport}/${widget.season}/Date/${widget.date}";
        game.GameNum = i;

        game.SetUpVote();
        game.GetLineUpImages();
        allGames.add(game);
        i++;
    }
    /*
    ToolbarItems.Add(new ToolbarItem("Leader", "Leader.png", async() =>
    {
        Title = "";
        await Navigation.PushAsync(new LeaderboardPage(currentLeague, currentSeason));
    }));

    await addShortcut(currentLeague, currentSeason);
    */
    widget.onTitleSelect(allGames[0].date);
    return allGames;
  }

  List<Card> populateCardList(List<Game> gamesList) {
    List<Card> cardList = [];
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
                        Image.network(width: 70, game.team1SourcePath),
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
                        Image.network(width: 70, game.team2SourcePath),
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
      cardList.add(card);
    }
    return cardList;
  }

  Future<void> _refreshData() async { 
    // Add new items or update the data here 
    List<Game> gamesList = await getGames();
    setState(() { 
      cardList = populateCardList(gamesList); 
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
    tableSport = widget.sport;
    tableSeason = widget.season;
    if (cardList.isEmpty) {
      return RefreshIndicator(
      onRefresh: () async {
        _refreshData;
      },
      child: FutureBuilder(
        future: getGames(), 
        builder:(context, snapshot) {
          if (!snapshot.hasData) {
              return Text("Loading");
          }
          List<Game> gamesList = snapshot.data as List<Game>;
          cardList = populateCardList(gamesList); 
          return ListView(
            padding: const EdgeInsets.all(15),
            children: cardList,
          );
        }), 
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        _refreshData;
      },
      child: ListView(
            padding: const EdgeInsets.all(15),
            children: cardList,
      )
      );
  }
}
