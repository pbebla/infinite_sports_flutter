import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/tournamentspage.dart';

class TournamentsNavigation extends StatefulWidget {
  const TournamentsNavigation({super.key});

  @override
  TournamentsNavigationState createState() => TournamentsNavigationState();
}

GlobalKey<NavigatorState> tournamentsNavigatorKey = GlobalKey<NavigatorState>();

class TournamentsNavigationState extends State<TournamentsNavigation> {
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: tournamentsNavigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            return const TournamentsPage();
          },
        );
      },
    );
  }
}
