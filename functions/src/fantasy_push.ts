// sendFantasyReminderNow callable (P4 Phase F): the Manager's "Send now"
// button beside the reminder config. Admin-gated via /Admins
// (generateTicketJoke parity); the audience rule and message building live
// pure in src/lib/fantasy/orchestration.ts sendReminderNow / pushes.ts.
//
// data: { sport:string, season:string|number, audience?: 'all' } — the
// default audience is the scheduled reminder's (unchanged squads only).
// Returns { gw, audience, sent }.
//
// Spec: docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md §12.
// Plan: docs/superpowers/plans/2026-10-28-fantasy-p4-functions.md Phase F.

import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  fantasyLogger, rtdbFantasyDb, rtdbFantasyPusher,
} from './fantasy_adapter';
import { sendReminderNow } from './lib/fantasy/orchestration';

function asTrimmedString(v: unknown): string {
  return typeof v === 'string' || typeof v === 'number' ? String(v).trim() : '';
}

export const sendFantasyReminderNow = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  // Admin allowlist (/Admins/<uid> = true drives rules + Manager inbox).
  const adminSnap = await admin.database().ref(`Admins/${uid}`).get();
  if (adminSnap.val() !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }

  const sport = asTrimmedString(request.data?.sport);
  const season = asTrimmedString(request.data?.season);
  if (!sport || !season) {
    throw new HttpsError('invalid-argument', 'Missing sport/season.');
  }
  const audience = request.data?.audience === 'all' ? 'all' : 'unchanged';

  const root = admin.database().ref();
  try {
    return await sendReminderNow(
      rtdbFantasyDb(root), rtdbFantasyPusher(root), {
        sport, season, audience, nowUtc: new Date(), log: fantasyLogger,
      });
  } catch (err) {
    throw new HttpsError('failed-precondition', String(err));
  }
});
