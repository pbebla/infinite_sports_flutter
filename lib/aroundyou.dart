
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:infinite_sports_flutter/businesspage.dart';
import 'package:infinite_sports_flutter/eventpage.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:infinite_sports_flutter/model/event.dart';

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
  LatLng? _center;
  Position? _currentPosition;
  final DraggableScrollableController sheetController = DraggableScrollableController();
  bool isSheetExpanded = true;
  List<Business>? businesses;
  List<Event>? events;
  Set<Marker> markers = {};
  GoogleMap? _googleMap;
  List<Location?> eventLocations = List.empty(growable: true);

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  _getUserLocation() async {
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
    // Get the current location of the user
    _currentPosition = await Geolocator.getCurrentPosition();
    setState(() {
      _center = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    });
  }
  
  Future<int> _getBusinessesAndEvents() async {
    businesses = await getBusinesses();
    events = await getEvents();
    for (var i = 0; i < businesses!.length ; i++) {
      if (!businesses![i].lat.isNaN) {
        Marker marker = Marker(
          markerId: MarkerId(i.toString()),
          position: LatLng(businesses![i].lat, businesses![i].long),
          infoWindow: InfoWindow(title: businesses![i].name),
        );
        markers.add(marker);
      }
    }
    for (var i = 0; i < events!.length ; i++) {
      if (events![i].address != null) {
        try {
          List<Location> locations = await GeocodingPlatform.instance!.locationFromAddress(events![i].address!);
          Marker marker = Marker(
            markerId: MarkerId(((businesses?.length ?? 0) + i).toString()),
            position: LatLng(locations[0].latitude, locations[0].longitude),
            infoWindow: InfoWindow(title: events![i].title),
          );
          markers.add(marker);
          eventLocations.add(locations[0]);
        } catch (e) {
          eventLocations.add(null);
        }
      } else {
        eventLocations.add(null);
      }
    }
    _googleMap = GoogleMap(
      myLocationEnabled: true,
      padding: const EdgeInsets.only(
         bottom:45),
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: _center!,
        zoom: 11.0,
      ),
      markers: markers,
    );
    return 1;
  }

  Future<void> _refreshData() async {
    setState(() {});
  }

  Future<String> getAddress(LatLng position) async
  {
    List<Placemark> addresses = await placemarkFromCoordinates(position.latitude, position.longitude);
    return addresses.isNotEmpty ? '${addresses[0].street}\n${addresses[0].locality} ${addresses[0].administrativeArea} ${addresses[0].postalCode}' : "";

  }

  @override
  Widget build(BuildContext context) {
    return _center == null
      ? const Center(child: CircularProgressIndicator())
      : FutureBuilder(
        future: _getBusinessesAndEvents(), 
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child:  CircularProgressIndicator(),);
          }
          return Stack(
            children: [
              SizedBox(
                height: double.infinity,
                  child: _googleMap,
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
                              Tab(child: Text("Businesses", style: TextStyle(fontSize: 13),),),
                              Tab(child: Text("Events"),)
                            ],
                          ),
                          primary: false,
                          pinned: true,
                          centerTitle: true,
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
                        SliverFillRemaining(
                          child: TabBarView(
                            children: [
                              ListView.builder(
                                itemCount: businesses?.length ?? 0,
                                //controller: scrollController,
                                physics: const ClampingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemBuilder: (context, index) => ListTile(
                                  leading: businesses![index].logo ?? const Text(""),
                                  title: Text('${businesses![index].name}'),
                                  subtitle: Text('${businesses![index].description}', overflow: TextOverflow.ellipsis,),
                                  trailing: (!businesses![index].lat.isNaN) ? Text('${businesses![index].getMiles(_currentPosition!).toString().substring(0,4)} mi' ) : const Text(""),
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
                              ListView.builder(
                                itemCount: events?.length ?? 0,
                                //controller: scrollController,
                                physics: const ClampingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemBuilder: (context, index) => ListTile(
                                  leading: events![index].imageSrc ?? const Text(""),
                                  title: Text('${events![index].title}'),
                                  subtitle: Text('on ${events![index].eventDate}\nat ${events![index].location}\n${events![index].startTime} - ${events![index].endTime}'),
                                  onTap: () async {
                                    if (eventLocations[index] != null) {
                                      mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(eventLocations[index]!.latitude-0.08, eventLocations[index]!.longitude)));
                                    }
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (context) {
                                      return EventPage(index: index,);
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
          );
        }
      );
      
  }
}