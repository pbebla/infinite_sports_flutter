// Way back fix round, Minor 1: ONE chip decision for the status page's top
// chip and the registration list's chip, so they can never disagree.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

RegistrationConfig _config(
        {num fee = 60, num teamFee = 0, String mode = 'perPlayer'}) =>
    RegistrationConfig(
      targetType: 'league',
      sport: 'Futsal',
      season: '16',
      status: 'open',
      fee: fee,
      teamFee: teamFee,
      paymentMode: mode,
    );

const _individual = RegSubmission(path: 'individual', answers: {});

void main() {
  test('paid / paid via team code', () {
    expect(
        registrationChipFor(
                config: _config(),
                submission: const RegSubmission(
                    path: 'individual', answers: {}, paid: true))
            .kind,
        RegistrationChipKind.paid);
    final c = registrationChipFor(
        config: _config(),
        submission: const RegSubmission(
            path: 'joiner', answers: {}, paid: true, paidVia: 'team code'));
    expect(c.label, 'Paid via team code');
    expect(c.settled, isTrue);
  });

  test('owing: pending, with the amount', () {
    final c = registrationChipFor(config: _config(), submission: _individual);
    expect(c.kind, RegistrationChipKind.pending);
    expect(c.label, 'Payment pending');
    expect(c.owed, 60);
    expect(c.settled, isFalse);
  });

  test('a fee owed but discounted to 0: covered', () {
    final c = registrationChipFor(
        config: _config(),
        submission: const RegSubmission(
            path: 'individual',
            answers: {},
            adjustedFee: 0,
            discountSource: 'manual'));
    expect(c.kind, RegistrationChipKind.covered);
    expect(c.label, 'Covered');
  });

  test(
      'free registration (fee 0): the status page says Payment pending, '
      'and so does the list (never a green Covered)', () {
    final c =
        registrationChipFor(config: _config(fee: 0), submission: _individual);
    expect(c.kind, RegistrationChipKind.pending);
    expect(c.label, 'Payment pending');
    expect(c.owed, 0);
  });

  test('an individual when only a team fee is charged: Payment pending', () {
    final c = registrationChipFor(
        config: _config(fee: 0, teamFee: 200, mode: 'teamFee'),
        submission: _individual);
    expect(c.kind, RegistrationChipKind.pending);
  });

  test('a team-code waiver counts (joiner)', () {
    final c = registrationChipFor(
        config: _config(),
        submission: const RegSubmission(path: 'joiner', answers: {}),
        codeWaivesPayment: true);
    expect(c.owed, 0);
    expect(c.kind, RegistrationChipKind.pending,
        reason: 'paymentOwed is false: same as the status page today');
  });
}
