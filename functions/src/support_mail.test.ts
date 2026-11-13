// sendMail (the status-returning core) and sendSupportMail (its unchanged
// never-throws wrapper), driven through support_mail's __setMailerForTests
// seam over a recording fake Reference.

import { afterEach, describe, expect, it, vi } from 'vitest';
import * as logger from 'firebase-functions/logger';
import { __setMailerForTests, sendMail, sendSupportMail } from './support_mail';

interface Logged { path: string; value: Record<string, unknown> }

/** A Reference that records Support/MailLog pushes (and can fail them). */
function fakeRoot(opts: { failLog?: boolean } = {}): { root: any; logged: Logged[] } {
  const logged: Logged[] = [];
  const root = {
    child: (path: string) => ({
      push: () => ({
        set: async (value: Record<string, unknown>) => {
          if (opts.failLog) throw new Error('database unavailable');
          logged.push({ path, value });
        },
      }),
    }),
  };
  return { root, logged };
}

function fakeMailer(send: (o: any) => Promise<unknown> = async () => ({})): { mailer: any; sent: any[] } {
  const sent: any[] = [];
  return {
    sent,
    mailer: { from: 'noreply@infinitesports.org', send: async (o: any) => { sent.push(o); return send(o); } },
  };
}

const MSG = { to: 'player.one@example.com', subject: 'Hello', html: '<p>hi</p>' };

afterEach(() => {
  __setMailerForTests('unset');
  vi.restoreAllMocks();
});

describe('sendMail', () => {
  it("returns 'sent', delivers it and logs the attempt to Support/MailLog", async () => {
    const { mailer, sent } = fakeMailer();
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await expect(sendMail(root, MSG)).resolves.toBe('sent');
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ to: MSG.to, subject: 'Hello', html: '<p>hi</p>' });
    expect(logged).toHaveLength(1);
    expect(logged[0].path).toBe('Support/MailLog');
    expect(logged[0].value).toMatchObject({ To: MSG.to, Subject: 'Hello', Ok: true });
  });

  it("returns 'skipped' (and logs nothing) when the SMTP secrets are not configured", async () => {
    __setMailerForTests(null);
    const { root, logged } = fakeRoot();
    await expect(sendMail(root, MSG)).resolves.toBe('skipped');
    expect(logged).toEqual([]);
  });

  it("returns 'failed' for an invalid recipient without trying to send", async () => {
    const { mailer, sent } = fakeMailer();
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await expect(sendMail(root, { ...MSG, to: 'not-an-address' })).resolves.toBe('failed');
    expect(sent).toEqual([]);
    expect(logged[0].value).toMatchObject({ Ok: false, Err: 'invalid recipient address' });
  });

  it("returns 'failed' when the transport throws, and never throws itself", async () => {
    const { mailer } = fakeMailer(async () => { throw new Error('connection refused'); });
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await expect(sendMail(root, MSG)).resolves.toBe('failed');
    expect(logged[0].value).toMatchObject({ Ok: false });
    expect(String(logged[0].value['Err'])).toContain('connection refused');
  });

  it("still reports 'sent' when only the MailLog write fails (the mail already left)", async () => {
    const { mailer, sent } = fakeMailer();
    __setMailerForTests(mailer);
    const { root } = fakeRoot({ failLog: true });
    await expect(sendMail(root, MSG)).resolves.toBe('sent');
    expect(sent).toHaveLength(1);
  });

  it('redactRecipient keeps the address out of the MailLog, the stored error and the logs', async () => {
    const warn = vi.spyOn(logger, 'warn').mockImplementation(() => undefined);
    const error = vi.spyOn(logger, 'error').mockImplementation(() => undefined);
    const { mailer } = fakeMailer(async (o) => { throw new Error(`550 <${o.to}>: mailbox unavailable`); });
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await expect(sendMail(root, MSG, { redactRecipient: true })).resolves.toBe('failed');
    const stored = JSON.stringify(logged);
    expect(stored).not.toContain('player.one@example.com');
    expect(logged[0].value['To']).toBe('pl••••••••@example.com');
    expect(String(logged[0].value['Err'])).toContain('mailbox unavailable');
    const logs = JSON.stringify([...warn.mock.calls, ...error.mock.calls]);
    expect(logs).not.toContain('player.one@example.com');
  });
});

describe('sendSupportMail (unchanged: resolves void, never throws)', () => {
  it('sends and logs exactly as before', async () => {
    const { mailer, sent } = fakeMailer();
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await expect(sendSupportMail(root, MSG)).resolves.toBeUndefined();
    expect(sent).toHaveLength(1);
    expect(logged[0].value).toMatchObject({ To: MSG.to, Ok: true });
  });

  it('is a quiet no-op without SMTP secrets and swallows a failing transport', async () => {
    const { root, logged } = fakeRoot();
    __setMailerForTests(null);
    await expect(sendSupportMail(root, MSG)).resolves.toBeUndefined();
    expect(logged).toEqual([]);
    const { mailer } = fakeMailer(async () => { throw new Error('boom'); });
    __setMailerForTests(mailer);
    await expect(sendSupportMail(root, MSG)).resolves.toBeUndefined();
    expect(logged[0].value).toMatchObject({ Ok: false });
  });

  it('logs the raw recipient (support mail is not redacted)', async () => {
    const { mailer } = fakeMailer();
    __setMailerForTests(mailer);
    const { root, logged } = fakeRoot();
    await sendSupportMail(root, MSG);
    expect(logged[0].value['To']).toBe('player.one@example.com');
  });
});
