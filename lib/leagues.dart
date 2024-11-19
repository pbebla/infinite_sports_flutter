import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
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
  if (sport == "AFC San Jose") {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/AFC San Jose/");
    var event = await newClient.child("Seasons").once();
    var seasonsMap = event.snapshot.value as Map;
    seasonsMap.forEach((k, v) {
      var seasonView = ListTile(
      title: Text("$k"),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return ShowLeaguePage(sport: sport, season: k);
          },));
        }
      );

      seasons.add(seasonView);
    });
    
    return seasons;
  }
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
    List<ListTile> list = [
      ListTile(leading: const ImageIcon(AssetImage('assets/FutsalLeague.png')), title: const Text("Assyrian Futsal League"),
      onTap: () {
        Navigator.pushNamed(context, "/futsalLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/BasketLeague.png')), title: const Text("Assyrian Basketball League"),
      onTap:() {
        Navigator.pushNamed(context, "/basketballLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/FutsalLeague.png')), title: const Text("AFC San Jose"),
      onTap:() {
        Navigator.pushNamed(context, "/afcsanjose");
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
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        title: Text("Leagues"),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: FutureBuilder(
        future: populateMenus(), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                )
              );
          }
          return ListView.separated(
            separatorBuilder: (context, index) => Divider(
              color: Theme.of(context).dividerColor,
            ),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => snapshot.data![index]
          );
        },
      )
    );
  }
}