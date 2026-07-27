import { describe, expect, it } from 'vitest';
import {
  counterUpdates, decideOnPaidFlip, effectiveCharge, notificationFor,
  tierDiscountPct, tierForStanding, tierName,
} from '../src/lib/insiders';

// ---------------------------------------------------------------------------
// Tiers
// ---------------------------------------------------------------------------

describe('tierForStanding', () => {
  it('is 0 (no tier) below 5', () => {
    expect(tierForStanding(0)).toBe(0);
    expect(tierForStanding(4)).toBe(0);
  });

  it('is Bronze at 5-9', () => {
    expect(tierForStanding(5)).toBe(1);
    expect(tierForStanding(9)).toBe(1);
  });

  it('is Silver at 10-14', () => {
    expect(tierForStanding(10)).toBe(2);
    expect(tierForStanding(14)).toBe(2);
  });

  it('is Gold at 15-19', () => {
    expect(tierForStanding(15)).toBe(3);
    expect(tierForStanding(19)).toBe(3);
  });

  it('is Platinum at 20-24', () => {
    expect(tierForStanding(20)).toBe(4);
    expect(tierForStanding(24)).toBe(4);
  });

  it('is Infinite at 25+', () => {
    expect(tierForStanding(25)).toBe(5);
    expect(tierForStanding(1000)).toBe(5);
  });
});

describe('tierName', () => {
  it('maps tiers to display names', () => {
    expect(tierName(0)).toBe('');
    expect(tierName(1)).toBe('Bronze');
    expect(tierName(2)).toBe('Silver');
    expect(tierName(3)).toBe('Gold');
    expect(tierName(4)).toBe('Platinum');
    expect(tierName(5)).toBe('Infinite');
  });

  it('returns "" for out-of-range tiers', () => {
    expect(tierName(-1)).toBe('');
    expect(tierName(6)).toBe('');
  });
});

describe('tierDiscountPct', () => {
  it('maps tiers to their own-fee discount percent', () => {
    expect(tierDiscountPct(0)).toBe(0);
    expect(tierDiscountPct(1)).toBe(5);
    expect(tierDiscountPct(2)).toBe(10);
    expect(tierDiscountPct(3)).toBe(15);
    expect(tierDiscountPct(4)).toBe(20);
    expect(tierDiscountPct(5)).toBe(25);
  });

  it('returns 0 for out-of-range tiers', () => {
    expect(tierDiscountPct(-1)).toBe(0);
    expect(tierDiscountPct(6)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// decideOnPaidFlip
// ---------------------------------------------------------------------------

function paidFlip(overrides: Partial<Parameters<typeof decideOnPaidFlip>[0]> = {}) {
  return {
    wasPaid: false,
    isPaid: true,
    insiderCode: 'ZAYA1234',
    referredUid: 'referred-1',
    insiderUid: 'insider-1',
    insiderStatus: 'active',
    alreadyReferredEntry: null,
    hasCountedReferralForSubmission: false,
    ...overrides,
  };
}

describe('decideOnPaidFlip — count path (unpaid -> paid)', () => {
  it('counts a fresh submission with a valid active code and no prior referral', () => {
    expect(decideOnPaidFlip(paidFlip()).action).toBe('count');
  });

  it('does nothing when Paid did not actually flip', () => {
    expect(decideOnPaidFlip(paidFlip({ wasPaid: true, isPaid: true })).action).toBe('none');
    expect(decideOnPaidFlip(paidFlip({ wasPaid: false, isPaid: false })).action).toBe('none');
  });

  it('does nothing when no code was entered', () => {
    expect(decideOnPaidFlip(paidFlip({ insiderCode: '' })).action).toBe('none');
  });

  it('does nothing when the code does not resolve to an Insider', () => {
    expect(decideOnPaidFlip(paidFlip({ insiderUid: null })).action).toBe('none');
  });

  it('does nothing when the Insider is not active (suspended/pending/declined/missing)', () => {
    expect(decideOnPaidFlip(paidFlip({ insiderStatus: 'suspended' })).action).toBe('none');
    expect(decideOnPaidFlip(paidFlip({ insiderStatus: 'pending' })).action).toBe('none');
    expect(decideOnPaidFlip(paidFlip({ insiderStatus: '' })).action).toBe('none');
  });

  it('does nothing on self-referral (code owner == referred user)', () => {
    expect(decideOnPaidFlip(paidFlip({ insiderUid: 'referred-1', referredUid: 'referred-1' })).action)
      .toBe('none');
  });

  it('does nothing when the referred user already has a referral on record (once-ever guard)', () => {
    expect(decideOnPaidFlip(paidFlip({ alreadyReferredEntry: 'some-other-referral-id' })).action)
      .toBe('none');
  });
});

describe('decideOnPaidFlip — void path (paid -> unpaid)', () => {
  it('voids when a counted referral exists for this submission', () => {
    const decision = decideOnPaidFlip(paidFlip({
      wasPaid: true, isPaid: false, hasCountedReferralForSubmission: true,
    }));
    expect(decision.action).toBe('void');
  });

  it('does nothing when there is no counted referral for this submission (never counted, or already voided)', () => {
    const decision = decideOnPaidFlip(paidFlip({
      wasPaid: true, isPaid: false, hasCountedReferralForSubmission: false,
    }));
    expect(decision.action).toBe('none');
  });
});

// ---------------------------------------------------------------------------
// counterUpdates
// ---------------------------------------------------------------------------

describe('counterUpdates', () => {
  it('applies +1 on count and reports no tier change well below a threshold', () => {
    const r = counterUpdates({ standing: 1, total: 1, yearCount: 1, delta: 1 });
    expect(r).toMatchObject({ standing: 2, total: 2, yearCount: 2, oldTier: 0, newTier: 0, tierChanged: false });
  });

  it('detects a tier-up crossing a threshold', () => {
    const r = counterUpdates({ standing: 4, total: 4, yearCount: 4, delta: 1 });
    expect(r.standing).toBe(5);
    expect(r.oldTier).toBe(0);
    expect(r.newTier).toBe(1);
    expect(r.tierChanged).toBe(true);
  });

  it('applies -1 on void and detects a tier-down', () => {
    const r = counterUpdates({ standing: 5, total: 5, yearCount: 5, delta: -1 });
    expect(r.standing).toBe(4);
    expect(r.oldTier).toBe(1);
    expect(r.newTier).toBe(0);
    expect(r.tierChanged).toBe(true);
  });

  it('floors every counter at 0 on void (never goes negative)', () => {
    const r = counterUpdates({ standing: 0, total: 0, yearCount: 0, delta: -1 });
    expect(r.standing).toBe(0);
    expect(r.total).toBe(0);
    expect(r.yearCount).toBe(0);
    expect(r.tierChanged).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// notificationFor
// ---------------------------------------------------------------------------

describe('notificationFor', () => {
  it('builds the +1 referral notification', () => {
    const n = notificationFor({ type: 'referral', referredName: 'Sara', sport: 'Futsal' });
    expect(n.title).toContain('+1');
    expect(n.body).toBe('Sara joined Futsal with your code');
  });

  it('builds a tier-up notification with the new tier name and discount pct', () => {
    const n = notificationFor({ type: 'tierUp', tier: 2 });
    expect(n.title.toLowerCase()).toContain('tier up');
    expect(n.body).toContain('Silver');
    expect(n.body).toContain('10%');
  });

  it('builds a tier-down notification with the new tier name and discount pct', () => {
    const n = notificationFor({ type: 'tierDown', tier: 1 });
    expect(n.body).toContain('Bronze');
    expect(n.body).toContain('5%');
  });

  it('builds a neutral voided notification', () => {
    const n = notificationFor({ type: 'voided' });
    expect(n.title.length).toBeGreaterThan(0);
    expect(n.body.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// effectiveCharge
// ---------------------------------------------------------------------------

describe('effectiveCharge', () => {
  it('returns baseCents unchanged when no discount fields are set', () => {
    expect(effectiveCharge({ baseCents: 2000, discountSource: '' })).toBe(2000);
  });

  it('manual absolute AdjustedFee wins for DiscountSource=="manual"', () => {
    expect(effectiveCharge({
      baseCents: 2000, adjustedFee: 15, discountPct: 50, discountSource: 'manual',
    })).toBe(1500);
  });

  it('manual percent-off applies when only DiscountPct is set', () => {
    expect(effectiveCharge({
      baseCents: 2000, discountPct: 25, discountSource: 'manual',
    })).toBe(1500);
  });

  it('comps to 0 and never goes negative', () => {
    expect(effectiveCharge({
      baseCents: 2000, adjustedFee: 0, discountSource: 'manual',
    })).toBe(0);
    expect(effectiveCharge({
      baseCents: 2000, adjustedFee: -5, discountSource: 'manual',
    })).toBe(0);
  });

  it('first-timer promo percent applies against EligibleFee, not baseCents', () => {
    expect(effectiveCharge({
      baseCents: 2000, eligibleFee: 20, discountPct: 10, discountSource: 'first_timer_promo',
    })).toBe(1800);
  });

  it('first-timer promo falls back to baseCents when EligibleFee is missing', () => {
    expect(effectiveCharge({
      baseCents: 2000, discountPct: 10, discountSource: 'first_timer_promo',
    })).toBe(1800);
  });

  it('rounds to the nearest cent', () => {
    expect(effectiveCharge({
      baseCents: 1235, discountPct: 33, discountSource: 'manual',
    })).toBe(Math.round(1235 * 0.67));
  });

  it('falls back to the manual-precedence rule for an unrecognized discountSource with fields set', () => {
    expect(effectiveCharge({
      baseCents: 2000, adjustedFee: 15, discountSource: 'something_else',
    })).toBe(1500);
  });
});
