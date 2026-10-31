// The tiny injected database seam + RTDB-shape parsing shared by the fantasy
// jobs (P4 Phases B–D). Pure TS — no firebase imports — so vitest drives the
// whole orchestration against an in-memory FantasyDb (generateJoke's
// injected-fetch idea applied to RTDB). The real adapter over an admin
// Reference lives in src/fantasy_adapter.ts.

import { FantasyPosition, parsePosition } from './fantasy_config';
import { MarketPlayer } from './finalize_core';

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

/** Every fantasy-enabled (sport, season): children of the Fantasy node that
 *  carry a Config map. Season keys are small ints, so the per-sport node WILL
 *  list-coerce — childEntries handles both shapes. */
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

/** Match-day keys (MMDDYYYY) of a season's Date node
 *  (fantasy_parsers.dart dateKeysFromNode parity). */
export function dateKeysOf(dateNode: unknown): string[] {
  return childEntries(dateNode).map(([k]) => k);
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
  return childEntries(dateNode)
    .map(([, v]) => v)
    .filter(isPlainMap)
    .filter((g) => !isFriendly(g));
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
