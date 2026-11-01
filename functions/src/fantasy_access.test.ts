// The paid-access callables (spec §7 / plan A3): createFantasyCheckoutSession
// and sendFantasyAccessTest, driven through `.run(request)` with
// firebase-admin mocked over an in-memory tree (user_contact.test.ts style),
// the Stripe client injected through __setStripeForTests and the mailer
// through support_mail's __setMailerForTests. The pusher dry-runs under
// FUNCTIONS_EMULATOR so no FCM is touched.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({
  tree: {} as Record<string, any>,
  reads: [] as string[],
  getUser: (async (_uid: string): Promise<unknown> => ({ email: 'zaya@example.com' })) as
    (uid: string) => Promise<unknown>,
}));

/** Minimal admin Reference over h.tree: child().get()/set()/remove()/
 *  transaction() + push().set() for the MailLog. */
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
    get: async () => { h.reads.push(parts.join('/')); return { val: () => read() }; },
    set: async (v: unknown) => write(v),
    remove: async () => write(null),
    push: () => fakeRef(`${path}/-pushed`),
    transaction: async (update: (cur: unknown) => unknown) => {
      const cur = read();
      const next = update(cur === null ? null : JSON.parse(JSON.stringify(cur)));
      if (next === undefined) return { committed: false, snapshot: { val: () => cur } };
      write(next);
      return { committed: true, snapshot: { val: () => next } };
    },
  };
}

vi.mock('firebase-admin', () => ({
  database: () => ({ ref: (path?: string) => fakeRef(path ?? '') }),
  auth: () => ({ getUser: (uid: string) => h.getUser(uid) }),
  messaging: () => ({ sendEach: async () => { throw new Error('FCM must not be called'); } }),
}));

import {
  __setStripeForTests, checkoutSessionParams, createFantasyCheckoutSession,
  onFantasyAccessClaimCreated, onFantasyAccessStatusWritten, onRegistrationPaidGrantFantasy,
  sendFantasyAccessTest,
} from './fantasy_access';
import { accessConfigFrom } from './lib/fantasy/access';
import { __setMailerForTests } from './support_mail';

const ROOT = 'Fantasy/Futsal/16';

/** A CallableRequest as the v2 runtime hands it over (only data/auth matter). */
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

function seed(over: Record<string, any> = {}): void {
  h.tree = {
    Admins: { adm: true },
    Users: { adm: { Token: 'tok-adm' }, u1: { Token: 'tok-u1' } },
    Fantasy: { Futsal: { '16': { Config: { Access: { Mode: 'pass', AmountDollars: 10, Methods: { Venmo: true, Zelle: false, Card: true } } } } } },
    ...over,
  };
}

let created: unknown[];
let mails: Array<{ to: string; subject: string; html: string }>;

beforeEach(() => {
  seed();
  h.reads.length = 0;
  h.getUser = async () => ({ email: 'zaya@example.com' });
  created = [];
  __setStripeForTests({
    checkout: { sessions: { create: async (params: unknown) => { created.push(params); return { url: 'https://checkout.stripe.com/c/pay/cs_test_1' }; } } },
  });
  mails = [];
  __setMailerForTests({ from: 'noreply@infinitesports.org', send: async (o: any) => { mails.push({ to: o.to, subject: o.subject, html: o.html }); } });
  process.env.FUNCTIONS_EMULATOR = 'true';
});

afterEach(() => {
  __setStripeForTests('unset');
  __setMailerForTests('unset');
  delete process.env.FUNCTIONS_EMULATOR;
});

describe('checkoutSessionParams', () => {
  it('builds the Stripe Checkout params from the SERVER amount with our metadata and the hosting URLs', () => {
    const cfg = accessConfigFrom({ Mode: 'pass', AmountDollars: 10.5 });
    expect(checkoutSessionParams({ cfg, sport: 'Futsal', season: '16', uid: 'u1', email: 'z@example.com' })).toEqual({
      mode: 'payment',
      line_items: [{
        price_data: {
          currency: 'usd', unit_amount: 1050,
          product_data: { name: 'Infinite Fantasy — Futsal Season 16 season pass' },
        },
        quantity: 1,
      }],
      payment_intent_data: { metadata: { kind: 'fantasyAccess', sport: 'Futsal', season: '16', uid: 'u1' } },
      customer_email: 'z@example.com',
      success_url: 'https://infinite-sports-app.web.app/fantasy/paid.html',
      cancel_url: 'https://infinite-sports-app.web.app/fantasy/cancelled.html',
    });
  });

  it('omits customer_email when the token has none', () => {
    const cfg = accessConfigFrom({ Mode: 'pass', AmountDollars: 10 });
    const p = checkoutSessionParams({ cfg, sport: 'Futsal', season: '16', uid: 'u1', email: undefined });
    expect(p).not.toHaveProperty('customer_email');
  });
});

describe('createFantasyCheckoutSession', () => {
  it('unauthenticated -> unauthenticated, nothing read, Stripe untouched', async () => {
    await expect(call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
    expect(h.reads).toEqual([]);
    expect(created).toEqual([]);
  });

  it('missing / blank sport or season -> invalid-argument', async () => {
    for (const data of [undefined, {}, { sport: 'Futsal' }, { sport: '', season: '16' }, { sport: 'Futsal', season: ' ' }]) {
      await expect(call(createFantasyCheckoutSession, data, { uid: 'u1' }))
        .rejects.toMatchObject({ code: 'invalid-argument' });
    }
    expect(created).toEqual([]);
  });

  it('a numeric season is accepted as its string', async () => {
    const r = await call(createFantasyCheckoutSession, { sport: 'Futsal', season: 16 }, { uid: 'u1' });
    expect(r).toEqual({ url: 'https://checkout.stripe.com/c/pay/cs_test_1' });
    expect((created[0] as any).payment_intent_data.metadata.season).toBe('16');
  });

  it.each([
    ['free mode', { Mode: 'free', AmountDollars: 10 }],
    ['no Access config', undefined],
    ['Card off', { Mode: 'pass', AmountDollars: 10, Methods: { Card: false } }],
    ['amount 0', { Mode: 'pass', AmountDollars: 0 }],
    ['amount missing', { Mode: 'pass' }],
  ] as const)('%s -> failed-precondition, Stripe untouched', async (_label, access) => {
    h.tree.Fantasy.Futsal['16'].Config = access === undefined ? {} : { Access: access };
    await expect(call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1' }))
      .rejects.toMatchObject({ code: 'failed-precondition' });
    expect(created).toEqual([]);
  });

  it('already active -> {alreadyActive:true}, no Stripe call (even in free mode)', async () => {
    h.tree.Fantasy.Futsal['16'].Access = { u1: { Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 1, By: 'adm' } };
    expect(await call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1' }))
      .toEqual({ alreadyActive: true });
    h.tree.Fantasy.Futsal['16'].Config.Access.Mode = 'free';
    expect(await call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1' }))
      .toEqual({ alreadyActive: true });
    expect(created).toEqual([]);
  });

  it('pending / revoked are not active: a link is still created', async () => {
    for (const status of ['pending', 'revoked']) {
      created = [];
      h.tree.Fantasy.Futsal['16'].Access = { u1: { Status: status, Via: 'venmo', AmountCents: 1000, By: 'system' } };
      expect(await call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1' }))
        .toEqual({ url: 'https://checkout.stripe.com/c/pay/cs_test_1' });
      expect(created).toHaveLength(1);
    }
  });

  it('happy path: sessions.create gets the server amount, our metadata, the caller email and the hosting URLs', async () => {
    h.tree.Fantasy.Futsal['16'].Config.Access.AmountDollars = 12.5;
    const r = await call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1', token: { email: 'fan@example.com' } });
    expect(r).toEqual({ url: 'https://checkout.stripe.com/c/pay/cs_test_1' });
    expect(created).toEqual([{
      mode: 'payment',
      line_items: [{
        price_data: { currency: 'usd', unit_amount: 1250, product_data: { name: 'Infinite Fantasy — Futsal Season 16 season pass' } },
        quantity: 1,
      }],
      payment_intent_data: { metadata: { kind: 'fantasyAccess', sport: 'Futsal', season: '16', uid: 'u1' } },
      customer_email: 'fan@example.com',
      success_url: 'https://infinite-sports-app.web.app/fantasy/paid.html',
      cancel_url: 'https://infinite-sports-app.web.app/fantasy/cancelled.html',
    }]);
    // Reads: Config/Access + Access/<uid> only — the caller never names the price.
    expect(h.reads.sort()).toEqual([`${ROOT}/Access/u1`, `${ROOT}/Config/Access`]);
  });

  it('Stripe returning no url -> internal', async () => {
    __setStripeForTests({ checkout: { sessions: { create: async () => ({ url: null }) } } });
    await expect(call(createFantasyCheckoutSession, { sport: 'Futsal', season: '16' }, { uid: 'u1' }))
      .rejects.toMatchObject({ code: 'internal' });
  });
});

describe('sendFantasyAccessTest', () => {
  it('unauthenticated / non-admin -> unauthenticated / permission-denied', async () => {
    await expect(call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'revoked' }))
      .rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'revoked' }, { uid: 'u1' }))
      .rejects.toMatchObject({ code: 'permission-denied' });
    expect(mails).toEqual([]);
  });

  it('admin with bad args -> invalid-argument', async () => {
    for (const data of [{ template: 'revoked' }, { sport: 'Futsal', season: '16' }, { sport: 'Futsal', season: '16', template: 'bogus' }]) {
      await expect(call(sendFantasyAccessTest, data, { uid: 'adm' })).rejects.toMatchObject({ code: 'invalid-argument' });
    }
    expect(mails).toEqual([]);
  });

  it('admin -> the template push (to the caller) + email (to the caller auth email) with sample values', async () => {
    const r = await call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'activatedPaid' }, { uid: 'adm', token: { name: 'Zaya Arami' } });
    expect(r).toEqual({ pushed: true, emailed: true });
    expect(mails).toHaveLength(1);
    expect(mails[0].to).toBe('zaya@example.com');
    expect(mails[0].subject).toBe('[Test] Receipt — Infinite Fantasy Futsal Season 16');
    expect(mails[0].html).toContain('<p>Hi Zaya Arami, your season pass is active.</p>');
    expect(mails[0].html).toContain('Amount: $10.00<br>Method: Venmo');
    expect(h.tree.Support?.MailLog?.['-pushed']?.Ok).toBe(true); // sendSupportMail logged it
  });

  it('no auth email -> emailed false; no device token -> pushed false', async () => {
    h.getUser = async () => ({});
    delete h.tree.Users.adm;
    expect(await call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'claimAdmin' }, { uid: 'adm' }))
      .toEqual({ pushed: false, emailed: false });
    expect(mails).toEqual([]);
  });

  it('an unknown Auth uid (user-not-found) is "no email", other Auth failures too (logged, never thrown)', async () => {
    h.getUser = async () => { throw Object.assign(new Error('nope'), { code: 'auth/user-not-found' }); };
    expect(await call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'revoked' }, { uid: 'adm' }))
      .toEqual({ pushed: true, emailed: false });
    h.getUser = async () => { throw Object.assign(new Error('quota'), { code: 'auth/quota-exceeded' }); };
    expect(await call(sendFantasyAccessTest, { sport: 'Futsal', season: '16', template: 'revoked' }, { uid: 'adm' }))
      .toEqual({ pushed: true, emailed: false });
  });
});

// The trigger wiring (plan A4): the ref patterns are the contract the fan
// app (claims) and the Manager (Access writes) are built against, and the
// two mail-sending triggers must bind the SMTP secrets or email is off.
describe('trigger contract', () => {
  const endpoint = (fn: unknown) => (fn as { __endpoint: any }).__endpoint;
  const secretsOf = (fn: unknown): string[] =>
    ((endpoint(fn).secretEnvironmentVariables ?? []) as Array<{ key: string }>).map((s) => s.key).sort();
  const MAIL = ['SUPPORT_SMTP_HOST', 'SUPPORT_SMTP_PASS', 'SUPPORT_SMTP_PORT', 'SUPPORT_SMTP_USER'];

  it('onFantasyAccessClaimCreated: created on AccessClaims/{uid}/{key}, mail secrets bound', () => {
    const e = endpoint(onFantasyAccessClaimCreated).eventTrigger;
    expect(e.eventType).toBe('google.firebase.database.ref.v1.created');
    expect(e.eventFilterPathPatterns.ref).toBe('Fantasy/{sport}/{season}/AccessClaims/{uid}/{key}');
    expect(secretsOf(onFantasyAccessClaimCreated)).toEqual(MAIL);
  });

  it('onFantasyAccessStatusWritten: written on Access/{uid}/Status, mail secrets bound', () => {
    const e = endpoint(onFantasyAccessStatusWritten).eventTrigger;
    expect(e.eventType).toBe('google.firebase.database.ref.v1.written');
    expect(e.eventFilterPathPatterns.ref).toBe('Fantasy/{sport}/{season}/Access/{uid}/Status');
    expect(secretsOf(onFantasyAccessStatusWritten)).toEqual(MAIL);
  });

  it('onRegistrationPaidGrantFantasy: written on the submission Paid leaf, no secrets', () => {
    const e = endpoint(onRegistrationPaidGrantFantasy).eventTrigger;
    expect(e.eventType).toBe('google.firebase.database.ref.v1.written');
    expect(e.eventFilterPathPatterns.ref).toBe('Registrations/{regId}/Submissions/{uid}/Paid');
    expect(secretsOf(onRegistrationPaidGrantFantasy)).toEqual([]);
  });

  it('the callables bind their secrets (Stripe key / SMTP)', () => {
    expect(secretsOf(createFantasyCheckoutSession)).toEqual(['STRIPE_SECRET_KEY']);
    expect(secretsOf(sendFantasyAccessTest)).toEqual(MAIL);
  });
});
