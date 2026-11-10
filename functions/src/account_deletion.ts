// Account deletion — the two callables (plan 2026-11-09-account-deletion,
// Task 2; design D2, D5). Thin: the planner and applier live pure in
// src/lib/account_deletion.ts; this file wires the admin SDK (RTDB, Auth,
// Storage) and the caller rules.
//
// deleteAccount (callable, the signed-in fan, on themselves)
//   data: none — the uid is ALWAYS request.auth.uid, never a parameter.
//   -> { deleted, anonymised, handoffs, storageDeleted, pendingStorage }
//      counts only; never a path or a uid.
//   Errors: unauthenticated / failed-precondition (details.code
//   'recent-login-required' when auth_time is older than 5 minutes;
//   'already-merged' + keepHint for the old account of a merge) / internal
//   ('deletion-incomplete' when a database step failed - nothing is
//   stamped and the Auth user stays so a retry finishes it;
//   'auth-delete-failed' when only the Auth user could not be removed).
//
// adminDeleteAccount (callable, admin-gated by requireAdmin)
//   data: { uid: string, reason?: string (<= 200 chars) }
//   Same run for that uid; DeletedAccounts/<uid> gets By = the admin and
//   Reason. An unknown uid is not an error (only the stamp is planned).
//
// Order: database steps -> Storage -> DeletedAccounts stamp -> Auth user. A
// Storage leftover (PendingStorage) never blocks the Auth deletion.

import * as admin from 'firebase-admin';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import * as logger from 'firebase-functions/logger';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { fantasyLogger, rtdbFantasyDb } from './fantasy_adapter';
import { requireAdmin } from './fantasy_messages';
import {
  applyAccountDeletion, DeletionStamp, ObjectStore, planAccountDeletion,
  readAccountDeletionSnapshot,
} from './lib/account_deletion';

/** How fresh the sign-in must be: the bar Firebase sets for client deletes. */
const RECENT_LOGIN_MS = 5 * 60 * 1000;
const ADMIN_UID_RE = /^[A-Za-z0-9_-]{8,128}$/;
const MAX_REASON = 200;

/** Counts only. */
export interface DeletionResult {
  deleted: number;
  anonymised: number;
  handoffs: number;
  storageDeleted: number;
  pendingStorage: number;
}

/** getStorage().bucket().file(p).delete — a missing object is success. */
function bucketStore(): ObjectStore {
  return {
    async deleteObject(path: string): Promise<void> {
      await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
    },
  };
}

function authErrorCode(err: unknown): string {
  const code = (err as { code?: unknown } | null)?.code;
  return typeof code === 'string' ? code : '';
}

/** The plan, the apply, then the Auth user. Never logs or returns the uid. */
async function deleteAccountFor(uid: string, stamp: DeletionStamp): Promise<DeletionResult> {
  const db = rtdbFantasyDb(admin.database().ref());
  const snapshot = await readAccountDeletionSnapshot(db, uid, fantasyLogger);
  const plan = planAccountDeletion(snapshot, uid, stamp);
  if (plan.refused !== undefined) {
    throw new HttpsError('failed-precondition', 'already-merged', {
      code: 'already-merged', keepHint: plan.keepHint,
    });
  }
  const summary = await applyAccountDeletion(db, bucketStore(), plan);
  if (!summary.stamped) {
    logger.warn('account deletion: a database step failed; Auth user kept', {
      errors: summary.errors.length, deleted: summary.deleted,
    });
    throw new HttpsError('internal', 'deletion-incomplete', { code: 'deletion-incomplete' });
  }
  try {
    await getAuth().deleteUser(uid);
  } catch (err) {
    if (authErrorCode(err) !== 'auth/user-not-found') {
      logger.warn('account deletion: Auth user not deleted', { code: authErrorCode(err) });
      throw new HttpsError('internal', 'auth-delete-failed', { code: 'auth-delete-failed' });
    }
  }
  return {
    deleted: summary.deleted,
    anonymised: summary.anonymised,
    handoffs: summary.handoffs,
    storageDeleted: summary.storageDeleted,
    // Stamped => every remaining error is a Storage delete.
    pendingStorage: summary.errors.length,
  };
}

function requireRecentLogin(request: CallableRequest): void {
  const authTime = request.auth?.token?.['auth_time'];
  const ok = typeof authTime === 'number' && Date.now() - authTime * 1000 <= RECENT_LOGIN_MS;
  if (!ok) {
    throw new HttpsError('failed-precondition', 'recent-login-required', {
      code: 'recent-login-required',
    });
  }
}

export const deleteAccount = onCall(async (request): Promise<DeletionResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  requireRecentLogin(request);
  const provider = request.auth?.token?.firebase?.sign_in_provider;
  return deleteAccountFor(uid, {
    nowMs: Date.now(),
    provider: typeof provider === 'string' && provider.length > 0 ? provider : 'unknown',
  });
});

/** The target's sign-in provider id for the stamp; 'unknown' when the Auth
 *  user is already gone. */
async function providerOf(uid: string): Promise<string> {
  try {
    const user = await getAuth().getUser(uid);
    return user.providerData[0]?.providerId ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

export const adminDeleteAccount = onCall(async (request): Promise<DeletionResult> => {
  const adminUid = await requireAdmin(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const uid = data['uid'];
  if (typeof uid !== 'string' || !ADMIN_UID_RE.test(uid)) {
    throw new HttpsError('invalid-argument', 'uid is not a valid account id.');
  }
  const rawReason = data['reason'];
  if (rawReason !== undefined && typeof rawReason !== 'string') {
    throw new HttpsError('invalid-argument', 'reason must be text.');
  }
  const reason = (rawReason ?? '').trim();
  if (reason.length > MAX_REASON) {
    throw new HttpsError('invalid-argument', `reason is longer than ${MAX_REASON} characters.`);
  }
  return deleteAccountFor(uid, {
    nowMs: Date.now(),
    provider: await providerOf(uid),
    by: adminUid,
    ...(reason.length > 0 ? { reason } : {}),
  });
});
