import { describe, expect, it, vi } from 'vitest';
import {
  ackEmailHtml, ackSubject, becameClosed, buildJokePrompt, cannedJoke,
  CATEGORY_KEYS, categoryLabel, closedOutcomePhrase, closingEmailHtml,
  closingSubject, escapeHtml, escapeMultiline, FetchLike, generateJoke,
  isValidEmail, JOKE_BANK, JOKE_MODEL, mailLogEntry, newTicketEmailHtml,
  newTicketSubject, normalizeCategory, parseAnthropicJoke, replyNoticeEmailHtml,
  replySubject, sanitizeSubject, screenshotCount, statusAfterThreadMessage,
} from '../src/lib/support';

// ---------------------------------------------------------------------------
// Escaping
// ---------------------------------------------------------------------------

describe('escapeHtml', () => {
  it('escapes all five HTML-special characters', () => {
    expect(escapeHtml(`<b>&"'</b>`)).toBe('&lt;b&gt;&amp;&quot;&#39;&lt;/b&gt;');
  });

  it('leaves plain text untouched', () => {
    expect(escapeHtml('Futsal Season 16!')).toBe('Futsal Season 16!');
  });
});

describe('escapeMultiline', () => {
  it('escapes first, then turns newlines into <br>', () => {
    expect(escapeMultiline('<b>\nhi')).toBe('&lt;b&gt;<br>hi');
  });

  it('handles \\r\\n and bare \\r as one break each', () => {
    expect(escapeMultiline('a\r\nb\rc')).toBe('a<br>b<br>c');
  });
});

describe('sanitizeSubject', () => {
  it('strips CRLF sequences so subjects cannot inject headers', () => {
    expect(sanitizeSubject('hello\r\nBcc: victim@example.com'))
      .toBe('hello Bcc: victim@example.com');
  });

  it('collapses runs of newlines to a single space and trims', () => {
    expect(sanitizeSubject('\na\n\n\nb\r\n')).toBe('a b');
  });
});

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

describe('normalizeCategory', () => {
  it('passes canonical keys through', () => {
    for (const key of CATEGORY_KEYS) expect(normalizeCategory(key)).toBe(key);
  });

  it('maps display labels (any case) to keys', () => {
    expect(normalizeCategory('Something is broken')).toBe('bug');
    expect(normalizeCategory('I NEED HELP')).toBe('help');
    expect(normalizeCategory('account or access')).toBe('account');
    expect(normalizeCategory('Something else')).toBe('other');
  });

  it('falls back to other for unknown values', () => {
    expect(normalizeCategory('')).toBe('other');
    expect(normalizeCategory('banana')).toBe('other');
  });
});

describe('categoryLabel', () => {
  it('returns the display label for keys and labels alike', () => {
    expect(categoryLabel('bug')).toBe('Something is broken');
    expect(categoryLabel('Suggestion')).toBe('Suggestion');
    expect(categoryLabel('unknown')).toBe('Something else');
  });
});

// ---------------------------------------------------------------------------
// Status transitions
// ---------------------------------------------------------------------------

describe('statusAfterThreadMessage', () => {
  it('user reply reopens the ticket', () => {
    expect(statusAfterThreadMessage('user')).toBe('open');
  });

  it('admin reply marks it answered', () => {
    expect(statusAfterThreadMessage('admin')).toBe('answered');
  });

  it('internal notes and unknown senders change nothing', () => {
    expect(statusAfterThreadMessage('note')).toBeNull();
    expect(statusAfterThreadMessage('')).toBeNull();
    expect(statusAfterThreadMessage('robot')).toBeNull();
  });
});

describe('becameClosed', () => {
  it('is true only when the status lands on closed from something else', () => {
    expect(becameClosed('open', 'closed')).toBe(true);
    expect(becameClosed('answered', 'closed')).toBe(true);
    expect(becameClosed('', 'closed')).toBe(true);
  });

  it('is false for closed re-writes and for every other transition', () => {
    expect(becameClosed('closed', 'closed')).toBe(false);
    expect(becameClosed('closed', 'open')).toBe(false);
    expect(becameClosed('open', 'answered')).toBe(false);
  });
});

describe('closedOutcomePhrase', () => {
  it('phrases each of the close-dialog outcomes', () => {
    expect(closedOutcomePhrase('Fixed')).toBe('We fixed it.');
    expect(closedOutcomePhrase('added')).toBe('We added it.');
    expect(closedOutcomePhrase('Planned')).toContain('roadmap');
    expect(closedOutcomePhrase("Won't do")).toContain('not to do');
  });

  it("tolerates wont_do spellings and treats unknowns as Other", () => {
    expect(closedOutcomePhrase('wont_do')).toContain('not to do');
    expect(closedOutcomePhrase('WONT-DO')).toContain('not to do');
    expect(closedOutcomePhrase('Other')).toBe('This ticket has been resolved.');
    expect(closedOutcomePhrase('')).toBe('This ticket has been resolved.');
  });
});

// ---------------------------------------------------------------------------
// Shape helpers
// ---------------------------------------------------------------------------

describe('screenshotCount', () => {
  it('counts arrays, skipping null holes', () => {
    expect(screenshotCount(['a.jpg', 'b.jpg'])).toBe(2);
    expect(screenshotCount(['a.jpg', null, 'c.jpg'])).toBe(2);
    expect(screenshotCount([])).toBe(0);
  });

  it('counts RTDB object-shaped arrays', () => {
    expect(screenshotCount({ 0: 'a.jpg', 2: 'c.jpg' })).toBe(2);
  });

  it('is 0 for missing/scalar values', () => {
    expect(screenshotCount(null)).toBe(0);
    expect(screenshotCount(undefined)).toBe(0);
    expect(screenshotCount('a.jpg')).toBe(0);
  });
});

describe('isValidEmail', () => {
  it('accepts ordinary addresses', () => {
    expect(isValidEmail('player@example.com')).toBe(true);
    expect(isValidEmail('support@infinitesports.org')).toBe(true);
  });

  it('refuses empty/garbage/whitespace addresses', () => {
    expect(isValidEmail('')).toBe(false);
    expect(isValidEmail('player')).toBe(false);
    expect(isValidEmail('a b@c.com')).toBe(false);
    expect(isValidEmail('a@b')).toBe(false);
    expect(isValidEmail('a@b.com\nBcc: x@y.com')).toBe(false);
  });
});

describe('mailLogEntry', () => {
  it('builds the Ok shape without Err', () => {
    const at = { '.sv': 'timestamp' };
    expect(mailLogEntry({ to: 'a@b.com', subject: 's', ok: true, at })).toEqual({
      To: 'a@b.com', Subject: 's', Ok: true, At: at,
    });
  });

  it('includes Err only on failures', () => {
    const entry = mailLogEntry({
      to: 'a@b.com', subject: 's', ok: false, err: 'boom', at: 1,
    });
    expect(entry).toEqual({ To: 'a@b.com', Subject: 's', Ok: false, Err: 'boom', At: 1 });
  });
});

// ---------------------------------------------------------------------------
// Subjects
// ---------------------------------------------------------------------------

describe('subjects', () => {
  it('ackSubject carries the reference number', () => {
    expect(ackSubject('42')).toBe('Thanks — your Infinite Sports reference is #42');
  });

  it('newTicketSubject follows [Infinite Sports <Category>] from <Name> (ref #N)', () => {
    expect(newTicketSubject('7', 'bug', 'Zayaa'))
      .toBe('[Infinite Sports Something is broken] from Zayaa (ref #7)');
  });

  it('newTicketSubject strips newline injection from the name', () => {
    const s = newTicketSubject('7', 'bug', 'Evil\r\nBcc: victim@example.com');
    expect(s).not.toMatch(/[\r\n]/);
    expect(s).toContain('(ref #7)');
  });

  it('replySubject strips newline injection from the name', () => {
    expect(replySubject('9', 'A\nB')).toBe('Re: ticket #9 — reply from A B');
  });

  it('closingSubject names the ticket', () => {
    expect(closingSubject('13')).toBe('Your Infinite Sports ticket #13 is closed');
  });
});

// ---------------------------------------------------------------------------
// Email bodies — content and escaping (script tags neutralized everywhere)
// ---------------------------------------------------------------------------

const XSS = '<script>alert("pwn")</script>';

describe('ackEmailHtml', () => {
  const html = ackEmailHtml({
    num: '42', name: 'Zayaa', category: 'suggestion', message: 'More futsal\nplease',
  });

  it('contains the reference, category label and message', () => {
    expect(html).toContain('#42');
    expect(html).toContain('Suggestion');
    expect(html).toContain('More futsal<br>please');
    expect(html).toContain('Hi Zayaa');
  });

  it('neutralizes script tags in name and message', () => {
    const evil = ackEmailHtml({ num: '1', name: XSS, category: 'bug', message: XSS });
    expect(evil).not.toContain('<script');
    expect(evil).toContain('&lt;script&gt;');
  });
});

describe('newTicketEmailHtml', () => {
  const html = newTicketEmailHtml({
    num: '42', name: 'Zayaa', email: 'z@example.com', uid: 'uid123',
    category: 'help', message: 'Where are standings?', platform: 'iOS',
    appVersion: '3.0.0+10', screen: 'TablePage', screenshotCount: 2,
  });

  it('carries message, context block and uid', () => {
    expect(html).toContain('#42');
    expect(html).toContain('I need help');
    expect(html).toContain('Where are standings?');
    expect(html).toContain('iOS');
    expect(html).toContain('3.0.0+10');
    expect(html).toContain('TablePage');
    expect(html).toContain('>2<'); // screenshot count cell
    expect(html).toContain('uid123');
    expect(html).toContain('z@example.com');
  });

  it('neutralizes script tags in every user field', () => {
    const evil = newTicketEmailHtml({
      num: '1', name: XSS, email: XSS, uid: 'u', category: 'other',
      message: XSS, platform: XSS, appVersion: XSS, screen: XSS, screenshotCount: 0,
    });
    expect(evil).not.toContain('<script');
  });
});

describe('replyNoticeEmailHtml', () => {
  it('carries the ticket number, name and reply text', () => {
    const html = replyNoticeEmailHtml({ num: '9', name: 'Zayaa', text: 'Still broken' });
    expect(html).toContain('#9');
    expect(html).toContain('Zayaa');
    expect(html).toContain('Still broken');
    expect(html).toContain('Open');
  });

  it('neutralizes script tags in the reply text', () => {
    const evil = replyNoticeEmailHtml({ num: '9', name: XSS, text: XSS });
    expect(evil).not.toContain('<script');
  });
});

describe('closingEmailHtml', () => {
  it('carries the outcome phrasing and the joke verbatim (escaped)', () => {
    const html = closingEmailHtml({
      num: '13', name: 'Zayaa', outcome: 'Fixed',
      note: 'The bug has been placed on administrative leave.',
    });
    expect(html).toContain('#13');
    expect(html).toContain('We fixed it.');
    expect(html).toContain('The bug has been placed on administrative leave.');
  });

  it('omits the note block when there is no note', () => {
    const html = closingEmailHtml({ num: '13', name: 'Z', outcome: 'Other', note: '' });
    expect(html).not.toContain('<blockquote');
  });

  it('neutralizes script tags in the note', () => {
    const evil = closingEmailHtml({ num: '1', name: XSS, outcome: 'Fixed', note: XSS });
    expect(evil).not.toContain('<script');
  });
});

// ---------------------------------------------------------------------------
// Canned joke bank
// ---------------------------------------------------------------------------

describe('JOKE_BANK', () => {
  it('covers every category with at least 3 jokes', () => {
    for (const key of CATEGORY_KEYS) {
      expect(JOKE_BANK[key].length, `bank for ${key}`).toBeGreaterThanOrEqual(3);
      for (const joke of JOKE_BANK[key]) {
        expect(joke.trim().length).toBeGreaterThan(0);
      }
    }
  });
});

describe('cannedJoke', () => {
  it('draws from the matching category bank', () => {
    expect(JOKE_BANK.bug).toContain(cannedJoke('bug', () => 0));
    expect(JOKE_BANK.bug).toContain(cannedJoke('Something is broken', () => 0.5));
  });

  it('first and last elements are reachable', () => {
    expect(cannedJoke('help', () => 0)).toBe(JOKE_BANK.help[0]);
    expect(cannedJoke('help', () => 0.999999)).toBe(JOKE_BANK.help[JOKE_BANK.help.length - 1]);
  });

  it('unknown categories draw from the other bank', () => {
    expect(JOKE_BANK.other).toContain(cannedJoke('banana', () => 0.2));
  });
});

// ---------------------------------------------------------------------------
// LLM joke path
// ---------------------------------------------------------------------------

describe('buildJokePrompt', () => {
  it('includes the category label and the ticket message', () => {
    const prompt = buildJokePrompt('bug', 'The scoreboard shows 999-0');
    expect(prompt).toContain('Something is broken');
    expect(prompt).toContain('The scoreboard shows 999-0');
  });

  it('truncates very long messages', () => {
    const prompt = buildJokePrompt('comment', 'x'.repeat(5000));
    expect(prompt).toContain('…');
    expect(prompt.length).toBeLessThan(2000);
  });
});

describe('parseAnthropicJoke', () => {
  it('pulls the first text block out of a Messages response', () => {
    expect(parseAnthropicJoke({
      content: [{ type: 'text', text: '  One-liner here.  ' }],
    })).toBe('One-liner here.');
  });

  it('skips non-text blocks', () => {
    expect(parseAnthropicJoke({
      content: [{ type: 'tool_use' }, { type: 'text', text: 'joke' }],
    })).toBe('joke');
  });

  it('is null for malformed/empty shapes', () => {
    expect(parseAnthropicJoke(null)).toBeNull();
    expect(parseAnthropicJoke('nope')).toBeNull();
    expect(parseAnthropicJoke({})).toBeNull();
    expect(parseAnthropicJoke({ content: [] })).toBeNull();
    expect(parseAnthropicJoke({ content: [{ type: 'text', text: '   ' }] })).toBeNull();
  });
});

function okFetch(text: string): FetchLike {
  return vi.fn(async () => ({
    ok: true,
    status: 200,
    json: async () => ({ content: [{ type: 'text', text }] }),
  })) as unknown as FetchLike;
}

describe('generateJoke', () => {
  it('returns the AI joke on a successful API call', async () => {
    const fetchImpl = okFetch('Scoreboard said 999-0? Even Rocky took fewer hits.');
    const res = await generateJoke({
      category: 'bug', message: 'Scoreboard shows 999-0', apiKey: 'sk-test', fetchImpl,
    });
    expect(res).toEqual({
      joke: 'Scoreboard said 999-0? Even Rocky took fewer hits.', source: 'ai',
    });
  });

  it('calls the Messages API with the documented headers and body', async () => {
    const fetchImpl = okFetch('ha');
    await generateJoke({
      category: 'bug', message: 'broken', apiKey: 'sk-test', fetchImpl,
    });
    const calls = (fetchImpl as unknown as ReturnType<typeof vi.fn>).mock.calls;
    expect(calls).toHaveLength(1);
    const [url, init] = calls[0];
    expect(url).toBe('https://api.anthropic.com/v1/messages');
    expect(init.headers['x-api-key']).toBe('sk-test');
    expect(init.headers['anthropic-version']).toBe('2023-06-01');
    const body = JSON.parse(init.body);
    expect(body.model).toBe(JOKE_MODEL);
    expect(body.max_tokens).toBe(150);
    expect(typeof body.system).toBe('string');
    expect(body.messages).toHaveLength(1);
    expect(body.messages[0].role).toBe('user');
    expect(body.messages[0].content).toContain('broken');
    expect(body.messages[0].content).toContain('Something is broken');
  });

  it('falls back to the bank when no key is configured (and never fetches)', async () => {
    const fetchImpl = okFetch('should not be used');
    const res = await generateJoke({
      category: 'help', message: 'halp', apiKey: '', fetchImpl, rand: () => 0,
    });
    expect(res).toEqual({ joke: JOKE_BANK.help[0], source: 'bank' });
    expect((fetchImpl as unknown as ReturnType<typeof vi.fn>).mock.calls).toHaveLength(0);
  });

  it('falls back to the bank on a non-2xx API response', async () => {
    const fetchImpl: FetchLike = async () => ({
      ok: false, status: 529, json: async () => ({ error: 'overloaded' }),
    });
    const res = await generateJoke({
      category: 'account', message: 'locked out', apiKey: 'sk', fetchImpl, rand: () => 0,
    });
    expect(res).toEqual({ joke: JOKE_BANK.account[0], source: 'bank' });
  });

  it('falls back to the bank when fetch throws', async () => {
    const fetchImpl: FetchLike = async () => { throw new Error('ECONNRESET'); };
    const res = await generateJoke({
      category: 'suggestion', message: 'idea', apiKey: 'sk', fetchImpl, rand: () => 0,
    });
    expect(res).toEqual({ joke: JOKE_BANK.suggestion[0], source: 'bank' });
  });

  it('falls back to the bank on a malformed API payload', async () => {
    const fetchImpl: FetchLike = async () => ({
      ok: true, status: 200, json: async () => ({ unexpected: true }),
    });
    const res = await generateJoke({
      category: 'comment', message: 'nice app', apiKey: 'sk', fetchImpl, rand: () => 0,
    });
    expect(res).toEqual({ joke: JOKE_BANK.comment[0], source: 'bank' });
  });

  it('aborts a hung API call after the timeout and uses the bank', async () => {
    const fetchImpl: FetchLike = (_url, init) => new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(new Error('aborted')));
    });
    const res = await generateJoke({
      category: 'other', message: 'hmm', apiKey: 'sk', fetchImpl,
      timeoutMs: 5, rand: () => 0,
    });
    expect(res).toEqual({ joke: JOKE_BANK.other[0], source: 'bank' });
  });
});
