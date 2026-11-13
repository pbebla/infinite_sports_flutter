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

    // { category } only. A `message` sent by an older Manager build is
    // deliberately never read: the person's words must not reach the AI
    // service (Privacy Policy) or the logs. Missing/unknown category -> the
    // generic one (normalizeCategory).
    const data = (request.data ?? {}) as Record<string, unknown>;
    const category = typeof data['category'] === 'string' ? data['category'] : '';

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

    const result = await generateJoke({ category, apiKey });
    logger.info('generateTicketJoke', { uid: uid.slice(0, 6), category, source: result.source });
    return result; // { joke, source: 'ai' | 'bank' }
  },
);
