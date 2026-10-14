// generateTicketJoke callable (zaya-support): the Manager's close flow asks
// for a one-liner matched to the ticket, previews it in an editable box, and
// the owner accepts/tweaks/rewrites before the closing email goes out. The
// whole generation core (Anthropic Messages API call, 8s timeout, canned-bank
// fallback) is pure-ish and injected in src/lib/support.ts generateJoke() —
// this file only adds the admin gate and the secret.
//
// Spec: docs/superpowers/specs/2026-10-13-support-tickets-design.md
// ("generateTicketJoke (callable, admin-only)").

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { defineSecret } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { generateJoke } from './lib/support';

export const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');

export const generateTicketJoke = onCall(
  { secrets: [anthropicApiKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in first.');
    }
    // Admin allowlist (spec: /Admins/<uid> = true drives rules + inbox).
    const adminSnap = await admin.database().ref(`Admins/${uid}`).get();
    if (adminSnap.val() !== true) {
      throw new HttpsError('permission-denied', 'Admins only.');
    }

    const category = typeof request.data?.category === 'string' ? request.data.category : '';
    const message = typeof request.data?.message === 'string' ? request.data.message : '';
    if (!message.trim()) {
      throw new HttpsError('invalid-argument', 'Missing ticket message.');
    }

    // Key absent/unbound -> '' -> generateJoke falls back to the canned bank.
    let apiKey = '';
    try {
      apiKey = (anthropicApiKey.value() ?? '').trim();
    } catch {
      apiKey = '';
    }
    if (!apiKey) {
      logger.warn('generateTicketJoke: ANTHROPIC_API_KEY not configured — using canned bank');
    }

    const result = await generateJoke({ category, message, apiKey });
    logger.info('generateTicketJoke', { uid, category, source: result.source });
    return result; // { joke, source: 'ai' | 'bank' }
  },
);
