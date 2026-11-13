// Paid access (season pass) — pure building blocks (spec
// docs/superpowers/specs/2026-11-01-fantasy-paid-access-design.md §3, §4,
// §7, §9; plan Track A1). Every default here is pinned verbatim: the fan
// app and the Manager carry Dart twins of these constants.

import { describe, expect, it } from 'vitest';
import {
  accessConfigFrom, accessRecordFrom, activationFor, ADMIN_EMAIL_DEFAULT,
  checkoutLineItem, checkoutUrls, claimFrom, COPY_DEFAULTS, dollarsToCents,
  emailHtml, fillTemplate, formatAccessDate, formatAmount, HOSTING_BASE,
  isActive, isPassMode, methodLabel, notifyKeyFor, PAID_VIAS, pendingFor, revokedPatch,
  seasonLabel, TEMPLATE_DEFAULTS, TEMPLATE_KEYS, templateFrom,
} from './access';

describe('accessConfigFrom', () => {
  it('absent / junk -> free mode with every default', () => {
    for (const raw of [null, undefined, 'pass', 42, [], {}]) {
      const cfg = accessConfigFrom(raw);
      expect(cfg).toEqual({
        mode: 'free',
        amountDollars: 0,
        methods: { venmo: true, zelle: false, card: true },
        registeredPlayersFree: false,
        copy: COPY_DEFAULTS,
      });
      expect(isPassMode(cfg)).toBe(false);
    }
  });

  it('reads a full pass-mode node', () => {
    const cfg = accessConfigFrom({
      Mode: 'pass', AmountDollars: 12.5,
      Methods: { Venmo: false, Zelle: true, Card: true },
      RegisteredPlayersFree: true,
      Copy: { Headline: 'H', Body: 'B', Button: 'Go' },
      ChangedAt: 1, ChangedBy: 'adm',
    });
    expect(cfg).toEqual({
      mode: 'pass',
      amountDollars: 12.5,
      methods: { venmo: false, zelle: true, card: true },
      registeredPlayersFree: true,
      copy: { headline: 'H', body: 'B', button: 'Go' },
    });
    expect(isPassMode(cfg)).toBe(true);
  });

  it('bad types fall back field by field', () => {
    const cfg = accessConfigFrom({
      Mode: 'PASS', AmountDollars: '10', Methods: 'yes',
      RegisteredPlayersFree: 'true', Copy: { Headline: '', Body: 7 },
    });
    expect(cfg.mode).toBe('free'); // only the literal 'pass' is pass mode
    expect(cfg.amountDollars).toBe(0);
    expect(cfg.methods).toEqual({ venmo: true, zelle: false, card: true });
    expect(cfg.registeredPlayersFree).toBe(false);
    expect(cfg.copy).toEqual(COPY_DEFAULTS); // blank + non-string -> defaults
  });

  it('a method switch is read as exactly true/false; junk keeps the default', () => {
    expect(accessConfigFrom({ Methods: { Venmo: 'no', Zelle: 1, Card: false } }).methods)
      .toEqual({ venmo: true, zelle: false, card: false });
  });

  it('a stray Methods/Cash switch is ignored: cash is not a fan method', () => {
    const m = accessConfigFrom({ Methods: { Cash: true } }).methods as Record<string, unknown>;
    expect(m).not.toHaveProperty('cash');
    expect(m).toEqual({ venmo: true, zelle: false, card: true });
  });

  it('negative / NaN amounts read 0', () => {
    expect(accessConfigFrom({ AmountDollars: -5 }).amountDollars).toBe(0);
    expect(accessConfigFrom({ AmountDollars: Number.NaN }).amountDollars).toBe(0);
  });
});

describe('accessRecordFrom / isActive', () => {
  it('null / junk / unknown status -> null, never active', () => {
    for (const raw of [null, undefined, 'active', 1, [], {}, { Status: 'done' }]) {
      expect(accessRecordFrom(raw)).toBeNull();
      expect(isActive(accessRecordFrom(raw))).toBe(false);
    }
  });

  it.each([
    ['active', true], ['pending', false], ['revoked', false],
  ] as const)('Status %s -> isActive %s', (status, active) => {
    const rec = accessRecordFrom({ Status: status, Via: 'card', AmountCents: 1000, PaidAt: 5, By: 'stripe' });
    expect(rec?.status).toBe(status);
    expect(isActive(rec)).toBe(active);
  });

  it('reads every field tolerantly; unknown Via reads as granted-like text', () => {
    const rec = accessRecordFrom({
      Status: 'revoked', Via: 'card', AmountCents: '1000', PaidAt: 10, By: 'stripe',
      Reason: 'r', StripePaymentIntent: 'pi_1', RefundedAt: 20, RevokedBy: 'stripe',
      RevokeReason: 'refund', Notified: { active_10: true },
    });
    expect(rec).toEqual({
      status: 'revoked', via: 'card', amountCents: 0, paidAt: 10, by: 'stripe',
      reason: 'r', stripePaymentIntent: 'pi_1', refundedAt: 20, revokedBy: 'stripe',
      revokeReason: 'refund', notified: { active_10: true },
    });
    expect(accessRecordFrom({ Status: 'active', Via: 'magic' })?.via).toBe('granted');
    expect(accessRecordFrom({ Status: 'active' })?.paidAt).toBeNull();
  });
});

describe('templates', () => {
  it('TEMPLATE_DEFAULTS are the spec §9 table, verbatim', () => {
    expect(TEMPLATE_KEYS).toEqual([
      'claimReceived', 'claimAdmin', 'activatedPaid', 'activatedGranted', 'revoked',
    ]);
    expect(TEMPLATE_DEFAULTS.claimReceived).toEqual({
      pushTitle: "Payment noted",
      pushBody: "Thanks {name} — we'll confirm your {method} payment for {season} Fantasy shortly.",
      emailSubject: "{season} Fantasy — payment noted",
      emailBody: "Hi {name}, we received your note that you paid {amount} by {method} for {season} Fantasy access. Zaya will confirm it shortly and you'll get a message the moment you're in.",
    });
    expect(TEMPLATE_DEFAULTS.claimAdmin).toEqual({
      pushTitle: "Fantasy access — {method} payment to confirm",
      pushBody: "{name} says they paid {amount} by {method} for {season} Fantasy access.",
      emailSubject: "Fantasy access — {method} payment to confirm — {name}",
      emailBody: "{name} says they paid {amount} by {method} for {season} Fantasy access.\n\nOpen the Manager → Fantasy → Access & payments to approve.",
    });
    expect(TEMPLATE_DEFAULTS.activatedPaid).toEqual({
      pushTitle: "You're in!",
      pushBody: "Your {season} Fantasy season pass is active. Build your team!",
      emailSubject: "Receipt — {season} Fantasy season pass",
      emailBody: "Hi {name}, your {season} Fantasy season pass is active.\n\nAmount: {amount}\nMethod: {method}\nDate: {date}\nSeason: {season}\n\nOpen the app → Fantasy → My Team to name your team and build your squad. Good luck!",
    });
    expect(TEMPLATE_DEFAULTS.activatedGranted).toEqual({
      pushTitle: "You're in!",
      pushBody: "Your {season} Fantasy access is active. Build your team!",
      emailSubject: "You're in — {season} Fantasy",
      emailBody: "Hi {name}, your access to {season} Fantasy is active. Open the app → Fantasy → My Team to build your squad.",
    });
    expect(TEMPLATE_DEFAULTS.revoked).toEqual({
      pushTitle: "Fantasy access removed",
      pushBody: "Your {season} Fantasy access was removed. Pay again in the app to keep playing.",
      emailSubject: "{season} Fantasy — access removed",
      emailBody: "Hi {name}, your {season} Fantasy access was removed on {date}. You can pay again from the app's Fantasy tab to keep playing. Reply to this email if you think this is a mistake.",
    });
    expect(COPY_DEFAULTS).toEqual({
      headline: 'Join Infinite Fantasy',
      body: 'A season pass for {season} Fantasy is {amount}. Pay once, play the whole season.',
      button: 'Pay with card',
    });
    expect(ADMIN_EMAIL_DEFAULT).toBe('support@infinitesports.org');
  });

  it('no fan-facing default mentions grants, free access or admins', () => {
    for (const key of ['claimReceived', 'activatedPaid', 'activatedGranted', 'revoked'] as const) {
      const t = TEMPLATE_DEFAULTS[key];
      const all = `${t.pushTitle} ${t.pushBody} ${t.emailSubject} ${t.emailBody}`.toLowerCase();
      expect(all, key).not.toMatch(/grant|free|admin/);
    }
    const copy = `${COPY_DEFAULTS.headline} ${COPY_DEFAULTS.body} ${COPY_DEFAULTS.button}`;
    expect(copy.toLowerCase()).not.toMatch(/grant|free|admin/);
  });

  it('templateFrom: absent node -> defaults, every field fell back', () => {
    const r = templateFrom('activatedPaid', null);
    expect(r.template).toEqual(TEMPLATE_DEFAULTS.activatedPaid);
    expect(r.fallbacks).toEqual(['PushTitle', 'PushBody', 'EmailSubject', 'EmailBody']);
    expect(r.present).toBe(false);
  });

  it('templateFrom: blank / missing / non-string fields fall back one by one', () => {
    const r = templateFrom('revoked', {
      PushTitle: 'Gone', PushBody: '   ', EmailSubject: 9, EmailBody: 'Bye {name}',
    });
    expect(r.template).toEqual({
      pushTitle: 'Gone',
      pushBody: TEMPLATE_DEFAULTS.revoked.pushBody,
      emailSubject: TEMPLATE_DEFAULTS.revoked.emailSubject,
      emailBody: 'Bye {name}',
    });
    expect(r.fallbacks).toEqual(['PushBody', 'EmailSubject']);
    expect(r.present).toBe(true);
  });

  it('fillTemplate replaces the seven placeholders, leaves unknown ones, tolerates missing vars', () => {
    const out = fillTemplate(
      '{name}/{teamName}/{amount}/{season}/{method}/{date}/{reason}/{unknown}/{name}',
      { name: 'Zed', amount: '$10.00', season: 'Futsal Season 16' });
    expect(out).toBe('Zed//$10.00/Futsal Season 16////{unknown}/Zed');
  });

  it('fillTemplate never treats a value as a pattern', () => {
    expect(fillTemplate('{name} {teamName}', { name: '$&', teamName: '{name}' }))
      .toBe('$& {name}');
  });
});

describe('labels', () => {
  it('formatAmount renders whole cents as dollars', () => {
    expect(formatAmount(1050)).toBe('$10.50');
    expect(formatAmount(1000)).toBe('$10.00');
    expect(formatAmount(0)).toBe('$0.00');
    expect(formatAmount(5)).toBe('$0.05');
    expect(formatAmount(123456)).toBe('$1,234.56');
  });

  it('dollarsToCents rounds to the nearest cent', () => {
    expect(dollarsToCents(10)).toBe(1000);
    expect(dollarsToCents(10.5)).toBe(1050);
    expect(dollarsToCents(0.1 + 0.2)).toBe(30);
  });

  it('seasonLabel / methodLabel', () => {
    expect(seasonLabel('Futsal', '16')).toBe('Futsal Season 16');
    expect(seasonLabel('Flag Football', 3)).toBe('Flag Football Season 3');
    expect(methodLabel('card')).toBe('card');
    expect(methodLabel('venmo')).toBe('Venmo');
    expect(methodLabel('zelle')).toBe('Zelle');
    expect(methodLabel('cash')).toBe('cash');
    expect(methodLabel('granted')).toBe('');
  });

  it('formatAccessDate renders the league-local (Pacific) calendar day', () => {
    // 2026-11-02T06:30Z is still Nov 1 in Los Angeles (PST, UTC-8 after the
    // Nov 1 2026 DST end).
    expect(formatAccessDate(Date.UTC(2026, 10, 2, 6, 30))).toBe('Nov 1, 2026');
    expect(formatAccessDate(Date.UTC(2026, 6, 4, 12))).toBe('Jul 4, 2026');
  });
});

describe('record builders', () => {
  it('activationFor writes the spec §4 node', () => {
    expect(activationFor('card', 1000, 123, 'stripe', { StripePaymentIntent: 'pi_1' }))
      .toEqual({
        Status: 'active', Via: 'card', AmountCents: 1000, PaidAt: 123, By: 'stripe',
        StripePaymentIntent: 'pi_1',
      });
    expect(activationFor('granted', 0, 5, 'adm', { Reason: 'VIP' })).toEqual({
      Status: 'active', Via: 'granted', AmountCents: 0, PaidAt: 5, By: 'adm', Reason: 'VIP',
    });
    expect(activationFor('player', 0, 5, 'system')).toEqual({
      Status: 'active', Via: 'player', AmountCents: 0, PaidAt: 5, By: 'system',
    });
  });

  it('pendingFor mirrors the claim; PaidAt stays null (absent)', () => {
    const claim = claimFrom({ Method: 'venmo', AmountDollars: 10, Note: 'n', At: 7 })!;
    expect(pendingFor(claim, 99)).toEqual({
      Status: 'pending', Via: 'venmo', AmountCents: 1000, By: 'system', ClaimedAt: 99,
    });
  });

  it('revokedPatch', () => {
    expect(revokedPatch(50, 'stripe')).toEqual({
      Status: 'revoked', RefundedAt: 50, RevokedBy: 'stripe',
    });
    expect(revokedPatch(50, 'adm', 'chargeback')).toEqual({
      Status: 'revoked', RefundedAt: 50, RevokedBy: 'adm', RevokeReason: 'chargeback',
    });
  });

  it('notifyKeyFor: active_<PaidAt> / revoked_<RefundedAt>; unknown stamps read "unknown"', () => {
    const active = accessRecordFrom({ Status: 'active', PaidAt: 1700 })!;
    expect(notifyKeyFor('active', active)).toBe('active_1700');
    const revoked = accessRecordFrom({ Status: 'revoked', PaidAt: 1700, RefundedAt: 1800 })!;
    expect(notifyKeyFor('revoked', revoked)).toBe('revoked_1800');
    expect(notifyKeyFor('active', accessRecordFrom({ Status: 'active' })!)).toBe('active_unknown');
    expect(notifyKeyFor('revoked', accessRecordFrom({ Status: 'revoked' })!)).toBe('revoked_unknown');
  });
});

describe('claimFrom', () => {
  it('parses a fan claim; rejects anything but venmo/zelle', () => {
    expect(claimFrom({ Method: 'zelle', AmountDollars: 10.5, Note: 'hi', At: 3 })).toEqual({
      method: 'zelle', amountDollars: 10.5, note: 'hi', at: 3, resolved: null,
    });
    expect(claimFrom({ Method: 'venmo', AmountDollars: 10, At: 3, Resolved: 'approved' })?.resolved)
      .toBe('approved');
    expect(claimFrom({ Method: 'card', AmountDollars: 10, At: 3 })).toBeNull();
    expect(claimFrom({ AmountDollars: 10, At: 3 })).toBeNull();
    expect(claimFrom(null)).toBeNull();
    expect(claimFrom('venmo')).toBeNull();
  });

  it('a fan cannot claim cash (2026-11-02: cash is recorded by an admin only)', () => {
    expect(claimFrom({ Method: 'cash', AmountDollars: 10, Note: 'n', At: 3 })).toBeNull();
    // ...but cash stays a valid PAID record an admin writes to Access/<uid>.
    expect(PAID_VIAS).toContain('cash');
    expect(methodLabel('cash')).toBe('cash');
    expect(accessRecordFrom({ Status: 'active', Via: 'cash', AmountCents: 1000, PaidAt: 5, By: 'adm' })?.via)
      .toBe('cash');
  });

  it('tolerates a bad amount / note / at', () => {
    expect(claimFrom({ Method: 'venmo', AmountDollars: 'ten', Note: 4, At: 'now' })).toEqual({
      method: 'venmo', amountDollars: 0, note: '', at: 0, resolved: null,
    });
  });
});

describe('checkout', () => {
  it('checkoutLineItem names the pass and charges the SERVER amount in cents', () => {
    const cfg = accessConfigFrom({ Mode: 'pass', AmountDollars: 10.5 });
    expect(checkoutLineItem(cfg, 'Futsal', '16')).toEqual({
      name: 'Infinite Fantasy — Futsal Season 16 season pass',
      unit_amount: 1050,
      currency: 'usd',
    });
  });

  it('checkoutUrls point at the hosting pages', () => {
    expect(HOSTING_BASE).toBe('https://infinite-sports-app.web.app');
    expect(checkoutUrls(HOSTING_BASE)).toEqual({
      success_url: 'https://infinite-sports-app.web.app/fantasy/paid.html',
      cancel_url: 'https://infinite-sports-app.web.app/fantasy/cancelled.html',
    });
    expect(checkoutUrls('https://x.test/')).toEqual({
      success_url: 'https://x.test/fantasy/paid.html',
      cancel_url: 'https://x.test/fantasy/cancelled.html',
    });
  });
});

describe('emailHtml', () => {
  it('blank lines become paragraphs, single newlines line breaks, everything escaped', () => {
    const html = emailHtml('Hi <Zed>,\n\nAmount: $10.00\nMethod: card\n\nBye & thanks');
    expect(html).toContain('<p>Hi &lt;Zed&gt;,</p>');
    expect(html).toContain('<p>Amount: $10.00<br>Method: card</p>');
    expect(html).toContain('<p>Bye &amp; thanks</p>');
    expect(html).toContain('Infinite Sports');
    expect(html).not.toContain('<script');
  });
});
