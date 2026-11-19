// Fresh reads, Task 3 — profile write-backs (survey list A #6: #75
// registration prefill → _writeBackProfile; #57/#60 legacy LeagueForm
// prefill → addUpdateInfo). The prefill comes from a read that may be the
// phone's saved copy, so the write-back only writes the fields the fan
// actually changed: an untouched (maybe stale) value is never written back
// over a newer one set by the Manager or another device.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/userinformation.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';

void main() {
  group('registration write-back (#75)', () {
    const prefill = {
      'firstName': 'Sam',
      'lastName': 'Lee',
      'phone': '4085550000',
      'age': '20',
      'height': "5'10",
      'positions': ['Defender'],
    };

    test('untouched prefilled answers write nothing', () {
      final w = profileWriteBack(
          sport: 'Futsal',
          answers: Map<String, dynamic>.from(prefill),
          prefill: prefill);
      expect(w.root, isEmpty);
      expect(w.info, isEmpty);
    });

    test('only the changed fields are written', () {
      final w = profileWriteBack(
          sport: 'Futsal',
          answers: {
            ...prefill,
            'phone': '(408) 555-1111',
            'positions': ['Defender', 'Striker'],
          },
          prefill: prefill);
      expect(w.root, {'Phone Number': '4085551111'});
      expect(w.info, {'FutsalPosition': 'Defender;Striker'});
    });

    test('a phone typed in a different format is not a change', () {
      final w = profileWriteBack(
          sport: 'Futsal',
          answers: {...prefill, 'phone': '(408) 555-0000'},
          prefill: prefill);
      expect(w.root, isEmpty);
    });

    test('a field the profile did not have is written (as before)', () {
      final w = profileWriteBack(
          sport: 'Futsal',
          answers: {'firstName': 'Ana', 'age': '19'},
          prefill: const {});
      expect(w.root, {'First Name': 'Ana'});
      expect(w.info, {'Age': 19});
    });
  });

  group('legacy LeagueForm write-back (#57, #60)', () {
    UserInformation info(
        {int age = 20,
        String height = "5'10",
        String futsal = 'Defender',
        String basketball = 'Center'}) {
      final i = UserInformation();
      i.age = age;
      i.height = height;
      i.futsalPosition = futsal;
      i.basketballPosition = basketball;
      return i;
    }

    test('unchanged answers write nothing', () {
      final c = legacyInfoChanges(
          sport: 'Futsal',
          before: info(),
          after: info(),
          phoneBefore: '4085550000',
          phoneAfter: '4085550000');
      expect(c.info, isEmpty);
      expect(c.phone, isNull);
    });

    test(
        'only changed fields; the other sport\'s position is never written '
        'back from the (maybe stale) prefill', () {
      final c = legacyInfoChanges(
          sport: 'Futsal',
          before: info(),
          after: info(age: 21, futsal: 'Striker', basketball: 'OLD'),
          phoneBefore: '4085550000',
          phoneAfter: '4085551111');
      expect(c.info, {'Age': 21, 'FutsalPosition': 'Striker'});
      expect(c.phone, '4085551111');
    });

    test('Basketball writes BasketballPosition only', () {
      final c = legacyInfoChanges(
          sport: 'Basketball',
          before: info(),
          after: info(basketball: 'Point Guard'),
          phoneBefore: '',
          phoneAfter: '');
      expect(c.info, {'BasketballPosition': 'Point Guard'});
    });
  });
}
