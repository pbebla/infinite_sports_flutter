import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:infinite_sports_flutter/calendar_tab.dart';
import 'package:infinite_sports_flutter/insiders/insider_dashboard_page.dart';
import 'package:infinite_sports_flutter/misc/auth_gate.dart';
import 'package:infinite_sports_flutter/misc/goal_toast.dart';
import 'package:infinite_sports_flutter/misc/home_nav.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/misc/notification_router.dart';
import 'package:infinite_sports_flutter/misc/pushnotifications.dart';
import 'package:infinite_sports_flutter/misc/server_time.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
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
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
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
  darkModeEnabled = resolveDarkModeDefault(prefs.getBool('darkMode'));
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
          signedOutHome: () => WelcomePage(
            onGoogle: () => _handleGoogleSignIn(context),
            onApple: () => _handleAppleSignIn(context),
          ),
        );
      },
    );
  }
}

/// Real "Sign up with Google" flow behind [WelcomePage]'s `onGoogle` seam
/// (auth-wall C2). Deliberately does NOT rely on
/// [_MyHomePageState._setupNotificationPrefs] for new users anymore
/// (auth-wall F2 fix): signing in flips `FirebaseAuth.instance.authStateChanges()`
/// the instant `signInWithGoogle()` resolves, which [AuthGate] rebuilds to
/// [MyHomePage] on — racing this very function's own base-profile write
/// below. That race used to make the gate read `Users/<uid>` too early,
/// decide the profile was incomplete, and push its own stale duplicate
/// About You page (with the wrong dynamic `askPhone`) on top of this
/// function's own steps.
///
/// The fix: set [onboardingFlowActive] BEFORE the base-profile write so the
/// gate sees it and skips itself entirely, then drive About You + favorites
/// EXPLICITLY from here — mirroring the email chain
/// (createaccountpage.dart) — for brand-new users only:
/// - New Google user: no `Users/<uid>` node yet. Writes the base profile
///   (name + join date), then pushes [AboutYouPage] (`askPhone: true` —
///   Google never collects a phone at credential sign-in time) whose
///   `onDone` continues to [FavoriteSportsPage], which clears
///   [onboardingFlowActive] on completion.
/// - Returning Google user: [onboardingFlowActive] is never set, so the
///   main gate runs as usual — `ProfileCompleted` already true → no-ops,
///   straight to the home tabs.
///
/// [context] is [AuthGate]'s own `StreamBuilder` builder context, which
/// stays mounted for the app's lifetime (it's the `MaterialApp.home`) even
/// as its *child* swaps between [WelcomePage] and [MyHomePage] — but the
/// `context.mounted` guard is kept anyway since this runs after several
/// awaited hops (sign-in, a DB read, the profile write, a token fetch).
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
    // Set BEFORE the write below: `authStateChanges()` can flip (and the
    // gate's post-frame callback can fire) at any point from here on.
    onboardingFlowActive = true;
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

  if (isNewUser && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => AboutYouPage(
          askPhone: true,
          stepIndex: 2,
          stepCount: 3,
          onDone: () => Navigator.pushReplacement(
            routeContext,
            MaterialPageRoute(builder: (_) => const FavoriteSportsPage()),
          ),
        ),
      ),
    );
  }
}

/// "Sign in with Apple" flow behind [WelcomePage]'s `onApple` seam
/// (auth-wall D1) — CODE COMPLETE but DORMANT, since [WelcomePage] only ever
/// renders its Apple button on `Platform.isIOS`, and this repo builds/ships
/// Android only today. Kept as a straight mirror of [_handleGoogleSignIn]
/// above (including the auth-wall F2 [onboardingFlowActive] fix and the
/// explicit About You/favorites push for new users) so there's no separate
/// code path to keep in sync:
/// - New Apple user: no `Users/<uid>` node yet. This function writes the
///   base profile first (name, from `user.displayName` — which
///   `signInWithApple` may have just set via
///   `combineAppleName`/`updateDisplayName` when Apple supplied a name on
///   this FIRST authorization; `null`/empty on every subsequent Apple
///   sign-in, same as `splitDisplayName` already handles for Google), then
///   pushes [AboutYouPage] → [FavoriteSportsPage] explicitly.
/// - Returning Apple user: [onboardingFlowActive] is never set, so the main
///   gate runs as usual and no-ops (`ProfileCompleted` already true).
Future<void> _handleAppleSignIn(BuildContext context) async {
  final credential = await auth.signInWithApple();
  if (credential == null) {
    // User backed out of the Face ID/Apple ID sheet, or sign-in genuinely
    // failed — either way there's nothing to recover from here except
    // telling them to try again (same convention as the Google handler).
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple sign-in cancelled or failed.')),
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
    // Set BEFORE the write below: `authStateChanges()` can flip (and the
    // gate's post-frame callback can fire) at any point from here on.
    onboardingFlowActive = true;
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

  if (isNewUser && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => AboutYouPage(
          askPhone: true,
          stepIndex: 2,
          stepCount: 3,
          onDone: () => Navigator.pushReplacement(
            routeContext,
            MaterialPageRoute(builder: (_) => const FavoriteSportsPage()),
          ),
        ),
      ),
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

  // Infinite Insiders (Task F4): the 5th bottom-nav tab appears/disappears
  // live with this stream — see lib/misc/home_nav.dart's navItemsFor.
  // _isActiveInsider mirrors the stream's latest value so _onItemTapped (a
  // user-gesture callback, not a build) can compute the same tab list the
  // nav bar is currently showing.
  late final Stream<Insider?> _insiderStream;
  bool _isActiveInsider = false;

  @override
  void initState() {
    // TODO: implement initState
    setTitle(_liveScoresTitle);
    _fetchCurrentValues = setCurrentValues();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _insiderStream = (uid != null && uid.isNotEmpty)
        ? InsiderService.watchMyInsider(uid)
        : Stream<Insider?>.value(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = pendingLaunchMessage;
      if (message != null) {
        pendingLaunchMessage = null;
        openMatchFromNotification(message.data);
      }
      _setupNotificationPrefs();
    });
    // Task F8: lets a page pushed on top of MyHomePage (e.g.
    // InsidersLeaderboardPage's bottom nav) request a tab switch via the
    // shared requestedHomeTab notifier (lib/misc/utility.dart) instead of
    // inventing its own navigation.
    requestedHomeTab.addListener(_onRequestedHomeTab);
    super.initState();
  }

  @override
  void dispose() {
    requestedHomeTab.removeListener(_onRequestedHomeTab);
    super.dispose();
  }

  /// Consumes a pending [requestedHomeTab] request: switches to that tab
  /// (reusing [_onItemTapped] so lazy Tournaments-tab build + title update
  /// stay identical to a real nav-bar tap) then resets the notifier back to
  /// null so a repeat request of the same tab still fires the listener.
  void _onRequestedHomeTab() {
    final tab = requestedHomeTab.value;
    if (tab == null) return;
    requestedHomeTab.value = null;
    final tabs = navItemsFor(_isActiveInsider);
    final idx = tabs.indexOf(tab);
    if (idx == -1) return;
    _onItemTapped(idx);
  }

  /// Every install joins the app-wide channel (for "Everyone" campaigns).
  /// Signed-in users then go through, in order: (1) the one-time MANDATORY
  /// "complete your profile" gate for accounts missing the About You fields
  /// (pre-existing accounts, or anything created before this step existed),
  /// then (2) the one-time favorites prompt for anyone who never picked any.
  /// Both are gated so they run at most once per launch (this method itself
  /// only ever runs once, from the post-frame callback in [initState]).
  Future<void> _setupNotificationPrefs() async {
    // An active signup flow (email, Google, or Apple) is already driving its
    // own About You + favorites steps and will finish them itself — running
    // this gate at the same time races the flow's own Users/<uid> writes and
    // shows a stale duplicate About You page (auth-wall F2 fix).
    if (shouldSkipOnboardingGate(onboardingFlowActive: onboardingFlowActive)) {
      return;
    }
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
  /// existed. Brand-new EMAIL, Google, and Apple sign-ups all set
  /// [onboardingFlowActive] (see `_handleGoogleSignIn`/`_handleAppleSignIn`
  /// above and `createaccountpage.dart`), which makes the CALLER of this
  /// method (`_setupNotificationPrefs`) skip entirely (auth-wall F2 fix) —
  /// so this only ever actually runs for returning/pre-existing accounts,
  /// for whom `ProfileCompleted` is already true and it no-ops immediately.
  ///
  /// `askPhone` is decided dynamically from the same node read: email
  /// signups always collected a phone in Step 1, but Google/Apple never
  /// collect one at credential sign-in time — not that it matters here
  /// anymore, since Google/Apple new-users never reach this method.
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

  /// The page body for a single tab (Task F4 — extracted out of build() so
  /// the tab list stays index-aligned with [navItemsFor]'s destinations,
  /// whatever length it currently is).
  Widget _pageFor(HomeTab tab) {
    switch (tab) {
      case HomeTab.matches:
        return FutureBuilder(
          future: _fetchCurrentValues,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // Skeleton sweep (F3 Fix 2): matches the match-list shape the
              // Matches tab (frontpage.dart) settles into once loaded.
              return const SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SkeletonMatchList(count: 8),
                ),
              );
            }
            if (isCurrentFinished) {
              return const Center(
                  child: Card(
                      child: Text("No Current Games, Stay Tuned for Next Season!",
                          style: TextStyle(fontWeight: FontWeight.bold))));
            }
            return CurrentLivescoreNavigation(onTitleSelect: setLiveScoreTitle);
          },
        );
      case HomeTab.leagues:
        return const LeaguesNavigation();
      case HomeTab.tournaments:
        // Lazy: don't instantiate TournamentsNavigation (which would trigger
        // getAllTournaments at app launch) until the user actually taps the
        // Tournaments tab.
        return _tournamentsTabBuilt
            ? const TournamentsNavigation()
            : const SizedBox.shrink();
      case HomeTab.calendar:
        return const CalendarTab();
      case HomeTab.insider:
        return const InsiderDashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    mainContext = context;
    // Infinite Insiders (Task F4): the nav tab list is derived live from
    // /Insiders/<uid>'s Status field — it appears the moment approval
    // lands and disappears the moment it doesn't (suspend/decline/etc).
    return StreamBuilder<Insider?>(
      stream: _insiderStream,
      builder: (context, insiderSnap) {
        _isActiveInsider = insiderSnap.data?.isActive == true;
        final tabs = navItemsFor(_isActiveInsider);
        // Safety clamp: if the Insider tab just disappeared (suspended
        // while it was the selected tab, say) and _selectedIndex pointed
        // past the new shorter list, IndexedStack would throw. This runs
        // synchronously within the current (stream-driven) build, so the
        // corrected index is what actually renders this frame — no extra
        // setState/rebuild needed.
        if (_selectedIndex >= tabs.length) {
          _selectedIndex = tabs.length - 1;
        }
        final List<Widget> widgetOptions = [
          for (final tab in tabs) _pageFor(tab),
        ];
        return Scaffold(
          drawer: const NavBar(),
          // Let page content scroll underneath the floating glass bar so the
          // frosted blur has something to sample.
          extendBody: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Builder(
            builder: (context) {
              mainScaffoldContext = context;
              return IndexedStack(index: _selectedIndex, children: widgetOptions);
            },
          ),
          bottomNavigationBar: GlassNavBar(
            destinations: [for (final tab in tabs) destinationFor(tab)],
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            onSearchTap: _openSearchHub,
          ), // This trailing comma makes auto-formatting nicer for build methods.
        );
      },
    );
  }

  void _openSearchHub() {
    Navigator.push(context, MaterialPageRoute(builder: (context) {
      return const SearchHubPage();
    }));
  }

  void _onItemTapped(int index) {
    final tabs = navItemsFor(_isActiveInsider);
    if (index < 0 || index >= tabs.length) return;
    setState(() {
      _selectedIndex = index;
      final tapped = tabs[index];
      if (tapped == HomeTab.tournaments && !_tournamentsTabBuilt) {
        _tournamentsTabBuilt = true;
      }
      _title = titleFor(tapped, _liveScoresTitle);
    });
  }
}

