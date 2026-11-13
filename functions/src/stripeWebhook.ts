// Cloud Function (L1c): Stripe webhook. On payment_intent.succeeded, flips
// Paid/PaidVia/PaidAmount on the matching submission and moves the legacy
// Sign Ups entry from NotPaid to Paid — the same two writes the Manager's
// manual "Mark Paid" flip performs, so every existing consumer (Sign Ups
// page, Add-from-signups roster builder) keeps working unchanged.
//
// Paid access (spec 2026-11-01 §7): the same endpoint also serves the
// fantasy season pass. A PaymentIntent whose metadata carries
// `kind:'fantasyAccess'` (a Checkout Session from createFantasyCheckoutSession)
// activates Fantasy/<sport>/<season>/Access/<uid> instead of a submission
// (idempotent on replay), and a FULL `charge.refunded` on such a payment
// revokes it. The registration path is unchanged: markPaid below is the
// L1c code verbatim, and metadata without a kind still parses as before.
// Routing is pure in routeStripeEvent (stripeWebhook.test.ts drives it with
// the in-memory FantasyDb); the onRequest wrapper only verifies the
// signature and wires the real database.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { activateFantasyAccess, revokeFantasyAccessOnRefund } from './lib/fantasy/access';
import type { FantasyDb } from './lib/fantasy/orchestration_db';
import { centsToDollars, parseWebhookMetadata, RegistrationMeta } from './lib/stripe_pay';

export const stripeWebhookSecret = defineSecret('STRIPE_WEBHOOK_SECRET');
export const stripeSecretKeyForWebhook = defineSecret('STRIPE_SECRET_KEY');

async function markPaid(
  meta: { regId: string; uid: string; league: string; season: string },
  amountReceivedCents: number,
): Promise<void> {
  const db = admin.database();
  const submissionRef = db.ref(`Registrations/${meta.regId}/Submissions/${meta.uid}`);
  const snap = await submissionRef.get();
  const submission = snap.val() as Record<string, unknown> | null;
  if (!submission) {
    logger.warn('stripeWebhook: submission not found, skipping', meta);
    return;
  }
  if (submission['Paid'] === true) {
    logger.info('stripeWebhook: already Paid, skipping (idempotent replay)', meta);
    return;
  }

  const displayName = typeof submission['DisplayName'] === 'string' ? submission['DisplayName'] : '';
  await submissionRef.update({
    Paid: true,
    PaidVia: 'card',
    PaidAmount: centsToDollars(amountReceivedCents),
  });

  const notPaidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/NotPaid/${meta.uid}`);
  const paidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/Paid/${meta.uid}`);
  await paidRef.set(displayName);
  await notPaidRef.remove();

  logger.info('stripeWebhook: marked Paid via card', meta);
}

/** What routeStripeEvent needs from the outside world (tests inject fakes). */
export interface StripeWebhookDeps {
  /** The fantasy access records (rtdbFantasyDb over the admin root). */
  db: FantasyDb;
  /** The registration flip — the untouched markPaid above. */
  markPaid(meta: RegistrationMeta, amountReceivedCents: number): Promise<void>;
  /** charge.refunded fallback: a Charge whose own metadata lacks our kind is
   *  resolved through its PaymentIntent's metadata (Stripe copies the
   *  PaymentIntent's metadata onto the charge, but a lookup costs nothing
   *  when it is missing). */
  paymentIntentMetadata(paymentIntentId: string): Promise<unknown>;
  nowMs: number;
}

export interface StripeWebhookResult {
  status: number;
  body: string;
}

/** The refunded charge's PaymentIntent id (a string, or an expanded object). */
function paymentIntentIdOf(charge: Stripe.Charge): string | null {
  const pi = charge.payment_intent as unknown;
  if (typeof pi === 'string' && pi.length > 0) return pi;
  if (pi !== null && typeof pi === 'object') {
    const id = (pi as { id?: unknown }).id;
    if (typeof id === 'string' && id.length > 0) return id;
  }
  return null;
}

/** Routes one verified Stripe event (see the header). Returns the HTTP
 *  status + body for Stripe: 200 stops retries, 500 asks for one. */
export async function routeStripeEvent(
  event: Stripe.Event, deps: StripeWebhookDeps,
): Promise<StripeWebhookResult> {
  if (event.type === 'payment_intent.succeeded') {
    const intent = event.data.object as Stripe.PaymentIntent;
    const meta = parseWebhookMetadata(intent.metadata);
    if (!meta) {
      logger.error('stripeWebhook: payment_intent.succeeded with malformed metadata', {
        id: intent.id, metadata: intent.metadata,
      });
      return { status: 200, body: 'malformed metadata, ignored' }; // 200 so Stripe stops retrying
    }

    try {
      const amountReceivedCents = intent.amount_received || intent.amount;
      if (meta.kind === 'fantasyAccess') {
        await activateFantasyAccess(deps.db, {
          sport: meta.sport, season: meta.season, uid: meta.uid,
          amountCents: amountReceivedCents, paymentIntent: intent.id,
          nowMs: deps.nowMs, log: fantasyLogger,
        });
      } else {
        await deps.markPaid(meta, amountReceivedCents);
      }
      return { status: 200, body: 'ok' };
    } catch (err) {
      logger.error('stripeWebhook: failed to mark Paid', { err: String(err), meta });
      return { status: 500, body: 'internal error' }; // 500 so Stripe retries
    }
  }

  if (event.type === 'charge.refunded') {
    const charge = event.data.object as Stripe.Charge;
    const paymentIntent = paymentIntentIdOf(charge);
    let meta = parseWebhookMetadata(charge.metadata);
    if ((meta === null || meta.kind !== 'fantasyAccess') && paymentIntent !== null) {
      try {
        meta = parseWebhookMetadata(await deps.paymentIntentMetadata(paymentIntent));
      } catch (err) {
        logger.warn('stripeWebhook: could not read the refunded PaymentIntent', {
          charge: charge.id, paymentIntent, err: String(err),
        });
      }
    }
    if (meta === null || meta.kind !== 'fantasyAccess') {
      logger.info('stripeWebhook: refund on a non-fantasy charge — ignored', {
        charge: charge.id, paymentIntent,
      });
      return { status: 200, body: 'ignored' };
    }
    if (charge.refunded !== true) {
      logger.info('stripeWebhook: partial fantasy refund — logged only, access unchanged', {
        charge: charge.id, paymentIntent, amountRefunded: charge.amount_refunded,
        sport: meta.sport, season: meta.season, uid: meta.uid,
      });
      return { status: 200, body: 'partial refund, ignored' };
    }
    try {
      await revokeFantasyAccessOnRefund(deps.db, {
        sport: meta.sport, season: meta.season, uid: meta.uid, paymentIntent,
        nowMs: deps.nowMs, log: fantasyLogger,
      });
      return { status: 200, body: 'ok' };
    } catch (err) {
      logger.error('stripeWebhook: failed to revoke on refund', { err: String(err), meta });
      return { status: 500, body: 'internal error' };
    }
  }

  logger.info('stripeWebhook: ignoring unhandled event type', { type: event.type });
  return { status: 200, body: 'ignored' };
}

export const stripeWebhook = onRequest(
  { secrets: [stripeWebhookSecret, stripeSecretKeyForWebhook] },
  async (request, response) => {
    const signature = request.headers['stripe-signature'];
    if (typeof signature !== 'string') {
      logger.warn('stripeWebhook: missing stripe-signature header');
      response.status(400).send('Missing signature');
      return;
    }

    const stripe = new Stripe(stripeSecretKeyForWebhook.value());
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody, signature, stripeWebhookSecret.value(),
      );
    } catch (err) {
      logger.error('stripeWebhook: signature verification failed', { err: String(err) });
      response.status(400).send('Invalid signature');
      return;
    }

    const result = await routeStripeEvent(event, {
      db: rtdbFantasyDb(admin.database().ref()),
      markPaid,
      paymentIntentMetadata: async (id) => (await stripe.paymentIntents.retrieve(id)).metadata,
      nowMs: Date.now(),
    });
    response.status(result.status).send(result.body);
  },
);
