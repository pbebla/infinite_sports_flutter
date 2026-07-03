import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

void main() {
  group('kRegQuestionTypes', () {
    test('includes height', () {
      expect(kRegQuestionTypes.contains('height'), isTrue);
    });
  });

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
      expect(parsed.teamFee, 0);
      expect(parsed.feeNote, 'Due by week 1');
      expect(parsed.paymentMode, 'perPlayer');
      expect(parsed.venmo, isTrue);
      expect(parsed.zelle, isTrue);
      expect(parsed.stripe, isFalse);
      expect(parsed.createdAt, 1750000000000);
      expect(parsed.label, 'Futsal Season 17');
    });

    test('round-trips teamFee and paymentMode "both"', () {
      const config = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        status: 'open',
        fee: 20,
        teamFee: 300,
        paymentMode: 'both',
      );
      final map = config.toFirebaseMap();
      expect(map['TeamFee'], 300);
      expect(map['PaymentMode'], 'both');
      final parsed = RegistrationConfig.fromFirebase(map);
      expect(parsed!.fee, 20);
      expect(parsed.teamFee, 300);
      expect(parsed.paymentMode, 'both');
    });

    test('fromFirebase defaults an unknown PaymentMode to perPlayer', () {
      final parsed = RegistrationConfig.fromFirebase({
        'TargetType': 'league',
        'Sport': 'Futsal',
        'PaymentMode': 'nonsense',
      });
      expect(parsed!.paymentMode, 'perPlayer');
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
      expect(parsed.paidAmount, isNull);
    });

    test('toFirebaseMap omits PaidAmount when null', () {
      const sub = RegSubmission(path: 'individual', answers: {});
      expect(sub.toFirebaseMap().containsKey('PaidAmount'), isFalse);
    });

    test('round-trips PaidAmount when set', () {
      const sub = RegSubmission(
        path: 'captain',
        answers: {},
        paid: true,
        paidVia: 'card',
        paidAmount: 300,
      );
      final map = sub.toFirebaseMap();
      expect(map['PaidAmount'], 300);
      final parsed = RegSubmission.fromFirebase(map);
      expect(parsed!.paidAmount, 300);
      expect(parsed.paidVia, 'card');
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
        teamFee: 500,
        paymentMode: 'perPlayer');
    const teamFee = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 120,
        teamFee: 500,
        paymentMode: 'teamFee');
    const both = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 120,
        teamFee: 500,
        paymentMode: 'both');
    const free = RegistrationConfig(
        targetType: 'league', sport: 'Futsal', season: '17', fee: 0);

    RegSubmission sub(String path, {bool paid = false}) =>
        RegSubmission(path: path, answers: const {}, paid: paid);

    test('paid submission owes nothing', () {
      expect(
          paymentOwed(config: perPlayer, submission: sub('individual', paid: true)),
          isFalse);
    });

    test('zero fee owes nothing', () {
      expect(paymentOwed(config: free, submission: sub('individual')), isFalse);
    });

    group('individual', () {
      test('owes fee under perPlayer', () {
        expect(paymentOwed(config: perPlayer, submission: sub('individual')),
            isTrue);
      });

      test('owes nothing under teamFee', () {
        expect(paymentOwed(config: teamFee, submission: sub('individual')),
            isFalse);
      });

      test('owes fee under both', () {
        expect(
            paymentOwed(config: both, submission: sub('individual')), isTrue);
      });
    });

    group('captain', () {
      test('owes nothing under perPlayer', () {
        expect(paymentOwed(config: perPlayer, submission: sub('captain')),
            isFalse);
      });

      test('owes teamFee under teamFee', () {
        expect(
            paymentOwed(config: teamFee, submission: sub('captain')), isTrue);
      });

      test('owes teamFee under both', () {
        expect(paymentOwed(config: both, submission: sub('captain')), isTrue);
      });

      test('owes nothing when teamFee is 0', () {
        const noTeamFee = RegistrationConfig(
            targetType: 'league',
            sport: 'Futsal',
            season: '17',
            fee: 120,
            paymentMode: 'both');
        expect(paymentOwed(config: noTeamFee, submission: sub('captain')),
            isFalse);
      });
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

  group('RegTemplate', () {
    test('fromNode parses legacy flat-List shape as "Default"', () {
      final node = [
        {'key': 'firstName', 'type': 'shortText', 'label': 'First Name'},
        {'key': 'age', 'type': 'number', 'label': 'Age'},
      ];
      final template = RegTemplate.fromNode('default', node);
      expect(template.id, 'default');
      expect(template.name, 'Default');
      expect(template.questions.map((q) => q.key).toList(),
          ['firstName', 'age']);
    });

    test('fromNode parses legacy index-keyed Map shape as "Default"', () {
      final node = {
        '0': {'key': 'firstName', 'type': 'shortText', 'label': 'First Name'},
      };
      final template = RegTemplate.fromNode('default', node);
      expect(template.name, 'Default');
      expect(template.questions.single.key, 'firstName');
    });

    test('fromNode / toMap round-trip the new named shape', () {
      const template = RegTemplate(
        id: 'tpl1',
        name: 'Adult league',
        questions: [
          RegQuestion(key: 'firstName', type: 'shortText', label: 'First Name'),
          RegQuestion(key: 'ht', type: 'height', label: 'Height'),
        ],
      );
      final map = template.toMap();
      expect(map['Name'], 'Adult league');
      final parsed = RegTemplate.fromNode('tpl1', map);
      expect(parsed.id, 'tpl1');
      expect(parsed.name, 'Adult league');
      expect(parsed.questions.map((q) => q.key).toList(), ['firstName', 'ht']);
      expect(parsed.questions.last.type, 'height');
    });

    test('fromNode on null/junk gives an empty "Default" template', () {
      final template = RegTemplate.fromNode('default', null);
      expect(template.name, 'Default');
      expect(template.questions, isEmpty);
    });

    test('copyWith overrides only the given fields', () {
      const template =
          RegTemplate(id: 'tpl1', name: 'Original', questions: []);
      final renamed = template.copyWith(name: 'Renamed');
      expect(renamed.id, 'tpl1');
      expect(renamed.name, 'Renamed');
      expect(renamed.questions, isEmpty);
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

  group('RegTeam', () {
    test('round-trips through toFirebaseMap/fromNode', () {
      const team = RegTeam(
        id: 'team1',
        name: 'Red Dragons',
        captainUid: 'cap-uid',
        status: 'approved',
        joinCode: 'ABC234',
        codeWaivesPayment: true,
        createdAt: 1750000000000,
      );
      final parsed = RegTeam.fromNode('team1', team.toFirebaseMap());
      expect(parsed, isNotNull);
      expect(parsed!.id, 'team1');
      expect(parsed.name, 'Red Dragons');
      expect(parsed.captainUid, 'cap-uid');
      expect(parsed.status, 'approved');
      expect(parsed.isApproved, isTrue);
      expect(parsed.joinCode, 'ABC234');
      expect(parsed.codeWaivesPayment, isTrue);
      expect(parsed.createdAt, 1750000000000);
    });

    test('defaults: new team is pending, no code, no waive', () {
      const team = RegTeam(id: 't', name: 'X', captainUid: 'u');
      expect(team.isPending, isTrue);
      expect(team.isApproved, isFalse);
      expect(team.isRejected, isFalse);
      expect(team.joinCode, '');
      expect(team.codeWaivesPayment, isFalse);
      final map = team.toFirebaseMap();
      expect(map.containsKey('JoinCode'), isFalse); // omitted while empty
    });

    test('fromNode rejects junk', () {
      expect(RegTeam.fromNode('t', null), isNull);
      expect(RegTeam.fromNode('t', 'garbage'), isNull);
      expect(RegTeam.fromNode('t', {'CaptainUid': 'u'}), isNull); // no Name
      expect(RegTeam.fromNode('', {'Name': 'X'}), isNull); // no id
    });

    test('fromNode defaults a bad status to pending', () {
      final parsed =
          RegTeam.fromNode('t', {'Name': 'X', 'Status': 'vaporized'});
      expect(parsed!.status, 'pending');
    });

    test('copyWith overrides only the given fields', () {
      const team = RegTeam(id: 't', name: 'X', captainUid: 'u');
      final approved = team.copyWith(status: 'approved', joinCode: 'ZZZZ99');
      expect(approved.id, 't');
      expect(approved.name, 'X');
      expect(approved.status, 'approved');
      expect(approved.joinCode, 'ZZZZ99');
      expect(approved.codeWaivesPayment, isFalse);
    });
  });

  group('regTeamsFromNode', () {
    test('parses a map of teams, skipping malformed entries', () {
      final node = {
        'a': {'Name': 'Team A', 'CaptainUid': 'u1'},
        'bad': 'garbage',
        'b': {'Name': 'Team B', 'CaptainUid': 'u2', 'Status': 'approved'},
      };
      final teams = regTeamsFromNode(node);
      expect(teams.keys.toSet(), {'a', 'b'});
      expect(teams['a']!.isPending, isTrue);
      expect(teams['b']!.isApproved, isTrue);
    });

    test('null / junk gives an empty map', () {
      expect(regTeamsFromNode(null), isEmpty);
      expect(regTeamsFromNode('x'), isEmpty);
      expect(regTeamsFromNode([1, 2]), isEmpty);
    });
  });

  group('cleanTeamName', () {
    test('collapses whitespace and capitalizes words', () {
      expect(cleanTeamName('  the   boys '), 'The Boys');
      expect(cleanTeamName('LA galaxy'), 'LA Galaxy'); // capitals preserved
      expect(cleanTeamName('   '), '');
    });
  });

  group('join codes', () {
    test('alphabet is confusable-free', () {
      expect(kJoinCodeAlphabet.contains('I'), isFalse);
      expect(kJoinCodeAlphabet.contains('O'), isFalse);
      expect(kJoinCodeAlphabet.contains('0'), isFalse);
      expect(kJoinCodeAlphabet.contains('1'), isFalse);
      expect(kJoinCodeAlphabet.length, 32);
    });

    test('generateJoinCode makes 6-char codes from the alphabet', () {
      final rand = Random(42);
      for (var i = 0; i < 100; i++) {
        final code = generateJoinCode(rand);
        expect(code.length, 6);
        for (final ch in code.split('')) {
          expect(kJoinCodeAlphabet.contains(ch), isTrue,
              reason: '$ch not in alphabet');
        }
      }
    });

    test('generateJoinCode honors length', () {
      expect(generateJoinCode(Random(1), length: 8).length, 8);
    });

    test('generateUniqueJoinCode skips taken codes', () {
      // Same seed => the first internal attempt IS `first`; it must be
      // skipped and a different code returned.
      final first = generateJoinCode(Random(7));
      final unique = generateUniqueJoinCode(Random(7), {first});
      expect(unique, isNot(first));
      expect(unique.length, 6);
    });

    test('normalizeJoinCode uppercases and trims', () {
      expect(normalizeJoinCode('  abC234 '), 'ABC234');
    });

    test('validateJoinCode enforces length, charset, uniqueness', () {
      expect(validateJoinCode('ABC234'), isNull);
      expect(validateJoinCode('abc234'), isNull); // normalized first
      expect(validateJoinCode('AB'), isNotNull); // too short
      expect(validateJoinCode('ABCDEFGHJKLMN'), isNotNull); // 13 chars
      expect(validateJoinCode('ABC 23'), isNotNull); // space
      expect(validateJoinCode('ABC234', taken: {'abc234'}), isNotNull);
      expect(validateJoinCode('ABC234', taken: {'XYZ789'}), isNull);
    });
  });

  group('matchJoinCode', () {
    const approved = RegTeam(
        id: 'a',
        name: 'Approved FC',
        captainUid: 'u1',
        status: 'approved',
        joinCode: 'GOOD22');
    const pending = RegTeam(
        id: 'p',
        name: 'Pending FC',
        captainUid: 'u2',
        status: 'pending',
        joinCode: 'WAIT33');
    final teams = {'a': approved, 'p': pending};

    test('finds an approved team case-insensitively', () {
      final m = matchJoinCode(teams, ' good22 ');
      expect(m.status, 'ok');
      expect(m.team!.id, 'a');
    });

    test('flags a non-approved team as notApproved', () {
      final m = matchJoinCode(teams, 'WAIT33');
      expect(m.status, 'notApproved');
      expect(m.team!.id, 'p');
    });

    test('unknown or empty input is notFound', () {
      expect(matchJoinCode(teams, 'NOPE99').status, 'notFound');
      expect(matchJoinCode(teams, '').status, 'notFound');
      expect(matchJoinCode(const {}, 'GOOD22').status, 'notFound');
    });

    test('an approved team wins over a pending one holding the same code', () {
      const shadow = RegTeam(
          id: 's',
          name: 'Shadow',
          captainUid: 'u3',
          status: 'pending',
          joinCode: 'GOOD22');
      final m = matchJoinCode({'s': shadow, 'a': approved}, 'GOOD22');
      expect(m.status, 'ok');
      expect(m.team!.id, 'a');
    });
  });

  group('hasDuplicateTeamName', () {
    final teams = {
      'a': const RegTeam(id: 'a', name: 'Red Dragons', captainUid: 'u1'),
      'b': const RegTeam(id: 'b', name: 'red dragons ', captainUid: 'u2'),
      'c': const RegTeam(id: 'c', name: 'Blue Sharks', captainUid: 'u3'),
    };

    test('true when another team shares the name (case/space-insensitive)',
        () {
      expect(hasDuplicateTeamName(teams, 'a', 'Red Dragons'), isTrue);
    });

    test('false when the name is unique (own entry ignored)', () {
      expect(hasDuplicateTeamName(teams, 'c', 'Blue Sharks'), isFalse);
    });
  });

  group('amountOwed', () {
    const both = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 20,
        teamFee: 300,
        paymentMode: 'both');
    const teamFee = RegistrationConfig(
        targetType: 'league',
        sport: 'Futsal',
        season: '17',
        fee: 20,
        teamFee: 300,
        paymentMode: 'teamFee');

    RegSubmission sub(String path, {bool paid = false}) =>
        RegSubmission(path: path, answers: const {}, paid: paid);

    test('captain owes the TEAM fee, not the player fee', () {
      expect(amountOwed(config: both, submission: sub('captain')), 300);
      expect(amountOwed(config: teamFee, submission: sub('captain')), 300);
    });

    test('individual owes the player fee under perPlayer/both, 0 under teamFee',
        () {
      expect(amountOwed(config: both, submission: sub('individual')), 20);
      expect(amountOwed(config: teamFee, submission: sub('individual')), 0);
    });

    test('joiner owes the player fee unless the code waives it', () {
      expect(amountOwed(config: teamFee, submission: sub('joiner')), 20);
      expect(
          amountOwed(
              config: teamFee,
              submission: sub('joiner'),
              codeWaivesPayment: true),
          0);
    });

    test('anything already paid owes 0', () {
      expect(
          amountOwed(config: both, submission: sub('captain', paid: true)), 0);
    });
  });
}
