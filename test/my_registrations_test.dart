// "My registration" way back (owner-approved 2026-11-14): the fan's own
// registrations, open OR closed, from the public config mirror (which keeps
// closed registrations: functions/src/lib/public_mirrors.ts copies Config
// verbatim whatever its Status) plus the fan's own
// Registrations/<regId>/Submissions/<uid> — both readable by the fan under
// both rules files. Firebase-free: the sources are seamed.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

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
}
