// Support-ticket RTDB triggers (zaya-support). Orchestration only — subjects,
// bodies, escaping and status decisions are all pure in src/lib/support.ts;
// delivery (SMTP + MailLog) lives in src/support_mail.ts. Style/plumbing
// follows insiders_watch.ts: dbRoot parity, token-lookup push with swallowed
// errors, data writes ALWAYS committed before any notification attempt.
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
  newTicketEmailHtml, newTicketSubject, replyNoticeEmailHtml, replySubject,
  screenshotCount, statusAfterThreadMessage,
} from './lib/support';
import { sendSupportMail, SUPPORT_MAIL_SECRETS } from './support_mail';

const BRAND_COLOR = '#D00000'; // infiniteSportsPrimaryColor (RGB 208,0,0)

/** The admin inbox every new ticket / user reply lands in (spec decision #5). */
export const SUPPORT_INBOX = 'support@infinitesports.org';

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
      logger.info('DRY-RUN support notification', { uid, title });
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
    logger.error('support notification failed', { uid, error: String(err) });
  }
}

/** The ticket fields the emails need, read tolerantly off a raw node. */
interface TicketFields {
  uid: string; name: string; email: string; category: string; message: string;
  platform: string; appVersion: string; screen: string; screenshots: number;
  closedOutcome: string; closedNote: string;
}

function parseTicket(raw: unknown): TicketFields {
  const t = (raw ?? {}) as Record<string, unknown>;
  const str = (key: string): string => (typeof t[key] === 'string' ? t[key] as string : '');
  return {
    uid: str('Uid'),
    name: str('Name'),
    email: str('Email'),
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

/** New ticket submitted (fan app writes the full node, ticket data is already
 *  stored): ack email to the user + new-ticket email to the support inbox
 *  (Reply-To the user). Exactly these two sends — mid-thread traffic is push
 *  only (spec decision #4). */
export const onTicketCreated = onValueCreated(
  { ref: '/Support/Tickets/{num}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const num = String(event.params['num']);
    const root = event.data.ref.root as Reference;
    const ticket = parseTicket(event.data.val());

    await sendSupportMail(root, {
      to: ticket.email,
      subject: ackSubject(num),
      html: ackEmailHtml({
        num, name: ticket.name, category: ticket.category, message: ticket.message,
      }),
    });

    await sendSupportMail(root, {
      to: SUPPORT_INBOX,
      subject: newTicketSubject(num, ticket.category, ticket.name),
      html: newTicketEmailHtml({
        num,
        name: ticket.name,
        email: ticket.email,
        uid: ticket.uid,
        category: ticket.category,
        message: ticket.message,
        platform: ticket.platform,
        appVersion: ticket.appVersion,
        screen: ticket.screen,
        screenshotCount: ticket.screenshots,
      }),
      ...(ticket.email ? { replyTo: ticket.email } : {}),
    });

    logger.info('support ticket created', { num, category: ticket.category });
  },
);

/** Thread message landed (thread messages are only replies — ticket creation
 *  writes no Thread echo): user reply -> Status 'open' + email the inbox;
 *  admin reply -> Status 'answered' + FCM push to the owner; internal notes
 *  (From=='note') do nothing. Status/UpdatedAt live OUTSIDE Thread, so this
 *  trigger never re-fires on its own writes. */
export const onTicketThreadMessage = onValueCreated(
  { ref: '/Support/Tickets/{num}/Thread/{msgId}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const num = String(event.params['num']);
    const msg = (event.data.val() ?? {}) as Record<string, unknown>;
    const from = typeof msg['From'] === 'string' ? msg['From'] as string : '';
    const nextStatus = statusAfterThreadMessage(from);
    if (!nextStatus) return; // internal note (or unknown) — invisible to the user

    const root = event.data.ref.root as Reference;
    const ticketRef = root.child(`Support/Tickets/${num}`);

    // Data first, mail/push second (house rule: notifications never gate or
    // retry committed writes). Raw sentinel — index.ts claimKey parity.
    await ticketRef.update({ Status: nextStatus, UpdatedAt: { '.sv': 'timestamp' } });

    const ticket = parseTicket((await ticketRef.get()).val());

    if (nextStatus === 'open') {
      const text = typeof msg['Text'] === 'string' ? msg['Text'] as string : '';
      await sendSupportMail(root, {
        to: SUPPORT_INBOX,
        subject: replySubject(num, ticket.name),
        html: replyNoticeEmailHtml({ num, name: ticket.name, text }),
        ...(ticket.email ? { replyTo: ticket.email } : {}),
      });
    } else {
      await sendSupportPush(
        root, ticket.uid,
        `Support replied to your ticket #${num}`,
        'Open My Tickets in the app to read it.',
      );
    }

    logger.info('support thread message handled', { num, from, nextStatus });
  },
);

/** Status became 'closed': closing email to the user (outcome phrasing +
 *  ClosedNote — the joke — verbatim) + FCM push. onValueUpdated only, and
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
    const ticket = parseTicket(
      (await root.child(`Support/Tickets/${num}`).get()).val(),
    );

    await sendSupportMail(root, {
      to: ticket.email,
      subject: closingSubject(num),
      html: closingEmailHtml({
        num,
        name: ticket.name,
        outcome: ticket.closedOutcome,
        note: ticket.closedNote,
      }),
    });

    await sendSupportPush(
      root, ticket.uid,
      `Your ticket #${num} is closed`,
      'Check your email for the outcome (and the joke).',
    );

    logger.info('support ticket closed', { num, outcome: ticket.closedOutcome });
  },
);
