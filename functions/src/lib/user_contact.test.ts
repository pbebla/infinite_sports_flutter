// getUserContact core (round 3 spec §3.4): Firebase Auth is injected, so the
// mapping and the user-not-found contract are tested without the Admin SDK.

import { describe, expect, it } from 'vitest';
import { getUserContactCore, UserContactAuth } from './user_contact';

/** A stand-in for admin.auth(): getUser resolves a record or throws. */
function fakeAuth(
  users: Record<string, {
    email?: string; providerData: Array<{ providerId: string }>;
  }>,
): UserContactAuth {
  return {
    async getUser(uid: string) {
      const u = users[uid];
      if (!u) {
        // Exactly what firebase-admin throws for an unknown uid.
        throw Object.assign(
          new Error('There is no user record corresponding to the provided identifier.'),
          { code: 'auth/user-not-found' });
      }
      return u;
    },
  };
}

describe('getUserContactCore', () => {
  it('returns email and provider ids', async () => {
    const auth = fakeAuth({
      u1: {
        email: 'zed@example.com',
        providerData: [
          { providerId: 'password' }, { providerId: 'google.com' },
        ],
      },
      u2: {
        email: 'rel@privaterelay.appleid.com',
        providerData: [{ providerId: 'apple.com' }],
      },
    });
    expect(await getUserContactCore(auth, 'u1')).toEqual({
      email: 'zed@example.com', signInMethods: ['password', 'google.com'],
    });
    expect(await getUserContactCore(auth, 'u2')).toEqual({
      email: 'rel@privaterelay.appleid.com', signInMethods: ['apple.com'],
    });
  });

  it('unknown uid returns null email and empty methods', async () => {
    expect(await getUserContactCore(fakeAuth({}), 'nobody')).toEqual({
      email: null, signInMethods: [],
    });
  });

  it('an account without an email (or an empty one) reads null, methods kept', async () => {
    const auth = fakeAuth({
      noEmail: { providerData: [{ providerId: 'apple.com' }] },
      blank: { email: '', providerData: [{ providerId: 'password' }] },
    });
    expect(await getUserContactCore(auth, 'noEmail')).toEqual({
      email: null, signInMethods: ['apple.com'],
    });
    expect(await getUserContactCore(auth, 'blank')).toEqual({
      email: null, signInMethods: ['password'],
    });
  });

  it('other Auth errors propagate (never swallowed as "no account")', async () => {
    const boom = Object.assign(new Error('quota'), { code: 'auth/quota-exceeded' });
    const auth: UserContactAuth = {
      async getUser() { throw boom; },
    };
    await expect(getUserContactCore(auth, 'u1')).rejects.toBe(boom);

    const plain: UserContactAuth = {
      async getUser() { throw new Error('network down'); },
    };
    await expect(getUserContactCore(plain, 'u1')).rejects.toThrow('network down');
  });
});
