
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/attendee.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens either a legacy event (by Events-list [index]) or an EventsV2
/// event (by [v2Id]). Exactly one must be provided.
class EventPage extends StatefulWidget {
  const EventPage({super.key, this.index, this.v2Id})
      : assert(index != null || v2Id != null);

  final int? index;
  final String? v2Id;

  @override
  _EventPageState createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  bool attending = false;
  late Event event;

  Future<Map<String, MyUser>> fetchEvent() async {
    if (widget.v2Id != null) {
      event = await getEventV2(widget.v2Id!) ?? Event();
    } else {
      event = await getEvent(widget.index!);
    }
    return await getAllUsers();
  }

  /// Attendees live under the record the page was opened from.
  String get _attendeesPath => widget.v2Id != null
      ? "EventsV2/${widget.v2Id}/Attendees/"
      : "Events/${widget.index}/Attendees/";

  Future<void> share_Clicked() async {
    final result = await Share.share((event.title ?? "") + ' is on ' + (event.date ?? "") + ". Download the Infinite Sports app for more info!", subject: "Share Event");

    if (result.status == ShareResultStatus.success) {

    }
  }

  /// Opens the external app for a contact/social action.
  Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Social fields may be pasted as full links or bare handles.
  String _socialUrl(String value, String host) {
    final v = value.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return 'https://$host/${v.replaceFirst('@', '')}';
  }

  /// Same routing the registrations hub uses: status page if this user
  /// already submitted, otherwise the registration flow. Falls back to a
  /// snackbar when the linked registration has closed.
  Future<void> _register() async {
    final regId = event.registrationId!;
    Map<String, RegistrationConfig> open = {};
    try {
      open = await RegistrationService.getOpenRegistrations();
    } catch (_) {}
    if (!mounted) return;
    final config = open[regId];
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration is closed')));
      return;
    }
    final existing = await RegistrationService.getMySubmission(regId);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return existing != null
          ? RegistrationStatusPage(regId: regId, config: config)
          : RegistrationPathPage(regId: regId, config: config);
    }));
  }

  /// Round icon buttons for phone/social contact, only for filled fields.
  Widget _contactRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = event.contactPhone?.trim() ?? '';
    final actions = <(IconData, String, VoidCallback)>[
      if (phone.isNotEmpty) (Icons.call, 'Call', () => _launch('tel:$phone')),
      if (phone.isNotEmpty) (Icons.sms, 'Text', () => _launch('sms:$phone')),
      if (event.instagram?.trim().isNotEmpty ?? false)
        (Icons.camera_alt, 'Instagram', () => _launch(_socialUrl(event.instagram!, 'instagram.com'))),
      if (event.facebook?.trim().isNotEmpty ?? false)
        (Icons.facebook, 'Facebook', () => _launch(_socialUrl(event.facebook!, 'facebook.com'))),
      if (event.youtube?.trim().isNotEmpty ?? false)
        (Icons.play_circle_fill, 'YouTube', () => _launch(_socialUrl(event.youtube!, 'youtube.com'))),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 18,
        alignment: WrapAlignment.center,
        children: [
          for (final (icon, label, onTap) in actions)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ink(
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: scheme.primary,
                  ),
                  child: IconButton(
                    icon: Icon(icon),
                    color: scheme.onPrimary,
                    onPressed: onTap,
                    tooltip: label,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> attend_Clicked() async {
    try {
      DatabaseReference newClient = FirebaseDatabase.instance.ref(_attendeesPath);
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        Map<String, MyUser> users = snapshot.data!;
        List<Attendee> attendees = List.empty(growable: true);
        event.attendees?.forEach((uid, val) {
          String name = '${users[uid]?.firstName ?? ""} ${users[uid]?.lastName ?? ""}';
          attendees.add(Attendee(name, Image.network(users[uid]!.profileURL!, errorBuilder:(context, error, stackTrace) => Image.asset("assets/portraitplaceholder.png"))));
          if (signedIn && uid == FirebaseAuth.instance.currentUser!.uid) {
            attending = true;
          }
        });
        return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              backgroundColor: appBarBackground(context),
              foregroundColor: appBarForeground(context),
              title: Text(event.title ?? "", style: const TextStyle(fontSize: 16),),
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  event.imageSrc ?? SizedBox(width: 0, height: 0),
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
                  if (event.registrationId?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.how_to_reg),
                          label: const Text('Register',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _register,
                        ),
                      ),
                    ),
                  _contactRow(context),
                  if (event.category != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(
                        label: Text(event.category!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontWeight: FontWeight.bold)),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(event.info ?? ""),
                  ),
                  if (event.details?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                      child: Text(event.details!),
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
        );
      }
    );
  }
}
