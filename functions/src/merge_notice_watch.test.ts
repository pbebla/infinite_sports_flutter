// onMergeNoticeCreated (merge design D11): the send-once email to an old
// account's address. handleMergeNotice is driven over an in-memory tree with
// the Auth lookup and the mailer injected, so no SMTP, Auth or secrets.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it, vi } from 'vitest';
import { handleMergeNotice, MergeNoticeDeps, onMergeNoticeCreated } from './merge_notice_watch';

const OLD_EMAIL = 'old.address.zzz@yahoo.com';
const HINT = 'ca••••••••@gmail.com';

type Tree = Record<string, any>;

/** Minimal admin Reference over [tree]: child(), get(), update(), transaction(). */
function fakeRef(tree: Tree, path: string): any {
  const parts = path.split('/').filter((p) => p.length > 0);
  const read = (): unknown => {
    let node: any = tree;
    for (const p of parts) {
      if (node === null || node === undefined || typeof node !== 'object') return null;
      node = node[p];
    }
    return node === undefined ? null : node;
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
    update: async (v: Record<string, unknown>) => {
      for (const [k, val] of Object.entries(v)) fakeRef(tree, `${path}/${k}`).set(val);
    },
    set: (v: unknown) => write(v),
    transaction: async (fn: (cur: unknown) => unknown) => {
      const cur = read();
      const next = fn(cur === null ? null : JSON.parse(JSON.stringify(cur)));
      if (next === undefined) return { committed: false, snapshot: { val: () => cur } };
      write(next);
      return { committed: true, snapshot: { val: () => next } };
    },
  };
}

function harness(over: Partial<MergeNoticeDeps> = {}, tree: Tree = {
  MergeNotices: { oldA: { KeepHint: HINT, CreatedAt: 1 } },
}): { root: any; tree: Tree; mails: any[]; deps: MergeNoticeDeps } {
  const mails: any[] = [];
  const deps: MergeNoticeDeps = {
    getEmail: async () => OLD_EMAIL,
    sendMail: async (_root, message, options) => { mails.push({ message, options }); return 'sent'; },
    emulator: false,
    at: () => 'NOW',
    ...over,
  };
  return { root: fakeRef(tree, ''), tree, mails, deps };
}

describe('handleMergeNotice', () => {
  it("sends the D11 email to the old account's Auth address, then records Status 'sent' + At", async () => {
    const h = harness();
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('sent');
    expect(h.mails).toHaveLength(1);
    const { message, options } = h.mails[0];
    expect(message.to).toBe(OLD_EMAIL);
    expect(message.subject).toBe('Your Infinite Sports accounts were combined');
    expect(message.html).toContain(`please sign in with ${HINT}.`);
    expect(options).toEqual({ redactRecipient: true }); // the address never reaches MailLog or the logs
    expect(h.tree.MergeNotices.oldA).toMatchObject({ KeepHint: HINT, Status: 'sent', At: 'NOW' });
    expect(h.tree.MergeNotices.oldA.Error).toBeUndefined();
  });

  it('claims once: a second invocation on a node that has a Status sends nothing', async () => {
    const h = harness();
    await handleMergeNotice(h.root, 'oldA', h.deps);
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('already-handled');
    expect(h.mails).toHaveLength(1);
    expect(h.tree.MergeNotices.oldA.Status).toBe('sent');
  });

  it('never re-sends a node that is mid-send or already failed', async () => {
    for (const status of ['sending', 'failed', 'no-email', 'dry-run']) {
      const h = harness({}, { MergeNotices: { oldA: { KeepHint: HINT, Status: status } } });
      await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('already-handled');
      expect(h.mails).toEqual([]);
      expect(h.tree.MergeNotices.oldA.Status).toBe(status);
    }
  });

  it("an account with no email in Firebase Auth records 'no-email' and sends nothing", async () => {
    for (const getEmail of [async () => null, async () => '', async () => '   ']) {
      const h = harness({ getEmail });
      await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('no-email');
      expect(h.mails).toEqual([]);
      expect(h.tree.MergeNotices.oldA).toMatchObject({ Status: 'no-email', At: 'NOW' });
    }
  });

  it("an Auth user that does not exist is also 'no-email'", async () => {
    const h = harness({
      getEmail: async () => { throw Object.assign(new Error('no user record'), { code: 'auth/user-not-found' }); },
    });
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('no-email');
    expect(h.mails).toEqual([]);
  });

  it("a mailer 'failed' records Status 'failed' with no address in the stored node", async () => {
    const h = harness({ sendMail: async () => 'failed' });
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('failed');
    expect(h.tree.MergeNotices.oldA.Status).toBe('failed');
    expect(h.tree.MergeNotices.oldA.At).toBe('NOW');
    expect(typeof h.tree.MergeNotices.oldA.Error).toBe('string');
    expect(JSON.stringify(h.tree)).not.toContain(OLD_EMAIL);
    expect(JSON.stringify(h.tree)).not.toMatch(/@yahoo|old\.address/); // (the masked KeepHint legitimately has @gmail.com)
  });

  it("mail that is switched off ('skipped') is recorded as failed, saying why", async () => {
    const h = harness({ sendMail: async () => 'skipped' });
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('failed');
    expect(h.tree.MergeNotices.oldA.Status).toBe('failed');
    expect(h.tree.MergeNotices.oldA.Error).toMatch(/not configured/i);
  });

  it('a lookup or mailer that THROWS is caught: failed, the error message only, addresses redacted', async () => {
    const h1 = harness({
      getEmail: async () => { throw new Error('lookup for old.address.zzz@yahoo.com timed out'); },
    });
    await expect(handleMergeNotice(h1.root, 'oldA', h1.deps)).resolves.toBe('failed');
    expect(h1.tree.MergeNotices.oldA.Status).toBe('failed');
    expect(h1.tree.MergeNotices.oldA.Error).toContain('timed out');
    expect(JSON.stringify(h1.tree)).not.toContain('old.address');

    const h2 = harness({ sendMail: async () => { throw new Error(`550 <${OLD_EMAIL}> rejected`); } });
    await expect(handleMergeNotice(h2.root, 'oldA', h2.deps)).resolves.toBe('failed');
    expect(h2.tree.MergeNotices.oldA.Status).toBe('failed');
    expect(JSON.stringify(h2.tree)).not.toContain('old.address');
  });

  it("in the emulator it records 'dry-run' and neither reads Auth nor sends", async () => {
    const getEmail = vi.fn(async () => OLD_EMAIL);
    const h = harness({ emulator: true, getEmail });
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('dry-run');
    expect(h.mails).toEqual([]);
    expect(getEmail).not.toHaveBeenCalled();
    expect(h.tree.MergeNotices.oldA).toMatchObject({ Status: 'dry-run', At: 'NOW' });
  });

  it('a node with no hint still sends, pointing at "your other email"', async () => {
    const h = harness({}, { MergeNotices: { oldA: { CreatedAt: 1 } } });
    await expect(handleMergeNotice(h.root, 'oldA', h.deps)).resolves.toBe('sent');
    expect(h.mails[0].message.html).toContain('please sign in with your other email.');
  });
});

describe('onMergeNoticeCreated registration', () => {
  const endpoint = (fn: unknown) => (fn as { __endpoint: any }).__endpoint;

  it('fires on creation of MergeNotices/{uid} with the support mailer secrets bound', () => {
    const e = endpoint(onMergeNoticeCreated);
    expect(e.eventTrigger.eventType).toBe('google.firebase.database.ref.v1.created');
    expect(e.eventTrigger.eventFilterPathPatterns.ref).toBe('MergeNotices/{uid}');
    const secrets = ((e.secretEnvironmentVariables ?? []) as Array<{ key: string }>).map((s) => s.key).sort();
    expect(secrets).toEqual(['SUPPORT_SMTP_HOST', 'SUPPORT_SMTP_PASS', 'SUPPORT_SMTP_PORT', 'SUPPORT_SMTP_USER']);
  });
});

describe('MergeNotices is closed to clients (D11)', () => {
  // The live stage1 rules still carry the legacy root `.read: true` (the whole
  // database is readable today; a notice holds only the masked hint, a status
  // and a bounded error with no address). No file may grant a client WRITE.
  it.each(['database.rules.stage1.json', 'database.rules.json'])(
    '%s has no MergeNotices entry and no root-level write, so no client can write a notice', (file) => {
      const rules = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', '..', file), 'utf8')).rules;
      expect(rules).not.toHaveProperty('MergeNotices');
      expect(rules['.write']).toBeUndefined();
    });

  it('the target rules (database.rules.json) also deny every client read', () => {
    const rules = JSON.parse(fs.readFileSync(path.resolve(__dirname, '..', '..', 'database.rules.json'), 'utf8')).rules;
    expect(rules['.read']).toBeUndefined();
  });
});
