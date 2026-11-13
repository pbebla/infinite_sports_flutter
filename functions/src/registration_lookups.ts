// DB security lockdown Phase A (Task A3): the two registration lookups that
// move server-side because the data they scan becomes unreadable under
// default-deny rules. Both require auth; both do their matching in the pure
// functions of src/lib/registration_lookups_logic.ts (vitest-covered, no
// emulator needed). onCall style mirrors createRegistrationPaymentIntent.ts.
//
// Spec: docs/superpowers/specs/2026-10-27-db-security-lockdown-design.md §1/§4.
// Plan: docs/superpowers/plans/2026-10-27-db-lockdown-implementation.md A3.
//
// Wire shapes (what the Dart side receives — field-for-field the shapes the
// client logic produces today, so Phase B swaps the data source, not the
// consumers):
//
//   checkFirstTimer({email, phone}) ->
//     { isFirstTimer: boolean, matchedByEmail: boolean,
//       matchedByPhone: boolean }
//   — promo_engine.dart's FirstTimerResult, verbatim. Replaces the client's
//   RegistrationService.getAllSubmissionAnswersForMatch scan + firstTimer():
//   email compared trim+lowercase, phone digits-only, against every
//   submission's Answers 'email'/'Email' and 'phone'/'Phone' keys across
//   EVERY registration. Empty inputs never match (-> first-timer).
//
//   resolveJoinCode({regId, code}) ->
//     { found: true,  status: 'ok', teamId: string, teamName: string,
//       codeWaivesPayment: boolean }
//   | { found: false, status: 'notApproved' | 'notFound' }
//   — matchJoinCode's three outcomes (registration_models.dart), with the
//   matched team's identity ONLY on 'ok'. 'notApproved' (the code belongs to
//   a pending/rejected team) carries no team fields, so the join code page
//   keeps its "awaiting approval" message without the server ever revealing
//   another team's data; other teams' codes are never returned in ANY
//   outcome (the entered code itself is not echoed back either).

import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  collectSubmissionAnswers, firstTimerVerdict, resolveJoinCodeFromTeams,
} from './lib/registration_lookups_logic';

/** RTDB-forbidden key characters — a regId carrying any of these is junk
 *  (and could otherwise splice the ref path). Push ids never contain them. */
const FORBIDDEN_KEY_CHARS = /[.#$/\[\]]/;

/** First-timer/promo match (spec §4), server-side. Input {email, phone}
 *  (either may be empty — an empty signal simply never matches). Scans every
 *  Registrations/<regId>/Submissions/<uid>/Answers with the Admin SDK,
 *  exactly the data set the client used to download. */
export const checkFirstTimer = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const email = typeof request.data?.email === 'string' ? request.data.email : '';
  const phone = typeof request.data?.phone === 'string' ? request.data.phone : '';

  const snap = await admin.database().ref('Registrations').get();
  const verdict = firstTimerVerdict(
    email, phone, collectSubmissionAnswers(snap.val()));
  // uid + booleans only — never the email/phone being checked.
  logger.info('first-timer check', { uid, ...verdict });
  return verdict;
});

/** Join-code resolution (spec §4), server-side — join codes stop being
 *  client-readable. Input {regId, code}; returns only the matched team's
 *  {found, status, teamId, teamName, codeWaivesPayment} on 'ok', bare
 *  {found, status} otherwise. */
export const resolveJoinCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const regId = request.data?.regId;
  if (typeof regId !== 'string' || regId.length === 0 ||
      FORBIDDEN_KEY_CHARS.test(regId)) {
    throw new HttpsError('invalid-argument', 'Missing regId.');
  }
  const code = request.data?.code;
  if (typeof code !== 'string') {
    throw new HttpsError('invalid-argument', 'Missing code.');
  }

  const snap = await admin.database().ref(`Registrations/${regId}/Teams`).get();
  const resolution = resolveJoinCodeFromTeams(snap.val(), code);
  // uid + regId + outcome only — never the entered code.
  logger.info('join code resolved', { uid, regId, status: resolution.status });
  return resolution;
});
