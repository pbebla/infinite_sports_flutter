// Unit tests for the pure PublicProfiles parsing
// (lib/misc/public_profiles.dart, DB lockdown B1). Firebase-free: only the
// pure fromNode/publicProfilesFromNode functions are exercised.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/misc/public_profiles.dart';

void main() {
  group('PublicProfile.fromNode', () {
    test('parses a full mirrored node', () {
      final profile = PublicProfile.fromNode('u1', {
        'First Name': 'Zaya',
        'Last Name': 'Arami',
        'ProfileUrl': 'https://x/img.jpg',
        'Information': {'Age': 30, 'Height': "5'10"},
        'Played': {
          'Futsal': {'Futsal 13': 'The Boys'}
        },
        'TournamentsPlayed': {'t1': true},
        'Awards': {
          'a1': {'Title': 'MVP'}
        },
        'ProfileCompleted': true,
      });
      expect(profile, isNotNull);
      expect(profile!.uid, 'u1');
      expect(profile.firstName, 'Zaya');
      expect(profile.lastName, 'Arami');
      expect(profile.fullName, 'Zaya Arami');
      expect(profile.profileUrl, 'https://x/img.jpg');
      expect(profile.information['Age'], 30);
      expect(profile.played['Futsal'], isA<Map>());
      expect(profile.tournamentsPlayed['t1'], true);
      expect(profile.awards['a1'], isA<Map>());
      expect(profile.profileCompleted, isTrue);
    });

    test('a minimal node parses with defaults', () {
      final profile = PublicProfile.fromNode('u1', {'First Name': 'Zaya'});
      expect(profile, isNotNull);
      expect(profile!.lastName, '');
      expect(profile.fullName, 'Zaya');
      expect(profile.profileUrl, '');
      expect(profile.information, isEmpty);
      expect(profile.played, isEmpty);
      expect(profile.tournamentsPlayed, isEmpty);
      expect(profile.awards, isEmpty);
      expect(profile.profileCompleted, isFalse);
    });

    test('null / non-map / empty-uid nodes return null', () {
      expect(PublicProfile.fromNode('u1', null), isNull);
      expect(PublicProfile.fromNode('u1', 'junk'), isNull);
      expect(PublicProfile.fromNode('u1', 42), isNull);
      // RTDB List coercion of a single node must not crash.
      expect(PublicProfile.fromNode('u1', ['a', 'b']), isNull);
      expect(PublicProfile.fromNode('', {'First Name': 'X'}), isNull);
    });

    test('inner maps coerced to Lists by RTDB degrade to empty, not crash',
        () {
      final profile = PublicProfile.fromNode('u1', {
        'First Name': 'Zaya',
        'Information': ['not', 'a', 'map'],
        'Played': 7,
        'Awards': null,
      });
      expect(profile, isNotNull);
      expect(profile!.information, isEmpty);
      expect(profile.played, isEmpty);
      expect(profile.awards, isEmpty);
    });
  });

  group('publicProfilesFromNode', () {
    test('parses the root map, skipping malformed children', () {
      final out = publicProfilesFromNode({
        'u1': {'First Name': 'A'},
        'u2': 'junk',
        'u3': {'Last Name': 'C'},
      });
      expect(out.keys, unorderedEquals(['u1', 'u3']));
      expect(out['u1']!.firstName, 'A');
      expect(out['u3']!.lastName, 'C');
    });

    test('null / junk roots return {}', () {
      expect(publicProfilesFromNode(null), isEmpty);
      expect(publicProfilesFromNode('junk'), isEmpty);
      expect(publicProfilesFromNode(12), isEmpty);
    });

    test('an RTDB List-coerced root must not crash — non-null entries parse '
        'under their index', () {
      final out = publicProfilesFromNode([
        null,
        {'First Name': 'B'},
      ]);
      expect(out.keys, ['1']);
      expect(out['1']!.firstName, 'B');
    });
  });

  group('isSignedInUid', () {
    test('empty uid is never self; no Firebase app degrades to false', () {
      expect(isSignedInUid(''), isFalse);
      // No Firebase app in unit tests — the defensive catch must return
      // false (mirror path) instead of throwing [core/no-app].
      expect(isSignedInUid('someone'), isFalse);
    });

    test('profileNodePathFor falls back to the public mirror', () {
      expect(profileNodePathFor('u9'), 'PublicProfiles/u9');
    });
  });
}
