// Unit tests for the pure lockdown-mirror parsing and callable-result
// mapping in lib/registration/registration_service.dart /
// lib/registration/promo_engine.dart (B2/B3/B4): the RegistrationsPublic
// root parse, the Teams/{tid}/Members roster parse, and the
// checkFirstTimer/resolveJoinCode result mappers. Firebase-free — only
// pure top-level functions are exercised.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/registration/promo_engine.dart';
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

  group('firstTimerResultFromCallable (B4)', () {
    test('maps the callable payload onto FirstTimerResult', () {
      final hit = firstTimerResultFromCallable({
        'isFirstTimer': false,
        'matchedByEmail': true,
        'matchedByPhone': false,
      });
      expect(hit.isFirstTimer, isFalse);
      expect(hit.matchedByEmail, isTrue);
      expect(hit.matchedByPhone, isFalse);

      final miss = firstTimerResultFromCallable({'isFirstTimer': true});
      expect(miss.isFirstTimer, isTrue);
      expect(miss.matchedByEmail, isFalse);
    });

    test('malformed payloads degrade to first-timer (the old scan error '
        'semantics)', () {
      expect(firstTimerResultFromCallable(null).isFirstTimer, isTrue);
      expect(firstTimerResultFromCallable('junk').isFirstTimer, isTrue);
      expect(
          firstTimerResultFromCallable(<String, dynamic>{}).isFirstTimer,
          isTrue);
    });
  });

  group('joinCodeMatchFromCallable (B4)', () {
    test('an ok result becomes an approved RegTeam with the joiner-path '
        'fields', () {
      final match = joinCodeMatchFromCallable({
        'found': true,
        'status': 'ok',
        'teamId': 't1',
        'teamName': 'The Boys',
        'codeWaivesPayment': true,
      });
      expect(match.status, 'ok');
      expect(match.team, isNotNull);
      expect(match.team!.id, 't1');
      expect(match.team!.name, 'The Boys');
      expect(match.team!.isApproved, isTrue);
      expect(match.team!.codeWaivesPayment, isTrue);
    });

    test('codeWaivesPayment defaults to false when absent', () {
      final match = joinCodeMatchFromCallable({
        'found': true,
        'status': 'ok',
        'teamId': 't1',
        'teamName': 'The Boys',
      });
      expect(match.team!.codeWaivesPayment, isFalse);
    });

    test("notApproved maps to the page's awaiting-approval branch", () {
      final match = joinCodeMatchFromCallable(
          {'found': false, 'status': 'notApproved'});
      expect(match.status, 'notApproved');
      expect(match.team, isNull);
    });

    test('notFound / malformed / incomplete payloads all map to notFound',
        () {
      expect(
          joinCodeMatchFromCallable({'found': false, 'status': 'notFound'})
              .status,
          'notFound');
      expect(joinCodeMatchFromCallable(null).status, 'notFound');
      expect(joinCodeMatchFromCallable('junk').status, 'notFound');
      // 'ok' without a teamId/teamName can't drive the joiner flow.
      expect(
          joinCodeMatchFromCallable({'found': true, 'status': 'ok'}).status,
          'notFound');
    });
  });
}
