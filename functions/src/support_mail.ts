// Support-ticket SMTP transport (zaya-support). One job: deliver one email
// and log the attempt to Support/MailLog. Every decision about WHAT to send
// is pure in src/lib/support.ts; every caller is a trigger in
// src/support_watch.ts that has ALREADY committed its ticket writes — so
// nothing in here ever throws back to a trigger (a mail failure must never
// retry, and so re-email, a ticket that is safely stored).
//
// Secrets (Secret Manager, bound by the triggers that call this):
// SUPPORT_SMTP_HOST / SUPPORT_SMTP_PORT / SUPPORT_SMTP_USER /
// SUPPORT_SMTP_PASS. STARTTLS on :587 — secure=false + requireTLS, per spec.
// When they are missing/empty, email is simply off: warn and no-op.

import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import * as nodemailer from 'nodemailer';
import type { Reference } from 'firebase-admin/database';
import { isValidEmail, mailLogEntry, sanitizeSubject } from './lib/support';

export const supportSmtpHost = defineSecret('SUPPORT_SMTP_HOST');
export const supportSmtpPort = defineSecret('SUPPORT_SMTP_PORT');
export const supportSmtpUser = defineSecret('SUPPORT_SMTP_USER');
export const supportSmtpPass = defineSecret('SUPPORT_SMTP_PASS');

/** Bind these on every function that sends mail. */
export const SUPPORT_MAIL_SECRETS = [
  supportSmtpHost, supportSmtpPort, supportSmtpUser, supportSmtpPass,
];

export interface SupportMailMessage {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}

interface Mailer {
  from: string;
  send(options: nodemailer.SendMailOptions): Promise<unknown>;
}

/** Test seam: vitest injects a fake mailer so sendSupportMail unit-tests
 *  without SMTP or secrets (stripe_pay-style dependency injection, kept out
 *  of the call signature so trigger code stays clean). */
let testMailer: Mailer | null | 'unset' = 'unset';
export function __setMailerForTests(mailer: Mailer | null | 'unset'): void {
  testMailer = mailer;
  cachedTransport = null;
}

let cachedTransport: nodemailer.Transporter | null = null;

/** Secret value at runtime; '' when unbound/absent (params throw outside a
 *  bound runtime — treat that the same as "not configured"). */
function secretValue(secret: { value(): string }): string {
  try {
    return (secret.value() ?? '').trim();
  } catch {
    return '';
  }
}

/** The live mailer, or null when SMTP secrets are missing (email off). */
function getMailer(): Mailer | null {
  if (testMailer !== 'unset') return testMailer;
  const host = secretValue(supportSmtpHost);
  const port = Number(secretValue(supportSmtpPort)) || 587;
  const user = secretValue(supportSmtpUser);
  const pass = secretValue(supportSmtpPass);
  if (!host || !user || !pass) return null;
  if (!cachedTransport) {
    cachedTransport = nodemailer.createTransport({
      host,
      port,
      secure: false, // STARTTLS upgrade on :587, never implicit TLS
      requireTLS: true, // and refuse to send if the server won't upgrade
      auth: { user, pass },
    });
  }
  const transport = cachedTransport;
  return { from: user, send: (options) => transport.sendMail(options) };
}

/** Sends one support email and push-logs the attempt to Support/MailLog
 *  ({To, Subject, Ok, Err?, At}). Never throws: the ticket data was written
 *  by the trigger BEFORE any mail attempt, and a mail failure is a log line,
 *  not a reason to retry the trigger. Missing secrets -> warn + no-op. */
export async function sendSupportMail(
  root: Reference, message: SupportMailMessage,
): Promise<void> {
  const subject = sanitizeSubject(message.subject); // belt-and-braces: builders already sanitize
  try {
    const mailer = getMailer();
    if (!mailer) {
      logger.warn('support mail skipped — SMTP secrets not configured', {
        to: message.to, subject,
      });
      return;
    }

    let ok = true;
    let err: string | undefined;
    if (!isValidEmail(message.to)) {
      ok = false;
      err = 'invalid recipient address';
      logger.warn('support mail refused — invalid recipient', { to: message.to, subject });
    } else {
      try {
        await mailer.send({
          from: `Infinite Sports <${mailer.from}>`,
          to: message.to,
          subject,
          html: message.html,
          ...(message.replyTo ? { replyTo: message.replyTo } : {}),
        });
      } catch (sendErr) {
        ok = false;
        err = String(sendErr);
        logger.error('support mail send failed', { to: message.to, subject, error: err });
      }
    }

    await root.child('Support/MailLog').push().set(mailLogEntry({
      to: message.to,
      subject,
      ok,
      ...(err ? { err } : {}),
      // Raw sentinel (index.ts claimKey parity — safe everywhere, including
      // the emulator's admin.database shim).
      at: { '.sv': 'timestamp' },
    }));
  } catch (outerErr) {
    // Even the MailLog write must never bubble into the trigger.
    logger.error('support mail logging failed', {
      to: message.to, subject, error: String(outerErr),
    });
  }
}
