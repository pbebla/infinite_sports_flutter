
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
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
  String? profileImagePath;
  Future<void>? _loadProfilePic;
  Future<void>? _getSignUpStatus;

  @override
  void initState() {
    super.initState();
    _loadProfilePic = retrieveProfilePic();
    _getSignUpStatus = setUp();
  }

  Future<void> retrieveProfilePic() async {
    DatabaseReference newClient = FirebaseDatabase.instance.ref();
    if (signedIn) {
      var event = await newClient.child("Users/${FirebaseAuth.instance.currentUser?.uid}").get();
      var player = event.value as Map;
      profileImagePath = player["ProfileUrl"] ?? "";
    }
  }

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
      case 3:
        signUpDetail = "Sign Ups Open";
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
    return NavigationDrawer(
      backgroundColor: Theme.of(context).brightness == Brightness.light ? Theme.of(context).colorScheme.primary : Theme.of(context).navigationDrawerTheme.backgroundColor,
      children: [
        Visibility(
            visible: signedIn,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    var actions = <CupertinoActionSheetAction>[
                      CupertinoActionSheetAction(
                        isDefaultAction: true,
                        onPressed: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                          if (file != null) {
                            await setImage(FirebaseAuth.instance.currentUser!, FileImage(File(file.path)));
                          }
                          Navigator.pop(context);
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
                          Navigator.pop(context);
                          setState(() {
                          });
                        },
                        child: const Text('Camera'),
                      ),
                    ];
                    if (FirebaseAuth.instance.currentUser?.photoURL?.isNotEmpty ?? false) {
                      actions.add(
                        CupertinoActionSheetAction(
                          isDestructiveAction: true,
                          onPressed: () async {
                            showAdaptiveDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog.adaptive(
                                  title: Text("Are you sure you want to remove your current profile picture?"),
                                  actions: [
                                    TextButton(
                                      child: const Text("Yes"),
                                      onPressed: () async {
                                        await removeImage(FirebaseAuth.instance.currentUser!);
                                        Navigator.pop(context);
                                        Navigator.pop(context);
                                        setState(() {});
                                      },
                                    ),
                                    TextButton(
                                      child: const Text("No"),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Navigator.pop(context);
                                        setState(() {});
                                      },
                                    )
                                  ],
                                );
                              }
                            );
                          },
                          child: const Text('Remove'),
                        ),
                      );
                    }
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
                        actions: actions
                      ));
                  },
                  child: FutureBuilder(
                    future: _loadProfilePic, 
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                            child: CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          );
                      }
                      if (signedIn) {
                        if (FirebaseAuth.instance.currentUser?.photoURL?.isNotEmpty ?? false) {
                          return CircleAvatar(backgroundImage: NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!), radius: 50);
                        } else if (profileImagePath?.isNotEmpty ?? false) {
                          return CircleAvatar(backgroundImage: NetworkImage(profileImagePath!), radius: 50);
                        }
                      }
                      return const CircleAvatar(backgroundImage: AssetImage("assets/portraitplaceholder.png"), radius: 50);
                    }
                  )
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
                return PlayerPage(uid: FirebaseAuth.instance.currentUser!.uid,);
              },));
            },
          ),),
          FutureBuilder(
            future: _getSignUpStatus, 
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
      ]
    );
  }
}