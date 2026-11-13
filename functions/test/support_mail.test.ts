// sendSupportMail unit tests: transport mocked through __setMailerForTests,
// RTDB root faked with a push/set recorder — no SMTP, no secrets, no Firebase
// app. Verifies the MailLog contract (always logged after an attempt, Ok/Err
// shape, server-timestamp sentinel) and that failures never throw back to the
// calling trigger.

import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Reference } from 'firebase-admin/database';
import {
  __setMailerForTests, sendSupportMail, SUPPORT_MAIL_SECRETS,
} from '../src/support_mail';

interface Logged { path: string; value: Record<string, unknown>; }

function fakeRoot(log: Logged[]): Reference {
  return {
    child: (path: string) => ({
      push: () => ({
        set: async (value: Record<string, unknown>) => { log.push({ path, value }); },
      }),
    }),
  } as unknown as Reference;
}

afterEach(() => __setMailerForTests('unset'));

describe('sendSupportMail', () => {
  it('sends through the transport and logs an Ok MailLog entry', async () => {
    const send = vi.fn(async () => ({ accepted: ['z@example.com'] }));
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });
    const log: Logged[] = [];

    await sendSupportMail(fakeRoot(log), {
      to: 'z@example.com', subject: 'Hello', html: '<p>hi</p>', replyTo: 'fan@example.com',
    });

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0]).toEqual({
      from: 'Infinite Sports <noreply@infinitesports.org>',
      to: 'z@example.com',
      subject: 'Hello',
      html: '<p>hi</p>',
      replyTo: 'fan@example.com',
    });
    expect(log).toHaveLength(1);
    expect(log[0].path).toBe('Support/MailLog');
    expect(log[0].value).toEqual({
      To: 'z@example.com', Subject: 'Hello', Ok: true, At: { '.sv': 'timestamp' },
    });
  });

  it('omits replyTo when not provided', async () => {
    const send = vi.fn(async () => ({}));
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });

    await sendSupportMail(fakeRoot([]), {
      to: 'z@example.com', subject: 'Hello', html: '<p>hi</p>',
    });

    expect(send.mock.calls[0][0]).not.toHaveProperty('replyTo');
  });

  it('sanitizes subject newlines before sending and logging', async () => {
    const send = vi.fn(async () => ({}));
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });
    const log: Logged[] = [];

    await sendSupportMail(fakeRoot(log), {
      to: 'z@example.com', subject: 'Hi\r\nBcc: victim@example.com', html: '<p></p>',
    });

    expect(send.mock.calls[0][0].subject).toBe('Hi Bcc: victim@example.com');
    expect(log[0].value['Subject']).toBe('Hi Bcc: victim@example.com');
  });

  it('logs Ok:false with Err when the transport rejects — and does not throw', async () => {
    const send = vi.fn(async () => { throw new Error('SMTP down'); });
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });
    const log: Logged[] = [];

    await expect(sendSupportMail(fakeRoot(log), {
      to: 'z@example.com', subject: 'Hello', html: '<p>hi</p>',
    })).resolves.toBeUndefined();

    expect(log).toHaveLength(1);
    expect(log[0].value['Ok']).toBe(false);
    expect(String(log[0].value['Err'])).toContain('SMTP down');
    expect(log[0].value['At']).toEqual({ '.sv': 'timestamp' });
  });

  it('refuses invalid recipients without touching the transport, still logs', async () => {
    const send = vi.fn(async () => ({}));
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });
    const log: Logged[] = [];

    await sendSupportMail(fakeRoot(log), {
      to: 'not-an-address', subject: 'Hello', html: '<p>hi</p>',
    });

    expect(send).not.toHaveBeenCalled();
    expect(log).toHaveLength(1);
    expect(log[0].value['Ok']).toBe(false);
    expect(String(log[0].value['Err'])).toContain('invalid recipient');
  });

  it('no-ops (no send, no MailLog) when SMTP is not configured', async () => {
    __setMailerForTests(null); // what getMailer() returns with missing secrets
    const log: Logged[] = [];

    await expect(sendSupportMail(fakeRoot(log), {
      to: 'z@example.com', subject: 'Hello', html: '<p>hi</p>',
    })).resolves.toBeUndefined();

    expect(log).toHaveLength(0);
  });

  it('never throws even when the MailLog write itself fails', async () => {
    const send = vi.fn(async () => ({}));
    __setMailerForTests({ from: 'noreply@infinitesports.org', send });
    const explodingRoot = {
      child: () => ({ push: () => ({ set: async () => { throw new Error('db down'); } }) }),
    } as unknown as Reference;

    await expect(sendSupportMail(explodingRoot, {
      to: 'z@example.com', subject: 'Hello', html: '<p>hi</p>',
    })).resolves.toBeUndefined();
    expect(send).toHaveBeenCalledTimes(1);
  });
});

describe('SUPPORT_MAIL_SECRETS', () => {
  it('declares all four SMTP secrets for function binding', () => {
    expect(SUPPORT_MAIL_SECRETS.map((s) => s.name).sort()).toEqual([
      'SUPPORT_SMTP_HOST', 'SUPPORT_SMTP_PASS', 'SUPPORT_SMTP_PORT', 'SUPPORT_SMTP_USER',
    ]);
  });
});
