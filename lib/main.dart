import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/misc/pushnotifications.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/navigations/current_livescore_navigation.dart';
import 'package:infinite_sports_flutter/navigations/leagues_navigation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await PushNotifications.init();
  await PushNotifications.initLocalNotifications();
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
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    if (signedIn) {
      await uploadToken(auth.credential!.user!, newToken);
    }
  });
  runApp(ChangeNotifierProvider(create: (context) => ThemeProvider(), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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
  String currentDate = "";
  bool isCurrentFinished = false;

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
    String? email = await secureStorage.read(key: "Email");
    String? password = await secureStorage.read(key: "Password");
    if (email != null && password != null) {
      User? user = await auth.signInWithEmailAndPassword(email, password);
      if (user != null) {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await uploadToken(user, token);
        }
        auth.password = password;
        autoSignIn = true;
        signedIn = true;
      }
    }
    currentSport = await getCurrentSport();
    currentSeason = await getCurrentSeason(currentSport);
    currentDate = await getCurrentDate(currentSport, currentSeason);
    isCurrentFinished = await isSeasonFinished(currentSport, currentSeason);
    headerNotifier.value = [currentSport, currentSeason];
    await getAllTeamLogo();
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> widgetOptions = <Widget>[
      FutureBuilder(future: setCurrentValues(), builder:(context, snapshot) {
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
        return CurrentLivescoreNavigation(currentSport: currentSport, currentSeason: currentSeason, currentDate: currentDate, onTitleSelect: setLiveScoreTitle, isSeasonFinished: isCurrentFinished,);
      },),
      const LeaguesNavigation(),
    ];
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const NavBar(),
      appBar: GlobalAppBar(title: _title, height: AppBar().preferredSize.height),
      body: IndexedStack(
          index: _selectedIndex,
          children: widgetOptions
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

