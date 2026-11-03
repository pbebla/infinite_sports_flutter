// Infinite Fantasy — READ-ONLY dress rehearsal of the server pipeline against
// the real Futsal Season 15 data (2026-10-28).
//
// WHAT IT DOES
//   1. GETs a snapshot of Futsal/15 (Date, Line Ups, Teams, Finished) and
//      Fantasy/Futsal/15 (Config, Players, Voided) from the public REST
//      endpoint, once, and caches it in tools/rehearsal_out/snapshot.json.
//   2. Seeds an in-memory RTDB emulation (OverlayDb) with it. Config's
//      lockOverride is switched to 'auto' IN MEMORY ONLY (the live sandbox
//      says 'open').
//   3. Replays the whole season on a simulated clock through the REAL
//      production entry points (runLifecycleSweep every 15 minutes,
//      maybeFinalizeGame on every game-final write, runMondayReprice every
//      Monday 10:00 league time, recordSquadSave on every Squads/<uid> write)
//      with six synthetic managers playing the client role. Their money is
//      the fan app's FPL-rule squad draft (client_draft_money.ts — spec §4
//      selling): a kept or re-added baseline player at his Baselines/<uid>
//      price, a sale banked at sellPriceTenths(paid, today), room = budget +
//      realized − spent — so an honest synthetic save is never a squad the
//      lock judge calls overBudget.
//   4. Cross-checks every number against an independent recomputation with
//      the pure engine functions, asserts the pipeline invariants, and
//      surveys the real data for quality problems.
//
// SAFETY CONTRACT (this tool can never change the production database)
//   - The only network traffic is HTTP GET to the public REST endpoint,
//     before the simulation starts. A guard wraps globalThis.fetch: any
//     method other than GET, or any other host, throws; once the snapshot
//     is loaded ALL network access throws (so even code paths inside the
//     imported pipeline could not reach the network).
//   - No auth token is ever sent; a path answering 401/403 is reported and
//     skipped.
//   - firebase-admin is never imported. Every pipeline write lands in the
//     in-memory overlay and is logged to rehearsal_out/captured_writes.json.
//
// RUN (from functions/):
//   npm run rehearse:s15                live GET snapshot (cached), then replay
//   npm run rehearse:s15 -- --offline   replay from the cached snapshot only
//
// REUSE: the replay is also exported as runReplay() for the test-season
// fill tool (fill_test_season.ts), which replays the season with 20 made-up
// managers (+ the real managers' saved squads) and hands back the final
// in-memory Fantasy/Futsal/15 subtree. Importing this module runs nothing.

import * as fs from 'fs';
import * as path from 'path';
import { ClientDraftMoney, clientDraftMoney } from './client_draft_money';
import { fakeManagerDefs, fakeManagerRow } from './fill_test_season_logic';
import { pushBadgeAward } from '../src/lib/fantasy/badge_push';
import { awardBonus, bpsScore } from '../src/lib/fantasy/bps';
import {
  configFromMap, configToMap, FANTASY_POSITIONS, FantasyConfig, FantasyPosition,
  futsalDefault,
} from '../src/lib/fantasy/fantasy_config';
import { deriveGameweeks, Gameweek } from '../src/lib/fantasy/gameweeks';
import { lockInstantUtc } from '../src/lib/fantasy/league_time';
import {
  FantasyJobDeps, FantasyLogger, maybeFinalizeGame, recordSquadSave,
  runLifecycleSweep, runMondayReprice,
} from '../src/lib/fantasy/orchestration';
import { FantasyDb, FantasyTxResult } from '../src/lib/fantasy/orchestration_db';
import { PlayerGameStats, playedGame } from '../src/lib/fantasy/player_game_stats';
import { applyDelta, openingPrices, repriceDeltas } from '../src/lib/fantasy/pricing';
import { FantasyPusher } from '../src/lib/fantasy/pushes';
import { scorePlayerGame, scorePlayerWeek } from '../src/lib/fantasy/scoring';
import { realizedOf, sellPriceTenths } from '../src/lib/fantasy/selling';
import {
  FantasySquad, spentTenths, squadFromMap, squadToMap,
} from '../src/lib/fantasy/squad';
import { PlayerWeek, scoreSquadWeek, totalTenths } from '../src/lib/fantasy/squad_week';
import {
  integrityMarketOf, squadIntegrityIssues,
} from '../src/lib/fantasy/squad_integrity';
import { mapGameToStats } from '../src/lib/fantasy/stats_mapper';

/* eslint-disable @typescript-eslint/no-explicit-any */

// ═════════════════════════════════════════════════════════════════════════
// A. Constants, helpers, network guard, snapshot
// ═════════════════════════════════════════════════════════════════════════

const SPORT = 'Futsal';
const SEASON = '15';
const LEAGUE = `${SPORT}/${SEASON}`;
const F = `Fantasy/${SPORT}/${SEASON}`;
export const DB_URL = 'https://infinite-sports-app.firebaseio.com';
// `${LEAGUE}/Finished` (the league's season-over flag) lets the replay award
// the season-end badges (spec 2026-10-30 §2). A cached snapshot taken before
// it was listed simply lacks it: the replay then plays a season that is not
// flagged over (no season-end badges) — the console says so.
export const READ_PATHS = [
  `${LEAGUE}/Date`, `${LEAGUE}/Line Ups`, `${LEAGUE}/Teams`, `${LEAGUE}/Finished`,
  `${F}/Config`, `${F}/Players`, `${F}/Voided`,
];
const FUNCTIONS_DIR = process.cwd();
const OUT_DIR = path.join(FUNCTIONS_DIR, 'tools', 'rehearsal_out');
const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

type Json = any;

function isMap(v: unknown): v is Record<string, any> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

/** Children of a node that may be a map or an RTDB-coerced array (null
 *  holes skipped). Independent of the pipeline's childEntries on purpose. */
function entriesOf(node: unknown): Array<[string, any]> {
  if (Array.isArray(node)) {
    const out: Array<[string, any]> = [];
    node.forEach((v, i) => { if (v !== null && v !== undefined) out.push([String(i), v]); });
    return out;
  }
  if (isMap(node)) return Object.entries(node).filter(([, v]) => v !== null && v !== undefined);
  return [];
}

function childAt(node: unknown, key: string | number): any {
  if (Array.isArray(node)) return node[Number(key)] ?? null;
  if (isMap(node)) return node[String(key)] ?? null;
  return null;
}

function intLoose(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v);
  const s = String(v ?? '').trim();
  return /^[+-]?\d+$/.test(s) ? Number(s) : 0;
}

const iso = (ms: number): string => new Date(ms).toISOString();

function mmddyyyy(d: Date): string {
  return `${String(d.getUTCMonth() + 1).padStart(2, '0')}` +
    `${String(d.getUTCDate()).padStart(2, '0')}${d.getUTCFullYear()}`;
}

function prettyDate(key: string): string {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[Number(key.substring(0, 2)) - 1]} ${Number(key.substring(2, 4))}, ${key.substring(4)}`;
}

const money = (t: number): string => `$${(t / 10).toFixed(1)}M`;
const stable = (v: unknown): string => JSON.stringify(v);

const networkLog: Array<{ method: string; url: string; allowed: boolean; reason?: string }> = [];
let networkOpen = true;

/** Wrap globalThis.fetch: GET to the public REST host only, and nothing at
 *  all after the snapshot is loaded. Returns the restore function (puts the
 *  native fetch back — the fill tool needs it after the replay). */
export function installNetworkGuard(): () => void {
  const original = (globalThis as any).fetch;
  const native = original.bind(globalThis);
  networkOpen = true;
  (globalThis as any).fetch = async (input: any, init?: any): Promise<any> => {
    const url = typeof input === 'string' ? input : String(input?.url ?? input);
    const method = String(init?.method ?? 'GET').toUpperCase();
    let reason: string | undefined;
    if (!networkOpen) reason = 'network closed after the snapshot';
    else if (method !== 'GET') reason = `method ${method} not allowed`;
    else if (!url.startsWith(`${DB_URL}/`)) reason = 'host not allowed';
    networkLog.push({ method, url, allowed: reason === undefined, ...(reason ? { reason } : {}) });
    if (reason) throw new Error(`rehearsal network guard: ${reason} (${method} ${url})`);
    return native(url, { method: 'GET' });
  };
  return () => {
    (globalThis as any).fetch = original;
    networkOpen = true;
  };
}

async function restGet(p: string): Promise<{ ok: boolean; status: number; value?: unknown; body?: string }> {
  const url = `${DB_URL}/${p.split('/').map(encodeURIComponent).join('/')}.json`;
  const res = await (globalThis as any).fetch(url, { method: 'GET' });
  const text: string = await res.text();
  if (!res.ok) return { ok: false, status: res.status, body: text.slice(0, 300) };
  return { ok: true, status: res.status, value: JSON.parse(text) };
}

export interface Snapshot {
  fetchedAt: string;
  source: string;
  values: Record<string, unknown>;
  skipped: Array<{ path: string; status: number; body: string }>;
}

/** GET every READ_PATHS node (+ [opts.extraPaths]) and cache it in
 *  rehearsal_out/[opts.file] (default snapshot.json — the rehearsal's own
 *  cache; the fill tool keeps a separate one). Offline = the cache only.
 *  Only READ_PATHS values are ever seeded into the replay. */
export async function loadSnapshot(
  offline: boolean, opts: { file?: string; extraPaths?: string[] } = {},
): Promise<Snapshot> {
  const cachePath = path.join(OUT_DIR, opts.file ?? 'snapshot.json');
  if (offline) {
    if (!fs.existsSync(cachePath)) throw new Error(`--offline but no ${cachePath}`);
    return JSON.parse(fs.readFileSync(cachePath, 'utf8')) as Snapshot;
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const values: Record<string, unknown> = {};
  const skipped: Snapshot['skipped'] = [];
  for (const p of [...READ_PATHS, ...(opts.extraPaths ?? [])]) {
    const r = await restGet(p);
    if (r.ok) values[p] = r.value;
    else skipped.push({ path: p, status: r.status, body: r.body ?? '' });
  }
  const snap: Snapshot = { fetchedAt: new Date().toISOString(), source: DB_URL, values, skipped };
  fs.writeFileSync(cachePath, JSON.stringify(snap, null, 1));
  return snap;
}

// ═════════════════════════════════════════════════════════════════════════
// B. Read-only RTDB emulation (the injected FantasyDb)
// ═════════════════════════════════════════════════════════════════════════
//
// Faithful to the RTDB behaviors the pipeline depends on:
// - storage never holds arrays, nulls or empty maps (a set of [] or {} is a
//   removal; array elements become index keys);
// - reads hand back RTDB's coerced form: a map whose keys are all small
//   non-negative integers with maxKey < 2 * count comes back as a
//   null-padded array (gameweek-keyed nodes, picks, Breakdown...);
// - writeIfAbsent is a set-if-null claim (the transaction in fantasy_adapter);
//   transaction is the compare-and-set seam (undefined aborts, null removes);
// - read results are deep-frozen and structurally shared (persistent tree),
//   so the pipeline can never mutate stored state through a read.

const INT_KEY = /^(0|[1-9]\d*)$/;
// eslint-disable-next-line no-control-regex
const BAD_KEY = /[.#$[\]/\u0000-\u001F\u007F]/;

function splitPath(p: string): string[] {
  return p.split('/').filter((s) => s.length > 0);
}

function rtdbKeyOrder(a: string, b: string): number {
  const ai = INT_KEY.test(a) && Number(a) <= 2147483647;
  const bi = INT_KEY.test(b) && Number(b) <= 2147483647;
  if (ai && bi) return Number(a) - Number(b);
  if (ai !== bi) return ai ? -1 : 1;
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Key-order-insensitive JSON for "same value?" comparisons. */
function canon(v: unknown): string {
  const sortDeep = (x: unknown): unknown => {
    if (Array.isArray(x)) return x.map(sortDeep);
    if (isMap(x)) {
      const o: Record<string, unknown> = {};
      for (const k of Object.keys(x).sort()) o[k] = sortDeep(x[k]);
      return o;
    }
    return x;
  };
  return JSON.stringify(sortDeep(v));
}

function own(obj: Record<string, unknown>, key: string): unknown {
  return Object.prototype.hasOwnProperty.call(obj, key) ? obj[key] : undefined;
}

function toStorage(v: unknown): unknown {
  if (v === null || v === undefined) return null;
  if (Array.isArray(v)) {
    const o: Record<string, unknown> = {};
    v.forEach((x, i) => { const s = toStorage(x); if (s !== null) o[String(i)] = s; });
    return Object.keys(o).length > 0 ? Object.freeze(o) : null;
  }
  if (typeof v === 'object') {
    const o: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
      const s = toStorage(x);
      if (s !== null) o[k] = s;
    }
    return Object.keys(o).length > 0 ? Object.freeze(o) : null;
  }
  return v;
}

/** Problems the Admin SDK (or a client parser) would choke on. A top-level
 *  undefined is fine: the production adapter treats it as a removal. */
function auditValue(v: unknown, at: string, out: string[], top: boolean): string[] {
  if (v === undefined) {
    if (!top) out.push(`undefined at ${at}`);
    return out;
  }
  if (v === null) return out;
  switch (typeof v) {
    case 'number':
      if (!Number.isFinite(v)) out.push(`${v} at ${at}`);
      return out;
    case 'string':
    case 'boolean':
      return out;
    case 'object': {
      if (Array.isArray(v)) {
        v.forEach((x, i) => {
          if (x === undefined) out.push(`undefined at ${at}/${i}`);
          else auditValue(x, `${at}/${i}`, out, false);
        });
        return out;
      }
      const proto = Object.getPrototypeOf(v);
      if (proto !== Object.prototype && proto !== null) {
        out.push(`non-plain object at ${at}`);
        return out;
      }
      for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
        if (k.length === 0 || BAD_KEY.test(k)) out.push(`invalid RTDB key "${k}" at ${at}`);
        if (x === undefined) out.push(`undefined at ${at}/${k}`);
        else auditValue(x, `${at}/${k}`, out, false);
      }
      return out;
    }
    default:
      out.push(`${typeof v} at ${at}`);
      return out;
  }
}

function jsonSafe(v: unknown): unknown {
  if (v === undefined) return '__UNDEFINED__';
  if (typeof v === 'number' && !Number.isFinite(v)) return `__${v}__`;
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(jsonSafe);
  const o: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(v as Record<string, unknown>)) o[k] = jsonSafe(x);
  return o;
}

interface WriteRec {
  seq: number;
  at: string;
  atMs: number;
  job: string;
  op: 'write' | 'writeIfAbsent' | 'transaction';
  path: string;
  won?: boolean;
  value: unknown;
}

class OverlayDb implements FantasyDb {
  private root: unknown = null;
  private readonly memo = new WeakMap<object, unknown>();
  private seq = 0;
  nowMs = 0;
  job = 'setup';
  readCount = 0;
  readonly pipelineWrites: WriteRec[] = [];
  readonly simWrites: WriteRec[] = [];
  readonly violations: Array<{ seq: number; job: string; path: string; problem: string }> = [];

  // ── the FantasyDb seam the pipeline calls ──
  async read(p: string): Promise<unknown> {
    this.readCount++;
    return this.get(p);
  }

  async write(p: string, value: unknown): Promise<void> {
    this.capture(this.pipelineWrites, 'write', p, value);
    this.assign(p, value);
  }

  async writeIfAbsent(p: string, value: unknown): Promise<boolean> {
    const won = this.get(p) === null;
    this.capture(this.pipelineWrites, 'writeIfAbsent', p, value, won);
    if (won) this.assign(p, value);
    return won;
  }

  async transaction(
    p: string, update: (current: unknown) => unknown,
  ): Promise<FantasyTxResult> {
    // Reads are deep-frozen, so the update can never mutate stored state.
    const current = this.get(p);
    const next = update(current);
    if (next === undefined) return { committed: false, value: current };
    // null over an absent node is RTDB's no-op: nothing written.
    if (!(next === null && current === null)) {
      this.capture(this.pipelineWrites, 'transaction', p, next);
      this.assign(p, next);
    }
    return { committed: true, value: this.get(p) };
  }

  // ── simulation-side access (clients, live scoring, setup) ──
  simWrite(p: string, value: unknown): void {
    this.capture(this.simWrites, 'write', p, value);
    this.assign(p, value);
  }

  seed(p: string, value: unknown): void {
    this.assign(p, value);
  }

  get(p: string): unknown {
    let node: unknown = this.root;
    for (const part of splitPath(p)) {
      if (!isMap(node)) return null;
      node = own(node, part);
      if (node === undefined || node === null) return null;
    }
    return this.coerce(node);
  }

  private assign(p: string, value: unknown): void {
    const parts = splitPath(p);
    const leaf = toStorage(value);
    const rec = (node: unknown, i: number): unknown => {
      if (i === parts.length) return leaf;
      const base: Record<string, unknown> = isMap(node) ? node : {};
      const next = rec(own(base, parts[i]), i + 1);
      const copy: Record<string, unknown> = {};
      for (const k of Object.keys(base)) if (k !== parts[i]) copy[k] = base[k];
      if (next !== null) copy[parts[i]] = next;
      return Object.keys(copy).length > 0 ? Object.freeze(copy) : null;
    };
    this.root = rec(this.root, 0);
  }

  private coerce(node: unknown): unknown {
    if (!isMap(node)) return node;
    const hit = this.memo.get(node);
    if (hit !== undefined) return hit;
    const keys = Object.keys(node);
    let out: unknown;
    if (keys.length > 0 && keys.every((k) => INT_KEY.test(k) && Number(k) <= 2147483647)) {
      const max = Math.max(...keys.map(Number));
      if (max < 2 * keys.length) {
        const arr: unknown[] = new Array(max + 1).fill(null);
        for (const k of keys) arr[Number(k)] = this.coerce(node[k]);
        out = Object.freeze(arr);
      }
    }
    if (out === undefined) {
      // RTDB hands children back key-ordered (32-bit integer keys first,
      // numerically; then the rest lexicographically), never in write order.
      const o: Record<string, unknown> = {};
      for (const k of [...keys].sort(rtdbKeyOrder)) o[k] = this.coerce(node[k]);
      out = Object.freeze(o);
    }
    this.memo.set(node, out);
    return out;
  }

  private capture(list: WriteRec[], op: WriteRec['op'], p: string, value: unknown, won?: boolean): void {
    const seq = ++this.seq;
    if (list === this.pipelineWrites) {
      for (const problem of auditValue(value, p, [], true)) {
        this.violations.push({ seq, job: this.job, path: p, problem });
      }
      for (const seg of splitPath(p)) {
        if (BAD_KEY.test(seg)) {
          this.violations.push({ seq, job: this.job, path: p, problem: `invalid path segment "${seg}"` });
        }
      }
    }
    list.push({
      seq, at: iso(this.nowMs), atMs: this.nowMs, job: this.job, op, path: p,
      ...(won === undefined ? {} : { won }), value: jsonSafe(value),
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════
// C. Independent engine replay (pure engine functions, own composition)
// ═════════════════════════════════════════════════════════════════════════

interface MarketEntry {
  position: FantasyPosition;
  eligible: boolean;
  price: number;
  team: string;
}

function marketOf(playersNode: unknown, issues: string[]): Record<string, MarketEntry> {
  const out: Record<string, MarketEntry> = {};
  for (const [name, raw] of entriesOf(playersNode)) {
    if (!isMap(raw)) { issues.push(`Players/${name} is not a map`); continue; }
    const pos = String(raw['position'] ?? '');
    if (pos !== 'GK' && pos !== 'DEF' && pos !== 'ATT') {
      issues.push(`Players/${name} has unusable position "${pos}"`);
      continue;
    }
    out[name] = {
      position: pos, eligible: raw['eligible'] === true,
      price: intLoose(raw['priceTenths']), team: String(raw['teamName'] ?? ''),
    };
  }
  return out;
}

function absentNames(raw: unknown): string[] {
  return entriesOf(raw)
    .filter(([, v]) => v === false || (typeof v === 'string' && v.trim().toLowerCase() === 'false'))
    .map(([k]) => k);
}

function isScoreableFinal(g: unknown): g is Record<string, any> {
  return isMap(g) && intLoose(g['status']) === 2 &&
    String(g['Stage'] ?? '').trim().toLowerCase() !== 'friendly';
}

interface BonusAward {
  date: string; game: string; team: string; name: string; bonus: number; bps: number; market: boolean;
}

interface IndepWeek {
  gw: number;
  date: string;
  games: number;
  points: Record<string, number>;
  base: Record<string, number>;
  bonus: Record<string, number>;
  played: Record<string, boolean>;
  awards: BonusAward[];
  bothSides: Array<{ game: string; name: string }>;
}

/** One gameweek recomputed from scratch: every final non-friendly game, each
 *  side with its full roster present (absent-only node applied), engine
 *  mapper -> scorePlayerWeek, and a per-game BPS pool keyed by TEAM + name
 *  (so two different 'Guest's on opposite sides stay two people). */
function independentWeek(
  gw: Gameweek, dateNode: unknown, lineups: unknown,
  market: Record<string, MarketEntry>, cfg: FantasyConfig,
): IndepWeek {
  const statsByName: Record<string, PlayerGameStats[]> = {};
  const bonusByName: Record<string, number> = {};
  const awards: BonusAward[] = [];
  const bothSides: Array<{ game: string; name: string }> = [];
  let games = 0;
  for (const [idx, g] of entriesOf(dateNode)) {
    if (!isScoreableFinal(g)) continue;
    games++;
    const pool: Record<string, number> = {};
    const sideNames: Array<Set<string>> = [];
    for (const side of [1, 2]) {
      const team = g[`team${side}`];
      if (typeof team !== 'string' || team.length === 0) continue;
      const roster = isMap(lineups) && isMap(lineups[team]) ? Object.keys(lineups[team]) : [];
      const attendance: Record<string, boolean> = {};
      for (const n of roster) attendance[n] = true;
      for (const n of absentNames(g[`team${side}attendance`])) attendance[n] = false;
      const stats = mapGameToStats(g, { teamName: team, attendance });
      sideNames.push(new Set(Object.keys(stats)));
      for (const [name, s] of Object.entries(stats)) {
        (statsByName[name] ??= []).push(s);
        pool[`${team}@@${name}`] = bpsScore(s, cfg);
      }
    }
    if (sideNames.length === 2) {
      for (const n of sideNames[0]) if (sideNames[1].has(n)) bothSides.push({ game: `${gw.date}#${idx}`, name: n });
    }
    for (const [key, b] of Object.entries(awardBonus(pool))) {
      const [team, name] = key.split('@@');
      bonusByName[name] = (bonusByName[name] ?? 0) + b;
      awards.push({ date: gw.date, game: idx, team, name, bonus: b, bps: pool[key], market: name in market });
    }
  }
  const points: Record<string, number> = {};
  const base: Record<string, number> = {};
  const bonus: Record<string, number> = {};
  const played: Record<string, boolean> = {};
  for (const [name, p] of Object.entries(market)) {
    const list = statsByName[name] ?? [];
    base[name] = scorePlayerWeek(list, p.position, cfg).total;
    bonus[name] = bonusByName[name] ?? 0;
    points[name] = base[name] + bonus[name];
    // Same "played" as the engine's scorePlayerWeek (a forfeiting team's
    // players did not play — spec §8a; S15 has no forfeits).
    played[name] = list.some(playedGame);
  }
  return { gw: gw.number, date: gw.date, games, points, base, bonus, played, awards, bothSides };
}

/** tool/seed_fantasy_logic.dart seasonPointsByPlayer, reimplemented for the
 *  comparison only: EVERY game node under Date (no status / friendly
 *  filter), each team side with its full Line Ups roster present, BASE
 *  points only (no bonus), futsalDefault() config. */
function seedSemanticsTotals(
  dateNode: unknown, lineups: unknown, positionByName: Record<string, FantasyPosition>,
): { points: Record<string, number>; strays: string[] } {
  const cfg = futsalDefault();
  const rosterByTeam: Record<string, string[]> = {};
  for (const [team, lineup] of entriesOf(lineups)) {
    if (!isMap(lineup)) continue;
    for (const [name, info] of Object.entries(lineup)) {
      if (isMap(info)) (rosterByTeam[team] ??= []).push(name);
    }
  }
  const points: Record<string, number> = {};
  for (const name of Object.keys(positionByName)) points[name] = 0;
  const strays = new Set<string>();
  for (const [, games] of entriesOf(dateNode)) {
    for (const [, g] of entriesOf(games)) {
      if (!isMap(g)) continue;
      for (const teamKey of ['team1', 'team2']) {
        const team = g[teamKey] == null ? '' : String(g[teamKey]);
        if (team.length === 0) continue;
        const attendance: Record<string, boolean> = {};
        for (const n of rosterByTeam[team] ?? []) attendance[n] = true;
        const stats = mapGameToStats(g, { teamName: team, attendance });
        for (const [name, s] of Object.entries(stats)) {
          const pos = positionByName[name];
          if (pos === undefined) { strays.add(name); continue; }
          points[name] += scorePlayerGame(s, pos, cfg).total;
        }
      }
    }
  }
  return { points, strays: [...strays].sort() };
}

// ═════════════════════════════════════════════════════════════════════════
// D. Synthetic managers (client role) + their independent expected ledger
// ═════════════════════════════════════════════════════════════════════════

interface WeekPlan {
  transfers?: number;
  rebuild?: 'freeHit' | 'wildcard';
  /** Present = the manager deliberately toggles the chip this week (intent).
   *  Absent = the client keeps whatever chip the saved squad carries — since
   *  the one-week-chip fix that is always none after a played week (the
   *  rollover switches it off server-side). */
  chip?: string | null;
  benchSwap?: [string, string];
  captain?: string;
  vice?: string;
  undoOneNextDay?: boolean;
}

interface ManagerDef {
  uid: string;
  name: string;
  persona: string;
  initial: { picks: Array<[string, boolean]>; captain: string; vice: string };
  weeks: Record<number, WeekPlan>;
}

const MANAGERS: ManagerDef[] = [
  {
    uid: 'rh-m1-steady-eddie', name: 'Steady Eddie',
    persona: 'Builds once and never transfers; one free bench/armband shuffle in GW6.',
    initial: {
      picks: [['Brandon Zaya', false], ['Peter Zaya', false], ['Konstantin Bertos', false],
        ['Carlo Gewargis', false], ['Eli Derazizyan', false], ['Justin Chapa', true],
        ['Polus Gorgees', true]],
      captain: 'Carlo Gewargis', vice: 'Eli Derazizyan',
    },
    weeks: { 6: { benchSwap: ['Konstantin Bertos', 'Justin Chapa'], captain: 'Eli Derazizyan', vice: 'Carlo Gewargis' } },
  },
  {
    uid: 'rh-m2-triple-tina', name: 'Triple Tina',
    persona: 'Triple Captain in GW3, clears it in GW4, tries it AGAIN in GW5 (same chip set: must be voided), clears in GW6.',
    initial: {
      picks: [['Johnny Lugo', false], ['David Gewargis', false], ['Ilsin Baghdasarian', false],
        ['Bruno Siva', false], ['Yousif Audisho', false], ['Alex Shahbazi', true],
        ['Emad Yousif', true]],
      captain: 'Bruno Siva', vice: 'Yousif Audisho',
    },
    weeks: { 3: { chip: 'tripleCaptain' }, 4: { chip: null }, 5: { chip: 'tripleCaptain' }, 6: { chip: null } },
  },
  {
    uid: 'rh-m3-benchboost-bob', name: 'Bench Boost Bob',
    persona: 'Plays Bench Boost in GW4 and never opens the app again (pre-fix the chip stayed armed and re-fired at the first set-2 lock, GW7; chips are now one-week).',
    initial: {
      picks: [['Christian Lachinpour', false], ['Raman Nissan', false], ['Wilbert Givargiz', false],
        ['Ramsin Nissan', false], ['Parlevino Tamraz', false], ['Matthew Shamshayoo', true],
        ['Isaac Oshana', true]],
      captain: 'Ramsin Nissan', vice: 'Parlevino Tamraz',
    },
    weeks: { 4: { chip: 'benchBoost' } },
  },
  {
    uid: 'rh-m4-absent-captain-ava', name: 'Absent-Captain Ava',
    persona: 'Captain from Ashur, vice from Hakkari, never changes: GW11 Ashur has no game (vice inherits), GW12 neither plays (no armband).',
    initial: {
      picks: [['Christian Lachinpour', false], ['Raman Nissan', false], ['Ninos Sarkis', false],
        ['Ramsin Nissan', false], ['Netibel Shamoon', false], ['Alex Shahbazi', true],
        ['Robert Tatari', true]],
      captain: 'Ramsin Nissan', vice: 'Netibel Shamoon',
    },
    weeks: {},
  },
  {
    uid: 'rh-m5-churn-charlie', name: 'Churn Charlie',
    persona: 'Transfers every week from GW2: 4 (4 free), then 3 with only 2 free in GW3 (-4), and a 3-then-undo-to-2 re-save in GW6.',
    initial: {
      picks: [['Daniel Youkhanna', false], ['Adrian Oshana', false], ['Danipaul Madoo', false],
        ['Adorin Tuman', false], ['Isaac Oshana', false], ['Oniel Yousif', true],
        ['Ninos Rihan', true]],
      captain: 'Adorin Tuman', vice: 'Isaac Oshana',
    },
    weeks: {
      2: { transfers: 4 }, 3: { transfers: 3 }, 4: { transfers: 1 }, 5: { transfers: 2 },
      6: { transfers: 3, undoOneNextDay: true }, 7: { transfers: 1 }, 8: { transfers: 2 },
      9: { transfers: 1 }, 10: { transfers: 2 }, 11: { transfers: 1 }, 12: { transfers: 1 },
    },
  },
  {
    uid: 'rh-m6-freehit-fiona', name: 'Free Hit Fiona',
    persona: 'Drains her bank GW2-GW4, Free Hit in GW5 (all 7 replaced), one transfer from the restored squad in GW6, Wildcard in GW8, clears it in GW9. (Free Hit / Wildcard are server-supported but not yet selectable in the app.)',
    initial: {
      picks: [['Breymin Amir', false], ['Zaya Shahbaz Arami', false], ['Brandan Solomon', false],
        ['Netibel Shamoon', false], ['Brayan Elie', false], ['Mishel Ushana', true],
        ['Robert Tatari', true]],
      captain: 'Netibel Shamoon', vice: 'Brayan Elie',
    },
    weeks: {
      2: { transfers: 4 }, 3: { transfers: 2 }, 4: { transfers: 2 }, 5: { rebuild: 'freeHit' },
      6: { transfers: 1 }, 8: { rebuild: 'wildcard', transfers: 5 }, 9: { chip: null, transfers: 1 },
    },
  },
];

function cloneSquad(s: FantasySquad): FantasySquad {
  return { picks: s.picks.map((p) => ({ ...p })), captainId: s.captainId, viceId: s.viceId, chip: s.chip };
}

function countNew(a: FantasySquad, base: FantasySquad): number {
  const ids = new Set(base.picks.map((p) => p.playerId));
  return a.picks.filter((p) => !ids.has(p.playerId)).length;
}

function sameSquad(a: FantasySquad, b: FantasySquad): string[] {
  const diffs: string[] = [];
  const key = (s: FantasySquad) => s.picks
    .map((p) => `${p.playerId}|${p.position}|${p.priceTenths}|${p.bench}`).sort().join(';');
  if (key(a) !== key(b)) diffs.push('picks');
  if (a.captainId !== b.captainId) diffs.push('captain');
  if (a.viceId !== b.viceId) diffs.push('vice');
  if ((a.chip ?? null) !== (b.chip ?? null)) diffs.push('chip');
  return diffs;
}

interface ExpRow {
  gw: number;
  saved: boolean;
  used: number;
  freeBefore: number;
  intent: string | null;
  carriedChip: string | null;
  effectiveChip: string | null;
  cost: number;
  locked: FantasySquad;
  pipelineFreeAtLock: number | null;
  pipelineUsedAtLock: number | null;
  /** FPL selling (spec §4): the running sale total this lock books —
   *  the carried total + every baseline player sold, at the lock's price. */
  realized: number;
  grossTenths?: number;
  netTenths?: number;
}

interface ExpState {
  held: FantasySquad | null;
  /** The effective squad after the last lock = the selling baseline (its
   *  prices are what was paid). */
  lastLocked: FantasySquad | null;
  /** The running sale total that baseline carries (Free Hit aware). */
  realized: number;
  free: number;
  honored: Record<number, string>;
  week: { saves: number; lastSaved: FantasySquad | null; intent: string | null };
  rows: Record<number, ExpRow>;
  lastTransfers: Array<[string, string]>;
}

// ═════════════════════════════════════════════════════════════════════════
// E. The rehearsal
// ═════════════════════════════════════════════════════════════════════════

interface SimEvent { at: number; prio: number; seq: number; label: string; run: () => Promise<void> }

interface ReplayOptions {
  offline: boolean;
  /** A snapshot already loaded by the caller (skips loadSnapshot). */
  snapshot?: Snapshot;
  /** The synthetic managers playing the client role, built once the
   *  opening market + config are known. */
  managers: (market: Record<string, MarketEntry>, cfg: FantasyConfig) => ManagerDef[];
  /** Seed Managers/<uid> = { TeamName, NameFlagged:false } for every
   *  synthetic manager (the fill tool's fakes; the rehearsal never did). */
  seedManagerRows?: boolean;
  /** Real managers: uid -> raw saved squad. Saved once before GW1 through
   *  the client path (validated like the synthetic saves, then
   *  recordSquadSave) and held unchanged; a rejected one is skipped. */
  extraManagers?: Record<string, unknown>;
  /** Inject a recording no-op pusher (sends nothing anywhere) so the push
   *  steps run and claim their once-only guards (ReminderSent, RecapSent). */
  stubPusher?: boolean;
  /** Seeded managers make as many of a week's scripted transfers as they
   *  can afford instead of crashing the replay (see transfers()). */
  lenientTransfers?: boolean;
  /** Write rehearsal_out/{captured_writes,summary}.json + report_tables.md
   *  and print the console verdict (the rehearsal itself). */
  writeOutputs: boolean;
}

export interface ReplayResult {
  /** The final in-memory Fantasy/Futsal/15 subtree (RTDB-coerced shape). */
  state: Record<string, unknown>;
  skippedManagers: Array<{ uid: string; reason: string }>;
  /** Invariant name -> failures (empty when everything holds). */
  invariantFailures: Record<string, string[]>;
  crashes: Array<{ at: string; job: string; error: string }>;
  /** Synthetic + accepted real managers, and the expected-ledger mismatches. */
  managerUids: string[];
  managerLedgerMismatches: number;
  pushesRecorded: number;
  /** Seeded-manager weeks whose scripted transfers were cut to what the
   *  budget allowed (lenientTransfers only). */
  transfersCapped: number;
}

/** Replay Season 15 through the real pipeline with [managerCount] made-up
 *  managers test-01.. (seeded squads, the rehearsal personas' scripts
 *  cycled) plus [extraManagers] (real uid -> saved squad, held every week).
 *  Pure in-memory: the network is closed for the whole replay, nothing is
 *  ever written anywhere. Push steps run against a recording stub so their
 *  done-markers exist; a seeded manager makes only the scripted transfers it
 *  can afford; rehearsal_out reports are NOT written. */
export async function runReplay(opts: {
  offline: boolean;
  managerCount: number;
  extraManagers?: Record<string, unknown>;
  snapshot?: Snapshot;
}): Promise<ReplayResult> {
  const templates = MANAGERS.map((m) => ({ persona: m.persona, weeks: m.weeks }));
  return replaySeason({
    offline: opts.offline,
    snapshot: opts.snapshot,
    managers: (market, cfg) => fakeManagerDefs(opts.managerCount, market, cfg, templates),
    seedManagerRows: true,
    extraManagers: opts.extraManagers,
    stubPusher: true,
    lenientTransfers: true,
    writeOutputs: false,
  });
}

async function main(): Promise<void> {
  if (!fs.existsSync(path.join(FUNCTIONS_DIR, 'tools', 'rehearse_s15.ts'))) {
    throw new Error('Run from functions/ (npm run rehearse:s15).');
  }
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const offline = process.argv.includes('--offline');
  await replaySeason({ offline, managers: () => MANAGERS, writeOutputs: true });
}

async function replaySeason(opts: ReplayOptions): Promise<ReplayResult> {
  const restoreNetwork = installNetworkGuard();
  try {
    return await replaySeasonGuarded(opts);
  } finally {
    restoreNetwork();
  }
}

async function replaySeasonGuarded(opts: ReplayOptions): Promise<ReplayResult> {
  const offline = opts.offline;
  const snap = opts.snapshot ?? await loadSnapshot(offline);
  networkOpen = false; // from here on, ANY network attempt throws

  const db = new OverlayDb();
  for (const p of READ_PATHS) if (p in snap.values) db.seed(p, snap.values[p]);
  const configRaw = snap.values[`${F}/Config`];
  if (!isMap(configRaw)) throw new Error('No Fantasy Config in the snapshot — cannot rehearse.');
  const liveLockOverride = configRaw['lockOverride'] ?? null;
  db.seed(`${F}/Config/lockOverride`, 'auto'); // IN MEMORY ONLY

  const cfg = configFromMap(db.get(`${F}/Config`) as Record<string, unknown>);
  const originalDate = snap.values[`${LEAGUE}/Date`];
  const lineups = snap.values[`${LEAGUE}/Line Ups`];
  const marketIssues: string[] = [];
  const market = marketOf(snap.values[`${F}/Players`], marketIssues);
  const startPrices: Record<string, number> = {};
  for (const [n, p] of Object.entries(market)) startPrices[n] = p.price;

  const dateKeys = entriesOf(originalDate).map(([k]) => k);
  const gws = deriveGameweeks(dateKeys, cfg);
  const gwByNumber: Record<number, Gameweek> = {};
  for (const g of gws) gwByNumber[g.number] = g;

  const managers = opts.managers(market, cfg);
  if (opts.seedManagerRows) {
    for (const m of managers) {
      db.seed(`${F}/Managers/${m.uid}`, fakeManagerRow(m));
    }
  }
  const skippedManagers: ReplayResult['skippedManagers'] = [];
  const acceptedExtras: string[] = [];
  let transfersCapped = 0;
  // Recording no-op pusher: the push steps run (and claim their guards) but
  // nothing is sent anywhere — the network is closed anyway.
  const pushLog: Json[] = [];
  const stubPusher: FantasyPusher = {
    sendToUsers: async (messages) => {
      for (const m of messages) pushLog.push({ at: iso(db.nowMs), job: db.job, uid: m.uid, title: m.title });
      return messages.length;
    },
    sendToTopic: async (topic, title) => {
      pushLog.push({ at: iso(db.nowMs), job: db.job, topic, title });
      return 1;
    },
  };
  const deps: FantasyJobDeps | undefined = opts.stubPusher ? { pusher: stubPusher } : undefined;

  const logs: Array<{ at: string; job: string; level: string; message: string; context?: unknown }> = [];
  const logger: FantasyLogger = {
    info: (message, context) => logs.push({ at: iso(db.nowMs), job: db.job, level: 'info', message, context }),
    warn: (message, context) => logs.push({ at: iso(db.nowMs), job: db.job, level: 'warn', message, context }),
  };
  const crashes: Array<{ at: string; job: string; error: string }> = [];
  const jobCounts: Record<string, number> = {};
  const invariantFailures: Record<string, string[]> = {};
  const fail = (inv: string, msg: string) => {
    const list = (invariantFailures[inv] ??= []);
    if (!list.includes(msg)) list.push(msg);
  };
  const clientSaves: Json[] = [];
  const clientViewMismatches: Json[] = [];

  // Independent per-week recount (pure: the ORIGINAL snapshot only, never
  // pipeline output) — computed up front so the Dream Team audit can check
  // "played" during the replay; F1 compares it against PlayerWeeks after.
  const indep: Record<number, IndepWeek> = {};
  for (const gw of gws) indep[gw.number] = independentWeek(gw, childAt(originalDate, gw.date), lineups, market, cfg);

  // ── state audit, run after every job that touched a scoring node ──
  function auditState(label: string): void {
    const hist = db.get(`${F}/History`);
    const costsAll = db.get(`${F}/TransferCosts`);
    const voided = new Set(entriesOf(db.get(`${F}/Voided`)).filter(([, v]) => v === true).map(([k]) => Number(k)));
    const gwBoards = db.get(`${F}/Leaderboards/Gameweek`);
    const overall = db.get(`${F}/Leaderboards/Overall`);
    const weeksSeen = entriesOf(hist).map(([w]) => Number(w));
    const maxWeek = weeksSeen.length > 0 ? Math.max(...weeksSeen) : 0;
    const totals: Record<string, number> = {};
    const prevTotals: Record<string, number> = {};
    for (const [w, byUid] of entriesOf(hist)) {
      const board = childAt(gwBoards, w);
      const boardPts: Record<string, number> = {};
      for (const [uid, e] of entriesOf(byUid)) {
        if (!isMap(e)) { fail('history-shape', `${label}: History/${w}/${uid} not a map`); continue; }
        const breakdown = entriesOf(e['Breakdown']).map(([, b]) => b);
        const sum = breakdown.reduce((a: number, b: any) => a + Number(b?.countedTenths), 0);
        const cost = intLoose(childAt(childAt(costsAll, w), uid));
        // An Invalid week (the lock judge, squad_integrity.ts) scores zero
        // whatever its cost — the no-invalid-squads invariant flags the row.
        const invalid = e['Invalid'] != null && e['Invalid'] !== false;
        const expected = voided.has(Number(w)) || invalid ? 0 : sum - 10 * cost;
        if (e['TotalTenths'] !== expected || !Number.isInteger(e['TotalTenths'])) {
          fail('history-total', `${label}: History/${w}/${uid} TotalTenths ${e['TotalTenths']} != sum(Breakdown) ${sum} - 10*cost ${cost} = ${expected}`);
        }
        const whole = Math.trunc(Number(e['TotalTenths']) / 10);
        totals[uid] = (totals[uid] ?? 0) + whole;
        if (Number(w) < maxWeek) prevTotals[uid] = (prevTotals[uid] ?? 0) + whole;
        const row = childAt(board, uid);
        if (!isMap(row)) { fail('gameweek-board', `${label}: Leaderboards/Gameweek/${w}/${uid} missing`); continue; }
        if (row['points'] !== whole) fail('gameweek-board', `${label}: GW${w} ${uid} board ${row['points']} != trunc(TotalTenths/10) ${whole}`);
        boardPts[uid] = Number(row['points']);
      }
      for (const [uid, row] of entriesOf(board)) {
        const better = Object.values(boardPts).filter((p) => p > Number(row?.points)).length;
        if (row?.rank !== better + 1) fail('ranks', `${label}: GW${w} ${uid} rank ${row?.rank} != ${better + 1}`);
      }
    }
    const rankOf = (m: Record<string, number>, uid: string) =>
      1 + Object.values(m).filter((p) => p > m[uid]).length;
    for (const [uid, row] of entriesOf(overall)) {
      if (row?.points !== totals[uid]) fail('overall-sum', `${label}: Overall ${uid} ${row?.points} != sum of weekly whole points ${totals[uid]}`);
      if (row?.rank !== rankOf(totals, uid) || row?.rank < 1) fail('ranks', `${label}: Overall ${uid} rank ${row?.rank} != ${rankOf(totals, uid)}`);
      const expectMove = uid in prevTotals ? rankOf(prevTotals, uid) - rankOf(totals, uid) : undefined;
      if (row?.movement !== expectMove) fail('overall-movement', `${label}: Overall ${uid} movement ${row?.movement} != ${expectMove}`);
    }
    for (const uid of Object.keys(totals)) {
      if (!isMap(childAt(overall, uid))) fail('overall-sum', `${label}: Overall row missing for ${uid}`);
    }
    const pw = db.get(`${F}/PlayerWeeks`);
    for (const [name, row] of entriesOf(db.get(`${F}/PlayerTotals`))) {
      const pct = row?.ownershipPct;
      if (!Number.isInteger(pct) || pct < 0 || pct > 100) fail('ownership', `${label}: PlayerTotals/${name} ownershipPct ${pct}`);
      let sum = 0;
      for (const [w, byName] of entriesOf(pw)) if (!voided.has(Number(w))) sum += intLoose(childAt(byName, name));
      if (row?.points !== sum) fail('player-totals', `${label}: PlayerTotals/${name} ${row?.points} != sum PlayerWeeks ${sum}`);
    }
    for (const [w, dt] of entriesOf(db.get(`${F}/DreamTeam`))) {
      auditDreamTeam(label, Number(w), dt, childAt(pw, w));
    }
  }

  // Dream Team contract (finalize_core.ts pickDreamTeam): eligible market
  // players who PLAYED that week only; per position min(formation count,
  // eligible players of that position who played) slots; optimal among the
  // players who played (points desc, name asc).
  function auditDreamTeam(label: string, w: number, dt: any, weekPts: any): void {
    if (!isMap(dt)) { fail('dream-team', `${label}: DreamTeam/${w} not a map`); return; }
    const playedThisWeek = indep[w]?.played ?? {};
    const rows = entriesOf(dt['Players']).map(([, r]) => r);
    const formation: Record<string, number> = { GK: cfg.startersGk, DEF: cfg.startersDef, ATT: cfg.startersAtt };
    const got: Record<string, number> = { GK: 0, DEF: 0, ATT: 0 };
    for (const r of rows) {
      const m = market[String(r?.name)];
      got[String(r?.position)] = (got[String(r?.position)] ?? 0) + 1;
      if (!m) { fail('dream-team', `${label}: DreamTeam/${w} ${r?.name} not a market player`); continue; }
      if (!m.eligible) fail('dream-team', `${label}: DreamTeam/${w} ${r?.name} not eligible`);
      if (playedThisWeek[r.name] !== true) fail('dream-team', `${label}: DreamTeam/${w} ${r?.name} did not play`);
      if (m.position !== r?.position) fail('dream-team', `${label}: DreamTeam/${w} ${r?.name} position ${r?.position} != market ${m.position}`);
      if (intLoose(childAt(weekPts, r.name)) !== r?.points) fail('dream-team', `${label}: DreamTeam/${w} ${r?.name} ${r?.points} != PlayerWeeks ${childAt(weekPts, r.name)}`);
    }
    for (const pos of FANTASY_POSITIONS) {
      const playedOfPos = Object.entries(market)
        .filter(([n, m]) => m.eligible && m.position === pos && playedThisWeek[n] === true).length;
      const want = Math.min(formation[pos], playedOfPos);
      if (got[pos] !== want) fail('dream-team', `${label}: DreamTeam/${w} has ${got[pos]} ${pos}, want ${want}`);
      const chosen = rows.filter((r) => r?.position === pos);
      const minChosen = Math.min(...chosen.map((r) => Number(r.points)));
      for (const [name, m] of Object.entries(market)) {
        if (!m.eligible || m.position !== pos || chosen.some((r) => r.name === name)) continue;
        if (playedThisWeek[name] !== true) continue; // never a candidate
        const pts = intLoose(childAt(weekPts, name));
        const beats = pts > minChosen ||
          (pts === minChosen && chosen.some((r) => Number(r.points) === pts && name.localeCompare(r.name) < 0));
        if (beats) fail('dream-team', `${label}: DreamTeam/${w} skipped ${name} (${pts}) for a lower ${pos}`);
      }
    }
  }

  // ── job runner: production triggers fire on server writes too ──
  async function runJob(job: string, t: number, fn: () => Promise<unknown>): Promise<void> {
    const kind = job.replace(/\(.*$/, '');
    jobCounts[kind] = (jobCounts[kind] ?? 0) + 1;
    const prevJob = db.job;
    db.nowMs = t;
    db.job = job;
    const from = db.pipelineWrites.length;
    try {
      await fn();
    } catch (err) {
      crashes.push({ at: iso(t), job, error: String((err as Error)?.stack ?? err) });
    }
    db.job = prevJob;
    const mine = db.pipelineWrites.slice(from);
    // onFantasySquadWritten fires for the Admin SDK's own Squads writes
    // exactly as for client saves — the whole-squad Free Hit restore AND
    // descendant writes (the rollover's chip switch-off, a position
    // relabel), since an RTDB trigger on Squads/{uid} sees any change
    // under it. One firing per uid per job (the trigger debounces nothing,
    // but recordSquadSave is a recompute, so once is equivalent).
    const firedUids = new Set<string>();
    for (const w of mine) {
      const m = /^Fantasy\/Futsal\/15\/Squads\/([^/]+)(\/|$)/.exec(w.path);
      if (!m || firedUids.has(m[1])) continue;
      if (!isMap(db.get(`${F}/Squads/${m[1]}`))) continue; // deletion: the trigger's payload gate
      firedUids.add(m[1]);
      await runJob(`trigger:onFantasySquadWritten(${m[1]}, server write)`, t,
        () => recordSquadSave(db, { sport: SPORT, season: SEASON, uid: m[1], log: logger, nowUtc: new Date(t) }));
    }
    // onFantasyBadgeAwarded is a CREATE trigger on one award row; the engine
    // creates award rows set-if-absent, one child each — so every WON claim
    // under Badges/<uid>/<awardId> is one firing. Only with a pusher (the
    // fill's recording stub): the rehearsal injects none, so — like the
    // recap/reminder guards — no BadgePushClaims are produced there.
    const pusher = deps?.pusher;
    if (pusher) {
      for (const w of mine) {
        const b = /^Fantasy\/Futsal\/15\/Badges\/([^/]+)\/([^/]+)$/.exec(w.path);
        if (!b || w.op !== 'writeIfAbsent' || !w.won) continue;
        await runJob(`trigger:onFantasyBadgeAwarded(${b[1]}/${b[2]})`, t,
          () => pushBadgeAward(db, pusher, {
            sport: SPORT, season: SEASON, uid: b[1], awardId: b[2], nowUtc: new Date(t), log: logger,
          }));
      }
    }
    if (mine.some((w) => /\/(History|Leaderboards|PlayerTotals|DreamTeam|PlayerWeeks)(\/|$)/.test(w.path))) {
      auditState(`${job} @ ${iso(t)}`);
    }
  }

  async function fireGameTrigger(date: string, idx: string, t: number, why: string): Promise<void> {
    const after = db.get(`${LEAGUE}/Date/${date}/${idx}`);
    // fantasy_finalize.ts payload gate: nothing unless the game is Final.
    if (!isMap(after) || intLoose(after['status']) !== 2) return;
    await runJob(`trigger:onGameWritten(${date}/${idx} ${why})`, t,
      () => maybeFinalizeGame(db, { sport: SPORT, season: SEASON, dateKey: date, nowUtc: new Date(t), log: logger, deps }));
  }

  // ── client helpers (what the app does, using only client-visible nodes) ──
  function livePlayers(): Record<string, MarketEntry> {
    return marketOf(db.get(`${F}/Players`), []);
  }
  function liveForm(): Record<string, number> {
    const out: Record<string, number> = {};
    for (const [n, r] of entriesOf(db.get(`${F}/PlayerTotals`))) out[n] = intLoose(r?.points);
    return out;
  }
  /** The app's FPL-rule draft money for [uid] editing gameweek [gw]
   *  (client_draft_money.ts), from the nodes the app itself reads: its own
   *  Baselines/<uid>, today's Players prices, PriceHistory/<gw − 1>. */
  function clientMoney(uid: string, gw: number): ClientDraftMoney {
    const currentPrices: Record<string, number> = {};
    for (const [n, p] of Object.entries(livePlayers())) currentPrices[n] = p.price;
    const last = gw > 1 ? db.get(`${F}/PriceHistory/${gw - 1}`) : null;
    let lastWeekPrices: Record<string, number> | null = null;
    if (isMap(last)) {
      lastWeekPrices = {};
      for (const [n, v] of Object.entries(last)) if (typeof v === 'number') lastWeekPrices[n] = v;
    }
    return clientDraftMoney({
      baselineNode: db.get(`${F}/Baselines/${uid}`), currentPrices, lastWeekPrices, editingGw: gw,
    });
  }
  /** The app blocks Save while its money isn't real (squad_draft.dart
   *  moneyReady): a missing-for-this-week or unreadable Baselines/<uid> is a
   *  pipeline finding, never a silent save. */
  function moneyBlocked(uid: string, gw: number, draft: ClientDraftMoney, t: number, kind: string): boolean {
    if (draft.ready) return false;
    fail('sale-baseline', `${iso(t)} ${uid} GW${gw} ${kind}: Baselines/${uid} not FOR GW${gw} ` +
      `(${stable(db.get(`${F}/Baselines/${uid}`))}) — the app would block Save`);
    clientSaves.push({ at: iso(t), uid, gw, kind: `${kind}-blocked (budget still updating)` });
    return true;
  }
  function fixArmband(s: FantasySquad, form: Record<string, number>): void {
    const starters = s.picks.filter((p) => !p.bench).map((p) => p.playerId);
    const rank = (ids: string[]) => [...ids].sort((a, b) => (form[b] ?? 0) - (form[a] ?? 0) || a.localeCompare(b));
    if (!starters.includes(s.captainId)) s.captainId = rank(starters.filter((x) => x !== s.viceId))[0];
    if (!starters.includes(s.viceId) || s.viceId === s.captainId) {
      s.viceId = rank(starters.filter((x) => x !== s.captainId))[0];
    }
  }
  /** Greedy transfers: sell the n worst by season form (PlayerTotals), buy
   *  the best affordable same-position replacement. The money is the app
   *  draft's ([draft], FPL selling): kept picks cost their price paid (a
   *  baseline player his baseline price), a sold baseline player frees his
   *  SELL price (half a rise, the full drop), a replacement takes
   *  draft.addCost (today's price; a sold baseline player bought back un-
   *  books his sale) and is picked at draft.buyPrice. */
  function transferGreedy(
    squad: FantasySquad, n: number, notes: string[], pairs: Array<[string, string]>,
    draft: ClientDraftMoney,
  ): FantasySquad {
    const mkt = livePlayers();
    const form = liveForm();
    const s = cloneSquad(squad);
    const owned = new Set(s.picks.map((p) => p.playerId));
    const order = s.picks.map((_, i) => i).sort((a, b) =>
      (form[s.picks[a].playerId] ?? 0) - (form[s.picks[b].playerId] ?? 0) ||
      s.picks[a].priceTenths - s.picks[b].priceTenths ||
      s.picks[a].playerId.localeCompare(s.picks[b].playerId));
    const outIdx = order.slice(0, n).sort((a, b) => a - b);
    const filled = new Set<number>();
    const unfilled = (j: number) => outIdx.includes(j) && !filled.has(j);
    const cheapest = (pos: string, keptIds: string[]) => Math.min(...Object.entries(mkt)
      .filter(([nm, p]) => p.eligible && p.position === pos && !owned.has(nm))
      .map(([nm]) => draft.addCost(nm, keptIds)));
    for (const i of outIdx) {
      filled.add(i);
      const pos = s.picks[i].position;
      // Everything still owned once slot i and the unfilled slots are sold.
      const kept = s.picks.filter((_, j) => !(unfilled(j) || j === i));
      const keptIds = kept.map((p) => p.playerId);
      const committed = kept.reduce((a, p) => a + draft.priceOfPick(p), 0);
      const reserve = outIdx.filter(unfilled).reduce((a, j) => a + cheapest(s.picks[j].position, keptIds), 0);
      const cap = cfg.budgetTenths + draft.realizedFor(keptIds) - committed - reserve;
      const cands = Object.entries(mkt)
        .filter(([nm, p]) => p.eligible && p.position === pos && !owned.has(nm) &&
          draft.addCost(nm, keptIds) <= cap)
        .sort((a, b) => (form[b[0]] ?? 0) - (form[a[0]] ?? 0) || a[1].price - b[1].price || a[0].localeCompare(b[0]));
      if (cands.length === 0) throw new Error(`no affordable ${pos} under ${cap}`);
      const [nm] = cands[0];
      const price = draft.buyPrice(nm);
      notes.push(`${s.picks[i].playerId} -> ${nm} (${money(price)})`);
      pairs.push([s.picks[i].playerId, nm]);
      s.picks[i] = { playerId: nm, position: pos, priceTenths: price, bench: s.picks[i].bench };
      owned.add(nm);
    }
    fixArmband(s, form);
    return s;
  }
  /** transferGreedy — or, for the fill's seeded managers
   *  (opts.lenientTransfers), as many of the n transfers as the greedy can
   *  afford (n, n-1, … 0), so one unlucky seeded squad cannot crash the
   *  replay. The rehearsal stays strict: there a failure is a finding. */
  function transfers(
    squad: FantasySquad, n: number, notes: string[], pairs: Array<[string, string]>,
    draft: ClientDraftMoney,
  ): FantasySquad {
    if (!opts.lenientTransfers) return transferGreedy(squad, n, notes, pairs, draft);
    for (let k = n; k > 0; k--) {
      const kNotes: string[] = [];
      const kPairs: Array<[string, string]> = [];
      try {
        const out = transferGreedy(squad, k, kNotes, kPairs, draft);
        if (k < n) {
          kNotes.push(`only ${k} of ${n} transfers affordable`);
          transfersCapped++;
        }
        notes.push(...kNotes);
        pairs.push(...kPairs);
        return out;
      } catch {
        // one fewer
      }
    }
    notes.push(`no affordable transfer (wanted ${n})`);
    transfersCapped++;
    return squad;
  }

  const exp: Record<string, ExpState> = {};
  for (const m of managers) {
    exp[m.uid] = {
      held: null, lastLocked: null, realized: 0, free: cfg.freeTransfersPerWeek, honored: {},
      week: { saves: 0, lastSaved: null, intent: null }, rows: {}, lastTransfers: [],
    };
  }
  const setOf = (gw: number) => (gw <= cfg.chipSet1EndGw ? 1 : 2);

  async function clientWrite(m: ManagerDef, gw: number, squad: FantasySquad, t: number, kind: string, notes: string[]): Promise<void> {
    const draft = clientMoney(m.uid, gw);
    if (moneyBlocked(m.uid, gw, draft, t, kind)) return;
    const issues = draft.issues(squad, cfg);
    if (issues.length > 0) throw new Error(`synthetic squad invalid: ${m.uid} GW${gw} ${kind}: ${issues.join(',')}`);
    db.nowMs = t;
    db.job = `client:${m.uid}`;
    db.simWrite(`${F}/Squads/${m.uid}`, squadToMap(squad));
    const ids = squad.picks.map((p) => p.playerId);
    clientSaves.push({
      at: iso(t), uid: m.uid, gw, kind, notes, spent: spentTenths(squad),
      charged: squad.picks.reduce((a, p) => a + draft.priceOfPick(p), 0),
      available: cfg.budgetTenths + draft.realizedFor(ids), chip: squad.chip,
      captain: squad.captainId, vice: squad.viceId,
      picks: squad.picks.map((p) => `${p.playerId}${p.bench ? ' (bench)' : ''}`),
    });
    const e = exp[m.uid];
    e.week.saves++;
    e.week.lastSaved = cloneSquad(squad);
    await runJob(`trigger:onFantasySquadWritten(${m.uid})`, t,
      () => recordSquadSave(db, { sport: SPORT, season: SEASON, uid: m.uid, log: logger, nowUtc: new Date(t) }));
  }

  async function clientWeek(m: ManagerDef, gw: number, t: number): Promise<void> {
    const e = exp[m.uid];
    const notes: string[] = [];
    let squad: FantasySquad;
    if (gw === 1) {
      const mkt = livePlayers();
      squad = {
        picks: m.initial.picks.map(([name, bench]) => {
          const p = mkt[name];
          if (!p) throw new Error(`${m.uid}: ${name} is not in the market`);
          return { playerId: name, position: p.position, priceTenths: p.price, bench };
        }),
        captainId: m.initial.captain, viceId: m.initial.vice, chip: null,
      };
      notes.push('initial build');
    } else {
      const raw = db.get(`${F}/Squads/${m.uid}`);
      if (!isMap(raw)) throw new Error(`${m.uid}: no saved squad at GW${gw}`);
      squad = squadFromMap(raw);
      if (e.held) {
        const diffs = sameSquad(squad, e.held);
        if (diffs.length > 0) clientViewMismatches.push({ at: iso(t), uid: m.uid, gw, diffs });
      }
      // The money the app shows (FPL selling): Baselines/<uid> must be FOR
      // this week and say what the expected ledger says the last lock left.
      const draft = clientMoney(m.uid, gw);
      if (moneyBlocked(m.uid, gw, draft, t, 'save')) return;
      const wantPrices: Record<string, number> = {};
      for (const p of e.lastLocked?.picks ?? []) wantPrices[p.playerId] = p.priceTenths;
      const b = draft.baseline;
      const baselineDiffs: string[] = [];
      if (b === null) baselineDiffs.push('Baselines absent');
      else {
        if (b.realizedTenths !== e.realized) baselineDiffs.push(`Baselines.RealizedTenths ${b.realizedTenths} != ${e.realized}`);
        if (canon(b.prices) !== canon(wantPrices)) baselineDiffs.push(`Baselines.Prices ${stable(b.prices)} != ${stable(wantPrices)}`);
      }
      if (baselineDiffs.length > 0) clientViewMismatches.push({ at: iso(t), uid: m.uid, gw, diffs: baselineDiffs });
      const plan = m.weeks[gw];
      e.lastTransfers = [];
      if (plan.rebuild === 'freeHit') {
        squad = transfers(squad, squad.picks.length, notes, e.lastTransfers, draft);
        squad.chip = 'freeHit';
        e.week.intent = 'freeHit';
      } else if (plan.rebuild === 'wildcard') {
        squad = transfers(squad, plan.transfers ?? 5, notes, e.lastTransfers, draft);
        squad.chip = 'wildcard';
        e.week.intent = 'wildcard';
      } else if (plan.transfers) {
        squad = transfers(squad, plan.transfers, notes, e.lastTransfers, draft);
      }
      if ('chip' in plan) {
        squad.chip = plan.chip ?? null;
        e.week.intent = plan.chip ?? null;
        notes.push(`chip -> ${plan.chip ?? 'none'}`);
      }
      if (plan.benchSwap) {
        const [a, b] = plan.benchSwap;
        for (const p of squad.picks) {
          if (p.playerId === a || p.playerId === b) p.bench = !p.bench;
        }
        notes.push(`bench swap ${a} <-> ${b}`);
      }
      if (plan.captain) squad.captainId = plan.captain;
      if (plan.vice) squad.viceId = plan.vice;
    }
    await clientWrite(m, gw, squad, t, 'save', notes);
  }

  async function clientUndoOne(m: ManagerDef, gw: number, t: number): Promise<void> {
    const e = exp[m.uid];
    const raw = db.get(`${F}/Squads/${m.uid}`);
    if (!isMap(raw)) return;
    const base = squadFromMap(raw);
    const mkt = livePlayers();
    const draft = clientMoney(m.uid, gw);
    if (moneyBlocked(m.uid, gw, draft, t, 'undo-one')) return;
    for (const [outName, inName] of [...e.lastTransfers].reverse()) {
      const p = mkt[outName];
      const idx = base.picks.findIndex((x) => x.playerId === inName);
      if (!p || idx < 0) continue;
      // Changed your mind (FPL selling): a baseline player put back before
      // the deadline returns at the price paid — no sale, no transfer.
      const price = draft.buyPrice(outName);
      const cand = cloneSquad(base);
      cand.picks[idx] = { playerId: outName, position: p.position, priceTenths: price, bench: base.picks[idx].bench };
      fixArmband(cand, liveForm());
      if (draft.issues(cand, cfg).length === 0) {
        await clientWrite(m, gw, cand, t, 'undo-one', [`undo: ${inName} -> ${outName} (${money(price)})`]);
        return;
      }
    }
    clientSaves.push({ at: iso(t), uid: m.uid, gw, kind: 'undo-skipped (budget)' });
  }

  /** A real manager's saved squad, replayed as-is: one save before GW1
   *  through the same client path (the client's own checks, the Squads
   *  write, the onFantasySquadWritten trigger), then held — the server
   *  keeps it every week, exactly like a manager who saved once. A squad
   *  the client path cannot take is skipped, never repaired. */
  async function extraSave(uid: string, raw: unknown, t: number): Promise<void> {
    const reject = (reason: string) => { skippedManagers.push({ uid, reason }); };
    if (!isMap(raw)) return reject('saved squad is not a map');
    let squad: FantasySquad;
    try {
      squad = squadFromMap(raw);
    } catch (err) {
      return reject(`malformed saved squad: ${(err as Error).message}`);
    }
    const mkt = livePlayers();
    const unknown = squad.picks.map((p) => p.playerId).filter((n) => !(n in mkt));
    if (unknown.length > 0) return reject(`not in the market: ${unknown.join(', ')}`);
    // The app's own check: its FPL-rule draft money for a first squad.
    const draft = clientMoney(uid, 1);
    if (!draft.ready) return reject(`Baselines/${uid} is not readable for GW1 — the app would block Save`);
    const issues = draft.issues(squad, cfg);
    if (issues.length > 0) return reject(`invalid squad: ${issues.join(', ')}`);
    // The server's lock-time judge too (audit I2, squad_integrity.ts): a
    // first squad's picks must be affordable at the replay's OWN opening
    // prices. A real squad saved at other prices (e.g. a dry run over an
    // already-filled season, whose Players hold end-of-season prices) would
    // be scored zero every week — skipped instead, never repaired.
    const serverIssues = squadIntegrityIssues(
      squad, cfg, integrityMarketOf(db.get(`${F}/Players`)), null, 0, {});
    if (serverIssues.length > 0) {
      return reject('the server would judge it invalid at the replay ' +
        `opening prices: ${serverIssues.join(', ')}`);
    }
    db.nowMs = t;
    db.job = `client:${uid}`;
    db.simWrite(`${F}/Squads/${uid}`, squadToMap(squad));
    clientSaves.push({
      at: iso(t), uid, gw: 1, kind: 'real squad (held)', notes: [], spent: spentTenths(squad),
      chip: squad.chip, captain: squad.captainId, vice: squad.viceId,
      picks: squad.picks.map((p) => `${p.playerId}${p.bench ? ' (bench)' : ''}`),
    });
    acceptedExtras.push(uid);
    await runJob(`trigger:onFantasySquadWritten(${uid})`, t,
      () => recordSquadSave(db, { sport: SPORT, season: SEASON, uid, log: logger, nowUtc: new Date(t) }));
  }

  /** The expected (spec) ledger at the lock instant — never reads pipeline
   *  output except to RECORD what the pipeline holds for comparison. */
  function expectLock(m: ManagerDef, gw: number): void {
    const e = exp[m.uid];
    const lockedRaw = e.week.lastSaved ?? e.held;
    if (!lockedRaw) return;
    const intent = e.week.intent;
    const repeated = intent !== null && Object.entries(e.honored)
      .some(([w, c]) => c === intent && Number(w) < gw && setOf(Number(w)) === setOf(gw));
    const effective = intent !== null && !repeated ? intent : null;
    const used = e.week.saves > 0 && e.held !== null ? countNew(lockedRaw, e.held) : 0;
    const unlimited = effective === 'wildcard' || effective === 'freeHit';
    const cost = unlimited ? 0 : Math.max(0, used - e.free) * cfg.extraTransferCost;
    const ts = db.get(`${F}/TransferState/${m.uid}`);
    // FPL selling (spec §4), recomputed from the ledger's own baseline (the
    // last locked squad, Free Hit aware): every baseline player missing from
    // the locked squad is sold at the lock-instant price — half a rise, the
    // full drop; no usable price adds 0.
    const lockedIds = new Set(lockedRaw.picks.map((p) => p.playerId));
    const mktNow = livePlayers();
    let realized = e.realized;
    for (const p of e.lastLocked?.picks ?? []) {
      if (lockedIds.has(p.playerId)) continue;
      const now = mktNow[p.playerId]?.price;
      if (now === undefined || now <= 0) continue;
      realized += sellPriceTenths(p.priceTenths, now) - p.priceTenths;
    }
    const row: ExpRow = {
      gw, saved: e.week.saves > 0, used, freeBefore: e.free, intent,
      carriedChip: lockedRaw.chip ?? null, effectiveChip: effective, cost,
      locked: { ...cloneSquad(lockedRaw), chip: effective },
      pipelineFreeAtLock: isMap(ts) && typeof ts['Free'] === 'number' ? ts['Free'] : (isMap(ts) ? null : cfg.freeTransfersPerWeek),
      pipelineUsedAtLock: isMap(ts) ? intLoose(ts['UsedThisGw']) : 0,
      realized,
    };
    e.rows[gw] = row;
    const remaining = unlimited ? e.free : Math.min(Math.max(e.free - used, 0), e.free);
    e.free = Math.min(Math.max(remaining + cfg.freeTransfersPerWeek, 0), cfg.maxBankedTransfers);
    if (effective) e.honored[gw] = effective;
    const prevLocked = e.lastLocked;
    // Spec §6: a Free Hit squad lasts one week, the previous squad returns —
    // so the squad "last locked" for the next restore is the RETURNED one.
    e.lastLocked = effective === 'freeHit' && prevLocked ? prevLocked : row.locked;
    // ...and its sales were temporary: the returned squad keeps ITS total.
    if (!(effective === 'freeHit' && prevLocked)) e.realized = realized;
    // Chips are one-week (owner decision 2026-10-28): whatever chip the
    // squad carried is switched off after its week, so the squad the
    // manager holds next week is chipless.
    e.held = effective === 'freeHit' && prevLocked
      ? { ...cloneSquad(prevLocked), chip: null }
      : { ...cloneSquad(lockedRaw), chip: null };
    e.week = { saves: 0, lastSaved: null, intent: null };
  }

  // ── build the event timeline ──
  const events: SimEvent[] = [];
  let evSeq = 0;
  const at = (t: number, prio: number, label: string, run: () => Promise<void>) =>
    events.push({ at: t, prio, seq: evSeq++, label, run });

  const firstLock = gws[0].lockUtc.getTime();
  const lastLock = gws[gws.length - 1].lockUtc.getTime();
  const simStart = Math.floor((firstLock - 3 * DAY) / (15 * MIN)) * 15 * MIN;
  const simEnd = lastLock + 3 * DAY;

  // Time-travel device: every S15 game is already final in the snapshot. In
  // production a match day goes final AFTER its lock, game by game, so the
  // replay first sets every game's status to 0 (scheduled) in memory and
  // flips each one back to its real value at a realistic final instant.
  const originalStatus: Record<string, unknown> = {};
  db.job = 'league:pre-season-mask';
  db.nowMs = simStart;
  for (const [date, games] of entriesOf(originalDate)) {
    for (const [idx, g] of entriesOf(games)) {
      if (!isMap(g)) continue;
      originalStatus[`${date}/${idx}`] = g['status'] ?? null;
      db.simWrite(`${LEAGUE}/Date/${date}/${idx}/status`, 0);
    }
  }

  for (let t = simStart; t <= simEnd; t += 15 * MIN) {
    at(t, 1, 'sweep', () => runJob('cron:fantasyLifecycleSweep', t, () => runLifecycleSweep(db, new Date(t), logger, deps)));
  }
  for (let d = Math.floor(simStart / DAY) * DAY; d <= simEnd; d += DAY) {
    const day = new Date(d);
    if (day.getUTCDay() !== 1) continue; // Mondays
    const t = lockInstantUtc(mmddyyyy(day), 10).getTime(); // 10:00 league time
    if (t < simStart || t > simEnd) continue;
    at(t, 2, `reprice ${mmddyyyy(day)}`, () => runJob('cron:fantasyMondayReprice', t, () => runMondayReprice(db, new Date(t), logger)));
  }
  for (const gw of gws) {
    const L = gw.lockUtc.getTime();
    at(L, 0, `expected-ledger lock GW${gw.number}`, async () => { for (const m of managers) expectLock(m, gw.number); });
    const games = entriesOf(childAt(originalDate, gw.date)).filter(([, g]) => isMap(g));
    games.forEach(([idx], k) => {
      const t = L + 97 * MIN + k * HOUR;
      at(t, 0, `final ${gw.date}#${idx}`, async () => {
        db.nowMs = t;
        db.job = 'league:live-scoring';
        db.simWrite(`${LEAGUE}/Date/${gw.date}/${idx}/status`, originalStatus[`${gw.date}/${idx}`]);
        await fireGameTrigger(gw.date, idx, t, 'final');
      });
    });
    if (games.length > 0) {
      const t = L + 20 * HOUR + 11 * MIN;
      at(t, 0, `rerun ${gw.date}`, () => fireGameTrigger(gw.date, games[0][0], t, 'later edit'));
    }
  }
  managers.forEach((m, mi) => {
    for (const gw of gws) {
      const n = gw.number;
      if (n !== 1 && !m.weeks[n]) continue;
      const openAt = n === 1 ? firstLock - 2 * DAY : gwByNumber[n - 1].lockUtc.getTime() + DAY;
      const t = openAt + 2 * HOUR + 7 * MIN + mi * 3 * MIN;
      at(t, 3, `client ${m.uid} GW${n}`, () => clientWeek(m, n, t));
      if (m.weeks[n]?.undoOneNextDay) {
        const t2 = t + DAY;
        at(t2, 3, `client ${m.uid} GW${n} undo`, () => clientUndoOne(m, n, t2));
      }
    }
  });
  Object.entries(opts.extraManagers ?? {}).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .forEach(([uid, raw], k) => {
      const t = firstLock - 2 * DAY + 2 * HOUR + 7 * MIN + (managers.length + k) * 3 * MIN;
      at(t, 3, `client ${uid} GW1 (real squad)`, () => extraSave(uid, raw, t));
    });
  let preLate: Json = null;
  let postLate: Json = null;
  const lateT = simEnd - DAY + 11 * MIN;
  const gw1Games = entriesOf(childAt(originalDate, gws[0].date)).filter(([, g]) => isMap(g));
  at(lateT, 0, 'late GW1 correction rerun', async () => {
    preLate = {
      overall: db.get(`${F}/Leaderboards/Overall`), totals: db.get(`${F}/PlayerTotals`),
      history: db.get(`${F}/History`), boards: db.get(`${F}/Leaderboards/Gameweek`),
      badges: db.get(`${F}/Badges`),
    };
    await fireGameTrigger(gws[0].date, gw1Games[0][0], lateT, 'late correction');
    postLate = {
      overall: db.get(`${F}/Leaderboards/Overall`), totals: db.get(`${F}/PlayerTotals`),
      history: db.get(`${F}/History`), boards: db.get(`${F}/Leaderboards/Gameweek`),
      badges: db.get(`${F}/Badges`),
    };
  });

  events.sort((a, b) => a.at - b.at || a.prio - b.prio || a.seq - b.seq);
  const t0 = Date.now();
  for (const ev of events) {
    try {
      await ev.run();
    } catch (err) {
      crashes.push({ at: iso(ev.at), job: ev.label, error: String((err as Error)?.stack ?? err) });
    }
  }
  const wallMs = Date.now() - t0;

  // ═══════════════════════════════════════════════════════════════════════
  // F. Cross-checks + invariants on the finished season
  // ═══════════════════════════════════════════════════════════════════════

  auditState('final state');
  const finalState = db.get(F);
  // A real squad the client path took but no gameweek ever scored (finalize
  // skips a squad it cannot read) is skipped too.
  for (const uid of [...acceptedExtras]) {
    const scored = entriesOf(db.get(`${F}/History`)).some(([, byUid]) => isMap(childAt(byUid, uid)));
    if (!scored) {
      skippedManagers.push({ uid, reason: 'saved, but no gameweek ever scored it (finalize skipped the squad)' });
      acceptedExtras.splice(acceptedExtras.indexOf(uid), 1);
    }
  }

  // F1. Player weeks: pipeline vs independent recomputation (indep was
  // computed up front from the original snapshot)
  const pwMismatches: Json[] = [];
  let pwCompared = 0;
  for (const gw of gws) {
    const stored = db.get(`${F}/PlayerWeeks/${gw.number}`);
    for (const name of Object.keys(market)) {
      pwCompared++;
      const got = childAt(stored, name);
      const want = indep[gw.number].points[name];
      if (got !== want) {
        pwMismatches.push({ gw: gw.number, date: gw.date, name, pipeline: got, independent: want,
          base: indep[gw.number].base[name], bonus: indep[gw.number].bonus[name] });
      }
    }
    for (const [name] of entriesOf(stored)) {
      if (!(name in market)) pwMismatches.push({ gw: gw.number, name, pipeline: childAt(stored, name), independent: 'not a market player' });
    }
  }
  // Every write of PlayerWeeks/<gw> must equal the final one (reruns).
  const idempotence: Json[] = [];
  const byPath: Record<string, string[]> = {};
  for (const w of db.pipelineWrites) {
    if (/\/(History|PlayerWeeks|TransferCosts|PublishedPicks)\/\d+$/.test(w.path) ||
      /\/Leaderboards\/Gameweek\/\d+$/.test(w.path)) {
      if (w.op === 'writeIfAbsent' && !w.won) continue;
      (byPath[w.path] ??= []).push(canon(w.value));
    }
  }
  for (const [p, vals] of Object.entries(byPath)) {
    if (new Set(vals).size > 1) idempotence.push({ path: p, distinctValues: new Set(vals).size, writes: vals.length });
  }
  const dtWrites: Record<string, Set<string>> = {};
  for (const w of db.pipelineWrites) {
    if (/\/DreamTeam\/\d+$/.test(w.path) && isMap(w.value)) {
      (dtWrites[w.path] ??= new Set()).add(canon({ ...w.value, ComputedAt: 0 }));
    }
  }
  for (const [p, vals] of Object.entries(dtWrites)) if (vals.size > 1) idempotence.push({ path: p, distinctValues: vals.size, note: 'ignoring ComputedAt' });
  const lateRerun = {
    historyUnchanged: canon(preLate?.history) === canon(postLate?.history),
    overallUnchanged: canon(preLate?.overall) === canon(postLate?.overall),
    boardsUnchanged: canon(preLate?.boards) === canon(postLate?.boards),
    badgesUnchanged: canon(preLate?.badges) === canon(postLate?.badges),
    playerTotalsPointsUnchanged: canon(Object.fromEntries(entriesOf(preLate?.totals).map(([n, r]) => [n, r.points]))) ===
      canon(Object.fromEntries(entriesOf(postLate?.totals).map(([n, r]) => [n, r.points]))),
    ownershipChanged: entriesOf(postLate?.totals)
      .filter(([n, r]) => childAt(preLate?.totals, n)?.ownershipPct !== r.ownershipPct)
      .map(([n, r]) => ({ name: n, before: childAt(preLate?.totals, n)?.ownershipPct, after: r.ownershipPct })),
  };

  // F2. Season totals: pipeline vs seed-tool semantics (+ opening prices)
  const positionByName: Record<string, FantasyPosition> = {};
  for (const [n, p] of Object.entries(market)) positionByName[n] = p.position;
  const seed = seedSemanticsTotals(originalDate, lineups, positionByName);
  const seasonRows: Json[] = [];
  const seedGaps: Json[] = [];
  for (const name of Object.keys(market)) {
    let pipelineTotal = 0;
    let bonus = 0;
    let base = 0;
    for (const gw of gws) {
      pipelineTotal += intLoose(childAt(db.get(`${F}/PlayerWeeks/${gw.number}`), name));
      bonus += indep[gw.number].bonus[name];
      base += indep[gw.number].base[name];
    }
    const row = { name, position: market[name].position, team: market[name].team,
      pipelineTotal, bonus, pipelineExBonus: pipelineTotal - bonus, seedBase: seed.points[name],
      gap: pipelineTotal - bonus - seed.points[name], playerTotals: childAt(db.get(`${F}/PlayerTotals`), name)?.points };
    seasonRows.push(row);
    if (row.gap !== 0) seedGaps.push(row);
  }
  const seedOpening: Record<string, number> = {};
  for (const pos of FANTASY_POSITIONS) {
    const group: Record<string, number> = {};
    for (const [n, p] of Object.entries(positionByName)) if (p === pos) group[n] = seed.points[n];
    Object.assign(seedOpening, openingPrices(group, futsalDefault()));
  }
  const openingMismatch = Object.keys(market)
    .filter((n) => seedOpening[n] !== startPrices[n])
    .map((n) => ({ name: n, snapshotPrice: startPrices[n], seedSemanticsPrice: seedOpening[n] }));
  const liveCfgDiffersFromDefault = canon(configToMap(cfg)) !== canon(configToMap(futsalDefault()));

  // F3. Repricing: independent price ledger
  const ledger: Record<string, number> = { ...startPrices };
  const repriceMismatches: Json[] = [];
  const priceChangesByGw: Record<number, Record<string, number>> = {};
  for (const gw of gws) {
    const rep = db.get(`${F}/Repriced/${gw.number}`);
    if (!isMap(rep)) { repriceMismatches.push({ gw: gw.number, issue: 'never repriced' }); continue; }
    const want: Record<string, number> = {};
    for (const pos of FANTASY_POSITIONS) {
      const group: Record<string, number> = {};
      for (const [n, p] of Object.entries(market)) if (p.eligible && p.position === pos) group[n] = indep[gw.number].points[n];
      for (const [n, d] of Object.entries(repriceDeltas(group, cfg))) {
        if (d === 0) continue;
        const nw = applyDelta(ledger[n], d, cfg);
        if (nw !== ledger[n]) { want[n] = nw - ledger[n]; ledger[n] = nw; }
      }
    }
    const got: Record<string, number> = {};
    for (const [n, r] of entriesOf(db.get(`${F}/PriceChanges/${gw.number}`))) if (isMap(r)) got[n] = r['delta'];
    priceChangesByGw[gw.number] = got;
    if (stable(Object.entries(got).sort()) !== stable(Object.entries(want).sort())) {
      repriceMismatches.push({ gw: gw.number, pipeline: got, independent: want });
    }
  }
  const finalPrices: Record<string, number> = {};
  for (const [n, r] of entriesOf(db.get(`${F}/Players`))) finalPrices[n] = intLoose(r?.priceTenths);
  for (const n of Object.keys(market)) {
    if (finalPrices[n] !== ledger[n]) repriceMismatches.push({ name: n, finalPipeline: finalPrices[n], finalIndependent: ledger[n] });
  }
  // Price writes: integer, in range, step-aligned, exactly one step.
  const lastPrice: Record<string, number> = { ...startPrices };
  for (const w of db.pipelineWrites) {
    const pm = /^Fantasy\/Futsal\/15\/Players\/(.+)\/priceTenths$/.exec(w.path);
    if (pm) {
      const v = w.value as number;
      if (!Number.isInteger(v) || v < cfg.priceMinTenths || v > cfg.priceMaxTenths || v % cfg.priceStepTenths !== 0) {
        fail('prices', `${w.at} ${pm[1]} price ${v} outside ${cfg.priceMinTenths}..${cfg.priceMaxTenths} or off-step`);
      }
      if (Math.abs(v - lastPrice[pm[1]]) !== cfg.priceStepTenths) fail('prices', `${w.at} ${pm[1]} moved ${lastPrice[pm[1]]} -> ${v}`);
      lastPrice[pm[1]] = v;
    }
    if (/^Fantasy\/Futsal\/15\/PriceChanges\/\d+$/.test(w.path)) {
      for (const [n, r] of entriesOf(w.value)) {
        if (!isMap(r) || Math.abs(Number(r['delta'])) !== cfg.priceStepTenths) fail('price-changes', `${w.path}/${n} = ${stable(r)}`);
      }
    }
  }

  // F4. Managers: pipeline vs the independent expected ledger
  const managerMismatches: Json[] = [];
  const managerTable: Json[] = [];
  for (const m of managers) {
    const e = exp[m.uid];
    let expOverall = 0;
    const weeks: Json[] = [];
    for (const gw of gws) {
      const row = e.rows[gw.number];
      if (!row) continue;
      const pwMap: Record<string, PlayerWeek> = {};
      for (const n of Object.keys(market)) pwMap[n] = { points: indep[gw.number].points[n], played: indep[gw.number].played[n] };
      const result = scoreSquadWeek(row.locked, pwMap, cfg);
      row.grossTenths = totalTenths(result);
      row.netTenths = row.grossTenths - 10 * row.cost;
      expOverall += Math.trunc(row.netTenths / 10);
      const hist = db.get(`${F}/History/${gw.number}/${m.uid}`);
      const pub = db.get(`${F}/PublishedPicks/${gw.number}/${m.uid}`);
      const pipeCost = intLoose(db.get(`${F}/TransferCosts/${gw.number}/${m.uid}`));
      const pipeTotal = isMap(hist) ? hist['TotalTenths'] : null;
      const pipeChip = isMap(pub) ? (pub['chip'] ?? null) : 'NO SNAPSHOT';
      const mm = (field: string, expected: unknown, pipeline: unknown) => {
        if (canon(expected) !== canon(pipeline)) managerMismatches.push({ uid: m.uid, gw: gw.number, field, expected, pipeline });
      };
      mm('TransferState.Free at lock', row.freeBefore, row.pipelineFreeAtLock);
      mm('TransferState.UsedThisGw at lock', row.used, row.pipelineUsedAtLock);
      mm('TransferCosts (points)', row.cost, pipeCost);
      mm('effective chip (PublishedPicks)', row.effectiveChip, pipeChip);
      if (isMap(pub)) {
        const pubPicks = entriesOf(pub['picks']).map(([, p]) => String(p.playerId)).sort();
        mm('locked picks', row.locked.picks.map((p) => p.playerId).sort(), pubPicks);
        // FPL selling: the judge's running sale total (and its prices — an
        // honest client's prices ARE the judged ones) equal the ledger's.
        mm('realizedTenths (PublishedPicks)', row.realized, realizedOf(pub));
        const pubPrices = entriesOf(pub['picks']).map(([, p]) => `${p.playerId}@${p.priceTenths}`).sort();
        mm('locked prices (PublishedPicks)', row.locked.picks.map((p) => `${p.playerId}@${p.priceTenths}`).sort(), pubPrices);
      }
      if (isMap(hist)) mm('realizedTenths (History)', row.realized, realizedOf(hist));
      mm('History TotalTenths', row.netTenths, pipeTotal);
      const armband = result.slots.find((s) => s.multiplier > 1)?.playerId ?? null;
      weeks.push({
        gw: gw.number, date: gw.date, pipelineTenths: pipeTotal, expectedTenths: row.netTenths,
        pipelinePoints: childAt(db.get(`${F}/Leaderboards/Gameweek/${gw.number}`), m.uid)?.points ?? null,
        cost: pipeCost, chip: pipeChip, expectedChip: row.effectiveChip, used: row.pipelineUsedAtLock,
        armband, captain: row.locked.captainId, captainPlayed: indep[gw.number].played[row.locked.captainId],
        autoSubs: result.slots.filter((s) => s.autoSubbedIn).map((s) => s.playerId),
      });
    }
    const ov = childAt(db.get(`${F}/Leaderboards/Overall`), m.uid);
    if (ov?.points !== expOverall) managerMismatches.push({ uid: m.uid, field: 'Overall points', expected: expOverall, pipeline: ov?.points });
    managerTable.push({ uid: m.uid, name: m.name, persona: m.persona, overall: ov, expectedOverall: expOverall, weeks });
  }

  // F4b. Every client in the replay is honest and saves with the app's own
  // FPL-rule money, so the lock judge must never call a squad Invalid: one
  // would be a false verdict (or a client bug) — never a scored zero.
  for (const node of ['PublishedPicks', 'History']) {
    for (const [w, byUid] of entriesOf(db.get(`${F}/${node}`))) {
      for (const [uid, row] of entriesOf(byUid)) {
        if (isMap(row) && row['Invalid'] != null && row['Invalid'] !== false) {
          fail('no-invalid-squads', `${node}/${w}/${uid} Invalid ${stable(row['Invalid'])} ` +
            `(realizedTenths ${stable(row['realizedTenths'] ?? null)})`);
        }
      }
    }
  }

  // F5. Structural write-log checks
  const publishedClaims: Record<string, number> = {};
  for (const w of db.pipelineWrites) {
    if (/\/PublishedPicks\/\d+$/.test(w.path) && w.op === 'writeIfAbsent' && w.won) publishedClaims[w.path] = (publishedClaims[w.path] ?? 0) + 1;
  }
  const positionClaims: Record<string, number> = {};
  for (const w of db.pipelineWrites) {
    if (/\/LockedPositions\/\d+$/.test(w.path) && w.op === 'writeIfAbsent' && w.won) positionClaims[w.path] = (positionClaims[w.path] ?? 0) + 1;
    if (/\/LockedPositions\//.test(w.path) && w.op === 'write') fail('lock-positions-once', `${w.path} overwritten (plain write)`);
  }
  for (const gw of gws) {
    const lp = `${F}/LockedPositions/${gw.number}`;
    if (positionClaims[lp] !== 1) fail('lock-positions-once', `${lp} claimed ${positionClaims[lp] ?? 0} times`);
    // S15 positions never change during the replay: every snapshot = market.
    for (const [n, m] of Object.entries(market)) {
      if (childAt(db.get(lp), n) !== m.position) fail('lock-positions-once', `${lp}/${n} = ${childAt(db.get(lp), n)}, market ${m.position}`);
    }
    const p = `${F}/PublishedPicks/${gw.number}`;
    if (publishedClaims[p] !== 1) fail('lock-snapshot-once', `${p} claimed ${publishedClaims[p] ?? 0} times`);
    // Repriced/<gw> is written exactly TWICE by design since 672ff3f: the
    // once-only claim {At, Pending:true} (a transaction), then the final
    // {At} row. Prices themselves must move exactly once — that is the real
    // invariant: one PriceChanges/<gw> row, and the claim must precede it.
    const repPath = `${F}/Repriced/${gw.number}`;
    const repWrites = db.pipelineWrites.filter((w) => w.path === repPath);
    const pcWrites = db.pipelineWrites.filter((w) => w.path === `${F}/PriceChanges/${gw.number}`).length;
    if (repWrites.length < 1 || repWrites.length > 2) fail('reprice-once', `${repPath} written ${repWrites.length} times`);
    if (pcWrites > 1) fail('reprice-once', `PriceChanges/${gw.number} written ${pcWrites} times (prices moved twice)`);
    const finalRep = db.get(repPath) as Json | null;
    if (finalRep && (finalRep as Record<string, unknown>)['Pending'] === true) fail('reprice-once', `${repPath} left Pending (claim never finalized)`);
  }
  const gwStateSeq = db.pipelineWrites.filter((w) => w.path === `${F}/GwState`).map((w) => ({ at: w.at, ...(w.value as Json) }));
  const statusOrder: Record<string, number> = { open: 0, locked: 1, finalized: 2 };
  for (let i = 1; i < gwStateSeq.length; i++) {
    const a = gwStateSeq[i - 1];
    const b = gwStateSeq[i];
    const okAdvance = b.current === a.current + 1 && b.status === 'open' && a.status === 'finalized';
    const okSame = b.current === a.current && statusOrder[b.status] > statusOrder[a.status];
    if (!okAdvance && !okSame) fail('gwstate-sequence', `${a.at} ${a.current}/${a.status} -> ${b.at} ${b.current}/${b.status}`);
  }
  // Nothing outside the season (the global badge catalog excepted) — in
  // particular no trophy-cabinet write: the replay has no Users node, so a
  // podium badge for a fake (or real) uid never reaches Users/<uid>/Awards.
  for (const w of db.pipelineWrites) {
    if (!w.path.startsWith(`${F}/`) && !w.path.startsWith('Fantasy/BadgeCatalog/')) {
      fail('writes-in-scope', `${w.job} wrote ${w.path}`);
    }
  }
  // Badges (spec 2026-10-30): every award row is an auto row under its
  // deterministic id; none for a voided week; Top of the Week == the
  // Gameweek board's rank-1 managers, week by week (independent of badges.ts).
  const badgesNode = db.get(`${F}/Badges`);
  const voidedFinal = new Set(entriesOf(db.get(`${F}/Voided`)).filter(([, v]) => v === true).map(([k]) => Number(k)));
  const badgeCounts: Record<string, number> = {};
  const topByWeek: Record<number, string[]> = {};
  for (const [uid, byId] of entriesOf(badgesNode)) {
    for (const [id, row] of entriesOf(byId)) {
      const gwN = intLoose(row?.Gw);
      const expectId = row?.Gw === undefined ? `${row?.Badge}_season` : `${row?.Badge}_gw${gwN}`;
      if (row?.Source !== 'auto' || id !== expectId || typeof row?.At !== 'number') {
        fail('badges', `Badges/${uid}/${id} ${stable(row)}`);
      }
      if (row?.Gw !== undefined && voidedFinal.has(gwN)) fail('badges', `Badges/${uid}/${id} for voided GW${gwN}`);
      badgeCounts[String(row?.Badge)] = (badgeCounts[String(row?.Badge)] ?? 0) + 1;
      if (row?.Badge === 'topOfTheWeek') (topByWeek[gwN] ??= []).push(uid);
    }
  }
  for (const gw of gws) {
    if (voidedFinal.has(gw.number) || !isMap(childAt(db.get(`${F}/History`), gw.number))) continue;
    const top = entriesOf(childAt(db.get(`${F}/Leaderboards/Gameweek`), gw.number))
      .filter(([, r]) => r?.rank === 1).map(([u]) => u).sort();
    if (canon(top) !== canon((topByWeek[gw.number] ?? []).sort())) {
      fail('badges', `GW${gw.number} Top of the Week ${stable(topByWeek[gw.number] ?? [])} != rank-1 ${stable(top)}`);
    }
  }
  const finalizeSources = logs.filter((l) => l.message === 'fantasy gameweek finalized').map((l) => (l.context as Json)?.source);
  if (finalizeSources.some((s) => s !== 'publishedPicks')) fail('finalize-source', `sources seen: ${[...new Set(finalizeSources)].join(',')}`);
  for (const v of db.violations) fail('no-nan-undefined', `${v.job} ${v.path}: ${v.problem}`);
  for (const c of crashes) fail('no-crash', `${c.at} ${c.job}: ${c.error.split('\n')[0]}`);
  for (const l of logs) if (/failed/.test(l.message)) fail('no-crash', `${l.at} ${l.job}: ${l.message} ${stable(l.context)}`);
  const unexpectedNetwork = networkLog.filter((n) => !n.allowed);

  // ═══════════════════════════════════════════════════════════════════════
  // G. Data quality on the REAL S15 data
  // ═══════════════════════════════════════════════════════════════════════
  const dq = dataQuality(originalDate, lineups, snap.values[`${LEAGUE}/Teams`], market, indep, gws);

  // ═══════════════════════════════════════════════════════════════════════
  // H. Headline numbers + outputs
  // ═══════════════════════════════════════════════════════════════════════
  const totalsFinal = entriesOf(db.get(`${F}/PlayerTotals`)).map(([n, r]) => ({ name: n, points: r.points, ownershipPct: r.ownershipPct }));
  const seasonByName: Record<string, Json> = {};
  for (const r of seasonRows) seasonByName[r.name] = r;
  const topPlayers = [...totalsFinal].sort((a, b) => b.points - a.points || a.name.localeCompare(b.name)).slice(0, 10)
    .map((r) => ({ ...r, position: market[r.name].position, team: market[r.name].team,
      bonus: seasonByName[r.name].bonus, startPrice: startPrices[r.name], endPrice: finalPrices[r.name] }));
  const dreamTeams: Record<number, Json> = {};
  for (const gw of gws) {
    const dt = db.get(`${F}/DreamTeam/${gw.number}`);
    dreamTeams[gw.number] = isMap(dt) ? entriesOf(dt['Players']).map(([, r]) => ({ ...r, team: market[r.name]?.team })) : null;
  }
  // Not an invariant (the spec only says "eligible"), but worth surfacing:
  // Team of the Week rows whose player had no game / scored <= 0.
  const dreamTeamOddities: Json[] = [];
  for (const gw of gws) {
    for (const r of dreamTeams[gw.number] ?? []) {
      const played = indep[gw.number].played[r.name];
      if (!played || r.points <= 0) {
        dreamTeamOddities.push({ gw: gw.number, date: gw.date, name: r.name, position: r.position, team: r.team,
          points: r.points, played });
      }
    }
  }
  const movers = Object.keys(market).map((n) => ({ name: n, position: market[n].position, team: market[n].team,
    start: startPrices[n], end: finalPrices[n], net: finalPrices[n] - startPrices[n],
    moves: Object.values(priceChangesByGw).filter((c) => n in c).length }));
  const overallRows = entriesOf(db.get(`${F}/Leaderboards/Overall`)).map(([uid, r]) => ({ uid, name: managers.find((x) => x.uid === uid)?.name, ...r }))
    .sort((a, b) => a.rank - b.rank);

  const checks = {
    invariants: Object.fromEntries([
      'history-total', 'gameweek-board', 'overall-sum', 'overall-movement', 'ranks', 'ownership', 'player-totals',
      'dream-team', 'prices', 'price-changes', 'no-nan-undefined', 'lock-snapshot-once', 'lock-positions-once', 'reprice-once',
      'gwstate-sequence', 'finalize-source', 'no-crash', 'history-shape', 'writes-in-scope', 'badges',
      'no-invalid-squads', 'sale-baseline',
    ].map((k) => [k, { pass: !(invariantFailures[k]?.length), failures: invariantFailures[k] ?? [] }])),
    crossChecks: {
      playerWeeks: { compared: pwCompared, mismatches: pwMismatches },
      seasonVsSeedTool: { players: seasonRows.length, gapsBeyondBonus: seedGaps, seedStrays: seed.strays,
        openingPriceMismatches: openingMismatch, liveConfigDiffersFromDefault: liveCfgDiffersFromDefault },
      repricing: { mismatches: repriceMismatches },
      managers: { mismatches: managerMismatches, clientViewMismatches },
      idempotence: { divergentRewrites: idempotence, lateGw1Rerun: lateRerun },
    },
    observations: { dreamTeamOddities },
  };

  const meta = {
    generatedAt: new Date().toISOString(),
    snapshot: { fetchedAt: snap.fetchedAt, source: snap.source, offline, readPaths: READ_PATHS, skipped: snap.skipped },
    network: { requests: networkLog.length, allowed: networkLog.filter((n) => n.allowed).length, blocked: unexpectedNetwork },
    liveLockOverride, rehearsalLockOverride: 'auto (in memory only)',
    simWindow: { start: iso(simStart), end: iso(simEnd) },
    gameweeks: gws.map((g) => ({ number: g.number, date: g.date, lockUtc: g.lockUtc.toISOString(), games: indep[g.number].games })),
    jobCounts, wallMs, reads: db.readCount,
    pipelineWrites: db.pipelineWrites.length, simulatedWrites: db.simWrites.length,
    marketIssues,
  };

  const result: ReplayResult = {
    state: (isMap(finalState) ? finalState : {}) as Record<string, unknown>,
    skippedManagers,
    invariantFailures,
    crashes,
    managerUids: [...managers.map((m) => m.uid), ...acceptedExtras],
    managerLedgerMismatches: managerMismatches.length,
    pushesRecorded: pushLog.length,
    transfersCapped,
  };
  if (!opts.writeOutputs) return result;

  fs.writeFileSync(path.join(OUT_DIR, 'captured_writes.json'), JSON.stringify({
    meta,
    note: 'Every write the pipeline attempted, in order (job = production entry point that made it). ' +
      'simulatedWrites are the rehearsal\'s own client/live-scoring inputs. finalFantasyState is the in-memory ' +
      'Fantasy/Futsal/15 node at the end. NOTHING here was ever sent to the database.',
    pipelineWrites: db.pipelineWrites,
    simulatedWrites: db.simWrites,
    logs,
    crashes,
    violations: db.violations,
    finalFantasyState: finalState,
  }, null, 1));

  const summary = {
    meta, checks, dataQuality: dq,
    headline: { topPlayers, dreamTeams, movers, overall: overallRows, managers: managerTable, seasonRows, badgeCounts,
      clientSaves, priceChangesByGw,
      weeks: gws.map((g) => ({ gw: g.number, date: g.date, games: indep[g.number].games,
        topScorer: Object.entries(indep[g.number].points).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0],
        priceMoves: Object.keys(priceChangesByGw[g.number] ?? {}).length })) },
  };
  fs.writeFileSync(path.join(OUT_DIR, 'summary.json'), JSON.stringify(summary, null, 1));
  fs.writeFileSync(path.join(OUT_DIR, 'report_tables.md'), reportTables(summary, market));

  // Console verdict
  const invFails = Object.entries(checks.invariants).filter(([, v]) => !v.pass);
  console.log('Infinite Fantasy S15 rehearsal');
  console.log(`  snapshot ${snap.fetchedAt} (${offline ? 'offline cache' : 'live GET'}); skipped: ${snap.skipped.map((s) => `${s.path} ${s.status}`).join(', ') || 'none'}`);
  console.log(`  network: ${networkLog.filter((n) => n.allowed).length} GETs, ${unexpectedNetwork.length} blocked attempts`);
  console.log(`  jobs: ${stable(jobCounts)}  wall ${wallMs} ms  reads ${db.readCount}`);
  console.log(`  pipeline writes captured: ${db.pipelineWrites.length} (never sent anywhere)`);
  console.log(`  invariants: ${invFails.length === 0 ? 'ALL PASS' : 'FAIL ' + invFails.map(([k, v]) => `${k}(${v.failures.length})`).join(' ')}`);
  console.log(`  player-week cross-check: ${pwCompared} compared, ${pwMismatches.length} mismatches`);
  console.log(`  season vs seed-tool: ${seedGaps.length} gaps beyond bonus; opening-price mismatches ${openingMismatch.length}`);
  console.log(`  repricing cross-check: ${repriceMismatches.length} mismatches`);
  console.log(`  manager ledger cross-check: ${managerMismatches.length} mismatches; client-view mismatches ${clientViewMismatches.length}`);
  console.log(`  rerun idempotence: ${idempotence.length} divergent rewrites; late GW1 rerun ${stable(lateRerun).slice(0, 200)}`);
  console.log(`  late GW1 rerun ownership changes: ${lateRerun.ownershipChanged.length}`);
  const dreamTeamNonPlayers = dreamTeamOddities.filter((o) => o.played !== true);
  console.log(`  Dream Team rows for players who did not play: ${dreamTeamNonPlayers.length}` +
    `${dreamTeamNonPlayers.length ? ' ' + stable(dreamTeamNonPlayers) : ''}`);
  const managerOverall = managerTable.map((m) => `${m.name} ${m.overall?.points}/${m.expectedOverall}`).join(', ');
  console.log(`  manager Overall (pipeline/expected): ${managerOverall}`);
  const finishedKey = `${LEAGUE}/Finished`;
  console.log(`  badges: ${stable(badgeCounts)}; ${finishedKey} ` +
    `${finishedKey in snap.values ? stable(snap.values[finishedKey]) : 'not in this snapshot (season-end badges not exercised)'}`);
  console.log(`  outputs: ${OUT_DIR}`);
  return result;
}

// ═════════════════════════════════════════════════════════════════════════
// G. Data quality survey (real data, read-only)
// ═════════════════════════════════════════════════════════════════════════

function dataQuality(
  dateNode: unknown, lineups: unknown, teamsNode: unknown,
  market: Record<string, MarketEntry>, indep: Record<number, IndepWeek>, gws: Gameweek[],
): Json {
  const rosterOf = (team: string): string[] => (isMap(lineups) && isMap(lineups[team]) ? Object.keys(lineups[team]) : []);
  const teamsOfName: Record<string, string[]> = {};
  for (const [team, lu] of entriesOf(lineups)) for (const n of Object.keys(isMap(lu) ? lu : {})) (teamsOfName[n] ??= []).push(team);
  const typeCounts: Record<string, number> = {};
  const offRoster: Record<string, Json> = {};
  const gameIssues: Json[] = [];
  const bothSides: Json[] = [];
  const activityTotals: Record<string, Record<string, number>> = {};
  const computedTable: Record<string, Json> = {};
  const scoreKeys: Record<string, number> = {};
  const sortedDates = gws.map((g) => g.date);
  for (const date of sortedDates) {
    for (const [idx, g] of entriesOf(childAt(dateNode, date))) {
      const id = `${date}#${idx}`;
      if (!isMap(g)) { gameIssues.push({ game: id, issue: 'game node is not a map' }); continue; }
      if (g['status'] === undefined || g['status'] === null) gameIssues.push({ game: id, issue: 'missing status' });
      else if (intLoose(g['status']) !== 2) gameIssues.push({ game: id, issue: `status ${g['status']} (not final)` });
      if (typeof g['status'] === 'string') gameIssues.push({ game: id, issue: `status stored as string "${g['status']}"` });
      if (String(g['Stage'] ?? '').trim().toLowerCase() === 'friendly') gameIssues.push({ game: id, issue: 'friendly (excluded from fantasy)' });
      const sides: Array<{ team: string; score: number; activity: unknown }> = [];
      for (const s of [1, 2]) {
        const team = String(g[`team${s}`] ?? '');
        const rawScore = g[`team${s}score`] ?? g[`team${s}Score`];
        const key = g[`team${s}score`] !== undefined ? `team${s}score` : (g[`team${s}Score`] !== undefined ? `team${s}Score (legacy)` : 'missing');
        scoreKeys[`${key} as ${typeof rawScore}`] = (scoreKeys[`${key} as ${typeof rawScore}`] ?? 0) + 1;
        if (rawScore === undefined || rawScore === null || !/^[+-]?\d+$/.test(String(rawScore).trim())) {
          gameIssues.push({ game: id, issue: `team${s} score missing/non-numeric (${stable(rawScore)})` });
        }
        if (team.length === 0) gameIssues.push({ game: id, issue: `team${s} name missing` });
        else if (rosterOf(team).length === 0) gameIssues.push({ game: id, issue: `team ${team} has no Line Ups roster` });
        if (g[`team${s}attendance`] !== undefined) gameIssues.push({ game: id, issue: `team${s}attendance present` });
        sides.push({ team, score: intLoose(rawScore), activity: g[`team${s}activity`] });
      }
      const namesBySide: Array<Set<string>> = [];
      sides.forEach((side, si) => {
        const names = new Set<string>();
        let goalEvents = 0;
        let leaves = 0;
        const visitLeaf = (leaf: unknown) => {
          if (!isMap(leaf)) return;
          const ev = Object.entries(leaf).find(([k]) => !k.startsWith('_'));
          if (!ev) return;
          leaves++;
          const [type, who] = ev;
          const name = who == null ? '' : String(who);
          typeCounts[type] = (typeCounts[type] ?? 0) + 1;
          const t = type.toLowerCase().trim();
          if (t === 'goal' || t === 'pengoal' || t === 'penalty goal') goalEvents++;
          if (name.length === 0) { gameIssues.push({ game: id, issue: `${side.team}: ${type} event with empty player` }); return; }
          names.add(name);
          (activityTotals[name] ??= {})[type] = (activityTotals[name]?.[type] ?? 0) + 1;
          if (!rosterOf(side.team).includes(name)) {
            const k = `${name} @ ${side.team}`;
            const row = (offRoster[k] ??= { name, recordedFor: side.team, onRosterOf: teamsOfName[name] ?? [], events: {}, games: [] as string[] });
            row.events[type] = (row.events[type] ?? 0) + 1;
            if (!row.games.includes(id)) row.games.push(id);
          }
        };
        const visitBucket = (b: unknown) => {
          if (Array.isArray(b)) b.forEach(visitLeaf);
          else if (isMap(b)) Object.values(b).forEach(visitLeaf);
        };
        if (Array.isArray(side.activity)) side.activity.forEach(visitBucket);
        else if (isMap(side.activity)) Object.values(side.activity).forEach(visitBucket);
        if (side.activity === undefined || leaves === 0) {
          gameIssues.push({ game: id, issue: `${side.team}: no activity recorded (score ${side.score})` });
        }
        if (goalEvents !== side.score) {
          gameIssues.push({ game: id, issue: `${side.team}: ${goalEvents} goal events vs score ${side.score}` });
        }
        namesBySide[si] = names;
      });
      if (namesBySide.length === 2) {
        for (const n of namesBySide[0]) if (namesBySide[1].has(n)) bothSides.push({ game: id, name: n });
      }
      // standings recomputed from results
      if (sides.length === 2 && sides[0].team && sides[1].team) {
        const [a, b] = sides;
        for (const [me, op] of [[a, b], [b, a]] as const) {
          const r = (computedTable[me.team] ??= { GP: 0, Wins: 0, Draws: 0, Losses: 0, GS: 0, GC: 0, Points: 0 });
          r.GP++; r.GS += me.score; r.GC += op.score;
          if (me.score > op.score) { r.Wins++; r.Points += 3; } else if (me.score === op.score) { r.Draws++; r.Points += 1; } else r.Losses++;
        }
      }
    }
  }
  const tableMismatches: Json[] = [];
  for (const [team, row] of entriesOf(teamsNode)) {
    const c = computedTable[team];
    for (const k of ['GP', 'Wins', 'Draws', 'Losses', 'GS', 'GC', 'Points']) {
      if (!c || intLoose(row?.[k]) !== c[k]) tableMismatches.push({ team, field: k, teamsNode: row?.[k], fromResults: c?.[k] });
    }
  }
  // Line Ups aggregate stats vs activity-derived counts (by name)
  const aggMap: Record<string, string> = { Goals: 'Goal', Assists: 'Assist', Yellow: 'Yellow', Red: 'Red' };
  const lineupVsActivity: Json[] = [];
  for (const [team, lu] of entriesOf(lineups)) {
    if (!isMap(lu)) continue;
    for (const [name, info] of Object.entries(lu)) {
      if (!isMap(info)) continue;
      for (const [aggKey, evKey] of Object.entries(aggMap)) {
        const agg = intLoose(info[aggKey]);
        const act = activityTotals[name]?.[evKey] ?? 0;
        if (agg !== act) lineupVsActivity.push({ name, team, stat: aggKey, lineUps: agg, activities: act });
      }
    }
  }
  const lineupHasSaves = Object.values(isMap(lineups) ? lineups : {}).some((lu: any) =>
    isMap(lu) && Object.values(lu).some((i: any) => isMap(i) && intLoose(i['Saves']) > 0));
  // Position sanity: fantasy position vs lineup hints
  const positionFlags: Json[] = [];
  for (const [team, lu] of entriesOf(lineups)) {
    if (!isMap(lu)) continue;
    for (const [name, info] of Object.entries(lu)) {
      const m = market[name];
      if (!m || !isMap(info)) continue;
      const goals = activityTotals[name]?.['Goal'] ?? 0;
      const saves = intLoose(info['Saves']);
      const number = String(info['number'] ?? '');
      if (m.position !== 'GK' && (number.toUpperCase() === 'GK' || saves >= 50)) {
        positionFlags.push({ name, team, fantasyPosition: m.position, hint: `lineup number "${number}", ${saves} saves — looks like the team's keeper` });
      }
      if (m.position === 'GK' && goals >= 3) {
        positionFlags.push({ name, team, fantasyPosition: m.position, hint: `${goals} goals as a GK (GK goal = +10 pts) — looks like an outfield player` });
      }
    }
  }
  // Bonus anomalies from the independent replay
  const nonMarketBonus: Json[] = [];
  const floodGames: Json[] = [];
  for (const w of Object.values(indep)) {
    const byGame: Record<string, BonusAward[]> = {};
    for (const a of w.awards) (byGame[`${a.date}#${a.game}`] ??= []).push(a);
    for (const [g, list] of Object.entries(byGame)) {
      if (list.length > 3) floodGames.push({ game: g, recipients: list.length, bonusPointsAwarded: list.reduce((s, a) => s + a.bonus, 0),
        sample: list.slice(0, 8).map((a) => `${a.name} (${a.team}) +${a.bonus} bps ${a.bps}`) });
      for (const a of list) if (!a.market) nonMarketBonus.push({ game: g, name: a.name, team: a.team, bonus: a.bonus, bps: a.bps });
    }
  }
  const dupNames = Object.entries(teamsOfName).filter(([, t]) => t.length > 1).map(([n, t]) => ({ name: n, teams: t }));
  const allTypes = ['Goal', 'PenGoal', 'Assist', 'Save', 'PenSaved', 'PenMissed', 'OwnGoal', 'DPL', 'Yellow', 'SecondYellow', 'Red', 'Foul', 'Substitution'];
  return {
    activityTypeCounts: typeCounts,
    activityTypesNeverRecorded: allTypes.filter((t) => !(t in typeCounts)),
    lineUpsCarrySavesButNoSaveEvents: lineupHasSaves && !('Save' in typeCounts),
    offRosterActivityNames: Object.values(offRoster).sort((a: Json, b: Json) => a.name.localeCompare(b.name)),
    gameIssues,
    sameNameBothSidesOfAGame: bothSides,
    duplicateNamesAcrossTeams: dupNames,
    teamsTableVsResults: tableMismatches,
    lineUpsAggregatesVsActivities: lineupVsActivity,
    positionFlags,
    bonusToNonMarketNames: nonMarketBonus,
    bonusFloodGames: floodGames,
    scoreFieldShapes: scoreKeys,
  };
}

// ═════════════════════════════════════════════════════════════════════════
// H. Markdown tables for the report
// ═════════════════════════════════════════════════════════════════════════

function reportTables(s: Json, market: Record<string, MarketEntry>): string {
  const L: string[] = [];
  const h = s.headline;
  L.push('## Top 10 players by fantasy points (PlayerTotals, bonus included)', '');
  L.push('| # | Player | Pos | Team | Points | of which bonus | Price start → end |', '|---|---|---|---|---|---|---|');
  h.topPlayers.forEach((r: Json, i: number) => L.push(`| ${i + 1} | ${r.name} | ${r.position} | ${r.team} | ${r.points} | ${r.bonus} | ${money(r.startPrice)} → ${money(r.endPrice)} |`));
  L.push('', '## Team of the Week (DreamTeam) per gameweek', '');
  for (const w of h.weeks) {
    const dt = h.dreamTeams[w.gw];
    L.push(`- **GW${w.gw} (${prettyDate(w.date)}, ${w.games} games):** ` +
      (dt ? dt.map((r: Json) => `${r.name} (${r.position}, ${r.team}) ${r.points}`).join(' · ') : '—'));
  }
  L.push('', '## Biggest price movers (season start → end)', '');
  const movers = [...h.movers].sort((a: Json, b: Json) => b.net - a.net || a.name.localeCompare(b.name));
  L.push('| Player | Pos | Team | Start | End | Net | Weeks moved |', '|---|---|---|---|---|---|---|');
  for (const r of [...movers.slice(0, 6), ...movers.slice(-6)]) {
    L.push(`| ${r.name} | ${r.position} | ${r.team} | ${money(r.start)} | ${money(r.end)} | ${r.net > 0 ? '+' : ''}${(r.net / 10).toFixed(1)}M | ${r.moves} |`);
  }
  L.push('', '## Synthetic managers — final standings', '');
  L.push('| Rank | Manager | Points | Movement (last week) |', '|---|---|---|---|');
  for (const r of h.overall) L.push(`| ${r.rank} | ${r.name} | ${r.points} | ${r.movement ?? '—'} |`);
  L.push('', '## Synthetic managers — week by week (pipeline points; chip; transfer cost)', '');
  const head = ['Manager', ...h.weeks.map((w: Json) => `GW${w.gw}`)];
  L.push(`| ${head.join(' | ')} |`, `|${head.map(() => '---').join('|')}|`);
  for (const m of h.managers) {
    const cells = m.weeks.map((w: Json) => {
      const bits = [String(w.pipelinePoints)];
      if (w.chip && w.chip !== 'NO SNAPSHOT') bits.push(w.chip === 'tripleCaptain' ? 'TC' : w.chip === 'benchBoost' ? 'BB' : w.chip === 'freeHit' ? 'FH' : w.chip === 'wildcard' ? 'WC' : w.chip);
      if (w.cost) bits.push(`-${w.cost}`);
      if (w.pipelineTenths !== w.expectedTenths) bits.push(`(exp ${Math.trunc(w.expectedTenths / 10)})`);
      return bits.join(' ');
    });
    L.push(`| ${m.name} | ${cells.join(' | ')} |`);
  }
  L.push('', `_(market: ${Object.keys(market).length} players)_`, '');
  return L.join('\n');
}

// Run the rehearsal only when executed directly (npm run rehearse:s15) —
// the fill tool imports runReplay without triggering it.
if (typeof require !== 'undefined' && require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
}
