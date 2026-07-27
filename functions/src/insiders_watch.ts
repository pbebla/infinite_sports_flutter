// Infinite Insiders referral counting/voiding watcher (Task X1). Orchestration
// only — every decision is pure in src/lib/insiders.ts. Watches every
// registration submission's Paid flip and maintains /Referrals,
// /ReferredUsers (the global once-ever guard) and each Insider's counters +
// tier, notifying the Insider by FCM token (not a topic — this is a private,
// per-user event, unlike the tournament/league condition-based alerts in
// index.ts/league_watch.ts).
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §3
// (lifecycle), §9 (data shapes), §10 (automation). Plan:
// docs/superpowers/plans/2026-07-27-infinite-insiders.md Task X1.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueWritten } from 'firebase-functions/v2/database';
import type { DatabaseEvent, DataSnapshot } from 'firebase-functions/v2/database';
import type { Change } from 'firebase-functions/v2';
import type { Reference } from 'firebase-admin/database';
import {
  counterUpdates, decideOnPaidFlip, InsiderNotification, notificationFor,
} from './lib/insiders';

const BRAND_COLOR = '#D00000'; // infiniteSportsPrimaryColor (RGB 208,0,0)

/** Same-instance root (matters in the emulator) — index.ts/league_watch.ts
 *  dbRoot parity. */
function dbRoot(event: DatabaseEvent<Change<DataSnapshot>>): Reference {
  return event.data.before.ref.root as Reference;
}

/** Sends one notification straight to an Insider's stored device token
 *  (campaign_watch.ts sendToUids' single-recipient twin — this is a private
 *  per-user event, not a topic broadcast). Errors are logged and swallowed:
 *  the referral ledger writes have already committed by the time this runs,
 *  so a push failure must never fail (and retry) the whole trigger.
 *  Exported for reuse by insiders_maintenance.ts (Task X2) — same delivery
 *  mechanism, different trigger. */
export async function sendToInsider(
  root: Reference, uid: string, notification: InsiderNotification,
): Promise<void> {
  try {
    const snap = await root.child(`Users/${uid}/Token`).get();
    const token = String(snap.val() ?? '').trim();
    if (!token) return;
    if (process.env.FUNCTIONS_EMULATOR === 'true') {
      logger.info('DRY-RUN insider notification', { uid, title: notification.title });
      return;
    }
    await admin.messaging().send({
      token,
      notification: {
        title: notification.title,
        ...(notification.body ? { body: notification.body } : {}),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'infinite_sports_notifications',
          sound: 'default',
          color: BRAND_COLOR,
        },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch (err) {
    logger.error('insider notification failed', { uid, error: String(err) });
  }
}

/** ReferredName for a fresh /Referrals entry: prefer the submission's
 *  Answers.firstName/lastName (well-known keys, registration_models.dart),
 *  falling back to the top-level DisplayName, then ''. */
function deriveReferredName(after: Record<string, unknown>): string {
  const answers = (after['Answers'] ?? {}) as Record<string, unknown>;
  const first = typeof answers['firstName'] === 'string' ? answers['firstName'] as string : '';
  const last = typeof answers['lastName'] === 'string' ? answers['lastName'] as string : '';
  const combined = `${first} ${last}`.trim();
  if (combined) return combined;
  const displayName = after['DisplayName'];
  return typeof displayName === 'string' ? displayName : '';
}

/** Atomically applies +1 (count) or -1 (void) to one Insider's counters +
 *  recomputed Tier via a transaction on the Insider node itself — this is
 *  the ONLY place counters are written, so concurrent referrals for the
 *  same Insider never lose an update. Returns null if the transaction never
 *  committed (Insider node vanished mid-flight, etc). */
async function applyInsiderCounterDelta(
  root: Reference, insiderUid: string, delta: 1 | -1,
): Promise<{ oldTier: number; newTier: number; tierChanged: boolean } | null> {
  const insiderRef = root.child(`Insiders/${insiderUid}`);
  let captured: { oldTier: number; newTier: number; tierChanged: boolean } | null = null;
  const result = await insiderRef.transaction((current) => {
    const cur = (current ?? {}) as Record<string, unknown>;
    const standing = Number(cur['CurrentStanding'] ?? 0);
    const total = Number(cur['TotalReferred'] ?? 0);
    const yearCount = Number(cur['CurrentYearCount'] ?? 0);
    const updated = counterUpdates({ standing, total, yearCount, delta });
    captured = {
      oldTier: updated.oldTier, newTier: updated.newTier, tierChanged: updated.tierChanged,
    };
    return {
      ...cur,
      CurrentStanding: updated.standing,
      TotalReferred: updated.total,
      CurrentYearCount: updated.yearCount,
      Tier: updated.newTier,
      // Raw sentinel: admin.database.ServerValue is unavailable inside a
      // transaction callback in the emulator (index.ts claimKey parity).
      LastReferralAt: { '.sv': 'timestamp' },
    };
  });
  return result.committed ? captured : null;
}

/** Increments /Registrations/{regId}/Promo/Used by 1 via transaction — only
 *  called on the count path when the submission redeemed the first-timer
 *  promo (DiscountSource=='first_timer_promo'). Never decremented on void:
 *  spec §3 "Already-redeemed Insider discounts are NOT clawed back." applies
 *  to promo redemptions too — a used slot stays used. */
async function incrementPromoUsed(root: Reference, regId: string): Promise<void> {
  await root.child(`Registrations/${regId}/Promo/Used`).transaction(
    (current) => Number(current ?? 0) + 1,
  );
}

async function handleCount(
  root: Reference, regId: string, subId: string, after: Record<string, unknown>,
): Promise<void> {
  const referredUid = subId;
  const insiderCode = String(after['InsiderCode'] ?? '').trim().toUpperCase();

  const alreadyReferredSnap = await root.child(`ReferredUsers/${referredUid}`).get();
  const alreadyReferredEntry = alreadyReferredSnap.exists() ? String(alreadyReferredSnap.val()) : null;

  let insiderUid: string | null = null;
  let insiderStatus = '';
  if (insiderCode) {
    const codeSnap = await root.child(`InsiderCodes/${insiderCode}`).get();
    const v = codeSnap.val();
    insiderUid = typeof v === 'string' && v.length > 0 ? v : null;
    if (insiderUid) {
      const statusSnap = await root.child(`Insiders/${insiderUid}/Status`).get();
      insiderStatus = String(statusSnap.val() ?? '');
    }
  }

  const decision = decideOnPaidFlip({
    wasPaid: false,
    isPaid: true,
    insiderCode,
    referredUid,
    insiderUid,
    insiderStatus,
    alreadyReferredEntry,
    hasCountedReferralForSubmission: false,
  });

  if (decision.action !== 'count' || !insiderUid) {
    logger.info('insider count skipped', { regId, subId, reason: decision.reason });
    return;
  }

  const newRef = root.child('Referrals').push();
  const referralId = newRef.key;
  if (!referralId) {
    logger.error('failed to generate Referrals push id', { regId, subId });
    return;
  }

  // Once-ever lock: the real race-safe guard (the decision above only
  // reflects a point-in-time read). Two submissions can never win this for
  // the same referredUid.
  const referredUsersRef = root.child(`ReferredUsers/${referredUid}`);
  const claim = await referredUsersRef.transaction(
    (current) => (current === null ? referralId : undefined),
  );
  if (!claim.committed) {
    logger.info('insider count aborted — once-ever guard already claimed', {
      regId, subId, referredUid,
    });
    return;
  }

  const configSnap = await root.child(`Registrations/${regId}/Config`).get();
  const config = (configSnap.val() ?? {}) as Record<string, unknown>;
  const sport = String(config['Sport'] ?? '');
  const offeringType = config['TargetType'] === 'tournament' || config['TargetType'] === 'league'
    ? String(config['TargetType']) : '';
  const path = String(after['Path'] ?? '');
  const isTeamRegistration = path === 'captain';
  const referredName = deriveReferredName(after);

  await newRef.set({
    InsiderUid: insiderUid,
    ReferredUid: referredUid,
    RegistrationId: `${regId}/${subId}`,
    Sport: sport,
    OfferingType: offeringType,
    IsTeamRegistration: isTeamRegistration,
    State: 'counted',
    Verified: false,
    CountedAt: admin.database.ServerValue.TIMESTAMP,
    ...(referredName ? { ReferredName: referredName } : {}),
  });

  const discountSource = String(after['DiscountSource'] ?? '');
  if (discountSource === 'first_timer_promo') {
    await incrementPromoUsed(root, regId);
  }

  const delta = await applyInsiderCounterDelta(root, insiderUid, 1);
  if (!delta) {
    logger.error('insider counter transaction did not commit on count', {
      insiderUid, regId, subId,
    });
    return;
  }

  await sendToInsider(root, insiderUid, notificationFor({
    type: 'referral', referredName: referredName || 'Someone', sport: sport || 'a league',
  }));
  if (delta.tierChanged) {
    await sendToInsider(root, insiderUid, notificationFor({
      type: delta.newTier > delta.oldTier ? 'tierUp' : 'tierDown', tier: delta.newTier,
    }));
  }
  logger.info('insider referral counted', { regId, subId, insiderUid, referralId });
}

async function handleVoid(root: Reference, regId: string, subId: string): Promise<void> {
  const referredUid = subId;
  const pointerSnap = await root.child(`ReferredUsers/${referredUid}`).get();
  const referralId = pointerSnap.exists() ? String(pointerSnap.val()) : null;
  if (!referralId) {
    logger.info('insider void skipped — no referral on record', { regId, subId });
    return;
  }

  const referralRef = root.child(`Referrals/${referralId}`);
  const referralSnap = await referralRef.get();
  const referral = referralSnap.val() as Record<string, unknown> | null;
  if (!referral) {
    logger.warn('insider void skipped — referral pointer is dangling', {
      regId, subId, referralId,
    });
    return;
  }

  const matchesThisSubmission = referral['RegistrationId'] === `${regId}/${subId}`;
  const hasCountedReferralForSubmission = matchesThisSubmission && referral['State'] === 'counted';

  const decision = decideOnPaidFlip({
    wasPaid: true,
    isPaid: false,
    insiderCode: '',
    referredUid,
    insiderUid: null,
    insiderStatus: '',
    alreadyReferredEntry: referralId,
    hasCountedReferralForSubmission,
  });

  if (decision.action !== 'void') {
    logger.info('insider void skipped', { regId, subId, referralId, reason: decision.reason });
    return;
  }

  const insiderUid = String(referral['InsiderUid'] ?? '');
  if (!insiderUid) {
    logger.warn('insider void skipped — referral missing InsiderUid', {
      regId, subId, referralId,
    });
    return;
  }

  await referralRef.update({
    State: 'voided',
    VoidedAt: admin.database.ServerValue.TIMESTAMP,
    VoidReason: 'payment reversed',
  });
  await root.child(`ReferredUsers/${referredUid}`).remove();

  const delta = await applyInsiderCounterDelta(root, insiderUid, -1);
  if (!delta) {
    logger.error('insider counter transaction did not commit on void', {
      insiderUid, regId, subId,
    });
    return;
  }

  await sendToInsider(root, insiderUid, notificationFor({ type: 'voided' }));
  if (delta.tierChanged) {
    await sendToInsider(root, insiderUid, notificationFor({
      type: delta.newTier > delta.oldTier ? 'tierUp' : 'tierDown', tier: delta.newTier,
    }));
  }
  logger.info('insider referral voided', { regId, subId, insiderUid, referralId });
}

/** Watches every registration submission for a Paid flip and drives the
 *  referral ledger (spec §3, §10). Fires on ANY write to a submission, so it
 *  bails immediately unless Paid actually flipped. */
export const onSubmissionPaidChange = onValueWritten(
  '/Registrations/{regId}/Submissions/{subId}',
  async (event) => {
    const regId = String(event.params['regId']);
    const subId = String(event.params['subId']);
    const before = (event.data.before.val() ?? {}) as Record<string, unknown>;
    const after = (event.data.after.val() ?? {}) as Record<string, unknown>;
    const wasPaid = before['Paid'] === true;
    const isPaid = after['Paid'] === true;
    if (wasPaid === isPaid) return; // no flip — nothing for this watcher to do

    const root = dbRoot(event);
    if (!wasPaid && isPaid) {
      await handleCount(root, regId, subId, after);
    } else {
      await handleVoid(root, regId, subId);
    }
  },
);
