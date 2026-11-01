// Paid access orchestration (spec §7) against the in-memory FantasyDb +
// capturing pusher/mailer/auth: card activation + refund (the webhook's pure
// halves), the claim trigger, the status trigger, the registration Paid
// grant and the admin "Send me a test". Plan Track A2/A4 test lists.

import { beforeEach, describe, expect, it } from 'vitest';
import {
  AccessDeps, AccessMailer, activateFantasyAccess, grantFantasyAccessForRegistration,
  handleAccessClaimCreated, handleAccessStatusWritten, revokeFantasyAccessOnRefund,
  sendAccessTestMessage, TEMPLATE_DEFAULTS,
} from './access';
import type { FantasyLogger } from './orchestration';
import { FakeDb, FakePusher } from './test_support';

const ROOT = 'Fantasy/Futsal/16';
const NOW = Date.UTC(2026, 10, 1, 20); // Nov 1 2026 12:00 PST

interface Mail { to: string; subject: string; html: string }

class FakeMailer implements AccessMailer {
  mails: Mail[] = [];
  async send(to: string, subject: string, html: string): Promise<void> {
    this.mails.push({ to, subject, html });
  }
}

class CapturingLog implements FantasyLogger {
  lines: Array<{ level: 'info' | 'warn'; message: string; context?: Record<string, unknown> }> = [];
  info(message: string, context?: Record<string, unknown>): void {
    this.lines.push({ level: 'info', message, context });
  }
  warn(message: string, context?: Record<string, unknown>): void {
    this.lines.push({ level: 'warn', message, context });
  }
  has(fragment: string): boolean {
    return this.lines.some((l) => l.message.includes(fragment));
  }
}

function world(opts: {
  access?: Record<string, unknown>;
  claims?: Record<string, unknown>;
  config?: Record<string, unknown>;
  templates?: Record<string, unknown>;
  admins?: Record<string, unknown>;
  managers?: Record<string, unknown>;
  profiles?: Record<string, unknown>;
} = {}): Record<string, any> {
  return {
    Admins: opts.admins ?? { adm1: true, adm2: true, notAdmin: false },
    PublicProfiles: opts.profiles ?? { u1: { 'First Name': 'Zed', 'Last Name': 'Fan' } },
    Fantasy: {
      ...(opts.templates ? { Templates: { Access: opts.templates } } : {}),
      Futsal: {
        '16': {
          Config: { lockHour: 15, Access: opts.config ?? { Mode: 'pass', AmountDollars: 10 } },
          ...(opts.managers ? { Managers: opts.managers } : {}),
          ...(opts.access ? { Access: opts.access } : {}),
          ...(opts.claims ? { AccessClaims: opts.claims } : {}),
        },
      },
    },
  };
}

let emails: Record<string, string | null>;
function deps(db: FakeDb, over: Partial<AccessDeps> = {}): AccessDeps & {
  pusher: FakePusher; mailer: FakeMailer; log: CapturingLog;
} {
  const pusher = new FakePusher();
  const mailer = new FakeMailer();
  const log = new CapturingLog();
  return {
    db, pusher, mailer, log, nowMs: NOW,
    auth: { emailOf: async (uid) => emails[uid] ?? null },
    ...over,
  } as never;
}

beforeEach(() => {
  emails = { u1: 'zed@example.com', adm1: 'zaya@example.com' };
});

// ── Card activation (webhook) ───────────────────────────────────────────────

describe('activateFantasyAccess', () => {
  it('writes the card activation and supersedes open claims', async () => {
    const db = new FakeDb(world({
      claims: { u1: { k1: { Method: 'venmo', AmountDollars: 10, At: 1 }, k0: { Method: 'zelle', AmountDollars: 10, At: 0, Resolved: 'rejected' } } },
      access: { u1: { Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', Notified: { x: true } } },
    }));
    const log = new CapturingLog();
    const r = await activateFantasyAccess(db, {
      sport: 'Futsal', season: '16', uid: 'u1', amountCents: 1000, paymentIntent: 'pi_1',
      nowMs: NOW, log,
    });
    expect(r).toEqual({ activated: true });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: NOW, By: 'stripe',
      StripePaymentIntent: 'pi_1', Notified: { x: true },
    });
    const k1 = await db.read(`${ROOT}/AccessClaims/u1/k1`) as Record<string, unknown>;
    expect(k1['Resolved']).toBe('superseded');
    expect(k1['ResolvedBy']).toBe('stripe');
    expect(k1['ResolvedAt']).toBe(NOW);
    const k0 = await db.read(`${ROOT}/AccessClaims/u1/k0`) as Record<string, unknown>;
    expect(k0['Resolved']).toBe('rejected'); // already resolved: untouched
    expect(log.has('activated')).toBe(true);
  });

  it('a replay on an active record writes nothing and logs', async () => {
    const db = new FakeDb(world({
      access: { u1: { Status: 'active', Via: 'venmo', AmountCents: 1000, PaidAt: 5, By: 'adm1' } },
    }));
    const log = new CapturingLog();
    const r = await activateFantasyAccess(db, {
      sport: 'Futsal', season: '16', uid: 'u1', amountCents: 1000, paymentIntent: 'pi_1',
      nowMs: NOW, log,
    });
    expect(r).toEqual({ activated: false });
    expect(db.writes).toEqual([]);
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Via']).toBe('venmo');
    expect(log.has('already active')).toBe(true);
  });

  it('a revoked record is re-activated by a new card payment', async () => {
    const db = new FakeDb(world({
      access: { u1: { Status: 'revoked', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe', StripePaymentIntent: 'pi_old', RefundedAt: 6, RevokedBy: 'stripe', Notified: { active_5: true, revoked_6: true } } },
    }));
    await activateFantasyAccess(db, {
      sport: 'Futsal', season: '16', uid: 'u1', amountCents: 1000, paymentIntent: 'pi_new', nowMs: NOW,
    });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: NOW, By: 'stripe',
      StripePaymentIntent: 'pi_new', Notified: { active_5: true, revoked_6: true },
    });
  });
});

describe('revokeFantasyAccessOnRefund', () => {
  const active = (extra: Record<string, unknown> = {}) => ({
    u1: { Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe', StripePaymentIntent: 'pi_1', ...extra },
  });

  it('revokes the record the refunded payment activated', async () => {
    const db = new FakeDb(world({ access: active() }));
    const log = new CapturingLog();
    const r = await revokeFantasyAccessOnRefund(db, {
      sport: 'Futsal', season: '16', uid: 'u1', paymentIntent: 'pi_1', nowMs: NOW, log,
    });
    expect(r).toEqual({ revoked: true });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'revoked', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe',
      StripePaymentIntent: 'pi_1', RefundedAt: NOW, RevokedBy: 'stripe',
    });
    expect(log.has('revoked')).toBe(true);
  });

  it('a refund of an OLD payment never revokes a pass paid for since (venmo / other pi)', async () => {
    for (const rec of [
      { Status: 'active', Via: 'venmo', AmountCents: 1000, PaidAt: 9, By: 'adm1' },
      { Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 9, By: 'stripe', StripePaymentIntent: 'pi_2' },
      { Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 9, By: 'adm1' },
    ]) {
      const db = new FakeDb(world({ access: { u1: rec } }));
      const log = new CapturingLog();
      const r = await revokeFantasyAccessOnRefund(db, {
        sport: 'Futsal', season: '16', uid: 'u1', paymentIntent: 'pi_1', nowMs: NOW, log,
      });
      expect(r).toEqual({ revoked: false });
      expect(db.writes).toEqual([]);
      expect(log.has('does not match')).toBe(true);
    }
  });

  it('not active (pending / revoked / absent) -> no write, logged', async () => {
    for (const access of [
      { u1: { Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system' } },
      { u1: { Status: 'revoked', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe', StripePaymentIntent: 'pi_1', RefundedAt: 6 } },
      undefined,
    ]) {
      const db = new FakeDb(world({ access }));
      const log = new CapturingLog();
      const r = await revokeFantasyAccessOnRefund(db, {
        sport: 'Futsal', season: '16', uid: 'u1', paymentIntent: 'pi_1', nowMs: NOW, log,
      });
      expect(r).toEqual({ revoked: false });
      expect(db.writes).toEqual([]);
      expect(log.has('not active')).toBe(true);
    }
  });

  it('no PaymentIntent id from Stripe: revokes a card record with none on file only', async () => {
    const noPi = new FakeDb(world({ access: { u1: { Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe' } } }));
    expect(await revokeFantasyAccessOnRefund(noPi, {
      sport: 'Futsal', season: '16', uid: 'u1', paymentIntent: null, nowMs: NOW,
    })).toEqual({ revoked: true });
    const withPi = new FakeDb(world({ access: active() }));
    expect(await revokeFantasyAccessOnRefund(withPi, {
      sport: 'Futsal', season: '16', uid: 'u1', paymentIntent: null, nowMs: NOW,
    })).toEqual({ revoked: false });
  });
});

// ── Claim created ───────────────────────────────────────────────────────────

describe('handleAccessClaimCreated', () => {
  const claim = () => ({ Method: 'venmo', AmountDollars: 10, Note: 'paid!', At: 1 });

  it('pending written, one push per admin + admin email + fan push + fan email, once', async () => {
    const db = new FakeDb(world({ claims: { u1: { k1: claim() } }, managers: { u1: { TeamName: 'Zed United' } } }));
    const d = deps(db);
    const r = await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' });
    expect(r).toEqual({ pending: true, adminPushes: 2, adminEmailed: true, fanEmailed: true });

    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', ClaimedAt: NOW,
    });
    expect(await db.read(`${ROOT}/AccessClaims/u1/k1/Notified`)).toBe(true);

    // (a) admins pushed — exactly the Admins === true uids, sorted.
    expect(d.pusher.sends).toHaveLength(2);
    const adminPush = d.pusher.sends[0];
    expect(adminPush.map((m) => m.uid)).toEqual(['adm1', 'adm2']);
    expect(adminPush[0].title).toBe('Fantasy payment to confirm');
    expect(adminPush[0].body).toBe('Zed United says they paid $10.00 by Venmo for Futsal Season 16.');
    expect(adminPush[0].data).toEqual({ type: 'fantasyAccess', sport: 'Futsal', season: '16' });
    // (c) the fan pushed.
    expect(d.pusher.sends[1]).toEqual([{
      uid: 'u1', title: 'Payment noted',
      body: "Thanks Zed United — we'll confirm your Venmo payment shortly.",
      data: { type: 'fantasyAccess', sport: 'Futsal', season: '16' },
    }]);
    // (b) admin email to the default inbox, (c) fan email.
    expect(d.mailer.mails).toHaveLength(2);
    expect(d.mailer.mails[0].to).toBe('support@infinitesports.org');
    expect(d.mailer.mails[0].subject).toBe('Fantasy payment to confirm — Zed United');
    expect(d.mailer.mails[0].html).toContain('<p>Zed United says they paid $10.00 by Venmo for Futsal Season 16.</p>');
    expect(d.mailer.mails[0].html).toContain('Open the Manager');
    expect(d.mailer.mails[1].to).toBe('zed@example.com');
    expect(d.mailer.mails[1].subject).toBe('Infinite Fantasy — payment noted');
    expect(d.mailer.mails[1].html).toContain('you paid $10.00 by Venmo for Futsal Season 16');

    // Once: a re-fire sends nothing more.
    const again = deps(db);
    expect(await handleAccessClaimCreated(again, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' })).toBeNull();
    expect(again.pusher.sends).toEqual([]);
    expect(again.mailer.mails).toEqual([]);
    expect(again.log.has('already notified')).toBe(true);
  });

  it('no team name: the public profile name for admins, first name for the fan; no email -> push only', async () => {
    emails = {};
    const db = new FakeDb(world({ claims: { u1: { k1: { ...claim(), Method: 'zelle', AmountDollars: 12.5 } } } }));
    const d = deps(db);
    const r = await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' });
    expect(r).toEqual({ pending: true, adminPushes: 2, adminEmailed: true, fanEmailed: false });
    expect(d.pusher.sends[0][0].body).toBe('Zed Fan says they paid $12.50 by Zelle for Futsal Season 16.');
    expect(d.pusher.sends[1][0].body).toBe("Thanks Zed — we'll confirm your Zelle payment shortly.");
    expect(d.mailer.mails).toHaveLength(1); // admin only
    expect(d.log.has('no email on file')).toBe(true);
  });

  it('unknown fan: "a manager"', async () => {
    const db = new FakeDb(world({ claims: { u9: { k1: claim() } }, profiles: {} }));
    const d = deps(db);
    await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u9', key: 'k1' });
    expect(d.pusher.sends[0][0].body).toBe('a manager says they paid $10.00 by Venmo for Futsal Season 16.');
  });

  it('owner templates + AdminEmail override the defaults; blank fields fall back (warned)', async () => {
    const db = new FakeDb(world({
      claims: { u1: { k1: claim() } },
      templates: {
        AdminEmail: 'zaya@infinitesports.org',
        claimAdmin: { PushTitle: 'Cash!', PushBody: '', EmailSubject: '{name} paid {amount}', EmailBody: 'Check {method}.' },
      },
    }));
    const d = deps(db);
    await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' });
    expect(d.pusher.sends[0][0].title).toBe('Cash!');
    expect(d.pusher.sends[0][0].body).toBe('Zed Fan says they paid $10.00 by Venmo for Futsal Season 16.');
    expect(d.mailer.mails[0].to).toBe('zaya@infinitesports.org');
    expect(d.mailer.mails[0].subject).toBe('Zed Fan paid $10.00');
    expect(d.mailer.mails[0].html).toContain('<p>Check Venmo.</p>');
    const warn = d.log.lines.find((l) => l.level === 'warn' && l.message.includes('blank'));
    expect(warn?.context).toEqual({ template: 'claimAdmin', fields: ['PushBody'] });
  });

  it('a second claim replaces the pending one and supersedes the first', async () => {
    const db = new FakeDb(world({
      claims: { u1: { k1: { ...claim(), Notified: true }, k2: { ...claim(), Method: 'zelle' } } },
      access: { u1: { Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', ClaimedAt: 1 } },
    }));
    const d = deps(db);
    const r = await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k2' });
    expect(r?.pending).toBe(true);
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Via']).toBe('zelle');
    expect((await db.read(`${ROOT}/AccessClaims/u1/k1`) as Record<string, unknown>)['Resolved']).toBe('superseded');
    expect((await db.read(`${ROOT}/AccessClaims/u1/k2`) as Record<string, unknown>)['Resolved']).toBeUndefined();
    expect(d.pusher.sends).toHaveLength(2); // admins + fan again for the new claim
  });

  it('a stray claim on an ACTIVE record: no pending, no mails, claim superseded, logged', async () => {
    const db = new FakeDb(world({
      claims: { u1: { k1: claim() } },
      access: { u1: { Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 5, By: 'adm1' } },
    }));
    const d = deps(db);
    expect(await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' })).toBeNull();
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Status']).toBe('active');
    expect((await db.read(`${ROOT}/AccessClaims/u1/k1`) as Record<string, unknown>)['Resolved']).toBe('superseded');
    expect(d.pusher.sends).toEqual([]);
    expect(d.mailer.mails).toEqual([]);
    expect(d.log.has('claim on an active record')).toBe(true);
  });

  it('a revoked record goes back to pending on a new claim (Notified kept)', async () => {
    const db = new FakeDb(world({
      claims: { u1: { k1: claim() } },
      access: { u1: { Status: 'revoked', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe', RefundedAt: 6, Notified: { active_5: true } } },
    }));
    const d = deps(db);
    await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', ClaimedAt: NOW,
      Notified: { active_5: true },
    });
  });

  it('a bad claim (card / missing method / gone) is ignored and warned', async () => {
    for (const claims of [
      { u1: { k1: { Method: 'card', AmountDollars: 10, At: 1 } } },
      { u1: { k1: { AmountDollars: 10, At: 1 } } },
      undefined,
    ]) {
      const db = new FakeDb(world({ claims }));
      const d = deps(db);
      expect(await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' })).toBeNull();
      expect(db.writes).toEqual([]);
      expect(d.pusher.sends).toEqual([]);
      expect(d.log.lines.some((l) => l.level === 'warn')).toBe(true);
    }
  });

  it('an already-resolved claim (re-fired create) is ignored', async () => {
    const db = new FakeDb(world({ claims: { u1: { k1: { ...claim(), Resolved: 'approved' } } } }));
    const d = deps(db);
    expect(await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' })).toBeNull();
    expect(db.writes).toEqual([]);
  });

  it('no admins: no admin push, the admin email still goes', async () => {
    const db = new FakeDb(world({ claims: { u1: { k1: claim() } }, admins: {} }));
    const d = deps(db);
    const r = await handleAccessClaimCreated(d, { sport: 'Futsal', season: '16', uid: 'u1', key: 'k1' });
    expect(r?.adminPushes).toBe(0);
    expect(d.mailer.mails[0].to).toBe('support@infinitesports.org');
  });
});

// ── Status written ──────────────────────────────────────────────────────────

describe('handleAccessStatusWritten', () => {
  const paid = () => ({ Status: 'active', Via: 'venmo', AmountCents: 1000, PaidAt: NOW, By: 'adm1' });

  it('active via venmo -> activatedPaid push + receipt email, once per PaidAt', async () => {
    const db = new FakeDb(world({ access: { u1: paid() }, managers: { u1: { TeamName: 'Zed United' } } }));
    const d = deps(db);
    const r = await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: 'pending', after: 'active' });
    expect(r).toEqual({ template: 'activatedPaid', pushed: 1, emailed: true });
    expect(await db.read(`${ROOT}/Access/u1/Notified/active_${NOW}`)).toBe(true);
    expect(d.pusher.sends).toEqual([[{
      uid: 'u1', title: "You're in!",
      body: 'Your Futsal Season 16 season pass is active. Build your team!',
      data: { type: 'fantasyAccess', sport: 'Futsal', season: '16' },
    }]]);
    expect(d.mailer.mails).toHaveLength(1);
    expect(d.mailer.mails[0].to).toBe('zed@example.com');
    expect(d.mailer.mails[0].subject).toBe('Receipt — Infinite Fantasy Futsal Season 16');
    expect(d.mailer.mails[0].html).toContain('<p>Hi Zed United, your season pass is active.</p>');
    expect(d.mailer.mails[0].html).toContain(
      '<p>Amount: $10.00<br>Method: Venmo<br>Date: Nov 1, 2026<br>Season: Futsal Season 16</p>');

    const again = deps(db);
    expect(await handleAccessStatusWritten(again, { sport: 'Futsal', season: '16', uid: 'u1', before: 'pending', after: 'active' })).toBeNull();
    expect(again.pusher.sends).toEqual([]);
    expect(again.mailer.mails).toEqual([]);
  });

  it.each(['granted', 'player', 'grandfathered'] as const)(
    'active via %s -> activatedGranted (no amount, no grant wording)', async (via) => {
      const db = new FakeDb(world({ access: { u1: { ...paid(), Via: via, AmountCents: 0 } } }));
      const d = deps(db);
      const r = await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: null, after: 'active' });
      expect(r?.template).toBe('activatedGranted');
      expect(d.pusher.sends[0][0].body).toBe('Your Futsal Season 16 fantasy access is active. Build your team!');
      expect(d.mailer.mails[0].subject).toBe("You're in — Infinite Fantasy Futsal Season 16");
      expect(d.mailer.mails[0].html).toContain('<p>Hi Zed, your access to Infinite Fantasy for Futsal Season 16 is active.');
      const all = `${d.pusher.sends[0][0].title} ${d.pusher.sends[0][0].body} ${d.mailer.mails[0].subject} ${d.mailer.mails[0].html}`.toLowerCase();
      expect(all).not.toMatch(/grant|free|admin|\$0/);
    });

  it('card activation (webhook) -> receipt with the card method', async () => {
    const db = new FakeDb(world({ access: { u1: { ...paid(), Via: 'card', By: 'stripe', StripePaymentIntent: 'pi_1' } } }));
    const d = deps(db);
    await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: null, after: 'active' });
    expect(d.mailer.mails[0].html).toContain('Method: card');
  });

  it('revoked -> revoked template once per RefundedAt; a re-activation notifies again', async () => {
    const db = new FakeDb(world({ access: { u1: { ...paid(), Status: 'revoked', RefundedAt: NOW + 5, RevokedBy: 'stripe', Notified: { [`active_${NOW}`]: true } } } }));
    const d = deps(db);
    const r = await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: 'active', after: 'revoked' });
    expect(r).toEqual({ template: 'revoked', pushed: 1, emailed: true });
    expect(d.pusher.sends[0][0].title).toBe('Fantasy access removed');
    expect(d.mailer.mails[0].subject).toBe('Infinite Fantasy — access removed');
    expect(d.mailer.mails[0].html).toContain('was removed on Nov 1, 2026');
    expect(await db.read(`${ROOT}/Access/u1/Notified`)).toEqual({ [`active_${NOW}`]: true, [`revoked_${NOW + 5}`]: true });

    // Paid again later: a new PaidAt is a new key.
    await db.write(`${ROOT}/Access/u1/Status`, 'active');
    await db.write(`${ROOT}/Access/u1/PaidAt`, NOW + 10);
    const d2 = deps(db);
    expect((await handleAccessStatusWritten(d2, { sport: 'Futsal', season: '16', uid: 'u1', before: 'revoked', after: 'active' }))?.pushed).toBe(1);
    expect(await db.read(`${ROOT}/Access/u1/Notified/active_${NOW + 10}`)).toBe(true);
  });

  it('no email on file -> push only, logged', async () => {
    emails = {};
    const db = new FakeDb(world({ access: { u1: paid() } }));
    const d = deps(db);
    expect(await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: null, after: 'active' }))
      .toEqual({ template: 'activatedPaid', pushed: 1, emailed: false });
    expect(d.mailer.mails).toEqual([]);
    expect(d.log.has('no email on file')).toBe(true);
  });

  it('pending, unchanged, deleted, or a record that moved on: nothing', async () => {
    const db = new FakeDb(world({ access: { u1: paid() } }));
    for (const [before, after] of [
      [null, 'pending'], ['active', 'active'], ['active', null], ['active', 'bogus'],
    ] as const) {
      const d = deps(db);
      expect(await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before, after })).toBeNull();
      expect(d.pusher.sends).toEqual([]);
    }
    // The event says revoked but the record is active again already.
    const d = deps(db);
    expect(await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: 'active', after: 'revoked' })).toBeNull();
    expect(d.log.has('changed again')).toBe(true);
    expect(db.writes).toEqual([]);
  });

  it('a record without PaidAt notifies once ever and warns', async () => {
    const db = new FakeDb(world({ access: { u1: { Status: 'active', Via: 'granted', AmountCents: 0, By: 'adm1' } } }));
    const d = deps(db);
    expect((await handleAccessStatusWritten(d, { sport: 'Futsal', season: '16', uid: 'u1', before: null, after: 'active' }))?.pushed).toBe(1);
    expect(d.log.lines.some((l) => l.level === 'warn' && l.message.includes('no PaidAt'))).toBe(true);
    expect(await db.read(`${ROOT}/Access/u1/Notified/active_unknown`)).toBe(true);
    const d2 = deps(db);
    expect(await handleAccessStatusWritten(d2, { sport: 'Futsal', season: '16', uid: 'u1', before: null, after: 'active' })).toBeNull();
  });
});

// ── Registration Paid grant ─────────────────────────────────────────────────

describe('grantFantasyAccessForRegistration', () => {
  function regWorld(access: Record<string, unknown>, config?: Record<string, unknown>) {
    const w = world({ config: config ?? { Mode: 'pass', AmountDollars: 10, RegisteredPlayersFree: true } });
    w['Registrations'] = {
      'Futsal-16': { Config: { TargetType: 'league', Sport: 'Futsal', Season: '16', Methods: { venmo: true } } },
      'Cup-1': { Config: { TargetType: 'tournament', TournamentId: 'cup1', TournamentName: 'Winter Cup' } },
    };
    return w;
  }

  it('happy path: pass mode + registered players free + not active -> Via player', async () => {
    const db = new FakeDb(regWorld({}));
    const log = new CapturingLog();
    expect(await grantFantasyAccessForRegistration(db, { regId: 'Futsal-16', uid: 'u1', paid: true, nowMs: NOW, log }))
      .toEqual({ granted: true });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'active', Via: 'player', AmountCents: 0, PaidAt: NOW, By: 'system',
    });
    expect(log.has('granted')).toBe(true);
  });

  it('a pending claim is superseded by the grant', async () => {
    const w = regWorld({});
    w.Fantasy.Futsal['16'].Access = { u1: { Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', Notified: { n: true } } };
    w.Fantasy.Futsal['16'].AccessClaims = { u1: { k1: { Method: 'venmo', AmountDollars: 10, At: 1 } } };
    const db = new FakeDb(w);
    await grantFantasyAccessForRegistration(db, { regId: 'Futsal-16', uid: 'u1', paid: true, nowMs: NOW });
    expect(await db.read(`${ROOT}/Access/u1`)).toEqual({
      Status: 'active', Via: 'player', AmountCents: 0, PaidAt: NOW, By: 'system', Notified: { n: true },
    });
    expect((await db.read(`${ROOT}/AccessClaims/u1/k1`) as Record<string, unknown>)['Resolved']).toBe('superseded');
  });

  it.each([
    ['toggle off', { Mode: 'pass', AmountDollars: 10, RegisteredPlayersFree: false }, 'do not play free'],
    ['free mode', { Mode: 'free', RegisteredPlayersFree: true }, 'not in pass mode'],
    ['no Access config', undefined, 'not in pass mode'],
  ] as const)('%s -> nothing, logged', async (_label, config, fragment) => {
    const w = regWorld({}, config as never);
    if (config === undefined) delete w.Fantasy.Futsal['16'].Config.Access;
    const db = new FakeDb(w);
    const log = new CapturingLog();
    expect(await grantFantasyAccessForRegistration(db, { regId: 'Futsal-16', uid: 'u1', paid: true, nowMs: NOW, log }))
      .toEqual({ granted: false });
    expect(db.writes).toEqual([]);
    expect(log.has(fragment)).toBe(true);
  });

  it('already active -> nothing (a paid card pass is not downgraded to player)', async () => {
    const w = regWorld({});
    w.Fantasy.Futsal['16'].Access = { u1: { Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe' } };
    const db = new FakeDb(w);
    const log = new CapturingLog();
    expect(await grantFantasyAccessForRegistration(db, { regId: 'Futsal-16', uid: 'u1', paid: true, nowMs: NOW, log }))
      .toEqual({ granted: false });
    expect(db.writes).toEqual([]);
    expect(log.has('already active')).toBe(true);
  });

  it('an unpaid flip or a non-true value never touches access', async () => {
    const w = regWorld({});
    w.Fantasy.Futsal['16'].Access = { u1: { Status: 'active', Via: 'player', AmountCents: 0, PaidAt: 5, By: 'system' } };
    const db = new FakeDb(w);
    for (const paid of [false, null, 'true', 1]) {
      expect(await grantFantasyAccessForRegistration(db, { regId: 'Futsal-16', uid: 'u1', paid, nowMs: NOW }))
        .toEqual({ granted: false });
    }
    expect(db.writes).toEqual([]);
    expect((await db.read(`${ROOT}/Access/u1`) as Record<string, unknown>)['Status']).toBe('active');
  });

  it('a tournament registration targets Fantasy/<TournamentName>/<TournamentId>', async () => {
    const w = regWorld({});
    w.Fantasy['Winter Cup'] = { cup1: { Config: { Access: { Mode: 'pass', AmountDollars: 5, RegisteredPlayersFree: true } } } };
    const db = new FakeDb(w);
    expect(await grantFantasyAccessForRegistration(db, { regId: 'Cup-1', uid: 'u1', paid: true, nowMs: NOW }))
      .toEqual({ granted: true });
    expect((await db.read('Fantasy/Winter Cup/cup1/Access/u1') as Record<string, unknown>)['Via']).toBe('player');
  });

  it('unknown registration -> nothing, logged', async () => {
    const db = new FakeDb(regWorld({}));
    const log = new CapturingLog();
    expect(await grantFantasyAccessForRegistration(db, { regId: 'nope', uid: 'u1', paid: true, nowMs: NOW, log }))
      .toEqual({ granted: false });
    expect(db.writes).toEqual([]);
    expect(log.has('config unreadable')).toBe(true);
  });
});

// ── Send me a test ──────────────────────────────────────────────────────────

describe('sendAccessTestMessage', () => {
  it('fills the template with sample values and sends to the caller', async () => {
    const db = new FakeDb(world({ config: { Mode: 'pass', AmountDollars: 12.5 } }));
    const d = deps(db);
    const r = await sendAccessTestMessage(d, {
      sport: 'Futsal', season: '16', uid: 'adm1', template: 'activatedPaid', displayName: 'Zaya A',
    });
    expect(r).toEqual({ pushed: true, emailed: true });
    expect(d.pusher.sends).toEqual([[{
      uid: 'adm1', title: "You're in!",
      body: 'Your Futsal Season 16 season pass is active. Build your team!',
      data: { type: 'fantasyAccess', sport: 'Futsal', season: '16' },
    }]]);
    expect(d.mailer.mails[0].to).toBe('zaya@example.com');
    expect(d.mailer.mails[0].subject).toBe('[Test] Receipt — Infinite Fantasy Futsal Season 16');
    expect(d.mailer.mails[0].html).toContain('<p>Hi Zaya A, your season pass is active.</p>');
    expect(d.mailer.mails[0].html).toContain('Amount: $12.50<br>Method: Venmo<br>Date: Nov 1, 2026');
  });

  it('blank display name reads "Zaya"; no email -> emailed false; no device -> pushed false', async () => {
    emails = {};
    const db = new FakeDb(world());
    const pusher = new FakePusher();
    pusher.sendToUsers = async () => 0;
    const d = deps(db, { pusher });
    const r = await sendAccessTestMessage(d, {
      sport: 'Futsal', season: '16', uid: 'adm1', template: 'claimAdmin', displayName: '  ',
    });
    expect(r).toEqual({ pushed: false, emailed: false });
    expect(d.mailer.mails).toEqual([]);
  });

  it('every template key renders without leaking a raw placeholder', async () => {
    const db = new FakeDb(world());
    for (const key of Object.keys(TEMPLATE_DEFAULTS) as Array<keyof typeof TEMPLATE_DEFAULTS>) {
      const d = deps(db);
      await sendAccessTestMessage(d, { sport: 'Futsal', season: '16', uid: 'adm1', template: key, displayName: 'Z' });
      const text = `${d.pusher.sends[0][0].title} ${d.pusher.sends[0][0].body} ${d.mailer.mails[0].subject} ${d.mailer.mails[0].html}`;
      expect(text, key).not.toMatch(/\{(name|teamName|amount|season|method|date|reason)\}/);
    }
  });
});
