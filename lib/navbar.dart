import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/signup.dart';


class NavBar extends StatefulWidget {
  const NavBar({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".


  @override
  State<NavBar> createState() => _NavBarState();
}
class _NavBarState extends State<NavBar> {
  String nextleague = "";
  String season = "";
  bool signUpEnabled = false;
  String signUpDetail = "";

  Future<void> setUp() async {
    var status  = await getSignUpStatus();
    switch (status) {
      case 0:
        signUpDetail = "Sign Ups Closed";
        signUpEnabled = false;
        break;
      case 1:
        nextleague = "Futsal";
        season = (int.parse(await getSeason(nextleague)) + 1).toString();
        signUpDetail = "Sign Up for Futsal Season " + season;
        signUpEnabled = true;
        break;
      case 2:
        nextleague = "Basketball";
        season = (int.parse(await getSeason(nextleague)) + 1).toString();
        signUpDetail = "Sign Up for Basketball Season " + season;
        signUpEnabled = true;
        break;
      default:
        signUpDetail = "Sign Ups Closed";
        signUpEnabled = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: setUp(), 
      builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              )
            );
        }
        return Drawer(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: ListView(
            children: [
              const ListTile(
                leading: ImageIcon(AssetImage("assets/playerstats.png"), color: Colors.white,),
                title: Text("Stats", style: TextStyle(fontWeight: FontWeight.bold),),
                textColor: Colors.white,
              ),
              ListTile(
                enabled: signUpEnabled,
                leading: ImageIcon(AssetImage("assets/events.png"), color: Colors.white,),
                title: Text("Sign Up List", style: TextStyle(fontWeight: FontWeight.bold),),
                subtitle: Text(signUpDetail),
                textColor: Colors.white,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Signup(nextleague: nextleague, season: season);
                  },));
                },
              ),
              const ListTile(
                leading: ImageIcon(AssetImage("assets/notifnew.png"), color: Colors.white,),
                title: Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold),),
                textColor: Colors.white,
              ),
              const ListTile(
                leading: ImageIcon(AssetImage("assets/settings.png"), color: Colors.white,),
                title: Text("Settings", style: TextStyle(fontWeight: FontWeight.bold),),
                textColor: Colors.white,
              ),
              ListTile(
                title: const Center(child: Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold),)),
                textColor: Colors.white,
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginPage()))
              ),
            ],
          ),
        );
      }
    );
  }
}