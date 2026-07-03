// Cloud Function (L1c): creates a Stripe PaymentIntent for the signed-in
// caller's own registration submission. The amount is ALWAYS recomputed
// server-side from RTDB — the client never gets to name its own price.

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import Stripe from 'stripe';
import {
  isAlreadyPaid, legacyTarget, owedCents, RegistrationConfigLike, SubmissionLike, TeamLike,
  webhookMetadata,
} from './lib/stripe_pay';

export const stripeSecretKey = defineSecret('STRIPE_SECRET_KEY');

function parseConfig(raw: unknown): RegistrationConfigLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const c = raw as Record<string, unknown>;
  const targetType = c['TargetType'] === 'tournament' ? 'tournament' : 'league';
  const methods = (c['Methods'] ?? {}) as Record<string, unknown>;
  if (methods['stripe'] !== true) return null; // Stripe not enabled for this registration
  const paymentModeRaw = c['PaymentMode'];
  const paymentMode = paymentModeRaw === 'teamFee' || paymentModeRaw === 'both'
    ? paymentModeRaw : 'perPlayer';
  return {
    targetType,
    sport: String(c['Sport'] ?? ''),
    season: String(c['Season'] ?? ''),
    tournamentId: String(c['TournamentId'] ?? ''),
    tournamentName: String(c['TournamentName'] ?? ''),
    fee: Number(c['Fee'] ?? 0),
    teamFee: Number(c['TeamFee'] ?? 0),
    paymentMode,
  };
}

function parseSubmission(raw: unknown): SubmissionLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const s = raw as Record<string, unknown>;
  const path = s['Path'];
  if (typeof path !== 'string' || path.length === 0) return null;
  return {
    path,
    paid: s['Paid'] === true,
  };
}

function parseTeam(raw: unknown): TeamLike | null {
  if (raw === null || typeof raw !== 'object') return null;
  const t = raw as Record<string, unknown>;
  return { codeWaivesPayment: t['CodeWaivesPayment'] === true };
}

export const createRegistrationPaymentIntent = onCall(
  { secrets: [stripeSecretKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to pay.');
    }
    const regId = request.data?.regId;
    if (typeof regId !== 'string' || regId.length === 0) {
      throw new HttpsError('invalid-argument', 'Missing regId.');
    }

    const db = admin.database();
    const [configSnap, submissionSnap] = await Promise.all([
      db.ref(`Registrations/${regId}/Config`).get(),
      db.ref(`Registrations/${regId}/Submissions/${uid}`).get(),
    ]);
    const config = parseConfig(configSnap.val());
    if (!config) {
      throw new HttpsError('failed-precondition', 'Card payments are not enabled for this registration.');
    }
    const submission = parseSubmission(submissionSnap.val());
    if (!submission) {
      throw new HttpsError('not-found', 'No registration submission found for your account.');
    }
    // Double-pay server guard: reject up front (distinct from the generic
    // "nothing owed" message) if this submission is already Paid by ANY
    // method — card webhook, or the owner manually marking Paid in the
    // Manager while a client had the payment sheet open.
    if (isAlreadyPaid(submission)) {
      throw new HttpsError('failed-precondition', 'Already paid.');
    }

    let team: TeamLike | null = null;
    if (submission.path === 'joiner') {
      const teamId = (submissionSnap.val() as Record<string, unknown>)?.['TeamId'];
      if (typeof teamId === 'string' && teamId.length > 0) {
        const teamSnap = await db.ref(`Registrations/${regId}/Teams/${teamId}`).get();
        team = parseTeam(teamSnap.val());
      }
    }

    const amount = owedCents(config, submission, team ?? undefined);
    if (amount <= 0) {
      throw new HttpsError('failed-precondition', 'Nothing is owed for this registration.');
    }

    const target = legacyTarget(config);
    const stripe = new Stripe(stripeSecretKey.value());
    const intent = await stripe.paymentIntents.create({
      amount,
      currency: 'usd',
      automatic_payment_methods: { enabled: true },
      metadata: webhookMetadata({ regId, uid, league: target.league, season: target.season }),
    });

    logger.info('created PaymentIntent', { regId, uid, amount });

    const keySnap = await db.ref('AppConfig/StripePublishableKey').get();
    const publishableKey = typeof keySnap.val() === 'string' ? keySnap.val() : '';

    return { clientSecret: intent.client_secret, publishableKey };
  },
);
