import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/model/basketballgame.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:infinite_sports_flutter/model/game.dart';

typedef TitleCallback = void Function(String value);
var cardList = <Card>[];

class LiveScorePage extends StatefulWidget {
  const LiveScorePage({super.key, required this.onTitleSelect});
  final TitleCallback onTitleSelect;

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

  @override
  State<LiveScorePage> createState() => _LiveScorePageState();
}

class _LiveScorePageState extends State<LiveScorePage> {
  Map<String, Map<String, int>> times = {};
  Future<String> getCurrentSport() async {
    try
    {
      DatabaseReference newClient = FirebaseDatabase.instance.ref();
      var season = await newClient.child("Current League").get();
      return season.value.toString();
    }
    catch (e)
    {
        return e.toString();
    }
  }

  Future<String> getCurrentSeason(currentSport) async {
    try
    {
      DatabaseReference newClient = FirebaseDatabase.instance.ref();
      var seasonNum = await newClient.child(currentSport + " Season").get();
      return seasonNum.value.toString();
    }
    catch (e)
    {
        return e.toString();
    }
  }

  Future<bool> isSeasonFinished(sport, season) async {
    try
    {
        DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
        var seasonFinished = await newClient.child("Finished").get();
        return seasonFinished.value as bool;
    }
    catch (e)
    {
        return true;
    }
  }

  Future<Map<String, List<BasketballGame>>> getAllCurrentBasketballGames() async {
    try
    {
      var sport = "Basketball";
      var season = await getCurrentSeason(sport);

      DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
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

  String convertDateToDatabase(DateTime date) {
    String formattedDate = "";

    if (date.month < 10)
    {
        formattedDate = "0${date.month.toString()}";
    }
    else
    {
        formattedDate = date.month.toString();
    }

    if (date.day < 10)
    {
        formattedDate = "${formattedDate}0${date.day.toString()}";
    }
    else
    {
        formattedDate = formattedDate + (date.day.toString());
    }

    return formattedDate + (date.year.toString());
  }

  Future<Map> getAllTeamLogo() async
  {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    var event = await newClient.child("Logo Urls").once();
    Map urls = event.snapshot.value as Map;

    return urls;
  }

  Future<void> fillInNull(game, season) async {
    //if (game is FutsalGame)
    /*
    if (false)
      try
      {
        var gameF = (FutsalGame)game;

        gameF.team1lineup = await getFutsalLineUp(season, game.team1);
        gameF.team2lineup = await getFutsalLineUp(season, game.team2);
        if (((FutsalGame)game).team1Source == null)
        {
            var league = Utility.TeamLogos["Futsal"];
            var logos = league[season];

            game.team1Source = ImageSource.FromUri(new Uri(logos[game.team1]));
            game.team2Source = ImageSource.FromUri(new Uri(logos[game.team2]));
        }

      }
      catch (Exception e)
      {
          var message = e.Message;
      }
    */
    if (game is BasketballGame) {
      try
      {
          //gameF.team1lineup = await getBasketballLineUp(season, game.team1);
          //gameF.team2lineup = await getBasketballLineUp(season, game.team2);

          if (game.team1SourcePath == "")
          {
              var league = await getAllTeamLogo();
              var basketball = league["Basketball"];
              var logos = basketball[season];

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

  Future<int> getSeasonStartTime(sport, season) async {
    if (times.containsKey(sport))
    {
        if (times[sport]!.containsKey(season))
        {
            return times[sport]![season]!;
        }
    }

    try
    {
        DatabaseReference newClient = FirebaseDatabase.instance.ref("/$sport/$season");
        var event = await newClient.child("Start Time").get();
        int seasonStart = event.value as int;

        if (!times.containsKey(sport))
        {
            var dictionary = <String, int>{};
            dictionary[season] = seasonStart;
            times[sport] = dictionary;
        }
        else
        {
            times[sport]![season] = seasonStart;
        }

        return seasonStart;
    }
    on Exception catch (_, e)
    {
        return 5;
    }
  }

  Future<List<Game>> getCurrentGames() async {
    List<Game> allGames = <Game>[];
    var currentSport = await getCurrentSport();
    var currentSeason = await getCurrentSeason(currentSport);
    if (!await isSeasonFinished(currentSport, currentSeason))
    {

        List<Game> games = <Game>[];

        var Sunday = DateTime.now();

        while (Sunday.weekday != DateTime.sunday)
        {
            Sunday = Sunday.add(const Duration(days: 1));
        }

        if (currentSport == "Futsal")
        {
          /*
            var all = await FirebaseGetter.getAllCurrentFutsalGames();

            while (!all.ContainsKey(Utility.ConvertDateToDatabase(Sunday)))
            {
                Sunday = Sunday.add(const Duration(days: 7));
            }

            games = all[Utility.ConvertDateToDatabase(Sunday)].ToList<Game>();
          */        
        }
        else
        {
            var all = await getAllCurrentBasketballGames();

            while (!all.containsKey(convertDateToDatabase(Sunday)))
            {
                Sunday = Sunday.add(const Duration(days: 7));
            }

            games = List<Game>.from(all[convertDateToDatabase(Sunday)] as List<Game>);
        }

        int i = 0;
        for (var game in games)
        {
            await fillInNull(game, currentSeason);
            game.Time = (await getSeasonStartTime(currentSport, currentSeason)) + i;

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

            game.UrlPath = "https://infinite-sports-app.firebaseio.com/$currentSport/$currentSeason/Date/${convertDateToDatabase(Sunday)}";
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
    }
    widget.onTitleSelect(allGames[0].date);
    return allGames;
  }
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
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
                    Expanded(child:Text(game.stringStatus,textAlign: TextAlign.left, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
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
                          progressColor: Colors.green,
                    ),
                    Expanded(
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
                    CircularPercentIndicator(
                          radius: 30,
                          lineWidth: 4.0,
                          percent: game.finalvote2,
                          center: Text(game.percvote2),
                          progressColor: Colors.green,
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
    List<Game> gamesList = await getCurrentGames();
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
    if (cardList.isEmpty) {
      return RefreshIndicator(
      onRefresh: () async {
        _refreshData;
      },
      child: FutureBuilder(
        future: getCurrentGames(), 
        builder:(context, snapshot) {
          if (!snapshot.hasData) {
              return Card(child: SizedBox(height: 50, child: Column(children: [Text("Loading...")])));
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
