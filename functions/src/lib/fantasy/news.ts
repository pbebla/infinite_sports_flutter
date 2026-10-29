// AI news drafts + the Dream Team post (P4 Phase G; News desk 2.0 autopilot,
// spec 2026-10-28 §4.1/§4.4) — pure logic with the Anthropic call behind an
// injected fetch, mirroring lib/support.ts generateJoke (same secret, same
// model family, same 8s abort). The only difference in failure policy: the
// joke falls back to a canned bank, news drafting writes NOTHING — a quiet
// week beats invented news, and finalize never blocks on the API (spec §13).
//
// NODE SHAPES (under Fantasy/<sport>/<season>; additive — older rows
// without the 2.0 fields stay valid):
//
// - News/Drafts/<key> = { Title, Body, Gw?:int, CreatedAt:int,
//   Source:'ai'|'dreamteam'|'owner', AutoPublishAt?:int,
//   Template?:'spotlight'|'star'|'price'|'h2h'|'free'|'dreamteam'|'ai',
//   Players?:{"0":PlayerCard,..}, Push?:{Title,Body,Audience}, PhotoUrl?,
//   EditedAt? } — the Manager approval queue (admin-read/write per rules).
//   Server keys are deterministic per gameweek (gw<g>ai<n>, gw<g>dreamteam)
//   — the NewsDrafted guard makes them once-only; the Manager adds 'owner'
//   drafts (scheduled posts). PlayerCard = news_cards.ts.
//
// - News/Published/<id> = { Title, Body, At:int, Template?, Gw?, Players?,
//   Push?, PhotoUrl? } — the public feed row (the sweep's auto-publish and
//   the Manager's publish write the same shape).
//
// - Config/NewsAutopilot = { Enabled:bool (default TRUE — automation
//   first; only an explicit false turns it off), Weekday:string (default
//   'tuesday'), Hour:int (default 10, league time) } — owner-editable in
//   the Manager. When enabled, EVERY server-built draft carries
//   AutoPublishAt = the next such league-local instant. The legacy
//   Config/DreamTeamPost {AutoPublish, Weekday, Hour} is read as a fallback
//   while NewsAutopilot is absent (AutoPublish -> Enabled).
//
// THE AUTO-PUBLISH RULE (spec §4.4): the sweep publishes ANY draft — every
// Source — whose numeric AutoPublishAt is due. The schedule is always
// owner-visible and owner-controlled: the Manager's Auto-publish switch
// writes or removes AutoPublishAt, and a discard deletes the draft.

import { FetchLike } from '../support';
import { MarketPlayer } from './finalize_core';
import { isPacificDst, lockInstantUtc } from './league_time';
import { PlayerCard, cardsNode } from './news_cards';
import { childEntries, isPlainMap, toIntLoose } from './orchestration_db';
import { WEEKDAYS } from './pushes';

export const NEWS_MODEL = 'claude-haiku-5-5';
export const NEWS_TIMEOUT_MS = 8_000;
export const NEWS_TITLE_MAX = 60;
export const NEWS_BODY_MAX = 400;
/** Players an AI draft may tag (spec §4.4: 0–3). */
export const NEWS_PLAYERS_MAX = 3;

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

/** Every player name the stats JSON shows the model — the only names an AI
 *  draft may tag (spec §4.4: "must be from the stats it was given"). */
export function newsStatsNames(stats: NewsStats): Set<string> {
  const names = new Set<string>();
  for (const n of [
    stats.topScorer?.name, stats.riser?.name, stats.faller?.name,
    stats.coldStreak?.name, ...stats.dreamTeam.map((r) => r.name),
  ]) {
    if (n) names.add(n);
  }
  return names;
}

// ── The Anthropic call (generateJoke pattern; injected fetch) ───────────────

export const NEWS_SYSTEM_PROMPT =
  "You draft short news blurbs for a recreational futsal fantasy league's " +
  'news feed. Tone: playful and celebratory, NEVER mean — no mocking, no ' +
  'criticism of any player or manager. If a cold-streak stat is provided, ' +
  'mention it only as kind encouragement, or skip it entirely. Use ONLY ' +
  'the stats provided: invent no facts, no injuries, no quotes, no extra ' +
  `numbers. Each draft: "title" at most ${NEWS_TITLE_MAX} characters, ` +
  `"body" at most ${NEWS_BODY_MAX} characters, "players" a list of the 0 ` +
  `to ${NEWS_PLAYERS_MAX} players the draft is about, each spelled exactly ` +
  'as a "name" in the stats JSON (never anyone who is not in it). Reply ' +
  'with ONLY a JSON array of 2 to 4 objects, each {"title": string, ' +
  '"body": string, "players": string[]} — no markdown fences, no ' +
  'commentary.';

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
  /** Names the draft tags (0–3, display order); [] when none. */
  players: string[];
}

/** The model's "players" list: strings only, trimmed, blanks and repeats
 *  dropped, at most [NEWS_PLAYERS_MAX]; anything but a list = none. */
function parseDraftPlayers(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const out: string[] = [];
  for (const v of raw) {
    if (typeof v !== 'string') continue;
    const name = v.trim();
    if (!name || out.includes(name)) continue;
    out.push(name);
    if (out.length === NEWS_PLAYERS_MAX) break;
  }
  return out;
}

/** Validates the model's reply: a JSON array (stray markdown fences
 *  tolerated) of objects with non-empty string title/body (+ an optional
 *  "players" name list). Items are length-clamped defensively; invalid
 *  items are dropped; more than 4 are cut. Null = nothing usable (refusal
 *  prose, garbage JSON, empty array) — the caller then writes NOTHING. */
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
      players: parseDraftPlayers(m['players']),
    });
    if (out.length === 4) break;
  }
  return out.length > 0 ? out : null;
}

/** The drafting call. Null — and ONLY null — on blank key, API error,
 *  timeout or an unusable reply; never throws (finalize must never block,
 *  spec §13). Tagged players the stats never showed the model are dropped
 *  (newsStatsNames) — the caller still drops non-market names when it
 *  builds the cards. */
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
    const drafts = text === null ? null : parseNewsDrafts(text);
    if (drafts === null) return null;
    const allowed = newsStatsNames(opts.stats);
    return drafts.map((d) => ({
      ...d, players: d.players.filter((n) => allowed.has(n)),
    }));
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

// ── Autopilot config + schedule (spec §4.4) ─────────────────────────────────

export interface NewsAutopilotConfig {
  enabled: boolean;
  weekday: number; // Dart convention: Monday=1 .. Sunday=7
  hour: number; // league-local
}

const WEEKDAY_BY_NAME: Record<string, number> = {
  monday: 1, tuesday: 2, wednesday: 3, thursday: 4,
  friday: 5, saturday: 6, sunday: 7,
};

/** The autopilot for the season: Config/NewsAutopilot when it is a map,
 *  else the legacy Config/DreamTeamPost map (its AutoPublish flag reads as
 *  Enabled), else the defaults — ENABLED (automation first), Tuesday 10:00
 *  league time. Only an explicit `false` turns it off; a garbage weekday or
 *  hour falls back per field. */
export function newsAutopilotConfigFrom(
  newsAutopilotRaw: unknown, legacyDreamTeamPostRaw: unknown,
): NewsAutopilotConfig {
  let m: Record<string, unknown> = {};
  let enabled = true;
  if (isPlainMap(newsAutopilotRaw)) {
    m = newsAutopilotRaw;
    enabled = m['Enabled'] !== false;
  } else if (isPlainMap(legacyDreamTeamPostRaw)) {
    m = legacyDreamTeamPostRaw;
    enabled = m['AutoPublish'] !== false;
  }
  const weekday =
    WEEKDAY_BY_NAME[String(m['Weekday'] ?? '').trim().toLowerCase()] ?? 2;
  const hour = toIntLoose(m['Hour']);
  return {
    enabled,
    weekday,
    hour: hour >= 0 && hour <= 23 && m['Hour'] != null ? hour : 10,
  };
}

/** League-local wall clock of an instant, as a Date whose UTC fields read
 *  the league time (America/Los_Angeles via isPacificDst — the same
 *  offset rule as the lock math). */
function leagueWallClock(instantUtc: Date): Date {
  const guess = new Date(instantUtc.getTime() - 8 * 3_600_000);
  const guessDay = new Date(Date.UTC(
    guess.getUTCFullYear(), guess.getUTCMonth(), guess.getUTCDate()));
  const offset = isPacificDst(guessDay) ? 7 : 8;
  return new Date(instantUtc.getTime() - offset * 3_600_000);
}

/** League-local calendar date (as a UTC-midnight Date) of an instant. */
function leagueLocalDate(nowUtc: Date): Date {
  const local = leagueWallClock(nowUtc);
  return new Date(Date.UTC(
    local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()));
}

/** "Tue 10:00 AM" — short weekday + h:mm AM/PM of an instant in league
 *  time (the admin heads-up's publish time). */
export function formatLeagueWeekdayTime(instantUtc: Date): string {
  const local = leagueWallClock(instantUtc);
  const h = local.getUTCHours();
  const h12 = h % 12 === 0 ? 12 : h % 12;
  const mm = String(local.getUTCMinutes()).padStart(2, '0');
  return `${WEEKDAYS[local.getUTCDay()]} ${h12}:${mm} ${h < 12 ? 'AM' : 'PM'}`;
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

// ── Dream Team post ─────────────────────────────────────────────────────────

export const DREAM_TEAM_PUSH_TITLE = 'Team of the Week is out';

/** The stored Dream Team's player names in stored (display) order — the
 *  names the post's player cards are built for. Blank names skipped. */
export function dreamTeamNames(dreamTeamRaw: unknown): string[] {
  if (!isPlainMap(dreamTeamRaw)) return [];
  const out: string[] = [];
  for (const [, row] of childEntries(dreamTeamRaw['Players'])) {
    if (!isPlainMap(row)) continue;
    const name = String(row['name'] ?? '').trim();
    if (name) out.push(name);
  }
  return out;
}

/** The auto-built Team of the Week draft (spec §13, §4.4): a structured
 *  post the app renders natively, from the SAME stored DreamTeam node the
 *  hub shows. [cards] = the snapshots for dreamTeamNames(dreamTeamRaw), in
 *  that order (null = not a market player, dropped); the Players node is
 *  omitted when none resolve. Carries the default managers push. Null when
 *  the node holds no players (nothing worth posting). */
export function buildDreamTeamDraft(args: {
  gw: number;
  dreamTeamRaw: unknown;
  nowMs: number;
  autoPublishAtMs: number | null;
  cards: ReadonlyArray<PlayerCard | null | undefined>;
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
  const players = cardsNode(args.cards);
  return {
    Title: `Team of the Week — GW${args.gw}`,
    Body: rows.join(' · '),
    Gw: args.gw,
    CreatedAt: args.nowMs,
    Source: 'dreamteam',
    Template: 'dreamteam',
    ...(players !== null ? { Players: players } : {}),
    Push: {
      Title: DREAM_TEAM_PUSH_TITLE,
      Body: `GW${args.gw}'s best five are in — see who made it.`,
      Audience: 'managers',
    },
    ...(args.autoPublishAtMs !== null
      ? { AutoPublishAt: args.autoPublishAtMs } : {}),
  };
}

// ── Auto-publish ────────────────────────────────────────────────────────────

/** The auto-publish rule (spec §4.4): ANY draft — every Source — whose
 *  AutoPublishAt is a number that is due. No AutoPublishAt = waiting for
 *  the owner (autopilot off, or the Manager's Auto-publish switch is off);
 *  a discard deleted the draft. */
export function shouldAutoPublish(draftRaw: unknown, nowMs: number): boolean {
  if (!isPlainMap(draftRaw)) return false;
  const at = draftRaw['AutoPublishAt'];
  return typeof at === 'number' && Number.isFinite(at) && at <= nowMs;
}

/** The News/Published row for a draft published at [nowMs]: Title, Body,
 *  At, plus Template, Gw, Players, Push and PhotoUrl when the draft has
 *  them (spec §4.1 — Source, AutoPublishAt, CreatedAt and EditedAt stay
 *  queue-only). */
export function publishedRowFromDraft(
  draft: Record<string, unknown>, nowMs: number,
): Record<string, unknown> {
  const row: Record<string, unknown> = {
    Title: String(draft['Title'] ?? ''),
    Body: String(draft['Body'] ?? ''),
    At: nowMs,
  };
  for (const key of ['Template', 'Gw', 'Players', 'Push', 'PhotoUrl']) {
    if (draft[key] != null) row[key] = draft[key];
  }
  return row;
}
