// AI news drafts + the Dream Team post (P4 Phase G) — pure logic with the
// Anthropic call behind an injected fetch, mirroring lib/support.ts
// generateJoke (same secret, same model family, same 8s abort). The only
// difference in failure policy: the joke falls back to a canned bank, news
// drafting writes NOTHING — a quiet week beats invented news, and finalize
// never blocks on the API (spec §13).
//
// NODE SHAPES (under Fantasy/<sport>/<season>):
//
// - News/Drafts/<key> = { Title, Body, Gw:int, CreatedAt:int,
//   Source:'ai'|'dreamteam', AutoPublishAt?:int } — the Manager approval
//   queue (admin-read/write per rules; the owner publishes, edits or
//   discards in P5). Keys are deterministic per gameweek (gw<g>ai<n>,
//   gw<g>dreamteam) — the NewsDrafted guard makes them once-only.
//
// - News/Published/<id> = { Title, Body, At:int } — the public feed row the
//   auto-publish step writes (publish-by-hand lands here through the
//   Manager, same shape).
//
// - Config/DreamTeamPost = { AutoPublish:bool (default false),
//   Weekday:string (default 'tuesday'), Hour:int (default 10, league time) }
//   — owner-editable (Manager P5). When AutoPublish is on, the Dream Team
//   draft carries AutoPublishAt = the next such league-local instant.
//
// THE ACTED-ON RULE (spec §13): the sweep auto-publishes a draft only while
// Source == 'dreamteam' AND AutoPublishAt is due. The Manager CLEARS
// AutoPublishAt on any edit (and swap-a-player counts as an edit) and
// deletes discarded drafts — so a draft the owner touched never publishes
// itself.

import { FetchLike } from '../support';
import { MarketPlayer } from './finalize_core';
import { isPacificDst, lockInstantUtc } from './league_time';
import { childEntries, isPlainMap, toIntLoose } from './orchestration_db';

export const NEWS_MODEL = 'claude-haiku-5-5';
export const NEWS_TIMEOUT_MS = 8_000;
export const NEWS_TITLE_MAX = 60;
export const NEWS_BODY_MAX = 400;

// ── Stats the model may write about (and nothing else) ─────────────────────

export interface NewsStats {
  gw: number;
  /** Best bonus-inclusive week score among eligible market players. */
  topScorer: { name: string; points: number } | null;
  /** The stored Dream Team rows (hub + post read the same node). */
  dreamTeam: Array<{ name: string; position: string; points: number }>;
  /** Biggest price moves of the most recent repriced week, in tenths. */
  riser: { name: string; deltaTenths: number } | null;
  faller: { name: string; deltaTenths: number } | null;
  /** Lowest two-week total — only offered when two weeks exist, and the
   *  prompt only allows kind encouragement (or silence) about it. */
  coldStreak: { name: string; lastTwoWeeksPoints: number } | null;
}

export function buildNewsStats(args: {
  gw: number;
  playerWeeksThisGw: Record<string, number>;
  playerWeeksPrevGw: Record<string, number> | null;
  players: Record<string, MarketPlayer>;
  dreamTeamRaw: unknown;
  priceChangesRaw: unknown;
}): NewsStats {
  const eligible = Object.entries(args.players)
    .filter(([, p]) => p.eligible)
    .map(([name]) => name)
    .sort();

  let topScorer: NewsStats['topScorer'] = null;
  for (const name of eligible) {
    const points = args.playerWeeksThisGw[name] ?? 0;
    if (topScorer === null || points > topScorer.points) {
      topScorer = { name, points };
    }
  }

  const dreamTeam: NewsStats['dreamTeam'] = [];
  if (isPlainMap(args.dreamTeamRaw)) {
    for (const [, row] of childEntries(args.dreamTeamRaw['Players'])) {
      if (!isPlainMap(row)) continue;
      dreamTeam.push({
        name: String(row['name'] ?? ''),
        position: String(row['position'] ?? ''),
        points: toIntLoose(row['points']),
      });
    }
  }

  let riser: NewsStats['riser'] = null;
  let faller: NewsStats['faller'] = null;
  for (const [name, row] of childEntries(args.priceChangesRaw)) {
    if (!isPlainMap(row)) continue; // skips the Manual flag
    const delta = toIntLoose(row['delta']);
    if (delta > 0 && (riser === null || delta > riser.deltaTenths)) {
      riser = { name, deltaTenths: delta };
    }
    if (delta < 0 && (faller === null || delta < faller.deltaTenths)) {
      faller = { name, deltaTenths: delta };
    }
  }

  let coldStreak: NewsStats['coldStreak'] = null;
  if (args.playerWeeksPrevGw !== null) {
    for (const name of eligible) {
      const total = (args.playerWeeksPrevGw[name] ?? 0) +
        (args.playerWeeksThisGw[name] ?? 0);
      if (coldStreak === null || total < coldStreak.lastTwoWeeksPoints) {
        coldStreak = { name, lastTwoWeeksPoints: total };
      }
    }
  }

  return { gw: args.gw, topScorer, dreamTeam, riser, faller, coldStreak };
}

// ── The Anthropic call (generateJoke pattern; injected fetch) ───────────────

export const NEWS_SYSTEM_PROMPT =
  "You draft short news blurbs for a recreational futsal fantasy league's " +
  'news feed. Tone: playful and celebratory, NEVER mean — no mocking, no ' +
  'criticism of any player or manager. If a cold-streak stat is provided, ' +
  'mention it only as kind encouragement, or skip it entirely. Use ONLY ' +
  'the stats provided: invent no facts, no injuries, no quotes, no extra ' +
  `numbers. Each draft: "title" at most ${NEWS_TITLE_MAX} characters, ` +
  `"body" at most ${NEWS_BODY_MAX} characters. Reply with ONLY a JSON ` +
  'array of 2 to 4 objects, each {"title": string, "body": string} — no ' +
  'markdown fences, no commentary.';

export function buildNewsPrompt(stats: NewsStats): string {
  return `Gameweek ${stats.gw} stats (JSON):\n` +
    `${JSON.stringify(stats, null, 1)}\n` +
    'Write the drafts now.';
}

/** First text block of a Messages API response (parseAnthropicJoke parity). */
export function parseNewsText(json: unknown): string | null {
  if (json === null || typeof json !== 'object') return null;
  const content = (json as Record<string, unknown>)['content'];
  if (!Array.isArray(content)) return null;
  for (const block of content) {
    if (block !== null && typeof block === 'object') {
      const text = (block as Record<string, unknown>)['text'];
      if (typeof text === 'string' && text.trim().length > 0) {
        return text.trim();
      }
    }
  }
  return null;
}

export interface NewsDraftText {
  title: string;
  body: string;
}

/** Validates the model's reply: a JSON array (stray markdown fences
 *  tolerated) of objects with non-empty string title/body. Items are
 *  length-clamped defensively; invalid items are dropped; more than 4 are
 *  cut. Null = nothing usable (refusal prose, garbage JSON, empty array) —
 *  the caller then writes NOTHING. */
export function parseNewsDrafts(text: string): NewsDraftText[] | null {
  let t = text.trim();
  if (t.startsWith('```')) {
    t = t.replace(/^```[a-zA-Z]*\s*/, '').replace(/\s*```$/, '');
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(t);
  } catch {
    return null;
  }
  if (!Array.isArray(parsed)) return null;
  const out: NewsDraftText[] = [];
  for (const item of parsed) {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) continue;
    const m = item as Record<string, unknown>;
    const title = typeof m['title'] === 'string' ? m['title'].trim() : '';
    const body = typeof m['body'] === 'string' ? m['body'].trim() : '';
    if (!title || !body) continue;
    out.push({
      title: title.slice(0, NEWS_TITLE_MAX),
      body: body.slice(0, NEWS_BODY_MAX),
    });
    if (out.length === 4) break;
  }
  return out.length > 0 ? out : null;
}

/** The drafting call. Null — and ONLY null — on blank key, API error,
 *  timeout or an unusable reply; never throws (finalize must never block,
 *  spec §13). */
export async function generateNewsDrafts(opts: {
  stats: NewsStats;
  apiKey: string;
  fetchImpl?: FetchLike;
  timeoutMs?: number;
}): Promise<NewsDraftText[] | null> {
  if (!opts.apiKey) return null;
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
        max_tokens: 1200,
        system: NEWS_SYSTEM_PROMPT,
        messages: [
          { role: 'user', content: buildNewsPrompt(opts.stats) },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const text = parseNewsText(await res.json());
    return text === null ? null : parseNewsDrafts(text);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ── Dream Team post + auto-publish schedule ─────────────────────────────────

export interface DreamTeamPostConfig {
  autoPublish: boolean;
  weekday: number; // Dart convention: Monday=1 .. Sunday=7
  hour: number; // league-local
}

const WEEKDAY_BY_NAME: Record<string, number> = {
  monday: 1, tuesday: 2, wednesday: 3, thursday: 4,
  friday: 5, saturday: 6, sunday: 7,
};

/** Config/DreamTeamPost with the spec §13 defaults: auto-publish OFF until
 *  the owner opts in; the stock schedule is Tuesday 10:00 league time. */
export function dreamTeamPostConfigFrom(raw: unknown): DreamTeamPostConfig {
  const m = isPlainMap(raw) ? raw : {};
  const weekday =
    WEEKDAY_BY_NAME[String(m['Weekday'] ?? '').trim().toLowerCase()] ?? 2;
  const hour = toIntLoose(m['Hour']);
  return {
    autoPublish: m['AutoPublish'] === true,
    weekday,
    hour: hour >= 0 && hour <= 23 && m['Hour'] != null ? hour : 10,
  };
}

/** League-local calendar date (as a UTC-midnight Date) of an instant. */
function leagueLocalDate(nowUtc: Date): Date {
  const guess = new Date(nowUtc.getTime() - 8 * 3_600_000);
  const guessDay = new Date(Date.UTC(
    guess.getUTCFullYear(), guess.getUTCMonth(), guess.getUTCDate()));
  const offset = isPacificDst(guessDay) ? 7 : 8;
  const local = new Date(nowUtc.getTime() - offset * 3_600_000);
  return new Date(Date.UTC(
    local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
}

/** The next strictly-future instant of [weekday] at [hour]:00 league time
 *  (e.g. "Tuesday 10 AM"). Shares lockInstantUtc with the deadline engine,
 *  so DST handling is identical to the lock math. */
export function nextLeagueWeekdayInstantUtc(
  nowUtc: Date, weekday: number, hour: number,
): Date {
  const start = leagueLocalDate(nowUtc);
  for (let d = 0; d < 9; d++) {
    const day = new Date(start.getTime() + d * 86_400_000);
    const dartDay = day.getUTCDay() === 0 ? 7 : day.getUTCDay();
    if (dartDay !== weekday) continue;
    const key = `${String(day.getUTCMonth() + 1).padStart(2, '0')}` +
      `${String(day.getUTCDate()).padStart(2, '0')}${day.getUTCFullYear()}`;
    const instant = lockInstantUtc(key, hour);
    if (instant.getTime() > nowUtc.getTime()) return instant;
  }
  /* istanbul ignore next -- every weekday occurs twice within 9 days */
  throw new Error('nextLeagueWeekdayInstantUtc found no instant');
}

/** The auto-built Team of the Week draft (spec §13): a structured post the
 *  app renders natively, from the SAME stored DreamTeam node the hub shows.
 *  Null when the node holds no players (nothing worth posting). */
export function buildDreamTeamDraft(args: {
  gw: number;
  dreamTeamRaw: unknown;
  nowMs: number;
  autoPublishAtMs: number | null;
}): Record<string, unknown> | null {
  const rows: string[] = [];
  if (isPlainMap(args.dreamTeamRaw)) {
    for (const [, row] of childEntries(args.dreamTeamRaw['Players'])) {
      if (!isPlainMap(row)) continue;
      rows.push(`${String(row['name'] ?? '')} ` +
        `(${String(row['position'] ?? '')}) ${toIntLoose(row['points'])}`);
    }
  }
  if (rows.length === 0) return null;
  return {
    Title: `Team of the Week — GW${args.gw}`,
    Body: rows.join(' · '),
    Gw: args.gw,
    CreatedAt: args.nowMs,
    Source: 'dreamteam',
    ...(args.autoPublishAtMs !== null
      ? { AutoPublishAt: args.autoPublishAtMs } : {}),
  };
}

/** The acted-on rule, decided: publish only a draft still carrying
 *  Source 'dreamteam' and a due AutoPublishAt. An admin edit cleared
 *  AutoPublishAt; a discard deleted the draft; an 'ai' draft never
 *  auto-publishes. */
export function shouldAutoPublish(draftRaw: unknown, nowMs: number): boolean {
  if (!isPlainMap(draftRaw)) return false;
  if (String(draftRaw['Source'] ?? '') !== 'dreamteam') return false;
  const at = draftRaw['AutoPublishAt'];
  return typeof at === 'number' && at <= nowMs;
}
