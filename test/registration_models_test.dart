import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

void main() {
  group('RegQuestion (de)serialization', () {
    test('round-trips through toMap/fromMap', () {
      const q = RegQuestion(
        key: 'positions',
        type: 'multiChoice',
        label: 'Positions',
        isRequired: true,
        visibility: 'individual',
        options: ['Defender', 'Striker'],
        hint: 'Pick all that apply',
      );
      final parsed = RegQuestion.fromMap(q.toMap());
      expect(parsed, isNotNull);
      expect(parsed!.key, 'positions');
      expect(parsed.type, 'multiChoice');
      expect(parsed.label, 'Positions');
      expect(parsed.isRequired, isTrue);
      expect(parsed.visibility, 'individual');
      expect(parsed.options, ['Defender', 'Striker']);
      expect(parsed.hint, 'Pick all that apply');
    });

    test('toMap omits empty options/hint, stores isRequired as "required"', () {
      const q = RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name');
      final map = q.toMap();
      expect(map.containsKey('options'), isFalse);
      expect(map.containsKey('hint'), isFalse);
      expect(map['required'], isFalse);
    });

    test('fromMap rejects malformed nodes', () {
      expect(RegQuestion.fromMap(null), isNull);
      expect(RegQuestion.fromMap('garbage'), isNull);
      expect(RegQuestion.fromMap({'type': 'shortText'}), isNull); // no key
      expect(RegQuestion.fromMap({'key': 'x', 'type': 'hologram'}), isNull); // bad type
    });

    test('fromMap defaults bad visibility to all, missing label to key', () {
      final q = RegQuestion.fromMap(
          {'key': 'x', 'type': 'shortText', 'visibility': 'martians'});
      expect(q!.visibility, 'all');
      expect(q.label, 'x');
      expect(q.isRequired, isFalse);
    });
  });

  group('visibleFor', () {
    test('all is visible to every path', () {
      const q = RegQuestion(key: 'x', type: 'shortText', label: 'X');
      expect(q.visibleFor('individual'), isTrue);
      expect(q.visibleFor('captain'), isTrue);
      expect(q.visibleFor('joiner'), isTrue);
    });

    test('path-scoped question only shows on its path', () {
      const q = RegQuestion(
          key: 'x', type: 'shortText', label: 'X', visibility: 'captain');
      expect(q.visibleFor('captain'), isTrue);
      expect(q.visibleFor('individual'), isFalse);
      expect(q.visibleFor('joiner'), isFalse);
    });
  });

  group('regQuestionsFromNode / regQuestionsToList', () {
    test('parses a List node in order, skipping malformed entries', () {
      final node = [
        {'key': 'a', 'type': 'shortText', 'label': 'A'},
        'garbage',
        {'key': 'b', 'type': 'yesNo', 'label': 'B'},
      ];
      final list = regQuestionsFromNode(node);
      expect(list.map((q) => q.key).toList(), ['a', 'b']);
    });

    test('parses an index-keyed Map node in numeric order', () {
      final node = {
        '10': {'key': 'late', 'type': 'shortText', 'label': 'Late'},
        '2': {'key': 'early', 'type': 'shortText', 'label': 'Early'},
      };
      expect(regQuestionsFromNode(node).map((q) => q.key).toList(),
          ['early', 'late']);
    });

    test('null / junk gives empty list', () {
      expect(regQuestionsFromNode(null), isEmpty);
      expect(regQuestionsFromNode('x'), isEmpty);
    });

    test('default template round-trips through regQuestionsToList', () {
      final round =
          regQuestionsFromNode(regQuestionsToList(kDefaultRegQuestions.toList()));
      expect(round.length, kDefaultRegQuestions.length);
      expect(round.first.key, 'firstName');
      expect(round.last.type, 'linkAcknowledge');
    });
  });

  group('input hygiene', () {
    test('capitalizeWords uppercases the first letter of each word', () {
      expect(capitalizeWords('john doe'), 'John Doe');
      expect(capitalizeWords('mary-jane o brien'), 'Mary-jane O Brien');
      expect(capitalizeWords(''), '');
    });

    test('collapseTrailingSpaces trims and collapses whitespace runs', () {
      expect(collapseTrailingSpaces('  john   doe  '), 'john doe');
      expect(collapseTrailingSpaces('one\t two'), 'one two');
    });

    test('normalizePhone keeps digits only', () {
      expect(normalizePhone('(408) 693-9436'), '4086939436');
      expect(normalizePhone('+1 408.693.9436'), '14086939436');
    });

    test('formatPhone renders 10 and 1+10 digit numbers, passes junk through', () {
      expect(formatPhone('4086939436'), '(408) 693-9436');
      expect(formatPhone('14086939436'), '(408) 693-9436');
      expect(formatPhone('123'), '123');
      expect(formatPhone(''), '');
    });

    test('suggestKeyFromLabel camelCases labels', () {
      expect(suggestKeyFromLabel('First Name'), 'firstName');
      expect(suggestKeyFromLabel('T-Shirt  Size!'), 'tshirtSize');
      expect(suggestKeyFromLabel('  '), '');
    });

    test('cleanAnswers applies type-aware hygiene and drops nulls', () {
      final questions = [
        const RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
        const RegQuestion(key: 'comment', type: 'paragraph', label: 'Comment'),
        const RegQuestion(key: 'phone', type: 'phone', label: 'Phone'),
        const RegQuestion(key: 'age', type: 'number', label: 'Age'),
        const RegQuestion(key: 'birthday', type: 'date', label: 'Birthday'),
        const RegQuestion(key: 'waiver', type: 'linkAcknowledge', label: 'Waiver'),
      ];
      final cleaned = cleanAnswers(questions, {
        'firstName': '  john   doe ',
        'comment': '  keep Case here  ',
        'phone': '(408) 693-9436',
        'age': '25',
        'birthday': DateTime(2001, 3, 7),
        'waiver': true,
        'skipped': null,
      });
      expect(cleaned['firstName'], 'John Doe');
      expect(cleaned['comment'], 'keep Case here');
      expect(cleaned['phone'], '4086939436');
      expect(cleaned['age'], 25);
      expect(cleaned['birthday'], '03/07/2001');
      expect(cleaned['waiver'], true);
      expect(cleaned.containsKey('skipped'), isFalse);
    });
  });

  group('RegistrationConfig', () {
    test('round-trips league config through toFirebaseMap/fromFirebase', () {
      const config = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        status: 'open',
        fee: 120,
        feeNote: 'Due by week 1',
        paymentMode: 'perPlayer',
        venmo: true,
        zelle: true,
        stripe: false,
        createdAt: 1750000000000,
      );
      final parsed = RegistrationConfig.fromFirebase(config.toFirebaseMap());
      expect(parsed, isNotNull);
      expect(parsed!.targetType, 'league');
      expect(parsed.sport, 'Futsal');
      expect(parsed.season, '17');
      expect(parsed.isOpen, isTrue);
      expect(parsed.fee, 120);
      expect(parsed.feeNote, 'Due by week 1');
      expect(parsed.paymentMode, 'perPlayer');
      expect(parsed.venmo, isTrue);
      expect(parsed.zelle, isTrue);
      expect(parsed.stripe, isFalse);
      expect(parsed.createdAt, 1750000000000);
      expect(parsed.label, 'Futsal Season 17');
    });

    test('round-trips tournament config; label uses tournament name', () {
      const config = RegistrationConfig(
        targetType: 'tournament',
        sport: 'Soccer',
        tournamentId: 'summer-cup-2026',
        tournamentName: 'Summer Cup',
        status: 'closed',
        fee: 250,
        paymentMode: 'teamFee',
      );
      final parsed = RegistrationConfig.fromFirebase(config.toFirebaseMap());
      expect(parsed!.tournamentId, 'summer-cup-2026');
      expect(parsed.tournamentName, 'Summer Cup');
      expect(parsed.isOpen, isFalse);
      expect(parsed.paymentMode, 'teamFee');
      expect(parsed.label, 'Summer Cup');
    });

    test('fromFirebase rejects junk and unknown target types', () {
      expect(RegistrationConfig.fromFirebase(null), isNull);
      expect(RegistrationConfig.fromFirebase('x'), isNull);
      expect(RegistrationConfig.fromFirebase({'TargetType': 'raffle'}), isNull);
    });

    test('regIds', () {
      expect(leagueRegId('Futsal', '17'), 'Futsal-17');
      expect(tournamentRegId('summer-cup'), 'T-summer-cup');
      const league = RegistrationConfig(
          targetType: 'league', sport: 'Basketball', season: '9');
      const tourney = RegistrationConfig(
          targetType: 'tournament', sport: 'Soccer', tournamentId: 'cup1');
      expect(regIdFor(league), 'Basketball-9');
      expect(regIdFor(tourney), 'T-cup1');
    });

    test('legacySignUpTarget: league keeps Sport/Season; tournament uses name/id', () {
      const league = RegistrationConfig(
          targetType: 'league', sport: 'Futsal', season: '17');
      expect(legacySignUpTarget(league), (league: 'Futsal', season: '17'));
      const tourney = RegistrationConfig(
          targetType: 'tournament',
          sport: 'Soccer',
          tournamentId: 'cup1',
          tournamentName: 'Summer Cup');
      expect(legacySignUpTarget(tourney), (league: 'Summer Cup', season: 'cup1'));
      const anon = RegistrationConfig(
          targetType: 'tournament', sport: 'Soccer', tournamentId: 'cup1');
      expect(legacySignUpTarget(anon).league, 'cup1');
    });
  });

  group('RegSubmission', () {
    test('round-trips through toFirebaseMap/fromFirebase', () {
      const sub = RegSubmission(
        path: 'individual',
        answers: {'firstName': 'John', 'positions': ['Striker']},
        paid: false,
        displayName: 'John Doe',
        submittedAt: 1750000000000,
      );
      final parsed = RegSubmission.fromFirebase(sub.toFirebaseMap());
      expect(parsed!.path, 'individual');
      expect(parsed.answers['firstName'], 'John');
      expect(parsed.paid, isFalse);
      expect(parsed.displayName, 'John Doe');
      expect(parsed.submittedAt, 1750000000000);
      expect(parsed.teamId, '');
      expect(parsed.paidVia, '');
    });

    test('fromFirebase rejects junk', () {
      expect(RegSubmission.fromFirebase(null), isNull);
      expect(RegSubmission.fromFirebase({'Answers': {}}), isNull); // no Path
    });
  });

  group('paymentOwed', () {
    const perPlayer = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 120,
        paymentMode: 'perPlayer');
    const teamFee = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 500,
        paymentMode: 'teamFee');
    const free = RegistrationConfig(
        targetType: 'league', sport: 'Futsal', season: '17', fee: 0);

    RegSubmission sub(String path, {bool paid = false}) =>
        RegSubmission(path: path, answers: const {}, paid: paid);

    test('unpaid individual owes in both modes', () {
      expect(paymentOwed(config: perPlayer, submission: sub('individual')), isTrue);
      expect(paymentOwed(config: teamFee, submission: sub('individual')), isTrue);
    });

    test('paid submission owes nothing', () {
      expect(
          paymentOwed(config: perPlayer, submission: sub('individual', paid: true)),
          isFalse);
    });

    test('zero fee owes nothing', () {
      expect(paymentOwed(config: free, submission: sub('individual')), isFalse);
    });

    test('captain owes in both modes', () {
      expect(paymentOwed(config: perPlayer, submission: sub('captain')), isTrue);
      expect(paymentOwed(config: teamFee, submission: sub('captain')), isTrue);
    });

    test('joiner follows CodeWaivesPayment', () {
      expect(
          paymentOwed(
              config: teamFee, submission: sub('joiner'), codeWaivesPayment: true),
          isFalse);
      expect(
          paymentOwed(
              config: teamFee, submission: sub('joiner'), codeWaivesPayment: false),
          isTrue);
      expect(
          paymentOwed(
              config: perPlayer, submission: sub('joiner'), codeWaivesPayment: true),
          isFalse);
    });
  });

  group('positionsFieldForSport', () {
    test('maps sports to Information fields', () {
      expect(positionsFieldForSport('Futsal'), 'FutsalPosition');
      expect(positionsFieldForSport('Soccer'), 'FutsalPosition');
      expect(positionsFieldForSport('Basketball'), 'BasketballPosition');
      expect(positionsFieldForSport('Flag Football'), 'FlagFootballPosition');
      expect(positionsFieldForSport('Cricket'), '');
    });
  });
}
