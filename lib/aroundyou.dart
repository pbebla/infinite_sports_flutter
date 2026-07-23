
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:infinite_sports_flutter/businesspage.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/event_repo.dart';
import 'package:infinite_sports_flutter/misc/event_utils.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
class AroundYou extends StatefulWidget {
  const AroundYou({super.key});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  //final String title;

  @override
  State<AroundYou> createState() => _AroundYouState();
}


class _AroundYouState extends State<AroundYou> with SingleTickerProviderStateMixin {
  GoogleMapController? mapController;
  // Map shows immediately centered on San Jose, then glides to the user
  // once their location resolves — no full-screen wait.
  static const LatLng _fallbackCenter = LatLng(37.3382, -121.8863);
  bool _locationReady = false;
  Position? _currentPosition;
  final DraggableScrollableController sheetController = DraggableScrollableController();
  bool isSheetExpanded = true;
  List<Business>? businesses;
  List<Event>? events;
  Set<Marker> markers = {};
  // Geocode results cached by address so live event updates don't re-hit
  // the geocoder for addresses we already resolved.
  final Map<String, Location?> _geocodeCache = {};
  StreamSubscription<List<Event>>? _eventsSub;
  StreamSubscription<DatabaseEvent>? _bizSub;

  @override
  void initState() {
    super.initState();
    // Live businesses: onValue fires immediately with current data and
    // again on every change to the Map node.
    _bizSub = FirebaseDatabase.instance.ref('Map').onValue.listen((_) {
      _loadBusinesses();
    });
    // Live events: the list, markers, and upcoming/past split update in
    // place whenever an event is added, edited, or removed.
    _eventsSub = watchAllEvents().listen((list) async {
      events = list;
      _splitEvents();
      await _rebuildEventMarkers();
      if (mounted) setState(() {});
    });
    _getUserLocation();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _bizSub?.cancel();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }
    // Request permission to get the user's location
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
      return;
    }
    }
    // Get the current location of the user, then glide the map over.
    _currentPosition = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _locationReady = true);
    mapController?.animateCamera(CameraUpdate.newLatLng(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude)));
  }
  
  // Merged-list indices split by whether the event is fully over; upcoming
  // soonest-first, past most-recent-first (browsable history, never deleted).
  List<int> _upcomingIdx = [];
  List<int> _pastIdx = [];

  void _splitEvents() {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final upcoming = <int>[];
    final past = <int>[];
    for (var i = 0; i < (events?.length ?? 0); i++) {
      final days = occurrenceDays(events![i]);
      if (days.isNotEmpty && days.last.isBefore(midnight)) {
        past.add(i);
      } else {
        upcoming.add(i);
      }
    }
    DateTime sortKey(int i) => events![i].eventDateTime ?? midnight;
    upcoming.sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    past.sort((a, b) => sortKey(b).compareTo(sortKey(a)));
    _upcomingIdx = upcoming;
    _pastIdx = past;
  }

  Future<void> _loadBusinesses() async {
    businesses = await getBusinesses();
    for (var i = 0; i < businesses!.length ; i++) {
      if (!businesses![i].lat.isNaN) {
        Marker marker = Marker(
          markerId: MarkerId('biz-$i'),
          position: LatLng(businesses![i].lat, businesses![i].long),
          infoWindow: InfoWindow(title: businesses![i].name),
        );
        markers.add(marker);
      }
    }
    if (mounted) setState(() {});
  }

  Future<Location?> _locationFor(Event event) async {
    final address = event.address;
    if (address == null || address.isEmpty) return null;
    if (_geocodeCache.containsKey(address)) return _geocodeCache[address];
    try {
      final locations = await GeocodingPlatform.instance!.locationFromAddress(address);
      _geocodeCache[address] = locations.isEmpty ? null : locations[0];
    } catch (_) {
      _geocodeCache[address] = null;
    }
    return _geocodeCache[address];
  }

  Future<void> _rebuildEventMarkers() async {
    markers.removeWhere((m) => m.markerId.value.startsWith('event-'));
    for (var i = 0; i < (events?.length ?? 0); i++) {
      final location = await _locationFor(events![i]);
      if (location == null) continue;
      markers.add(Marker(
        markerId: MarkerId('event-$i'),
        // Gold pins distinguish events from the red business pins.
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        position: LatLng(location.latitude, location.longitude),
        infoWindow: InfoWindow(title: events![i].title),
      ));
    }
  }

  Future<void> _refreshData() async {
    // Events are live; only businesses need a manual re-pull.
    markers.removeWhere((m) => m.markerId.value.startsWith('biz-'));
    await _loadBusinesses();
  }

  Future<String> getAddress(LatLng position) async
  {
    List<Placemark> addresses = await placemarkFromCoordinates(position.latitude, position.longitude);
    return addresses.isNotEmpty ? '${addresses[0].street}\n${addresses[0].locality} ${addresses[0].administrativeArea} ${addresses[0].postalCode}' : "";

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          // Pushed from the search hub: the root drawer would open hidden
          // behind this route, so show a back button instead.
          leading: Navigator.canPop(context)
              ? const BackButton()
              : Builder(
                  builder: (context) {
                    return IconButton(
                      icon: const ImageIcon(AssetImage('assets/profile.png')),
                      onPressed: () {
                        Scaffold.of(mainScaffoldContext!).openDrawer();
                      },);
                  },
                ),
          backgroundColor: TournamentColors.headerBackground(context),
          foregroundColor: TournamentColors.headerForeground(context),
          centerTitle: true,
          title: Image.asset('assets/infinitelarge_dark.png', height: 30),
          actions: [
            IconButton(
              onPressed: () async {
                await _refreshData();
              },
              icon: const Icon(Icons.refresh)
            ),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text("Around You is a place to discover Assyrian Businesses and Events.\nIf you want us to feature your Business or Event, contact us for more info!"),
                      actions: [
                        TextButton(
                          child: const Text("OK"),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                        )
                      ],
                    );
                  },
                );
              },
              icon: const Icon(Icons.info_outline_rounded)
            )
          ],
        ),
        body: Builder(
          builder: (context) {
          // No gate: map + sheet render immediately; each tab shows
          // skeleton rows until its data arrives (events are live).
          return Scaffold(
            body: Stack(
              children: [
                SizedBox(
                  height: double.infinity,
                    // Rebuilt with a fresh marker set every build so live
                    // event/business changes actually reach the map.
                    child: GoogleMap(
                      myLocationEnabled: _locationReady,
                      padding: const EdgeInsets.only(bottom: 45),
                      onMapCreated: _onMapCreated,
                      initialCameraPosition: const CameraPosition(
                        target: _fallbackCenter,
                        zoom: 10.5,
                      ),
                      markers: Set.of(markers),
                    ),
                ),
                DraggableScrollableSheet(
                  controller: sheetController,
                  minChildSize: 0.08,
                  maxChildSize: 0.5,
                  initialChildSize: 0.5,
                  builder: (BuildContext context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface
                      ),
                      child: DefaultTabController(
                      length: 2, 
                      child: CustomScrollView(
                        controller: scrollController,
                        physics: const ClampingScrollPhysics(),
                        slivers: [
                          SliverAppBar(
                            leading: IconButton(
                              onPressed: () {
                                if (isSheetExpanded) {
                                  sheetController.animateTo(
                                    0.08,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.bounceIn,
                                  );
                                } else {
                                  sheetController.animateTo(
                                    0.5,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.bounceIn,
                                  );
                                }
                                setState(() {
                                  isSheetExpanded = !isSheetExpanded;
                                });
                              },
                              icon: isSheetExpanded ? const Icon(Icons.arrow_drop_down) : const Icon(Icons.arrow_drop_up),
                            ),
                            title: const TabBar(
                              tabs: [
                                Tab(child: Text("Events"),),
                                Tab(child: Text("Businesses"),)
                              ],
                            ),
                            primary: false,
                            pinned: true,
                            centerTitle: true,
                          ),
                          SliverFillRemaining(
                            child: TabBarView(
                              children: [
                                events == null
                                    ? const SingleChildScrollView(
                                        physics: ClampingScrollPhysics(),
                                        child: SkeletonMatchList(count: 7))
                                    : ListView.builder(
                                  itemCount: _upcomingIdx.length +
                                      (_pastIdx.isEmpty ? 0 : _pastIdx.length + 1),
                                  //controller: scrollController,
                                  physics: const ClampingScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, position) {
                                    // Upcoming first, then a header, then
                                    // past events dimmed (auto-archived by
                                    // date — nothing is ever deleted).
                                    if (position == _upcomingIdx.length && _pastIdx.isNotEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                                        child: Text('Past events',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                            )),
                                      );
                                    }
                                    final isPast = position > _upcomingIdx.length;
                                    final index = isPast
                                        ? _pastIdx[position - _upcomingIdx.length - 1]
                                        : _upcomingIdx[position];
                                    final event = events![index];
                                    final tile = ListTile(
                                      leading: event.imageSrc ?? SizedBox(width: 0, height: 0),
                                      title: Text('${event.title}'),
                                      subtitle: Text('on ${event.eventDate}\nat ${event.location}\n${event.startTime} - ${event.endTime}'),
                                      onTap: () async {
                                        final location = _geocodeCache[event.address];
                                        if (location != null && mapController != null) {
                                          mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(location.latitude-0.08, location.longitude)));
                                        }
                                        Navigator.push(context, MaterialPageRoute(
                                          builder: (context) {
                                          return event.id != null
                                              ? EventPage(v2Id: event.id)
                                              : EventPage(index: event.legacyIndex ?? index);
                                        }));
                                      },
                                    );
                                    return isPast ? Opacity(opacity: 0.55, child: tile) : tile;
                                  },
                                ),
                                businesses == null
                                    ? const SingleChildScrollView(
                                        physics: ClampingScrollPhysics(),
                                        child: SkeletonMatchList(count: 7))
                                    : ListView.builder(
                                  itemCount: businesses?.length ?? 0,
                                  //controller: scrollController,
                                  physics: const ClampingScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (context, index) => ListTile(
                                    leading: businesses![index].logo ?? SizedBox(width: 0, height: 0),
                                    title: Text('${businesses![index].name}'),
                                    subtitle: Text('${businesses![index].description}', overflow: TextOverflow.ellipsis,),
                                    trailing: (_currentPosition != null && !businesses![index].lat.isNaN) ? Text('${businesses![index].getMiles(_currentPosition!).toString().substring(0,4)} mi' ) : SizedBox(width: 0, height: 0),
                                    onTap: () async {
                                      var address = "";
                                      if (!businesses![index].lat.isNaN) {
                                        mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(businesses![index].lat-0.08, businesses![index].long)));
                                        address = await getAddress(LatLng(businesses![index].lat,  businesses![index].long));
                                      }
                                      Navigator.push(context, ModalBottomSheetRoute(
                                        isScrollControlled: true,
                                        modalBarrierColor: Colors.transparent,
                                        builder: (context) {
                                        return BusinessPage(business: businesses![index], address: address);
                                      }));
                                    },
                                  ),
                                ),
                              ],
                        ),
                          )
                        ]
                      ),
                    ),
                    );
                  },
                ),
              ],
            ),
          );
        }
        ),
      );
      
  }
}