import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/botnavbar.dart';
import 'package:infinite_sports_flutter/globalappbar.dart';
import 'package:infinite_sports_flutter/leagueform.dart';
import 'package:infinite_sports_flutter/main.dart';
import 'package:infinite_sports_flutter/misc/navigation_controls.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/leaguemenu.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
import 'package:infinite_sports_flutter/navbar.dart';
import 'package:infinite_sports_flutter/showleague.dart';
import 'package:webview_flutter/webview_flutter.dart';

class Signup extends StatefulWidget {
  const Signup({super.key, required this.nextleague, required this.season});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;
  final String nextleague;
  final String season;

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  Future<List<ListTile>> populateMenus() async {
    UserInformation? oldInfo = await getInformation();
    String? phoneNumber = await getPhone();
    List<ListTile> list = List<ListTile>.empty(growable: true);
    ListTile nextSeasonTile = ListTile(title: Text("${widget.nextleague} Season ${widget.season}"), onTap: () {
      Navigator.push(context, MaterialPageRoute(builder:(context) {
        return LeagueForm(sport: widget.nextleague, season: widget.season, oldInfo: oldInfo ?? UserInformation(), phoneNumber: phoneNumber ?? "",);
      },));
    },);
    list.add(nextSeasonTile);

    var signups = await getOtherSignups();
    signups.forEach((k, v) {
      try {
        if (v.containsKey("Sign Up Status") && v["Sign Up Status"] == 1) {
          ListTile tile = ListTile(
            title: Text(v["Name"] ?? ""),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder:(context) {
                WebViewController controller = WebViewController()..loadRequest(Uri.parse(v["Form URL"] != "\"\"" ? v["Form URL"] : "https://google.com"));
                return Scaffold(
                  appBar: AppBar(
                    title: Text(v["Name"]),
                    actions: [
                      NavigationControls(controller: controller)
                    ],
                  ),
                  body: WebViewStack(controller: controller,)
                );
              },));
            },
          );
          list.add(tile);
        }
      } catch (e) {
      }
    });
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
    return FutureBuilder(
      future: populateMenus(), 
      builder:(context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        return Scaffold(
          appBar: AppBar(title: Text("Sign Up List"), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white,),
          body: ListView.separated(
            separatorBuilder: (context, index) => const Divider(
              color: Colors.black,
            ),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) => snapshot.data![index]
            ),
          );
      },
    );
  }
}