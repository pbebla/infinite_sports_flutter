
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/theme_provider.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/playerpage.dart';
import 'package:infinite_sports_flutter/settings.dart';
import 'package:infinite_sports_flutter/signup.dart';
import 'package:provider/provider.dart';


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
  bool signUpsOpen = false;
  bool signUpEnabled = false;
  String signUpDetail = "";

  Future<void> setUp() async {
    var status  = await getSignUpStatus();
    switch (status) {
      case 0:
        signUpDetail = "Sign Ups Closed";
        signUpsOpen = false;
        break;
      case 1:
        nextleague = "Futsal";
        season = (int.parse(await getSeason(nextleague)) + 1).toString();
        signUpDetail = "Sign Up for Futsal Season $season";
        signUpsOpen = true;
        break;
      case 2:
        nextleague = "Basketball";
        season = (int.parse(await getSeason(nextleague)) + 1).toString();
        signUpDetail = "Sign Up for Basketball Season $season";
        signUpsOpen = true;
        break;
      default:
        signUpDetail = "Sign Ups Closed";
        signUpsOpen = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).brightness == Brightness.light ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
      child: ListView(
        children: [
          Visibility(
            visible: signedIn,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    showCupertinoModalPopup(
                      context: context, 
                      builder: (context) => CupertinoActionSheet(
                        title: const Text('Image from...'),
                        cancelButton: CupertinoActionSheetAction(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('Cancel'),
                          ),
                        actions: <CupertinoActionSheetAction>[
                          CupertinoActionSheetAction(
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                              if (file != null) {
                                await setImage(FirebaseAuth.instance.currentUser!, FileImage(File(file.path)));
                              }
                              setState(() {
                              });
                            },
                            child: const Text('Photos'),
                          ),
                          CupertinoActionSheetAction(
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? file = await picker.pickImage(source: ImageSource.camera);
                              if (file != null) {
                                await setImage(FirebaseAuth.instance.currentUser!, FileImage(File(file.path)));
                              }
                              setState(() {
                              });
                            },
                            child: const Text('Camera'),
                          ),
                        ],
                      ));
                  },
                  child: signedIn && (currentUser?.photoURL?.isNotEmpty ?? false) ? 
                  CircleAvatar(backgroundImage: NetworkImage(currentUser!.photoURL!), radius: 50) : 
                  const CircleAvatar(backgroundImage: AssetImage("assets/portraitplaceholder.png"), radius: 50),
                ),
                Text(FirebaseAuth.instance.currentUser?.displayName ?? "", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: Theme.of(context).textTheme.headlineMedium!.fontSize)),
              ],)),
          Visibility(
            visible: !signedIn,
            child: ListTile(
            leading: const ImageIcon(AssetImage("assets/profile.png"), color: Colors.white,),
            title: const Text("Login or Sign Up", style: TextStyle(fontWeight: FontWeight.bold),),
            textColor: Colors.white,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage())).then((value) => setState(() {
              if (signedIn) {
                Navigator.pop(context);
              }
            })),
          ),),
          Visibility(
            visible: signedIn,
            child: ListTile(
            leading: const ImageIcon(AssetImage("assets/playerstats.png"), color: Colors.white,),
            title: const Text("Stats", style: TextStyle(fontWeight: FontWeight.bold),),
            textColor: Colors.white,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder:(context) {
                return PlayerPage(uid: currentUser!.uid,);
              },));
            },
          ),),
          FutureBuilder(
            future: setUp(), 
            builder: (context, snapshot) {
              if(snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    )
                  );
              }
              signUpEnabled = signUpsOpen && signedIn;
              return ListTile(
                enabled: signUpEnabled,
                leading: const ImageIcon(AssetImage("assets/events.png"), color: Colors.white,),
                title: const Text("Sign Up List", style: TextStyle(fontWeight: FontWeight.bold),),
                subtitle: Text(signUpDetail),
                textColor: Colors.white,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder:(context) {
                    return Signup(nextleague: nextleague, season: season);
                  },));
                },
              );
            } 
          ),
          ListTile(
            leading: const ImageIcon(AssetImage("assets/settings.png"), color: Colors.white,),
            title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold),),
            textColor: Colors.white,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder:(context) {
                return const Settings();
              },));
            },
          ),
          StatefulBuilder(
            builder: (context, setState) {
              return ListTile(
                title: const Text("Dark Theme", style: TextStyle(fontWeight: FontWeight.bold),),
                textColor: Colors.white,
                trailing: Switch(
                  value: darkModeEnabled, 
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (value) {
                  Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
                  setState(() {
                    darkModeEnabled = value;
                  });
                },),
              );
            },
          ),
          Visibility(
            visible: signedIn,
            child: ListTile(
              title: const Center(child: Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold),)),
              textColor: Colors.white,
              onTap: () async {
                showDialog(
                  context: context, 
                  builder: (context) {
                    return AlertDialog(
                      title: const Text("Are you sure you want to logout?"),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            print(FirebaseAuth.instance.currentUser);
                            await auth.signOut();
                            print("Signed out");
                            signedIn = false;
                            setState(() {});
                            Navigator.pop(context);
                          }, 
                          child: const Text("Yes")
                        ),
                        TextButton(
                          onPressed: () {Navigator.pop(context);}, 
                          child: const Text("No")
                        ),
                      ],
                    );
                  }
                );
              }
          ),),
        ],
      ),
    );
  }
}