// TDD for the Insider promo-code + first-timer pure engine
// (Infinite Insiders program, Fan Task F3 — Phase P2).
//
// NO Flutter/Firebase imports in lib/registration/promo_engine.dart — every
// helper here is unit-tested directly. See:
// docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §3 (referral
// lifecycle incl. once-ever rule + error copy), §4 (first-timer promo), §5
// (stacking), §9 (data) and docs/superpowers/plans/2026-07-27-infinite-insiders.md
// Task F3.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';

void main() {
  group('normalizeEmail', () {
    test('trims and lowercases', () {
      expect(normalizeEmail('  Zaya@Example.COM  '), 'zaya@example.com');
    });

    test('empty stays empty', () {
      expect(normalizeEmail(''), '');
      expect(normalizeEmail('   '), '');
    });
  });

  group('normalizePhoneDigits', () {
    test('strips everything but digits', () {
      expect(normalizePhoneDigits('(408) 693-9436'), '4086939436');
    });

    test('empty/no-digit input stays empty', () {
      expect(normalizePhoneDigits(''), '');
      expect(normalizePhoneDigits('abc'), '');
    });
  });

  group('promoActiveNow', () {
    final now = DateTime(2026, 7, 27);

    test('disabled is never active regardless of everything else', () {
      expect(promoActiveNow(enabled: false, used: 0, now: now), isFalse);
    });

    test('enabled with no bounds/max is active', () {
      expect(promoActiveNow(enabled: true, used: 0, now: now), isTrue);
    });

    test('before the start date is not active', () {
      expect(
        promoActiveNow(
          enabled: true,
          start: DateTime(2026, 8, 1),
          used: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('on/after the start date is active', () {
      expect(
        promoActiveNow(
          enabled: true,
          start: DateTime(2026, 7, 27),
          used: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('after the end date is not active', () {
      expect(
        promoActiveNow(
          enabled: true,
          end: DateTime(2026, 7, 1),
          used: 0,
          now: now,
        ),
        isFalse,
      );
    });

    test('on/before the end date is active', () {
      expect(
        promoActiveNow(
          enabled: true,
          end: DateTime(2026, 7, 27),
          used: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('used at or above maxRedemptions is not active', () {
      expect(
        promoActiveNow(enabled: true, maxRedemptions: 10, used: 10, now: now),
        isFalse,
      );
      expect(
        promoActiveNow(enabled: true, maxRedemptions: 10, used: 11, now: now),
        isFalse,
      );
    });

    test('used below maxRedemptions is active', () {
      expect(
        promoActiveNow(enabled: true, maxRedemptions: 10, used: 9, now: now),
        isTrue,
      );
    });

    test('null maxRedemptions means unlimited', () {
      expect(
        promoActiveNow(enabled: true, maxRedemptions: null, used: 999999, now: now),
        isTrue,
      );
    });
  });

  group('promoDiscountedTotal', () {
    test('applies a straight percent off', () {
      expect(promoDiscountedTotal(100, 20), 80.0);
    });

    test('rounds to the nearest cent', () {
      expect(promoDiscountedTotal(99.99, 33), closeTo(66.99, 0.001));
    });

    test('100% off comps to zero', () {
      expect(promoDiscountedTotal(160, 100), 0.0);
    });

    test('clamps an over-100% pct to zero, never negative', () {
      expect(promoDiscountedTotal(160, 150), 0.0);
    });

    test('zero eligible fee stays zero', () {
      expect(promoDiscountedTotal(0, 20), 0.0);
    });
  });

  group('evaluateCode', () {
    test('a code that matches no Insider is invalid', () {
      final result = evaluateCode(
        codeOwnerUid: null,
        codeOwnerStatus: null,
        myUid: 'me',
        alreadyReferred: false,
      );
      expect(result.status, CodeCheckStatus.invalid);
      expect(result.message, 'Invalid code');
    });

    test('an empty owner uid is also invalid', () {
      final result = evaluateCode(
        codeOwnerUid: '',
        codeOwnerStatus: 'active',
        myUid: 'me',
        alreadyReferred: false,
      );
      expect(result.status, CodeCheckStatus.invalid);
    });

    test('a code owned by a non-active Insider is suspended', () {
      final result = evaluateCode(
        codeOwnerUid: 'owner1',
        codeOwnerStatus: 'suspended',
        myUid: 'me',
        alreadyReferred: false,
      );
      expect(result.status, CodeCheckStatus.suspended);
      expect(result.message, 'This code is not active right now');
    });

    test('entering your own code is rejected as self-referral', () {
      final result = evaluateCode(
        codeOwnerUid: 'me',
        codeOwnerStatus: 'active',
        myUid: 'me',
        alreadyReferred: false,
      );
      expect(result.status, CodeCheckStatus.selfReferral);
      expect(result.message, "You can't use your own code");
    });

    test('a user who has already redeemed a referral is blocked', () {
      final result = evaluateCode(
        codeOwnerUid: 'owner1',
        codeOwnerStatus: 'active',
        myUid: 'me',
        alreadyReferred: true,
      );
      expect(result.status, CodeCheckStatus.alreadyReferred);
      expect(result.message,
          'A referral code has already been used on this account.');
    });

    test('a valid active code from someone else, never referred, is ok', () {
      final result = evaluateCode(
        codeOwnerUid: 'owner1',
        codeOwnerStatus: 'active',
        myUid: 'me',
        alreadyReferred: false,
      );
      expect(result.status, CodeCheckStatus.ok);
      expect(result.isOk, isTrue);
      expect(result.message, '');
    });

    test('chain order: invalid is checked before suspended/self/already', () {
      // Owner uid null (invalid) even though every other flag would also
      // fail — invalid wins because the lookup itself failed.
      final result = evaluateCode(
        codeOwnerUid: null,
        codeOwnerStatus: 'suspended',
        myUid: 'me',
        alreadyReferred: true,
      );
      expect(result.status, CodeCheckStatus.invalid);
    });

    test('chain order: suspended is checked before self/already', () {
      final result = evaluateCode(
        codeOwnerUid: 'me',
        codeOwnerStatus: 'suspended',
        myUid: 'me',
        alreadyReferred: true,
      );
      expect(result.status, CodeCheckStatus.suspended);
    });

    test('chain order: selfReferral is checked before alreadyReferred', () {
      final result = evaluateCode(
        codeOwnerUid: 'me',
        codeOwnerStatus: 'active',
        myUid: 'me',
        alreadyReferred: true,
      );
      expect(result.status, CodeCheckStatus.selfReferral);
    });
  });

  group('firstTimer', () {
    test('no prior submissions at all is a first-timer', () {
      final result = firstTimer(
        email: 'new@example.com',
        phone: '4085551212',
        priorSubmissions: const [],
      );
      expect(result.isFirstTimer, isTrue);
      expect(result.matchedByEmail, isFalse);
      expect(result.matchedByPhone, isFalse);
    });

    test('a normalized email match against a prior submission is existing',
        () {
      final result = firstTimer(
        email: '  Old@Example.COM ',
        phone: '4085551212',
        priorSubmissions: const [
          {'email': 'old@example.com', 'phone': '4089990000'},
        ],
      );
      expect(result.isFirstTimer, isFalse);
      expect(result.matchedByEmail, isTrue);
      expect(result.matchedByPhone, isFalse);
    });

    test('a normalized phone match against a prior submission is existing',
        () {
      final result = firstTimer(
        email: 'new@example.com',
        phone: '(408) 999-0000',
        priorSubmissions: const [
          {'email': 'someoneelse@example.com', 'phone': '4089990000'},
        ],
      );
      expect(result.isFirstTimer, isFalse);
      expect(result.matchedByPhone, isTrue);
      expect(result.matchedByEmail, isFalse);
    });

    test('no match on either field is a first-timer', () {
      final result = firstTimer(
        email: 'new@example.com',
        phone: '4085551212',
        priorSubmissions: const [
          {'email': 'someoneelse@example.com', 'phone': '4089990000'},
        ],
      );
      expect(result.isFirstTimer, isTrue);
    });

    test('blank email/phone never match a submission with blank fields', () {
      final result = firstTimer(
        email: '',
        phone: '',
        priorSubmissions: const [
          {'email': '', 'phone': ''},
        ],
      );
      expect(result.isFirstTimer, isTrue);
    });

    test('tolerates prior submissions missing email/phone keys entirely', () {
      final result = firstTimer(
        email: 'new@example.com',
        phone: '4085551212',
        priorSubmissions: const [
          {'firstName': 'John'},
        ],
      );
      expect(result.isFirstTimer, isTrue);
    });
  });

  group('RegPromo', () {
    test('a missing/malformed node parses to an all-defaults disabled promo',
        () {
      expect(RegPromo.fromFirebase(null).enabled, isFalse);
      expect(RegPromo.fromFirebase('junk').enabled, isFalse);
      expect(RegPromo.fromFirebase(null).percent, 0);
      expect(RegPromo.fromFirebase(null).used, 0);
      expect(RegPromo.fromFirebase(null).maxRedemptions, isNull);
    });

    test('parses a fully populated node', () {
      final promo = RegPromo.fromFirebase({
        'Enabled': true,
        'Percent': 15,
        'Start': 1753574400000,
        'End': 1756252800000,
        'MaxRedemptions': 50,
        'Used': 12,
      });
      expect(promo.enabled, isTrue);
      expect(promo.percent, 15.0);
      expect(promo.start, DateTime.fromMillisecondsSinceEpoch(1753574400000));
      expect(promo.end, DateTime.fromMillisecondsSinceEpoch(1756252800000));
      expect(promo.maxRedemptions, 50);
      expect(promo.used, 12);
    });

    test('activeAt combines its own fields via promoActiveNow', () {
      const promo = RegPromo(enabled: true, percent: 10, used: 0);
      expect(promo.activeAt(DateTime(2026, 7, 27)), isTrue);
      const disabled = RegPromo(enabled: false, percent: 10);
      expect(disabled.activeAt(DateTime(2026, 7, 27)), isFalse);
    });
  });

  group('bestDiscountedTotal', () {
    test('no discount signals returns the base fee', () {
      expect(bestDiscountedTotal(baseFee: 160, discountSource: ''), 160);
    });

    test('manual-only (discountSource manual) matches adjustedOwed', () {
      expect(
        bestDiscountedTotal(
          baseFee: 160,
          adjustedFee: 100,
          discountSource: 'manual',
        ),
        100,
      );
      expect(
        bestDiscountedTotal(
          baseFee: 160,
          discountPct: 10,
          discountSource: 'manual',
        ),
        closeTo(144, 0.001),
      );
    });

    test('promo-only (discountSource first_timer_promo) applies the pct '
        'against eligibleFee', () {
      expect(
        bestDiscountedTotal(
          baseFee: 160,
          eligibleFee: 160,
          discountPct: 25,
          discountSource: 'first_timer_promo',
        ),
        120.0,
      );
    });

    test('promo falls back to baseFee when eligibleFee is missing', () {
      expect(
        bestDiscountedTotal(
          baseFee: 160,
          discountPct: 25,
          discountSource: 'first_timer_promo',
        ),
        120.0,
      );
    });

    test('clamps a negative/over-cap result to zero', () {
      expect(
        bestDiscountedTotal(
          baseFee: 160,
          adjustedFee: -5,
          discountSource: 'manual',
        ),
        0,
      );
    });
  });

  group('InsiderPromoOutcome', () {
    test('holds the stamped fields verbatim', () {
      const outcome = InsiderPromoOutcome(
        insiderCode: 'ZA4K9P2',
        firstTimer: true,
        discountSource: 'first_timer_promo',
        discountPct: 15,
        eligibleFee: 60,
      );
      expect(outcome.insiderCode, 'ZA4K9P2');
      expect(outcome.firstTimer, isTrue);
      expect(outcome.discountSource, 'first_timer_promo');
      expect(outcome.discountPct, 15);
      expect(outcome.eligibleFee, 60);
    });

    test('defaults to no discount', () {
      const outcome = InsiderPromoOutcome(insiderCode: 'ZA4K9P2', firstTimer: false);
      expect(outcome.discountSource, '');
      expect(outcome.discountPct, isNull);
      expect(outcome.eligibleFee, isNull);
    });
  });
}
