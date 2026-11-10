// The two account-deletion callables (plan 2026-11-09-account-deletion,
// Task 2), driven through `.run(request)` with firebase-admin mocked over an
// in-memory tree (fantasy_access.test.ts style), Auth and Storage faked and
// the logger captured so the "no uid in any line" rule is asserted.

import { beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({
  tree: {} as Record<string, any>,
  failWrite: null as string | null,
  failStorage: false,
  deletedAuth: [] as string[],
  authDeleteError: null as unknown,
  providers: {} as Record<string, string>,
  getUserError: null as unknown,
  storageDeleted: [] as string[],
  lines: [] as string[],
}));

function fakeRef(path: string): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = h.tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : node;
  };
  const write = (value: unknown) => {
    if (h.failWrite !== null && parts.join('/').startsWith(h.failWrite)) throw new Error(`db down at ${path}`);
    let node: any = h.tree;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') node[p] = {};
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete node[last]; else node[last] = value;
  };
  return {
    child: (sub: string) => fakeRef(`${path}/${sub}`),
    get: async () => ({ val: () => read() }),
    set: async (v: unknown) => write(v),
    remove: async () => write(null),
  };
}

vi.mock('firebase-admin', () => ({
  database: () => ({ ref: (path?: string) => fakeRef(path ?? '') }),
  // The shallow key read needs an app; without one it falls back to a full read.
  app: () => { throw new Error('no app in unit tests'); },
}));
vi.mock('firebase-admin/auth', () => ({
  getAuth: () => ({
    deleteUser: async (uid: string) => {
      if (h.authDeleteError !== null) throw h.authDeleteError;
      if (h.deletedAuth.includes(uid)) {
        throw Object.assign(new Error('gone'), { code: 'auth/user-not-found' });
      }
      h.deletedAuth.push(uid);
    },
    getUser: async (uid: string) => {
      if (h.getUserError !== null) throw h.getUserError;
      const id = h.providers[uid];
      if (id === undefined) throw Object.assign(new Error('gone'), { code: 'auth/user-not-found' });
      return { providerData: [{ providerId: id }] };
    },
  }),
}));
vi.mock('firebase-admin/storage', () => ({
  getStorage: () => ({
    bucket: () => ({
      file: (p: string) => ({
        delete: async (opts: unknown) => {
          if (h.failStorage) throw new Error(`storage down for ${p}`);
          if (JSON.stringify(opts) !== '{"ignoreNotFound":true}') throw new Error('wrong options');
          h.storageDeleted.push(p);
        },
      }),
    }),
  }),
}));
vi.mock('firebase-functions/logger', () => {
  const line = (kind: string) => (m: string, c?: unknown) => {
    h.lines.push(`${kind} ${m} ${JSON.stringify(c ?? {})}`);
  };
  return { info: line('info'), warn: line('warn'), error: line('error'), debug: line('debug') };
});

import { adminDeleteAccount, deleteAccount } from './account_deletion';

const ALICE = 'uid_alice_12345';
const BOB = 'uid_bob_12345';
const ADMIN = 'uid_admin_12345';
const NOW = Date.UTC(2026, 10, 9, 18);

function call(
  fn: { run: (req: never) => Promise<unknown> }, data: unknown,
  auth?: { uid: string; token?: Record<string, unknown> },
): Promise<unknown> {
  return fn.run({
    data,
    auth: auth === undefined ? undefined : { uid: auth.uid, token: auth.token ?? {} },
    rawRequest: {},
    acceptsStreaming: false,
  } as never);
}

const fresh = (uid = ALICE) => ({
  uid, token: { auth_time: Math.floor(NOW / 1000) - 30, firebase: { sign_in_provider: 'google.com' } },
});

async function failure(p: Promise<unknown>): Promise<any> {
  try { await p; } catch (e) { return e; }
  throw new Error('expected the call to fail');
}

function seed(): void {
  h.tree = {
    Admins: { [ADMIN]: true },
    Users: { [ALICE]: { 'First Name': 'Alice', Email: 'a***@example.com' }, [BOB]: { 'First Name': 'Bob' } },
    PublicProfiles: { [ALICE]: { 'First Name': 'Alice' } },
    Fantasy: { Futsal: { '15': {
      Config: { budgetTenths: 1000 },
      Managers: { [ALICE]: { TeamName: 'Alice FC', DisplayName: 'Alice Able' }, [BOB]: { TeamName: 'Bob FC' } },
      Squads: { [ALICE]: { captainId: 'x' } },
    } } },
  };
}

beforeEach(() => {
  seed();
  h.failWrite = null;
  h.failStorage = false;
  h.deletedAuth = [];
  h.authDeleteError = null;
  h.providers = { [ALICE]: 'google.com' };
  h.getUserError = null;
  h.storageDeleted = [];
  h.lines = [];
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

describe('deleteAccount', () => {
  it('refuses a caller who is not signed in', async () => {
    const e = await failure(call(deleteAccount, {}));
    expect(e.code).toBe('unauthenticated');
    expect(e.details).toEqual({ code: 'unauthenticated' });
    expect(h.deletedAuth).toEqual([]);
  });

  it('refuses a stale sign-in with recent-login-required', async () => {
    const token = { auth_time: Math.floor(NOW / 1000) - 6 * 60 };
    const e = await failure(call(deleteAccount, {}, { uid: ALICE, token }));
    expect(e.code).toBe('failed-precondition');
    expect(e.message).toBe('recent-login-required');
    expect(e.details).toEqual({ code: 'recent-login-required' });
    expect(h.tree.Users[ALICE]).toBeDefined();
    const missing = await failure(call(deleteAccount, {}, { uid: ALICE, token: {} }));
    expect(missing.details).toEqual({ code: 'recent-login-required' });
  });

  it('refuses the old account of a merge and names the kept hint', async () => {
    h.tree.Users[ALICE] = { MergedInto: 'uid_kept_12345', MergedHint: 'k***@example.com' };
    const e = await failure(call(deleteAccount, {}, fresh()));
    expect(e.code).toBe('failed-precondition');
    expect(e.message).toBe('already-merged');
    expect(e.details).toEqual({ code: 'already-merged', keepHint: 'k***@example.com' });
    expect(h.deletedAuth).toEqual([]);
    expect(h.tree.Users[ALICE]).toBeDefined();
  });

  it('applies the plan, then deletes the Auth user, and returns counts only', async () => {
    const result = await call(deleteAccount, { uid: BOB }, fresh()) as Record<string, unknown>;
    expect(Object.keys(result).sort())
      .toEqual(['anonymised', 'deleted', 'handoffs', 'pendingStorage', 'storageDeleted']);
    expect(Object.values(result).every((v) => typeof v === 'number')).toBe(true);
    expect(result['deleted']).toBeGreaterThan(0);
    expect(result['anonymised']).toBeGreaterThan(0); // Managers/<uid>
    expect(result['pendingStorage']).toBe(0);
    expect(JSON.stringify(result)).not.toContain(ALICE);
    // The uid is the token's, never the payload's: bob is untouched.
    expect(h.tree.Users[BOB]).toBeDefined();
    expect(h.tree.Users[ALICE]).toBeUndefined();
    expect(h.tree.PublicProfiles[ALICE]).toBeUndefined();
    expect(h.tree.Fantasy.Futsal['15'].Managers[ALICE])
      .toEqual({ TeamName: 'Deleted manager', Deleted: true });
    expect(h.tree.DeletedAccounts[ALICE]).toEqual({ At: NOW, Provider: 'google.com' });
    expect(h.storageDeleted).toEqual([`Users/${ALICE}/profileimage.jpg`]);
    expect(h.deletedAuth).toEqual([ALICE]);
    expect(h.lines.filter((l) => l.includes(ALICE))).toEqual([]);
  });

  it('a Storage leftover does not block the Auth deletion and is counted as pending', async () => {
    h.failStorage = true;
    const result = await call(deleteAccount, {}, fresh()) as Record<string, number>;
    expect(result['pendingStorage']).toBe(1);
    expect(result['storageDeleted']).toBe(0);
    expect(h.deletedAuth).toEqual([ALICE]);
    expect(h.tree.DeletedAccounts[ALICE].PendingStorage).toEqual([`Users/${ALICE}/profileimage.jpg`]);
    expect(h.lines.filter((l) => l.includes(ALICE))).toEqual([]);
  });

  it('a database failure answers deletion-incomplete and keeps the Auth user', async () => {
    h.failWrite = 'PublicProfiles';
    const e = await failure(call(deleteAccount, {}, fresh()));
    expect(e.code).toBe('internal');
    expect(e.message).toBe('deletion-incomplete');
    expect(e.details).toEqual({ code: 'deletion-incomplete' });
    expect(JSON.stringify([e.message, e.details])).not.toContain(ALICE);
    expect(h.deletedAuth).toEqual([]);
    expect(h.tree.DeletedAccounts).toBeUndefined();
    expect(h.lines.some((l) => l.startsWith('warn'))).toBe(true);
    expect(h.lines.filter((l) => l.includes(ALICE))).toEqual([]);
  });

  it('two concurrent calls for the same uid both succeed; the second deleteUser not-found is success', async () => {
    const [a, b] = await Promise.all([
      call(deleteAccount, {}, fresh()), call(deleteAccount, {}, fresh()),
    ]) as Array<Record<string, number>>;
    expect(a['pendingStorage']).toBe(0);
    expect(b['pendingStorage']).toBe(0);
    expect(h.deletedAuth).toEqual([ALICE]); // deleted once; the other saw not-found
    expect(h.tree.Users[ALICE]).toBeUndefined();
    expect(h.tree.DeletedAccounts[ALICE]).toEqual({ At: NOW, Provider: 'google.com' });
  });

  it('treats auth/user-not-found as success and fails loudly on other Auth errors', async () => {
    h.authDeleteError = Object.assign(new Error('gone'), { code: 'auth/user-not-found' });
    await expect(call(deleteAccount, {}, fresh())).resolves.toBeDefined();

    seed();
    h.authDeleteError = Object.assign(new Error('boom'), { code: 'auth/internal-error' });
    const e = await failure(call(deleteAccount, {}, fresh()));
    expect(e.code).toBe('internal');
    expect(e.message).toBe('auth-delete-failed');
    expect(JSON.stringify([e.message, e.details])).not.toContain(ALICE);
    // The database part is done; the retry just finishes the Auth user.
    h.authDeleteError = null;
    await expect(call(deleteAccount, {}, fresh())).resolves.toBeDefined();
    expect(h.deletedAuth).toEqual([ALICE]);
  });
});

describe('adminDeleteAccount', () => {
  const admin = () => ({ uid: ADMIN, token: {} });

  it('refuses a caller who is not signed in or not an admin', async () => {
    const anon = await failure(call(adminDeleteAccount, { uid: ALICE }));
    expect(anon.code).toBe('unauthenticated');
    expect(anon.details).toEqual({ code: 'unauthenticated' });
    const e = await failure(call(adminDeleteAccount, { uid: ALICE }, { uid: BOB, token: {} }));
    expect(e.code).toBe('permission-denied');
    expect(e.details).toEqual({ code: 'permission-denied' });
    expect(h.tree.Users[ALICE]).toBeDefined();
    expect(h.deletedAuth).toEqual([]);
  });

  it('validates the uid and the reason', async () => {
    const bad = [undefined, {}, { uid: 5 }, { uid: 'short' }, { uid: 'bad/uid/xxxxxxxx' },
      { uid: ALICE, reason: 5 }, { uid: ALICE, reason: 'x'.repeat(201) }];
    for (const data of bad) {
      const e = await failure(call(adminDeleteAccount, data, admin()));
      expect(e.code).toBe('invalid-argument');
      expect(e.details).toEqual({ code: 'invalid-argument' });
    }
    expect(h.tree.Users[ALICE]).toBeDefined();
  });

  it('runs for an admin, stamps By and Reason, and deletes the Auth user', async () => {
    const result = await call(adminDeleteAccount, { uid: ALICE, reason: '  emailed request  ' }, admin());
    expect(result).toMatchObject({ pendingStorage: 0 });
    expect(JSON.stringify(result)).not.toContain(ALICE);
    expect(h.tree.Users[ALICE]).toBeUndefined();
    expect(h.tree.DeletedAccounts[ALICE]).toEqual({
      At: NOW, Provider: 'google.com', By: ADMIN, Reason: 'emailed request',
    });
    expect(h.deletedAuth).toEqual([ALICE]);
    expect(h.lines.filter((l) => l.includes(ALICE))).toEqual([]);
  });

  it('a transient getUser failure propagates instead of stamping unknown', async () => {
    h.getUserError = Object.assign(new Error('unavailable'), { code: 'auth/internal-error' });
    await expect(call(adminDeleteAccount, { uid: ALICE }, admin())).rejects.toThrow('unavailable');
    expect(h.tree.Users[ALICE]).toBeDefined();
    expect(h.tree.DeletedAccounts).toBeUndefined();
    expect(h.deletedAuth).toEqual([]);
  });

  it('an unknown uid is not an error: only the stamp is planned', async () => {
    const result = await call(adminDeleteAccount, { uid: 'uid_nobody_1234' }, admin()) as Record<string, number>;
    expect(result['deleted']).toBe(0);
    expect(h.tree.DeletedAccounts['uid_nobody_1234']).toEqual({ At: NOW, Provider: 'unknown', By: ADMIN });
    expect(h.deletedAuth).toEqual(['uid_nobody_1234']);
  });

  it('refuses a merged old account like the self-service call', async () => {
    h.tree.Users[ALICE] = { MergedInto: 'uid_kept_12345', MergedHint: 'k***@example.com' };
    const e = await failure(call(adminDeleteAccount, { uid: ALICE }, admin()));
    expect(e.details).toEqual({ code: 'already-merged', keepHint: 'k***@example.com' });
  });
});
