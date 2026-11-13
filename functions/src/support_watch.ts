// Support-ticket RTDB triggers (zaya-support). Orchestration only — subjects,
// bodies, escaping and status decisions are all pure in src/lib/support.ts;
// delivery (SMTP + MailLog) lives in src/support_mail.ts. Style/plumbing
// follows insiders_watch.ts: dbRoot parity, token-lookup push with swallowed
// errors, data writes ALWAYS committed before any notification attempt.
//
// Mail to "the person" (acknowledgement, closing email, Reply-To on inbox
// mail) goes ONLY to the address Firebase Auth holds for the ticket's Uid -
// never the client-written Email field (a scripted account could otherwise
// make infinitesports.org mail its own text to any stranger). No Auth email
// -> no mail to the person. Server-side caps per uid (rolling hour, counter
// at Support/MailCaps/<uid>/<kind>, functions-only): 6 new-ticket emails
// (ack + inbox) and 20 user-reply notices to the inbox. Over a cap the
// ticket/reply is stored and processed as normal, but no email goes out for
// it (one masked warning).
//
// Loop safety: these triggers write Status/UpdatedAt on the ticket node —
// never inside Thread/ — so the Thread onCreate can't re-fire on its own
// writes, and the Status trigger only acts when the value BECOMES 'closed'
// (our 'open'/'answered' writes pass through it as no-ops).
//
// Spec: docs/superpowers/specs/2026-10-13-support-tickets-design.md
// ("Functions (fan repo /functions)" — onTicketCreated / onTicketThreadMessage
// / onTicketClosed, email rules in decisions #4/#5).

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { onValueCreated, onValueUpdated } from 'firebase-functions/v2/database';
import type { Reference } from 'firebase-admin/database';
import {
  ackEmailHtml, ackSubject, becameClosed, closingEmailHtml, closingSubject,
  MAIL_CAPS, mailCapStep, MailCapKind, newTicketEmailHtml, newTicketSubject,
  replyNoticeEmailHtml, replySubject, screenshotCount, statusAfterThreadMessage,
} from './lib/support';
import { sendSupportMail, SUPPORT_MAIL_SECRETS, SupportMailMessage } from './support_mail';

const BRAND_COLOR = '#D00000'; // infiniteSportsPrimaryColor (RGB 208,0,0)

/** The admin inbox every new ticket / user reply lands in (spec decision #5). */
export const SUPPORT_INBOX = 'support@infinitesports.org';

/** Logs never carry a whole uid (merge_notice_watch.ts parity). */
const uidPrefix = (uid: string): string => uid.slice(0, 6);

/** Sends one notification straight to the ticket owner's stored device token
 *  (insiders_watch.ts sendToInsider's twin — a private per-user event, not a
 *  topic broadcast). Errors are logged and swallowed: the ticket writes have
 *  already committed, so a push failure must never fail (and retry) the
 *  trigger. */
async function sendSupportPush(
  root: Reference, uid: string, title: string, body?: string,
): Promise<void> {
  try {
    if (!uid) return;
    const snap = await root.child(`Users/${uid}/Token`).get();
    const token = String(snap.val() ?? '').trim();
    if (!token) return;
    if (process.env.FUNCTIONS_EMULATOR === 'true') {
      logger.info('DRY-RUN support notification', { uid: uidPrefix(uid), title });
      return;
    }
    await admin.messaging().send({
      token,
      notification: { title, ...(body ? { body } : {}) },
      // Routes the tap to My Tickets (fan notification_router 'support'
      // payload branch).
      data: { type: 'support' },
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
    logger.error('support notification failed', { uid: uidPrefix(uid), error: String(err) });
  }
}

/** Injected seams so the handlers unit-test without Auth, SMTP or FCM. */
export interface SupportDeps {
  /** The Auth account's email for [uid]; null when there is none or the
   *  user is gone (auth/user-not-found). May throw on other Auth errors. */
  getAuthEmail(uid: string): Promise<string | null>;
  /** Never throws (sendSupportMail). */
  sendMail(root: Reference, message: SupportMailMessage): Promise<void>;
  /** Never throws (sendSupportPush). */
  sendPush(root: Reference, uid: string, title: string, body?: string): Promise<void>;
  now(): number;
}

function liveDeps(): SupportDeps {
  return {
    getAuthEmail: async (uid) => {
      try {
        const email = (await admin.auth().getUser(uid)).email;
        return typeof email === 'string' && email.trim() ? email.trim() : null;
      } catch (err) {
        if ((err as { code?: string } | null)?.code === 'auth/user-not-found') return null;
        throw err;
      }
    },
    sendMail: sendSupportMail,
    sendPush: sendSupportPush,
    now: () => Date.now(),
  };
}

/** The account's Auth address for [uid], or null (no uid, no Auth email,
 *  user gone, or the lookup failed - logged with a uid prefix, never
 *  thrown). */
async function authEmailFor(deps: SupportDeps, uid: string, num: string): Promise<string | null> {
  if (!uid) return null;
  try {
    const email = await deps.getAuthEmail(uid);
    if (!email) {
      logger.info('support: account has no email; no mail to the person', {
        num, uid: uidPrefix(uid),
      });
      return null;
    }
    return email;
  } catch (err) {
    const code = (err as { code?: unknown } | null)?.code;
    logger.error('support: account email lookup failed; no mail to the person', {
      num, uid: uidPrefix(uid), code: typeof code === 'string' ? code : 'unknown',
    });
    return null;
  }
}

/** Claims one send under [kind]'s cap for [uid] (a bounded transaction on
 *  Support/MailCaps/<uid>/<kind>). False when over the cap (one masked
 *  warning) or when the counter could not be updated - fails closed: the
 *  ticket data is stored and visible in the Manager inbox either way. */
async function underMailCap(
  root: Reference, deps: SupportDeps, uid: string, kind: MailCapKind, num: string,
): Promise<boolean> {
  if (!uid) return true; // no account to count against
  const limit = MAIL_CAPS[kind];
  try {
    const nowMs = deps.now();
    const result = await root.child(`Support/MailCaps/${uid}/${kind}`).transaction(
      (current) => mailCapStep(current, nowMs, limit) ?? undefined,
    );
    if (result.committed) return true;
    logger.warn('support mail cap reached; email not sent', {
      num, uid: uidPrefix(uid), kind, limitPerHour: limit,
    });
    return false;
  } catch (err) {
    logger.error('support mail cap check failed; email not sent', {
      num, uid: uidPrefix(uid), kind, error: String(err),
    });
    return false;
  }
}

/** The ticket fields the emails need, read tolerantly off a raw node. The
 *  stored Email field is deliberately NOT read: it is client-written. */
interface TicketFields {
  uid: string; name: string; category: string; message: string;
  platform: string; appVersion: string; screen: string; screenshots: number;
  closedOutcome: string; closedNote: string;
}

function parseTicket(raw: unknown): TicketFields {
  const t = (raw ?? {}) as Record<string, unknown>;
  const str = (key: string): string => (typeof t[key] === 'string' ? t[key] as string : '');
  return {
    uid: str('Uid'),
    name: str('Name'),
    category: str('Category'),
    message: str('Message'),
    platform: str('Platform'),
    appVersion: str('AppVersion'),
    screen: str('Screen'),
    screenshots: screenshotCount(t['Screenshots']),
    closedOutcome: str('ClosedOutcome'),
    closedNote: str('ClosedNote'),
  };
}

/** New ticket (already stored by the app): ack email to the account's Auth
 *  address + new-ticket email to the support inbox (Reply-To that address).
 *  Both count as one send against the Ack cap: over it, neither goes out
 *  (the ticket is still in the Manager inbox). */
export async function handleTicketCreated(
  root: Reference, num: string, raw: unknown, deps: SupportDeps = liveDeps(),
): Promise<void> {
  const ticket = parseTicket(raw);
  if (!(await underMailCap(root, deps, ticket.uid, 'Ack', num))) return;
  const email = await authEmailFor(deps, ticket.uid, num);

  if (email) {
    await deps.sendMail(root, {
      to: email,
      subject: ackSubject(num),
      html: ackEmailHtml({
        num, name: ticket.name, category: ticket.category, message: ticket.message,
      }),
    });
  }

  await deps.sendMail(root, {
    to: SUPPORT_INBOX,
    subject: newTicketSubject(num, ticket.category, ticket.name),
    html: newTicketEmailHtml({
      num,
      name: ticket.name,
      email: email ?? '(no account email)',
      uid: ticket.uid,
      category: ticket.category,
      message: ticket.message,
      platform: ticket.platform,
      appVersion: ticket.appVersion,
      screen: ticket.screen,
      screenshotCount: ticket.screenshots,
    }),
    ...(email ? { replyTo: email } : {}),
  });
}

/** Thread message landed: user reply -> Status 'open' + inbox email (Reply
 *  cap); admin reply -> Status 'answered' + push to the owner; internal notes
 *  (From=='note') do nothing. The Status write always happens first. */
export async function handleThreadMessage(
  root: Reference, num: string, rawMsg: unknown, deps: SupportDeps = liveDeps(),
): Promise<void> {
  const msg = (rawMsg ?? {}) as Record<string, unknown>;
  const from = typeof msg['From'] === 'string' ? msg['From'] as string : '';
  const nextStatus = statusAfterThreadMessage(from);
  if (!nextStatus) return; // internal note (or unknown) — invisible to the user

  const ticketRef = root.child(`Support/Tickets/${num}`);
  // Data first, mail/push second (house rule: notifications never gate or
  // retry committed writes). Raw sentinel — index.ts claimKey parity.
  await ticketRef.update({ Status: nextStatus, UpdatedAt: { '.sv': 'timestamp' } });

  const ticket = parseTicket((await ticketRef.get()).val());

  if (nextStatus === 'open') {
    if (!(await underMailCap(root, deps, ticket.uid, 'Reply', num))) return;
    const email = await authEmailFor(deps, ticket.uid, num);
    const text = typeof msg['Text'] === 'string' ? msg['Text'] as string : '';
    await deps.sendMail(root, {
      to: SUPPORT_INBOX,
      subject: replySubject(num, ticket.name),
      html: replyNoticeEmailHtml({ num, name: ticket.name, text }),
      ...(email ? { replyTo: email } : {}),
    });
  } else {
    await deps.sendPush(
      root, ticket.uid,
      `Support replied to your ticket #${num}`,
      'Open My Tickets in the app to read it.',
    );
  }
}

/** Ticket became closed: closing email to the account's Auth address (none
 *  when there is no Auth email) + push. Admin-driven, so not capped. */
export async function handleTicketClosed(
  root: Reference, num: string, deps: SupportDeps = liveDeps(),
): Promise<void> {
  const ticket = parseTicket((await root.child(`Support/Tickets/${num}`).get()).val());
  const email = await authEmailFor(deps, ticket.uid, num);
  if (email) {
    await deps.sendMail(root, {
      to: email,
      subject: closingSubject(num),
      html: closingEmailHtml({
        num,
        name: ticket.name,
        outcome: ticket.closedOutcome,
        note: ticket.closedNote,
      }),
    });
  }
  await deps.sendPush(
    root, ticket.uid,
    `Your ticket #${num} is closed`,
    'Check your email for the outcome (and the joke).',
  );
}

/** New ticket submitted (fan app writes the full node, ticket data is already
 *  stored): see handleTicketCreated. Exactly these two sends — mid-thread
 *  traffic is push only (spec decision #4). */
export const onTicketCreated = onValueCreated(
  { ref: '/Support/Tickets/{num}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const num = String(event.params['num']);
    const root = event.data.ref.root as Reference;
    const raw = event.data.val();
    await handleTicketCreated(root, num, raw);
    logger.info('support ticket created', { num, category: parseTicket(raw).category });
  },
);

/** Thread message landed (thread messages are only replies — ticket creation
 *  writes no Thread echo). Status/UpdatedAt live OUTSIDE Thread, so this
 *  trigger never re-fires on its own writes. */
export const onTicketThreadMessage = onValueCreated(
  { ref: '/Support/Tickets/{num}/Thread/{msgId}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const num = String(event.params['num']);
    const root = event.data.ref.root as Reference;
    const msg = (event.data.val() ?? {}) as Record<string, unknown>;
    const from = typeof msg['From'] === 'string' ? msg['From'] as string : '';
    const nextStatus = statusAfterThreadMessage(from);
    if (!nextStatus) return;
    await handleThreadMessage(root, num, msg);
    logger.info('support thread message handled', { num, from, nextStatus });
  },
);

/** Status became 'closed': closing email + FCM push. onValueUpdated only, and
 *  becameClosed() guards both re-writes of 'closed' and this trigger's
 *  sibling writes ('open'/'answered') from the thread handler. */
export const onTicketStatusChanged = onValueUpdated(
  { ref: '/Support/Tickets/{num}/Status', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const before = String(event.data.before.val() ?? '');
    const after = String(event.data.after.val() ?? '');
    if (!becameClosed(before, after)) return;

    const num = String(event.params['num']);
    const root = event.data.after.ref.root as Reference;
    await handleTicketClosed(root, num);
    logger.info('support ticket closed', { num });
  },
);
