import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/match_location.dart';

void main() {
  group('MatchLocationInfo.fromMatch', () {
    test('parses structured Location map', () {
      final info = MatchLocationInfo.fromMatch(
        location: {'Venue': 'Pioneer High School', 'Address': '1290 Blossom Hill Rd', 'Field': 'Field 1 · Turf'},
        legacyString: null,
      );
      expect(info, isNotNull);
      expect(info!.venue, 'Pioneer High School');
      expect(info.address, '1290 Blossom Hill Rd');
      expect(info.field, 'Field 1 · Turf');
    });
    test('falls back to legacy string (venue only)', () {
      final info = MatchLocationInfo.fromMatch(location: null, legacyString: 'City Park — Field 2');
      expect(info, isNotNull);
      expect(info!.venue, 'City Park — Field 2');
      expect(info.address, isNull);
      expect(info.field, isNull);
    });
    test('null when no location at all', () {
      expect(MatchLocationInfo.fromMatch(location: null, legacyString: null), isNull);
      expect(MatchLocationInfo.fromMatch(location: null, legacyString: ''), isNull);
    });
  });

  group('mapsUrl', () {
    test('uses address when present, url-encoded', () {
      final info = MatchLocationInfo(venue: 'Pioneer HS', address: '1290 Blossom Hill Rd, San Jose', field: 'F1');
      expect(info.mapsUrl(),
          'https://www.google.com/maps/search/?api=1&query=1290%20Blossom%20Hill%20Rd%2C%20San%20Jose');
    });
    test('falls back to venue when no address', () {
      final info = MatchLocationInfo(venue: 'Pioneer HS', address: null, field: null);
      expect(info.mapsUrl(), 'https://www.google.com/maps/search/?api=1&query=Pioneer%20HS');
    });
  });
}
