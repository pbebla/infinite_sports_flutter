// Cloud Function (L1c): Stripe webhook. On payment_intent.succeeded, flips
// Paid/PaidVia on the matching submission and moves the legacy Sign Ups
// entry from NotPaid to Paid — the same two writes the Manager's manual
// "Mark Paid" flip performs, so every existing consumer (Sign Ups page,
// Add-from-signups roster builder) keeps working unchanged.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { onRequest } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import { parseWebhookMetadata } from './lib/stripe_pay';

export const stripeWebhookSecret = defineSecret('STRIPE_WEBHOOK_SECRET');
export const stripeSecretKeyForWebhook = defineSecret('STRIPE_SECRET_KEY');

async function markPaid(meta: { regId: string; uid: string; league: string; season: string }): Promise<void> {
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
  await submissionRef.update({ Paid: true, PaidVia: 'card' });

  const notPaidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/NotPaid/${meta.uid}`);
  const paidRef = db.ref(`Sign Ups/${meta.league}/${meta.season}/Paid/${meta.uid}`);
  await paidRef.set(displayName);
  await notPaidRef.remove();

  logger.info('stripeWebhook: marked Paid via card', meta);
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

    if (event.type !== 'payment_intent.succeeded') {
      logger.info('stripeWebhook: ignoring unhandled event type', { type: event.type });
      response.status(200).send('ignored');
      return;
    }

    const intent = event.data.object as Stripe.PaymentIntent;
    const meta = parseWebhookMetadata(intent.metadata);
    if (!meta) {
      logger.error('stripeWebhook: payment_intent.succeeded with malformed metadata', {
        id: intent.id, metadata: intent.metadata,
      });
      response.status(200).send('malformed metadata, ignored'); // 200 so Stripe stops retrying
      return;
    }

    try {
      await markPaid(meta);
      response.status(200).send('ok');
    } catch (err) {
      logger.error('stripeWebhook: failed to mark Paid', { err: String(err), meta });
      response.status(500).send('internal error'); // 500 so Stripe retries
    }
  },
);
