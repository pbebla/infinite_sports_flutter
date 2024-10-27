import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/showleague.dart';

class CurrentLivescoreNavigation extends StatefulWidget {
  const CurrentLivescoreNavigation({super.key, required this.currentSport, required this.currentSeason, required this.currentAFCSeason, required this.currentDate, required this.onTitleSelect, required this.isISSeasonFinished, required this.isAFCSeasonFinished});
  final String currentSport;
  final String currentSeason;
  final String currentAFCSeason;
  final String currentDate;
  final bool isISSeasonFinished;
  final bool isAFCSeasonFinished;
  final Function(String) onTitleSelect;

  @override
  CurrentLivescoreNavigationState createState() => CurrentLivescoreNavigationState();
}

GlobalKey<NavigatorState> wishListNavigatorKey = GlobalKey<NavigatorState>();

class CurrentLivescoreNavigationState extends State<CurrentLivescoreNavigation> {
  List<Widget> tabs = List.empty(growable: true);
  List<Tab> tabNames = List.empty(growable: true);

  @override
  Widget build(BuildContext context) {
    tabs.clear();
    tabNames.clear();
    
    return Navigator(
      key: wishListNavigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          settings: settings,
          builder: (BuildContext context) {
            if (settings.name == '/currentLeague') {
              return ShowLeaguePage(sport: widget.currentSport, season: widget.currentSeason);
            }
            if (!widget.isISSeasonFinished || !widget.isAFCSeasonFinished) {
              if (!widget.isISSeasonFinished) {
                tabNames.add(Tab(text: "Infinite Sports"));
                tabs.add(Column(children: [
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
                ));
              }
              if (!widget.isAFCSeasonFinished) {
                tabNames.add(Tab(text: "AFC San Jose"));
                tabs.add(Column(children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder:(context) {
                        return ShowLeaguePage(sport: "AFC San Jose", season: widget.currentAFCSeason);
                      },));
                    },
                    child: Card(
                      elevation: 2,
                      child: SizedBox(
                        width: 350,
                        height: 70,
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          child: Row(children: [Flexible(child: Text(widget.currentAFCSeason, style: const TextStyle(fontWeight: FontWeight.bold),)), ImageIcon(AssetImage('assets/FutsalLeague.png'), size: windowsDefaultIconSize.toDouble(),)],),),
                      )
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  Text(convertDatabaseDateToFormatDate(widget.currentDate), style: const TextStyle(fontWeight: FontWeight.bold),),
                  Expanded(
                    child: LiveScorePage(sport: "AFC San Jose", season: widget.currentAFCSeason, date: widget.currentDate ,onTitleSelect: (String value) {widget.onTitleSelect(value); })
                  )
                ]
                ));
              }
              return DefaultTabController(
                length: tabs.length, 
                child: Scaffold(
                  appBar: AppBar(
                    title: TabBar(
                      tabs: tabNames,
                      onTap: (value) {
                        if (tabNames[value].text == "Infinite Sports") {
                          headerNotifier.value = [widget.currentSport, widget.currentSeason];
                        } else if (tabNames[value].text == "AFC San Jose") {
                          headerNotifier.value = ["AFC San Jose", widget.currentAFCSeason];
                        }
                      },
                    ),
                  ),
                  body: TabBarView(
                    children: tabs,
                  )
                )
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