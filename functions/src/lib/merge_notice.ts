// Merge notices (plan 2026-11-06-merge-duplicate-accounts, Task 6; design
// D11 + D12): what a player is told when their duplicate accounts were
// combined. Pure - the email trigger (src/merge_notice_watch.ts) and the
// merge tool's `--notify` (tools/merge_accounts.ts) both build their text and
// nodes from here, so the copy lives in exactly one place.
//
// No email address is ever stored: the hint is the MASKED kept address
// (maskEmail), and the trigger reads the old address from Firebase Auth only
// at send time.

import * as crypto from 'crypto';
import { escapeHtml } from './support';

// ── D11: the email to each old address ────────────────────────────────────

export const MERGE_NOTICE_SUBJECT = 'Your Infinite Sports accounts were combined';

/** The subject + HTML body of the notice. [hint] is the masked kept email
 *  (e.g. `ca••••••••@gmail.com`); it is escaped like any other data. With no
 *  hint (the kept account has no email on file) the sentence points at "your
 *  other email" rather than leaving a gap. The copy is fixed; only the hint
 *  varies. */
export function mergeNoticeEmail(hint?: string | null): { subject: string; html: string } {
  const shown = typeof hint === 'string' && hint.trim() !== '' ? escapeHtml(hint.trim()) : 'your other email';
  return {
    subject: MERGE_NOTICE_SUBJECT,
    html:
      '<p>Hi, we combined your Infinite Sports accounts so all of your seasons show on one profile. ' +
      `From now on, please sign in with ${shown}. ` +
      "If you didn't expect this, just reply to this email.</p>",
  };
}

/** The send-once transaction on `MergeNotices/<uid>/Status` (the
 *  campaignClaim twin): an absent Status is claimed ('sending'), any existing
 *  Status aborts - so a second invocation, or a retry, can never send again.
 *  A null/undefined current is a CLAIM, not an abort: RTDB's first run sees
 *  the function's empty cache, and if the server already holds a Status it
 *  rejects the commit and re-runs this on the real value, which aborts. */
export function noticeClaim(current: unknown): 'sending' | undefined {
  return current === null || current === undefined ? 'sending' : undefined;
}

// ── D12: the push to each kept account ────────────────────────────────────

export const MERGE_PUSH_TITLE = 'Your accounts were combined';
export const MERGE_PUSH_BODY = 'All your seasons are now on this profile.';

/** A kept account's uid as a campaign key: a non-blank string, or a clear error. */
function keptUidOf(keepUid: unknown): string {
  if (typeof keepUid !== 'string' || keepUid.trim() === '') {
    throw new Error('A merge-notice campaign needs a kept account (no kept account given).');
  }
  return keepUid;
}

/** The deterministic campaign id of ONE kept account: derived from that uid
 *  alone (never from the rest of the map), so a re-run of `--notify` finds the
 *  campaign it already wrote for that person, and adding another person to the
 *  map later creates only that person's campaign - nobody is pushed twice. */
export function mergeNoticeCampaignId(keepUid: string): string {
  const digest = crypto.createHash('sha256').update(keptUidOf(keepUid)).digest('hex');
  return `merge-notice-${digest.slice(0, 16)}`;
}

/** The `Campaigns/<id>` node for ONE kept account: exactly what the Manager
 *  app writes (CampaignModel.toJson) so parseCampaign accepts it, the existing
 *  `onCampaignCreated` sends it at once (SendAt 0 = now) and the Manager's
 *  campaign list shows it. `CreatedAt` is the caller's clock (the tool has
 *  no server timestamp over REST). */
export function mergeNoticeCampaign(keepUid: string, nowMs: number): Record<string, unknown> {
  const uid = keptUidOf(keepUid);
  return {
    Title: MERGE_PUSH_TITLE,
    Body: MERGE_PUSH_BODY,
    Audience: { Type: 'users', Uids: { [uid]: true } },
    Data: { type: 'campaign' },
    SendAt: 0,
    Status: 'pending',
    CreatedBy: 'merge-accounts-tool',
    CreatedAt: nowMs,
  };
}
