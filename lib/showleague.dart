import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leaderboard.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:intl/intl.dart';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

typedef TitleCallback = void Function(String value);

class ShowLeaguePage extends StatefulWidget {
  const ShowLeaguePage({super.key, required this.sport, required this.season});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;
  final String sport;
  final String season;

  @override
  State<ShowLeaguePage> createState() => _ShowLeaguePageState();
}

class _ShowLeaguePageState extends State<ShowLeaguePage> { 
  List<LiveScorePage> scoresList = <LiveScorePage>[];
  List<Tab> dateList = <Tab>[];
  Future<int>? _league;

  @override
  void initState() {
    _league = buildLeague();
    super.initState();
  }
  
  Future<int> buildLeague() async {
    var dates = await getDates(widget.sport, widget.season);
    dates.sort();
    for (var date in dates) {
      int year = int.parse(date.substring(4));
      int day = int.parse(date.substring(2,4));
      int month = int.parse(date.substring(0,2));
      if (dateList.length < dates.length && scoresList.length < dates.length) {
        dateList.add(Tab(text: DateFormat.yMMMMd('en_US').format(DateTime.utc(year, month=month, day=day))));
        scoresList.add(LiveScorePage(onTitleSelect:(value) {}, sport: widget.sport, season: widget.season, date: date));
      }
    }
    return 1;
  }
  
  @override
  Widget build(BuildContext context) {
    executeAfterBuild();
    return FutureBuilder(
      future: _league, 
      builder:(context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        return DefaultTabController(
          length: dateList.length,
          child: Scaffold(
            appBar: GlobalAppBar(
              title: Flexible(child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                    text: widget.sport,
                    style: TextStyle(fontSize: Theme.of(context).textTheme.headlineSmall!.fontSize),
                    children: <TextSpan>[
                      TextSpan(
                        text: '\n${widget.season}',
                        style: TextStyle(
                          fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                        ),
                      ),
                    ]
                ),
              ),),
              height: AppBar().preferredSize.height, 
              showTables: true,
            ),
            body: CustomScrollView(
              controller: ScrollController(),
              slivers: [
                SliverAppBar(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context), 
                    icon: Icon(Icons.arrow_back)
                  ),
                  title: TabBar(
                    tabAlignment: TabAlignment.start,
                    isScrollable: true,
                    tabs: dateList
                  ),
                ),
                SliverFillRemaining(
                  child: TabBarView(
                    children: scoresList,
                  ),
                )
              ],
            )
          )
        );
      },
    );
  }

  Future<void> executeAfterBuild() async {
    await Future.delayed(Duration.zero);
    headerNotifier.value = [widget.sport, widget.season];
    // this code will get executed after the build method
    // because of the way async functions are scheduled
  }
}