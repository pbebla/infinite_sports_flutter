import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_detail_page.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/season_pointers.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/misc/fresh_read.dart';

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
    var event = await refreshingOnce(newClient.child("Seasons"));
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
    // P2.1: modern SeasonCard, same navigation as before — futsal, basketball
    // and flag football open the tournament-parity league page (P2/P4); any
    // other sport (AFC San Jose) keeps ShowLeaguePage.
    var seasonView = SeasonCard(
      title: "Season $i",
      iconAsset: _sportIconAsset(sport.toString()),
      onTap: () {
        if (isLeagueEngineSport(sport.toString())) {
          Navigator.push(context, MaterialPageRoute(builder:(context) {
            return LeagueDetailPage(
                sport: sport.toString(), season: season);
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

/// A league sport's season list (Leagues tab → Futsal / Basketball / Flag
/// Football). Follows the live season pointer (fresh-reads Task 2): when
/// `<Sport> Season` moves (Season 15 → 16) the list is rebuilt and swapped
/// in one update — the old list stays on screen meanwhile, no skeleton
/// flash. Only the first load shows the skeleton.
class SeasonTilesPage extends StatefulWidget {
  const SeasonTilesPage({super.key, required this.sport, required this.title});

  final String sport;
  final String title;

  /// Test seam replacing [getSeasonTiles] (null = real).
  @visibleForTesting
  static Future<List<Widget>> Function(String sport, BuildContext context)?
      tilesOverride;

  @override
  State<SeasonTilesPage> createState() => _SeasonTilesPageState();
}

class _SeasonTilesPageState extends State<SeasonTilesPage> {
  List<Widget>? _tiles;
  String? _season;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    SeasonPointers.listenable.addListener(_onPointers);
    _load();
  }

  @override
  void dispose() {
    SeasonPointers.listenable.removeListener(_onPointers);
    super.dispose();
  }

  void _onPointers() {
    final now = SeasonPointers.listenable.value.seasonFor(widget.sport);
    if (now == null || now == _season) return;
    _load();
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final load = SeasonTilesPage.tilesOverride ?? getSeasonTiles;
    try {
      final season = await SeasonPointers.read(seasonPointerPath(widget.sport));
      if (!mounted || gen != _gen) return;
      final tiles = await load(widget.sport, context);
      if (!mounted || gen != _gen) return;
      setState(() {
        _season = season;
        _tiles = tiles;
      });
    } catch (e) {
      // Keep the list on screen; a failed first load shows an empty list
      // (what the old FutureBuilder showed on an error) instead of a
      // skeleton forever.
      debugPrint('Season list ${widget.sport}: load failed: $e');
      if (!mounted || gen != _gen) return;
      if (_tiles == null) setState(() => _tiles = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(widget.title)),
      // Skeleton sweep (F3 Fix 2): matches the season-tile list, app bar
      // included so it doesn't pop in once the data arrives.
      body: tiles == null
          ? const SkeletonList()
          // P2.1: SeasonCards need no dividers between rows. Bottom inset
          // clears the floating glass nav bar (PR #12 review).
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(
                  0, 8, 0, 8 + MediaQuery.paddingOf(context).bottom),
              itemCount: tiles.length,
              itemBuilder: (context, index) => tiles[index],
            ),
    );
  }
}

class _LeaguesPageState extends State<LeaguesPage> {
  Future<List<ListTile>> populateMenus() async {
    List<ListTile> list = [
      ListTile(leading: const ImageIcon(AssetImage('assets/FutsalLeague.png')), title: const Text("Futsal League"),
      onTap: () {
        Navigator.pushNamed(context, "/futsalLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/BasketLeague.png')), title: const Text("Basketball League"),
      onTap:() {
        Navigator.pushNamed(context, "/basketballLeagues");
      },),
      ListTile(leading: const ImageIcon(AssetImage('assets/FlagFootballLeague.png')), title: const Text("Flag Football League"),
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
        title: Image.asset('assets/infinite_mark.png', height: 32),
      ),
      body: FutureBuilder(
        future: populateMenus(), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Skeleton sweep (F3 Fix 2): matches the menu ListTiles below.
            return const SkeletonList(count: 4);
          }
          return ListView.separated(
            // Theme-staleness fix (F3.1): separatorBuilder's own `context`
            // can go stale after a theme toggle, same as itemBuilder rows
            // (see fixtures_tab.dart, F3 Fix 1) — wrap in a Builder so this
            // Divider's Theme.of() lookup stays live/dependency-tracked.
            separatorBuilder: (context, index) => Builder(
              builder: (context) => Divider(
                color: Theme.of(context).dividerColor,
              ),
            ),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => snapshot.data![index]
          );
        },
      )
    );
  }
}