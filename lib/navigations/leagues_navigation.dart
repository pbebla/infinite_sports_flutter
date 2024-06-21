import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/leagues.dart';

class LeaguesNavigation extends StatefulWidget {
  const LeaguesNavigation({super.key});

  @override
  LeaguesNavigationState createState() => LeaguesNavigationState();
}

GlobalKey<NavigatorState> wishListNavigatorKey = GlobalKey<NavigatorState>();

class LeaguesNavigationState extends State<LeaguesNavigation> {
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: wishListNavigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
            settings: settings,
            builder: (BuildContext context) {
              if (settings.name == "/futsalLeagues") {
                return FutureBuilder(
                  future: getSeasonTiles("Futsal", context), 
                  builder:(context, snapshot) {
                    if (!snapshot.hasData) {
                      return Text("Loading");
                    }
                    return Scaffold(appBar: AppBar(title: const Text("Futsal")), body:ListView(children: snapshot.data!));
                  },);
              } else if (settings.name == '/basketballLeagues') {
                return FutureBuilder(
                  future: getSeasonTiles("Basketball", context), 
                  builder:(context, snapshot) {
                    if (!snapshot.hasData) {
                      return Text("Loading");
                    }
                    return Scaffold(appBar: AppBar(title: const Text("Basketball")), body:ListView(children: snapshot.data!));
                  },);
              }
              return LeaguesPage();
            });
      },
    );
  }
}