
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/misc/event_share.dart';
import 'package:infinite_sports_flutter/misc/notification_prefs.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/attendee.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/model/myuser.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:infinite_sports_flutter/misc/ics.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:path_provider/path_provider.dart';
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
  bool _reminding = false;
  final NotificationPrefs _notifPrefs = NotificationPrefs();
  late Event event;
  // Live record: attend/edit changes appear without reopening the page.
  Stream<Event?>? _eventStream;
  Future<Map<String, MyUser>>? _users;

  @override
  void initState() {
    super.initState();
    _loadReminding();
    _eventStream = watchEvent(v2Id: widget.v2Id, legacyIndex: widget.index);
    _users = getAllUsers();
  }

  /// Attendees live under the record the page was opened from.
  String get _attendeesPath => widget.v2Id != null
      ? "EventsV2/${widget.v2Id}/Attendees/"
      : "Events/${widget.index}/Attendees/";

  /// The message that goes out with a share. Owner's custom caption when set
  /// (from the manager event form), otherwise auto-built from the details.
  /// Always ends with the app call-to-action.
  /// Remind-me only applies to V2 events (they have an id/topic).
  bool get _canRemind => widget.v2Id != null;

  Future<void> _loadReminding() async {
    if (!_canRemind) return;
    final on = await _notifPrefs.isEventReminderOn(widget.v2Id!);
    if (mounted) setState(() => _reminding = on);
  }

  Future<void> _toggleRemind() async {
    if (!_canRemind) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final next = !_reminding;
    await _notifPrefs.setEventReminder(widget.v2Id!, next, uid: uid);
    if (mounted) {
      setState(() => _reminding = next);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next
              ? "You'll be reminded about this event"
              : "Reminders off for this event")));
    }
  }

  /// Downloads the flyer to a temp file so it can be shared as its own clean
  /// image (no overlay), with the message carried as separate text.
  Future<File?> _downloadFlyer(String url) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(response);
      final dir = await getTemporaryDirectory();
      final ext = url.toLowerCase().contains('.png') ? 'png' : 'jpg';
      final file = File('${dir.path}/flyer_${event.id ?? widget.index}.$ext');
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Shares the flyer as its own clean image with the message as separate
  /// text (custom caption, or an auto invite when none is set). Apps that
  /// keep both (Messages, WhatsApp, email) show flyer + text; image-only
  /// targets still get the flyer.
  Future<void> share_Clicked() async {
    final message = buildShareMessage(event);
    final url = event.imageUrl?.trim() ?? '';
    File? flyer;
    if (url.isNotEmpty) flyer = await _downloadFlyer(url);

    // Copy the message first so that if the chosen app drops attached text
    // (Instagram/Snapchat do), the user can just paste it.
    if (flyer != null) {
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Caption copied — paste it if the app drops the text'),
          duration: Duration(seconds: 4),
        ));
      }
      await Share.shareXFiles([XFile(flyer.path)],
          text: message, subject: event.title ?? 'Share Event');
    } else {
      await Share.share(message, subject: event.title ?? 'Share Event');
    }
  }

  /// Writes a one-event .ics to a temp file and hands it to the OS. On iOS
  /// this opens the Calendar "Add Event" sheet; on Android the calendar app
  /// (or a chooser) offers to add it — the user sets their own alerts there.
  Future<void> addToCalendar_Clicked() async {
    final ics = buildEventIcs(event, stampMs: DateTime.now().millisecondsSinceEpoch);
    if (ics.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final safeName = (event.title ?? 'event')
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .toLowerCase();
      final file = File('${dir.path}/$safeName.ics');
      await file.writeAsString(ics);
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/calendar')],
          subject: event.title ?? 'Event');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't open calendar")));
      }
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

  /// Shimmering placeholder shaped like the loaded page: flyer, register
  /// bar, contact circles, button row.
  Widget _skeleton(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SkeletonBox(width: width, height: 320, radius: 0),
          const SizedBox(height: 14),
          SkeletonBox(width: width - 30, height: 44, radius: 22),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonBox(width: 44, height: 44, radius: 22),
              SizedBox(width: 18),
              SkeletonBox(width: 44, height: 44, radius: 22),
              SizedBox(width: 18),
              SkeletonBox(width: 44, height: 44, radius: 22),
            ],
          ),
          const SizedBox(height: 14),
          SkeletonBox(width: width - 30, height: 36),
          const SizedBox(height: 10),
          SkeletonBox(width: width - 90, height: 14),
          const SizedBox(height: 6),
          SkeletonBox(width: width - 140, height: 14),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Event?>(
      stream: _eventStream,
      builder: (context, eventSnapshot) {
        return FutureBuilder(
          future: _users,
          builder: (context, snapshot) {
        if (!eventSnapshot.hasData || !snapshot.hasData) {
          return _skeleton(context);
        }
        event = eventSnapshot.data ?? Event();
        Map<String, MyUser> users = snapshot.data!;
        List<Attendee> attendees = List.empty(growable: true);
        // Recomputed on every live update so un-attending elsewhere is
        // reflected here too.
        attending = false;
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
                  // Owner-approved order: flyer, Register, contact/socials,
                  // Attend/Share, address, then the write-up.
                  event.imageSrc ?? SizedBox(width: 0, height: 0),
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
                  if (_canRemind)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 6, 15, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _reminding
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary,
                            backgroundColor: _reminding
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            side: BorderSide(
                                color: Theme.of(context).colorScheme.primary),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                            ),
                          ),
                          icon: Icon(_reminding
                              ? Icons.notifications_active
                              : Icons.notifications_none),
                          label: Text(_reminding ? 'Reminders on' : 'Remind me'),
                          onPressed: _toggleRemind,
                        ),
                      ),
                    ),
                  _contactRow(context),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
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
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                        ),
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Add to my calendar'),
                        onPressed: addToCalendar_Clicked,
                      ),
                    ),
                  ),
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
          },
        );
      }
    );
  }
}
