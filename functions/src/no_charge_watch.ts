// "No charge" auto-stamp triggers (plan 2026-11-14-no-charge-payment-option,
// Task 6, owner-approved): a brand-new sign-up that owes nothing starts out as
// Paid / 'no charge' / 0. Only NEW submissions are stamped (onValueCreated);
// nothing here ever changes an existing one, and a later fee change re-stamps
// nobody. The Insiders watcher gives no referral credit for 'no charge'.
//
// onLegacyNotPaidCreated: the fan app writes the submission and then, as a
// second write, its legacy NotPaid entry - which can land after the stamp.
// After a settle delay (the old Manager moves entries as two writes: set
// NotPaid, then remove Paid) it removes NotPaid only if Paid still exists.
//
// Logs carry only a 6-character uid prefix, never names or emails.

import * as logger from 'firebase-functions/logger';
import { onValueCreated } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  parseConfigPricing, parseSubmission, parseTeam,
} from './createRegistrationPaymentIntent';
import { buildNoChargeUpdate, shouldStampNoCharge } from './lib/no_charge';
import { legacyTarget, TeamLike } from './lib/stripe_pay';

/** How long the legacy cleanup waits for a two-write move to finish. */
export const SETTLE_MS = 5000;

const uidPrefix = (uid: string): string => uid.slice(0, 6);
const realDelay = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, SETTLE_MS));

export async function handleSubmissionCreated(
  root: Reference, regId: string, uid: string,
): Promise<'stamped' | 'skipped'> {
  const [configSnap, subSnap] = await Promise.all([
    root.child(`Registrations/${regId}/Config`).get(),
    root.child(`Registrations/${regId}/Submissions/${uid}`).get(),
  ]);
  const config = parseConfigPricing(configSnap.val());
  const raw = subSnap.val();
  const submission = parseSubmission(raw);
  if (!config || !submission) return 'skipped';

  let team: TeamLike | undefined;
  if (submission.path === 'joiner') {
    const teamId = (raw as Record<string, unknown>)['TeamId'];
    if (typeof teamId === 'string' && teamId.length > 0) {
      const teamSnap = await root.child(`Registrations/${regId}/Teams/${teamId}`).get();
      team = parseTeam(teamSnap.val()) ?? undefined;
    }
  }
  // Re-checked on the fresh read: an already-paid submission is never touched.
  if (!shouldStampNoCharge(config, submission, team)) return 'skipped';

  const name = (raw as Record<string, unknown>)['DisplayName'];
  await root.update(buildNoChargeUpdate(regId, uid, legacyTarget(config), typeof name === 'string' ? name : ''));
  logger.info('stamped no charge', { regId, uid: uidPrefix(uid) });
  return 'stamped';
}

export async function handleLegacyNotPaidCreated(
  root: Reference, league: string, season: string, uid: string,
  delay: () => Promise<void> = realDelay,
): Promise<'removed' | 'kept' | 'gone'> {
  await delay();
  const base = `Sign Ups/${league}/${season}`;
  const [paidSnap, notPaidSnap] = await Promise.all([
    root.child(`${base}/Paid/${uid}`).get(),
    root.child(`${base}/NotPaid/${uid}`).get(),
  ]);
  if (notPaidSnap.val() === null || notPaidSnap.val() === undefined) return 'gone';
  if (paidSnap.val() === null || paidSnap.val() === undefined) return 'kept';
  await root.child(`${base}/NotPaid/${uid}`).remove();
  logger.info('removed stray NotPaid next to Paid', { uid: uidPrefix(uid) });
  return 'removed';
}

export const onSubmissionCreatedStampNoCharge = onValueCreated(
  '/Registrations/{regId}/Submissions/{uid}',
  async (event) => {
    await handleSubmissionCreated(
      event.data.ref.root as Reference, String(event.params['regId']), String(event.params['uid']),
    );
  },
);

export const onLegacyNotPaidCreated = onValueCreated(
  '/Sign Ups/{league}/{season}/NotPaid/{uid}',
  async (event) => {
    await handleLegacyNotPaidCreated(
      event.data.ref.root as Reference,
      String(event.params['league']), String(event.params['season']), String(event.params['uid']),
    );
  },
);
