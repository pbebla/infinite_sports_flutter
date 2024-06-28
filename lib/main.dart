import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:infinite_sports_flutter/botnavbar.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/leagues.dart';
import 'package:infinite_sports_flutter/livescore.dart';
import 'package:infinite_sports_flutter/navigations/current_livescore_navigation.dart';
import 'package:infinite_sports_flutter/navigations/leagues_navigation.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:infinite_sports_flutter/table.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

var infiniteSportsPrimaryColor = const Color.fromARGB(255, 208, 0, 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: infiniteSportsPrimaryColor, primary: infiniteSportsPrimaryColor),
        useMaterial3: true,
      ),
      home: LoginPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  String _title = "";
  String _liveScoresTitle = "Live Scores";
  String currentSport = "";
  String currentSeason = "";
  String currentDate = "";

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    setTitle(_liveScoresTitle);
  }

  void setTitle(String value) {
    setState(() {
      _title = value;
    });
  }

  void setLiveScoreTitle(String value) {
    setState(() {
      _liveScoresTitle = value;
      setTitle(_liveScoresTitle);
    });
  }

  Future<int> setCurrentValues() async {
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    currentDate = await getCurrentDate(currentSport, currentSeason);
    headerNotifier.value = [currentSport, currentSeason];
    await getAllTeamLogo();
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _widgetOptions = <Widget>[
      FutureBuilder(future: setCurrentValues(), builder:(context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        return CurrentLivescoreNavigation(currentSport: currentSport, currentSeason: currentSeason, currentDate: currentDate, onTitleSelect: setLiveScoreTitle);
      },),
      LeaguesNavigation(),
      Text('Index 2: School'),
    ];
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      drawer: NavBar(),
      appBar: GlobalAppBar(title: _title, height: AppBar().preferredSize.height),
      body: Center(
        child: IndexedStack(
          index: _selectedIndex,
          children: _widgetOptions
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/scores.png')),
          label: 'Live Scores'),
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/leagues.png')),
          label: 'Leagues'),
        BottomNavigationBarItem(
          icon: ImageIcon(AssetImage('assets/aroundyou.png')),
          label: 'Around You'),
      ],
      selectedItemColor: Theme.of(context).colorScheme.primary,
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      ) // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      switch(index) { 
        case 0: { _title = _liveScoresTitle; } 
        break; 
        case 1: { _title = 'Leagues'; } 
        break;
        case 2: { _title = 'Around You'; } 
        break;
      } 
    });
  }
}

