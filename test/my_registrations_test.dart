// "My registration" way back (owner-approved 2026-11-14): the fan's own
// registrations, open OR closed, from the public config mirror (which keeps
// closed registrations: functions/src/lib/public_mirrors.ts copies Config
// verbatim whatever its Status) plus the fan's own
// Registrations/<regId>/Submissions/<uid> — both readable by the fan under
// both rules files. Firebase-free: the sources are seamed.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart'
    as models show allRegistrationsFromNode;

RegistrationConfig _config(String status, {num fee = 60}) => RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: status,
      fee: fee,
      paymentMode: 'perPlayer',
    );

void main() {
  late StreamController<Map<String, RegistrationConfig>> configs;
  late Map<String, StreamController<RegSubmission?>> subs;

  setUp(() {
    configs = StreamController<Map<String, RegistrationConfig>>();
    subs = {};
  });

  Stream<MyRegistrations> watch(
          {String? uid = 'u1', Duration bound = const Duration(seconds: 8)}) =>
      watchMyRegistrations(
        uidOf: () => uid,
        firstAnswerBound: bound,
        configs: () => configs.stream,
        submissionFor: (regId) => subs
            .putIfAbsent(regId, () => StreamController<RegSubmission?>())
            .stream,
      );

  test('one answer only after the configs AND every own submission answered',
      () async {
    final out = <MyRegistrations>[];
    final sub = watch().listen(out.add);
    configs.add({'a': _config('open'), 'b': _config('closed')});
    await Future<void>.delayed(Duration.zero);
    expect(out, isEmpty, reason: 'submissions not answered yet: no pop-in');
    subs['a']!.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(out, isEmpty);
    subs['b']!.add(const RegSubmission(path: 'individual', answers: {}));
    await Future<void>.delayed(Duration.zero);
    expect(out, hasLength(1));
    expect(out.single.mine.map((m) => m.regId), ['b'],
        reason: 'a CLOSED registration with my submission is mine');
    expect(out.single.openForSignUp.keys, ['a']);
    await sub.cancel();
  });

  test('an open registration I registered for is listed once, under mine',
      () async {
    final out = <MyRegistrations>[];
    final sub = watch().listen(out.add);
    configs.add({'a': _config('open')});
    await Future<void>.delayed(Duration.zero);
    subs['a']!.add(const RegSubmission(path: 'individual', answers: {}));
    await Future<void>.delayed(Duration.zero);
    expect(out.last.mine.single.regId, 'a');
    expect(out.last.openForSignUp, isEmpty);
    await sub.cancel();
  });

  test('a removed registration drops out (its submission stream is closed)',
      () async {
    final out = <MyRegistrations>[];
    final sub = watch().listen(out.add);
    configs.add({'a': _config('closed')});
    await Future<void>.delayed(Duration.zero);
    subs['a']!.add(const RegSubmission(path: 'individual', answers: {}));
    await Future<void>.delayed(Duration.zero);
    expect(out.last.mine, hasLength(1));
    configs.add({});
    await Future<void>.delayed(Duration.zero);
    expect(out.last.mine, isEmpty);
    expect(subs['a']!.hasListener, isFalse);
    await sub.cancel();
  });

  test('a failed read is an error, not "no registrations"', () async {
    final errors = <Object>[];
    final sub = watch().listen((_) {}, onError: errors.add);
    configs.addError(StateError('denied'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    await sub.cancel();
  });

  test('signed out: no submissions are read, nothing is mine', () async {
    final out = <MyRegistrations>[];
    final sub = watch(uid: null).listen(out.add);
    configs.add({'a': _config('open')});
    await Future<void>.delayed(Duration.zero);
    expect(out.single.mine, isEmpty);
    expect(out.single.openForSignUp.keys, ['a']);
    expect(subs, isEmpty);
    await sub.cancel();
  });

  test('owed is the status page\'s amount (discountedAmountOwed)', () {
    const unpaid = RegSubmission(
        path: 'individual',
        answers: {},
        discountPct: 10,
        eligibleFee: 60,
        discountSource: 'first_timer_promo');
    final m = MyRegistration(
        regId: 'a', config: _config('closed'), submission: unpaid);
    expect(m.owed,
        discountedAmountOwed(config: _config('closed'), submission: unpaid));
    expect(m.owed, 54);
    expect(m.paid, isFalse);
    const paid = RegSubmission(path: 'individual', answers: {}, paid: true);
    final p =
        MyRegistration(regId: 'a', config: _config('closed'), submission: paid);
    expect(p.paid, isTrue);
    expect(p.owed, 0);
    expect(formatOwed(54), r'$54.00');
  });

  test('firstOwing picks a registration that still owes money', () {
    final regs = MyRegistrations(mine: [
      MyRegistration(
          regId: 'paid',
          config: _config('open'),
          submission:
              const RegSubmission(path: 'individual', answers: {}, paid: true)),
      MyRegistration(
          regId: 'owes',
          config: _config('closed', fee: 80),
          submission: const RegSubmission(path: 'individual', answers: {})),
    ], openForSignUp: const {});
    expect(regs.firstOwing!.regId, 'owes');
    expect(regs.firstOwing!.owed, 80);
  });

  // Way back fix round, Important 2: never a skeleton forever.
  group('bounded first answer', () {
    test(
        'no first answer within the bound: an error (could not load), '
        'still listening; a late answer then arrives as data', () async {
      final events = <Object>[];
      final sub = watch(bound: const Duration(milliseconds: 30))
          .listen(events.add, onError: events.add);
      configs.add({'a': _config('closed')});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events.single, isA<TimeoutException>());
      subs['a']!.add(const RegSubmission(path: 'individual', answers: {}));
      await Future<void>.delayed(Duration.zero);
      expect(events.last, isA<MyRegistrations>());
      expect((events.last as MyRegistrations).mine, hasLength(1));
      await sub.cancel();
    });

    test('the mirror never answering is bounded too', () async {
      final events = <Object>[];
      final sub = watch(bound: const Duration(milliseconds: 30))
          .listen(events.add, onError: events.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events.single, isA<TimeoutException>());
      await sub.cancel();
    });

    test('one submission read that fails is an error', () async {
      final errors = <Object>[];
      final sub = watch().listen((_) {}, onError: errors.add);
      configs.add({'a': _config('open'), 'b': _config('closed')});
      await Future<void>.delayed(Duration.zero);
      subs['a']!.add(null);
      subs['b']!.addError(StateError('denied'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      await sub.cancel();
    });

    test(
        'a registration added to the mirror while open is held until its '
        'submission answers (no flicker)', () async {
      final out = <MyRegistrations>[];
      final sub = watch().listen(out.add);
      configs.add({'a': _config('open')});
      await Future<void>.delayed(Duration.zero);
      subs['a']!.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(out, hasLength(1));
      configs.add({'a': _config('open'), 'b': _config('closed')});
      await Future<void>.delayed(Duration.zero);
      expect(out, hasLength(1), reason: 'held while b has not answered');
      subs['b']!.add(const RegSubmission(path: 'individual', answers: {}));
      await Future<void>.delayed(Duration.zero);
      expect(out, hasLength(2));
      expect(out.last.mine.single.regId, 'b');
      await sub.cancel();
    });

    test('closing the screen cancels every listener', () async {
      final sub = watch().listen((_) {});
      configs.add({'a': _config('open'), 'b': _config('closed')});
      await Future<void>.delayed(Duration.zero);
      expect(subs['a']!.hasListener, isTrue);
      expect(subs['b']!.hasListener, isTrue);
      await sub.cancel();
      expect(subs['a']!.hasListener, isFalse);
      expect(subs['b']!.hasListener, isFalse);
      expect(configs.hasListener, isFalse);
    });
  });

  // Way back fix round, Important 4 (ruling): the home banner and the
  // drawer's "You owe" only nag for a CURRENT registration. The list is
  // unchanged (every registration, its true chip).
  group('isCurrentRegistration / firstCurrentOwing', () {
    RegistrationConfig league(String status, String season) =>
        RegistrationConfig(
          targetType: 'league',
          sport: 'Futsal',
          season: season,
          status: status,
          fee: 60,
          paymentMode: 'perPlayer',
        );
    RegistrationConfig cup(String status, String id) => RegistrationConfig(
          targetType: 'tournament',
          sport: 'Soccer',
          tournamentId: id,
          tournamentName: 'Cup',
          status: status,
          fee: 60,
          paymentMode: 'perPlayer',
        );
    bool current(RegistrationConfig c,
            {String? pointer, Set<String>? active}) =>
        isCurrentRegistration(c, seasonPointer: (sport) {
          expect(sport, c.sport);
          return pointer;
        }, activeTournamentIds: active);

    test('open is always current (even with nothing known)', () {
      expect(current(league('open', '9')), isTrue);
      expect(current(cup('open', 't1')), isTrue);
    });

    test('Season 16 closed with pointer 16: current (nags)', () {
      expect(current(league('closed', '16'), pointer: '16'), isTrue);
    });

    test('Season 16 closed with pointer 17: not current (silent)', () {
      expect(current(league('closed', '16'), pointer: '17'), isFalse);
    });

    test('a registration for 17 closed while the pointer is 16: current', () {
      expect(current(league('closed', '17'), pointer: '16'), isTrue);
    });

    test('unknown pointer: a closed league registration is silent', () {
      expect(current(league('closed', '16'), pointer: null), isFalse);
      expect(current(league('closed', '16'), pointer: 'oops'), isFalse);
    });

    test('closed tournament: current only while it exists and is active', () {
      expect(current(cup('closed', 't1'), active: {'t1'}), isTrue);
      expect(current(cup('closed', 't1'), active: {'t2'}), isFalse);
      expect(current(cup('closed', 't1'), active: null), isFalse,
          reason: 'tournaments not known yet: never nag on a guess');
    });

    test('firstCurrentOwing skips an old owing registration', () {
      final regs = MyRegistrations(mine: [
        MyRegistration(
            regId: 'old',
            config: league('closed', '15'),
            submission: const RegSubmission(path: 'individual', answers: {})),
        MyRegistration(
            regId: 'now',
            config: league('closed', '16'),
            submission: const RegSubmission(path: 'individual', answers: {})),
      ], openForSignUp: const {});
      final pick = firstCurrentOwing(regs,
          seasonPointer: (_) => '16', activeTournamentIds: null);
      expect(pick!.regId, 'now');
      expect(
          firstCurrentOwing(regs,
              seasonPointer: (_) => '17', activeTournamentIds: null),
          isNull);
      expect(
          firstCurrentOwing(null,
              seasonPointer: (_) => '16', activeTournamentIds: null),
          isNull);
    });
  });

  test('a No charge registration is never the first current owing', () {
    final regs = MyRegistrations(mine: [
      MyRegistration(
          regId: 'now',
          config: const RegistrationConfig(
            targetType: 'league',
            sport: 'Futsal',
            season: '16',
            status: 'open',
            fee: 255,
            paymentMode: 'perPlayer',
          ),
          submission: const RegSubmission(
              path: 'individual',
              answers: {},
              paid: true,
              paidVia: 'no charge',
              paidAmount: 0)),
    ], openForSignUp: const {});
    expect(
        firstCurrentOwing(regs,
            seasonPointer: (_) => '16', activeTournamentIds: null),
        isNull);
    expect(regs.mine.single.chip.kind, RegistrationChipKind.noCharge);
  });

  // Way back fix round, Minor 2: the Manager can switch a team to "code
  // waives payment" after an unpaid member joined (setTeamWaive). The status
  // page then reads that team node; the list/banner/drawer follow the SAME
  // node (RegistrationService.watchTeam), live, inside the gate.
  group('team-code waiver for a team member', () {
    late Map<String, StreamController<RegTeam?>> teams;

    Stream<MyRegistrations> watchWithTeams() => watchMyRegistrations(
          uidOf: () => 'u1',
          configs: () => configs.stream,
          submissionFor: (regId) => subs
              .putIfAbsent(regId, () => StreamController<RegSubmission?>())
              .stream,
          teamFor: (regId, teamId) => teams
              .putIfAbsent('$regId/$teamId', () => StreamController<RegTeam?>())
              .stream,
        );

    RegTeam team({required bool waives}) => RegTeam(
        id: 't1',
        name: 'Lions',
        captainUid: 'cap',
        status: 'approved',
        codeWaivesPayment: waives);

    setUp(() => teams = {});

    test('held until the team answers; a waiver means nothing is owed',
        () async {
      final out = <MyRegistrations>[];
      final sub = watchWithTeams().listen(out.add);
      configs.add({'a': _config('closed')});
      await Future<void>.delayed(Duration.zero);
      subs['a']!
          .add(const RegSubmission(path: 'joiner', answers: {}, teamId: 't1'));
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty, reason: 'the team has not answered');
      teams['a/t1']!.add(team(waives: false));
      await Future<void>.delayed(Duration.zero);
      expect(out.last.mine.single.owed, 60);
      teams['a/t1']!.add(team(waives: true)); // the Manager waives later
      await Future<void>.delayed(Duration.zero);
      expect(out.last.mine.single.owed, 0,
          reason: 'never "You owe" where the status page says nothing');
      expect(out.last.firstOwing, isNull);
      await sub.cancel();
      expect(teams['a/t1']!.hasListener, isFalse);
    });

    test('a denied team read (target rules) is null, like the status page',
        () async {
      final out = <MyRegistrations>[];
      final sub = watchWithTeams().listen(out.add);
      configs.add({'a': _config('closed')});
      await Future<void>.delayed(Duration.zero);
      subs['a']!
          .add(const RegSubmission(path: 'joiner', answers: {}, teamId: 't1'));
      await Future<void>.delayed(Duration.zero);
      teams['a/t1']!.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(out.last.mine.single.owed, 60);
      await sub.cancel();
    });

    test('individuals and captains read no team', () async {
      final out = <MyRegistrations>[];
      final sub = watchWithTeams().listen(out.add);
      configs.add({'a': _config('open')});
      await Future<void>.delayed(Duration.zero);
      subs['a']!
          .add(const RegSubmission(path: 'captain', answers: {}, teamId: 't1'));
      await Future<void>.delayed(Duration.zero);
      expect(out, hasLength(1));
      expect(teams, isEmpty);
      await sub.cancel();
    });
  });

  // Way back fix round, Minor 5: no circular import between the service and
  // the "my registrations" file; the mirror parser lives with the models.
  group('no circular import', () {
    test('registration_service.dart does not import my_registrations.dart', () {
      final src =
          File('lib/registration/registration_service.dart').readAsStringSync();
      expect(
          RegExp(r"^import .*my_registrations\.dart'", multiLine: true)
              .hasMatch(src),
          isFalse);
    });

    test('the mirror parser lives in registration_models.dart', () {
      final all = models.allRegistrationsFromNode({
        'a': {
          'TargetType': 'league',
          'Sport': 'Futsal',
          'Season': '16',
          'Status': 'closed',
        },
        'bad': 'not a config',
      });
      expect(all.keys, ['a']);
      expect(all['a']!.status, 'closed');
    });
  });
}
