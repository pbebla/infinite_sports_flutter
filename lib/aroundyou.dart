import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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


class _AroundYouState extends State<AroundYou> {
  GoogleMapController? mapController;
  LatLng? _center;
  Position? _currentPosition;
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
  
  @override
  Widget build(BuildContext context) {
    return _center == null
      ? const Center(child: CircularProgressIndicator())
      : SizedBox(
          height: double.infinity,
            child: GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _center!,
              zoom: 11.0,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('user_location'),
                position: _center!,
                infoWindow: const InfoWindow(title: 'Your Location'),
              ),
            },
          ),
      );
  }
}