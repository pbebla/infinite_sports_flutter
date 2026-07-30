// Pure Infinite Insiders referral-lifecycle logic (functions Task X1). No
// Firebase/Stripe imports — unit-tested directly (test/insiders.test.ts).
// The impure RTDB trigger that calls these lives in src/insiders_watch.ts;
// this file only holds deterministic decisions so they TDD without an
// emulator, mirroring the pure/impure split of lib/decide.ts and
// lib/stripe_pay.ts.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §2
// (tiers), §3 (referral lifecycle — count/void/once-ever), §5 (discount
// stacking/ceiling), §9 (RTDB shape), §10 (automation). Plan:
// docs/superpowers/plans/2026-07-27-infinite-insiders.md Task X1.

// ---------------------------------------------------------------------------
// Tiers (spec §2) — byte-identical thresholds/names to the fan's
// lib/model/insider.dart and the Manager's lib/models/insider_models.dart.
// ---------------------------------------------------------------------------

/** Ladder thresholds, index == tier (index 0 is "no tier", unused as a
 *  threshold). Tier N is reached at CurrentStanding >= thresholds[N]. */
const TIER_THRESHOLDS = [0, 5, 10, 15, 20, 25];

const TIER_NAMES = ['', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Infinite'];

const TIER_DISCOUNT_PCT = [0, 5, 10, 15, 20, 25];

/** Maps a ladder-progress counter to a tier 0-5 (0 = no tier, below Bronze).
 *  Bronze >=5, Silver >=10, Gold >=15, Platinum >=20, Infinite >=25+. */
export function tierForStanding(standing: number): number {
  let tier = 0;
  for (let t = 1; t < TIER_THRESHOLDS.length; t++) {
    if (standing >= TIER_THRESHOLDS[t]) tier = t;
  }
  return tier;
}

/** Display name for a tier (0 = ''). Out-of-range tiers return ''. */
export function tierName(tier: number): string {
  return tier >= 0 && tier < TIER_NAMES.length ? TIER_NAMES[tier] : '';
}

/** The Insider's own-registration-fee discount percent for a tier.
 *  Out-of-range tiers return 0. */
export function tierDiscountPct(tier: number): number {
  return tier >= 0 && tier < TIER_DISCOUNT_PCT.length ? TIER_DISCOUNT_PCT[tier] : 0;
}

// ---------------------------------------------------------------------------
// Payment-flip decision (spec §3, §11)
// ---------------------------------------------------------------------------

export type PaidFlipAction = 'count' | 'void' | 'none';

export interface PaidFlipDecision {
  action: PaidFlipAction;
  reason: string;
}

export interface PaidFlipInput {
  /** Paid before this write. */
  wasPaid: boolean;
  /** Paid after this write. */
  isPaid: boolean;
  /** The submission's stamped InsiderCode, normalized uppercase; '' if none
   *  was entered. */
  insiderCode: string;
  /** The uid of the registrant whose submission just flipped (the
   *  Submissions/{subId} key — the registrant IS the referred user). */
  referredUid: string;
  /** The uid `/InsiderCodes/{insiderCode}` resolves to, or null when the
   *  code doesn't resolve to any Insider. */
  insiderUid: string | null;
  /** `/Insiders/{insiderUid}/Status`; '' when missing/unknown (treated the
   *  same as any non-'active' status — suspended). */
  insiderStatus: string;
  /** The current `/ReferredUsers/{referredUid}` value (a referralId), or
   *  null when no entry exists yet. Used as the once-ever guard on the
   *  count path. */
  alreadyReferredEntry: string | null;
  /** True when a /Referrals entry with State=='counted' exists whose
   *  RegistrationId matches THIS submission ('{regId}/{subId}') — the fact
   *  the void path needs to know there's something to reverse. Irrelevant
   *  on the count path. */
  hasCountedReferralForSubmission: boolean;
}

/**
 * Decides what a submission's Paid flip should do to the referral ledger.
 *
 * COUNT iff the flip is unpaid->paid AND a code was entered AND the code
 * resolves to an Insider AND that Insider is active AND the Insider isn't
 * the referred user themselves (self-referral) AND the referred user has no
 * prior referral on record (global once-ever guard, spec §3).
 *
 * VOID iff the flip is paid->unpaid AND a counted referral for THIS
 * submission already exists (an already-voided or nonexistent referral
 * yields 'none' — nothing to reverse; that's the idempotency guard the
 * watcher relies on for safe re-delivery).
 *
 * Anything else (Paid didn't actually flip, or a paid->unpaid flip with no
 * matching counted referral) is 'none'.
 */
export function decideOnPaidFlip(input: PaidFlipInput): PaidFlipDecision {
  const {
    wasPaid, isPaid, insiderCode, referredUid, insiderUid, insiderStatus,
    alreadyReferredEntry, hasCountedReferralForSubmission,
  } = input;

  if (wasPaid === isPaid) {
    return { action: 'none', reason: 'Paid did not flip' };
  }

  if (!wasPaid && isPaid) {
    if (!insiderCode) {
      return { action: 'none', reason: 'no Insider code on this submission' };
    }
    if (!insiderUid) {
      return { action: 'none', reason: 'code does not resolve to an Insider' };
    }
    if (insiderStatus !== 'active') {
      return { action: 'none', reason: 'Insider is not active' };
    }
    if (insiderUid === referredUid) {
      return { action: 'none', reason: 'self-referral' };
    }
    if (alreadyReferredEntry) {
      return { action: 'none', reason: 'referred user already has a referral on record' };
    }
    return {
      action: 'count',
      reason: 'newly paid, valid active code, no self-referral, no prior referral',
    };
  }

  // paid -> unpaid (refund/unmark)
  if (!hasCountedReferralForSubmission) {
    return { action: 'none', reason: 'no counted referral on record for this submission' };
  }
  return { action: 'void', reason: 'payment reversed on a previously counted referral' };
}

// ---------------------------------------------------------------------------
// Counter math (spec §2, §3)
// ---------------------------------------------------------------------------

export interface CounterUpdatesInput {
  standing: number;
  total: number;
  yearCount: number;
  /** +1 on count, -1 on void. */
  delta: 1 | -1;
}

export interface CounterUpdatesResult {
  standing: number;
  total: number;
  yearCount: number;
  oldTier: number;
  newTier: number;
  tierChanged: boolean;
}

/** New counters after a count (+1) or void (-1), floored at 0 (spec §3 "void
 *  decrement counters (floor 0)"), plus the tier before/after so the
 *  watcher knows whether to send a tier-change notification. */
export function counterUpdates(input: CounterUpdatesInput): CounterUpdatesResult {
  const { standing, total, yearCount, delta } = input;
  const oldTier = tierForStanding(standing);
  const newStanding = Math.max(0, standing + delta);
  const newTotal = Math.max(0, total + delta);
  const newYearCount = Math.max(0, yearCount + delta);
  const newTier = tierForStanding(newStanding);
  return {
    standing: newStanding,
    total: newTotal,
    yearCount: newYearCount,
    oldTier,
    newTier,
    tierChanged: oldTier !== newTier,
  };
}

// ---------------------------------------------------------------------------
// Tier-maintenance decision (spec §2 inactivity + Infinite annual, Task X2)
// ---------------------------------------------------------------------------

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/** 30-day "months" (documented, not calendar months — a daily cron only
 *  needs a stable, easily-tested elapsed-time threshold, not calendar-aware
 *  month boundaries). 5mo/5.5mo/6mo -> 150/165/180 days. */
const INACTIVITY_REMIND_DAYS = 150;
const INACTIVITY_WARN_DAYS = 165;
const INACTIVITY_DROP_DAYS = 180;

/** Referrals required per calendar year (America/Los_Angeles) to keep
 *  Infinite (spec §2 "Infinite maintenance"). */
const INFINITE_ANNUAL_QUOTA = 5;

export type MaintenanceAction =
  | 'none' | 'remind5mo' | 'warn2wk' | 'dropInactivity' | 'dropInfiniteAnnual';

export interface MaintenanceDecision {
  action: MaintenanceAction;
  /** Set only on a drop action. */
  newStanding?: number;
  /** Set only on a drop action. */
  newTier?: number;
}

export interface MaintenanceInput {
  /** /Insiders/{uid}/CurrentStanding. */
  standing: number;
  /** /Insiders/{uid}/Tier (0 = no tier, 1 = Bronze ... 5 = Infinite). */
  tier: number;
  /** /Insiders/{uid}/LastReferralAt (ms). 0/missing is treated as
   *  insufficient data (returns 'none') rather than "infinitely inactive" —
   *  every tier>=2 Insider is stamped on their first counted referral
   *  (insiders_watch.ts applyInsiderCounterDelta), so a missing value here
   *  signals a data gap, not a real inactivity episode. */
  lastReferralAtMs: number;
  /** /Insiders/{uid}/CurrentYearCount — counted referrals so far this
   *  calendar year (America/Los_Angeles); only read when isYearRollover. */
  currentYearCount: number;
  /** The scheduled job's "now", in epoch ms — kept a plain number (not
   *  Date.now() inside this function) so the whole ladder tests
   *  deterministically with fixed fixtures. */
  nowMs: number;
  /** /Insiders/{uid}/LastInactivityRemindedAt (ms), or null/undefined if
   *  never sent. A reminder already sent for the CURRENT inactivity episode
   *  iff this is >= lastReferralAtMs — comparing against lastReferralAtMs
   *  (rather than tracking a separate "episode id") means a new referral
   *  automatically starts a fresh episode: LastReferralAt jumps forward,
   *  so any older stamp is immediately "stale" again. */
  lastReminderSentMs?: number | null;
  /** /Insiders/{uid}/LastInactivityWarnedAt (ms) — same episode rule as
   *  lastReminderSentMs, for the 2-week warning. */
  lastWarnSentMs?: number | null;
  /** True ONLY on the one daily run that lands on Dec 31 or Jan 1 in
   *  America/Los_Angeles (computed by the trigger — see
   *  insiders_maintenance.ts isYearRolloverNow). Kept as a precomputed bool
   *  rather than doing timezone math in here so this function stays a
   *  plain-millis, Intl-free pure function to unit test. */
  isYearRollover?: boolean;
  /** Documentation-only: which wall-clock/timezone basis nowMs represents
   *  at the call site (e.g. 'America/Los_Angeles daily 06:00 run'). Not
   *  read by this function — the only timezone-sensitive judgment (the
   *  annual window) is precomputed into isYearRollover by the caller so
   *  this function never needs Intl/timezone data itself. */
  tzOffsetNote?: string;
}

/**
 * Daily tier-maintenance decision (spec §2, Task X2 scheduled job).
 *
 * Two INDEPENDENT degradation paths, both gated to tier >= 2 (Silver+) —
 * Bronze (1) is the permanent floor and tier 0 has no tier to lose, so both
 * return 'none' unconditionally for tier < 2:
 *
 * 1. Inactivity ladder (checked every day, any tier 2-5): elapsed days since
 *    LastReferralAt, using 30-day "months" (documented above) —
 *    >=150 days -> remind once, >=165 days -> warn once, >=180 days -> drop
 *    ONE tier, landing CurrentStanding on the new tier's own threshold
 *    (Silver(10)->Bronze(5); Gold(15)->Silver(10); Platinum(20)->Gold(15);
 *    Infinite(25+)->Platinum(20) — the general inactivity rule applies to
 *    Infinite too, spec §2 "Silver and above"). Reminders/warnings are
 *    idempotent per episode via the lastReminderSentMs/lastWarnSentMs >=
 *    lastReferralAtMs comparison (see field docs above); the drop itself
 *    needs no such guard because the caller (insiders_maintenance.ts) also
 *    stamps LastReferralAt = now on a drop, which restarts the elapsed-days
 *    clock at 0 — without that, a single stale LastReferralAt would
 *    otherwise cascade into dropping a tier on every subsequent daily run
 *    instead of the single "drop one tier" spec describes.
 * 2. Infinite annual maintenance (checked ONLY when isYearRollover): tier 5
 *    with currentYearCount below the 5-referral quota -> drop to Platinum
 *    (standing 20). CurrentYearCount resetting to 0 for every Insider on
 *    rollover is handled by the trigger, not this function (spec §2 "Year
 *    rollover also resets CurrentYearCount ... handled by trigger").
 *
 * Precedence when both could apply the same day (e.g. a Jan-1 run where an
 * Infinite Insider is BOTH 6-months inactive AND short on the annual quota):
 * the inactivity drop wins — it's evaluated first and returned immediately,
 * so the annual check never double-drops the same Insider in one call.
 */
export function maintenanceDecision(input: MaintenanceInput): MaintenanceDecision {
  const {
    standing, tier, lastReferralAtMs, currentYearCount, nowMs,
    lastReminderSentMs, lastWarnSentMs, isYearRollover,
  } = input;
  void standing; // not needed by the decision itself — kept for call-site symmetry/logging

  const inactivityEligible = tier >= 2 && lastReferralAtMs > 0;
  const daysSinceReferral = inactivityEligible ? (nowMs - lastReferralAtMs) / MS_PER_DAY : -1;

  if (inactivityEligible && daysSinceReferral >= INACTIVITY_DROP_DAYS) {
    const newTier = tier - 1;
    return { action: 'dropInactivity', newTier, newStanding: TIER_THRESHOLDS[newTier] };
  }

  if (isYearRollover && tier === 5 && currentYearCount < INFINITE_ANNUAL_QUOTA) {
    return { action: 'dropInfiniteAnnual', newStanding: TIER_THRESHOLDS[4], newTier: 4 };
  }

  if (inactivityEligible && daysSinceReferral >= INACTIVITY_WARN_DAYS) {
    const alreadyWarned = lastWarnSentMs != null && lastWarnSentMs >= lastReferralAtMs;
    return alreadyWarned ? { action: 'none' } : { action: 'warn2wk' };
  }

  if (inactivityEligible && daysSinceReferral >= INACTIVITY_REMIND_DAYS) {
    const alreadyReminded = lastReminderSentMs != null && lastReminderSentMs >= lastReferralAtMs;
    return alreadyReminded ? { action: 'none' } : { action: 'remind5mo' };
  }

  return { action: 'none' };
}

// ---------------------------------------------------------------------------
// Notification copy (spec §7, §10)
// ---------------------------------------------------------------------------

export interface InsiderNotification {
  title: string;
  body: string;
}

export type InsiderNotificationEvent =
  | { type: 'referral'; referredName: string; sport: string }
  | { type: 'tierUp'; tier: number }
  | { type: 'tierDown'; tier: number }
  | { type: 'voided' }
  | { type: 'maintenanceRemind' }
  | { type: 'maintenanceWarn'; tier: number }
  | { type: 'maintenanceDropped'; tier: number }
  | { type: 'infiniteMaintenanceDropped'; currentYearCount: number };

/** {title, body} for an Insider push (spec §7 "+1 referral", tier up/down;
 *  §10 automation notifications). */
export function notificationFor(event: InsiderNotificationEvent): InsiderNotification {
  switch (event.type) {
    case 'referral':
      return {
        title: '🎉 +1!',
        body: `${event.referredName} joined ${event.sport} with your code`,
      };
    case 'tierUp':
      return {
        title: 'Tier up!',
        body: `You're now ${tierName(event.tier)} (${tierDiscountPct(event.tier)}% off)`,
      };
    case 'tierDown':
      return {
        title: 'Tier update',
        body: event.tier > 0
          ? `You're now ${tierName(event.tier)} (${tierDiscountPct(event.tier)}% off)`
          : "You're currently below Bronze — keep referring to climb back up!",
      };
    case 'voided':
      return {
        title: 'Referral update',
        body: 'One of your referrals was reversed after a payment change.',
      };
    case 'maintenanceRemind':
      return {
        title: 'Keep climbing!',
        body: 'Bring players to keep your tier! 5 months without a referral.',
      };
    case 'maintenanceWarn':
      return {
        title: 'Tier at risk',
        body: `2 weeks until your tier drops — refer a new player to keep ${tierName(event.tier)}.`,
      };
    case 'maintenanceDropped':
      return {
        title: 'Tier update',
        body: `Your tier dropped to ${tierName(event.tier)}. Bring new players to climb back up.`,
      };
    case 'infiniteMaintenanceDropped':
      return {
        title: 'Infinite maintenance',
        body: `You finished the year with ${event.currentYearCount} referral`
          + `${event.currentYearCount === 1 ? '' : 's'} (5 needed to keep Infinite) — `
          + "you're now Platinum. Refer 5 more this year to climb back to Infinite.",
      };
  }
}

// ---------------------------------------------------------------------------
// Server-side charge math (spec §4, §5) — cents twin of the fan's
// promo_engine.dart bestDiscountedTotal (dollars) + payment_adjustment.dart
// adjustedOwed. MUST agree with those on every case; when one changes,
// check the others.
// ---------------------------------------------------------------------------

export interface EffectiveChargeInput {
  /** The amount (cents) owed before any Insider/first-timer discount —
   *  functions/src/lib/stripe_pay.ts owedCents(). */
  baseCents: number;
  /** Submission.EligibleFee (dollars) — the base the first-timer promo
   *  percent was computed against. */
  eligibleFee?: number | null;
  /** Submission.AdjustedFee (dollars) — an absolute new total, manual mode. */
  adjustedFee?: number | null;
  /** Submission.DiscountPct — percent off, either mode. */
  discountPct?: number | null;
  /** Submission.DiscountSource: '' | 'manual' | 'first_timer_promo' |
   *  'insider_tier'. */
  discountSource: string;
}

function dollarsToCents(dollars: number): number {
  return Math.round(dollars * 100);
}

/** Cents twin of payment_adjustment.dart's adjustedOwed. */
function adjustedOwedCents(
  baseCents: number, adjustedFeeCents: number | null, discountPct: number | null,
): number {
  if (adjustedFeeCents != null) return Math.max(0, Math.round(adjustedFeeCents));
  if (discountPct != null) {
    return Math.max(0, Math.round(baseCents * (1 - discountPct / 100)));
  }
  return Math.max(0, Math.round(baseCents));
}

/** Cents twin of promo_engine.dart's promoDiscountedTotal. */
function promoDiscountedCents(eligibleCents: number, pct: number): number {
  return Math.max(0, Math.round(eligibleCents * (1 - pct / 100)));
}

/**
 * The amount (integer cents) to actually charge via Stripe once a
 * submission's stamped discount fields are taken into account —
 * best-discount-wins (spec §5): a manual admin adjustment
 * (DiscountSource=='manual', absolute AdjustedFee wins over DiscountPct), an
 * automatic first-timer promo (DiscountSource=='first_timer_promo'), or the
 * registrant's OWN Insider tier discount (DiscountSource=='insider_tier',
 * Task F5 — spec §2) — the latter two compute IDENTICALLY (a plain percent
 * off EligibleFee; the fan's promo_engine.dart pickBestDiscount already
 * picked the single winning automatic source before the submission was
 * ever written, so only one of them is ever actually stamped) — whichever
 * total is LOWER, mirroring bestDiscountedTotal's defensive "both plausible
 * -> bigger discount wins" rule. No discount fields at all -> [baseCents]
 * unchanged. Always clamped to zero or more and rounded to the nearest
 * cent.
 */
export function effectiveCharge(input: EffectiveChargeInput): number {
  const { eligibleFee, adjustedFee, discountPct, discountSource } = input;
  const baseCents = Math.max(0, Math.round(input.baseCents));
  if (adjustedFee == null && discountPct == null) return baseCents;

  const adjustedFeeCents = adjustedFee != null ? dollarsToCents(adjustedFee) : null;
  const eligibleCents = eligibleFee != null ? dollarsToCents(eligibleFee) : null;

  const manualTotal = discountSource === 'manual'
    ? adjustedOwedCents(baseCents, adjustedFeeCents, discountPct ?? null)
    : null;
  const isAutomaticPromo = discountSource === 'first_timer_promo'
    || discountSource === 'insider_tier';
  const promoTotal = isAutomaticPromo && discountPct != null
    ? promoDiscountedCents(eligibleCents ?? baseCents, discountPct)
    : null;

  const candidates = [manualTotal, promoTotal].filter((v): v is number => v != null);
  if (candidates.length === 0) {
    // Unrecognized/legacy discountSource but fields are set anyway — fall
    // back to the manual-only precedence rule (bestDiscountedTotal parity).
    return adjustedOwedCents(baseCents, adjustedFeeCents, discountPct ?? null);
  }
  return Math.min(...candidates);
}
