// Unit tests for the pure lockdown-mirror parsing in
// lib/registration/registration_service.dart (B2/B3): the
// RegistrationsPublic root parse and the Teams/{tid}/Members roster parse.
// Firebase-free — only the pure top-level functions are exercised.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/registration/registration_service.dart';

Map<String, dynamic> _config({String status = 'open'}) => {
      'TargetType': 'league',
      'Sport': 'Futsal',
      'Season': '17',
      'Status': status,
      'Fee': 60,
    };

void main() {
  group('openRegistrationsFromNode (B2)', () {
    test('keeps open configs, drops closed and malformed ones', () {
      final out = openRegistrationsFromNode({
        'Futsal-17': _config(),
        'Futsal-16': _config(status: 'closed'),
        'junk': 'not a map',
        'bad': {'Status': 'open'}, // no TargetType -> malformed
      });
      expect(out.keys, ['Futsal-17']);
      expect(out['Futsal-17']!.sport, 'Futsal');
      expect(out['Futsal-17']!.isOpen, isTrue);
    });

    test('null / junk roots return {}', () {
      expect(openRegistrationsFromNode(null), isEmpty);
      expect(openRegistrationsFromNode('junk'), isEmpty);
      expect(openRegistrationsFromNode(3), isEmpty);
    });

    test('an RTDB List-coerced root must not crash', () {
      final out = openRegistrationsFromNode([null, _config()]);
      expect(out.keys, ['1']);
      expect(out['1']!.isOpen, isTrue);
    });
  });

  group('teamMembersFromNode (B3)', () {
    test('parses members, filters the captain, sorts case-insensitively', () {
      final out = teamMembersFromNode({
        'cap-uid': {'DisplayName': 'Captain Carl', 'Paid': true},
        'u2': {'DisplayName': 'zoe', 'Paid': false},
        'u3': {'DisplayName': 'Adam', 'Paid': true},
        'u4': 'junk',
      }, teamId: 't1', captainUid: 'cap-uid');
      expect(out.map((m) => m.displayName), ['Adam', 'zoe']);
      expect(out.first.paid, isTrue);
      expect(out.last.paid, isFalse);
      // Shape the status page has always consumed.
      expect(out.first.path, 'joiner');
      expect(out.first.teamId, 't1');
    });

    test('no captainUid keeps every well-formed entry', () {
      final out = teamMembersFromNode({
        'cap-uid': {'DisplayName': 'Captain Carl', 'Paid': true},
        'u2': {'DisplayName': 'Zoe'},
      }, teamId: 't1');
      expect(out.length, 2);
    });

    test('DisplayName/Paid fallbacks: missing -> "" / false', () {
      final out = teamMembersFromNode({
        'u1': <String, dynamic>{},
      }, teamId: 't1');
      expect(out.single.displayName, '');
      expect(out.single.paid, isFalse);
    });

    test('null / junk / List-coerced nodes must not crash', () {
      expect(teamMembersFromNode(null, teamId: 't1'), isEmpty);
      expect(teamMembersFromNode('junk', teamId: 't1'), isEmpty);
      final coerced = teamMembersFromNode(
          [null, {'DisplayName': 'Idx One', 'Paid': true}],
          teamId: 't1');
      expect(coerced.single.displayName, 'Idx One');
    });
  });
}
