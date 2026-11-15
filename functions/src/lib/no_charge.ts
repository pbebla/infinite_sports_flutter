// Pure "No charge" stamp logic (plan 2026-11-14-no-charge-payment-option,
// Task 6). A brand-new sign-up that owes nothing starts out as
// Paid / PaidVia 'no charge' / PaidAmount 0. No Firebase imports.

import { NO_CHARGE } from './insiders';
import {
  owedCents, RegistrationConfigLike, SubmissionLike, TeamLike,
} from './stripe_pay';

/** True only for a not-yet-paid sign-up that owes nothing AND is not a joiner
 *  on a code-waives-payment team (that joiner is already handled by the
 *  waiver, so it keeps its own state). A joiner with no team owes the full
 *  fee (owedCents fails closed), so it is never stamped. */
export function shouldStampNoCharge(
  config: RegistrationConfigLike, sub: SubmissionLike, team?: TeamLike,
): boolean {
  if (sub.paid) return false;
  if (owedCents(config, sub, team) !== 0) return false;
  if (sub.path === 'joiner' && team?.codeWaivesPayment) return false;
  return true;
}

/** The one root multi-path update: the submission's payment fields plus the
 *  legacy mirror move (NotPaid -> Paid). The legacy value is the display name,
 *  else the uid (same fallback as the Manager's _setPaid). */
export function buildNoChargeUpdate(
  regId: string, uid: string, target: { league: string; season: string }, displayName: string,
): Record<string, unknown> {
  const sub = `Registrations/${regId}/Submissions/${uid}`;
  const update: Record<string, unknown> = {
    [`${sub}/Paid`]: true,
    [`${sub}/PaidVia`]: NO_CHARGE,
    [`${sub}/PaidAmount`]: 0,
  };
  if (target.league.length > 0 && target.season.length > 0) {
    const legacy = `Sign Ups/${target.league}/${target.season}`;
    update[`${legacy}/NotPaid/${uid}`] = null;
    update[`${legacy}/Paid/${uid}`] = displayName.trim().length > 0 ? displayName.trim() : uid;
  }
  return update;
}
