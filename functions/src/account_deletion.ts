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
//   'recent-login-required' when auth_time is older than 5 minutes, unless
//   the account is brand new and never finished its profile (see
//   isNewIncompleteAccount: the under-13 exit must work without a re-login);
//   'already-merged' + keepHint for the old account of a merge) / internal
//   ('deletion-incomplete' when a database step failed - nothing is
//   stamped and the Auth user stays so a retry finishes it;
//   'auth-delete-failed' when only the Auth user could not be removed).
//
// adminDeleteAccount (callable, admin-gated by requireAdmin)
//   data: { uid: string, reason?: string (<= 200 chars) }
//   Same run for that uid; DeletedAccounts/<uid> gets By = the admin
//   (reason is accepted for compatibility but never stored or logged). An unknown uid is not an error (only the stamp is planned).
//   Refuses (failed-precondition, details.code 'admin-protected') the
//   caller's own uid and any uid with /Admins/<uid> === true (M7). An old
//   account of a merge is deleted on its own (C1; no already-merged refusal).
//
// C1: deleting a kept account also deletes the old accounts combined into it
// (Users/<uid>/MergedFrom): their data in the same plan, then each old Auth
// user (user-not-found = done; any other failure goes to the stamp's
// PendingAuth and is retried by a rerun, never thrown), then the person's
// own Auth user. The result adds `oldAccounts` and `pendingAuth` (counts).
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
  applyAccountDeletion, DeletionOptions, DeletionStamp, ObjectStore, planAccountDeletion,
  readAccountDeletionSnapshot, settlePendingAuth,
} from './lib/account_deletion';

/** How fresh the sign-in must be: the bar Firebase sets for client deletes. */
const RECENT_LOGIN_MS = 5 * 60 * 1000;
/** How new an account with an unfinished profile must be to skip that bar. */
const NEW_ACCOUNT_MS = 7 * 24 * 60 * 60 * 1000;
const ADMIN_UID_RE = /^[A-Za-z0-9_-]{8,128}$/;
const MAX_REASON = 200;

/** Counts only. */
export interface DeletionResult {
  deleted: number;
  anonymised: number;
  handoffs: number;
  storageDeleted: number;
  pendingStorage: number;
  /** C1: old accounts (combined into this one) deleted with it. */
  oldAccounts: number;
  /** C1: old accounts whose Auth user is still there (retried on a rerun). */
  pendingAuth: number;
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
async function deleteAccountFor(
  uid: string, stamp: DeletionStamp, opts: DeletionOptions = {},
): Promise<DeletionResult> {
  const db = rtdbFantasyDb(admin.database().ref());
  const snapshot = await readAccountDeletionSnapshot(db, uid, fantasyLogger, opts);
  const plan = planAccountDeletion(snapshot, uid, stamp, opts);
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
  // C1: the old accounts' Auth users first - a failure is recorded in the
  // stamp's PendingAuth (a rerun tries again), never thrown, so the person's
  // own deletion is not held up by an account they no longer use.
  const olds = plan.authUidsToDelete.filter((u) => u !== uid);
  const stillThere: string[] = [];
  for (const old of olds) {
    try {
      await getAuth().deleteUser(old);
    } catch (err) {
      if (authErrorCode(err) !== 'auth/user-not-found') {
        logger.warn('account deletion: an old Auth user not deleted', { code: authErrorCode(err) });
        stillThere.push(old);
      }
    }
  }
  if (olds.length > 0) {
    try {
      await settlePendingAuth(db, uid, stillThere);
    } catch {
      // The stamp still lists every old account: a rerun retries them all.
      logger.warn('account deletion: PendingAuth not settled', { pending: olds.length });
    }
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
    oldAccounts: snapshot.merged.length,
    pendingAuth: stillThere.length,
  };
}

/** True only when ALL hold: Users/<uid>/ProfileCompleted is not true, there
 *  is no Users/<uid>/MergedFrom (not the kept account of a combine), AND
 *  the Auth user was created within the last 7 days. Such an account (the
 *  under-13 exit right after sign-up) may delete itself without a fresh
 *  sign-in. Any doubt - a gone Auth user, an unreadable creation time, a
 *  failed read - answers false, so the recent-login rule applies as before. */
async function isNewIncompleteAccount(uid: string): Promise<boolean> {
  try {
    const completed = (await admin.database().ref(`Users/${uid}/ProfileCompleted`).get()).val();
    if (completed === true) return false;
    // A KEPT account of a combine never qualifies: its deletion cascades to
    // the old accounts combined into it (C1).
    const mergedFrom = (await admin.database().ref(`Users/${uid}/MergedFrom`).get()).val();
    if (mergedFrom !== null && mergedFrom !== undefined) return false;
    const user = await getAuth().getUser(uid);
    const created = Date.parse(String(user.metadata?.creationTime ?? ''));
    if (!Number.isFinite(created)) return false;
    const age = Date.now() - created;
    return age >= 0 && age <= NEW_ACCOUNT_MS;
  } catch (err) {
    if (authErrorCode(err) !== 'auth/user-not-found') {
      logger.warn('account deletion: new-account check failed; recent login required', {
        code: authErrorCode(err),
      });
    }
    return false;
  }
}

async function requireRecentLogin(request: CallableRequest, uid: string): Promise<void> {
  const authTime = request.auth?.token?.['auth_time'];
  const ok = typeof authTime === 'number' && Date.now() - authTime * 1000 <= RECENT_LOGIN_MS;
  if (!ok && !(await isNewIncompleteAccount(uid))) {
    throw new HttpsError('failed-precondition', 'recent-login-required', {
      code: 'recent-login-required',
    });
  }
}

export const deleteAccount = onCall(async (request): Promise<DeletionResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.', { code: 'unauthenticated' });
  await requireRecentLogin(request, uid);
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
  } catch (err) {
    // Only a gone user is 'unknown'; a transient failure must not stamp it.
    if (authErrorCode(err) === 'auth/user-not-found') return 'unknown';
    throw err;
  }
}

export const adminDeleteAccount = onCall(async (request): Promise<DeletionResult> => {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Sign in first.', { code: 'unauthenticated' });
  }
  let adminUid: string;
  try {
    adminUid = await requireAdmin(request); // shared; leaves no details of its own
  } catch (err) {
    if (err instanceof HttpsError && err.code === 'permission-denied') {
      throw new HttpsError('permission-denied', 'Admins only.', { code: 'permission-denied' });
    }
    throw err;
  }
  const data = (request.data ?? {}) as Record<string, unknown>;
  const uid = data['uid'];
  if (typeof uid !== 'string' || !ADMIN_UID_RE.test(uid)) {
    throw new HttpsError('invalid-argument', 'uid is not a valid account id.', {
      code: 'invalid-argument',
    });
  }
  const rawReason = data['reason'];
  if (rawReason !== undefined && typeof rawReason !== 'string') {
    throw new HttpsError('invalid-argument', 'reason must be text.', { code: 'invalid-argument' });
  }
  const reason = rawReason === undefined ? '' : (rawReason as string).trim();
  if (reason.length > MAX_REASON) {
    throw new HttpsError('invalid-argument', `reason is longer than ${MAX_REASON} characters.`, {
      code: 'invalid-argument',
    });
  }
  // M7: an admin never deletes themself or another admin here (remove them
  // from /Admins first). Same answer for both; no uid in it.
  if (uid === adminUid || (await admin.database().ref(`Admins/${uid}`).get()).val() === true) {
    throw new HttpsError('failed-precondition', 'admin-protected', { code: 'admin-protected' });
  }
  // C1: an old account of a merge is deleted on its own here (the user path
  // still refuses it and names the kept account).
  return deleteAccountFor(uid, {
    nowMs: Date.now(),
    provider: await providerOf(uid),
    by: adminUid,
  }, { allowMerged: true });
});
