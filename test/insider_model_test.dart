// Pure-logic tests for the fan-side Infinite Insiders model
// (lib/model/insider.dart, Task F2). TDD failing-first: this file is
// written before the implementation exists.
//
// Tier thresholds/names/pct mirror the Manager's lib/models/insider_models.dart
// byte-identically (spec §2): Bronze>=5 (5%), Silver>=10 (10%), Gold>=15
// (15%), Platinum>=20 (20%), Infinite>=25+ (25%). Boundary tests below cover
// 4, 5, 9, 10, 24, 25, 40 per the plan.

import 'package:flutter_test/flutter_test.dart';

import 'package:infinite_sports_flutter/model/insider.dart';

void main() {
  group('tierForStanding (boundaries)', () {
    test('4 -> 0 (below Bronze)', () => expect(tierForStanding(4), 0));
    test('5 -> 1 (Bronze floor)', () => expect(tierForStanding(5), 1));
    test('9 -> 1 (still Bronze, below Silver)',
        () => expect(tierForStanding(9), 1));
    test('10 -> 2 (Silver floor)', () => expect(tierForStanding(10), 2));
    test('24 -> 4 (still Platinum, below Infinite)',
        () => expect(tierForStanding(24), 4));
    test('25 -> 5 (Infinite floor)', () => expect(tierForStanding(25), 5));
    test('40 -> 5 (Infinite has no ceiling)',
        () => expect(tierForStanding(40), 5));
    test('0 -> 0', () => expect(tierForStanding(0), 0));
    test('negative standing clamps to tier 0',
        () => expect(tierForStanding(-3), 0));
  });

  group('tierName', () {
    test('0 -> empty (no tier yet)', () => expect(tierName(0), ''));
    test('1 -> Bronze', () => expect(tierName(1), 'Bronze'));
    test('2 -> Silver', () => expect(tierName(2), 'Silver'));
    test('3 -> Gold', () => expect(tierName(3), 'Gold'));
    test('4 -> Platinum', () => expect(tierName(4), 'Platinum'));
    test('5 -> Infinite', () => expect(tierName(5), 'Infinite'));
    test('out of range returns empty', () {
      expect(tierName(6), '');
      expect(tierName(-1), '');
    });
  });

  group('tierDiscountPct', () {
    test('0 -> 0', () => expect(tierDiscountPct(0), 0));
    test('1 -> 5', () => expect(tierDiscountPct(1), 5));
    test('2 -> 10', () => expect(tierDiscountPct(2), 10));
    test('3 -> 15', () => expect(tierDiscountPct(3), 15));
    test('4 -> 20', () => expect(tierDiscountPct(4), 20));
    test('5 -> 25', () => expect(tierDiscountPct(5), 25));
    test('out of range returns 0', () {
      expect(tierDiscountPct(6), 0);
      expect(tierDiscountPct(-1), 0);
    });
  });

  group('Insider.fromFirebase', () {
    test('returns null when raw is not a Map', () {
      expect(Insider.fromFirebase('u1', null), isNull);
      expect(Insider.fromFirebase('u1', 'not a map'), isNull);
      expect(Insider.fromFirebase('u1', 42), isNull);
    });

    test('parses a full node', () {
      final insider = Insider.fromFirebase('u1', {
        'Code': 'zs4k9p2',
        'Status': 'active',
        'Tier': 2,
        'CurrentStanding': 12,
        'TotalReferred': 14,
        'SportsOfInterest': ['Futsal', 'Basketball'],
        'Name': 'Zaya Arami',
        'Email': 'zaya@example.com',
      });
      expect(insider, isNotNull);
      expect(insider!.uid, 'u1');
      // Code is stored uppercased-elsewhere (Manager normalizes); the fan
      // model reads tolerantly and doesn't re-case it.
      expect(insider.code, 'zs4k9p2');
      expect(insider.status, 'active');
      expect(insider.tier, 2);
      expect(insider.currentStanding, 12);
      expect(insider.totalReferred, 14);
      expect(insider.sportsOfInterest, ['Futsal', 'Basketball']);
      expect(insider.name, 'Zaya Arami');
      expect(insider.email, 'zaya@example.com');
      expect(insider.isActive, isTrue);
      expect(insider.isPending, isFalse);
      expect(insider.isDeclined, isFalse);
      expect(insider.isSuspended, isFalse);
    });

    test('an empty map still parses to all-defaults (Status defaults to pending)', () {
      final insider = Insider.fromFirebase('u2', <String, dynamic>{});
      expect(insider, isNotNull);
      expect(insider!.status, 'pending');
      expect(insider.isPending, isTrue);
      expect(insider.code, '');
      expect(insider.tier, 0);
      expect(insider.currentStanding, 0);
      expect(insider.totalReferred, 0);
      expect(insider.sportsOfInterest, isEmpty);
      expect(insider.name, '');
      expect(insider.email, '');
    });

    test('an unrecognized Status string falls back to pending', () {
      final insider =
          Insider.fromFirebase('u3', {'Status': 'not-a-real-status'});
      expect(insider!.status, 'pending');
    });

    test('numeric fields parse from numeric strings too (tolerant)', () {
      final insider = Insider.fromFirebase('u4', {
        'Tier': '3',
        'CurrentStanding': '17',
        'TotalReferred': '20',
      });
      expect(insider!.tier, 3);
      expect(insider.currentStanding, 17);
      expect(insider.totalReferred, 20);
    });

    test('non-list SportsOfInterest is treated as empty', () {
      final insider =
          Insider.fromFirebase('u5', {'SportsOfInterest': 'Futsal'});
      expect(insider!.sportsOfInterest, isEmpty);
    });

    test('declined/suspended/pending status flags', () {
      expect(Insider.fromFirebase('u', {'Status': 'declined'})!.isDeclined,
          isTrue);
      expect(Insider.fromFirebase('u', {'Status': 'suspended'})!.isSuspended,
          isTrue);
      expect(
          Insider.fromFirebase('u', {'Status': 'pending'})!.isPending, isTrue);
    });
  });

  group('Insider.fromFirebase — dashboard fields (Task F4)', () {
    test('parses CurrentYearCount and the two opt-in flags', () {
      final insider = Insider.fromFirebase('u1', {
        'CurrentYearCount': 3,
        'PublicLeaderboardOptIn': false,
        'ProfileBadgeOptIn': false,
      });
      expect(insider!.currentYearCount, 3);
      expect(insider.publicLeaderboardOptIn, isFalse);
      expect(insider.profileBadgeOptIn, isFalse);
    });

    test('opt-ins default to true when absent (tolerant parse)', () {
      final insider = Insider.fromFirebase('u1', <String, dynamic>{});
      expect(insider!.publicLeaderboardOptIn, isTrue);
      expect(insider.profileBadgeOptIn, isTrue);
      expect(insider.currentYearCount, 0);
    });
  });

  group('normalizeInsiderCode (Task F3 — code entry on the registration form)',
      () {
    test('trims and uppercases', () {
      expect(normalizeInsiderCode('  za4k9p2  '), 'ZA4K9P2');
    });

    test('already-normalized input is unchanged', () {
      expect(normalizeInsiderCode('ZA4K9P2'), 'ZA4K9P2');
    });

    test('empty stays empty', () {
      expect(normalizeInsiderCode(''), '');
      expect(normalizeInsiderCode('   '), '');
    });
  });
}
