
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/attendee.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key, required this.index});

  final int index;

  @override
  _EventPageState createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  bool attending = false;
  late Event event;

  Future<Map<String, MyUser>> fetchEvent() async {
    event = await getEvent(widget.index);
    return await getAllUsers();
  }

  Future<void> share_Clicked() async {
    final result = await Share.share((event.title ?? "") + ' is on ' + (event.date ?? "") + ". Download the Infinite Sports app for more info!", subject: "Share Event");

    if (result.status == ShareResultStatus.success) {

    }
  }

  Future<void> attend_Clicked() async {
    try {
      DatabaseReference newClient = FirebaseDatabase.instance.ref("Events/${widget.index}/Attendees/");
      if (!attending)
      {
          if (signedIn && FirebaseAuth.instance.currentUser!.photoURL != null)
          {
            await newClient.child(FirebaseAuth.instance.currentUser!.uid).set(FirebaseAuth.instance.currentUser!.photoURL);
          }
          else
          {
            await newClient.child(FirebaseAuth.instance.currentUser!.uid).set(1);
          }
          attending = true;
      }
      else
      {
          await newClient.child(FirebaseAuth.instance.currentUser!.uid).remove();
          attending = false;
      }
    }
    catch (e)
    {
    }

  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: fetchEvent(), 
      builder: (context, snapshot) {
        if(snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: const Center(child: CircularProgressIndicator(),),
          );
        }
        Map<String, MyUser> users = snapshot.data!;
        List<Attendee> attendees = List.empty(growable: true);
        event.attendees?.forEach((uid, val) {
          String name = '${users[uid]?.firstName ?? ""} ${users[uid]?.lastName ?? ""}';
          attendees.add(Attendee(name, (users[uid]!.profileURL != null) ? Image.network(users[uid]!.profileURL!) : Image.asset("assets/portraitplaceholder.png")));
          if (signedIn && uid == FirebaseAuth.instance.currentUser!.uid) {
            attending = true;
          }
        });
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.5,
          child: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              title: Text(event.title ?? "", style: const TextStyle(fontSize: 16),),
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  event.imageSrc ?? const Text(""),
                  Visibility(
                    visible: event.address?.isNotEmpty ?? false,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),),
                      child: Text(event.address!),
                      onPressed: () async {
                        String appleUrl = 'https://maps.apple.com/?saddr=&daddr=${event.address}&directionsmode=driving';
                        String googleUrl = 'https://www.google.com/maps/search/?api=1&query=${event.address}';

                        if (Platform.isIOS) {
                          if (await canLaunch(appleUrl)) {
                            await launch(appleUrl);
                          } else {
                            if (await canLaunch(googleUrl)) {
                              await launch(googleUrl);
                            } else {
                              throw 'Could not open the map.';
                            }
                          }
                        } else {
                          if (await canLaunch(googleUrl)) {
                            await launch(googleUrl);
                          } else {
                            throw 'Could not open the map.';
                          }
                        }
                      },
                    )
                  ),
                  Row(
                    children: [
                      Expanded(
                        child:ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                            ),),
                          onPressed: () async {
                            await attend_Clicked();
                            setState(() {
                            });
                          }, 
                          child: Text(attending ? "Remove" : "Attend")
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                            ),),
                          onPressed: () async {
                            await share_Clicked();
                            setState(() {
                            });
                          },
                          child: const Text("Share")
                        ),
                      ),
                  ],),
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(event.info ?? ""),
                  ),
                  Column(
                    children: [
                      Text(attendees.isNotEmpty ? "Attendees" : "", style: Theme.of(context).textTheme.headlineMedium,),
                      ListView.builder(
                        shrinkWrap: true,
                          itemCount: attendees.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              leading: CircleAvatar(backgroundImage: attendees[index].img?.image ?? const AssetImage("assets/portraitplaceholder.png"),),
                              title: Text(attendees[index].name ?? ""),
                            );
                          },
                      ),
                    ],
                  )
                ],
              )
            ),   
          ),
        );
      }
    );
  }
}
