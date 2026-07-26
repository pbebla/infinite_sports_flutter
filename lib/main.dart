import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:infinite_sports_flutter/calendar_tab.dart';
import 'package:infinite_sports_flutter/misc/auth_gate.dart';
import 'package:infinite_sports_flutter/misc/goal_toast.dart';
import 'package:infinite_sports_flutter/misc/notification_router.dart';
import 'package:infinite_sports_flutter/misc/pushnotifications.dart';
import 'package:infinite_sports_flutter/misc/server_time.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/onboarding/about_you_page.dart';
import 'package:infinite_sports_flutter/onboarding/favorite_sports_page.dart';
import 'package:infinite_sports_flutter/onboarding/google_profile.dart';
import 'package:infinite_sports_flutter/onboarding/profile_completion.dart';
import 'package:infinite_sports_flutter/onboarding/welcome_page.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/navigations/current_livescore_navigation.dart';
import 'package:infinite_sports_flutter/navigations/leagues_navigation.dart';
import 'package:infinite_sports_flutter/navigations/tournaments_navigation.dart';
import 'package:infinite_sports_flutter/search_hub_page.dart';
import 'package:infinite_sports_flutter/widgets/glass_nav_bar.dart';
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
  // Start listening to Firebase server-time offset so live match clocks
  // stay accurate even when the device clock differs from server time.
  initServerTimeOffset();
  // Cache RTDB on disk so tournament pages render instantly from the last
  // known data, then stream fresh updates. Must run before any DB access.
  FirebaseDatabase.instance.setPersistenceEnabled(true);
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
    final ctx = mainContext;
    // Foreground goal in a followed match → slim in-app toast instead of a
    // heads-up notification; tap opens the match.
    if (message.data['type'] == 'goal' && ctx != null) {
      GoalToast.show(
        context: ctx,
        title: message.notification?.title ?? 'GOAL!',
        body: message.notification?.body ?? '',
        onTap: () =>
            openMatchFromNotification(Map<String, dynamic>.from(message.data)),
      );
      return;
    }
    if (message.notification != null) {
      PushNotifications.showSimpleNotification(
          title: message.notification!.title!,
          body: message.notification!.body!,
          payload: payloadData);
    }
  });
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    openMatchFromNotification(message.data);
  });
  pendingLaunchMessage = await FirebaseMessaging.instance.getInitialMessage();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  darkModeEnabled = prefs.getBool('darkMode') ?? false;
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
      home: const AuthGate(),
    );
  }
}

/// Hard login wall (owner decision, auth-wall spec): a signed-out user only
/// ever sees [WelcomePage] — nothing else in the app is reachable. Signed-in
/// users go straight to [MyHomePage]. Logout signs out of Firebase, which
/// flips `authStateChanges()` back to `null`, and this rebuilds to the wall
/// instantly — no manual navigation needed anywhere else in the app.
///
/// Auto sign-in is now the ONLY behavior: a persisted Firebase session (from
/// a previous login) goes straight into the app on launch. There is no
/// "sign out on launch" path anymore and no user-facing toggle for it.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Brief — matches the native splash colors so there's no flash
          // between splash, this frame, and the real content.
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          );
        }
        final user = snapshot.data;
        signedIn = user != null;
        return chooseRootWidget(
          user: user,
          signedInHome: () => const MyHomePage(),
          signedOutHome: () =>
              WelcomePage(onGoogle: () => _handleGoogleSignIn(context)),
        );
      },
    );
  }
}

/// Real "Sign up with Google" flow behind [WelcomePage]'s `onGoogle` seam
/// (auth-wall C2). Deliberately does NOT navigate anywhere itself: signing
/// in flips `FirebaseAuth.instance.authStateChanges()`, which [AuthGate]
/// above is already listening to, so it rebuilds straight to [MyHomePage]
/// on its own. From there the existing [_MyHomePageState._setupNotificationPrefs]
/// gate (B2) takes over — same single mechanism for brand-new Google users,
/// returning Google users, and pre-existing accounts alike:
/// - New Google user: no `Users/<uid>` node/`ProfileCompleted` yet →
///   `profileCompleted` is false → the gate shows [AboutYouPage]. This
///   function writes the base profile (name + join date) first so that page
///   isn't starting from a completely empty account, but even if this write
///   hasn't landed yet by the time the gate reads the node, the result is
///   the same (About You still shows) because none of the About You fields
///   live in this write.
/// - Returning Google user: `ProfileCompleted` already true → gate no-ops,
///   straight to the home tabs.
///
/// [context] is [AuthGate]'s own `StreamBuilder` builder context, which
/// stays mounted for the app's lifetime (it's the `MaterialApp.home`) even
/// as its *child* swaps between [WelcomePage] and [MyHomePage] — but the
/// `context.mounted` guard is kept anyway since this runs after two awaited
/// hops (sign-in, then a DB read).
Future<void> _handleGoogleSignIn(BuildContext context) async {
  final credential = await auth.signInWithGoogle();
  if (credential == null) {
    // Either the user backed out of the account picker, or the sign-in
    // genuinely failed — either way there's nothing to recover from here
    // except telling them to try again.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google sign-in cancelled or failed.')),
      );
    }
    return;
  }
  final user = credential.user;
  if (user == null) return;

  var usersNodeExists = false;
  try {
    final snap = await FirebaseDatabase.instance.ref('Users/${user.uid}').get();
    usersNodeExists = snap.exists;
  } catch (_) {
    // Network hiccup reading the node: fall through with usersNodeExists
    // false, which only means the (harmless, .update()-based) base-profile
    // write below might redundantly re-run for an existing user — never a
    // reason to block sign-in.
  }

  final isNewUser = isNewSignInUser(
    isNewUserFlag: credential.additionalUserInfo?.isNewUser == true,
    usersNodeExists: usersNodeExists,
  );

  if (isNewUser) {
    final name = splitDisplayName(user.displayName);
    try {
      // `.update()` — never `.set()` — so this can never clobber sibling
      // fields (About You's answers, the FCM token below) regardless of
      // write order.
      await FirebaseDatabase.instance.ref('Users/${user.uid}').update({
        'First Name': name.first,
        'Last Name': name.last,
        'Date Joined': DateTime.now().toString(),
      });
    } catch (_) {}
  }

  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await uploadToken(user, token);
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
  // Track whether the Tournaments tab has ever been opened. Until it has,
  // we keep TournamentsNavigation un-instantiated so getAllTournaments()
  // doesn't fire at app launch for users who never visit Tournaments.
  bool _tournamentsTabBuilt = false;
  String _title = "";
  String _liveScoresTitle = "Matches";
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = pendingLaunchMessage;
      if (message != null) {
        pendingLaunchMessage = null;
        openMatchFromNotification(message.data);
      }
      _setupNotificationPrefs();
    });
    super.initState();
  }

  /// Every install joins the app-wide channel (for "Everyone" campaigns).
  /// Signed-in users then go through, in order: (1) the one-time MANDATORY
  /// "complete your profile" gate for accounts missing the About You fields
  /// (pre-existing accounts, or anything created before this step existed),
  /// then (2) the one-time favorites prompt for anyone who never picked any.
  /// Both are gated so they run at most once per launch (this method itself
  /// only ever runs once, from the post-frame callback in [initState]).
  Future<void> _setupNotificationPrefs() async {
    final prefs = NotificationPrefs();
    await prefs.subscribeAllUsers();
    final user = FirebaseAuth.instance.currentUser;
    if (!signedIn || user == null) return;
    await _showAboutYouIfIncomplete(user.uid);
    if (await prefs.hasAnswered(user.uid)) return;
    final answered = await prefs.serverFavorites(user.uid);
    if (answered != null) return; // already has favorites recorded
    final ctx = mainContext;
    if (ctx != null && mounted) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const FavoriteSportsPage()));
    }
  }

  /// One-time MANDATORY "Complete your profile" gate (owner decision, no
  /// skip) for any signed-in account whose `Users/<uid>` node is missing the
  /// About You fields — pre-existing accounts created before this step
  /// existed, AND brand-new Google/Apple sign-ups (whose base profile write
  /// never sets `ProfileCompleted`). Brand-new EMAIL signups already write
  /// `ProfileCompleted: true` during Step 2 of 3 (see createaccountpage.dart),
  /// so `profileCompleted` is already true for them and this never re-prompts.
  ///
  /// `askPhone` is decided dynamically from the same node read: email
  /// signups always collected a phone in Step 1, but Google/Apple never
  /// collect one at credential sign-in time, so this asks for it here
  /// instead whenever `Phone Number` is missing/empty — one shared gate,
  /// no separate Google-specific flow.
  Future<void> _showAboutYouIfIncomplete(String uid) async {
    dynamic usersNode;
    try {
      final snap = await FirebaseDatabase.instance.ref('Users/$uid').get();
      usersNode = snap.value;
    } catch (_) {
      return; // network hiccup: don't block app entry over this check
    }
    if (profileCompleted(usersNode)) return;
    final ctx = mainContext;
    if (ctx == null || !ctx.mounted) return;
    final askPhone = needsPhoneNumber(usersNode);
    // No step labels here (not part of the 3-step signup flow); onDone pops
    // this route back to MyHomePage, then favorites logic runs as today.
    await Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (routeContext) => AboutYouPage(
          askPhone: askPhone,
          onDone: () => Navigator.pop(routeContext),
        ),
      ),
    );
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
    // MyHomePage only ever exists once AuthGate has already confirmed a
    // signed-in Firebase user (auto sign-in is always on now — no more
    // sign-out-on-launch path), so this is just the FCM token upload.
    if (FirebaseAuth.instance.currentUser != null) {
      signedIn = true;
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await uploadToken(FirebaseAuth.instance.currentUser!, token);
      }
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
      // Lazy: don't instantiate TournamentsNavigation (which would trigger
      // getAllTournaments at app launch) until the user actually taps the
      // Tournaments tab.
      _tournamentsTabBuilt
          ? const TournamentsNavigation()
          : const SizedBox.shrink(),
      const CalendarTab(),
    ];
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      drawer: const NavBar(),
      // Let page content scroll underneath the floating glass bar so the
      // frosted blur has something to sample.
      extendBody: true,
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
      bottomNavigationBar: GlassNavBar(
        destinations: const [
          GlassNavDestination(
            icon: ImageIcon(AssetImage('assets/scores.png')),
            label: 'Matches'),
          GlassNavDestination(
            icon: ImageIcon(AssetImage('assets/leagues.png')),
            label: 'Leagues'),
          GlassNavDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Tournaments'),
          GlassNavDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar'),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        onSearchTap: _openSearchHub,
        ) // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _openSearchHub() {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return const SearchHubPage();
    }));
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 2 && !_tournamentsTabBuilt) {
        _tournamentsTabBuilt = true;
      }
      switch(index) { 
        case 0: { 
          _title = _liveScoresTitle; 
        } 
        break; 
        case 1: { _title = 'Leagues'; }
        break;
        case 2: { _title = 'Tournaments'; }
        break;
        case 3: { _title = 'Calendar'; }
        break;
      } 
    });
  }
}

