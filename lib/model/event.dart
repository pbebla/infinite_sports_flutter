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
  DateTime? eventDateTime;

  // EventsV2 fields (null on legacy events).
  String? id;
  String? category;
  String? details;
  DateTime? startDate;
  DateTime? endDate;
  String? repeatFreq;
  DateTime? repeatUntil;
  String? contactPhone;
  String? instagram;
  String? facebook;
  String? youtube;
  int? legacyIndex;

  void format() {
    eventDateTime = parseDatabaseDate(eventDate!);
    eventDate = convertDatabaseDateToFormatDate(eventDate!);
    date = convertDatabaseDateToFormatDate(date!);
    if (imageUrl != null) {
      imageSrc = Image.network(imageUrl!, errorBuilder:(context, error, stackTrace) => SizedBox(width: 0, height: 0));
    }
  }

  /// Builds an event from an EventsV2 record. Returns null when the record
  /// has no parseable StartDate — a V2 event without a date can't be shown.
  static Event? fromV2(String id, Map json) {
    final start = parseDatabaseDate(json['StartDate']?.toString() ?? '');
    if (start == null) return null;
    final event = Event();
    event.id = id;
    event.title = json['Title']?.toString() ?? '';
    event.category = json['Category']?.toString();
    event.info = json['Info']?.toString() ?? '';
    event.details = json['Details']?.toString();
    event.startDate = start;
    event.eventDateTime = start;
    event.eventDate = convertDatabaseDateToFormatDate(json['StartDate'].toString());
    event.endDate = parseDatabaseDate(json['EndDate']?.toString() ?? '');
    final repeat = json['Repeat'];
    if (repeat is Map) {
      event.repeatFreq = repeat['Freq']?.toString();
      event.repeatUntil = parseDatabaseDate(repeat['Until']?.toString() ?? '');
    }
    event.startTime = json['StartTime']?.toString() ?? '';
    event.endTime = json['EndTime']?.toString() ?? '';
    event.location = json['Location']?.toString() ?? '';
    event.address = json['Address']?.toString() ?? '';
    event.contactPhone = json['ContactPhone']?.toString();
    event.instagram = json['Instagram']?.toString();
    event.facebook = json['Facebook']?.toString();
    event.youtube = json['Youtube']?.toString();
    event.legacyIndex = json['LegacyIndex'] is int ? json['LegacyIndex'] : int.tryParse('${json['LegacyIndex']}');
    event.imageUrl = json['ImageUrl']?.toString() ?? '';
    if (event.imageUrl!.isNotEmpty) {
      event.imageSrc = Image.network(event.imageUrl!, errorBuilder:(context, error, stackTrace) => SizedBox(width: 0, height: 0));
    }
    if (json['Attendees'] is Map) {
      event.attendees = {};
      (json['Attendees'] as Map).forEach((uid, value) {
        event.attendees![uid.toString()] = value.toString();
      });
    }
    return event;
  }
}