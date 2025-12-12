import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_launcher_icons/constants.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  TextEditingController? _emailController;
  String? _emailErrorText;
  
  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _emailErrorText = "";
  }

  @override
  void dispose() {
    _emailController!.dispose();
    super.dispose();
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
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
                  ListTile(title: const Text("Auto Log In"), minTileHeight: 40, trailing: Checkbox(value: autoSignIn, onChanged: (value) async {
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('autoSignIn', value!);
                    setState(() {
                      autoSignIn = value;
                    });
                  },),),
                  const Divider(color: Colors.grey),
                ]
              ),
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      body: Column(children: [
                        Image.asset("assets/infinite.png"),
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
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      body: Column(children: [
                        Image.asset("assets/ninevehware.png"),
                        const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(15), child: Text("NinevehWare is a San Jose-based Software Development brand by Bronsin Benyamin that specializes in Mobile App Development."),))],)
                    );
                  },)); 
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Terms and Conditions"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://docs.google.com/document/d/1EifPlImldFfq4yLMZA5m7brbnwH8mfP8Kxf9UpHaF74/edit?usp=sharing"));
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Terms and Conditions"),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      body: WebViewStack(controller: controller,)
                    );
                  },));  
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("Privacy Poilicy"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    WebViewController controller = WebViewController()..loadRequest(Uri.parse("https://docs.google.com/document/d/1cT9lJEUyvMsFUAfkpNtzHBBqeM3Em3nvK3lONvK-shk/edit?usp=sharing"));
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("Privacy Poilicy"),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      body: WebViewStack(controller: controller,)
                    );
                  },));             
                },),
                const Divider(color: Colors.grey),
                ListTile(title: const Text("End-User License Agreement"), minTileHeight: 40, onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Scaffold(
                      appBar: AppBar(
                        centerTitle: true,
                        title: const Text("End-User License Agreement"),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      body: const SingleChildScrollView(child: Text("End-User License Agreement (EULA) of Infinite Sports App \n \n This End-User License Agreement (\"EULA\") is a legal agreement between you, Infinite Sports Association and NinevehWare \n \n This EULA agreement governs your acquisition and use of our Infinite Sports App software (\"Software\") directly from Infinite Sports Association and NinevehWare or indirectly through a Infinite Sports Association and NinevehWare authorized reseller or distributor (a \"Reseller\"). \n \n Please read this EULA agreement carefully before completing the installation process and using the Infinite Sports App software. It provides a license to use the Infinite Sports App software and contains warranty information and liability disclaimers. \n \n If you register for a free trial of the Infinite Sports App software, this EULA agreement will also govern that trial. By clicking \"accept\" or installing and/or using the Infinite Sports App software, you are confirming your acceptance of the Software and agreeing to become bound by the terms of this EULA agreement. \n \n If you are entering into this EULA agreement on behalf of a company or other legal entity, you represent that you have the authority to bind such entity and its affiliates to these terms and conditions. If you do not have such authority or if you do not agree with the terms and conditions of this EULA agreement, do not install or use the Software, and you must not accept this EULA agreement. \n \n This EULA agreement shall apply only to the Software supplied by Infinite Sports Association and NinevehWare herewith regardless of whether other software is referred to or described herein. The terms also apply to any Infinite Sports Association and NinevehWare updates, supplements, Internet-based services, and support services for the Software, unless other terms accompany those items on delivery. If so, those terms apply. \n \n License Grant \n \n Infinite Sports Association and NinevehWare hereby grants you a personal, non-transferable, non-exclusive licence to use the Infinite Sports App software on your devices in accordance with the terms of this EULA agreement. \n \n You are permitted to load the Infinite Sports App software (for example a PC, laptop, mobile or tablet) under your control. You are responsible for ensuring your device meets the minimum requirements of the Infinite Sports App software. \n \n You are not permitted to: \n \n \n - Edit, alter, modify, adapt, translate or otherwise change the whole or any part of the Software nor permit the whole or any part of the Software to be combined with or become incorporated in any other software, nor decompile, disassemble or reverse engineer the Software or attempt to do any such things \n - Reproduce, copy, distribute, resell or otherwise use the Software for any commercial purpose \n - Allow any third party to use the Software on behalf of or for the benefit of any third party \n - Use the Software in any way which breaches any applicable local, national or international law \n - use the Software for any purpose that Infinite Sports Association and NinevehWare considers is a breach of this EULA agreement \n \n \n Intellectual Property and Ownership \n \n Infinite Sports Association and NinevehWare shall at all times retain ownership of the Software as originally downloaded by you and all subsequent downloads of the Software by you. The Software (and the copyright, and other intellectual property rights of whatever nature in the Software, including any modifications made thereto) are and shall remain the property of Infinite Sports Association and NinevehWare. \n \n Infinite Sports Association and NinevehWare reserves the right to grant licences to use the Software to third parties. \n \n Termination \n \n This EULA agreement is effective from the date you first use the Software and shall continue until terminated. You may terminate it at any time upon written notice to Infinite Sports Association and NinevehWare. \n \n This EULA was created by eulatemplate.com for Infinite Sports App \n \n It will also terminate immediately if you fail to comply with any term of this EULA agreement. Upon such termination, the licenses granted by this EULA agreement will immediately terminate and you agree to stop all access and use of the Software. The provisions that by their nature continue and survive will survive any termination of this EULA agreement. \n \n Governing Law \n \n This EULA agreement, and any dispute arising out of or in connection with this EULA agreement, shall be governed by and construed in accordance with the laws of United States of America."),)
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
              ListTile(title: Text("Delete Account", style: TextStyle(color: Theme.of(context).colorScheme.error,)), minTileHeight: 40, onTap: () async {
                showDialog(
                  context: context, 
                  builder: (context) {
                    return StatefulBuilder(
                      builder: (context, localSetState) {
                        return AlertDialog(
                          title: Text("ALERT!"),
                          content: SizedBox(
                            height: 150,
                            child: Column(
                            children: [
                              Text("Are you sure you want to delete your account? Type your email below before confirming."),
                              Padding(
                                padding: EdgeInsets.fromLTRB(0, 10, 0, 0),
                                child: TextField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    errorText: (_emailErrorText),
                                    labelText: 'Email',
                                    hintText: 'Enter your email'),
                                ),
                              )
                            ],
                          ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              }, 
                              child: const Text("No, Go Back"),
                            ),
                            FilledButton(
                              onPressed: () async {
                                if (_emailController!.text != FirebaseAuth.instance.currentUser!.email) {
                                  _emailErrorText = "Email does not match.";
                                  localSetState(() {});
                                } else {
                                  var user = FirebaseAuth.instance.currentUser!;
                                  await removeImage(user);
                                  await user.delete();
                                  signedIn = false;
                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                  setState(() {},);
                                }
                              }, 
                              child: const Text("Yes, Delete", style: TextStyle(color: Colors.white),),
                            )
                          ],
                        );
                      }
                    );
                  }
                );
              },),
              const Divider(color: Colors.grey),
            ]   
          ),
        )
        )
    ],),)
    );
  }
  
}
