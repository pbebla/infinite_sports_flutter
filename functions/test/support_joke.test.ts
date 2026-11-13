// generateTicketJoke callable: takes { category } only. A `message` sent by
// an older Manager build is ignored - never an error, never forwarded to the
// AI service, never logged (the Privacy Policy says only public fantasy
// statistics go to that service).

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const h = vi.hoisted(() => ({ admins: {} as Record<string, unknown>, lines: [] as string[] }));

vi.mock('firebase-admin', () => ({
  database: () => ({
    ref: (path: string) => ({ get: async () => ({ val: () => h.admins[path] ?? null }) }),
  }),
}));
vi.mock('firebase-functions/logger', () => {
  const line = (kind: string) => (...args: unknown[]) => { h.lines.push(`${kind} ${JSON.stringify(args)}`); };
  return { info: line('info'), warn: line('warn'), error: line('error'), debug: line('debug') };
});

import { generateTicketJoke } from '../src/support_joke';

const ADMIN = 'uid_admin_12345';
const PRIVATE = 'My son Jordan at 12 Elm Street cannot log in';

function call(data: unknown, uid: string | null = ADMIN): Promise<any> {
  return (generateTicketJoke as any).run({
    data, auth: uid === null ? undefined : { uid, token: {} }, rawRequest: {},
  });
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  h.admins = { [`Admins/${ADMIN}`]: true };
  h.lines = [];
  process.env.ANTHROPIC_API_KEY = 'sk-test';
  fetchMock = vi.fn(async () => ({
    ok: true, status: 200, json: async () => ({ content: [{ type: 'text', text: 'A one-liner.' }] }),
  }));
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  delete process.env.ANTHROPIC_API_KEY;
  vi.unstubAllGlobals();
});

describe('generateTicketJoke', () => {
  it('works with { category } alone', async () => {
    await expect(call({ category: 'bug' })).resolves.toEqual({ joke: 'A one-liner.', source: 'ai' });
    const body = String(fetchMock.mock.calls[0][1].body);
    expect(body).toContain('Something is broken');
  });

  it('ignores a message from an older build: no error, not forwarded, not logged', async () => {
    await expect(call({ category: 'account', message: PRIVATE })).resolves.toMatchObject({ source: 'ai' });
    const body = String(fetchMock.mock.calls[0][1].body);
    for (const part of ['Jordan', 'Elm Street', PRIVATE]) {
      expect(body).not.toContain(part);
      expect(h.lines.join('\n')).not.toContain(part);
    }
  });

  it('a missing or unknown category falls back to the generic one', async () => {
    await expect(call({})).resolves.toMatchObject({ source: 'ai' });
    expect(String(fetchMock.mock.calls[0][1].body)).toContain('Something else');
    await expect(call(null)).resolves.toMatchObject({ source: 'ai' });
  });

  it('still refuses non-admins and signed-out callers', async () => {
    await expect(call({ category: 'bug' }, null)).rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(call({ category: 'bug' }, 'uid_fan_12345')).rejects.toMatchObject({ code: 'permission-denied' });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
