// Merge-notice email trigger (plan 2026-11-06-merge-duplicate-accounts, Task 6;
// design D11). The merge tool's `--notify` writes MergeNotices/<oldUid> =
// {KeepHint, CreatedAt} - a MASKED hint of the account to sign in with and no
// address. This trigger turns each node into one email to the OLD account's
// address, read from Firebase Auth at send time (getUser also works for a
// disabled account), through the support mailer.
//
// Send-once: the node is claimed first with a transaction on Status
// (absent -> 'sending'); an existing Status aborts, so a second invocation or
// a retry can never email twice - even a run that died mid-send stays
// 'sending' rather than risk a duplicate. To re-send one, delete the node and
// run `--notify` again (it rewrites absent nodes).
//
// Then Status becomes 'sent' | 'no-email' | 'failed' (+ At; a failure also
// records an Error message with any address redacted). In the emulator it is
// 'dry-run' and nothing is read or sent. MergeNotices has no rules entry, so
// clients are denied; only the admin SDK and the tool (admin REST) touch it.
//
// Orchestration only: the copy and the claim are pure in lib/merge_notice.ts.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueCreated } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import { redactEmails } from './lib/mask_email';
import { mergeNoticeEmail, noticeClaim } from './lib/merge_notice';
import {
  MailOutcome, sendMail, SendMailOptions, SupportMailMessage, SUPPORT_MAIL_SECRETS,
} from './support_mail';

export type MergeNoticeOutcome = 'sent' | 'no-email' | 'failed' | 'dry-run' | 'already-handled';

/** The impure edges, injectable so the handler runs without SMTP or Auth. */
export interface MergeNoticeDeps {
  /** The old account's email from Firebase Auth; null/'' when it has none. */
  getEmail(uid: string): Promise<string | null | undefined>;
  sendMail(root: Reference, message: SupportMailMessage, options: SendMailOptions): Promise<MailOutcome>;
  emulator: boolean;
  /** The value written to `At` (the RTDB server-timestamp sentinel live). */
  at(): unknown;
}

const liveDeps = (): MergeNoticeDeps => ({
  getEmail: async (uid) => (await admin.auth().getUser(uid)).email ?? null,
  sendMail,
  emulator: process.env.FUNCTIONS_EMULATOR === 'true',
  // Raw sentinel (support_watch parity - safe in the emulator's admin shim).
  at: () => ({ '.sv': 'timestamp' }),
});

/** A stored error: the message only, any address redacted, bounded. */
function safeMessage(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  return redactEmails(msg).slice(0, 200) || 'unknown error';
}

export async function handleMergeNotice(
  root: Reference, uid: string, deps: MergeNoticeDeps = liveDeps(),
): Promise<MergeNoticeOutcome> {
  const noticeRef = root.child(`MergeNotices/${uid}`);
  const claim = await noticeRef.child('Status').transaction(noticeClaim);
  // Someone already claimed (or finished) it: send nothing.
  if (!claim.committed || claim.snapshot.val() !== 'sending') return 'already-handled';

  let status: Exclude<MergeNoticeOutcome, 'already-handled'> = 'failed';
  let error: string | undefined;
  try {
    if (deps.emulator) {
      status = 'dry-run';
      logger.info('DRY-RUN merge notice', { uid });
    } else {
      const hint = String((await noticeRef.child('KeepHint').get()).val() ?? '');
      let email: string | null = null;
      let lookupFailed = false;
      try {
        email = (await deps.getEmail(uid))?.trim() || null;
      } catch (err) {
        if ((err as { code?: string })?.code !== 'auth/user-not-found') {
          lookupFailed = true;
          error = `could not read the account's email: ${safeMessage(err)}`;
        }
      }
      if (lookupFailed) {
        status = 'failed';
      } else if (!email) {
        status = 'no-email';
      } else {
        const { subject, html } = mergeNoticeEmail(hint);
        const outcome = await deps.sendMail(root, { to: email, subject, html }, { redactRecipient: true });
        status = outcome === 'sent' ? 'sent' : 'failed';
        if (outcome === 'skipped') error = 'email is not configured (SMTP secrets missing)';
        else if (outcome === 'failed') error = 'the mailer could not send it (see Support/MailLog)';
      }
    }
  } catch (err) {
    status = 'failed';
    error = safeMessage(err);
  }

  try {
    await noticeRef.update({ Status: status, At: deps.at(), ...(error ? { Error: error } : {}) });
  } catch (err) {
    // The mail (if any) is out; a lost status must not throw into the runtime.
    logger.error('merge notice status not recorded', { uid, status, error: safeMessage(err) });
    return status;
  }
  logger.info('merge notice handled', { uid, status });
  return status;
}

export const onMergeNoticeCreated = onValueCreated(
  { ref: '/MergeNotices/{uid}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    await handleMergeNotice(event.data.ref.root as Reference, String(event.params['uid']));
  },
);
