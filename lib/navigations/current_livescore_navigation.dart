import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/showleague.dart';

class CurrentLivescoreNavigation extends StatefulWidget {
  const CurrentLivescoreNavigation({super.key, required this.currentSport, required this.currentSeason, required this.currentDate, required this.onTitleSelect, required this.isSeasonFinished});
  final String currentSport;
  final String currentSeason;
  final String currentDate;
  final bool isSeasonFinished;
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
            if (settings.name == '/currentLeague') {
              return ShowLeaguePage(sport: widget.currentSport, season: widget.currentSeason);
            }
            if (!widget.isSeasonFinished) {
              return Column(children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder:(context) {
                      return ShowLeaguePage(sport: widget.currentSport, season: widget.currentSeason);
                    },));
                  },
                  child: Card(
                    elevation: 2,
                    child: SizedBox(
                      width: 350,
                      height: 70,
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        child: Row(children: [Text("Assyrian ${widget.currentSport} League Season ${widget.currentSeason}", style: const TextStyle(fontWeight: FontWeight.bold),), const Spacer(), ImageIcon(AssetImage(widget.currentSport == "Futsal" ? 'assets/FutsalLeague.png' : 'assets/BasketLeague.png'), size: windowsDefaultIconSize.toDouble(),)],),),
                    )
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                Text(convertDatabaseDateToFormatDate(widget.currentDate), style: const TextStyle(fontWeight: FontWeight.bold),),
                Expanded(
                  child: LiveScorePage(sport: widget.currentSport, season: widget.currentSeason, date: widget.currentDate ,onTitleSelect: (String value) {widget.onTitleSelect(value); })
                )
              ]
              );
            }
            return Center(
              child: Card(
              elevation: 2,
              shadowColor: Colors.black,
              color: Colors.white,
              child: SizedBox(
                width: 350,
                height: 70,
                child: Container(
                  padding: const EdgeInsets.all(13),
                  child: const Text("No Upcoming Games,\nStay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),),
              )
            ),);
          }
        );
      },
    );
  }
}