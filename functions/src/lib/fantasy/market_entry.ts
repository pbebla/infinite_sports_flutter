// What a market entry starts with (season setup + schedule plan 2026-11-05,
// Task 6). One module for everything that decides a NEW market entry's
// position and price, shared by the Manager's season Start (season_start.ts)
// and the mid-season joiners (Task 7's roster sync):
//
//   - the registration -> fantasy position mapping (port of
//     tool/seed_fantasy_logic.dart mapRegistrationPosition / parseLineups);
//   - the position-average price a player with no history opens at;
//   - the carry-over of a returning player's last price + position from the
//     newest earlier fantasy season.
//
// Pure TS behind the FantasyDb seam — no firebase imports.

import { FantasyConfig, FantasyPosition } from './fantasy_config';
import {
  childEntries, FantasyDb, fantasyRoot, isPlainMap, marketPlayersOf, marketPricesOf,
  toIntLoose,
} from './orchestration_db';
import { snapPrice } from './pricing';

export type { FantasyPosition } from './fantasy_config';

// ── Registration position ───────────────────────────────────────────────────

/** Registration position -> fantasy position (spec §3 defaults; port of
 *  tool/seed_fantasy_logic.dart mapRegistrationPosition): Goal Keeper -> GK,
 *  Defender -> DEF, Midfielder / Striker -> ATT. A multi-select string
 *  (';' or ':' separated in real data, also ',' and '/') uses the FIRST
 *  listed position; missing, blank or unknown reads as ATT (the spec's
 *  midfielder default — the owner can change it per player before Start). */
export function mapRegistrationPosition(raw: unknown): FantasyPosition {
  const text = raw === null || raw === undefined ? '' : String(raw);
  let first = '';
  for (const part of text.split(/[;:,/]/)) {
    const trimmed = part.trim();
    if (trimmed.length > 0) {
      first = trimmed;
      break;
    }
  }
  const p = first.toLowerCase().replace(/[^a-z]/g, '');
  if (p === 'goalkeeper' || p === 'gk' || p === 'keeper' || p === 'goalie') return 'GK';
  if (p === 'defender' || p === 'defense' || p === 'defence' || p === 'def' || p === 'd') {
    return 'DEF';
  }
  return 'ATT';
}

/** The `Users/<uid>/Information/<field>` a player's sign-up position lives
 *  under: 'Futsal' -> 'FutsalPosition', 'Flag Football' ->
 *  'FlagFootballPosition'. */
export function signupPositionField(sport: string): string {
  return `${sport.replace(/\s+/g, '')}Position`;
}

/** A player's profile photo (`PublicProfiles/<uid>/ProfileUrl`), trimmed;
 *  null when there is none or it is blank. A failed read throws — a photo
 *  that could not be read is not "no photo". */
export async function readProfilePhoto(db: FantasyDb, uid: string): Promise<string | null> {
  const raw = await db.read(`PublicProfiles/${uid}/ProfileUrl`);
  const photo = typeof raw === 'string' ? raw.trim() : '';
  return photo.length > 0 ? photo : null;
}

/** A player's sign-up position as the registration form stored it
 *  (`Users/<uid>/Information/<Sport>Position`, e.g. 'Defender;Striker');
 *  '' when there is none. Feed it to mapRegistrationPosition. A failed read
 *  throws. */
export async function readSignupPosition(
  db: FantasyDb, sport: string, uid: string,
): Promise<string> {
  const raw = await db.read(`Users/${uid}/Information/${signupPositionField(sport)}`);
  return raw === null || raw === undefined ? '' : String(raw);
}

// ── Market entries and the position average ────────────────────────────────

/** One market player as the pricing needs it. */
export interface MarketEntry {
  position: FantasyPosition;
  priceTenths: number;
  eligible: boolean;
}

/** The market (Fantasy/<sport>/<season>/Players) as {name -> MarketEntry}.
 *  Built from the finalizer's own parsers (marketPlayersOf: entries with an
 *  unusable position are skipped; marketPricesOf: a missing price reads 0), so
 *  the market is parsed in exactly one place. */
export function marketEntriesOf(playersNode: unknown): Record<string, MarketEntry> {
  const prices = marketPricesOf(playersNode);
  const out: Record<string, MarketEntry> = {};
  for (const [name, p] of Object.entries(marketPlayersOf(playersNode))) {
    out[name] = { position: p.position, priceTenths: prices[name] ?? 0, eligible: p.eligible };
  }
  return out;
}

/** The price a player with no history opens at: the mean price of the
 *  ELIGIBLE entries of [position] (never [excludeName] — a joiner is not part
 *  of its own average), rounded to a whole tenth and snapped to the price
 *  step. No such entry -> the rookie price. */
export function positionAveragePrice(
  players: Record<string, MarketEntry>, position: FantasyPosition,
  cfg: FantasyConfig, excludeName?: string,
): number {
  let sum = 0;
  let count = 0;
  for (const [name, p] of Object.entries(players)) {
    if (name === excludeName || !p.eligible || p.position !== position) continue;
    sum += p.priceTenths;
    count += 1;
  }
  if (count === 0) return cfg.rookiePriceTenths;
  return snapPrice(Math.round(sum / count), cfg);
}

// ── Line Ups roster ─────────────────────────────────────────────────────────

export interface RosterPlayer {
  name: string;
  team: string;
  uid: string | null;
}

/** Guests are recorded under the literal player name 'Guest' (league
 *  convention); they are never in the fantasy market (spec §3). */
function isGuestName(name: string): boolean {
  return name.trim().toLowerCase() === 'guest';
}

/** A Line Ups UID: blank, '0' or absent means "not linked". */
export function uidOf(raw: unknown): string | null {
  if (raw === null || raw === undefined) return null;
  const uid = String(raw).trim();
  return uid.length === 0 || uid === '0' ? null : uid;
}

/** Everyone on a season's `Line Ups` node ({team: {playerName: {UID?,
 *  ...stats}}}; the player's name is the key), team by team in node order.
 *  Port of tool/seed_fantasy_logic.dart parseLineups: a non-map team or
 *  player is skipped; 'Guest' (any case) is left out. */
export function rosterOf(lineupsNode: unknown): RosterPlayer[] {
  const out: RosterPlayer[] = [];
  for (const [team, lineup] of childEntries(lineupsNode)) {
    if (!isPlainMap(lineup)) continue;
    for (const [name, info] of childEntries(lineup)) {
      if (!isPlainMap(info) || isGuestName(name)) continue;
      out.push({ name, team, uid: uidOf(info['UID']) });
    }
  }
  return out;
}

// ── Carry-over from earlier seasons ─────────────────────────────────────────

export interface CarryOver {
  priceTenths: number;
  position: FantasyPosition;
  /** The earlier season this price and position come from. */
  season: string;
}

/** What loadCarryOver found: the lookup, and the newest earlier season that
 *  has a market at all (the season a new one copies its Config and season
 *  pass from) — null when there is none. */
export interface CarryOverIndex {
  lookup: (name: string, uid: string | null) => CarryOver | null;
  sourceSeason: string | null;
}

function nameKey(name: string): string {
  return name.trim().toLowerCase();
}

/** One earlier season's entry by name: the carry-over plus whether the entry
 *  is linked to ANY uid (its Players `uid` field or that season's Line Ups
 *  UID). */
interface NamedCarry {
  carry: CarryOver;
  linked: boolean;
}

interface SeasonIndex {
  byUid: Map<string, CarryOver>;
  byName: Map<string, NamedCarry>;
}

/** One earlier season's market, indexed by uid (a Players `uid` field, or
 *  that season's Line Ups uid -> name) and by trimmed lowercase name. An
 *  entry whose position is unusable or whose price is not above 0 is
 *  skipped (it carries nothing over). */
function indexSeason(season: string, playersNode: unknown, lineupsNode: unknown): SeasonIndex {
  const byUid = new Map<string, CarryOver>();
  const byName = new Map<string, NamedCarry>();
  const byExactName = new Map<string, NamedCarry>();
  const market = marketEntriesOf(playersNode);
  for (const [name, raw] of childEntries(playersNode)) {
    const m = Object.hasOwn(market, name) ? market[name] : undefined;
    if (m === undefined || m.priceTenths <= 0 || !isPlainMap(raw)) continue;
    const uid = uidOf(raw['uid']);
    const named: NamedCarry = {
      carry: { priceTenths: m.priceTenths, position: m.position, season },
      linked: uid !== null,
    };
    byExactName.set(name, named);
    if (!byName.has(nameKey(name))) byName.set(nameKey(name), named);
    if (uid !== null && !byUid.has(uid)) byUid.set(uid, named.carry);
  }
  for (const player of rosterOf(lineupsNode)) {
    const named = byExactName.get(player.name);
    if (player.uid === null || named === undefined) continue;
    named.linked = true;
    if (!byUid.has(player.uid)) byUid.set(player.uid, named.carry);
  }
  return { byUid, byName };
}

/** The seasons below [season], newest first: the numeric ones only (a
 *  non-numeric season has no predecessor). */
function earlierSeasons(season: string): string[] {
  if (!/^\d+$/.test(season)) return [];
  const n = Number(season);
  const out: string[] = [];
  for (let s = n - 1; s >= 1; s--) out.push(String(s));
  return out;
}

/** loadCarryOver plus the source season. For s = season-1 down to 1: when
 *  Fantasy/<sport>/<s>/Players exists the season counts — its market and its
 *  Line Ups (<sport>/<s>/Line Ups) are read.
 *
 *  A player is matched SEASON BY SEASON, newest first, and the first season
 *  that matches wins (T6c ruling 2026-11-05): within a season by uid (that
 *  season's Line Ups uid -> name, or a Players `uid` field), else by trimmed
 *  lowercase name — unless that season's same-name entry is linked to a
 *  DIFFERENT uid (a namesake, not the same person). A player with no uid has
 *  nothing to contradict the entry, so a name still matches. A newer season's
 *  unlinked same-name entry therefore beats an older season's uid match.
 *
 *  A failed read throws (an error is not "no history"). */
export async function loadCarryOverIndex(
  db: FantasyDb, sport: string, season: string,
): Promise<CarryOverIndex> {
  // Every earlier season's Players is asked at once (one failed read rejects
  // the lot); the seasons that have one then bring their Line Ups.
  const candidates = earlierSeasons(season);
  const playersNodes = await Promise.all(
    candidates.map((s) => db.read(`${fantasyRoot(sport, s)}/Players`)));
  const counted = candidates
    .map((s, i) => ({ season: s, players: playersNodes[i] }))
    .filter((c) => c.players !== null && c.players !== undefined);
  const lineupsNodes = await Promise.all(
    counted.map((c) => db.read(`${sport}/${c.season}/Line Ups`)));
  const seasons = counted.map((c, i) => indexSeason(c.season, c.players, lineupsNodes[i]));
  const sourceSeason = counted.length > 0 ? counted[0].season : null;
  return {
    sourceSeason,
    lookup: (name, uid) => {
      const key = nameKey(name);
      for (const idx of seasons) {
        if (uid !== null) {
          const byUid = idx.byUid.get(uid);
          if (byUid !== undefined) return byUid;
        }
        const named = idx.byName.get(key);
        // A uid that did not match above AND an entry linked to some uid:
        // that entry belongs to someone else.
        if (named !== undefined && !(uid !== null && named.linked)) return named.carry;
      }
      return null;
    },
  };
}

/** The carry-over lookup for a player of [season]: their price and position
 *  from the newest earlier fantasy season they were in (null = new). */
export async function loadCarryOver(
  db: FantasyDb, sport: string, season: string,
): Promise<(name: string, uid: string | null) => CarryOver | null> {
  return (await loadCarryOverIndex(db, sport, season)).lookup;
}
