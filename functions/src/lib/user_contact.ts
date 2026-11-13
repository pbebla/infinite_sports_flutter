// Pure core of the admin getUserContact callable (round 3 spec §3.4). Emails
// are not stored in RTDB, so Firebase Auth is the only source; the Admin SDK
// is injected as a one-method port so this stays vitest-able without it.
// Read-only: nothing here writes anywhere.

/** The slice of a Firebase Auth UserRecord this core reads. */
export interface UserContactRecord {
  email?: string;
  providerData: Array<{ providerId: string }>;
}

/** The slice of admin.auth() this core needs. */
export interface UserContactAuth {
  getUser(uid: string): Promise<UserContactRecord>;
}

export interface UserContact {
  email: string | null;
  /** Firebase provider ids: 'password', 'google.com', 'apple.com', ... */
  signInMethods: string[];
}

/** firebase-admin's AuthClientErrorCode.USER_NOT_FOUND, as thrown by getUser. */
const USER_NOT_FOUND = 'auth/user-not-found';

/** The uid's email and sign-in methods. An unknown uid (a fake test manager,
 *  a deleted account) is a normal answer — `{email: null, signInMethods: []}`
 *  — never an error. Every OTHER failure (quota, network, permissions)
 *  propagates: swallowing it would show "No account" for a real manager. */
export async function getUserContactCore(
  auth: UserContactAuth, uid: string,
): Promise<UserContact> {
  let user: UserContactRecord;
  try {
    user = await auth.getUser(uid);
  } catch (err) {
    if ((err as { code?: unknown } | null)?.code === USER_NOT_FOUND) {
      return { email: null, signInMethods: [] };
    }
    throw err;
  }
  const email = typeof user.email === 'string' && user.email.length > 0
    ? user.email : null;
  return {
    email,
    signInMethods: user.providerData.map((p) => p.providerId),
  };
}
