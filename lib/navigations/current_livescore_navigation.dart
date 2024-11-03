import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/frontpage.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/showleague.dart';

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