// Infinite Fantasy paid access (season pass) — the Cloud Function exports.
// Thin: every decision lives pure in src/lib/fantasy/access.ts behind the
// FantasyDb / FantasyPusher / AccessMailer / AccessAuth seams; this file
// wires the admin SDK, FCM, SMTP (support_mail), Firebase Auth and Stripe.
//
// Spec: docs/superpowers/specs/2026-11-01-fantasy-paid-access-design.md §7
// Plan: docs/superpowers/plans/2026-11-01-fantasy-paid-access.md A3/A4
//
// createFantasyCheckoutSession (callable, signed-in fan)
//   data: { sport:string, season:string|number }
//   -> { url:string }                 a Stripe Checkout link to open OUTSIDE
//                                     the app (store policy, spec §2)
//   -> { alreadyActive:true }         the fan is already in (a race)
//   Errors: unauthenticated / invalid-argument (sport, season) /
//   failed-precondition (free season, Card off, no price) / internal
//   (Stripe returned no link). The amount is ALWAYS the server's
//   Config/Access/AmountDollars — the client never names a price. The
//   PaymentIntent carries {kind:'fantasyAccess', sport, season, uid} so the
//   existing stripeWebhook activates Access/<uid> on payment_intent.succeeded.
//
// sendFantasyAccessTest (callable, admin-gated like getUserContact)
//   data: { sport, season, template:'claimReceived'|'claimAdmin'|
//           'activatedPaid'|'activatedGranted'|'revoked' }
//   -> { pushed:boolean, emailed:boolean }   that template, filled with
//                                            sample values, to the CALLER
//   Errors: unauthenticated / permission-denied / invalid-argument.
//
// onFantasyAccessClaimCreated   AccessClaims/{uid}/{key} created (a fan's
//   "I sent it"): Access/<uid> -> pending unless active; once-only
//   Notified on the claim; pushes every /Admins uid + emails AdminEmail
//   (claimAdmin) and pushes + emails the fan (claimReceived).
// onFantasyAccessStatusWritten  Access/{uid}/Status written -> 'active' /
//   'revoked': once per PaidAt / RefundedAt, push + email the fan with
//   activatedPaid (the receipt) / activatedGranted / revoked.
// onRegistrationPaidGrantFantasy  Registrations/{regId}/Submissions/{uid}/Paid
//   written -> true: grants {active, player} when the matching fantasy
//   season is pass mode with RegisteredPlayersFree and the uid is not active.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import type { Reference } from 'firebase-admin/database';
import { onValueCreated, onValueWritten } from 'firebase-functions/v2/database';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import { stripeSecretKey } from './createRegistrationPaymentIntent';
import { fantasyLogger, rtdbFantasyDb, rtdbFantasyPusher } from './fantasy_adapter';
import { requireAdmin } from './fantasy_messages';
import {
  AccessConfig, accessConfigFrom, AccessDeps, accessRecordFrom, checkoutLineItem,
  checkoutUrls, dollarsToCents, grantFantasyAccessForRegistration, handleAccessClaimCreated,
  handleAccessStatusWritten, HOSTING_BASE, isActive, isPassMode, isTemplateKey,
  sendAccessTestMessage,
} from './lib/fantasy/access';
import { fantasyRoot } from './lib/fantasy/orchestration_db';
import { fantasyAccessMetadata } from './lib/stripe_pay';
import { sendSupportMail, SUPPORT_MAIL_SECRETS } from './support_mail';

// ── Seams ───────────────────────────────────────────────────────────────────

/** The one Stripe call this module makes. */
export interface StripeCheckoutLike {
  checkout: {
    sessions: {
      create(params: Stripe.Checkout.SessionCreateParams): Promise<{ url: string | null }>;
    };
  };
}

/** Test seam (support_mail __setMailerForTests parity): vitest injects a
 *  fake Stripe client so the callable runs without a key or the network. */
let testStripe: StripeCheckoutLike | 'unset' = 'unset';
export function __setStripeForTests(client: StripeCheckoutLike | 'unset'): void {
  testStripe = client;
}

function stripeClient(): StripeCheckoutLike {
  if (testStripe !== 'unset') return testStripe;
  return new Stripe(stripeSecretKey.value());
}

/** The impure edges every access handler needs, over one admin root. The
 *  mailer is sendSupportMail (never throws, logs to Support/MailLog); the
 *  auth seam reads the fan's email off Firebase Auth — an unknown uid or
 *  any Auth hiccup is "no email on file" (logged), never a thrown trigger:
 *  the push still goes and the once-only claim is already written. */
export function accessDeps(root: Reference, nowMs: number): AccessDeps {
  return {
    db: rtdbFantasyDb(root),
    pusher: rtdbFantasyPusher(root),
    mailer: {
      send: (to, subject, html) => sendSupportMail(root, { to, subject, html }),
    },
    auth: {
      async emailOf(uid: string): Promise<string | null> {
        try {
          const user = await admin.auth().getUser(uid);
          return typeof user.email === 'string' && user.email.length > 0 ? user.email : null;
        } catch (err) {
          const code = (err as { code?: unknown } | null)?.code;
          if (code !== 'auth/user-not-found') {
            logger.warn('fantasy access: could not read the auth email', { uid, err: String(err) });
          }
          return null;
        }
      },
    },
    nowMs,
    log: fantasyLogger,
  };
}

// ── Args ────────────────────────────────────────────────────────────────────

function asTrimmedString(v: unknown): string {
  return typeof v === 'string' || typeof v === 'number' ? String(v).trim() : '';
}

function seasonOf(data: unknown): { sport: string; season: string } {
  const d = (data ?? {}) as Record<string, unknown>;
  const sport = asTrimmedString(d['sport']);
  const season = asTrimmedString(d['season']);
  if (!sport || !season) {
    throw new HttpsError('invalid-argument', 'Missing sport/season.');
  }
  return { sport, season };
}

function tokenString(request: CallableRequest, key: string): string | undefined {
  const token = (request.auth?.token ?? {}) as Record<string, unknown>;
  const v = token[key];
  return typeof v === 'string' && v.length > 0 ? v : undefined;
}

// ── createFantasyCheckoutSession ────────────────────────────────────────────

/** The Stripe Checkout Session params (spec §7): one line item at the
 *  server's amount, our metadata on the PaymentIntent, the hosting pages
 *  as the return URLs. Pure — the callable test pins every field. */
export function checkoutSessionParams(args: {
  cfg: AccessConfig; sport: string; season: string; uid: string; email: string | undefined;
}): Stripe.Checkout.SessionCreateParams {
  const item = checkoutLineItem(args.cfg, args.sport, args.season);
  return {
    mode: 'payment',
    line_items: [{
      price_data: {
        currency: item.currency,
        unit_amount: item.unit_amount,
        product_data: { name: item.name },
      },
      quantity: 1,
    }],
    payment_intent_data: {
      metadata: fantasyAccessMetadata({ sport: args.sport, season: args.season, uid: args.uid }),
    },
    ...(args.email ? { customer_email: args.email } : {}),
    ...checkoutUrls(HOSTING_BASE),
  };
}

export const createFantasyCheckoutSession = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to pay.');
    }
    const { sport, season } = seasonOf(request.data);

    const db = rtdbFantasyDb(admin.database().ref());
    const root = fantasyRoot(sport, season);
    const [cfgRaw, recRaw] = await Promise.all([
      db.read(`${root}/Config/Access`),
      db.read(`${root}/Access/${uid}`),
    ]);
    // An active fan never gets a link, whatever the mode (a race with the
    // webhook / an approval while the pay card was open).
    if (isActive(accessRecordFrom(recRaw))) {
      logger.info('createFantasyCheckoutSession: already active', { uid, sport, season });
      return { alreadyActive: true };
    }
    const cfg = accessConfigFrom(cfgRaw);
    if (!isPassMode(cfg)) {
      throw new HttpsError('failed-precondition', 'This season is free to play.');
    }
    if (!cfg.methods.card) {
      throw new HttpsError('failed-precondition', 'Card payments are not available for this season.');
    }
    if (cfg.amountDollars <= 0) {
      throw new HttpsError('failed-precondition', 'No price is set for this season yet.');
    }

    const params = checkoutSessionParams({
      cfg, sport, season, uid, email: tokenString(request, 'email'),
    });
    const session = await stripeClient().checkout.sessions.create(params);
    if (!session.url) {
      logger.error('createFantasyCheckoutSession: Stripe returned no url', { uid, sport, season });
      throw new HttpsError('internal', 'Could not start the payment. Please try again.');
    }
    logger.info('createFantasyCheckoutSession: created', {
      uid, sport, season, amountCents: dollarsToCents(cfg.amountDollars),
    });
    return { url: session.url };
  },
);

// ── sendFantasyAccessTest ───────────────────────────────────────────────────

export const sendFantasyAccessTest = onCall(
  { secrets: SUPPORT_MAIL_SECRETS },
  async (request) => {
    const uid = await requireAdmin(request);
    const { sport, season } = seasonOf(request.data);
    const template = (request.data as Record<string, unknown> | undefined)?.['template'];
    if (!isTemplateKey(template)) {
      throw new HttpsError('invalid-argument', 'Unknown template.');
    }
    const root = admin.database().ref();
    return sendAccessTestMessage(accessDeps(root, Date.now()), {
      sport, season, uid, template,
      displayName: tokenString(request, 'name') ?? '',
    });
  },
);

// ── Triggers ────────────────────────────────────────────────────────────────
//
// The Fantasy/ prefix keeps the wildcards off the busy league paths
// (fantasy_badges.ts convention); the same-instance root matters in the
// emulator (index.ts dbRoot parity). Every handler is pure and tested in
// lib/fantasy/access_orchestration.test.ts; these only hand it the event.

export const onFantasyAccessClaimCreated = onValueCreated(
  { ref: '/Fantasy/{sport}/{season}/AccessClaims/{uid}/{key}', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const root = event.data.ref.root as Reference;
    await handleAccessClaimCreated(accessDeps(root, Date.now()), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      uid: String(event.params['uid']),
      key: String(event.params['key']),
    });
  },
);

export const onFantasyAccessStatusWritten = onValueWritten(
  { ref: '/Fantasy/{sport}/{season}/Access/{uid}/Status', secrets: SUPPORT_MAIL_SECRETS },
  async (event) => {
    const root = event.data.before.ref.root as Reference;
    await handleAccessStatusWritten(accessDeps(root, Date.now()), {
      sport: String(event.params['sport']),
      season: String(event.params['season']),
      uid: String(event.params['uid']),
      before: event.data.before.val(),
      after: event.data.after.val(),
    });
  },
);

export const onRegistrationPaidGrantFantasy = onValueWritten(
  '/Registrations/{regId}/Submissions/{uid}/Paid',
  async (event) => {
    const root = event.data.before.ref.root as Reference;
    await grantFantasyAccessForRegistration(rtdbFantasyDb(root), {
      regId: String(event.params['regId']),
      uid: String(event.params['uid']),
      paid: event.data.after.val(),
      nowMs: Date.now(),
      log: fantasyLogger,
    });
  },
);
