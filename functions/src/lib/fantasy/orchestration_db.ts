// The tiny injected database seam + RTDB-shape parsing shared by the fantasy
// jobs (P4 Phases B–D). Pure TS — no firebase imports — so vitest drives the
// whole orchestration against an in-memory FantasyDb (generateJoke's
// injected-fetch idea applied to RTDB). The real adapter over an admin
// Reference lives in src/fantasy_adapter.ts.

import {
  FantasyConfig, FantasyPosition, parsePosition,
} from './fantasy_config';
import { MarketPlayer } from './finalize_core';
import {
  DEFAULT_MINUTES_BEFORE_KICKOFF, deriveGameweeks, Gameweek, legacyKickoffHHmm,
  LockedWeek, ScheduleOverrides,
} from './gameweeks';
import { leagueInstantUtc, parseDbDate } from './league_time';
import type { FantasyLogger } from './orchestration';

/** What a FantasyDb.transaction resolved to. */
export interface FantasyTxResult {
  /** false = the update aborted (returned undefined); nothing was written. */
  committed: boolean;
  /** The node's value as committed (on an abort: as last seen). */
  value: unknown;
}

/** Everything the fantasy jobs do to the database. Paths are RTDB paths
 *  relative to the root, never leading-slashed. */
export interface FantasyDb {
  /** Snapshot value at [path]; null when absent. */
  read(path: string): Promise<unknown>;
  /** Whether the MAP node at [path] has at least one child — for "is week N
   *  scored / snapshotted?" checks that never need the contents. Production
   *  downloads at most ONE child (a one-child query), not the whole node.
   *  An empty map is absent (RTDB never stores one).
   *  MAP NODES ONLY (History/<n>, PublishedPicks/<n>): a scalar leaf has no
   *  child, so it answers false — in production (probed on the RTDB
   *  emulator; the SDK's limited-query filter turns a leaf into an empty
   *  node) and in every in-memory db, which mirror that. Use
   *  `(await read(path)) != null` for a leaf such as a timestamp or flag. */
  exists(path: string): Promise<boolean>;
  /** The child KEYS of [path] without their values (RTDB `?shallow=true`) —
   *  season discovery only. Optional: absent (tests, a db without it) or
   *  failing, callers use childKeysOf, which falls back to a full read. */
  childKeys?(path: string): Promise<string[]>;
  /** set() — null removes. */
  write(path: string, value: unknown): Promise<void>;
  /** Transactional set-if-absent; true when this call won the claim. */
  writeIfAbsent(path: string, value: unknown): Promise<boolean>;
  /** Compare-and-set (an RTDB transaction on [path]): [update] gets the
   *  node's current value (null when absent) and returns the value to
   *  store (null removes) or undefined to abort. It may run more than once
   *  — a concurrent write re-runs it on the fresh value — so it must be
   *  pure. RTDB caveat: the first run can see null for a node that exists
   *  but is not cached yet, so an update must never ABORT on null; return
   *  null (a no-op when it really is absent — RTDB re-runs it on the real
   *  value otherwise). updateIfPresent below wraps that rule. */
  transaction(
    path: string, update: (current: unknown) => unknown,
  ): Promise<FantasyTxResult>;
}

export function fantasyRoot(sport: string, season: string): string {
  return `Fantasy/${sport}/${season}`;
}

/** Plain object — RTDB array coercion (a JS Array) is NOT a map. */
export function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

/** Changes the map at [path] only while it exists (review 2026-10-28: a
 *  stamp or claim on a row the owner deleted must never recreate a partial
 *  stub row). [next] gets the CURRENT map and returns its replacement, or
 *  undefined to leave it alone (the compare-and-set "no"). An absent node
 *  (or a non-map) is never handed to [next]. Resolves to the value [next]
 *  produced once it committed; null when nothing changed (absent, not a
 *  map, or [next] declined). */
export async function updateIfPresent(
  db: FantasyDb, path: string,
  next: (current: Record<string, unknown>) => Record<string, unknown> | undefined,
): Promise<Record<string, unknown> | null> {
  let landed: Record<string, unknown> | null = null;
  const res = await db.transaction(path, (current) => {
    landed = null; // every (re-)run decides afresh
    if (current === null || current === undefined) return null; // see FantasyDb
    if (!isPlainMap(current)) return undefined;
    const value = next(current);
    if (value === undefined) return undefined;
    landed = value;
    return value;
  });
  return res.committed ? landed : null;
}

/** Dart-ish tolerant int: num -> trunc, full signed decimal string -> parse,
 *  everything else -> 0 (league scores/status mix int and String). */
export function toIntLoose(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v);
  const s = String(v ?? '').trim();
  return /^[+-]?\d+$/.test(s) ? Number(s) : 0;
}

/** Children of a node that RTDB may hand back as a Map OR a null-padded
 *  array (small-int keys list-coerce: season numbers, gameweeks, game
 *  indexes). Null holes are skipped; array indexes become string keys. */
export function childEntries(node: unknown): Array<[string, unknown]> {
  if (Array.isArray(node)) {
    const out: Array<[string, unknown]> = [];
    node.forEach((v, i) => {
      if (v !== null && v !== undefined) out.push([String(i), v]);
    });
    return out;
  }
  if (isPlainMap(node)) {
    return Object.entries(node).filter(([, v]) => v !== null);
  }
  return [];
}

/** The in-memory dbs' `exists`, mirroring production's one-child query
 *  (FantasyDb.exists): true only for a map or list with at least one non-null
 *  child. A scalar leaf, an empty map and an absent node are all false. */
export function nodeExists(value: unknown): boolean {
  return childEntries(value).length > 0;
}

/** The child keys in a `?shallow=true` body. The body comes in both RTDB
 *  shapes — an object `{k: true}` or, for small-int keys, a null-padded list
 *  (`[null, true, true]`) — and yields exactly the keys childEntries would
 *  on the full node. Anything else (null, a leaf) has no children. */
export function shallowKeysOf(body: unknown): string[] {
  return childEntries(body).map(([k]) => k);
}

/** The REST URL of a keys-only (`?shallow=true`) read of [path]. Against the
 *  RTDB emulator ([emulatorHost] = FIREBASE_DATABASE_EMULATOR_HOST) it is
 *  `http://<host>/<path>.json?ns=<namespace>&shallow=true`, the namespace
 *  being the database URL's `ns` parameter or its first host label — what
 *  firebase-admin itself uses, e.g. `infinite-sports-app`, never the
 *  project id. The URL never carries a credential. */
export function shallowUrl(
  databaseURL: string, path: string, emulatorHost?: string,
): string {
  const encoded = path.split('/').filter((p) => p.length > 0)
    .map(encodeURIComponent).join('/');
  const base = new URL(databaseURL);
  if (emulatorHost) {
    const ns = base.searchParams.get('ns') ||
      base.hostname.split('.')[0].toLowerCase();
    return `http://${emulatorHost}/${encoded}.json` +
      `?ns=${encodeURIComponent(ns)}&shallow=true`;
  }
  return `${base.origin}/${encoded}.json?shallow=true`;
}

/** The child keys of [path], cheaply when the db can (childKeys) and exactly
 *  as the engine always did when it cannot: a db without childKeys, or ANY
 *  failure of it (token, network, 5xx, timeout), reads the full node and
 *  takes its keys — with ONE warning in the failure case — so a shallow
 *  failure can never make a season go missing. */
export async function childKeysOf(
  db: FantasyDb, path: string, log: FantasyLogger,
): Promise<string[]> {
  return (await keysLook(db, path, log)).keys;
}

/** What childKeysOf found, plus the WHOLE node when it had to read it (a db
 *  without childKeys, or a failed shallow read) — so a caller that needs
 *  what lies below can take it from that node instead of reading it again
 *  (listFantasySeasons: the fallback costs one whole read, never two). */
interface KeysLook {
  keys: string[];
  whole?: { node: unknown };
}

async function keysLook(
  db: FantasyDb, path: string, log: FantasyLogger,
): Promise<KeysLook> {
  if (db.childKeys) {
    try {
      return { keys: await db.childKeys(path) };
    } catch (err) {
      log.warn('fantasy keys: shallow read failed', {
        path, error: err instanceof Error ? err.message : String(err),
      });
    }
  }
  const node = await db.read(path);
  return { keys: childEntries(node).map(([k]) => k), whole: { node } };
}

// ── Server-originated Squads/<uid> writes ──────────────────────────────────
//
// The Squads/<uid> trigger (recordSquadSave) fires for the server's OWN
// writes too — the post-finalize chip switch-off, the Free Hit restore,
// position re-labels — and must not stamp TransferState.SavedGw for them:
// SavedGw is the deadline reminder's "the manager acted this week" marker
// (pushes.ts reminderAudience), and a server write is not the manager
// acting. DOCUMENTED CHOICE — a marker IN the squad node, not a comparison
// against a remembered server copy: every server write to Squads/<uid>
// carries `ServerWriteAt: <epoch ms>` (the whole-node restore includes it;
// child writes stamp it FIRST, before the change, so every event of that
// write already carries it). Clients always save with ONE whole-node set()
// of FantasySquad.toMap (FantasyService.saveMySquad, every app version),
// which wipes the marker — so "the node carries ServerWriteAt" means
// exactly "the last whole-squad author was the server". The trigger judges
// the EVENT's after-value (not a later re-read), so a manager save racing a
// server write is still counted. The marker is ignored by every squad
// parser (squadFromMap / FantasySquad.fromMap read named keys only); the
// lock snapshot copies it verbatim like any other key. Admin SDK writes
// bypass the rules, and no client ever writes it.

/** Squads/<uid> field stamped by every server-originated squad write. */
export const SERVER_WRITE_KEY = 'ServerWriteAt';

/** The instant an RTDB trigger's write happened: the CloudEvent `time`
 *  (RFC 3339) when it parses, else [fallback] (the run's now). Judging the
 *  write's own time keeps a save made just before the lock counted even
 *  when its trigger runs just after it (audit I3). */
export function writeTimeOf(eventTime: unknown, fallback: Date): Date {
  if (typeof eventTime !== 'string' || eventTime.length === 0) return fallback;
  const ms = Date.parse(eventTime);
  return Number.isFinite(ms) ? new Date(ms) : fallback;
}

/** Whether a Squads/<uid> value was written by the server (see above). */
export function isServerSquadWrite(squadNode: unknown): boolean {
  return isPlainMap(squadNode) && squadNode[SERVER_WRITE_KEY] != null;
}

/** Stamps the server marker on Squads/<uid> — call it BEFORE a server
 *  child write to the same squad (chip clear, re-label). */
export async function markServerSquadWrite(
  db: FantasyDb, root: string, uid: string, nowMs: number,
): Promise<void> {
  await db.write(`${root}/Squads/${uid}/${SERVER_WRITE_KEY}`, nowMs);
}

/** Config.lockOverride (fantasy_parsers.dart FantasyLockOverride.parse):
 *  absent/unknown = 'auto' (production). Anything but 'auto' freezes the
 *  whole machine — lifecycle, finalize and repricing all stand down.
 *
 *  Auto-return (spec §2, 2026-10-28): the optional Config.lockOverrideUntil
 *  (epoch ms) bounds an open/locked override — once [nowMs] reaches it the
 *  EFFECTIVE value is 'auto' (the sweep then reverts the DB). Only a finite
 *  number counts; junk/absent = no automatic return ("Never"). Without
 *  [nowMs] this is the raw value (old behaviour). */
export function lockOverrideOf(
  configNode: unknown, nowMs?: number,
): 'open' | 'locked' | 'auto' {
  const raw = isPlainMap(configNode) ? configNode['lockOverride'] : null;
  const s = raw == null ? '' : String(raw);
  if (s !== 'open' && s !== 'locked') return 'auto';
  const until = isPlainMap(configNode) ? configNode['lockOverrideUntil'] : null;
  if (nowMs !== undefined && typeof until === 'number' &&
    Number.isFinite(until) && nowMs >= until) {
    return 'auto';
  }
  return s;
}

/** A TEST season (audit I5, 2026-10-31): `Fantasy/<sport>/<season>/TestFill`
 *  = { At, Managers } is the marker tools/fill_test_season.ts writes FIRST
 *  when it fills a paused season with a replayed, made-up season (fake
 *  managers test-NN + the real managers' squads replayed into fake History,
 *  Leaderboards and Badges). Any value there makes the season a test fill,
 *  and the engine stands down for it entirely — sweep, finalize (and so the
 *  void re-settle), Monday reprice and the squad-save counter — whatever
 *  lockOverride says: a Resume Auto, an expired pause or a rerun must never
 *  settle fake data, and above all never copy a fake podium into a real
 *  user's trophy cabinet (Users/<uid>/Awards). settleSeasonBadges checks it
 *  too (badges.ts). The fill tool's --clear removes it; the season is then
 *  an ordinary one again. The S15 rehearsal/fill REPLAY never seeds it (its
 *  in-memory overlay holds only the replay's READ_PATHS), so the replay runs
 *  the real engine unchanged. */
export const TEST_FILL_NODE = 'TestFill';

/** The stand-down log line every engine entry point emits for a TestFill
 *  season. */
export const TEST_FILL_STAND_DOWN = 'fantasy: TestFill season — engine stands down';

/** Whether the season under [root] (fantasyRoot) carries the TestFill
 *  marker (see TEST_FILL_NODE). */
export async function isTestFillSeason(db: FantasyDb, root: string): Promise<boolean> {
  return (await db.read(`${root}/${TEST_FILL_NODE}`)) != null;
}

/** The season-end badge marker: `Fantasy/<sport>/<season>/SeasonBadgesSettledAt`
 *  = epoch ms of the settle that stamped it (badges.ts settleSeasonBadges, D6
 *  of the 2026-11-06 scale fixes). Present = the season is OVER (every
 *  scoreable week finalized) AND its badges are settled — so the sweep's
 *  "already settled?" check answers from this one number instead of reading
 *  every badge of the season, and a finished season can stand down. It is a
 *  bare number — a scalar leaf — so ask `(await db.read(path)) != null`,
 *  NEVER `db.exists(path)` (a map-node test: false for a number in
 *  production). Written set-if-absent only after the all-weeks-finalized
 *  check has passed: at the end of every completed settle (zero season awards
 *  and every season badge switched off included) and when the sweep finds an
 *  auto season award without it (it re-runs the same check first, without
 *  reconciling). Never for a season with an unfinalized week; deleted
 *  whenever a re-settle takes season awards away. */
export const SEASON_BADGES_SETTLED_NODE = 'SeasonBadgesSettledAt';

/** One `Voided/<gw>` leaf: ONLY a literal boolean true voids the week (the
 *  Manager writes true or removes the node — fantasy_admin_models.dart
 *  voidedGwsFromNode `raw == true` parity); absent/false/junk = counts. */
export function isVoidFlag(v: unknown): boolean {
  return v === true;
}

/** The owner-voided gameweeks (spec §15) out of the `Voided` node, sorted
 *  ascending. Gameweek keys are small ints, so the node WILL list-coerce —
 *  childEntries handles both shapes. */
export function voidedWeeksOf(voidedNode: unknown): number[] {
  return childEntries(voidedNode)
    .filter(([, v]) => isVoidFlag(v))
    .map(([k]) => Number(k))
    .filter((w) => Number.isInteger(w) && w > 0)
    .sort((a, b) => a - b);
}

export interface FantasySeasonRef {
  sport: string;
  season: string;
  configNode: Record<string, unknown>;
}

/** Every fantasy-enabled (sport, season) found in a WHOLE Fantasy node:
 *  children of it that carry a Config map. Season keys are small ints, so the
 *  per-sport node WILL list-coerce — childEntries handles both shapes.
 *  The engine no longer reads the whole node to discover seasons (see
 *  listFantasySeasons); this stays as the reference rule that function
 *  matches (the tests compare the two), and is what it falls back on when a
 *  keys read had to download the whole node anyway. */
export function fantasySeasonsOf(fantasyNode: unknown): FantasySeasonRef[] {
  const out: FantasySeasonRef[] = [];
  for (const [sport, seasons] of childEntries(fantasyNode)) {
    for (const [season, node] of childEntries(seasons)) {
      if (!isPlainMap(node)) continue;
      const config = node['Config'];
      if (!isPlainMap(config)) continue;
      out.push({ sport, season, configNode: config });
    }
  }
  return out;
}

/** The one child of `Fantasy` that is a shared node, not a sport (the badge
 *  catalog, badges.ts BADGE_CATALOG_PATH). Never listed for seasons. */
const BADGE_CATALOG_KEY = 'BadgeCatalog';

/** Every fantasy-enabled (sport, season), found WITHOUT downloading the
 *  Fantasy node — which holds every season's Players, Squads, Leaderboards
 *  and History (megabytes at league size, read every 15 minutes). The sport
 *  keys and each sport's season keys come from keys-only reads
 *  (childKeysOf: shallow when the db can, else the full node — never a
 *  skipped season), then only each season's small `Config` is read. A season
 *  counts iff that Config is a plain map — exactly fantasySeasonsOf's rule —
 *  and the order is the sport keys, then each sport's season keys, as they
 *  come back.
 *  When a keys read had to read the whole node instead (a db without
 *  childKeys, or a failed shallow read — warned once by keysLook), the
 *  seasons under it come from THAT node (fantasySeasonsOf), never from a
 *  second pass below it: a failed top-level read costs one whole Fantasy
 *  read, exactly the pre-D3 engine, not that plus every sport node again
 *  (final review Minor 1). A season whose Config read fails is warned and
 *  skipped for this run; the other seasons carry on (final review Minor 3). */
export async function listFantasySeasons(
  db: FantasyDb, log: FantasyLogger,
): Promise<FantasySeasonRef[]> {
  const top = await keysLook(db, 'Fantasy', log);
  if (top.whole) return fantasySeasonsOf(top.whole.node);
  const out: FantasySeasonRef[] = [];
  for (const sport of top.keys) {
    if (sport === BADGE_CATALOG_KEY) continue;
    const look = await keysLook(db, `Fantasy/${sport}`, log);
    if (look.whole) {
      out.push(...fantasySeasonsOf({ [sport]: look.whole.node }));
      continue;
    }
    for (const season of look.keys) {
      let config: unknown;
      try {
        config = await db.read(`${fantasyRoot(sport, season)}/Config`);
      } catch (err) {
        log.warn('fantasy sweep: season config read failed', {
          sport, season, error: err instanceof Error ? err.message : String(err),
        });
        continue;
      }
      if (!isPlainMap(config)) continue;
      out.push({ sport, season, configNode: config });
    }
  }
  return out;
}

/** The highest gameweek whose points are in (a finalize wrote its History
 *  node), without downloading History: the largest integer key of
 *  `<root>/History` — the week numbers only (childKeysOf: shallow keys, or
 *  the full node when the shallow read is unavailable, which is exactly what
 *  the reprice always did). Non-integer keys are ignored; null when nothing
 *  has been finalized. History itself is the truth: the LockedWeeks `Scored`
 *  mark is warn-only (markWeekScored) and nothing heals a missing one, so a
 *  finalized week without its mark must still count. */
export async function latestScoredWeek(
  db: FantasyDb, root: string, log: FantasyLogger,
): Promise<number | null> {
  const weeks = (await childKeysOf(db, `${root}/History`, log))
    .map(Number)
    .filter((w) => Number.isInteger(w));
  return weeks.length === 0 ? null : Math.max(...weeks);
}

/** Match-day keys (MMDDYYYY) of a season's Date node
 *  (fantasy_parsers.dart dateKeysFromNode parity). */
export function dateKeysOf(dateNode: unknown): string[] {
  return childEntries(dateNode).map(([k]) => k);
}

// ── Gameweek schedule nodes (season setup + schedule changes) ──────────────
// Twin of lib/fantasy/data/fantasy_parsers.dart (lockedWeeksFromNode,
// scheduleOverridesFromConfigNode, firstKickoffByDateFromNode): same shapes,
// same junk rules.

/** True for a string that is a real MMDDYYYY calendar date. */
function isDbDate(raw: unknown): raw is string {
  if (typeof raw !== 'string' || !/^\d{8}$/.test(raw)) return false;
  const d = parseDbDate(raw);
  return d.getUTCMonth() + 1 === Number(raw.substring(0, 2)) &&
    d.getUTCDate() === Number(raw.substring(2, 4));
}

/** A positive epoch-milliseconds NUMBER as a Date; null for anything else
 *  (strings, bools, NaN, <= 0, or past the Date range) so a junk node is
 *  skipped, never thrown on. */
function epochMsToDate(raw: unknown): Date | null {
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0 ||
    raw > 8640000000000000) return null;
  return new Date(Math.trunc(raw));
}

/** childEntries with the numeric index: a node RTDB may hand back as a
 *  null-padded List (index = key) or an int-keyed Map. Non-numeric Map keys
 *  have no index and are skipped. */
function indexedChildren(node: unknown): Array<[number, unknown]> {
  const out: Array<[number, unknown]> = [];
  for (const [key, v] of childEntries(node)) {
    const index = /^\d+$/.test(key) ? Number(key) : NaN;
    if (Number.isSafeInteger(index)) out.push([index, v]);
  }
  return out;
}

/** `Fantasy/<sport>/<season>/LockedWeeks` — the frozen-week ledger:
 *  `<n>` -> `{Date: 'MMDDYYYY', LockAtUtc: <epoch ms>, Scored?: true}`.
 *  Gameweek numbers are small ints, so RTDB list-coerces the node (index =
 *  week, index 0 null): a List and an int-keyed Map both parse. An entry that
 *  isn't week >= 1, isn't a map, has no valid Date or no numeric LockAtUtc is
 *  skipped; `Scored` counts only as a literal `true`. The server-only
 *  coordination keys `Rewinding` (isRewinding) and `Finalizing`
 *  (finalizingFresh) are not part of the week and are ignored here. */
export function lockedWeeksOf(node: unknown): Record<number, LockedWeek> {
  const out: Record<number, LockedWeek> = {};
  for (const [n, week] of indexedChildren(node)) {
    if (n < 1 || !isPlainMap(week)) continue;
    const date = week['Date'];
    const lockUtc = epochMsToDate(week['LockAtUtc']);
    if (!isDbDate(date) || lockUtc === null) continue;
    out[n] = { date, lockUtc, scored: week['Scored'] === true };
  }
  return out;
}

/** Whether a stored `LockedWeeks/<n>` value is marked by the sweep's rewind
 *  of a called-off week (`Rewinding: true`, its first step — see
 *  schedule_rewind.ts). A marked entry still parses (lockedWeeksOf keeps the
 *  week in the frozen prefix) but freezes nothing: no lock claim, re-check,
 *  Scored mark or finalize accepts it. */
export function isRewinding(node: unknown): boolean {
  return isPlainMap(node) && node['Rewinding'] === true;
}

/** [I1] How long a finalize's `Finalizing` stamp on `LockedWeeks/<n>` holds
 *  off the rewind's mark. Far longer than any finalize run (a function
 *  times out well before): an older stamp is a finalize that died. */
export const FINALIZING_STALE_MS = 10 * 60 * 1000;

/** [I1] Whether a stored `LockedWeeks/<n>` value carries a finalize's
 *  `Finalizing: <epoch ms>` stamp younger than [FINALIZING_STALE_MS] at
 *  [nowMs] — a finalize is writing the week's points right now, so the
 *  rewind must not mark it (schedule_rewind.ts). A stamp from a clock a
 *  little ahead counts as fresh; no stamp, or a non-numeric one, is none.
 *  Readers of the ledger (lockedWeeksOf, freezesWeekDate, both apps'
 *  parsers) ignore the key. */
export function finalizingFresh(node: unknown, nowMs: number): boolean {
  if (!isPlainMap(node)) return false;
  const at = node['Finalizing'];
  return typeof at === 'number' && Number.isFinite(at) &&
    nowMs - at < FINALIZING_STALE_MS;
}

/** Whether a stored `LockedWeeks/<n>` value freezes the week dated [date]:
 *  a map with that Date and not marked by a rewind. */
export function freezesWeekDate(node: unknown, date: string): boolean {
  return isPlainMap(node) && node['Date'] === date && !isRewinding(node);
}

/** The schedule bits of `Fantasy/<sport>/<season>/Config`:
 *  `SkippedDates/<MMDDYYYY> = true` (only a literal `true` counts),
 *  `Deadlines/<MMDDYYYY> = <epoch ms number>` (anything else is ignored) and
 *  `deadlineMinutesBeforeKickoff` (an integer, default 60, clamped 0..240; a
 *  non-integer reads as the default). */
export function scheduleOverridesOf(configNode: unknown): ScheduleOverrides {
  const skippedDates = new Set<string>();
  const deadlineOverrides: Record<string, Date> = {};
  let minutesBeforeKickoff = DEFAULT_MINUTES_BEFORE_KICKOFF;
  if (isPlainMap(configNode)) {
    const skipped = configNode['SkippedDates'];
    if (isPlainMap(skipped)) {
      for (const [date, v] of Object.entries(skipped)) {
        if (v === true && isDbDate(date)) skippedDates.add(date);
      }
    }
    const deadlines = configNode['Deadlines'];
    if (isPlainMap(deadlines)) {
      for (const [date, v] of Object.entries(deadlines)) {
        const at = epochMsToDate(v);
        if (at !== null && isDbDate(date)) deadlineOverrides[date] = at;
      }
    }
    const minutes = configNode['deadlineMinutesBeforeKickoff'];
    if (typeof minutes === 'number' && Number.isSafeInteger(minutes)) {
      minutesBeforeKickoff = Math.min(240, Math.max(0, minutes));
    }
  }
  return { skippedDates, deadlineOverrides, minutesBeforeKickoff };
}

/** League-time instant of a valid 'H:mm' / 'HH:mm' (24 h) string on [date];
 *  null when [hhmm] is not a valid time. */
function kickoffFromHHmm(date: string, hhmm: string): Date | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
  if (m === null) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return leagueInstantUtc(date, h, min);
}

/** The earliest kickoff of each match date of a season's
 *  `/<sport>/<season>/Date` node (the input of
 *  GameweekSchedule.firstKickoffUtc). A game's kickoff is its stored `Time`
 *  ('HH:mm', 24 h, league time) when valid; otherwise — only when
 *  [startHour] (the season Start Time) is > 0 — the legacy derived time
 *  legacyKickoffHHmm of its index (List position, or the numeric key of an
 *  index-keyed Map); otherwise it has none. A date with no kickoff at all is
 *  left out, as are non-date keys and non-map games. */
export function firstKickoffByDateOf(
  dateNode: unknown, startHour = 0,
): Record<string, Date> {
  const out: Record<string, Date> = {};
  if (!isPlainMap(dateNode)) return out;
  for (const [date, gamesNode] of Object.entries(dateNode)) {
    if (!isDbDate(date)) continue;
    let first: Date | null = null;
    for (const [index, game] of indexedChildren(gamesNode)) {
      if (!isPlainMap(game)) continue;
      const legacy = legacyKickoffHHmm(startHour, index);
      const kickoff = kickoffFromHHmm(date, String(game['Time'] ?? '')) ??
        (legacy === null ? null : kickoffFromHHmm(date, legacy));
      if (kickoff !== null && (first === null ||
        kickoff.getTime() < first.getTime())) first = kickoff;
    }
    if (first !== null) out[date] = first;
  }
  return out;
}

/** THE one place the server decides a season's gameweek list. Every job that
 *  needs the weeks — sweep, finalize, void re-settle, live, reminders,
 *  manager messages, position alerts, season badges — gets them here, so they
 *  all agree on what the managers see (guarded by schedule_guard.test.ts).
 *
 *  Reads the season's Date node (`<sport>/<season>/Date`), the frozen-week
 *  ledger (`Fantasy/<sport>/<season>/LockedWeeks`) and the season Start Time
 *  (`<sport>/<season>/Start Time`: > 0 gives games without a stored `Time` a
 *  legacy derived kickoff; absent/junk/<= 0 = none), and feeds
 *  deriveGameweeks those plus the owner's overrides from the raw Config node
 *  ([configNode]: SkippedDates, Deadlines, deadlineMinutesBeforeKickoff).
 *  With no LockedWeeks, no overrides and no kickoffs it is exactly the legacy
 *  "one gameweek per match date, locking at cfg.lockHour".
 *
 *  A failed read THROWS and propagates: an error is not a fact — a read that
 *  could not complete must never become "no weeks" (the caller aborts the
 *  step rather than acting on an empty schedule). Returns the Date node too,
 *  for callers that read the games of a date from the same snapshot.
 *
 *  [opts.withoutLockedFrom] = n derives the weeks as they will be once
 *  LockedWeeks/<n> and every later entry are gone — the rewind's look-ahead
 *  (schedule_rewind.ts), which announces the reopened week's deadline before
 *  it removes the entry. */
export async function loadSeasonGameweeks(
  db: FantasyDb, sport: string, season: string, cfg: FantasyConfig,
  configNode: Record<string, unknown>,
  opts: { withoutLockedFrom?: number } = {},
): Promise<{ gws: Gameweek[]; dateNode: unknown }> {
  // Three independent reads, issued together: a failed one rejects the lot.
  const [dateNode, lockedNode, startTime] = await Promise.all([
    db.read(`${sport}/${season}/Date`),
    db.read(`${fantasyRoot(sport, season)}/LockedWeeks`),
    db.read(`${sport}/${season}/Start Time`),
  ]);
  const startHour = toIntLoose(startTime);
  const lockedWeeks = lockedWeeksOf(lockedNode);
  const dropFrom = opts.withoutLockedFrom;
  if (dropFrom !== undefined) {
    for (const n of Object.keys(lockedWeeks).map(Number)) {
      if (n >= dropFrom) delete lockedWeeks[n];
    }
  }
  const gws = deriveGameweeks(dateKeysOf(dateNode), cfg, {
    lockedWeeks,
    ...scheduleOverridesOf(configNode),
    firstKickoffUtc: firstKickoffByDateOf(dateNode, startHour > 0 ? startHour : 0),
  });
  return { gws, dateNode };
}

/** A league game is a fantasy event unless it is a friendly (league
 *  convention: league_watch.ts recomputeLeagueLeaderboard skips Stage
 *  'friendly' everywhere). */
export function isFriendly(gameNode: Record<string, unknown>): boolean {
  return String(gameNode['Stage'] ?? '').trim().toLowerCase() === 'friendly';
}

/** The scoreable game nodes of one date: plain maps, friendlies dropped.
 *  Date nodes hold Lists (normal) or index-keyed Maps (hole collapsing). */
export function gamesOfDate(dateNode: unknown): Record<string, unknown>[] {
  return keyedGamesOfDate(dateNode).map(([, g]) => g);
}

/** gamesOfDate with each game's key under the date (its list index) — the
 *  live week's game keys (Live/Meta.Games). Same games, same order. */
export function keyedGamesOfDate(
  dateNode: unknown,
): Array<[string, Record<string, unknown>]> {
  const out: Array<[string, Record<string, unknown>]> = [];
  for (const [key, v] of childEntries(dateNode)) {
    if (isPlainMap(v) && !isFriendly(v)) out.push([key, v]);
  }
  return out;
}

/** All games final (status 2) — the finalize gate. An empty list is NOT
 *  complete (nothing to settle). */
export function allGamesFinal(games: Record<string, unknown>[]): boolean {
  return games.length > 0 && games.every((g) => toIntLoose(g['status']) === 2);
}

/** Port of the Manager's attendance parser (lib/services/attendance.dart):
 *  the team{n}attendance node stores ABSENT players only as name -> false
 *  (string 'false' tolerated); everything else means present. Tolerates the
 *  List shape a numeric-keyed node collapses to. */
export function parseAbsentMap(raw: unknown): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  const add = (key: string, value: unknown) => {
    if (key.length === 0) return;
    const isFalse = value === false ||
      (typeof value === 'string' && value.trim().toLowerCase() === 'false');
    if (isFalse) out[key] = false;
  };
  for (const [k, v] of childEntries(raw)) add(k, v);
  return out;
}

/** The FULL attendance map the stats mapper needs (spec §8 default-present):
 *  every rostered player true, overridden false by the absent-only node;
 *  stray absent keys off the roster stay false so they never score. The
 *  roster union is what gives a present, zero-stat player their appearance
 *  point. */
export function fullAttendance(
  roster: string[], absent: Record<string, boolean>,
): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const name of roster) out[name] = true;
  for (const name of Object.keys(absent)) out[name] = false;
  return out;
}

/** One team's roster names from the season's `Line Ups` node
 *  ({team: {playerName: stats}}). Empty when the team is missing — the
 *  finalizer then falls back to activity-event players only (logged). */
export function rosterNamesOf(lineupsNode: unknown, team: string): string[] {
  if (!isPlainMap(lineupsNode)) return [];
  return childEntries(lineupsNode[team]).map(([name]) => name);
}

/** The market (Fantasy/<sport>/<season>/Players) as the finalizer needs it.
 *  Entries with an unusable position are skipped (fantasy_player.dart
 *  fromNode parity). */
export function marketPlayersOf(
  playersNode: unknown,
): Record<string, MarketPlayer> {
  const out: Record<string, MarketPlayer> = {};
  for (const [name, raw] of childEntries(playersNode)) {
    if (!isPlainMap(raw)) continue;
    let position: FantasyPosition;
    try {
      position = parsePosition(String(raw['position'] ?? ''));
    } catch {
      continue;
    }
    const teamName = raw['teamName'];
    out[name] = {
      position,
      eligible: raw['eligible'] === true,
      ...(typeof teamName === 'string' && teamName.length > 0
        ? { teamName } : {}),
    };
  }
  return out;
}

/** The LockedPositions/<gw> snapshot value: every market player's usable
 *  position, name -> 'GK'|'DEF'|'ATT' (eligible or not — a guest promoted
 *  later still scores its locked weeks at the locked position). */
export function positionsSnapshotOf(
  players: Record<string, MarketPlayer>,
): Record<string, FantasyPosition> {
  const out: Record<string, FantasyPosition> = {};
  for (const [name, p] of Object.entries(players)) out[name] = p.position;
  return out;
}

/** Tolerant LockedPositions/<gw> parse: unusable entries skipped (they
 *  then fall back to the live position, like a player added after lock). */
export function lockedPositionsOf(node: unknown): Record<string, FantasyPosition> {
  const out: Record<string, FantasyPosition> = {};
  for (const [name, raw] of childEntries(node)) {
    try {
      out[name] = parsePosition(String(raw ?? ''));
    } catch {
      // skip
    }
  }
  return out;
}

/** The market as a LOCKED gameweek saw it: live membership + eligibility,
 *  positions overridden by that week's snapshot (spec §3: a week is scored
 *  with its locked positions forever). Players missing from the snapshot
 *  (added after lock) keep their live position. */
export function withLockedPositions(
  players: Record<string, MarketPlayer>,
  locked: Record<string, FantasyPosition>,
): Record<string, MarketPlayer> {
  const out: Record<string, MarketPlayer> = {};
  for (const [name, p] of Object.entries(players)) {
    out[name] = { ...p, position: locked[name] ?? p.position };
  }
  return out;
}

/** Current price per market player (repricing input). Missing/unusable
 *  prices read 0 — applyDelta's clamp then floors them. */
export function marketPricesOf(playersNode: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [name, raw] of childEntries(playersNode)) {
    if (!isPlainMap(raw)) continue;
    out[name] = toIntLoose(raw['priceTenths']);
  }
  return out;
}
