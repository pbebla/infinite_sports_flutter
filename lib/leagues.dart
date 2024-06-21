import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/botnavbar.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/leaguemenu.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/showleague.dart';

class LeaguesPage extends StatefulWidget {
  const LeaguesPage({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

  @override
  State<LeaguesPage> createState() => _LeaguesPageState();
}

Future<List<ListTile>> getSeasonTiles(sport, context) async {
  List<ListTile> seasons = List<ListTile>.empty(growable: true);
  var i = int.parse(await getMinSeason(sport));
  var max = int.parse(await getCurrentSeason(sport));
  while (i <= max)
  {
    var season = i.toString();
    var seasonView = ListTile(
      title: Text("Season $i"),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder:(context) {
          return ShowLeaguePage(sport: sport, season: season.toString());
        },));
      }
    );

    seasons.add(seasonView);

    i++;
  }
  return seasons;
}

class _LeaguesPageState extends State<LeaguesPage> {
  Future<List<ListTile>> populateMenus() async {
    /*
    var basketMin = int.parse(await getMinSeason("Basketball"));
    var futsalMin = int.parse(await getMinSeason("Futsal"));
    var basketCurrent = int.parse(await getCurrentSeason("Basketball"));
    var futsalCurrent = int.parse(await getCurrentSeason("Futsal"));

    int i = futsalMin;
    int max = futsalCurrent;
    while (i <= max)
    {
      var season = i.toString();
      var seasonView = ListTile(
        title: Text("Season $i"),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return ShowLeaguePage(sport: "Futsal", season: season.toString());
          },));
        }
      );

      futsalSeasons.add(seasonView);

      i++;
    }

    i = basketMin;
    max = basketCurrent;
    while (i <= max)
    {
      var season = i.toString();
      var seasonView = ListTile(
        title: Text("Season $i"),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return ShowLeaguePage(sport: "Basketball", season: season.toString());
          },));
        }
      );

      basketballSeasons.add(seasonView);

      i++;
    }*/

    List<ListTile> list = [
      ListTile(leading: ImageIcon(AssetImage('assets/FutsalLeague.png')), title: Text("Assyrian Futsal League"),
      onTap: () {
        Navigator.pushNamed(context, "/futsalLeagues");
      },),
      ListTile(leading: ImageIcon(AssetImage('assets/BasketLeague.png')), title: Text("Assyrian Basketball League"),
      onTap:() {
        Navigator.pushNamed(context, "/basketballLeagues");
      },),
    ];
    return list;
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
      future: populateMenus(), 
      builder:(context, snapshot) {
        if (!snapshot.hasData) {
          return Text("Loading");
        }
        return Scaffold(
          body: ListView(
          children: snapshot.data!,
          )
        );
      },
    );
  }
}