import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_detail_page.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/showleague.dart';

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

/// Sport → the league icon asset already used on the leagues menu.
String _sportIconAsset(String sport) {
  switch (sport) {
    case "Basketball":
      return 'assets/BasketLeague.png';
    case "Flag Football":
      return 'assets/FlagFootballLeague.png';
    default:
      return 'assets/FutsalLeague.png';
  }
}

/// Modern season card (P2.1 Task A3: replaces the plain grey ListTiles):
/// rounded card, sport-icon accent, "Season N" title, chevron — reads in
/// both light and dark mode via colorScheme. Public for widget tests.
class SeasonCard extends StatelessWidget {
  final String title;
  final String iconAsset;
  final VoidCallback onTap;

  const SeasonCard({
    super.key,
    required this.title,
    required this.iconAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: ImageIcon(
                    AssetImage(iconAsset),
                    size: 22,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List<Widget>> getSeasonTiles(sport, context) async {
  List<Widget> seasons = List<Widget>.empty(growable: true);
  if (sport == "AFC San Jose") {
    DatabaseReference newClient = FirebaseDatabase.instance.ref("/AFC San Jose/");
    var event = await newClient.child("Seasons").once();
    var seasonsMap = event.snapshot.value as Map;
    seasonsMap.forEach((k, v) {
      var seasonView = ListTile(
      title: Text("$k"),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return ShowLeaguePage(sport: sport, season: k);
          },));
        }
      );

      seasons.add(seasonView);
    });

    return seasons;
  }
  var i = int.parse(await getMinSeason(sport));
  var max = int.parse(await getCurrentSeason(sport));
  while (i <= max)
  {
    var season = i.toString();
    // P2.1: modern SeasonCard, same navigation as before — futsal opens the
    // tournament-parity league page (P2); Basketball/Flag Football keep
    // ShowLeaguePage until P4.
    var seasonView = SeasonCard(
      title: "Season $i",
      iconAsset: _sportIconAsset(sport.toString()),
      onTap: () {
        if (sport == "Futsal") {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return LeagueDetailPage(sport: "Futsal", season: season);
          },));
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder:(context) {
          return ShowLeaguePage(sport: sport, season: season.toString());
        },));
      },
    );

    seasons.add(seasonView);

    i++;
  }
  return seasons;
}

class _LeaguesPageState extends State<LeaguesPage> {
  Future<List<ListTile>> populateMenus() async {
    List<ListTile> list = [
      ListTile(leading: const ImageIcon(AssetImage('assets/FutsalLeague.png')), title: const Text("Assyrian Futsal League"),
      onTap: () {
        Navigator.pushNamed(context, "/futsalLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/BasketLeague.png')), title: const Text("Assyrian Basketball League"),
      onTap:() {
        Navigator.pushNamed(context, "/basketballLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/FlagFootballLeague.png')), title: const Text("Assyrian Flag Football League"),
      onTap:() {
        Navigator.pushNamed(context, "/flagFootballLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/FutsalLeague.png')), title: const Text("AFC San Jose"),
      onTap:() {
        Navigator.pushNamed(context, "/afcsanjose");
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
      appBar: AppBar(
        centerTitle: true,
        title: Image.asset('assets/infinitelarge_dark.png', height: 30),
      ),
      body: FutureBuilder(
        future: populateMenus(), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                )
              );
          }
          return ListView.separated(
            separatorBuilder: (context, index) => Divider(
              color: Theme.of(context).dividerColor,
            ),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => snapshot.data![index]
          );
        },
      )
    );
  }
}