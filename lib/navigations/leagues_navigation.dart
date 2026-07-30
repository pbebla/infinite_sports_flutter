import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

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
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Skeleton sweep (F3 Fix 2): matches the season-tile
                      // list this resolves into below, app bar included so
                      // it doesn't pop in once the data arrives.
                      return Scaffold(
                        appBar: AppBar(centerTitle: true, title: const Text("Futsal")),
                        body: const SkeletonList(),
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text("Futsal")
                      ),
                      // P2.1: SeasonCards need no dividers between rows.
                      body: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              } else if (settings.name == '/basketballLeagues') {
                return FutureBuilder(
                  future: getSeasonTiles("Basketball", context), 
                  builder:(context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Skeleton sweep (F3 Fix 2): matches the season-tile
                      // list this resolves into below, app bar included so
                      // it doesn't pop in once the data arrives.
                      return Scaffold(
                        appBar: AppBar(centerTitle: true, title: const Text("Basketball")),
                        body: const SkeletonList(),
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text("Basketball")
                      ),
                      // P2.1: SeasonCards need no dividers between rows.
                      body: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              } else if (settings.name == '/flagFootballLeagues') {
                return FutureBuilder(
                  future: getSeasonTiles("Flag Football", context), 
                  builder:(context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Skeleton sweep (F3 Fix 2): matches the season-tile
                      // list this resolves into below, app bar included so
                      // it doesn't pop in once the data arrives.
                      return Scaffold(
                        appBar: AppBar(centerTitle: true, title: const Text("Flag Football")),
                        body: const SkeletonList(),
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text("Flag Football")
                      ),
                      // P2.1: SeasonCards need no dividers between rows.
                      body: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              } else if (settings.name == '/currentLeague') {
                return ShowLeaguePage(sport: (settings.arguments as List<String>)[0], season: (settings.arguments as List<String>)[1]);
              } else if (settings.name == '/afcsanjose') {
                return FutureBuilder(
                  future: getSeasonTiles("AFC San Jose", context), 
                  builder:(context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      // Skeleton sweep (F3 Fix 2): matches the season-tile
                      // list this resolves into below, app bar included so
                      // it doesn't pop in once the data arrives.
                      return Scaffold(
                        appBar: AppBar(centerTitle: true, title: const Text("AFC San Jose")),
                        body: const SkeletonList(),
                      );
                    }
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: Text("AFC San Jose")
                      ),
                      body: ListView.separated(
                        // Theme-staleness fix (F3.1): separatorBuilder's own
                        // `context` can go stale after a theme toggle, same
                        // as itemBuilder rows (see fixtures_tab.dart, F3 Fix
                        // 1) — wrap in a Builder so this Divider's
                        // Theme.of() lookup stays live/dependency-tracked.
                        separatorBuilder: (context, index) => Builder(
                          builder: (context) => Divider(
                                color: Theme.of(context).dividerColor,
                              ),
                        ),
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) => snapshot.data![index]
                      )
                    );
                  },);
              }
              return const LeaguesPage();
            });
      },
    );
  }
}