// The ONE Venmo deep link + Zelle identity shared by the registration
// payment screen and the fantasy season-pass card (paid-access spec
// 2026-11-01 §2/§6) — the link shape both screens open.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/payment_links.dart';

void main() {
  group('venmoPayUri', () {
    test('venmo.com/<handle>?txn=pay&amount=&note= with the note encoded',
        () {
      final uri = venmoPayUri(amount: 10, note: 'Fantasy Futsal S16 Ava');
      expect(uri.scheme, 'https');
      expect(uri.host, 'venmo.com');
      expect(uri.path, '/$kVenmoHandle');
      expect(uri.queryParameters['txn'], 'pay');
      expect(uri.queryParameters['amount'], '10');
      expect(uri.queryParameters['note'], 'Fantasy Futsal S16 Ava');
      expect(uri.toString(), contains('note=Fantasy%20Futsal%20S16%20Ava'));
    });

    test('the registration note shape (regId - name) still round-trips', () {
      final uri = venmoPayUri(amount: 55, note: '-Nreg1 - Ava Striker');
      expect(uri.queryParameters['note'], '-Nreg1 - Ava Striker');
      expect(uri.queryParameters['amount'], '55');
    });
  });

  group('venmoAmountText', () {
    test('whole dollars plain, cents with two decimals, never "55.0"', () {
      expect(venmoAmountText(55), '55');
      expect(venmoAmountText(55.0), '55');
      expect(venmoAmountText(46.75), '46.75');
      expect(venmoAmountText(10.5), '10.50');
      expect(venmoAmountText(0), '0');
    });
  });

  test('the Zelle identity and Venmo handle are the owner-confirmed ones', () {
    expect(kVenmoHandle, 'infinite-sports');
    expect(kZelleNumber, '408-693-9436');
    expect(kZelleDisplayName, 'Zaya Shahbaz Arami');
  });
}
