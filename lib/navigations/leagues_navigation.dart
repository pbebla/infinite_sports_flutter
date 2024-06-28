import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:infinite_sports_flutter/showleague.dart';

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
                      return Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        )
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(title: const Text("Futsal")), 
                      body: ListView.separated(
                        separatorBuilder: (context, index) => Divider(
                              color: Colors.black,
                            ),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              } else if (settings.name == '/basketballLeagues') {
                return FutureBuilder(
                  future: getSeasonTiles("Basketball", context), 
                  builder:(context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        )
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(title: const Text("Basketball")), 
                      body: ListView.separated(
                        separatorBuilder: (context, index) => Divider(
                              color: Colors.black,
                            ),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              } else if (settings.name == '/currentLeague') {
                return ShowLeaguePage(sport: (settings.arguments as List<String>)[0], season: (settings.arguments as List<String>)[1]);
              }
              return LeaguesPage();
            });
      },
    );
  }
}