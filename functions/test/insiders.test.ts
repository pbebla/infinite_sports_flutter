import { describe, expect, it } from 'vitest';
import {
  counterUpdates, decideOnPaidFlip, effectiveCharge, maintenanceDecision, notificationFor,
  tierDiscountPct, tierForStanding, tierName,
} from '../src/lib/insiders';

const DAY_MS = 24 * 60 * 60 * 1000;

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

// ---------------------------------------------------------------------------
// maintenanceDecision (Task X2 — spec §2 inactivity + Infinite annual)
// ---------------------------------------------------------------------------

function maint(overrides: Partial<Parameters<typeof maintenanceDecision>[0]> = {}) {
  const nowMs = Date.parse('2026-07-27T00:00:00Z');
  return {
    standing: 10,
    tier: 2, // Silver
    lastReferralAtMs: nowMs - 10 * DAY_MS, // recently active by default
    currentYearCount: 3,
    nowMs,
    lastReminderSentMs: null,
    lastWarnSentMs: null,
    isYearRollover: false,
    ...overrides,
  };
}

describe('maintenanceDecision — tier floor (tier 0 / Bronze never drop or nag)', () => {
  it('tier 0 (no tier) never does anything, no matter how inactive', () => {
    const r = maintenanceDecision(maint({
      tier: 0, standing: 2, lastReferralAtMs: maint().nowMs - 400 * DAY_MS,
    }));
    expect(r.action).toBe('none');
  });

  it('Bronze (tier 1) never drops or gets inactivity nudges', () => {
    const r = maintenanceDecision(maint({
      tier: 1, standing: 6, lastReferralAtMs: maint().nowMs - 400 * DAY_MS,
    }));
    expect(r.action).toBe('none');
  });

  it('tier 0/1 ignore isYearRollover too (annual maintenance is Infinite-only)', () => {
    const r = maintenanceDecision(maint({
      tier: 1, standing: 6, currentYearCount: 0, isYearRollover: true,
    }));
    expect(r.action).toBe('none');
  });
});

describe('maintenanceDecision — inactivity ladder (Silver and above, 30-day months)', () => {
  it('does nothing well before the 5-month mark', () => {
    const r = maintenanceDecision(maint({ lastReferralAtMs: maint().nowMs - 100 * DAY_MS }));
    expect(r.action).toBe('none');
  });

  it('reminds once at the 5-month (150-day) mark', () => {
    const r = maintenanceDecision(maint({ lastReferralAtMs: maint().nowMs - 150 * DAY_MS }));
    expect(r.action).toBe('remind5mo');
  });

  it('does not re-remind the same episode (lastReminderSentMs already covers it)', () => {
    const base = maint();
    const lastReferralAtMs = base.nowMs - 152 * DAY_MS;
    const r = maintenanceDecision(maint({
      lastReferralAtMs, lastReminderSentMs: lastReferralAtMs + 1 * DAY_MS,
    }));
    expect(r.action).toBe('none');
  });

  it('warns once at the 5.5-month (165-day) mark', () => {
    const r = maintenanceDecision(maint({ lastReferralAtMs: maint().nowMs - 165 * DAY_MS }));
    expect(r.action).toBe('warn2wk');
  });

  it('still warns even if the 5-month reminder was never recorded (graceful catch-up)', () => {
    const r = maintenanceDecision(maint({
      lastReferralAtMs: maint().nowMs - 165 * DAY_MS, lastReminderSentMs: null,
    }));
    expect(r.action).toBe('warn2wk');
  });

  it('does not re-warn the same episode', () => {
    const base = maint();
    const lastReferralAtMs = base.nowMs - 170 * DAY_MS;
    const r = maintenanceDecision(maint({
      lastReferralAtMs, lastWarnSentMs: lastReferralAtMs + 1 * DAY_MS,
    }));
    expect(r.action).toBe('none');
  });

  it('a stale reminder/warn stamp from a PRIOR episode does not block the new episode', () => {
    // lastReminderSentMs predates this episode's lastReferralAtMs -> stale,
    // must not suppress the new episode's reminder.
    const base = maint();
    const lastReferralAtMs = base.nowMs - 150 * DAY_MS;
    const r = maintenanceDecision(maint({
      lastReferralAtMs, lastReminderSentMs: lastReferralAtMs - 5 * DAY_MS,
    }));
    expect(r.action).toBe('remind5mo');
  });

  it('drops one tier at the 6-month (180-day) mark — Silver -> Bronze lands standing at 5', () => {
    const r = maintenanceDecision(maint({
      tier: 2, lastReferralAtMs: maint().nowMs - 180 * DAY_MS,
    }));
    expect(r.action).toBe('dropInactivity');
    expect(r.newTier).toBe(1);
    expect(r.newStanding).toBe(5);
  });

  it('drops Gold -> Silver landing standing at 10', () => {
    const r = maintenanceDecision(maint({
      tier: 3, lastReferralAtMs: maint().nowMs - 200 * DAY_MS,
    }));
    expect(r.action).toBe('dropInactivity');
    expect(r.newTier).toBe(2);
    expect(r.newStanding).toBe(10);
  });

  it('drops Platinum -> Gold landing standing at 15', () => {
    const r = maintenanceDecision(maint({
      tier: 4, lastReferralAtMs: maint().nowMs - 180 * DAY_MS,
    }));
    expect(r.action).toBe('dropInactivity');
    expect(r.newTier).toBe(3);
    expect(r.newStanding).toBe(15);
  });

  it('the general 6-month inactivity rule also applies to Infinite -> Platinum', () => {
    const r = maintenanceDecision(maint({
      tier: 5, standing: 30, lastReferralAtMs: maint().nowMs - 180 * DAY_MS,
    }));
    expect(r.action).toBe('dropInactivity');
    expect(r.newTier).toBe(4);
    expect(r.newStanding).toBe(20);
  });

  it('treats a missing/zero LastReferralAt as insufficient data (does nothing)', () => {
    const r = maintenanceDecision(maint({ lastReferralAtMs: 0 }));
    expect(r.action).toBe('none');
  });
});

describe('maintenanceDecision — Infinite annual maintenance (year-end window only)', () => {
  it('does nothing outside the year-rollover window even if the year count is short', () => {
    const r = maintenanceDecision(maint({
      tier: 5, standing: 30, currentYearCount: 2, isYearRollover: false,
    }));
    expect(r.action).toBe('none');
  });

  it('drops Infinite -> Platinum (standing 20) on year-end when currentYearCount < 5', () => {
    const r = maintenanceDecision(maint({
      tier: 5, standing: 30, currentYearCount: 2, isYearRollover: true,
    }));
    expect(r.action).toBe('dropInfiniteAnnual');
    expect(r.newTier).toBe(4);
    expect(r.newStanding).toBe(20);
  });

  it('keeps Infinite when the year-end count meets the 5-referral quota', () => {
    const r = maintenanceDecision(maint({
      tier: 5, standing: 30, currentYearCount: 5, isYearRollover: true,
    }));
    expect(r.action).toBe('none');
  });

  it('never applies the annual rule to tiers below Infinite', () => {
    const r = maintenanceDecision(maint({
      tier: 4, standing: 22, currentYearCount: 0, isYearRollover: true,
    }));
    expect(r.action).toBe('none');
  });

  it('general 6-month inactivity takes precedence over the annual drop when both fire the same day', () => {
    const r = maintenanceDecision(maint({
      tier: 5, standing: 30, currentYearCount: 1, isYearRollover: true,
      lastReferralAtMs: maint().nowMs - 200 * DAY_MS,
    }));
    expect(r.action).toBe('dropInactivity');
    expect(r.newTier).toBe(4);
    expect(r.newStanding).toBe(20);
  });
});

// ---------------------------------------------------------------------------
// notificationFor — maintenance copy (Task X2)
// ---------------------------------------------------------------------------

describe('notificationFor — maintenance events', () => {
  it('builds the 5-month inactivity reminder', () => {
    const n = notificationFor({ type: 'maintenanceRemind' });
    expect(n.body).toBe('Bring players to keep your tier! 5 months without a referral.');
  });

  it('builds the 2-week warning naming the tier at risk', () => {
    const n = notificationFor({ type: 'maintenanceWarn', tier: 2 });
    expect(n.body).toBe('2 weeks until your tier drops — refer a new player to keep Silver.');
  });

  it('builds the drop notice naming the tier landed on', () => {
    const n = notificationFor({ type: 'maintenanceDropped', tier: 1 });
    expect(n.body).toBe('Your tier dropped to Bronze. Bring new players to climb back up.');
  });

  it('builds the Infinite annual-maintenance drop notice', () => {
    const n = notificationFor({ type: 'infiniteMaintenanceDropped', currentYearCount: 2 });
    expect(n.title.length).toBeGreaterThan(0);
    expect(n.body).toContain('Platinum');
    expect(n.body).toContain('2');
  });
});
