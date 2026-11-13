// AI copywriter for the Manager's News desk + Message managers card (spec
// 2026-10-28 §3, §4.3, §4.5) — pure TS behind an injected fetch; the
// admin-gated callable writeFantasyCopy lives in src/fantasy_messages.ts.
//
// ONE CALL, THREE MODES (each with its own character limits):
//   post    — a News feed post            title ≤ 60, body ≤ 400
//   push    — the push announcing a post  title ≤ 40, body ≤ 110
//   message — a Message-managers push     title ≤ 40, body ≤ 140
//
// FACTS: the model sees ONLY the JSON user content built here — the tagged
// players' PlayerCard snapshots (news_cards.ts, built server-side from the
// season's nodes, never from the client), the owner's current title/body
// and an optional hint. Same tone rules as the autopilot drafts (news.ts):
// playful, never mean, stats-only.
//
// THE CALL mirrors news.ts generateNewsDrafts exactly: NEWS_MODEL, the
// Messages API headers, an 8s AbortController timeout, first text block.
// Reply contract: ONE JSON object {"title","body"} (stray fences tolerated),
// both non-empty, clamped to the mode limits at a word boundary. Anything
// else — blank key, nothing to write from, HTTP error, timeout, garbage — is
// null, never a throw (the callable maps null to HttpsError 'unavailable').

import { FetchLike } from '../support';
import {
  clampText, NEWS_BODY_MAX, NEWS_MODEL, NEWS_TIMEOUT_MS, NEWS_TITLE_MAX,
  parseNewsText, stripJsonFences,
} from './news';
import {
  buildPlayerCard, MAX_POST_PLAYERS, PlayerCard, seasonGoalsAssists,
} from './news_cards';
import { FantasyDb, fantasyRoot, isPlainMap } from './orchestration_db';

export type CopyMode = 'post' | 'push' | 'message';

export function isCopyMode(v: unknown): v is CopyMode {
  return v === 'post' || v === 'push' || v === 'message';
}

/** Character limits per mode (spec §4.5). post = the news drafts' limits. */
export const COPY_LIMITS: Readonly<Record<CopyMode, { title: number; body: number }>> = {
  post: { title: NEWS_TITLE_MAX, body: NEWS_BODY_MAX },
  push: { title: 40, body: 110 },
  message: { title: 40, body: 140 },
};

export interface CopyText {
  title: string;
  body: string;
}

// ── Text clamp ──────────────────────────────────────────────────────────────

// The grapheme / word-boundary clamp lives in news.ts (it also clamps the AI
// drafts, and news.ts cannot import this module without a cycle); re-exported
// so messages.ts and the tests keep importing it from here.
export { clampText };

// ── Prompt ──────────────────────────────────────────────────────────────────

const MODE_BRIEF: Record<CopyMode, string> = {
  post: 'a news post for the fantasy news feed in the app',
  push: 'a push notification that sends fantasy players to a news post; ' +
    'the body is one short sentence',
  message: 'a push notification from the league to its fantasy managers ' +
    '(for example a deadline change, a postponed match day or a price ' +
    'update); be clear first: managers must understand what changed and ' +
    'what to do',
};

/** The system prompt for [mode]: tone + facts rules (news.ts parity), how
 *  to read the cards, the mode's limits, and the JSON-object reply rule. */
export function copySystemPrompt(mode: CopyMode): string {
  const { title, body } = COPY_LIMITS[mode];
  return "You write copy for a recreational futsal fantasy league. You are " +
    `writing ${MODE_BRIEF[mode]}. Tone: playful and celebratory, NEVER ` +
    'mean — no mocking, no criticism of any player or manager. Use ONLY the ' +
    "facts in the JSON you are given (the tagged players' stat cards, the " +
    "current title and body, and the owner's hint): invent no facts, no " +
    'injuries, no quotes, no results, no extra numbers, and keep every ' +
    'date, time and number from the current text or the hint exactly as ' +
    'written. Card fields: priceTenths is the price in tenths of a million ' +
    '(75 = 7.5M), priceDeltaTenths the latest price move (5 = up 0.5M), ' +
    'gwPoints the fantasy points in gameweek gw, seasonPoints the fantasy ' +
    'points this season, ownershipPct the percent of managers who own the ' +
    'player, goals and assists the season totals; a missing field is ' +
    'unknown — never mention it. "template" is the kind of story: spotlight ' +
    "(one player's season), star (the standout of the week), price (price " +
    'moves), h2h (two players compared), dreamteam (team of the week); ' +
    'free, ai or null = any story the facts support. When a current title ' +
    'or body is given, improve it and keep its meaning; when a hint is ' +
    `given, follow it. "title" at most ${title} characters, "body" at most ` +
    `${body} characters. Reply with ONLY a JSON object {"title": string, ` +
    '"body": string} — no markdown fences, no commentary.';
}

function blankToNull(v: string | undefined): string | null {
  const t = (v ?? '').trim();
  return t.length > 0 ? t : null;
}

export interface CopyRequest {
  mode: CopyMode;
  /** News template ('spotlight' | 'star' | 'price' | 'h2h' | 'free' | ...). */
  template?: string;
  /** The tagged players' snapshots — the only stats the model may use. */
  cards: PlayerCard[];
  /** The owner's current text (to polish) and direction. */
  title?: string;
  body?: string;
  hint?: string;
}

/** The user content: the JSON of {mode, template, players, currentTitle,
 *  currentBody, hint} — every key always present, blanks as null. */
export function buildCopyPrompt(req: CopyRequest): string {
  return JSON.stringify({
    mode: req.mode,
    template: blankToNull(req.template),
    players: req.cards,
    currentTitle: blankToNull(req.title),
    currentBody: blankToNull(req.body),
    hint: blankToNull(req.hint),
  });
}

// ── Reply ───────────────────────────────────────────────────────────────────

/** The model's reply: one JSON object (stray fences tolerated) with
 *  non-empty string title + body, clamped to [mode]'s limits at a word
 *  boundary. Null for anything else (prose, an array, blanks). */
export function parseCopy(text: string, mode: CopyMode): CopyText | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stripJsonFences(text));
  } catch {
    return null;
  }
  if (!isPlainMap(parsed)) return null;
  const title = typeof parsed['title'] === 'string' ? parsed['title'].trim() : '';
  const body = typeof parsed['body'] === 'string' ? parsed['body'].trim() : '';
  if (!title || !body) return null;
  const limits = COPY_LIMITS[mode];
  return {
    title: clampText(title, limits.title, { wordBoundary: true }),
    body: clampText(body, limits.body, { wordBoundary: true }),
  };
}

// ── The call ────────────────────────────────────────────────────────────────

/** Writes one {title, body} for [req.mode]. Null — never a throw — on a
 *  blank key, nothing to write from (no cards and no title/body/hint: the
 *  stats-only rule would leave the model inventing), an API error, a
 *  timeout or an unusable reply. */
export async function writeCopy(opts: CopyRequest & {
  apiKey: string;
  fetchImpl?: FetchLike;
  timeoutMs?: number;
}): Promise<CopyText | null> {
  if (!opts.apiKey) return null;
  if (opts.cards.length === 0 && blankToNull(opts.title) === null &&
    blankToNull(opts.body) === null && blankToNull(opts.hint) === null) {
    return null;
  }
  const fetchImpl = opts.fetchImpl ?? (globalThis.fetch as unknown as FetchLike);
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(), opts.timeoutMs ?? NEWS_TIMEOUT_MS);
  try {
    const res = await fetchImpl('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': opts.apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: NEWS_MODEL,
        max_tokens: 600,
        system: copySystemPrompt(opts.mode),
        messages: [
          {
            role: 'user',
            content: buildCopyPrompt({
              mode: opts.mode, template: opts.template, cards: opts.cards,
              title: opts.title, body: opts.body, hint: opts.hint,
            }),
          },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const text = parseNewsText(await res.json());
    return text === null ? null : parseCopy(text, opts.mode);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ── Facts for the callable ──────────────────────────────────────────────────

/** The PlayerCards for the requested names (the writeFantasyCopy callable's
 *  facts): names trimmed, blanks and repeats dropped, built from the
 *  season's Players / PlayerTotals / PlayerWeeks / PriceChanges nodes and
 *  the `<sport>/<season>/Date` goal/assist tally (the autopilot drafts'
 *  sources); names that are not market players are dropped; at most
 *  MAX_POST_PLAYERS, in request order. No names -> [] without any read. */
export async function loadCopyCards(db: FantasyDb, args: {
  sport: string; season: string; names: string[];
}): Promise<PlayerCard[]> {
  const names = [...new Set(args.names.map((n) => n.trim()).filter((n) => n))];
  if (names.length === 0) return [];
  const root = fantasyRoot(args.sport, args.season);
  const src = {
    playersRaw: await db.read(`${root}/Players`),
    playerTotalsRaw: await db.read(`${root}/PlayerTotals`),
    playerWeeksRaw: await db.read(`${root}/PlayerWeeks`),
    priceChangesRaw: await db.read(`${root}/PriceChanges`),
    goalsAssists: seasonGoalsAssists(
      await db.read(`${args.sport}/${args.season}/Date`)),
  };
  return names
    .map((name) => buildPlayerCard(name, src))
    .filter((c): c is PlayerCard => c !== null)
    .slice(0, MAX_POST_PLAYERS);
}
