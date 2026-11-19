import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:infinite_sports_flutter/account/delete_account_flow.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/misc/follow_store.dart';
import 'package:infinite_sports_flutter/misc/categories.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/support/support_form_page.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:webview_flutter/webview_flutter.dart';


class Settings extends StatefulWidget {
  const Settings({super.key});
  //final TitleCallback onTitleSelect;

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final FollowStore _followStore = FollowStore();
  final NotificationPrefs _notifPrefs = NotificationPrefs();
  List<FollowedChannel> _follows = [];
  bool _masterEnabled = true;
  Set<String> _categoriesOn = {};
  List<String> _allCategories = kDefaultCategories;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final follows = await _followStore.follows();
    final master = await _followStore.masterEnabled();
    final allCategories = await getCategories();
    final categories = <String>{};
    for (final c in allCategories) {
      if (await _notifPrefs.isCategoryOn(c)) categories.add(c);
    }
    if (!mounted) return;
    setState(() {
      _allCategories = allCategories;
      // 'sport' follows are shown as the category toggles below; 'event'
      // reminders are managed on each event page. Keep both out of the
      // generic team/tournament/league follows list.
      _follows =
          follows.where((c) => c.kind != 'sport' && c.kind != 'event').toList();
      _masterEnabled = master;
      _categoriesOn = categories;
    });
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
        title: const Text("Settings"),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: Padding(padding: const EdgeInsetsDirectional.all(10.0),
      child: CustomScrollView(slivers: [
        SliverVisibility(
          visible: signedIn,
          sliver: SliverStickyHeader(
            header: const Text("Profile"),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  const Divider(color: Colors.grey),
                  ListTile(title: const Text("Change Password"), minTileHeight: 40, onTap: () async {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return FutureBuilder(
                          future: FirebaseAuth.instance.sendPasswordResetEmail(email: FirebaseAuth.instance.currentUser!.email!),
                          builder: (context, snapshot) {
                            if(snapshot.connectionState == ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              );
                            }
                            return AlertDialog(
                              title: Text("Success! Reset Email Sent to\n${FirebaseAuth.instance.currentUser!.email!}", style: const TextStyle(fontSize: 16),),
                              actions: [TextButton(child: const Text("OK"), onPressed: () {
                                  Navigator.pop(context);
                              },)],
                            );
                          },
                        );
                      }
                    );
                  },),
                  const Divider(color: Colors.grey),
                ]
              ),
            ), 
          ),
        ),
        SliverStickyHeader(
          header: const Text("Notifications"),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const Divider(color: Colors.grey),
                ListTile(
                  title: const Text("All notifications"),
                  minTileHeight: 40,
                  trailing: Switch(
                    value: _masterEnabled,
                    onChanged: (value) async {
                      await _followStore.setMasterEnabled(value);
                      if (!mounted) return;
                      setState(() => _masterEnabled = value);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('Sports & events you follow',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ),
                for (final category in _allCategories)
                  ListTile(
                    minTileHeight: 40,
                    title: Text(category),
                    trailing: Switch(
                      value: _categoriesOn.contains(category),
                      onChanged: (value) async {
                        await _notifPrefs.setCategory(category, value,
                            uid: FirebaseAuth.instance.currentUser?.uid);
                        setState(() {
                          if (value) {
                            _categoriesOn.add(category);
                          } else {
                            _categoriesOn.remove(category);
                          }
                        });
                      },
                    ),
                  ),
                const Divider(color: Colors.grey),
                if (_follows.isEmpty)
                  const ListTile(
                    minTileHeight: 40,
                    title: Text(
                      "Turn on the bell on any tournament, league or team page to follow it here.",
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  )
                else
                  for (final channel in _follows)
                    ListTile(
                      minTileHeight: 40,
                      title: Text(channel.label),
                      subtitle: Text(
                        // 'tournament' and 'league' (P3.3 season bell) both
                        // mean every match; only 'team' is a single team.
                        channel.kind == 'team' ? 'Team' : 'All matches',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: 'Stop alerts',
                        icon: const Icon(Icons.notifications_active),
                        onPressed: () async {
                          await _followStore.unfollow(channel.topic);
                          await _loadNotificationSettings();
                        },
                      ),
                    ),
                const Divider(color: Colors.grey),
              ],
            ),
          ),
        ),
        SliverStickyHeader(
          header: const Text("League Table Info"),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Futsal"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Futsal"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: ListView(
                        children: [
                          Text("Game Activity Legend", style: Theme.of(context).textTheme.headlineSmall,),
                          ListTile(leading: Image.asset("assets/goal.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Goal"),),
                          ListTile(leading: Image.asset("assets/assist.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Assist"),),
                          ListTile(leading: Image.asset("assets/blue.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Blue Card"),),
                          ListTile(leading: Image.asset("assets/yellow.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Yellow Card"),),
                          ListTile(leading: Image.asset("assets/red.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Red Card"),),
                          ListTile(leading: Image.asset("assets/foul.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Foul"),),
                          Text("League Table Legend", style: Theme.of(context).textTheme.headlineSmall),
                          ListTile(leading: Text("GP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Games Played"),),
                          ListTile(leading: Text("L", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Losses"),),
                          ListTile(leading: Text("D", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Draws"),),
                          ListTile(leading: Text("W", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Wins"),),
                          ListTile(leading: Text("P", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Points"),),
                          ListTile(leading: Text("GD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Goal Differential"),),
                          Text("Leaderboard Table Legend", style: Theme.of(context).textTheme.headlineSmall),
                          ListTile(leading: Text("G", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Goals"),),
                          ListTile(leading: Text("A", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Assists"),),
                          ListTile(leading: Text("S", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Saves"),),
                        ],
                      ),
                    );
                  },)); 
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Basketball"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Basketball"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: ListView(
                        children: [
                          Text("Game Activity Legend", style: Theme.of(context).textTheme.headlineSmall,),
                          ListTile(leading: Image.asset("assets/onepointer.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("One Point"),),
                          ListTile(leading: Image.asset("assets/twopointer.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Two Points"),),
                          ListTile(leading: Image.asset("assets/threepointer.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Three Points"),),
                          ListTile(leading: Image.asset("assets/rebound.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Rebound"),),
                          ListTile(leading: Image.asset("assets/foul.png", width: windowsDefaultIconSize.toDouble(),), title: const Text("Foul"),),
                          Text("League Table Legend", style: Theme.of(context).textTheme.headlineSmall),
                          ListTile(leading: Text("GP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Games Played"),),
                          ListTile(leading: Text("L", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Losses"),),
                          ListTile(leading: Text("W", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Wins"),),
                          ListTile(leading: Text("Pct", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Win Percentage"),),
                          ListTile(leading: Text("APD", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Avg. Point Differential"),),
                          Text("Leaderboard Table Legend", style: Theme.of(context).textTheme.headlineSmall),
                          ListTile(leading: Text("PTS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Points"),),
                          ListTile(leading: Text("REB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Rebounds"),),
                          ListTile(leading: Text("FG%", style: TextStyle(fontWeight: FontWeight.bold, fontSize: windowsDefaultIconSize.toDouble()/1.5),), title: const Text("Field Goal Percentage"),),
                        ],
                      ),
                    );
                  },)); 
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Tournaments"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Tournaments"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: _buildIconLegend(context)
                    );
                  },)); 
                },),
              ]
            ),
          ), 
        ),
        SliverStickyHeader(
          header: const Text("General Info"),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const Divider(color: Colors.grey),
                ListTile(title: const Text("About Infinite Sports Association"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("About Infinite Sports Association", style: TextStyle(fontSize: 16),),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: Column(children: [
                        Image.asset('assets/infinite_mark.png', height: 120),
                        const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(15), child: Text("Infinite Sports Association is a San Jose-based non-profit Assyrian organization that runs Soccer, Basketball and Volleyball leagues, games, and tournaments for the Assyrian community")))],)
                    );
                  },)); 
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("About NinevehWare"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("About NinevehWare"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: Column(children: [
                        Image.asset("assets/ninevehware.png"),
                        const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(15), child: Text("NinevehWare is a San Jose-based Software Development brand by Bronsin Benyamin that specializes in Mobile App Development."),))],)
                    );
                  },)); 
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Terms of Use"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://infinite-sports-app.web.app/terms"));
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Terms of Use"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: WebViewStack(controller: controller,)
                    );
                  },));  
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Privacy Policy"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://infinite-sports-app.web.app/privacy"));
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Privacy Policy"),
                        backgroundColor: TournamentColors.headerBackground(context),
                        foregroundColor: TournamentColors.headerForeground(context),
                      ),
                      body: WebViewStack(controller: controller,)
                    );
                  },));             
                },),
                const Divider(color: Colors.grey),
              ]
            ),
          ), 
        ),
        SliverStickyHeader(
          header: const Text("Contact Info"),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                const Divider(color: Colors.grey),
                ListTile(
                  title: const Text("Help & Feedback"),
                  subtitle: const Text("Questions, ideas, bugs — send us a ticket"),
                  minTileHeight: 40,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) {
                      return const SupportFormPage(fromScreen: 'Settings');
                    }));
                  },
                ),
                const Divider(color: Colors.grey),
                const ListTile(title: Text("Infinite Sports Association"), subtitle: Text("Email: InfiniteSportsAssociation@gmail.com\nIG/FB: Infinite Sports Association") , minTileHeight: 40),
                const Divider(color: Colors.grey),
                const ListTile(title: Text("NinevehWare"), subtitle: Text("Email: NinevehWare@gmail.com\nIG/FB: NinevehWare"), minTileHeight: 40),
                const Divider(color: Colors.grey),
              ]
            ),
          ), 
        ),
        SliverList(
          delegate: SliverChildListDelegate(
            [
              const ListTile(title: Text("Infinite Sports App\nRewritten by Pauldin Bebla"),)
            ]
          )
        ),
        SliverVisibility(
          visible: signedIn,
          sliver: SliverList(
          delegate: SliverChildListDelegate(
            [
              const Divider(color: Colors.grey),
              ListTile(title: Text("Delete Account", style: TextStyle(color: Theme.of(context).colorScheme.error,)), minTileHeight: 40, onTap: () {
                // Account deletion (design D3): the page explains what goes,
                // re-signs the person in and asks the server to delete.
                Navigator.push(context, MaterialPageRoute(builder: (_) => buildDeleteAccountPage(context)));
              },),
              const Divider(color: Colors.grey),
            ]
          ),
        )
        ),
        // Keep the last row (Delete Account) scrollable clear of the bottom
        // of the screen (PR #12 review).
        SliverPadding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom),
        ),
    ],),)
    );
  }

    Widget _buildIconLegend(BuildContext context) {
    // [eventType, label] for all 13 icons, in approved order.
    const items = <List<String>>[
      ['goal', 'Goal'],
      ['own goal', 'Own goal'],
      ['penalty goal', 'Goal by penalty'],
      ['penalty missed', 'Missed penalty'],
      ['penalty saved', 'Saved penalty'],
      ['save', 'Save (goalkeeper)'],
      ['assist', 'Assist'],
      ['substitution', 'Substitution'],
      ['yellow card', 'Yellow card'],
      ['red card', 'Red card'],
      ['second yellow', 'Second yellow (= red)'],
      ['foul', 'Foul'],
      ['dpl', 'DPL — Defensive Play (Tackle, Steal, Block)'],
    ];

    Widget cell(List<String> item, {required bool rightColumn}) {
      return Padding(
        // Right column is nudged toward the middle, away from the left line.
        padding: EdgeInsets.only(left: rightColumn ? 14 : 0, bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StatIcon(asset: statIconAsset(item[0]), size: 30),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item[1],
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
          ],
        ),
      );
    }

    // Two columns running downward: pair items (left, right). A trailing odd
    // item occupies the left column only.
    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cell(items[i], rightColumn: false)),
          Expanded(
            child: (i + 1 < items.length)
                ? cell(items[i + 1], rightColumn: true)
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'What the icons mean',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(children: rows),
        ),
      ],
    );
  }
  
}
