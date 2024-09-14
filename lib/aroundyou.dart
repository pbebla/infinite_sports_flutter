import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:infinite_sports_flutter/misc/navigation_controls.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/misc/web_view_stack.dart';
import 'package:infinite_sports_flutter/model/business.dart';
import 'package:infinite_sports_flutter/model/event.dart';
import 'package:infinite_sports_flutter/scorepage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  bool isSheetExpanded = false;
  List<Business>? businesses;
  List<Event>? events;
  Set<Marker> markers = Set();
  Marker? currentPositionMarker;
  GoogleMap? _googleMap;

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
    markers = Set();
    currentPositionMarker = Marker(
      markerId: const MarkerId('user_location'),
      position: _center!,
      infoWindow: const InfoWindow(title: 'Your Location'),
    );
    markers.add(currentPositionMarker!);
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
    _googleMap = GoogleMap(
      padding: EdgeInsets.only(
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
    businesses = await getBusinesses();
    events = await getEvents();
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
            return CircularProgressIndicator();
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
                initialChildSize: 0.08,
                builder: (BuildContext context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface
                    ),
                    child: DefaultTabController(
                    length: 2, 
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: ClampingScrollPhysics(),
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
                            icon: isSheetExpanded ? Icon(Icons.arrow_drop_down) : Icon(Icons.arrow_drop_up),
                          ),
                          title: TabBar(
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
                              icon: Icon(Icons.refresh)
                            ),
                            IconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: Text("Around You is a place to discover Assyrian Businesses and Events.\nIf you want us to feature your Business or Event, contact us for more info!"),
                                      actions: [
                                        TextButton(
                                          child: Text("OK"),
                                          onPressed: () {
                                            Navigator.pop(context);
                                          },
                                        )
                                      ],
                                    );
                                  },
                                );
                              },
                              icon: Icon(Icons.info_outline_rounded)
                            )
                          ],
                        ),
                        SliverFillRemaining(
                          child: TabBarView(
                            children: [
                              ListView.builder(
                                itemCount: businesses?.length ?? 0,
                                //controller: scrollController,
                                physics: ClampingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemBuilder: (context, index) => ListTile(
                                  leading: businesses![index].logo ?? Text(""),
                                  title: Text('${businesses![index].name}'),
                                  subtitle: Text('${businesses![index].description}', overflow: TextOverflow.ellipsis,),
                                  trailing: (!businesses![index].lat.isNaN) ? Text('${businesses![index].getMiles(_currentPosition!).toString().substring(0,4)} mi' ) : Text(""),
                                  onTap: () async {
                                    var address = "";
                                    if (!businesses![index].lat.isNaN) {
                                      mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(businesses![index].lat-0.08, businesses![index].long)));
                                      address = await getAddress(LatLng(businesses![index].lat,  businesses![index].long));
                                    }
                                    Navigator.push(context, MaterialPageRoute(builder: (context) {
                                      return Scaffold(
                                        appBar: AppBar(
                                          title: Text(businesses![index].name ?? "")
                                        ),
                                        body: SingleChildScrollView(
                                          child: Column(
                                            children: [
                                              Container(child: businesses![index].logo, height: 250,),
                                              Container(
                                                color: Theme.of(context).colorScheme.surfaceContainer,
                                                child: !businesses![index].lat.isNaN ? 
                                                    ListTile(title: Text(address), onTap: () async {
                                                      String appleUrl = 'https://maps.apple.com/?saddr=&daddr=${businesses![index].lat},${businesses![index].long}&directionsmode=driving';
                                                      String googleUrl = 'https://www.google.com/maps/search/?api=1&query=${businesses![index].lat},${businesses![index].long}';

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
                                                    },) : Text(""),),
                                              Container(
                                                color: Theme.of(context).colorScheme.surfaceContainer,
                                                child: ListTile(title: Text("Website"), enabled: businesses![index].url?.isNotEmpty ?? false, onTap: () {
                                                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                                                    WebViewController controller = WebViewController()
                                                    ..loadRequest(Uri.parse(businesses![index].url ?? ""));
                                                    return Scaffold(
                                                      appBar: AppBar(
                                                        title: const Text(""),
                                                        actions: [
                                                          NavigationControls(controller: controller)
                                                        ],
                                                      ),
                                                      body: WebViewStack(controller: controller,),
                                                    );
                                                  },));
                                                },),
                                              ),
                                              Container(
                                                color: Theme.of(context).colorScheme.surfaceContainer,
                                                child: ListTile(title: Text("Call"), onTap: () async {
                                                  var url = Uri.parse("tel:${businesses![index].phone ?? ""}");
                                                  bool canCall = await canLaunchUrl(url);
                                                  if (canCall) {
                                                    await launchUrl(url);
                                                  }
                                                },),
                                              ),
                                              Text(businesses![index].description ?? ""),
                                            ],
                                          )
                                        ),   
                                      );
                                    }));
                                  },
                                ),
                              ),
                              ListView.builder(
                                itemCount: events?.length ?? 0,
                                //controller: scrollController,
                                physics: ClampingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemBuilder: (context, index) => ListTile(
                                  leading: events![index].imageSrc ?? Text(""),
                                  title: Text('${events![index].title}'),
                                  subtitle: Text('on ${events![index].eventDate}\nat ${events![index].location}\n${events![index].startTime} - ${events![index].endTime}'),
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