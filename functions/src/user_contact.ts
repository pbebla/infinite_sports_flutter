// Admin callable getUserContact (Infinite Fantasy round 3 spec §3.4): the
// Manager's fantasy profile shows a manager's email and how they sign in.
// Emails are not in RTDB, so Firebase Auth is the only source. Admin-gated
// exactly like the other Manager callables (fantasy_messages.ts requireAdmin:
// signed in -> /Admins/<uid> === true). The mapping and the unknown-uid
// contract live pure in src/lib/user_contact.ts. Never writes anything.
//
// getUserContact
//   data: { uid:string }
//   -> { email:string|null, signInMethods:string[] }
//      (providerIds: 'password' | 'google.com' | 'apple.com'; an unknown uid
//       -> { email:null, signInMethods:[] })
//   Errors: unauthenticated / permission-denied / invalid-argument (missing
//   uid). The email is returned to the admin caller only and never logged.

import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { requireAdmin } from './fantasy_messages';
import { getUserContactCore } from './lib/user_contact';

export const getUserContact = onCall(async (request) => {
  await requireAdmin(request);
  const uid = request.data?.uid;
  if (typeof uid !== 'string' || uid.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Missing uid.');
  }
  return getUserContactCore(admin.auth(), uid.trim());
});
