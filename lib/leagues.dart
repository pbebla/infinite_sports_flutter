import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/leaguemenu.dart';
import 'package:infinite_sports_flutter/navbar.dart';

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

class _LeaguesPageState extends State<LeaguesPage> {
  List<ListTile> populateMenus() {
    List<ListTile> list = [
      ListTile(leading: ImageIcon(AssetImage('assets/FutsalLeague.png')), title: Text("Assyrian Futsal League"),
      onTap: () {
        var seasons = List<ListTile>.empty(growable: true);
        int i = 1;
        int max = 13;
        while (i <= max)
        {
            var seasonView = ListTile(title: Text("Season $i"));

            seasons.add(seasonView);

            i++;
        }
        Navigator.push(context, MaterialPageRoute(builder:(context) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text("Futsal"),
              foregroundColor: Colors.white,
            ),
            body: ListView(children: seasons,));
        }));
      },),
      ListTile(leading: ImageIcon(AssetImage('assets/BasketLeague.png')), title: Text("Assyrian Basketball League"),
      onTap:() {
        var seasons = List<ListTile>.empty(growable: true);
        int i = 1;
        int max = 3;
        while (i <= max)
        {
            var seasonView = ListTile(title: Text("Season $i"));

            seasons.add(seasonView);

            i++;
        }
        Navigator.push(context, MaterialPageRoute(builder:(context) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              title: Text("Basketball"),
              foregroundColor: Colors.white,
            ),
            body: ListView(children: seasons,));
        }));
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
      body: ListView(
      children: populateMenus(),
  ),
    );
  }
}