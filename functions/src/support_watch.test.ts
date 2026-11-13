// Support-ticket triggers: mail to "the person" goes to the address Firebase
// Auth holds for the ticket's uid (never the client-written Email field), and
// the server caps acknowledgements (6/h) and user-reply notices (20/h) per
// uid. Handlers are driven over an in-memory tree with Auth and the mailer
// injected, so no SMTP, Auth or secrets.

import { describe, expect, it, vi } from 'vitest';

const logged = vi.hoisted(() => [] as string[]);
vi.mock('firebase-functions/logger', () => {
  const line = (kind: string) => (m: string, c?: unknown) => {
    logged.push(`${kind} ${m} ${JSON.stringify(c ?? {})}`);
  };
  return { info: line('info'), warn: line('warn'), error: line('error'), debug: line('debug') };
});

import {
  handleThreadMessage, handleTicketClosed, handleTicketCreated, SUPPORT_INBOX, SupportDeps,
} from './support_watch';

type Tree = Record<string, any>;
const UID = 'uid_alice_12345';
const AUTH_EMAIL = 'alice.account@example.com';
const STRANGER = 'stranger.victim@example.net';
const NOW = 50_000_000;

function fakeRef(tree: Tree, path: string): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : JSON.parse(JSON.stringify(node));
  };
  const write = (value: unknown): void => {
    let node: any = tree;
    for (const p of parts.slice(0, -1)) {
      if (node[p] === null || node[p] === undefined || typeof node[p] !== 'object') node[p] = {};
      node = node[p];
    }
    const last = parts[parts.length - 1];
    if (value === null || value === undefined) delete node[last]; else node[last] = value;
  };
  return {
    child: (sub: string) => fakeRef(tree, `${path}/${sub}`),
    get: async () => ({ val: () => read() }),
    set: async (v: unknown) => write(v),
    update: async (v: Record<string, unknown>) => {
      for (const [k, val] of Object.entries(v)) fakeRef(tree, `${path}/${k}`).set(val);
    },
    transaction: async (fn: (cur: unknown) => unknown) => {
      if (path.includes('MailCaps') && tree.__failCaps) throw new Error('db unavailable');
      const cur = read();
      const next = fn(cur);
      if (next === undefined) return { committed: false, snapshot: { val: () => cur } };
      write(next);
      return { committed: true, snapshot: { val: () => next } };
    },
  };
}

function harness(over: Partial<SupportDeps> = {}, tree: Tree = {}) {
  const mails: Array<{ to: string; subject: string; html: string; replyTo?: string }> = [];
  const pushes: string[] = [];
  const deps: SupportDeps = {
    getAuthEmail: async (uid) => (uid === UID ? { email: AUTH_EMAIL, verified: true } : null),
    sendMail: async (_root, m) => { mails.push(m); },
    sendPush: async (_root, uid, title) => { pushes.push(`${uid}:${title}`); },
    now: () => NOW,
    ...over,
  };
  return { root: fakeRef(tree, ''), tree, mails, pushes, deps };
}

const ticket = (over: Record<string, unknown> = {}) => ({
  Uid: UID, Name: 'Alice', Email: STRANGER, Category: 'bug', Message: 'It broke',
  Platform: 'iOS', AppVersion: '3.0.0', Screen: 'Home', Status: 'open', ...over,
});

describe('handleTicketCreated', () => {
  it("acknowledges to the account's Auth address, never the stored Email field", async () => {
    const h = harness();
    await handleTicketCreated(h.root, '7', ticket(), h.deps);
    const ack = h.mails.find((m) => m.to !== SUPPORT_INBOX)!;
    expect(ack.to).toBe(AUTH_EMAIL);
    const inbox = h.mails.find((m) => m.to === SUPPORT_INBOX)!;
    expect(inbox.replyTo).toBe(AUTH_EMAIL);
    expect(JSON.stringify(h.mails.map((m) => [m.to, m.replyTo]))).not.toContain(STRANGER);
  });

  it('no Auth email (or user-not-found) -> no acknowledgement, no throw; the inbox still hears', async () => {
    logged.length = 0;
    const h = harness({ getAuthEmail: async () => null });
    await expect(handleTicketCreated(h.root, '7', ticket(), h.deps)).resolves.toBe(true);
    expect(h.mails.map((m) => m.to)).toEqual([SUPPORT_INBOX]);
    expect(h.mails[0].replyTo).toBeUndefined();
    expect(logged.join('\n')).not.toContain(UID);
    expect(logged.join('\n')).not.toContain(STRANGER);
  });

  it('an Auth lookup that throws is treated as no address (never throws into the trigger)', async () => {
    const h = harness({ getAuthEmail: async () => { throw new Error('auth down'); } });
    await expect(handleTicketCreated(h.root, '7', ticket(), h.deps)).resolves.toBe(true);
    expect(h.mails.map((m) => m.to)).toEqual([SUPPORT_INBOX]);
  });

  it('caps acknowledgements at 6 per rolling hour per uid; over the cap sends nothing and warns once, masked', async () => {
    const h = harness();
    for (let i = 1; i <= 6; i++) await handleTicketCreated(h.root, String(i), ticket(), h.deps);
    expect(h.mails.filter((m) => m.to === AUTH_EMAIL)).toHaveLength(6);
    logged.length = 0;
    h.mails.length = 0;
    await handleTicketCreated(h.root, '7', ticket(), h.deps);
    expect(h.mails).toEqual([]);
    const warns = logged.filter((l) => l.startsWith('warn'));
    expect(warns).toHaveLength(1);
    expect(warns[0]).not.toContain(UID);
    expect(warns[0]).toContain(UID.slice(0, 6));
    // The counter node is bounded (6 stamps) and lives at the functions-only path.
    expect(h.tree.Support.MailCaps[UID].Ack).toHaveLength(6);
  });

  it('the cap is a ROLLING hour: an hour later the next ticket is acknowledged again', async () => {
    let now = NOW;
    const h = harness({ now: () => now });
    for (let i = 1; i <= 7; i++) await handleTicketCreated(h.root, String(i), ticket(), h.deps);
    expect(h.mails.filter((m) => m.to === AUTH_EMAIL)).toHaveLength(6);
    now += 60 * 60 * 1000 + 1;
    await handleTicketCreated(h.root, '8', ticket(), h.deps);
    expect(h.mails.filter((m) => m.to === AUTH_EMAIL)).toHaveLength(7);
  });

  it('a ticket with no Uid sends no acknowledgement', async () => {
    const h = harness();
    await handleTicketCreated(h.root, '7', ticket({ Uid: '' }), h.deps);
    expect(h.mails.map((m) => m.to)).toEqual([SUPPORT_INBOX]);
  });
});

describe('handleThreadMessage', () => {
  const seeded = (): Tree => ({ Support: { Tickets: { '7': ticket() } } });

  it('a user reply reopens the ticket and notifies the inbox with Reply-To the Auth address', async () => {
    const h = harness({}, seeded());
    await handleThreadMessage(h.root, '7', { From: 'user', Text: 'still broken' }, h.deps);
    expect(h.tree.Support.Tickets['7'].Status).toBe('open');
    expect(h.mails).toHaveLength(1);
    expect(h.mails[0].to).toBe(SUPPORT_INBOX);
    expect(h.mails[0].replyTo).toBe(AUTH_EMAIL);
  });

  it('caps user-reply notices at 20 per rolling hour per uid; the reply is still processed', async () => {
    const h = harness({}, seeded());
    for (let i = 0; i < 20; i++) {
      await handleThreadMessage(h.root, '7', { From: 'user', Text: `r${i}` }, h.deps);
    }
    expect(h.mails).toHaveLength(20);
    h.tree.Support.Tickets['7'].Status = 'answered';
    logged.length = 0;
    await handleThreadMessage(h.root, '7', { From: 'user', Text: 'r21' }, h.deps);
    expect(h.mails).toHaveLength(20);
    expect(h.tree.Support.Tickets['7'].Status).toBe('open'); // data still written
    expect(logged.filter((l) => l.startsWith('warn'))).toHaveLength(1);
    expect(logged.join('\n')).not.toContain(UID);
  });

  it('an admin reply pushes to the owner and sends no mail', async () => {
    const h = harness({}, seeded());
    await handleThreadMessage(h.root, '7', { From: 'admin', Text: 'fixed' }, h.deps);
    expect(h.tree.Support.Tickets['7'].Status).toBe('answered');
    expect(h.mails).toEqual([]);
    expect(h.pushes).toHaveLength(1);
  });
});

describe('handleTicketClosed', () => {
  it('sends the closing email to the Auth address, not the stored Email field', async () => {
    const h = harness({}, {
      Support: { Tickets: { '7': ticket({ ClosedOutcome: 'fixed', ClosedNote: 'ha' }) } },
    });
    await handleTicketClosed(h.root, '7', h.deps);
    expect(h.mails.map((m) => m.to)).toEqual([AUTH_EMAIL]);
    expect(h.pushes).toHaveLength(1);
  });

  it('no Auth email -> no closing email, push still sent', async () => {
    const h = harness({ getAuthEmail: async () => null }, { Support: { Tickets: { '7': ticket() } } });
    await handleTicketClosed(h.root, '7', h.deps);
    expect(h.mails).toEqual([]);
    expect(h.pushes).toHaveLength(1);
  });
});

describe("an UNVERIFIED account address (it may not be the writer's)", () => {
  const NAME = 'Evil Name spam.example';
  const MESSAGE = 'Click https://spam.example/win now';
  const CATEGORY = 'Free prizes at spam.example';
  const unverified = { getAuthEmail: async () => ({ email: AUTH_EMAIL, verified: false }) };
  const clientText = [NAME, MESSAGE, CATEGORY, 'spam.example', 'Evil'];

  it('the acknowledgement is fixed wording with none of the supplied Name/Message/category', async () => {
    const h = harness(unverified);
    await handleTicketCreated(h.root, '7', ticket({ Name: NAME, Message: MESSAGE, Category: CATEGORY }), h.deps);
    const ack = h.mails.find((m) => m.to === AUTH_EMAIL)!;
    expect(ack.html).toContain('We received your support request #7.');
    expect(ack.html).toContain('Help &amp; Feedback → My Tickets');
    for (const t of clientText) {
      expect(ack.html).not.toContain(t);
      expect(ack.subject).not.toContain(t);
    }
  });

  it('a fixed-list category is still named in the unverified acknowledgement', async () => {
    const h = harness(unverified);
    await handleTicketCreated(h.root, '7', ticket({ Category: 'bug' }), h.deps);
    expect(h.mails.find((m) => m.to === AUTH_EMAIL)!.html).toContain('Something is broken');
  });

  it("a verified user's acknowledgement is unchanged (name, category and message quoted)", async () => {
    const h = harness();
    await handleTicketCreated(h.root, '7', ticket({ Name: 'Alice', Message: 'It broke' }), h.deps);
    const ack = h.mails.find((m) => m.to === AUTH_EMAIL)!;
    expect(ack.html).toContain('Hi Alice');
    expect(ack.html).toContain('It broke');
    expect(ack.html).toContain('Something is broken');
  });

  it('inbox mail has no Reply-To and carries the not-verified line', async () => {
    const h = harness(unverified, { Support: { Tickets: { '7': ticket() } } });
    await handleTicketCreated(h.root, '8', ticket(), h.deps);
    await handleThreadMessage(h.root, '7', { From: 'user', Text: 'more' }, h.deps);
    const inbox = h.mails.filter((m) => m.to === SUPPORT_INBOX);
    expect(inbox).toHaveLength(2);
    for (const m of inbox) {
      expect(m.replyTo).toBeUndefined();
      expect(m.html).toContain('Email not verified — reply in the Manager, not by email.');
    }
  });

  it('the closing email keeps the admin outcome and note but no client-supplied text', async () => {
    const h = harness(unverified, {
      Support: { Tickets: { '7': ticket({
        Name: NAME, Message: MESSAGE, Category: CATEGORY, ClosedOutcome: 'fixed', ClosedNote: 'Admin joke here',
      }) } },
    });
    await handleTicketClosed(h.root, '7', h.deps);
    expect(h.mails).toHaveLength(1);
    const mail = h.mails[0];
    expect(mail.to).toBe(AUTH_EMAIL);
    expect(mail.html).toContain('We fixed it.');
    expect(mail.html).toContain('Admin joke here');
    for (const t of clientText) expect(mail.html + mail.subject).not.toContain(t);
  });
});

describe('mail cap failure', () => {
  it('fails closed when the cap transaction throws: no email, an error logged, nothing thrown, ticket untouched', async () => {
    const tree: Tree = { __failCaps: true, Support: { Tickets: { '7': ticket() } } };
    const before = JSON.stringify(tree.Support.Tickets['7']);
    const h = harness({}, tree);
    logged.length = 0;
    await expect(handleTicketCreated(h.root, '7', ticket(), h.deps)).resolves.toBe(true);
    expect(h.mails).toEqual([]);
    expect(JSON.stringify(tree.Support.Tickets['7'])).toBe(before);
    const errors = logged.filter((l) => l.startsWith('error'));
    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain('cap check failed');
    expect(errors[0]).not.toContain(UID);
  });
});

describe('the ticket key comes from the client: only a plain number is a ticket', () => {
  const BAD = ['Call +1 555 0100 about your account', '12 urgent', '', '7a', '1234567890', '-1', '00x'];
  const unverified = { getAuthEmail: async () => ({ email: AUTH_EMAIL, verified: false }) };

  for (const key of BAD) {
    it(`key ${JSON.stringify(key)}: no mail, no push, nothing stored, one length-only warning on each trigger`, async () => {
      const tree: Tree = { Support: { Tickets: { [key]: ticket({ ClosedOutcome: 'fixed' }) } } };
      const snapshot = JSON.stringify(tree);
      const h = harness(unverified, tree);
      logged.length = 0;
      await expect(handleTicketCreated(h.root, key, ticket(), h.deps)).resolves.toBe(false);
      await expect(handleThreadMessage(h.root, key, { From: 'user', Text: 'x' }, h.deps)).resolves.toBe(false);
      await expect(handleThreadMessage(h.root, key, { From: 'admin', Text: 'x' }, h.deps)).resolves.toBe(false);
      await expect(handleTicketClosed(h.root, key, h.deps)).resolves.toBe(false);
      expect(h.mails).toEqual([]);
      expect(h.pushes).toEqual([]);
      expect(JSON.stringify(tree)).toBe(snapshot); // no Status write, no cap stamp
      const warns = logged.filter((l) => l.startsWith('warn'));
      expect(warns).toHaveLength(4);
      for (const w of warns) {
        expect(w).toContain(`"keyLength":${key.length}`);
        if (key.length > 1) expect(w).not.toContain(key);
        expect(w).not.toContain(UID);
      }
      expect(logged.filter((l) => !l.startsWith('warn'))).toEqual([]);
    });
  }

  for (const key of ['7', '123456789']) {
    it(`key ${key} behaves as before, and the acknowledgement shows only digits after #`, async () => {
      for (const verified of [true, false]) {
        const h = harness({ getAuthEmail: async () => ({ email: AUTH_EMAIL, verified }) }, {
          Support: { Tickets: { [key]: ticket({ ClosedOutcome: 'fixed' }) } },
        });
        await expect(handleTicketCreated(h.root, key, ticket(), h.deps)).resolves.toBe(true);
        await expect(handleThreadMessage(h.root, key, { From: 'user', Text: 'x' }, h.deps)).resolves.toBe(true);
        await expect(handleTicketClosed(h.root, key, h.deps)).resolves.toBe(true);
        expect(h.mails.map((m) => m.to)).toEqual([AUTH_EMAIL, SUPPORT_INBOX, SUPPORT_INBOX, AUTH_EMAIL]);
        const ack = h.mails[0];
        // Scan the visible text: drop style attributes (CSS colours use '#').
        for (const text of [ack.subject, ack.html.replace(/ style="[^"]*"/g, '')]) {
          const refs = [...text.matchAll(/(?<!&)#([^\s<.]*)/g)].map((m) => m[1]);
          expect(refs.length).toBeGreaterThan(0);
          for (const r of refs) expect(r).toMatch(/^\d{1,9}$/);
        }
        expect(h.pushes).toHaveLength(1);
      }
    });
  }
});
