// Starting a fantasy season from the Manager (season setup + schedule plan
// 2026-11-05, Task 6). Pure TS behind the FantasyDb seam; the thin admin
// callables (previewFantasySeason / startFantasySeason) live in
// src/fantasy_season.ts.
//
// The owner's decisions: a new season opens each returning player at their
// FINAL price and position from the newest earlier fantasy season (his own
// edits included); a brand-new player gets their sign-up position and the
// AVERAGE price of the returning players in that position; he previews every
// row and edits before Start; the season pass (Config/Access) is pre-filled
// from the previous season and editable.
//
// buildSeasonPreview — read-only: one row per roster player (where the price
//   and position came from), the Config the season will start with, the
//   season-pass draft and the problems that would block Start.
// startSeason — recomputes the preview (never trusts a stale one), applies the
//   owner's edits and writes, in this order: StartedAt (the once-only claim),
//   Players, then Config. The Config goes LAST: its presence is what switches
//   the engine on, so the market is complete before anything reads it.
//
// NODES (under Fantasy/<sport>/<season>/):
//   StartedAt = { At: epoch ms, By: uid }          (server-only claim; T6b:
//               without a Config and 10 minutes old it is a Start that died —
//               the preview ignores it and the next Start takes it over)
//   Players   = { <name>: { position, priceTenths, eligible:true, teamName,
//                           uid?, photoUrl? } }    (the shape the fan market parses)
//   Config    = the newest earlier season's Config minus lockOverride,
//               lockOverrideUntil, Access, Deadlines and SkippedDates, plus
//               lockOverride:'auto' and the Access node below; with no earlier
//               season, futsalDefault + lockOverride:'auto'.
//   Config/Access = { Mode, AmountDollars, Methods:{Venmo,Zelle,Card},
//               RegisteredPlayersFree, ChangedAt, ChangedBy } — exactly what the
//               Manager's own writer stores (fantasy_access_admin.dart
//               AccessConfig.toMap + the service's change stamp); the paywall
//               `Copy` and Cash are not carried over (Copy stays at its
//               defaults, cash is recorded per player by the owner only).

import { accessConfigFrom } from './access';
import {
  configFromMap, configToMap, FantasyConfig, futsalDefault, parsePosition,
} from './fantasy_config';
import {
  CarryOver, FantasyPosition, loadCarryOverIndex, MarketEntry,
  mapRegistrationPosition, positionAveragePrice, readProfilePhoto, readSignupPosition,
  rosterOf,
} from './market_entry';
import type { FantasyLogger } from './orchestration';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap, isTestFillSeason,
} from './orchestration_db';
import { snapPrice } from './pricing';

const silent: FantasyLogger = { info: () => undefined, warn: () => undefined };

// ── Types ───────────────────────────────────────────────────────────────────

export interface PreviewRow {
  name: string;
  team: string;
  uid: string | null;
  position: FantasyPosition;
  /** 'season' = the newest earlier season's market; 'signup' = the player's
   *  registration; 'default' = nothing on file (ATT). */
  positionFrom: 'season' | 'signup' | 'default';
  priceTenths: number;
  /** 'season' = last season's final price; 'average' = the returning
   *  players' average in this position; 'rookie' = nobody to average. */
  priceFrom: 'season' | 'average' | 'rookie';
  fromSeason: string | null;
  photoUrl: string | null;
}

export type StartProblem = 'noRosters' | 'noSchedule' | 'alreadyStarted' | 'sourceIsTestFill';

/** The season pass the new season starts with (Config/Access, minus the
 *  paywall copy and the change stamp). */
export interface AccessDraft {
  Mode: 'free' | 'pass';
  AmountDollars: number | null;
  Methods: { Venmo: boolean; Zelle: boolean; Card: boolean };
  RegisteredPlayersFree: boolean;
}

export interface SeasonPreview {
  sport: string;
  season: string;
  /** The newest earlier season with a market — prices, positions, Config and
   *  season pass come from it; null when this is the first. */
  sourceSeason: string | null;
  rows: PreviewRow[];
  settings: { lockHour: number; copiedFrom: string | null };
  access: AccessDraft;
  problems: StartProblem[];
}

/** What the callables turn into an HttpsError (same code / details). */
export class StartSeasonError extends Error {
  constructor(
    readonly code: 'failed-precondition' | 'invalid-argument',
    message: string,
    readonly details: Record<string, unknown>,
  ) {
    super(message);
    this.name = 'StartSeasonError';
  }
}

function refused(problems: StartProblem[]): StartSeasonError {
  return new StartSeasonError(
    'failed-precondition', `The season cannot be started: ${problems.join(', ')}.`,
    { problems });
}

function badAccess(why: string): StartSeasonError {
  return new StartSeasonError(
    'invalid-argument', `The season pass settings are not valid: ${why}.`,
    { problem: 'badAccess' });
}

function badEdit(name: string, why: string): StartSeasonError {
  return new StartSeasonError(
    'invalid-argument', `Unusable edit for ${name}: ${why}.`,
    { problem: 'badEdit', name });
}

// ── The season pass ─────────────────────────────────────────────────────────

/** The most a season pass may cost (fantasy_access_admin.dart
 *  kMaxAccessAmountDollars). */
const MAX_ACCESS_DOLLARS = 1000;

/** The draft a season with no earlier season pass starts from. */
function freeDraft(): AccessDraft {
  return {
    Mode: 'free', AmountDollars: null,
    Methods: { Venmo: true, Zelle: true, Card: true }, RegisteredPlayersFree: false,
  };
}

/** The pre-filled draft from the source season's Config/Access: mode, price,
 *  the three ways to pay and RegisteredPlayersFree — nothing else (Cash, the
 *  paywall copy and the change stamp are not carried). No Access node = the
 *  free defaults. */
function accessDraftOf(raw: unknown): AccessDraft {
  if (!isPlainMap(raw)) return freeDraft();
  const cfg = accessConfigFrom(raw);
  return {
    Mode: cfg.mode,
    AmountDollars: cfg.amountDollars > 0 ? cfg.amountDollars : null,
    Methods: {
      Venmo: cfg.methods.venmo, Zelle: cfg.methods.zelle, Card: cfg.methods.card,
    },
    RegisteredPlayersFree: cfg.registeredPlayersFree,
  };
}

/** The draft the owner submitted, checked: the Manager's own rules
 *  (validateAccessConfig + its strict amount parser) — a pass costs more
 *  than $0 and at most $1000, in whole dollars or ending .50, and needs at
 *  least one way to pay. Throws invalid-argument/badAccess otherwise. Free
 *  mode takes any amount (only a positive one is kept). */
export function validateAccessDraft(raw: unknown): AccessDraft {
  if (!isPlainMap(raw)) throw badAccess('missing');
  const mode = raw['Mode'];
  if (mode !== 'free' && mode !== 'pass') throw badAccess('unknown mode');
  const methods = raw['Methods'];
  if (!isPlainMap(methods) || typeof methods['Venmo'] !== 'boolean' ||
    typeof methods['Zelle'] !== 'boolean' || typeof methods['Card'] !== 'boolean') {
    throw badAccess('the ways to pay must each be on or off');
  }
  if (typeof raw['RegisteredPlayersFree'] !== 'boolean') {
    throw badAccess('registered players free must be on or off');
  }
  const amountRaw = raw['AmountDollars'];
  if (amountRaw !== null && amountRaw !== undefined &&
    (typeof amountRaw !== 'number' || !Number.isFinite(amountRaw))) {
    throw badAccess('the price is not a number');
  }
  const amount = typeof amountRaw === 'number' ? amountRaw : null;
  if (mode === 'pass') {
    if (amount === null || amount <= 0) throw badAccess('a season pass needs a price above $0');
    if (amount > MAX_ACCESS_DOLLARS) throw badAccess('the price is above $1000');
    const cents = Math.round(amount * 100);
    // At most two decimals, and only whole dollars or .50.
    if (Math.abs(amount * 100 - cents) > 1e-6 || cents % 50 !== 0) {
      throw badAccess('the price must be whole dollars or end in .50');
    }
    if (!methods['Venmo'] && !methods['Zelle'] && !methods['Card']) {
      throw badAccess('turn on at least one way to pay');
    }
  }
  return {
    Mode: mode,
    AmountDollars: amount,
    Methods: { Venmo: methods['Venmo'], Zelle: methods['Zelle'], Card: methods['Card'] },
    RegisteredPlayersFree: raw['RegisteredPlayersFree'],
  };
}

/** The Config/Access node, in the Manager's shape: the draft's fields plus
 *  the change stamp (ChangedAt = the start instant, ChangedBy = the admin). A
 *  free season with no price stores 0, as the Manager's mode card does. */
function accessNodeOf(draft: AccessDraft, byUid: string, nowMs: number): Record<string, unknown> {
  const amount = draft.AmountDollars !== null && draft.AmountDollars > 0
    ? draft.AmountDollars : 0;
  return {
    Mode: draft.Mode,
    AmountDollars: amount,
    Methods: {
      Venmo: draft.Methods.Venmo, Zelle: draft.Methods.Zelle, Card: draft.Methods.Card,
    },
    RegisteredPlayersFree: draft.RegisteredPlayersFree,
    ChangedAt: nowMs,
    ChangedBy: byUid,
  };
}

// ── The plan ────────────────────────────────────────────────────────────────

interface SeasonPlan {
  preview: SeasonPreview;
  /** The new season's engine numbers (read from the Config it will get). */
  cfg: FantasyConfig;
  /** The raw Config of the source season (null = none: defaults). */
  sourceConfig: Record<string, unknown> | null;
  /** T6b: the StartedAt a Start that died left behind (stale, no Config) —
   *  startSeason takes exactly this node over; null = none. */
  staleStartedAt: unknown;
}

/** T6b: how long a StartedAt without a Config stands for "a Start under
 *  way". A Start writes Players and Config within seconds (a callable times
 *  out long before), so an older claim with no Config is a Start that died
 *  without cleaning up. */
export const STARTED_AT_STALE_MS = 10 * 60 * 1000;

/** T6b: whether a stored StartedAt (with no Config next to it) is stale at
 *  [nowMs]: its `At` is [STARTED_AT_STALE_MS] or more in the past. A node
 *  with no numeric At (junk) is stale too: nothing says a Start is running. */
function isStaleStartedAt(node: unknown, nowMs: number): boolean {
  const at = isPlainMap(node) ? node['At'] : undefined;
  return typeof at !== 'number' || !Number.isFinite(at) ||
    nowMs - at >= STARTED_AT_STALE_MS;
}

/** Key-order-independent JSON (StartedAt compare-and-set). */
function sameJson(a: unknown, b: unknown): boolean {
  const canon = (v: unknown): string => {
    if (Array.isArray(v)) return `[${v.map(canon).join(',')}]`;
    if (isPlainMap(v)) {
      return `{${Object.keys(v).sort()
        .map((k) => `${JSON.stringify(k)}:${canon(v[k])}`).join(',')}}`;
    }
    return JSON.stringify(v ?? null);
  };
  return canon(a) === canon(b);
}

/** Everything a Start needs, read once. Writes nothing; a read that fails
 *  throws (a missing sign-up position or photo is not a fact). [nowMs]
 *  judges a StartedAt left without a Config (T6b). */
async function planSeason(
  db: FantasyDb, sport: string, season: string, nowMs: number,
): Promise<SeasonPlan> {
  const root = fantasyRoot(sport, season);
  const [configNode, startedNode, dateNode, lineupsNode, carry] = await Promise.all([
    db.read(`${root}/Config`),
    db.read(`${root}/StartedAt`),
    db.read(`${sport}/${season}/Date`),
    db.read(`${sport}/${season}/Line Ups`),
    loadCarryOverIndex(db, sport, season),
  ]);

  const source = carry.sourceSeason;
  let sourceConfig: Record<string, unknown> | null = null;
  let sourceIsTestFill = false;
  if (source !== null) {
    const sourceRoot = fantasyRoot(sport, source);
    const [sourceConfigNode, testFill] = await Promise.all([
      db.read(`${sourceRoot}/Config`),
      isTestFillSeason(db, sourceRoot),
    ]);
    sourceConfig = isPlainMap(sourceConfigNode) ? sourceConfigNode : null;
    sourceIsTestFill = testFill;
  }
  const cfg = sourceConfig === null ? futsalDefault() : configFromMap(sourceConfig);

  // The market is keyed by name: a name on two teams is one player.
  const seen = new Set<string>();
  const roster = rosterOf(lineupsNode).filter((p) => {
    if (seen.has(p.name)) return false;
    seen.add(p.name);
    return true;
  });

  const partial = await Promise.all(roster.map(async (p) => {
    const carried: CarryOver | null = carry.lookup(p.name, p.uid);
    const [photoUrl, signup] = await Promise.all([
      p.uid === null ? null : readProfilePhoto(db, p.uid),
      carried !== null || p.uid === null ? '' : readSignupPosition(db, sport, p.uid),
    ]);
    return { p, carried, photoUrl, signup };
  }));

  // The average is over the RETURNING players only — brand-new rows never
  // feed it, so the order of the roster cannot change anyone's price.
  const returning: Record<string, MarketEntry> = {};
  for (const { p, carried } of partial) {
    if (carried === null) continue;
    returning[p.name] = {
      position: carried.position,
      priceTenths: clampPrice(carried.priceTenths, cfg),
      eligible: true,
    };
  }
  const hasReturning = (position: FantasyPosition) =>
    Object.values(returning).some((e) => e.position === position);

  const rows: PreviewRow[] = partial.map(({ p, carried, photoUrl, signup }) => {
    if (carried !== null) {
      return {
        name: p.name, team: p.team, uid: p.uid,
        position: carried.position, positionFrom: 'season',
        priceTenths: clampPrice(carried.priceTenths, cfg), priceFrom: 'season',
        fromSeason: carried.season, photoUrl,
      };
    }
    const hasSignup = signup.trim().length > 0;
    const position = hasSignup ? mapRegistrationPosition(signup) : 'ATT';
    const average = hasReturning(position);
    return {
      name: p.name, team: p.team, uid: p.uid,
      position, positionFrom: hasSignup ? 'signup' : 'default',
      priceTenths: positionAveragePrice(returning, position, cfg),
      priceFrom: average ? 'average' : 'rookie',
      fromSeason: null, photoUrl,
    };
  });

  const problems: StartProblem[] = [];
  if (rows.length === 0) problems.push('noRosters');
  if (childEntries(dateNode).length === 0) problems.push('noSchedule');
  // A Config means started; so does a FRESH StartedAt without one (a Start
  // under way). T6b: a StartedAt without a Config that is STARTED_AT_STALE_MS
  // old is a Start that died before it could clean up — not "started": the
  // owner can Start again, and startSeason takes the stale claim over.
  const hasConfig = configNode !== null && configNode !== undefined;
  const hasStarted = startedNode !== null && startedNode !== undefined;
  const startedIsStale = !hasConfig && hasStarted && isStaleStartedAt(startedNode, nowMs);
  if (hasConfig || (hasStarted && !startedIsStale)) problems.push('alreadyStarted');
  if (sourceIsTestFill) problems.push('sourceIsTestFill');

  return {
    cfg,
    sourceConfig,
    staleStartedAt: startedIsStale ? startedNode : null,
    preview: {
      sport, season,
      sourceSeason: source,
      rows,
      settings: {
        lockHour: cfg.lockHour,
        copiedFrom: sourceConfig === null ? null : source,
      },
      access: accessDraftOf(sourceConfig === null ? null : sourceConfig['Access']),
      problems,
    },
  };
}

function clampPrice(tenths: number, cfg: FantasyConfig): number {
  return Math.min(Math.max(tenths, cfg.priceMinTenths), cfg.priceMaxTenths);
}

/** The Manager's preview of Starting [sport] [season]. Never writes.
 *  [nowMs] (default: now) judges a StartedAt left without a Config (T6b). */
export async function buildSeasonPreview(
  db: FantasyDb, sport: string, season: string, nowMs: number = Date.now(),
): Promise<SeasonPreview> {
  return (await planSeason(db, sport, season, nowMs)).preview;
}

// ── Start ───────────────────────────────────────────────────────────────────

export interface RowEdit {
  priceTenths?: number;
  position?: FantasyPosition;
}

/** What a new season's Config must not inherit: a pause (lockOverride and
 *  its expiry), the season pass (replaced by the owner's draft) and the
 *  schedule changes that belonged to the old season's dates. */
const NOT_INHERITED = [
  'lockOverride', 'lockOverrideUntil', 'Access', 'Deadlines', 'SkippedDates',
] as const;

function newSeasonConfig(
  sourceConfig: Record<string, unknown> | null, access: Record<string, unknown>,
): Record<string, unknown> {
  const base: Record<string, unknown> = sourceConfig === null
    ? configToMap(futsalDefault())
    : JSON.parse(JSON.stringify(sourceConfig));
  for (const key of NOT_INHERITED) delete base[key];
  return { ...base, lockOverride: 'auto', Access: access };
}

/** The callable's `edits` argument: { <player name>: { priceTenths?,
 *  position? } }. Absent = none. Anything malformed is invalid-argument; a
 *  position's VALUE is checked at Start (it needs the roster). */
export function parseEditsArg(raw: unknown): Record<string, RowEdit> {
  if (raw === null || raw === undefined) return {};
  if (!isPlainMap(raw)) throw badEdit('(all)', 'edits must be a map of player names');
  const out: Record<string, RowEdit> = {};
  for (const [name, edit] of Object.entries(raw)) {
    if (!isPlainMap(edit)) throw badEdit(name, 'not a map');
    const parsed: RowEdit = {};
    const price = edit['priceTenths'];
    if (price !== undefined && price !== null) {
      if (typeof price !== 'number' || !Number.isFinite(price)) {
        throw badEdit(name, 'the price is not a number');
      }
      parsed.priceTenths = price;
    }
    const position = edit['position'];
    if (position !== undefined && position !== null) {
      if (typeof position !== 'string') throw badEdit(name, 'the position is not text');
      parsed.position = position as FantasyPosition;
    }
    out[name] = parsed;
  }
  return out;
}

/** T6b: replaces the StartedAt at [path] with [claim] only while it still
 *  holds exactly [stale]. An absent node (cleaned up meanwhile) is claimed
 *  set-if-absent instead. True = the claim is ours. */
async function takeOverStaleStart(
  db: FantasyDb, path: string, stale: unknown, claim: Record<string, unknown>,
): Promise<boolean> {
  let verdict: 'ours' | 'absent' | 'changed' = 'changed';
  await db.transaction(path, (current) => {
    if (current === null || current === undefined) {
      verdict = 'absent';
      return null; // FantasyDb: never abort on null (a no-op when absent)
    }
    if (!sameJson(current, stale)) {
      verdict = 'changed';
      return undefined;
    }
    verdict = 'ours';
    return claim;
  });
  switch (verdict as 'ours' | 'absent' | 'changed') {
    case 'ours': return true;
    case 'absent': return db.writeIfAbsent(path, claim);
    case 'changed': return false;
  }
}

/** Starts [sport] [season]: recompute the preview, refuse on any problem,
 *  validate the season pass, apply the owner's edits, claim StartedAt (or
 *  take over a stale one — T6b), write
 *  Players, then Config. Anything that fails after the claim removes what
 *  was written (Players, StartedAt — and Config, which may have landed
 *  despite the error) and rethrows, so the owner can simply try again.
 *  Errors: StartSeasonError (failed-precondition with the problem codes,
 *  invalid-argument badAccess / badEdit). */
export async function startSeason(
  db: FantasyDb, sport: string, season: string,
  edits: Record<string, RowEdit>, access: AccessDraft,
  byUid: string, nowMs: number, log: FantasyLogger = silent,
): Promise<{ players: number }> {
  const { preview, cfg, sourceConfig, staleStartedAt } =
    await planSeason(db, sport, season, nowMs);
  if (preview.problems.length > 0) throw refused(preview.problems);
  const draft = validateAccessDraft(access);

  // Edits: price snapped to the step and clamped into the price range, a
  // position that is not GK/DEF/ATT refused; a name not in the roster ignored.
  const known = new Set(preview.rows.map((r) => r.name));
  const ignored = Object.keys(edits).filter((name) => !known.has(name));
  const players: Record<string, Record<string, unknown>> = {};
  for (const row of preview.rows) {
    let { position, priceTenths } = row;
    const edit = Object.hasOwn(edits, row.name) ? edits[row.name] : undefined;
    if (edit !== undefined) {
      if (edit.priceTenths !== undefined && edit.priceTenths !== null) {
        if (typeof edit.priceTenths !== 'number' || !Number.isFinite(edit.priceTenths)) {
          throw badEdit(row.name, 'the price is not a number');
        }
        priceTenths = snapPrice(Math.round(edit.priceTenths), cfg);
      }
      if (edit.position !== undefined && edit.position !== null) {
        try {
          position = parsePosition(String(edit.position));
        } catch {
          throw badEdit(row.name, 'the position must be GK, DEF or ATT');
        }
      }
    }
    players[row.name] = {
      position,
      priceTenths,
      eligible: true,
      teamName: row.team,
      ...(row.uid !== null ? { uid: row.uid } : {}),
      ...(row.photoUrl !== null ? { photoUrl: row.photoUrl } : {}),
    };
  }
  if (ignored.length > 0) {
    log.info('fantasy season start: edits for players not in the roster ignored',
      { sport, season, ignoredEdits: ignored.length, names: ignored });
  }
  const config = newSeasonConfig(sourceConfig, accessNodeOf(draft, byUid, nowMs));

  const root = fantasyRoot(sport, season);
  const claim = { At: nowMs, By: byUid };
  if (staleStartedAt !== null) {
    // T6b: the claim a dead Start left — replaced only while it is still
    // that same stale node (a concurrent Start that took it over first wins).
    if (!(await takeOverStaleStart(db, `${root}/StartedAt`, staleStartedAt, claim))) {
      throw refused(['alreadyStarted']);
    }
    log.warn('fantasy season start: a stale StartedAt (a Start that died) ' +
      'taken over', { sport, season, by: byUid, stale: staleStartedAt });
  } else if (!(await db.writeIfAbsent(`${root}/StartedAt`, claim))) {
    throw refused(['alreadyStarted']);
  }
  let configAttempted = false;
  try {
    await db.write(`${root}/Players`, players);
    configAttempted = true;
    await db.write(`${root}/Config`, config);
  } catch (err) {
    log.warn('fantasy season start: write failed — rolling back', {
      sport, season, by: byUid, error: err instanceof Error ? err.message : String(err),
    });
    // Config first, so the engine never sees a Config without its market.
    const undo = [
      ...(configAttempted ? [`${root}/Config`] : []), `${root}/Players`, `${root}/StartedAt`,
    ];
    for (const path of undo) {
      try {
        await db.write(path, null);
      } catch (undoErr) {
        log.warn('fantasy season start: rollback step failed', {
          path, error: undoErr instanceof Error ? undoErr.message : String(undoErr),
        });
      }
    }
    throw err;
  }
  log.info('fantasy season start: started', {
    sport, season, by: byUid, players: preview.rows.length,
    copiedFrom: preview.settings.copiedFrom, accessMode: draft.Mode,
    ignoredEdits: ignored.length,
  });
  return { players: preview.rows.length };
}
