// stripeWebhook routing (paid access, spec §7 / plan A2). routeStripeEvent
// is driven directly with the in-memory FantasyDb and a markPaid spy: the
// registration path must reach the untouched markPaid with the identical
// meta + cents; the fantasy kind activates (idempotent on replay); a full
// charge.refunded revokes; a partial refund and foreign events only log.
// The onRequest wrapper itself is driven with firebase-admin + stripe
// mocked (user_contact.test.ts style) for the signature paths.

import { beforeEach, describe, expect, it, vi } from 'vitest';
import type Stripe from 'stripe';
import { FakeDb } from './lib/fantasy/test_support';

// Plain functions, not vi.fn: a vi.fn that THROWS from inside a mocked
// module escapes vitest's test boundary (the test fails with the thrown
// value even though the handler catches it) — a plain function does not.
const h = vi.hoisted(() => ({
  constructEvent: ((..._args: unknown[]) => undefined) as (...args: unknown[]) => unknown,
}));

vi.mock('firebase-admin', () => ({
  database: () => ({ ref: () => ({ child: () => ({}) }) }),
}));

vi.mock('stripe', () => ({
  default: class {
    webhooks = { constructEvent: (...args: unknown[]) => h.constructEvent(...args) };
    paymentIntents = { retrieve: async () => ({ metadata: {} }) };
  },
}));

import { routeStripeEvent, stripeWebhook, StripeWebhookDeps } from './stripeWebhook';

const ROOT = 'Fantasy/Futsal/16';
const NOW = Date.UTC(2026, 10, 1, 20);

function world(access?: Record<string, unknown>): Record<string, any> {
  return {
    Fantasy: { Futsal: { '16': { Config: { Access: { Mode: 'pass', AmountDollars: 10 } }, ...(access ? { Access: access } : {}) } } },
  };
}

function deps(db: FakeDb, over: Partial<StripeWebhookDeps> = {}) {
  const markPaid = vi.fn(async () => undefined);
  const paymentIntentMetadata = vi.fn(async () => null);
  return {
    deps: { db, markPaid, paymentIntentMetadata, nowMs: NOW, ...over } as StripeWebhookDeps,
    markPaid, paymentIntentMetadata,
  };
}

function intentEvent(metadata: Record<string, unknown>, extra: Record<string, unknown> = {}): Stripe.Event {
  return {
    id: 'evt_1', type: 'payment_intent.succeeded',
    data: { object: { id: 'pi_1', amount: 1000, amount_received: 1000, metadata, ...extra } },
  } as unknown as Stripe.Event;
}

function refundEvent(charge: Record<string, unknown>): Stripe.Event {
  return {
    id: 'evt_2', type: 'charge.refunded',
    data: { object: { id: 'ch_1', payment_intent: 'pi_1', refunded: true, metadata: {}, ...charge } },
  } as unknown as Stripe.Event;
}

const REG_META = { regId: 'Futsal-17', uid: 'u1', league: 'Futsal', season: '17' };
const FAN_META = { kind: 'fantasyAccess', sport: 'Futsal', season: '16', uid: 'u1' };

describe('routeStripeEvent — payment_intent.succeeded', () => {
  it('registration metadata reaches markPaid with the identical meta + received cents', async () => {
    const db = new FakeDb(world());
    const d = deps(db);
    const r = await routeStripeEvent(intentEvent(REG_META, { amount_received: 1250 }), d.deps);
    expect(r).toEqual({ status: 200, body: 'ok' });
    expect(d.markPaid).toHaveBeenCalledTimes(1);
    expect(d.markPaid).toHaveBeenCalledWith({ regId: 'Futsal-17', uid: 'u1', league: 'Futsal', season: '17' }, 1250);
    expect(db.writes).toEqual([]); // nothing fantasy touched
  });

  it('amount_received 0 falls back to amount (unchanged)', async () => {
    const d = deps(new FakeDb(world()));
    await routeStripeEvent(intentEvent(REG_META, { amount_received: 0, amount: 777 }), d.deps);
    expect(d.markPaid).toHaveBeenCalledWith(expect.anything(), 777);
  });

  it('markPaid throwing -> 500 so Stripe retries (unchanged)', async () => {
    const d = deps(new FakeDb(world()), { markPaid: async () => { throw new Error('db down'); } });
    expect(await routeStripeEvent(intentEvent(REG_META), d.deps)).toEqual({ status: 500, body: 'internal error' });
  });

  it('malformed metadata -> 200 "malformed metadata, ignored", nothing called', async () => {
    const db = new FakeDb(world());
    const d = deps(db);
    for (const meta of [{}, { regId: 'r' }, { kind: 'fantasyAccess', sport: 'Futsal' }, { kind: 'other', ...REG_META }]) {
      expect(await routeStripeEvent(intentEvent(meta), d.deps)).toEqual({ status: 200, body: 'malformed metadata, ignored' });
    }
    expect(d.markPaid).not.toHaveBeenCalled();
    expect(db.writes).toEqual([]);
  });

  it('fantasy kind activates Access/<uid> via card with the PaymentIntent, markPaid untouched', async () => {
    const db = new FakeDb(world());
    const d = deps(db);
    expect(await routeStripeEvent(intentEvent(FAN_META), d.deps)).toEqual({ status: 200, body: 'ok' });
    expect(d.markPaid).not.toHaveBeenCalled();
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: NOW, By: 'stripe', StripePaymentIntent: 'pi_1',
    });
  });

  it('a replayed fantasy event is idempotent: one write in total', async () => {
    const db = new FakeDb(world());
    const d = deps(db);
    await routeStripeEvent(intentEvent(FAN_META), d.deps);
    const writesAfterFirst = db.writes.length;
    expect(await routeStripeEvent(intentEvent(FAN_META), d.deps)).toEqual({ status: 200, body: 'ok' });
    expect(db.writes.length).toBe(writesAfterFirst);
    expect(writesAfterFirst).toBe(1);
  });

  it('fantasy activation throwing -> 500', async () => {
    const db = new FakeDb(world());
    db.transaction = async () => { throw new Error('tx down'); };
    const d = deps(db);
    expect(await routeStripeEvent(intentEvent(FAN_META), d.deps)).toEqual({ status: 500, body: 'internal error' });
  });
});

describe('routeStripeEvent — charge.refunded', () => {
  const activeCard = { u1: { Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe', StripePaymentIntent: 'pi_1' } };

  it('full refund of a fantasy charge revokes the access', async () => {
    const db = new FakeDb(world(activeCard));
    const d = deps(db);
    expect(await routeStripeEvent(refundEvent({ metadata: FAN_META }), d.deps)).toEqual({ status: 200, body: 'ok' });
    const rec = await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>;
    expect(rec['Status']).toBe('revoked');
    expect(rec['RefundedAt']).toBe(NOW);
    expect(rec['RevokedBy']).toBe('stripe');
    expect(d.paymentIntentMetadata).not.toHaveBeenCalled(); // metadata was on the charge
  });

  it('partial refund (refunded:false) logs only — access stays active', async () => {
    const db = new FakeDb(world(activeCard));
    const d = deps(db);
    expect(await routeStripeEvent(refundEvent({ metadata: FAN_META, refunded: false }), d.deps))
      .toEqual({ status: 200, body: 'partial refund, ignored' });
    expect(db.writes).toEqual([]);
  });

  it('a charge without our metadata is resolved through its PaymentIntent', async () => {
    const db = new FakeDb(world(activeCard));
    const d = deps(db, { paymentIntentMetadata: vi.fn(async () => FAN_META) });
    expect(await routeStripeEvent(refundEvent({ metadata: {} }), d.deps)).toEqual({ status: 200, body: 'ok' });
    expect(d.deps.paymentIntentMetadata).toHaveBeenCalledWith('pi_1');
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Status']).toBe('revoked');
  });

  it('registration refunds and foreign charges are ignored (200), even when the lookup fails', async () => {
    const db = new FakeDb(world(activeCard));
    for (const over of [
      {}, // lookup returns null
      { paymentIntentMetadata: vi.fn(async () => REG_META) },
      { paymentIntentMetadata: vi.fn(async () => { throw new Error('stripe down'); }) },
    ]) {
      const d = deps(db, over as Partial<StripeWebhookDeps>);
      expect(await routeStripeEvent(refundEvent({ metadata: REG_META }), d.deps)).toEqual({ status: 200, body: 'ignored' });
    }
    expect(db.writes).toEqual([]);
  });

  it('a refund for a record that is not active / another payment -> 200, no write', async () => {
    const db = new FakeDb(world({ u1: { Status: 'active', Via: 'venmo', AmountCents: 1000, PaidAt: 5, By: 'adm' } }));
    const d = deps(db);
    expect(await routeStripeEvent(refundEvent({ metadata: FAN_META }), d.deps)).toEqual({ status: 200, body: 'ok' });
    expect(db.writes).toEqual([]);
  });

  it('an expanded payment_intent object is read by id', async () => {
    const db = new FakeDb(world(activeCard));
    const d = deps(db);
    await routeStripeEvent(refundEvent({ metadata: FAN_META, payment_intent: { id: 'pi_1' } }), d.deps);
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Status']).toBe('revoked');
  });
});

describe('routeStripeEvent — other events', () => {
  it('unhandled types are ignored as before', async () => {
    const d = deps(new FakeDb(world()));
    const ev = { id: 'e', type: 'customer.created', data: { object: {} } } as unknown as Stripe.Event;
    expect(await routeStripeEvent(ev, d.deps)).toEqual({ status: 200, body: 'ignored' });
    expect(d.markPaid).not.toHaveBeenCalled();
  });
});

describe('stripeWebhook onRequest wrapper', () => {
  interface Res { status: number; body: string }
  function run(headers: Record<string, unknown>): Promise<Res> {
    return new Promise((resolve) => {
      const res = {
        status(code: number) { return { send: (body: string) => resolve({ status: code, body }) }; },
        on: () => undefined,
      };
      void stripeWebhook({ headers, rawBody: Buffer.from('{}') } as never, res as never);
    });
  }

  beforeEach(() => { h.constructEvent = () => undefined; });

  it('missing signature -> 400', async () => {
    expect(await run({})).toEqual({ status: 400, body: 'Missing signature' });
  });

  it('bad signature -> 400', async () => {
    h.constructEvent = () => { throw new Error('bad sig'); };
    expect(await run({ 'stripe-signature': 'sig' })).toEqual({ status: 400, body: 'Invalid signature' });
  });

  it('a verified unhandled event routes to 200 ignored', async () => {
    h.constructEvent = () => ({ id: 'e', type: 'customer.created', data: { object: {} } });
    expect(await run({ 'stripe-signature': 'sig' })).toEqual({ status: 200, body: 'ignored' });
  });
});
