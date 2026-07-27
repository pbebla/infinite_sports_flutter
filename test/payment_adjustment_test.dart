// TDD for the manual payment-adjustment pure helpers (Infinite Insiders
// M1/F1). Ported byte-identical from the Manager repo's
// test/payment_adjustment_test.dart (only this import differs) so both
// repos lock the same math — see docs/superpowers/plans/
// 2026-07-27-infinite-insiders.md Task F1 and the design spec
// docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §5
// (stacking/ceiling) and §9 (InsiderAudit shape).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/registration/payment_adjustment.dart';

void main() {
  group('adjustedOwed', () {
    test('no adjustment returns the base fee unchanged', () {
      expect(adjustedOwed(baseFee: 160), 160);
    });

    test('adjustedFee (absolute) wins over discountPct when both are set', () {
      expect(
        adjustedOwed(baseFee: 160, adjustedFee: 100, discountPct: 50),
        100,
      );
    });

    test('discountPct computes a percentage off the base fee', () {
      expect(adjustedOwed(baseFee: 160, discountPct: 10), closeTo(144, 0.001));
    });

    test('clamps a negative adjustedFee to zero', () {
      expect(adjustedOwed(baseFee: 160, adjustedFee: -20), 0);
    });

    test('a 100% discountPct comps to zero', () {
      expect(adjustedOwed(baseFee: 160, discountPct: 100), 0);
    });

    test('clamps an over-100% discountPct to zero, never negative', () {
      expect(adjustedOwed(baseFee: 160, discountPct: 150), 0);
    });

    test('a zero base fee with no adjustment stays zero', () {
      expect(adjustedOwed(baseFee: 0), 0);
    });
  });

  group('validateAdjustment', () {
    test('valid new amount under the base fee (within the cap) is allowed',
        () {
      // 130 off a 160 base is ~18.75% off — inside the default 25% cap.
      expect(
        validateAdjustment(baseFee: 160, newAmount: 130, compConfirmed: false),
        isNull,
      );
    });

    test(
        'a new amount implying more than the cap is rejected without comp '
        'confirmation, even though it is still under the base fee', () {
      // 100 off a 160 base is 37.5% off — over the default 25% cap.
      expect(
        validateAdjustment(baseFee: 160, newAmount: 100, compConfirmed: false),
        isNotNull,
      );
      expect(
        validateAdjustment(baseFee: 160, newAmount: 100, compConfirmed: true),
        isNull,
      );
    });

    test('new amount equal to the base fee is allowed', () {
      expect(
        validateAdjustment(baseFee: 160, newAmount: 160, compConfirmed: false),
        isNull,
      );
    });

    test('new amount above the base fee is rejected with the exact message', () {
      expect(
        validateAdjustment(baseFee: 160, newAmount: 200, compConfirmed: false),
        'Cannot charge more than the base fee',
      );
    });

    test('negative new amount is rejected', () {
      expect(
        validateAdjustment(baseFee: 160, newAmount: -5, compConfirmed: false),
        isNotNull,
      );
    });

    test('percent within the default 25% cap is allowed', () {
      expect(
        validateAdjustment(baseFee: 160, pct: 20, compConfirmed: false),
        isNull,
      );
    });

    test('percent exactly at the cap is allowed', () {
      expect(
        validateAdjustment(baseFee: 160, pct: 25, compConfirmed: false),
        isNull,
      );
    });

    test('percent above the cap is rejected without comp confirmation', () {
      expect(
        validateAdjustment(baseFee: 160, pct: 50, compConfirmed: false),
        isNotNull,
      );
    });

    test('percent above the cap is allowed once comp-confirmed', () {
      expect(
        validateAdjustment(baseFee: 160, pct: 100, compConfirmed: true),
        isNull,
      );
    });

    test('negative percent is rejected', () {
      expect(
        validateAdjustment(baseFee: 160, pct: -10, compConfirmed: false),
        isNotNull,
      );
    });

    test('percent above 100 is rejected even when comp-confirmed', () {
      expect(
        validateAdjustment(baseFee: 160, pct: 150, compConfirmed: true),
        isNotNull,
      );
    });

    test('a new-amount comp to zero requires comp confirmation past the cap',
        () {
      expect(
        validateAdjustment(baseFee: 160, newAmount: 0, compConfirmed: false),
        isNotNull,
      );
      expect(
        validateAdjustment(baseFee: 160, newAmount: 0, compConfirmed: true),
        isNull,
      );
    });

    test('a custom maxPct overrides the default 25% cap', () {
      expect(
        validateAdjustment(
          baseFee: 160,
          pct: 30,
          compConfirmed: false,
          maxPct: 40,
        ),
        isNull,
      );
    });

    test('neither newAmount nor pct supplied is valid (no-op)', () {
      expect(
        validateAdjustment(baseFee: 160, compConfirmed: false),
        isNull,
      );
    });
  });

  group('auditEntry', () {
    test('builds the spec InsiderAudit shape', () {
      final entry = auditEntry(
        adminUid: 'admin-1',
        regId: 'Futsal-17',
        submissionId: 'user-42',
        field: 'AdjustedFee',
        oldValue: null,
        newValue: 144.0,
        reason: 'Hardship discount approved by owner',
      );
      expect(entry['AdminUid'], 'admin-1');
      expect(entry['Target'], 'Futsal-17/user-42');
      expect(entry['Field'], 'AdjustedFee');
      expect(entry['Old'], isNull);
      expect(entry['New'], 144.0);
      expect(entry['Reason'], 'Hardship discount approved by owner');
      expect(entry['At'], isA<int>());
    });

    test('trims the reason', () {
      final entry = auditEntry(
        adminUid: 'admin-1',
        regId: 'Futsal-17',
        submissionId: 'user-42',
        field: 'AdjustedFee',
        oldValue: 160.0,
        newValue: 0.0,
        reason: '  Comp — season injury  ',
      );
      expect(entry['Reason'], 'Comp — season injury');
    });

    test('throws when reason is empty or blank', () {
      expect(
        () => auditEntry(
          adminUid: 'admin-1',
          regId: 'Futsal-17',
          submissionId: 'user-42',
          field: 'AdjustedFee',
          oldValue: null,
          newValue: 0.0,
          reason: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('accepts an injected timestamp for deterministic testing', () {
      final entry = auditEntry(
        adminUid: 'admin-1',
        regId: 'Futsal-17',
        submissionId: 'user-42',
        field: 'AdjustedFee',
        oldValue: null,
        newValue: 0.0,
        reason: 'Test',
        atMs: 123456,
      );
      expect(entry['At'], 123456);
    });
  });
}
