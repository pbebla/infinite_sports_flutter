// "An error is not a fact" for the registration callables
// (lib/registration/registration_service.dart): a FAILED resolveJoinCode /
// checkFirstTimer call must come back as a distinct error outcome — never as
// "that code doesn't exist" or "you're a first-timer". Firebase-free via
// RegistrationService.callableOverride.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

void main() {
  tearDown(() => RegistrationService.callableOverride = null);

  group('resolveJoinCode', () {
    test('a failing callable is an error outcome, not notFound', () async {
      RegistrationService.callableOverride =
          (name, data) async => throw Exception('unavailable');
      final match = await RegistrationService.resolveJoinCode(
          regId: 'Futsal-17', code: 'ABC234');
      expect(match.status, 'error');
      expect(match.team, isNull);
    });

    test('a real not-found answer stays notFound', () async {
      RegistrationService.callableOverride = (name, data) async {
        expect(name, 'resolveJoinCode');
        return {'found': false, 'status': 'notFound'};
      };
      final match = await RegistrationService.resolveJoinCode(
          regId: 'Futsal-17', code: 'ZZZ999');
      expect(match.status, 'notFound');
    });

    test('an approved answer still resolves the team', () async {
      RegistrationService.callableOverride = (name, data) async => {
            'found': true,
            'status': 'ok',
            'teamId': 't1',
            'teamName': 'The Boys',
            'codeWaivesPayment': false,
          };
      final match = await RegistrationService.resolveJoinCode(
          regId: 'Futsal-17', code: 'ABC234');
      expect(match.status, 'ok');
      expect(match.team!.name, 'The Boys');
    });
  });

  group('checkFirstTimer', () {
    test('a failing callable is NOT a first-timer and is flagged unverified',
        () async {
      RegistrationService.callableOverride =
          (name, data) async => throw Exception('deadline-exceeded');
      final result = await RegistrationService.checkFirstTimer(
          email: 'a***@example.com', phone: '');
      expect(result.isFirstTimer, isFalse);
      expect(result.checkFailed, isTrue);
    });

    test('a successful first-timer answer is unchanged', () async {
      RegistrationService.callableOverride = (name, data) async {
        expect(name, 'checkFirstTimer');
        return {'isFirstTimer': true};
      };
      final result = await RegistrationService.checkFirstTimer(
          email: 'a***@example.com', phone: '');
      expect(result.isFirstTimer, isTrue);
      expect(result.checkFailed, isFalse);
    });

    test('a successful returning-player answer is unchanged', () async {
      RegistrationService.callableOverride = (name, data) async =>
          {'isFirstTimer': false, 'matchedByEmail': true};
      final result = await RegistrationService.checkFirstTimer(
          email: 'a***@example.com', phone: '');
      expect(result.isFirstTimer, isFalse);
      expect(result.matchedByEmail, isTrue);
      expect(result.checkFailed, isFalse);
    });
  });
}
