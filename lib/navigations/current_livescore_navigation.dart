import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/frontpage.dart';

class CurrentLivescoreNavigation extends StatefulWidget {
  const CurrentLivescoreNavigation({super.key,required this.onTitleSelect});

  final Function(String) onTitleSelect;

  @override
  CurrentLivescoreNavigationState createState() => CurrentLivescoreNavigationState();
}

GlobalKey<NavigatorState> wishListNavigatorKey = GlobalKey<NavigatorState>();

class CurrentLivescoreNavigationState extends State<CurrentLivescoreNavigation> {
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: wishListNavigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            return FrontPage(onTitleSelect: widget.onTitleSelect);
          },
        );
      });
    
  }
}