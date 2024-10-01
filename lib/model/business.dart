import 'dart:core';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class Business {
  double lat = double.nan;
  double long = double.nan;
  String? logoUrl;
  Image? logo;
  String? description;
  String? name;
  String? url;
  String? phone;
  
  double compareTo(Position obj) {
    if (!lat.isNaN || !long.isNaN) {
      var dif = sqrt(pow(lat-obj.latitude, 2) + pow(long - obj.longitude, 2));
      return dif;
    }
    return double.maxFinite;
  }

  double getMiles(Position obj) {
    if (!lat.isNaN || !long.isNaN) {
      var thisLatMiles = lat * 69;
      var thisLongMiles = long * 69.172;
      var otherLatMiles = obj.latitude * 69;
      var otherLongMiles = obj.longitude  * 69.172;

      var dif = sqrt(pow(thisLatMiles - otherLatMiles, 2) + pow(thisLongMiles - otherLongMiles, 2));

      return dif;
    }
    return double.nan;
  }
}