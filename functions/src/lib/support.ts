// Pure support-ticket logic (zaya-support). No Firebase/nodemailer imports —
// unit-tested directly (test/support.test.ts). The impure pieces live in
// src/support_mail.ts (SMTP transport + MailLog), src/support_watch.ts (RTDB
// triggers + FCM) and src/support_joke.ts (admin callable), mirroring the
// pure/impure split of lib/decide.ts, lib/insiders.ts and lib/stripe_pay.ts.
//
// Spec: docs/superpowers/specs/2026-10-13-support-tickets-design.md
// ("Functions (fan repo /functions)" section — ack + new-ticket emails,
// reply/answer transitions, closing email with joke, HTML-escape all user
// strings, strip newlines from subjects, joke bank fallback).

// ---------------------------------------------------------------------------
// Escaping (every user-sourced string goes through these before hitting HTML)
// ---------------------------------------------------------------------------

/** HTML-escapes a user string so names/messages can never inject markup into
 *  an email body. &, <, >, " and ' are replaced. */
export function escapeHtml(raw: string): string {
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** escapeHtml + newline -> <br> for multi-line user text (messages, notes).
 *  Escapes FIRST so the inserted <br> tags are the only markup. */
export function escapeMultiline(raw: string): string {
  return escapeHtml(raw).replace(/\r\n|\r|\n/g, '<br>');
}

/** Strips CR/LF (and collapses the gap) from a subject line so a user string
 *  can never smuggle extra SMTP headers (header injection). */
export function sanitizeSubject(raw: string): string {
  return raw.replace(/[\r\n]+/g, ' ').trim();
}

// ---------------------------------------------------------------------------
// Categories (spec decision #2) — tickets may store either the key or the
// display label; everything normalizes through normalizeCategory().
// ---------------------------------------------------------------------------

export type CategoryKey =
  | 'suggestion' | 'comment' | 'bug' | 'help' | 'account' | 'other';

export const CATEGORY_KEYS: CategoryKey[] = [
  'suggestion', 'comment', 'bug', 'help', 'account', 'other',
];

const CATEGORY_LABELS: Record<CategoryKey, string> = {
  suggestion: 'Suggestion',
  comment: 'Comment',
  bug: 'Something is broken',
  help: 'I need help',
  account: 'Account or access',
  other: 'Something else',
};

/** Maps a raw Category value (key like 'bug' OR display label like
 *  "Something is broken") to a canonical key. Unknown values -> 'other'. */
export function normalizeCategory(raw: string): CategoryKey {
  const v = raw.trim().toLowerCase();
  if ((CATEGORY_KEYS as string[]).includes(v)) return v as CategoryKey;
  for (const key of CATEGORY_KEYS) {
    if (CATEGORY_LABELS[key].toLowerCase() === v) return key;
  }
  return 'other';
}

/** Human display label for a category ("Something is broken", ...). */
export function categoryLabel(raw: string): string {
  return CATEGORY_LABELS[normalizeCategory(raw)];
}

// ---------------------------------------------------------------------------
// Status transitions
// ---------------------------------------------------------------------------

export type ThreadFrom = 'user' | 'admin' | 'note';

/** Status a ticket moves to when a thread message lands: user reply reopens
 *  ('open'), admin reply marks 'answered', internal notes (and anything
 *  unknown) change nothing (null). */
export function statusAfterThreadMessage(from: string): 'open' | 'answered' | null {
  if (from === 'user') return 'open';
  if (from === 'admin') return 'answered';
  return null;
}

/** True exactly when a Status write lands on 'closed' from any other value —
 *  re-writing 'closed' over 'closed' (or touching other fields) never
 *  re-sends the closing email. */
export function becameClosed(before: string, after: string): boolean {
  return after === 'closed' && before !== 'closed';
}

/** Human phrasing for a ClosedOutcome value (Fixed / Added / Planned /
 *  Won't do / Other — the Manager close dialog's selector). Tolerant of
 *  casing, underscores and apostrophes; unknown values read as Other. */
export function closedOutcomePhrase(outcome: string): string {
  const v = outcome.trim().toLowerCase().replace(/[’']/g, '').replace(/[\s_-]+/g, ' ');
  switch (v) {
    case 'fixed': return 'We fixed it.';
    case 'added': return 'We added it.';
    case 'planned': return "It's on the roadmap — we're planning to do it.";
    case 'wont do': return "We looked at it carefully and decided not to do this one.";
    default: return 'This ticket has been resolved.';
  }
}

// ---------------------------------------------------------------------------
// Misc shape helpers
// ---------------------------------------------------------------------------

/** How many screenshots a ticket/message carries. RTDB hands arrays back as
 *  real arrays OR as {0: ..., 1: ...} objects depending on keys — count both,
 *  skipping null holes. */
export function screenshotCount(raw: unknown): number {
  if (Array.isArray(raw)) return raw.filter((v) => v != null).length;
  if (raw !== null && typeof raw === 'object') {
    return Object.values(raw as Record<string, unknown>).filter((v) => v != null).length;
  }
  return 0;
}

/** Lenient mailbox check — enough to refuse obvious garbage ('', 'player',
 *  strings with spaces/newlines) before handing an address to nodemailer. */
export function isValidEmail(address: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address);
}

/** The Support/MailLog entry shape (spec: "log sends to Support/MailLog (to,
 *  subject, ok/err, at)"). `at` is whatever timestamp the caller supplies —
 *  the trigger passes the RTDB server-timestamp sentinel. */
export function mailLogEntry(input: {
  to: string; subject: string; ok: boolean; err?: string; at: unknown;
}): Record<string, unknown> {
  return {
    To: input.to,
    Subject: input.subject,
    Ok: input.ok,
    ...(input.err ? { Err: input.err } : {}),
    At: input.at,
  };
}

// ---------------------------------------------------------------------------
// Subjects (all pass through sanitizeSubject — header-injection safe)
// ---------------------------------------------------------------------------

export function ackSubject(num: string): string {
  return sanitizeSubject(`Thanks — your Infinite Sports reference is #${num}`);
}

export function newTicketSubject(num: string, category: string, name: string): string {
  return sanitizeSubject(
    `[Infinite Sports ${categoryLabel(category)}] from ${name} (ref #${num})`,
  );
}

export function replySubject(num: string, name: string): string {
  return sanitizeSubject(`Re: ticket #${num} — reply from ${name}`);
}

export function closingSubject(num: string): string {
  return sanitizeSubject(`Your Infinite Sports ticket #${num} is closed`);
}

// ---------------------------------------------------------------------------
// Email bodies (HTML). Every user-sourced string is escaped here — callers
// pass raw values straight from RTDB.
// ---------------------------------------------------------------------------

const BRAND = '#D00000'; // infiniteSportsPrimaryColor (RGB 208,0,0)

function emailShell(inner: string): string {
  return `<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;` +
    `max-width:560px;margin:0 auto;padding:16px;color:#1a1a1a;">` +
    `<h2 style="color:${BRAND};margin:0 0 12px;">Infinite Sports</h2>${inner}` +
    `<p style="color:#888;font-size:12px;margin-top:24px;">` +
    `Infinite Sports support — this inbox is tended by humans (mostly).</p></div>`;
}

function quoteBlock(escapedHtml: string): string {
  return `<blockquote style="border-left:3px solid ${BRAND};margin:12px 0;` +
    `padding:8px 12px;background:#f7f7f7;color:#333;">${escapedHtml}</blockquote>`;
}

/** Acknowledgment email to the user on submit (spec decision #4, email 1 of
 *  exactly two): reference number, their category and their message. */
export function ackEmailHtml(input: {
  num: string; name: string; category: string; message: string;
}): string {
  const name = escapeHtml(input.name);
  return emailShell(
    `<p>Hi ${name || 'there'},</p>` +
    `<p>Thanks — your reference is <strong>#${escapeHtml(input.num)}</strong>.</p>` +
    `<p>We received your <strong>${escapeHtml(categoryLabel(input.category))}</strong>:</p>` +
    quoteBlock(escapeMultiline(input.message)) +
    `<p>Replies land in the app under <strong>My Tickets</strong>, and you&#39;ll get ` +
    `one more email from us when the ticket is closed.</p>`,
  );
}

/** New-ticket email to the support inbox: message first, then the captured
 *  context (platform, app version, screen, screenshot count, uid). */
export function newTicketEmailHtml(input: {
  num: string; name: string; email: string; uid: string; category: string;
  message: string; platform: string; appVersion: string; screen: string;
  screenshotCount: number;
}): string {
  const row = (label: string, value: string) =>
    `<tr><td style="padding:2px 12px 2px 0;color:#666;">${label}</td>` +
    `<td style="padding:2px 0;">${escapeHtml(value)}</td></tr>`;
  return emailShell(
    `<p><strong>${escapeHtml(categoryLabel(input.category))}</strong> ticket ` +
    `<strong>#${escapeHtml(input.num)}</strong> from ` +
    `<strong>${escapeHtml(input.name)}</strong> (${escapeHtml(input.email)})</p>` +
    quoteBlock(escapeMultiline(input.message)) +
    `<table style="font-size:13px;border-collapse:collapse;">` +
    row('Platform', input.platform) +
    row('App version', input.appVersion) +
    row('Screen', input.screen) +
    row('Screenshots', String(input.screenshotCount)) +
    row('Uid', input.uid) +
    `</table>` +
    `<p style="color:#666;font-size:13px;">Reply-To is set to the user — but app ` +
    `replies go through the Manager Support inbox.</p>`,
  );
}

/** User-reply email to the support inbox (ticket reopened -> 'open'). */
export function replyNoticeEmailHtml(input: {
  num: string; name: string; text: string;
}): string {
  return emailShell(
    `<p><strong>${escapeHtml(input.name)}</strong> replied on ticket ` +
    `<strong>#${escapeHtml(input.num)}</strong> (status is back to <strong>Open</strong>):</p>` +
    quoteBlock(escapeMultiline(input.text)),
  );
}

/** Closing email to the user (spec decision #4, email 2 of exactly two):
 *  outcome phrasing + the ClosedNote (the joke) verbatim — escaped, never
 *  reworded. */
export function closingEmailHtml(input: {
  num: string; name: string; outcome: string; note: string;
}): string {
  const name = escapeHtml(input.name);
  return emailShell(
    `<p>Hi ${name || 'there'},</p>` +
    `<p>Your ticket <strong>#${escapeHtml(input.num)}</strong> is closed. ` +
    `${escapeHtml(closedOutcomePhrase(input.outcome))}</p>` +
    (input.note
      ? quoteBlock(`<em>${escapeMultiline(input.note)}</em>`)
      : '') +
    `<p>The full thread stays in the app under <strong>My Tickets</strong>. ` +
    `Thanks for making the league better.</p>`,
  );
}

// ---------------------------------------------------------------------------
// Canned joke bank (fallback when the Anthropic key is absent or the API
// call fails). Snarky / pop-culture-adjacent, playful never mean — the owner
// edits the box before sending anyway.
// ---------------------------------------------------------------------------

// Flavored on the owner's comedy canon (JOKE_FRANCHISES) — original lines
// riffing on the shows, never verbatim quotes.
export const JOKE_BANK: Record<CategoryKey, string[]> = {
  suggestion: [
    "Your idea is going on the whiteboard, right next to Kevin's famous chili incident report. We believe in this one more.",
    "Treat yo' self to some credit — this suggestion just made the board, and our resident Ron Swanson grunted approvingly. Highest honor we offer.",
    "The committee has reviewed your idea and, unlike most things in Pawnee, it's actually getting built.",
  ],
  comment: [
    "Not that there's anything wrong with the app... but your point stands, and we're on it.",
    "60% of the time, that part works every time. Your comment is helping us fix the other 40%.",
    'Cool cool cool cool cool. Feedback logged — no doubt, no doubt, no doubt.',
  ],
  bug: [
    'The bug has been escorted from the building, Dwight-style: badge revoked, farewell party canceled.',
    'That bug had so much room for activities. It now has zero. Bunk beds were a bad idea anyway.',
    "So you're telling us there's a chance it comes back? No. No there is not. We checked twice.",
  ],
  help: [
    "We'll be there for you — clap, clap, clap, clap — your answer is waiting in the ticket thread.",
    'DO YOU UNDERSTAND THE WORDS COMING OUT OF OUR APP? You will now — we cleared it up.',
    'Allow ourselves to introduce... the answer. It was groovy, and it is in your thread, baby.',
  ],
  account: [
    'Your account went undercover for a while, 21 Jump Street style. We pulled it out, debriefed it, and it is back on duty.',
    "There's always money in the banana stand — and there's always a way back into your account. Access restored.",
    'Identity crisis resolved: unlike certain undercover agents in white, your account is exactly who it says it is.',
  ],
  other: [
    'GREAT SUCCESS! Your mysterious ticket has been dealt with. Very nice.',
    'We retraced the app\'s steps from last night, found the problem on the roof, and handled it. Classic.',
    'Thunder buddies for life — whatever that was, it is sorted now.',
  ],
};

/** Random canned joke for a category (unknown categories draw from 'other').
 *  `rand` is injectable for deterministic tests. */
export function cannedJoke(category: string, rand: () => number = Math.random): string {
  const bank = JOKE_BANK[normalizeCategory(category)];
  const idx = Math.min(bank.length - 1, Math.max(0, Math.floor(rand() * bank.length)));
  return bank[idx];
}

// ---------------------------------------------------------------------------
// LLM joke path (callable generateTicketJoke). The fetch is injected so the
// whole flow — happy path, API error, missing key, timeout — unit-tests
// without network or Firebase.
// ---------------------------------------------------------------------------

export const JOKE_MODEL = 'claude-haiku-4-5-20251001';
export const JOKE_TIMEOUT_MS = 8_000;

/** Owner-picked comedy canon (2026-10-14): the model riffs in the voice of
 *  whichever of these fits the ticket best. */
export const JOKE_FRANCHISES: string[] = [
  'The Office', 'Friends', 'The Hangover', 'White Chicks', 'Austin Powers',
  'The Big Bang Theory', 'Brooklyn Nine-Nine', 'Parks and Recreation',
  'Superbad', 'Step Brothers', 'Seinfeld',
  "It's Always Sunny in Philadelphia", 'Dumb and Dumber', 'Anchorman',
  '21 Jump Street', 'Modern Family', 'Borat', 'Tropic Thunder',
  'Arrested Development', 'Rush Hour', 'South Park', 'Family Guy',
  'The Dictator', 'Ted', 'Silicon Valley',
];

export const JOKE_SYSTEM_PROMPT =
  'You write the single closing one-liner for a sports-league support ticket. ' +
  'Pick whichever ONE of these comedies fits the ticket best and write an ' +
  'ORIGINAL line in its comedic voice (channel a signature character, ' +
  'catchphrase-style, or running gag — do not copy long quotes verbatim): ' +
  `${JOKE_FRANCHISES.join('; ')}. ` +
  "Match the ticket's category and content. One or two sentences max. " +
  'Snarky/sarcastic welcome; playful, never cruel or mocking of the user. ' +
  'No emoji spam (one at most). Reply with the one-liner only — no preamble, ' +
  'no quotes around it, no naming the show unless the line itself does.';

const JOKE_MESSAGE_MAX_CHARS = 1_500;

/** The user turn sent to the model: category + (truncated) ticket message. */
export function buildJokePrompt(category: string, message: string): string {
  const trimmed = message.length > JOKE_MESSAGE_MAX_CHARS
    ? `${message.slice(0, JOKE_MESSAGE_MAX_CHARS)}…`
    : message;
  return `Ticket category: ${categoryLabel(category)}\n` +
    `Ticket message:\n"""\n${trimmed}\n"""\n` +
    'Write the closing one-liner now.';
}

/** Minimal structural fetch so tests inject a fake and lib/ stays free of
 *  DOM lib types. Matches the global fetch signature where it matters. */
export type FetchLike = (url: string, init: {
  method: string;
  headers: Record<string, string>;
  body: string;
  signal?: AbortSignal;
}) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

/** Pulls the one-liner out of a Messages API response
 *  ({content: [{type:'text', text}]}); null when the shape is wrong/empty. */
export function parseAnthropicJoke(json: unknown): string | null {
  if (json === null || typeof json !== 'object') return null;
  const content = (json as Record<string, unknown>)['content'];
  if (!Array.isArray(content)) return null;
  for (const block of content) {
    if (block !== null && typeof block === 'object') {
      const text = (block as Record<string, unknown>)['text'];
      if (typeof text === 'string' && text.trim().length > 0) return text.trim();
    }
  }
  return null;
}

export interface JokeResult { joke: string; source: 'ai' | 'bank'; }

/** The generateTicketJoke core: Anthropic Messages API when a key exists,
 *  canned bank on missing key / API error / timeout. Never throws. */
export async function generateJoke(opts: {
  category: string;
  message: string;
  apiKey: string;
  fetchImpl?: FetchLike;
  timeoutMs?: number;
  rand?: () => number;
}): Promise<JokeResult> {
  const fallback = (): JokeResult => ({
    joke: cannedJoke(opts.category, opts.rand), source: 'bank',
  });
  if (!opts.apiKey) return fallback();

  const fetchImpl = opts.fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? JOKE_TIMEOUT_MS);
  try {
    const res = await fetchImpl('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': opts.apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: JOKE_MODEL,
        max_tokens: 150,
        system: JOKE_SYSTEM_PROMPT,
        messages: [{ role: 'user', content: buildJokePrompt(opts.category, opts.message) }],
      }),
      signal: controller.signal,
    });
    if (!res.ok) return fallback();
    const joke = parseAnthropicJoke(await res.json());
    return joke ? { joke, source: 'ai' } : fallback();
  } catch {
    return fallback();
  } finally {
    clearTimeout(timer);
  }
}
