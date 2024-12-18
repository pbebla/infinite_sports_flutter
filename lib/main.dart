import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:infinite_sports_flutter/aroundyou.dart';
import 'package:infinite_sports_flutter/misc/pushnotifications.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/navigations/current_livescore_navigation.dart';
import 'package:infinite_sports_flutter/navigations/leagues_navigation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterConfig.loadEnvVariables();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await PushNotifications.init();
  await PushNotifications.initLocalNotifications();
  FirebaseMessaging.instance.getToken().then( (token) {
    assert(token != null);
    print("device token: $token");
  }
  );
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    if (signedIn) {
      await uploadToken(FirebaseAuth.instance.currentUser!, newToken);
    }
  });
  FirebaseMessaging.onMessage.listen((message) {
    String payloadData = jsonEncode(message.data);
    print("Received notification in foreground");
    if (message.notification != null) {
      PushNotifications.showSimpleNotification(title: message.notification!.title!, body: message.notification!.body!, payload: payloadData);
    }
  },);
  final RemoteMessage? message = 
    await FirebaseMessaging.instance.getInitialMessage();
  if (message != null) {
    print("Launched from terminated state");
  }
  SharedPreferences prefs = await SharedPreferences.getInstance();
  darkModeEnabled = prefs.getBool('darkMode') ?? false;
  autoSignIn = prefs.getBool('autoSignIn') ?? false;
  runApp(ChangeNotifierProvider(create: (context) => ThemeProvider(darkModeEnabled), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinite Sports',
      theme: Provider.of<ThemeProvider>(context).themeData,
      home: const MyHomePage(),
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
  String currentAFCSeason = "";
  String currentDate = "";
  String currentAFCDate = "";
  bool isCurrentFinished = false;
  bool isCurrentAFCFinished = false;
  Future<int>? _fetchCurrentValues;

  @override
  void initState() {
    // TODO: implement initState
    setTitle(_liveScoresTitle);
    _fetchCurrentValues = setCurrentValues();
    super.initState();
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
    if (FirebaseAuth.instance.currentUser != null && autoSignIn) {
      signedIn = true;
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await uploadToken(FirebaseAuth.instance.currentUser!, token);
      }
    } else {
      FirebaseAuth.instance.signOut();
    }
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    headerNotifier.value = [currentSport, currentSeason];
    await getAllTeamLogo();
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    mainContext = context;
    final List<Widget> widgetOptions = <Widget>[
      FutureBuilder(future: _fetchCurrentValues, builder:(context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        if (isCurrentFinished) {
          return const Center(child: Card(child: Text("No Current Games, Stay Tuned for Next Season!", style: TextStyle(fontWeight: FontWeight.bold))));
        }
        return CurrentLivescoreNavigation(onTitleSelect: setLiveScoreTitle);
      },),
      const LeaguesNavigation(),
      const AroundYou(),
    ];
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      drawer: const NavBar(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Builder(
        builder: (context) {
          mainScaffoldContext = context;
          return IndexedStack(
              index: _selectedIndex,
              children: widgetOptions
          );
        }
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(
            icon: ImageIcon(AssetImage('assets/scores.png')),
            selectedIcon: ImageIcon(AssetImage('assets/scores.png'), color: Colors.white,),
            label: 'Live Scores'),
          NavigationDestination(
            icon: ImageIcon(AssetImage('assets/leagues.png')),
            selectedIcon: ImageIcon(AssetImage('assets/leagues.png'), color: Colors.white,),
            label: 'Leagues'),
          NavigationDestination(
            icon: ImageIcon(AssetImage('assets/aroundyou.png')),
            selectedIcon: ImageIcon(AssetImage('assets/aroundyou.png'), color: Colors.white,),
            label: 'Around You'),
        ],
        indicatorColor: Theme.of(context).colorScheme.primary,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        ) // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      switch(index) { 
        case 0: { 
          _title = _liveScoresTitle; 
        } 
        break; 
        case 1: { _title = 'Leagues'; } 
        break;
        case 2: { _title = 'Around You'; } 
        break;
      } 
    });
  }
}

