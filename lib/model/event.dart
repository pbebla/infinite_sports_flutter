import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';

class Event {
  String? address;
  String? date;
  String? endTime;
  String? eventDate;
  String? imageUrl;
  String? info;
  String? location;
  String? startTime;
  String? title;
  List<Map<String, String>>? buttons;
  Map<String, String>? attendees;
  Image? imageSrc;
  
  void format() {
    eventDate = convertDatabaseDateToFormatDate(eventDate!);
    date = convertDatabaseDateToFormatDate(date!);
    if (imageUrl != null) {
      imageSrc = Image.network(imageUrl!, errorBuilder:(context, error, stackTrace) => SizedBox(width: 0, height: 0));
    }
  }

}