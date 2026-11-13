// The getUserContact callable wrapper (round 3 spec §3.4 / §12 "getUserContact
// admin gate"): requireAdmin -> invalid-argument check -> Auth call. The pure
// core is covered in lib/user_contact.test.ts; this drives the v2 callable
// itself through `.run(request)` with firebase-admin mocked — requireAdmin's
// RTDB read (Admins/<uid>) and admin.auth().getUser — so no emulator is needed.

import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({
  /** What Admins/<uid> reads as (requireAdmin accepts only exactly true). */
  adminValue: null as unknown,
  /** Every RTDB path the gate read. */
  dbPaths: [] as string[],
  getUser: vi.fn(),
}));

vi.mock('firebase-admin', () => ({
  database: () => ({
    ref: (path: string) => {
      h.dbPaths.push(path);
      return { get: async () => ({ val: () => h.adminValue }) };
    },
  }),
  auth: () => ({ getUser: h.getUser }),
}));

import { getUserContact } from './user_contact';

/** A CallableRequest as the v2 runtime hands it over (only data/auth matter). */
function call(data: unknown, uid?: string) {
  return getUserContact.run({
    data,
    auth: uid === undefined ? undefined : { uid, token: {} },
    rawRequest: {},
    acceptsStreaming: false,
  } as never);
}

beforeEach(() => {
  h.adminValue = null;
  h.dbPaths.length = 0;
  h.getUser.mockReset();
});

describe('getUserContact callable', () => {
  it('unauthenticated caller -> unauthenticated, Auth not called', async () => {
    await expect(call({ uid: 'u1' })).rejects.toMatchObject({
      code: 'unauthenticated',
    });
    expect(h.getUser).not.toHaveBeenCalled();
    expect(h.dbPaths).toEqual([]); // never even reached the Admins lookup
  });

  it('signed-in non-admin -> permission-denied, Auth not called', async () => {
    for (const adminValue of [null, false, 'true', 1]) {
      h.adminValue = adminValue; // anything but exactly true is not an admin
      await expect(call({ uid: 'u1' }, 'someFan')).rejects.toMatchObject({
        code: 'permission-denied',
      });
    }
    expect(h.dbPaths.every((p) => p === 'Admins/someFan')).toBe(true);
    expect(h.getUser).not.toHaveBeenCalled();
  });

  it('admin with a missing or blank uid -> invalid-argument, Auth not called', async () => {
    h.adminValue = true;
    for (const data of [
      undefined, null, {}, { uid: '' }, { uid: '   ' }, { uid: 42 },
      { uid: ['u1'] },
    ]) {
      await expect(call(data, 'adm')).rejects.toMatchObject({
        code: 'invalid-argument',
      });
    }
    expect(h.getUser).not.toHaveBeenCalled();
  });

  it('admin with a good uid -> the core result (email + providerIds)', async () => {
    h.adminValue = true;
    h.getUser.mockResolvedValue({
      email: 'zed@example.com',
      providerData: [{ providerId: 'password' }, { providerId: 'google.com' }],
    });
    expect(await call({ uid: ' u1 ' }, 'adm')).toEqual({
      email: 'zed@example.com', signInMethods: ['password', 'google.com'],
    });
    expect(h.dbPaths).toEqual(['Admins/adm']);
    expect(h.getUser).toHaveBeenCalledTimes(1);
    expect(h.getUser).toHaveBeenCalledWith('u1'); // trimmed
  });

  it('admin asking for an unknown uid -> {email: null, signInMethods: []}', async () => {
    h.adminValue = true;
    h.getUser.mockRejectedValue(
      Object.assign(new Error('no user'), { code: 'auth/user-not-found' }));
    expect(await call({ uid: 'fakeTestManager' }, 'adm')).toEqual({
      email: null, signInMethods: [],
    });
  });

  it('other Auth failures are not swallowed', async () => {
    h.adminValue = true;
    h.getUser.mockRejectedValue(
      Object.assign(new Error('quota'), { code: 'auth/quota-exceeded' }));
    await expect(call({ uid: 'u1' }, 'adm')).rejects.toThrow('quota');
  });
});
