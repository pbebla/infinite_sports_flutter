// Duplicate-account merge tool - the command line around the reviewed pure
// planner (merge_accounts_logic.ts). Plan 2026-11-06-merge-duplicate-accounts,
// Task 5; design D1-D6, D10, D15, D16; Review Focus 1 and 4.
//
// MODES (run from functions/)
//   npm run merge:accounts                       DRY RUN (default): admin GETs
//                                                of every snapshot path + the
//                                                kept emails (masked in
//                                                memory); prints the plan,
//                                                the refusals and a plan
//                                                digest; writes NOTHING
//   npm run merge:accounts -- --apply --expect-plan <digest>
//                                                (the digest is REQUIRED on
//                                                production; the emulator may
//                                                omit it) re-plans, refuses a
//                                                plan other than the dry
//                                                run's, backs up every
//                                                planned path to
//                                                rehearsal_out/merge_backup_<ISO>.json,
//                                                then per cluster: re-reads
//                                                every target and refuses the
//                                                cluster if anything moved
//                                                since the plan (Review Focus
//                                                1), writes it, and after the
//                                                first stamped old account
//                                                runs the canary (Focus 4)
//   npm run merge:accounts -- --undo <backupFile>
//                                                restores every path the apply
//                                                wrote that still holds what
//                                                it wrote; refuses a backup of
//                                                the wrong kind / target / run
//   npm run merge:accounts -- --find-dupes <registrationId>
//                                                D16, read-only: submitters
//                                                whose account name matches a
//                                                roster row of that sport held
//                                                by another account or none
//   npm run merge:accounts -- --notify [--send]
//                                                WITHOUT --send: a PREVIEW -
//                                                the same checks, prints what
//                                                it would write (people by
//                                                label, number of notices, the
//                                                push audience size) and
//                                                writes NOTHING. With --send:
//                                                D11 + D12: tells the merged
//                                                players which email to use.
//                                                Refuses unless EVERY old
//                                                account of the map is stamped
//                                                (Users/<old>/MergedInto = the
//                                                map's kept account). Writes
//                                                MergeNotices/<old> =
//                                                {KeepHint, CreatedAt} for each
//                                                old account that has none (the
//                                                onMergeNoticeCreated trigger
//                                                emails its Auth address, once)
//                                                and ONE Campaigns/<id> (a push
//                                                to the kept accounts that had
//                                                an old account; the id derives
//                                                from their uids, so a re-run
//                                                finds it). A second run writes
//                                                nothing. SENDING IS OUTWARD:
//                                                run it only when the owner says
//   --map <file>        another mapping file (default
//                       tools/rehearsal_out/merge_map.json)
//   --fake-emails       emulator only: made-up kept emails instead of
//                       Identity Toolkit (required under the emulator)
//   --no-canary         emulator only: skip the canary (no mirror function
//                       runs in the database emulator)
//
// SAFETY
//   - The dry run and --find-dupes read through a READ-ONLY client (every
//     PUT/DELETE throws before the network) behind a fetch guard that only
//     lets GETs to the database and the two POSTs that read (the OAuth token
//     exchange and Identity Toolkit accounts:lookup) out of the process.
//   - Every GET passes READ_RULES (no whole Users, no Submissions bodies -
//     only their keys - so no answers, emails or phones are ever fetched by
//     --find-dupes). Every PUT/DELETE must be a path of this run's plan that
//     passed assertMergePaths, or a validated entry of the backup being
//     undone.
//   - A malformed map stops the dry run and --apply (the modes that read
//     it) before any network call ("fix the map file first").
//   - A production --apply must carry --expect-plan <digest> from the dry
//     run the owner read; it refuses before any read without it.
//   - --notify is a read-only PREVIEW (read-only client + fetch guard); only
//     --notify --send writes, and it writes only MergeNotices/<old> (old
//     accounts whose node is absent) and the one Campaigns/<id> it computed - nothing else passes
//     the write guard. Its hints are the masked ones --apply already stamped
//     on each old account; no address is read, written or printed.
//   - Emails: looked up only for the kept accounts and masked (maskEmail)
//     inside the lookup itself; never printed, logged or stored unmasked.
//     The tool prints roster names, team names, seasons and counts - not
//     uids (an account is "kept account" / "old account #n").
//   - Admin calls send the firebase-tools OAuth token in an
//     `Authorization: Bearer` header - never in a URL, log or error message.
//   - FIREBASE_DATABASE_EMULATOR_HOST (a local host:port) switches every
//     database call to the emulator; a backup records its target, so an
//     emulator backup can never be undone against production or vice versa.

import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import { maskEmail } from '../src/lib/mask_email';
import { mergeNoticeCampaign, mergeNoticeCampaignId } from '../src/lib/merge_notice';
import { accessToken } from './admin_rest';
import {
  afcUidPath, assertMergePaths, buildMergePlan, fantasyConfigPath, isCopyableInformation,
  LEAGUE_SPORTS, leagueUidPath, looksMasked, MergeMap, MergePlan, MergeSnapshot, parseRosterUidPath, PlanWrite,
  userPath,
} from './merge_accounts_logic';

/* eslint-disable @typescript-eslint/no-explicit-any */

export const PROJECT_ID = 'infinite-sports-app';
export const DB_URL = `https://${PROJECT_ID}.firebaseio.com`;
export const LOOKUP_URL =
  `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT_ID}/accounts:lookup`;
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';
export const BACKUP_KIND = 'merge-accounts-backup';
const BACKUP_VERSION = 1;
export const DEFAULT_MAP = path.join('tools', 'rehearsal_out', 'merge_map.json');
const AFC_SEASONS = 'AFC San Jose/Seasons';
export const CANARY_TIMEOUT_MS = 90_000;
export const CANARY_POLL_MS = 10_000;
const UID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const SEASON_RE = /^\d{1,4}$/;
const REG_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const STAMPS = ['MergedInto', 'MergedAt', 'MergedHint'];

const USAGE = 'Usage: npm run merge:accounts [-- --apply --expect-plan <digest> | ' +
  '-- --undo <backupFile> | -- --find-dupes <registrationId> | -- --notify [--send]] [--map <file>] ' +
  '[--fake-emails] [--no-canary]';

const isPlainMap = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === 'object' && !Array.isArray(v);
const keysOf = (v: unknown): string[] => (isPlainMap(v) ? Object.keys(v) : []);
const hasUidValue = (v: unknown): v is string => typeof v === 'string' && v.trim() !== '';

/** Key-sorted JSON, so equal values always compare (and digest) equal. */
export function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (isPlainMap(v)) {
    return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
  }
  return JSON.stringify(v ?? null);
}
const same = (a: unknown, b: unknown): boolean => canonical(a ?? null) === canonical(b ?? null);

// ── database client + guards ───────────────────────────────────────────────

export interface Rest {
  get(p: string, opts?: { shallow?: boolean }): Promise<unknown>;
  put(p: string, value: unknown): Promise<void>;
  del(p: string): Promise<void>;
}

export interface Target {
  kind: 'production' | 'emulator';
  base: string;
  /** Extra query string (the emulator's namespace); never a token. */
  query: string;
  label: string;
}

/** Production, or the RTDB emulator when FIREBASE_DATABASE_EMULATOR_HOST is
 *  set - and then only a local host:port. */
export function resolveTarget(env: NodeJS.ProcessEnv = process.env): Target {
  const host = env.FIREBASE_DATABASE_EMULATOR_HOST;
  if (host === undefined || host === '') {
    return { kind: 'production', base: DB_URL, query: '', label: 'PRODUCTION' };
  }
  if (!/^(127\.0\.0\.1|localhost|\[::1\]):\d{2,5}$/.test(host)) {
    throw new Error('Refusing: FIREBASE_DATABASE_EMULATOR_HOST must be a local host:port.');
  }
  return { kind: 'emulator', base: `http://${host}`, query: `ns=${PROJECT_ID}`, label: `EMULATOR ${host}` };
}

const SPORTS = LEAGUE_SPORTS.join('|');
/** Every GET the tool may make. `shallowOnly` paths are read as keys only. */
const READ_RULES: ReadonlyArray<{ re: RegExp; shallowOnly?: boolean }> = [
  { re: /^Users\/[A-Za-z0-9_-]+$/ },
  { re: /^Users\/[A-Za-z0-9_-]+\/(First Name|Last Name|MergedInto|MergedAt|MergedHint|ProfileUrl)$/ },
  { re: /^Users\/[A-Za-z0-9_-]+\/Information\/[^/]+$/ },
  { re: /^Users\/[A-Za-z0-9_-]+\/Played\/[^/]+\/Season \d+$/ },
  { re: new RegExp(`^(${SPORTS})$`), shallowOnly: true },
  { re: new RegExp(`^(${SPORTS})/\\d{1,4}/Line Ups$`) },
  { re: new RegExp(`^(${SPORTS})/\\d{1,4}/Line Ups/[^/]+/[^/]+(/UID)?$`) },
  { re: /^AFC San Jose\/Seasons$/, shallowOnly: true },
  { re: /^AFC San Jose\/Seasons\/[^/]+\/Roster$/ },
  { re: /^AFC San Jose\/Seasons\/[^/]+\/Roster\/[^/]+(\/UID)?$/ },
  { re: new RegExp(`^Fantasy/(${SPORTS})/\\d{1,4}/Config$`), shallowOnly: true },
  { re: /^PublicProfiles\/[A-Za-z0-9_-]+$/, shallowOnly: true },
  { re: /^Registrations\/[A-Za-z0-9_-]+\/Config$/ },
  { re: /^Registrations\/[A-Za-z0-9_-]+\/Submissions$/, shallowOnly: true },
  // --notify: is the notice / the campaign already there (keys only).
  { re: /^MergeNotices\/[A-Za-z0-9_-]+$/, shallowOnly: true },
  { re: /^Campaigns\/merge-notice-[0-9a-f]{16}$/, shallowOnly: true },
];

export function assertReadAllowed(p: string, shallow: boolean): void {
  const rule = READ_RULES.find((r) => r.re.test(p));
  if (!rule) throw new Error(`Refusing GET ${p}: not a path the merge tool reads`);
  if (rule.shallowOnly && !shallow) throw new Error(`Refusing GET ${p}: only its keys may be read`);
}

export interface GuardOptions {
  /** The dry run and --find-dupes: every PUT/DELETE throws. */
  readOnly: boolean;
  /** Otherwise: the only paths a PUT/DELETE may touch. */
  allowedWrites?: ReadonlySet<string>;
}

export function assertWriteAllowed(method: string, p: string, opts: GuardOptions): void {
  if (opts.readOnly) throw new Error(`Refusing ${method} ${p}: read-only client (dry run / find-dupes)`);
  if (!opts.allowedWrites || !opts.allowedWrites.has(p)) {
    throw new Error(`Refusing ${method} ${p}: not on this run's merge allowlist`);
  }
}

/** Wraps any client so every call passes the guards BEFORE it reaches the
 *  network (or the test stub). */
export function guardRest(inner: Rest, opts: GuardOptions): Rest {
  return {
    get: async (p, o) => {
      assertReadAllowed(p, o?.shallow === true);
      return inner.get(p, o);
    },
    put: async (p, value) => {
      assertWriteAllowed('PUT', p, opts);
      await inner.put(p, value);
    },
    del: async (p) => {
      assertWriteAllowed('DELETE', p, opts);
      await inner.del(p);
    },
  };
}

/** The real database client (REST). The bearer token is put in the header
 *  only; errors name the method + path, never the URL. */
export function httpRest(target: Target, token: () => Promise<string>): Rest {
  const call = async (method: string, p: string, body?: unknown, shallow = false): Promise<unknown> => {
    const qs = [target.query, shallow ? 'shallow=true' : ''].filter((s) => s !== '').join('&');
    const url = `${target.base}/${p.split('/').map(encodeURIComponent).join('/')}.json` +
      (qs ? `?${qs}` : '');
    const headers: Record<string, string> = { Authorization: `Bearer ${await token()}` };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let res: Response;
    try {
      res = await fetch(url, { method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    } catch (err) {
      throw new Error(`${method} ${p} failed: ${(err as Error)?.message ?? 'network error'}`);
    }
    const text = await res.text();
    if (!res.ok) throw new Error(`${method} ${p} -> HTTP ${res.status}: ${text.slice(0, 200)}`);
    return text.length > 0 ? JSON.parse(text) : null;
  };
  return {
    get: (p, o) => call('GET', p, undefined, o?.shallow === true),
    put: async (p, value) => { await call('PUT', p, value); },
    del: async (p) => { await call('DELETE', p); },
  };
}

/** Read-only runs (dry run, --find-dupes): from here on the process may only
 *  GET from the database and POST to the two endpoints that READ (the OAuth
 *  token exchange, Identity Toolkit accounts:lookup). Anything else throws
 *  before it leaves the process. Returns the undo. */
export function installReadOnlyFetchGuard(target: Target): () => void {
  const original = globalThis.fetch;
  const dbOrigin = new URL(target.base).origin;
  const guarded = async (input: any, init?: any): Promise<Response> => {
    const href = typeof input === 'string' ? input : input instanceof URL ? input.href : String(input?.url);
    const url = new URL(href);
    const method = String(init?.method ?? input?.method ?? 'GET').toUpperCase();
    const where = `${url.origin}${url.pathname}`;
    const ok = (method === 'GET' && url.origin === dbOrigin) ||
      (method === 'POST' && where === OAUTH_TOKEN_URL) ||
      (method === 'POST' && where === LOOKUP_URL);
    if (!ok) throw new Error(`Refusing ${method} ${where}: this run is read-only`);
    return original(input, init);
  };
  globalThis.fetch = guarded as typeof fetch;
  return () => { globalThis.fetch = original; };
}

/** uid -> the kept email ALREADY MASKED (maskEmail). An account with no
 *  email is simply absent. Raw emails never leave the implementation. */
export type HintLookup = (uids: string[]) => Promise<Record<string, string>>;

/** Identity Toolkit accounts:lookup with the admin bearer token. */
export function identityToolkitHints(token: () => Promise<string>): HintLookup {
  return async (uids) => {
    const out: Record<string, string> = {};
    for (let i = 0; i < uids.length; i += 100) {
      const res = await fetch(LOOKUP_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${await token()}`,
          'Content-Type': 'application/json',
          'x-goog-user-project': PROJECT_ID,
        },
        body: JSON.stringify({ localId: uids.slice(i, i + 100) }),
      });
      const json: any = await res.json().catch(() => null);
      if (!res.ok) {
        const why = typeof json?.error?.message === 'string' ? `, ${json.error.message.slice(0, 160)}` : '';
        throw new Error(`Identity Toolkit lookup failed (HTTP ${res.status}${why}).`);
      }
      for (const u of Array.isArray(json?.users) ? json.users : []) {
        if (typeof u?.localId === 'string' && typeof u?.email === 'string' && u.email.includes('@')) {
          out[u.localId] = maskEmail(u.email);
        }
      }
    }
    return out;
  };
}

/** --fake-emails (emulator only): a made-up, masked address per kept uid. */
export const fakeHints: HintLookup = async (uids) => {
  const out: Record<string, string> = {};
  [...uids].sort().forEach((u, i) => { out[u] = maskEmail(`rehearsal${i + 1}player@example.test`); });
  return out;
};

/** A JSON file's parsed contents. Errors are generic on purpose: neither the
 *  fs nor the JSON.parse message (which can quote the file) is echoed. */
export function readJsonFile(file: string, what: string): unknown {
  let text: string;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    throw new Error(`Couldn't read ${what} ${file} - the file is missing or cannot be opened.`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Couldn't read ${what} ${file} - not valid JSON.`);
  }
}

/** The mapping file (D15). A malformed map stops the modes that use it (the
 *  dry run and --apply) before any network call. */
export function loadMap(file: string): MergeMap {
  const raw: any = readJsonFile(file, 'the merge map');
  if (!isPlainMap(raw) || !Array.isArray(raw.clusters)) {
    throw new Error(`The merge map ${file} has no "clusters" list.`);
  }
  // assertMergePaths validates the map itself first (uids, duplicates, name
  // rows, firstNameFix) and throws "Refusing merge map: ..." - not caught.
  assertMergePaths([], raw as unknown as MergeMap, { nodes: {}, keptHints: {} });
  return raw as unknown as MergeMap;
}

const oldsOf = (map: MergeMap): string[] => map.clusters.flatMap((c) => c.old ?? []);
const uidsOf = (map: MergeMap): string[] => [...new Set(map.clusters.flatMap((c) => [c.keep, ...(c.old ?? [])]))];

const clusterOfUid = (uid: string, map: MergeMap): MergeMap['clusters'][number] | undefined =>
  map.clusters.find((x) => x.keep === uid || (x.old ?? []).includes(uid));

/** "kept account Played/Futsal/Season 11", a roster label, ... - never a uid
 *  and never a raw path: anything else is "an unrecognized path" (with the
 *  cluster's name when a map uid is in it). */
export function labelOf(p: string, map: MergeMap): string {
  const ref = parseRosterUidPath(p);
  if (ref) {
    return ref.kind === 'league'
      ? `roster ${ref.sport} Season ${ref.season}, ${ref.team}, "${ref.name}"`
      : `roster AFC San Jose "${ref.season}", "${ref.name}"`;
  }
  const m = /^Users\/([^/]+)(?:\/(.+))?$/.exec(String(p));
  const c = m ? clusterOfUid(m[1], map) : undefined;
  if (m && c) {
    const role = c.keep === m[1] ? 'kept account' : `old account #${(c.old ?? []).indexOf(m[1]) + 1}`;
    return `${c.who}: ${role}${m[2] ? ` ${m[2]}` : ''}`;
  }
  const pp = /^PublicProfiles\/([^/]+)$/.exec(String(p));
  const pc = pp ? clusterOfUid(pp[1], map) : undefined;
  if (pp && pc) return `public profile of ${labelOf(userPath(pp[1]), map)}`;
  const known = String(p).split('/').map((seg) => clusterOfUid(seg, map)).find((x) => x !== undefined);
  return known ? `${known.who}: an unrecognized path` : 'an unrecognized path';
}

// ── snapshot ───────────────────────────────────────────────────────────────

export interface RosterRow {
  /** A league sport, or 'AFC San Jose'. */
  sport: string;
  season: string;
  /** League rows only. */
  team?: string;
  name: string;
  uid: unknown;
  row: Record<string, unknown>;
}

const bySeason = (a: string, b: string): number => Number(a) - Number(b) || (a < b ? -1 : a > b ? 1 : 0);

/** Every roster row of [sports] (league `Line Ups`), plus the AFC San Jose
 *  rosters when [withAfc]. Seasons come from shallow key reads. */
export async function scanRosters(
  db: Rest, sports: readonly string[], withAfc: boolean,
): Promise<{ rows: RosterRow[]; seasons: Record<string, number> }> {
  const rows: RosterRow[] = [];
  const seasons: Record<string, number> = {};
  for (const sport of sports) {
    const keys = keysOf(await db.get(sport, { shallow: true })).filter((k) => SEASON_RE.test(k)).sort(bySeason);
    seasons[sport] = keys.length;
    for (const season of keys) {
      const lineUps = await db.get(`${sport}/${season}/Line Ups`);
      for (const [team, players] of Object.entries(isPlainMap(lineUps) ? lineUps : {})) {
        for (const [name, row] of Object.entries(isPlainMap(players) ? players : {})) {
          if (isPlainMap(row)) rows.push({ sport, season, team, name, uid: row['UID'], row });
        }
      }
    }
  }
  if (withAfc) {
    const keys = keysOf(await db.get(AFC_SEASONS, { shallow: true })).sort(bySeason);
    seasons['AFC San Jose'] = keys.length;
    for (const season of keys) {
      const roster = await db.get(`${AFC_SEASONS}/${season}/Roster`);
      for (const [name, row] of Object.entries(isPlainMap(roster) ? roster : {})) {
        if (isPlainMap(row)) rows.push({ sport: 'AFC San Jose', season, name, uid: row['UID'], row });
      }
    }
  }
  return { rows, seasons };
}

export interface SnapshotStats {
  accounts: number;
  accountsMissing: number;
  seasons: Record<string, number>;
  rows: number;
  oldRows: number;
  configChecks: number;
  hints: number;
}

/** The MergeSnapshot the planner's contract asks for (merge_accounts_logic.ts
 *  header): every map account's Users node; the UID leaf of every roster row
 *  holding an old uid (league + AFC); the row NODE of every name row (left
 *  out when there is no such row); the fantasy Config presence (null =
 *  checked, none) of every league season a relink would touch; the masked
 *  kept emails. Users nodes stay in memory - never logged or saved. */
export async function readMergeSnapshot(
  db: Rest, map: MergeMap, hints: HintLookup,
): Promise<{ snap: MergeSnapshot; stats: SnapshotStats }> {
  const nodes: Record<string, unknown> = {};
  const uids = uidsOf(map);
  let missing = 0;
  for (const uid of uids) {
    const v = await db.get(userPath(uid));
    if (v === null || v === undefined) missing++;
    else nodes[userPath(uid)] = v;
  }

  const olds = new Set(oldsOf(map));
  const { rows, seasons } = await scanRosters(db, LEAGUE_SPORTS, true);
  const touched = new Set<string>();
  let oldRows = 0;
  for (const r of rows) {
    if (typeof r.uid !== 'string' || !olds.has(r.uid)) continue;
    oldRows++;
    if (r.sport === 'AFC San Jose') {
      nodes[afcUidPath(r.season, r.name)] = r.uid;
    } else {
      nodes[leagueUidPath(r.sport, r.season, r.team as string, r.name)] = r.uid;
      touched.add(`${r.sport}|${r.season}`);
    }
  }
  for (const c of map.clusters) {
    for (const nr of c.nameRows ?? []) {
      const hit = rows.find((r) => r.sport === nr.sport && r.season === nr.season &&
        r.team === nr.team && r.name === nr.name);
      const rowPath = leagueUidPath(nr.sport, nr.season, nr.team, nr.name).slice(0, -'/UID'.length);
      if (hit) nodes[rowPath] = hit.row;
      touched.add(`${nr.sport}|${nr.season}`);
    }
  }
  for (const key of [...touched].sort()) {
    const [sport, season] = key.split('|');
    const cfg = fantasyConfigPath(sport, season);
    nodes[cfg] = (await db.get(cfg, { shallow: true })) ?? null;
  }

  const keptHints = await hints([...new Set(map.clusters.map((c) => c.keep))]);
  return {
    snap: { nodes, keptHints },
    stats: {
      accounts: uids.length, accountsMissing: missing, seasons, rows: rows.length, oldRows,
      configChecks: touched.size, hints: Object.keys(keptHints).length,
    },
  };
}

// ── plan helpers ───────────────────────────────────────────────────────────

/** sha256 of the writes with MergedAt's wall-clock value blanked, so a dry
 *  run and a later --apply over the same data give the same digest. */
export function planDigest(writes: ReadonlyArray<PlanWrite>): string {
  const body = writes.map((w) => ({
    path: w.path, before: w.before ?? null, after: /\/MergedAt$/.test(w.path) ? 'now' : w.after,
  }));
  return crypto.createHash('sha256').update(canonical(body)).digest('hex').slice(0, 16);
}

/** Which cluster (index in the map) a planned write belongs to. */
export function clusterOfWrite(w: PlanWrite, map: MergeMap): number {
  if (parseRosterUidPath(w.path)) return map.clusters.findIndex((c) => c.keep === w.after);
  const m = /^Users\/([^/]+)\//.exec(w.path);
  if (!m) return -1;
  return map.clusters.findIndex((c) => c.keep === m[1] || (c.old ?? []).includes(m[1]));
}

function kindOf(p: string): string {
  if (parseRosterUidPath(p)) return 'roster relinks';
  if (/\/Played\//.test(p)) return 'seasons-played entries';
  if (/\/ProfileUrl$/.test(p)) return 'profile photo links';
  if (/\/Information\//.test(p)) return 'information fields';
  if (/\/First Name$/.test(p)) return 'first-name fix';
  if (STAMPS.some((s) => p.endsWith(`/${s}`))) return 'merge stamps';
  return 'other';
}

function printPlan(map: MergeMap, plan: MergePlan, stats: SnapshotStats, log: (s: string) => void): void {
  const seasons = Object.entries(stats.seasons).map(([s, n]) => `${s} ${n}`).join(', ');
  log(`  read: ${stats.accounts} accounts (${stats.accountsMissing} with no Users node), ` +
    `${stats.rows} roster rows in ${seasons} seasons, ${stats.oldRows} rows held by an old account, ` +
    `${stats.configChecks} fantasy Config checks`);
  log(`  kept-email hints found (masked, not shown): ${stats.hints} of ${new Set(map.clusters.map((c) => c.keep)).size}`);
  log('  plan:');
  for (const line of plan.summary) log(`    ${line}`);
  log(`  refusals: ${plan.refusals.length === 0 ? 'none' : plan.refusals.length}`);
  for (const r of plan.refusals) log(`    - ${r.who}: ${r.why}`);
  const planned = new Set(plan.writes.map((w) => clusterOfWrite(w, map)));
  const refused = new Set(plan.refusals.map((r) => r.who));
  const already = map.clusters.length - planned.size - refused.size;
  log(`  clusters: ${map.clusters.length} in the map - ${planned.size} planned, ` +
    `${refused.size} refused, ${already} with nothing to do`);
  const kinds = new Map<string, number>();
  for (const w of plan.writes) kinds.set(kindOf(w.path), (kinds.get(kindOf(w.path)) ?? 0) + 1);
  log(`  writes: ${plan.writes.length}` +
    (kinds.size ? ` (${[...kinds].map(([k, n]) => `${n} ${k}`).join(', ')})` : ''));
  log(`  plan digest (MergedAt time excluded): ${planDigest(plan.writes)}`);
}

// ── backup ─────────────────────────────────────────────────────────────────

export interface BackupEntry {
  path: string;
  who: string;
  before: unknown;
  after: unknown;
  /** Set (and the file saved) right BEFORE the write is sent: --undo only
   *  touches attempted paths, never a refused cluster's. */
  attempted: boolean;
}

export interface MergeBackup {
  kind: typeof BACKUP_KIND;
  version: number;
  target: Target['kind'];
  createdAt: string;
  /** The MergedAt this run stamps: --undo refuses an account stamped by
   *  another run. */
  mergedAt: number;
  planDigest: string;
  clusters: Array<{ who: string; keep: string; old: string[] }>;
  entries: BackupEntry[];
}

/** A backup file's parsed JSON is untrusted: wrong kind, version or target,
 *  a malformed entry, or any path/value that is not a merge write of its own
 *  clusters throws before any network call. */
export function validateBackup(raw: unknown, target: Target['kind']): MergeBackup {
  if (!isPlainMap(raw) || raw['kind'] !== BACKUP_KIND) {
    const kind = isPlainMap(raw) ? JSON.stringify(raw['kind'] ?? null) : 'none';
    throw new Error(`Not a ${BACKUP_KIND} file (its kind is ${kind}) - refusing.`);
  }
  if (raw['version'] !== BACKUP_VERSION) throw new Error(`Unknown ${BACKUP_KIND} version - refusing.`);
  if (raw['target'] !== target) {
    throw new Error(`Refusing: this backup was taken against ${String(raw['target'])}, ` +
      `but this run targets ${target}.`);
  }
  const mergedAt = raw['mergedAt'];
  if (!(typeof mergedAt === 'number' && Number.isInteger(mergedAt) && mergedAt > 0)) {
    throw new Error('Malformed backup: mergedAt is not a positive integer.');
  }
  if (!Array.isArray(raw['clusters']) || !Array.isArray(raw['entries'])) {
    throw new Error('Malformed backup: no clusters/entries lists.');
  }
  const keepOf = new Map<string, { keep: string; old: string[] }>();
  const oldOf = new Map<string, { keep: string; old: string[] }>();
  for (const c of raw['clusters'] as unknown[]) {
    if (!isPlainMap(c) || typeof c['who'] !== 'string' || typeof c['keep'] !== 'string' ||
      !UID_RE.test(c['keep']) || !Array.isArray(c['old']) ||
      !(c['old'] as unknown[]).every((o) => typeof o === 'string' && UID_RE.test(o))) {
      throw new Error('Malformed backup: a cluster is not {who, keep, old[]} with plain uids.');
    }
    const entry = { keep: c['keep'], old: c['old'] as string[] };
    for (const u of [entry.keep, ...entry.old]) {
      if (keepOf.has(u) || oldOf.has(u)) throw new Error('Malformed backup: a uid appears twice.');
    }
    keepOf.set(entry.keep, entry);
    for (const o of entry.old) oldOf.set(o, entry);
  }
  const seen = new Set<string>();
  for (const e of raw['entries'] as unknown[]) {
    const bad = (why: string): never => {
      const p = isPlainMap(e) && typeof e['path'] === 'string' ? e['path'] : '?';
      throw new Error(`Malformed backup entry ${JSON.stringify(p)}: ${why}.`);
    };
    if (!isPlainMap(e) || typeof e['path'] !== 'string' || typeof e['who'] !== 'string' ||
      typeof e['attempted'] !== 'boolean' || !('before' in e)) return bad('missing fields');
    const p = e['path'];
    const before = e['before'] ?? null;
    const after = e['after'];
    if (seen.has(p)) bad('listed twice');
    seen.add(p);
    if (after === null || after === undefined) bad('no value written');
    const ref = parseRosterUidPath(p);
    if (ref) {
      const c = typeof after === 'string' ? keepOf.get(after) : undefined;
      if (!c) bad('the roster row was not relinked to a kept account of this backup');
      const fromOld = typeof before === 'string' && (c as { old: string[] }).old.includes(before);
      if (!fromOld && before !== null && before !== '') bad('the row held neither an old account nor nothing');
      continue;
    }
    const m = /^Users\/([A-Za-z0-9_-]+)\/(.+)$/.exec(p);
    if (!m) return bad('not a merge path');
    const [, uid, rest] = m;
    const oc = oldOf.get(uid);
    if (oc) {
      if (!STAMPS.includes(rest)) bad('an old account only ever gets the three stamps');
      if (before !== null) bad('a stamp only ever filled an empty leaf');
      if (rest === 'MergedInto' && after !== oc.keep) bad('MergedInto is not the cluster\'s kept account');
      if (rest === 'MergedAt' && after !== mergedAt) bad('MergedAt is not this backup\'s mergedAt');
      if (rest === 'MergedHint' && !looksMasked(after)) bad('MergedHint is not a masked hint');
      continue;
    }
    if (!keepOf.has(uid)) bad('the account is not in this backup\'s clusters');
    const played = new RegExp(`^Played/(${SPORTS})/Season \\d+$`).test(rest);
    const info = /^Information\/([^/]+)$/.exec(rest);
    const ok = (played && before === null && typeof after === 'string') ||
      (rest === 'ProfileUrl' && typeof after === 'string') ||
      (info !== null && isCopyableInformation(info[1], after)) ||
      (rest === 'First Name' && typeof after === 'string');
    if (!ok) bad('not a leaf the merge writes on a kept account');
  }
  return raw as unknown as MergeBackup;
}

/** Atomic: a temp file in the same folder, then renamed over the backup, so
 *  a crash mid-write never leaves a half-written backup. */
function saveBackup(file: string, backup: MergeBackup): void {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(backup, null, 1));
  fs.renameSync(tmp, file);
}

// ── runs ───────────────────────────────────────────────────────────────────

export interface RunDeps {
  /** The raw database client; every run wraps it in guardRest itself. */
  rest: Rest;
  hints: HintLookup;
  log: (line: string) => void;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  outDir: string;
  target: Target;
  /** Test seam: runs after --apply printed its plan, before the backup. */
  afterPlan?: () => Promise<void> | void;
}

export async function dryRun(map: MergeMap, deps: RunDeps): Promise<{ plan: MergePlan; digest: string }> {
  const db = guardRest(deps.rest, { readOnly: true });
  deps.log(`Merge duplicate accounts - DRY RUN (${deps.target.label})`);
  const { snap, stats } = await readMergeSnapshot(db, map, deps.hints);
  const plan = buildMergePlan(map, snap, deps.now());
  printPlan(map, plan, stats, deps.log);
  // The allowlist must accept this exact list, or --apply would stop.
  if (plan.writes.length > 0) assertMergePaths(plan.writes, map, snap);
  const digest = planDigest(plan.writes);
  deps.log('DRY RUN - nothing was written.');
  if (plan.writes.length > 0) {
    deps.log(`To apply exactly this plan: npm run merge:accounts -- --apply --expect-plan ${digest}`);
  }
  return { plan, digest };
}

export interface ApplyOptions {
  /** The canary (Review Focus 4). false only under the emulator. */
  canary: boolean;
  canaryTimeoutMs?: number;
  canaryPollMs?: number;
  /** The digest a dry run printed: refuse when the plan is not that one. */
  expectPlan?: string;
}

export interface ApplyResult {
  ok: boolean;
  backupFile: string | null;
  applied: string[];
  refusedAtApply: string[];
  /** Clusters the planner refused (nothing of them planned or written). */
  refusedByPlan: string[];
  stoppedByCanary: boolean;
  writes: number;
}

export const EXPECT_PLAN_REQUIRED =
  'Refusing --apply on production without --expect-plan <digest>: run the dry run first ' +
  '(npm run merge:accounts), read it, then apply exactly that plan with ' +
  'npm run merge:accounts -- --apply --expect-plan <the digest it printed>.';

const rowPathOf = (uidPath: string): string => uidPath.slice(0, -'/UID'.length);

/** Review Focus 1: what in this cluster no longer matches the plan, read
 *  live right before writing (labels only, no values). Also re-checks D2
 *  (no fantasy Config appeared) and that the kept account is not merged. */
async function changedSincePlan(
  db: Rest, map: MergeMap, keep: string, writes: ReadonlyArray<PlanWrite>,
): Promise<string[]> {
  const changed: string[] = [];
  const configs = new Map<string, string>();
  for (const w of writes) {
    const ref = parseRosterUidPath(w.path);
    if (ref) {
      const row = await db.get(rowPathOf(w.path));
      if (!isPlainMap(row) || !same(row['UID'] ?? null, w.before ?? null)) changed.push(labelOf(w.path, map));
      if (ref.kind === 'league') {
        configs.set(fantasyConfigPath(ref.sport, ref.season), `${ref.sport} Season ${ref.season}`);
      }
    } else if (!same(await db.get(w.path), w.before ?? null)) {
      changed.push(labelOf(w.path, map));
    }
  }
  for (const [cfg, label] of [...configs].sort()) {
    if ((await db.get(cfg, { shallow: true })) !== null) changed.push(`${label} now has a fantasy Config`);
  }
  if (hasUidValue(await db.get(`${userPath(keep)}/MergedInto`))) changed.push('the kept account is now merged itself');
  return changed;
}

/** Review Focus 4: poll PublicProfiles/<old> until every watched old
 *  account is gone or [timeoutMs] has passed. */
async function canaryGone(
  db: Rest, olds: string[], deps: RunDeps, timeoutMs: number, pollMs: number,
): Promise<{ gone: boolean; waited: number }> {
  let waited = 0;
  for (;;) {
    let still = 0;
    for (const o of olds) if ((await db.get(`PublicProfiles/${o}`, { shallow: true })) !== null) still++;
    if (still === 0) return { gone: true, waited };
    if (waited >= timeoutMs) return { gone: false, waited };
    await deps.sleep(pollMs);
    waited += pollMs;
  }
}

const stampedOlds = (writes: ReadonlyArray<PlanWrite>): string[] =>
  writes.map((w) => /^Users\/([^/]+)\/MergedInto$/.exec(w.path)?.[1]).filter((u): u is string => !!u);

export async function applyMerge(map: MergeMap, deps: RunDeps, opts: ApplyOptions): Promise<ApplyResult> {
  if (!opts.canary && deps.target.kind !== 'emulator') {
    throw new Error('Refusing: the canary can only be skipped under the emulator.');
  }
  if (deps.target.kind !== 'emulator' && (opts.expectPlan === undefined || opts.expectPlan === '')) {
    throw new Error(EXPECT_PLAN_REQUIRED);
  }
  const log = deps.log;
  log(`Merge duplicate accounts - APPLY (${deps.target.label})`);
  const reader = guardRest(deps.rest, { readOnly: true });
  const { snap, stats } = await readMergeSnapshot(reader, map, deps.hints);
  const mergedAt = deps.now();
  const plan = buildMergePlan(map, snap, mergedAt);
  printPlan(map, plan, stats, log);
  const result: ApplyResult = {
    ok: true, backupFile: null, applied: [], refusedAtApply: [], refusedByPlan: [],
    stoppedByCanary: false, writes: 0,
  };
  result.refusedByPlan = [...new Set(plan.refusals.map((r) => r.who))];
  const refusedLine = (): string =>
    `${result.refusedByPlan.length} cluster(s) REFUSED by the plan (see refusals) - nothing of them was written: ` +
    result.refusedByPlan.join(', ');
  if (plan.writes.length === 0) {
    log('Nothing to write - every cluster is already merged or refused.');
    if (result.refusedByPlan.length > 0) {
      log(refusedLine());
      result.ok = false;
    }
    return result;
  }
  assertMergePaths(plan.writes, map, snap); // throws on a malformed map or any off-list write
  const digest = planDigest(plan.writes);
  if (opts.expectPlan !== undefined && opts.expectPlan !== digest) {
    throw new Error(`Refusing --apply: the plan digest is ${digest}, not the ${opts.expectPlan} ` +
      'you expected - the data changed since that dry run. Run the dry run again and read it.');
  }
  if (plan.writes.some((w) => clusterOfWrite(w, map) < 0)) throw new Error('Refusing: a write belongs to no cluster.');
  await deps.afterPlan?.();

  // Group by cluster (map order), keeping the planner's crash-safe order.
  const groups = map.clusters
    .map((c, i) => ({ who: c.who, keep: c.keep, writes: plan.writes.filter((w) => clusterOfWrite(w, map) === i) }))
    .filter((g) => g.writes.length > 0);

  // The canary: an old account this run stamps that HAS a public profile
  // now (one without proves nothing). Its cluster goes first.
  const watchable = new Set<string>();
  if (opts.canary) {
    for (const g of groups) {
      for (const o of stampedOlds(g.writes)) {
        if ((await reader.get(`PublicProfiles/${o}`, { shallow: true })) !== null) watchable.add(o);
      }
    }
    const first = groups.findIndex((g) => stampedOlds(g.writes).some((o) => watchable.has(o)));
    if (first > 0) groups.unshift(...groups.splice(first, 1));
    if (first < 0) {
      log('  ********************************************************************');
      log('  * WARNING: THE MIRROR CHECK (CANARY) IS SKIPPED FOR THIS RUN.      *');
      log('  * No old account this run stamps has a PublicProfiles entry right  *');
      log('  * now, so there is nothing to watch disappear. That is expected    *');
      log('  * when re-running after a partial apply (already stamped accounts  *');
      log('  * have left the mirror). Otherwise make sure the functions with    *');
      log('  * the mirror change are deployed. The run continues.               *');
      log('  ********************************************************************');
    } else {
      log(`  canary: ${groups[0].who} goes first, then up to ` +
        `${Math.round((opts.canaryTimeoutMs ?? CANARY_TIMEOUT_MS) / 1000)} s for its old account to leave PublicProfiles`);
    }
  } else {
    log('  canary: OFF (--no-canary, emulator only)');
  }
  let canaryPending = watchable.size > 0;

  // Back up every planned path before any write (before = the snapshot's
  // value, re-checked live per cluster below).
  const createdAt = new Date(mergedAt).toISOString();
  const backupFile = path.join(deps.outDir, `merge_backup_${createdAt.replace(/[:.]/g, '-')}.json`);
  const backup: MergeBackup = {
    kind: BACKUP_KIND, version: BACKUP_VERSION, target: deps.target.kind, createdAt, mergedAt,
    planDigest: digest,
    clusters: map.clusters.map((c) => ({ who: c.who, keep: c.keep, old: [...(c.old ?? [])] })),
    entries: groups.flatMap((g) => g.writes.map((w) => ({
      path: w.path, who: g.who, before: w.before ?? null, after: w.after, attempted: false,
    }))),
  };
  validateBackup(JSON.parse(JSON.stringify(backup)), deps.target.kind); // --undo must accept it
  fs.mkdirSync(deps.outDir, { recursive: true });
  if (fs.existsSync(backupFile)) throw new Error(`Refusing: ${backupFile} already exists.`);
  saveBackup(backupFile, backup);
  result.backupFile = backupFile;
  const undoCmd = `npm run merge:accounts -- --undo "${backupFile}"`;
  log(`  backup of ${backup.entries.length} planned paths: ${backupFile}`);

  const writer = guardRest(deps.rest, {
    readOnly: false, allowedWrites: new Set(plan.writes.map((w) => w.path)),
  });
  try {
    for (const g of groups) {
      const changed = await changedSincePlan(writer, map, g.keep, g.writes);
      if (changed.length > 0) {
        log(`  ${g.who}: REFUSED at apply - changed since the plan: ${changed.join('; ')}`);
        result.refusedAtApply.push(g.who);
        continue;
      }
      assertMergePaths(g.writes, map, snap);
      for (const w of g.writes) {
        const entry = backup.entries.find((e) => e.path === w.path) as BackupEntry;
        entry.attempted = true;
        saveBackup(backupFile, backup); // recorded BEFORE the write is sent
        await writer.put(w.path, w.after);
        result.writes++;
        log(`    wrote ${labelOf(w.path, map)}`);
      }
      result.applied.push(g.who);

      const watch = stampedOlds(g.writes).filter((o) => watchable.has(o));
      if (!canaryPending || watch.length === 0) continue;
      canaryPending = false;
      const c = await canaryGone(writer, watch, deps,
        opts.canaryTimeoutMs ?? CANARY_TIMEOUT_MS, opts.canaryPollMs ?? CANARY_POLL_MS);
      if (!c.gone) {
        log(`  CANARY FAILED: ${g.who}'s old account is still in PublicProfiles after ` +
          `${Math.round(c.waited / 1000)} s - the mirror change (merged accounts leave the public ` +
          'profile mirror) is probably not deployed.');
        log('  STOPPED before any other cluster. Undo this run, deploy the functions, then apply again:');
        log(`  Undo: ${undoCmd}`);
        result.ok = false;
        result.stoppedByCanary = true;
        return result;
      }
      log(`  canary passed: the old account left PublicProfiles (after ~${Math.round(c.waited / 1000)} s)`);
    }
  } catch (err) {
    // The backup exists and some writes may have landed: always say how to undo.
    log('  STOPPED by an error after the backup was written (the error follows).');
    log(`  Undo: ${undoCmd}`);
    throw err;
  }
  result.ok = result.refusedAtApply.length === 0 && result.refusedByPlan.length === 0;
  log(`DONE - ${result.writes} writes for ${result.applied.length} cluster(s)` +
    (result.refusedAtApply.length ? `; REFUSED at apply: ${result.refusedAtApply.join(', ')}` : '') + '.');
  if (result.refusedByPlan.length > 0) log(refusedLine());
  log(`Undo: ${undoCmd}`);
  return result;
}

export interface UndoResult {
  ok: boolean;
  restored: number;
  alreadyBefore: number;
  leftAlone: string[];
}

/** --undo: every path the apply ATTEMPTED (refused clusters are never
 *  touched) that still holds exactly what the apply wrote is put back to its
 *  backed-up value verbatim (DELETE when it was absent), stamps first (the
 *  reverse of the write order). A path already back at its old value is
 *  skipped; one changed since by someone else is left alone and listed. An
 *  old account whose MergedAt is another run's refuses the whole undo. */
export async function undoMerge(file: string, deps: RunDeps): Promise<UndoResult> {
  deps.log(`Merge duplicate accounts - UNDO (${deps.target.label})`);
  const raw = readJsonFile(path.resolve(file), 'the backup');
  const backup = validateBackup(raw, deps.target.kind); // before any network call
  const map: MergeMap = { clusters: backup.clusters.map((c) => ({ who: c.who, keep: c.keep, old: c.old })) };
  const todo = backup.entries.filter((e) => e.attempted);
  const result: UndoResult = { ok: true, restored: 0, alreadyBefore: 0, leftAlone: [] };
  deps.log(`  backup ${backup.createdAt}: ${backup.entries.length} planned paths, ${todo.length} written`);
  if (todo.length === 0) {
    deps.log('Nothing to undo - this backup recorded no writes.');
    return result;
  }
  const db = guardRest(deps.rest, { readOnly: false, allowedWrites: new Set(todo.map((e) => e.path)) });
  const states: Array<{ e: BackupEntry; state: 'written' | 'before' | 'changed' }> = [];
  for (const e of todo) {
    const live = (await db.get(e.path)) ?? null;
    states.push({ e, state: same(live, e.after) ? 'written' : same(live, e.before) ? 'before' : 'changed' });
  }
  const otherRun = states.filter((s) => s.state === 'changed' && s.e.path.endsWith('/MergedAt'));
  if (otherRun.length > 0) {
    throw new Error(`Refusing --undo: ${otherRun.map((s) => labelOf(s.e.path, map)).join('; ')} ` +
      'carries a different MergedAt than this backup wrote - that account was merged by another ' +
      'run, so this backup is not the one to undo it with. Nothing was changed.');
  }
  for (const s of [...states].reverse()) {
    const label = labelOf(s.e.path, map);
    if (s.state === 'before') {
      result.alreadyBefore++;
    } else if (s.state === 'changed') {
      result.leftAlone.push(label);
      deps.log(`    LEFT ALONE ${label} (changed since the merge)`);
    } else {
      if (s.e.before === null || s.e.before === undefined) await db.del(s.e.path);
      else await db.put(s.e.path, s.e.before);
      result.restored++;
      deps.log(`    restored ${label}`);
    }
  }
  result.ok = result.leftAlone.length === 0;
  deps.log(`UNDONE - ${result.restored} restored, ${result.alreadyBefore} already as before` +
    (result.leftAlone.length ? `, ${result.leftAlone.length} LEFT ALONE (changed since the merge)` : '') + '.');
  return result;
}

// ── notify (D11 + D12) ─────────────────────────────────────────────────────

export interface NotifyResult {
  ok: boolean;
  /** MergeNotices/<old> nodes written this run (each makes the trigger send one email). */
  noticesWritten: number;
  /** Old accounts whose notice was already there (left alone). */
  noticesPresent: number;
  /** Notices a --send run would write now (the preview's count; equals noticesWritten after --send). */
  noticesToWrite: number;
  /** The one push campaign was written this run (false when it already existed or in a preview). */
  campaignWritten: boolean;
  campaignId: string | null;
  /** Kept accounts the push reaches. */
  audience: number;
}

export interface NotifyOptions {
  /** false (the default) = the PREVIEW: prints what would be written and
   *  writes nothing. Only --notify --send passes true. */
  send: boolean;
}

/** --notify: tells the merged players which email to use. Reads the stamps
 *  --apply left (never an address), refuses unless EVERY old account of the
 *  map is stamped into the map's kept account with a masked-or-absent hint,
 *  then writes - through a guard that allows exactly these paths and no other -
 *  MergeNotices/<old> for each old account that has none and the ONE campaign
 *  (deterministic id, so a re-run finds it) when it is not there yet. Idempotent:
 *  a second run writes nothing. The trigger and the campaign sender do the
 *  actual sending - this only creates their nodes. It SENDS people email, so
 *  by default it is a PREVIEW (same checks, same printout, no writes); only
 *  { send: true } (--notify --send) writes. */
export async function notifyMerge(
  map: MergeMap, deps: RunDeps, opts: NotifyOptions = { send: false },
): Promise<NotifyResult> {
  const log = deps.log;
  log(`Merge duplicate accounts - NOTIFY ${opts.send ? '--send' : 'PREVIEW'} (${deps.target.label})`);
  const reader = guardRest(deps.rest, { readOnly: true });
  const withOld = map.clusters.filter((c) => (c.old ?? []).length > 0);
  const result: NotifyResult = {
    ok: true, noticesWritten: 0, noticesPresent: 0, noticesToWrite: 0, campaignWritten: false,
    campaignId: null, audience: 0,
  };
  if (withOld.length === 0) {
    log('Nothing to notify - no cluster of the map has an old account.');
    return result;
  }

  // 1. Every old account must be stamped (D5) into the map's kept account.
  const hints = new Map<string, string>();
  const problems: string[] = [];
  for (const c of withOld) {
    for (const old of c.old ?? []) {
      const label = labelOf(userPath(old), map);
      const into = await reader.get(`${userPath(old)}/MergedInto`);
      const hint = await reader.get(`${userPath(old)}/MergedHint`);
      if (!hasUidValue(into)) problems.push(`${label} is not stamped yet (no MergedInto)`);
      else if (into !== c.keep) problems.push(`${label} is stamped into a different account than the map's kept account`);
      else if (hint !== null && hint !== undefined && !looksMasked(hint)) problems.push(`${label} has a hint that is not masked`);
      else hints.set(old, typeof hint === 'string' ? hint : '');
    }
  }
  if (problems.length > 0) {
    throw new Error(`Refusing --notify: ${problems.join('; ')}. Run --apply first (and check the map). Nothing was written.`);
  }

  // 2. What is missing: one notice per old account without one, and the campaign.
  const notices: Array<{ path: string; node: Record<string, unknown>; label: string }> = [];
  for (const c of withOld) {
    for (const old of c.old ?? []) {
      const path = `MergeNotices/${old}`;
      if ((await reader.get(path, { shallow: true })) !== null) {
        result.noticesPresent++;
        continue;
      }
      notices.push({ path, label: labelOf(userPath(old), map), node: { KeepHint: hints.get(old) ?? '', CreatedAt: deps.now() } });
    }
  }
  const keepUids = [...new Set(withOld.map((c) => c.keep))];
  const campaignId = mergeNoticeCampaignId(keepUids);
  const campaignPath = `Campaigns/${campaignId}`;
  const campaignPresent = (await reader.get(campaignPath, { shallow: true })) !== null;
  result.campaignId = campaignId;
  result.audience = keepUids.length;
  result.noticesToWrite = notices.length;

  log(`  old accounts: ${notices.length + result.noticesPresent} - ${notices.length} notice(s) to write, ` +
    `${result.noticesPresent} already there`);
  for (const n of notices) log(`    notice for ${n.label}`);
  log(`  push to ${keepUids.length} kept account(s): ` +
    (campaignPresent ? `campaign ${campaignId} already exists` : `campaign ${campaignId} to write`));
  if (notices.length === 0 && campaignPresent) {
    log('Nothing to write - every notice and the campaign are already there.');
    return result;
  }
  if (!opts.send) {
    log(`PREVIEW - nothing was written. ${notices.length} email(s) and ${campaignPresent ? 0 : 1} push campaign would go out. ` +
      'To send exactly this: npm run merge:accounts -- --notify --send');
    return result;
  }

  // 3. Write exactly those paths, notices first (each sends one email).
  const writes = [...notices.map((n) => n.path), ...(campaignPresent ? [] : [campaignPath])];
  const writer = guardRest(deps.rest, { readOnly: false, allowedWrites: new Set(writes) });
  for (const n of notices) {
    await writer.put(n.path, n.node);
    result.noticesWritten++;
    log(`    wrote the notice for ${n.label}`);
  }
  if (!campaignPresent) {
    await writer.put(campaignPath, mergeNoticeCampaign(keepUids, deps.now()));
    result.campaignWritten = true;
    log(`    wrote campaign ${campaignId} (push to ${keepUids.length} kept account(s))`);
  }
  log(`DONE - ${result.noticesWritten} notice(s) and ${result.campaignWritten ? 1 : 0} campaign written. ` +
    'The functions now send the emails and the push; check MergeNotices/<old>/Status and the Manager campaign list.');
  log('Notices only send if onMergeNoticeCreated is deployed; if it was not, delete MergeNotices/<old> ' +
    'and re-run --notify --send after deploying.');
  return result;
}

// ── find-dupes (D16, read-only) ────────────────────────────────────────────

export const normalizeName = (s: string): string => s.trim().toLowerCase().replace(/\s+/g, ' ');

export interface DupeCandidate {
  /** The roster name (public league data). */
  name: string;
  where: string[];
  kind: 'already linked to another account' | 'unlinked row';
}

/** Submitters of [regId] whose account first + last name matches a roster
 *  row of the registration's sport (any season) that is linked to ANOTHER
 *  account or to none. Reads only Submissions' keys and each submitter's
 *  First Name / Last Name leaves - never an answer, email or phone. */
export async function findDupes(regId: string, deps: RunDeps): Promise<DupeCandidate[]> {
  if (!REG_ID_RE.test(regId)) throw new Error(`"${regId}" is not a registration id.`);
  const db = guardRest(deps.rest, { readOnly: true });
  deps.log(`Merge duplicate accounts - FIND DUPES for ${regId} (${deps.target.label}, read-only)`);
  const config = await db.get(`Registrations/${regId}/Config`);
  if (!isPlainMap(config)) throw new Error(`Registration ${regId} has no Config - check the id.`);
  const sport = String(config['Sport'] ?? '');
  if (!LEAGUE_SPORTS.includes(sport)) {
    throw new Error(`Registration ${regId} is for "${sport}"; --find-dupes covers ${LEAGUE_SPORTS.join(', ')}.`);
  }
  const submitters = keysOf(await db.get(`Registrations/${regId}/Submissions`, { shallow: true }))
    .filter((u) => UID_RE.test(u)).sort();
  const { rows, seasons } = await scanRosters(db, [sport], false);
  const byName = new Map<string, RosterRow[]>();
  for (const r of rows) {
    const n = normalizeName(r.name);
    byName.set(n, [...(byName.get(n) ?? []), r]);
  }

  const out: DupeCandidate[] = [];
  let noName = 0;
  for (const uid of submitters) {
    const first = await db.get(`Users/${uid}/First Name`);
    const last = await db.get(`Users/${uid}/Last Name`);
    const full = normalizeName(`${typeof first === 'string' ? first : ''} ${typeof last === 'string' ? last : ''}`);
    if (full === '' || typeof first !== 'string' || typeof last !== 'string') {
      noName++;
      continue;
    }
    const others = (byName.get(full) ?? []).filter((r) => r.uid !== uid);
    const linked = others.filter((r) => hasUidValue(r.uid));
    const unlinked = others.filter((r) => !hasUidValue(r.uid));
    const where = (rs: RosterRow[]): string[] => rs.map((r) => `S${r.season} ${r.team}`);
    const add = (c: DupeCandidate): void => {
      if (!out.some((o) => o.name === c.name && o.kind === c.kind && o.where.join() === c.where.join())) out.push(c);
    };
    if (linked.length) add({ name: linked[0].name, where: where(linked), kind: 'already linked to another account' });
    if (unlinked.length) add({ name: unlinked[0].name, where: where(unlinked), kind: 'unlinked row' });
  }
  out.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : a.kind < b.kind ? -1 : 1));
  deps.log(`  ${sport}: ${seasons[sport]} seasons, ${rows.length} roster rows; ${submitters.length} submissions ` +
    `(${noName} without a first + last name on the account)`);
  deps.log(`  candidates: ${out.length === 0 ? 'none' : out.length}`);
  for (const c of out) deps.log(`    ${c.name} — ${c.where.join(', ')} — "${c.kind}"`);
  deps.log('FIND DUPES - read-only, nothing was written. Merge any real duplicate before building rosters.');
  return out;
}

// ── entry ──────────────────────────────────────────────────────────────────

export interface CliArgs {
  mode: 'dry-run' | 'apply' | 'undo' | 'find-dupes' | 'notify';
  backupFile?: string;
  regId?: string;
  mapFile: string;
  expectPlan?: string;
  fakeEmails: boolean;
  noCanary: boolean;
  /** --notify --send: write (otherwise --notify only previews). */
  send: boolean;
}

export function parseArgs(argv: readonly string[]): CliArgs {
  const valued = new Set(['--undo', '--find-dupes', '--map', '--expect-plan']);
  const flags = new Set(['--apply', '--notify', '--send', '--fake-emails', '--no-canary']);
  const got = new Map<string, string>();
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (got.has(a)) throw new Error(`${a} is given twice. ${USAGE}`);
    if (flags.has(a)) {
      got.set(a, '');
    } else if (valued.has(a)) {
      const v = argv[i + 1];
      if (v === undefined || v === '' || v.startsWith('--')) throw new Error(`${a} needs a value. ${USAGE}`);
      got.set(a, v);
      i++;
    } else {
      throw new Error(`Unknown argument ${a}. ${USAGE}`);
    }
  }
  const modes = ['--apply', '--undo', '--find-dupes', '--notify'].filter((m) => got.has(m));
  if (modes.length > 1) throw new Error(`Pick one of --apply, --undo, --find-dupes, --notify. ${USAGE}`);
  const mode: CliArgs['mode'] = got.has('--apply') ? 'apply' : got.has('--undo') ? 'undo'
    : got.has('--find-dupes') ? 'find-dupes' : got.has('--notify') ? 'notify' : 'dry-run';
  if (got.has('--expect-plan') && mode !== 'apply') throw new Error(`--expect-plan goes with --apply. ${USAGE}`);
  if (got.has('--no-canary') && mode !== 'apply') throw new Error(`--no-canary goes with --apply. ${USAGE}`);
  if (got.has('--map') && mode !== 'apply' && mode !== 'dry-run' && mode !== 'notify') {
    throw new Error(`--map goes with the dry run, --apply or --notify. ${USAGE}`);
  }
  if (got.has('--send') && mode !== 'notify') throw new Error(`--send goes with --notify. ${USAGE}`);
  if (got.has('--fake-emails') && mode === 'notify') {
    throw new Error(`--fake-emails does not go with --notify (it looks up no emails). ${USAGE}`);
  }
  return {
    mode,
    backupFile: got.get('--undo'),
    regId: got.get('--find-dupes'),
    mapFile: got.get('--map') ?? DEFAULT_MAP,
    expectPlan: got.get('--expect-plan'),
    fakeEmails: got.has('--fake-emails'),
    noCanary: got.has('--no-canary'),
    send: got.has('--send'),
  };
}

/** --fake-emails and --no-canary are emulator-only; under the emulator the
 *  kept emails must be made up (never a real lookup for emulator data). */
export function checkTargetFlags(args: CliArgs, target: Target): void {
  if (target.kind !== 'emulator') {
    if (args.fakeEmails) {
      throw new Error('Refusing --fake-emails: it only works with FIREBASE_DATABASE_EMULATOR_HOST set (the emulator).');
    }
    if (args.noCanary) throw new Error('Refusing --no-canary: it only works under the emulator.');
    if (args.mode === 'apply' && !args.expectPlan) throw new Error(EXPECT_PLAN_REQUIRED);
  } else if ((args.mode === 'dry-run' || args.mode === 'apply') && !args.fakeEmails) {
    throw new Error('Under the emulator pass --fake-emails (made-up kept emails; no real lookups).');
  }
}

async function main(): Promise<void> {
  if (!fs.existsSync(path.join(process.cwd(), 'tools', 'merge_accounts.ts'))) {
    throw new Error('Run from functions/ (npm run merge:accounts).');
  }
  const args = parseArgs(process.argv.slice(2));
  const target = resolveTarget();
  checkTargetFlags(args, target);
  const token = target.kind === 'emulator' ? async (): Promise<string> => 'owner' : accessToken;
  // Read-only modes: no PUT/DELETE/other POST can leave the process.
  const readOnly = args.mode === 'dry-run' || args.mode === 'find-dupes' || (args.mode === 'notify' && !args.send);
  const restoreFetch = readOnly ? installReadOnlyFetchGuard(target) : (): void => undefined;
  const deps: RunDeps = {
    rest: httpRest(target, token),
    hints: args.fakeEmails ? fakeHints : identityToolkitHints(token),
    log: (line) => console.log(line),
    now: () => Date.now(),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    // Production backups always land in tools/rehearsal_out; an emulator
    // rehearsal may keep its own elsewhere (MERGE_TOOL_OUT_DIR).
    outDir: target.kind === 'emulator' && process.env.MERGE_TOOL_OUT_DIR
      ? path.resolve(process.env.MERGE_TOOL_OUT_DIR)
      : path.join(process.cwd(), 'tools', 'rehearsal_out'),
    target,
  };
  try {
    if (args.mode === 'dry-run') {
      await dryRun(loadMap(args.mapFile), deps);
    } else if (args.mode === 'find-dupes') {
      await findDupes(args.regId as string, deps);
    } else if (args.mode === 'notify') {
      const r = await notifyMerge(loadMap(args.mapFile), deps, { send: args.send });
      if (!r.ok) process.exitCode = 1;
    } else if (args.mode === 'apply') {
      const r = await applyMerge(loadMap(args.mapFile), deps, { canary: !args.noCanary, expectPlan: args.expectPlan });
      if (!r.ok) process.exitCode = 1;
    } else {
      const r = await undoMerge(args.backupFile as string, deps);
      if (!r.ok) process.exitCode = 1;
    }
  } finally {
    restoreFetch();
  }
}

// Runs only as the built entry point (npm run merge:accounts), never when a
// test imports this module.
if (/merge_accounts\.js$/.test(process.argv[1] ?? '')) {
  main().catch((err) => {
    // Every error this tool raises names a path or a label - never a URL,
    // a token or an email.
    console.error((err as Error)?.stack ?? String(err));
    process.exitCode = 1;
  });
}
