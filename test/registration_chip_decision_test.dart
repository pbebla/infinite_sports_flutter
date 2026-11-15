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

  test('free registration (fee 0): No charge, never "Payment pending"', () {
    final c =
        registrationChipFor(config: _config(fee: 0), submission: _individual);
    expect(c.kind, RegistrationChipKind.noCharge);
    expect(c.label, 'No charge');
    expect(c.owed, 0);
    expect(c.settled, isTrue);
  });

  test('an individual when only a team fee is charged: No charge', () {
    final c = registrationChipFor(
        config: _config(fee: 0, teamFee: 200, mode: 'teamFee'),
        submission: _individual);
    expect(c.kind, RegistrationChipKind.noCharge);
    final byMode = registrationChipFor(
        config: _config(mode: 'teamFee'), submission: _individual);
    expect(byMode.kind, RegistrationChipKind.noCharge);
    expect(byMode.label, 'No charge');
  });

  test('paid with No charge, fee 255: noCharge, settled, owes 0', () {
    final c = registrationChipFor(
        config: _config(fee: 255),
        submission: const RegSubmission(
            path: 'individual',
            answers: {},
            paid: true,
            paidVia: 'no charge',
            paidAmount: 0));
    expect(c.kind, RegistrationChipKind.noCharge);
    expect(c.label, 'No charge');
    expect(c.owed, 0);
    expect(c.settled, isTrue);
  });

  test('isNoCharge: paid + paidVia, trimmed and case-insensitive', () {
    expect(kPaidViaNoCharge, 'no charge');
    const base = RegSubmission(
        path: 'individual', answers: {}, paid: true, paidVia: ' No Charge ');
    expect(base.isNoCharge, isTrue);
    expect(
        const RegSubmission(
                path: 'individual', answers: {}, paidVia: 'no charge')
            .isNoCharge,
        isFalse);
    expect(
        const RegSubmission(
                path: 'individual', answers: {}, paid: true, paidVia: 'venmo')
            .isNoCharge,
        isFalse);
  });

  test('paid by venmo stays Paid', () {
    final c = registrationChipFor(
        config: _config(fee: 255),
        submission: const RegSubmission(
            path: 'individual', answers: {}, paid: true, paidVia: 'venmo'));
    expect(c.kind, RegistrationChipKind.paid);
    expect(c.label, 'Paid');
  });

  test('unpaid with a kept PaidVia "no charge" and fee 255: still pending', () {
    final c = registrationChipFor(
        config: _config(fee: 255),
        submission: const RegSubmission(
            path: 'individual', answers: {}, paidVia: 'no charge'));
    expect(c.kind, RegistrationChipKind.pending);
    expect(c.label, 'Payment pending');
    expect(c.owed, 255);
    expect(c.settled, isFalse);
  });

  test('unpaid individual, fee 255: pending, owed 255', () {
    final c =
        registrationChipFor(config: _config(fee: 255), submission: _individual);
    expect(c.kind, RegistrationChipKind.pending);
    expect(c.owed, 255);
  });

  test('a team-code waiver counts (joiner)', () {
    final c = registrationChipFor(
        config: _config(),
        submission: const RegSubmission(path: 'joiner', answers: {}),
        codeWaivesPayment: true);
    expect(c.owed, 0);
    expect(c.kind, RegistrationChipKind.noCharge,
        reason: 'nothing owed and not covered: No charge');
  });
}
