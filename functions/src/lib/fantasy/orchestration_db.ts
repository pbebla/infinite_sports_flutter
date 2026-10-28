// The tiny injected database seam + RTDB-shape parsing shared by the fantasy
// jobs (P4 Phases B–D). Pure TS — no firebase imports — so vitest drives the
// whole orchestration against an in-memory FantasyDb (generateJoke's
// injected-fetch idea applied to RTDB). The real adapter over an admin
// Reference lives in src/fantasy_adapter.ts.

import { FantasyPosition, parsePosition } from './fantasy_config';
import { MarketPlayer } from './finalize_core';

/** Everything the fantasy jobs do to the database. Paths are RTDB paths
 *  relative to the root, never leading-slashed. */
export interface FantasyDb {
  /** Snapshot value at [path]; null when absent. */
  read(path: string): Promise<unknown>;
  /** set() — null removes. */
  write(path: string, value: unknown): Promise<void>;
  /** Transactional set-if-absent; true when this call won the claim. */
  writeIfAbsent(path: string, value: unknown): Promise<boolean>;
}

export function fantasyRoot(sport: string, season: string): string {
  return `Fantasy/${sport}/${season}`;
}

/** Plain object — RTDB array coercion (a JS Array) is NOT a map. */
export function isPlainMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
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

/** Config.lockOverride (fantasy_parsers.dart FantasyLockOverride.parse):
 *  absent/unknown = 'auto' (production). Anything but 'auto' freezes the
 *  whole machine — lifecycle, finalize and repricing all stand down. */
export function lockOverrideOf(configNode: unknown): 'open' | 'locked' | 'auto' {
  const raw = isPlainMap(configNode) ? configNode['lockOverride'] : null;
  const s = raw == null ? '' : String(raw);
  return s === 'open' || s === 'locked' ? s : 'auto';
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
    out[name] = { position, eligible: raw['eligible'] === true };
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
