// News player-card snapshots (spec §4.1) — pure TS, no firebase imports.
//
// A PlayerCard is taken when a post/draft is built, so a post reads
// correctly forever and the fan feed needs no extra listeners. The Manager
// builds the same shape in Dart (compose/templates); this is the server
// side (autopilot drafts, the writeFantasyCopy callable).
//
// SOURCES (under Fantasy/<sport>/<season> unless noted):
// - Players/<name> = {position, priceTenths, eligible, teamName, photoUrl?}
//   -> position / team / photo / price. Parsed like fantasy_player.dart
//   FantasyPlayer.fromNode: an unusable position = not a market player.
// - PriceChanges/<gw>/<name> = {delta} (+ a `Manual: true` flag key, which
//   is not a map and so never reads as a row) -> latest week's delta.
// - PlayerWeeks/<gw>/<name> = int -> latest finalized week's points.
// - PlayerTotals/<name> = {points, ownershipPct} or a bare number (= points)
//   -> season points + ownership.
// - <sport>/<season>/Date -> season goals (Goal + PenGoal) / assists,
//   tallied through the fantasy stats mapper (seasonGoalsAssists).
//
// "Latest" = the numerically highest gw key present in THAT node (gw keys
// are small ints, so the nodes list-coerce — childEntries reads both
// shapes). Optional fields are OMITTED when unknown: RTDB rejects undefined.

import { FantasyPosition, parsePosition } from './fantasy_config';
import {
  childEntries, gamesOfDate, isPlainMap, toIntLoose,
} from './orchestration_db';
import { mapGameToStats } from './stats_mapper';

export interface PlayerCard {
  name: string;
  position: FantasyPosition;
  team: string;
  photoUrl?: string;
  priceTenths: number;
  priceDeltaTenths?: number;
  gw?: number;
  gwPoints?: number;
  seasonPoints?: number;
  ownershipPct?: number;
  goals: number;
  assists: number;
}

export type GoalsAssists = Record<string, { goals: number; assists: number }>;

/** Max tagged players per post (spec §4.1: 0–5). */
export const MAX_POST_PLAYERS = 5;

/** Season Goal(+PenGoal) / Assist tallies per player name across every game
 *  under `<sport>/<season>/Date` ([dateNode] = that Date node). Each game is
 *  replayed through mapGameToStats for team1 and team2 — the same
 *  case-insensitive activity keys, metadata skipping and List/Map coercion
 *  the finalizer scores with. Fantasy conventions apply: friendlies are
 *  dropped (gamesOfDate) and a forfeited game's stray activity never counts
 *  (the mapper ignores it). Players with neither a goal nor an assist are
 *  left out (cards default them to 0). */
export function seasonGoalsAssists(dateNode: unknown): GoalsAssists {
  const out: GoalsAssists = {};
  for (const [, dayNode] of childEntries(dateNode)) {
    for (const game of gamesOfDate(dayNode)) {
      const teams = new Set<string>();
      for (const key of ['team1', 'team2']) {
        const team = game[key];
        if (team != null && String(team).length > 0) teams.add(String(team));
      }
      for (const teamName of teams) {
        const stats = mapGameToStats(game, { teamName });
        for (const [name, s] of Object.entries(stats)) {
          if (s.goals === 0 && s.assists === 0) continue;
          const t = out[name] ?? (out[name] = { goals: 0, assists: 0 });
          t.goals += s.goals;
          t.assists += s.assists;
        }
      }
    }
  }
  return out;
}

/** A child of a node that may be a Map or a list-coerced Array. */
function childOf(node: unknown, key: string): unknown {
  if (Array.isArray(node)) {
    const i = Number(key);
    return Number.isInteger(i) && i >= 0 ? node[i] ?? null : null;
  }
  return isPlainMap(node) ? node[key] ?? null : null;
}

/** The numerically highest gw key of a week-keyed node; null when none. */
function latestWeekOf(node: unknown): number | null {
  let best: number | null = null;
  for (const [k] of childEntries(node)) {
    const w = Number(k);
    if (Number.isInteger(w) && w > 0 && (best === null || w > best)) best = w;
  }
  return best;
}

/** An int when [v] is a finite number or a full signed decimal string;
 *  undefined otherwise (the field is then omitted). */
function optInt(v: unknown): number | undefined {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.trunc(v) : undefined;
  if (typeof v === 'string' && /^[+-]?\d+$/.test(v.trim())) return Number(v.trim());
  return undefined;
}

/** One card; null when [name] is not a usable market player (absent from
 *  Players, or an unparseable position). Optional fields are OMITTED (never
 *  undefined) when unknown. `gw` is the latest finalized week of the season
 *  even when this player has no entry in it (then gwPoints is omitted). */
export function buildPlayerCard(name: string, src: {
  playersRaw: unknown;
  playerTotalsRaw: unknown;
  playerWeeksRaw: unknown;
  priceChangesRaw: unknown;
  goalsAssists: GoalsAssists;
}): PlayerCard | null {
  const row = childOf(src.playersRaw, name);
  if (!isPlainMap(row)) return null;
  let position: FantasyPosition;
  try {
    position = parsePosition(String(row['position'] ?? ''));
  } catch {
    return null;
  }

  const card: PlayerCard = {
    name,
    position,
    team: row['teamName'] == null ? '' : String(row['teamName']),
    priceTenths: toIntLoose(row['priceTenths']),
    goals: 0,
    assists: 0,
  };
  const photo = row['photoUrl'] == null ? '' : String(row['photoUrl']).trim();
  if (photo.length > 0) card.photoUrl = photo;

  const priceWeek = latestWeekOf(src.priceChangesRaw);
  if (priceWeek !== null) {
    const change = childOf(childOf(src.priceChangesRaw, String(priceWeek)), name);
    const delta = isPlainMap(change) ? optInt(change['delta']) : undefined;
    if (delta !== undefined) card.priceDeltaTenths = delta;
  }

  const week = latestWeekOf(src.playerWeeksRaw);
  if (week !== null) {
    card.gw = week;
    const points = optInt(childOf(childOf(src.playerWeeksRaw, String(week)), name));
    if (points !== undefined) card.gwPoints = points;
  }

  const totals = childOf(src.playerTotalsRaw, name);
  if (isPlainMap(totals)) {
    const points = optInt(totals['points']);
    if (points !== undefined) card.seasonPoints = points;
    const pct = optInt(totals['ownershipPct']);
    if (pct !== undefined) card.ownershipPct = pct;
  } else {
    const points = optInt(totals);
    if (points !== undefined) card.seasonPoints = points;
  }

  const ga = src.goalsAssists[name];
  if (ga) {
    card.goals = ga.goals;
    card.assists = ga.assists;
  }
  return card;
}

/** The post's `Players` node: cards in input order, unknown names (null)
 *  dropped, at most [MAX_POST_PLAYERS], keyed "0", "1", ... — and any
 *  undefined optional stripped, so RTDB accepts it. Empty -> null (the
 *  caller omits the node). */
export function cardsNode(
  cards: ReadonlyArray<PlayerCard | null | undefined>,
): Record<string, PlayerCard> | null {
  const kept = cards
    .filter((c): c is PlayerCard => c != null)
    .slice(0, MAX_POST_PLAYERS);
  if (kept.length === 0) return null;
  const out: Record<string, PlayerCard> = {};
  kept.forEach((c, i) => {
    out[String(i)] = Object.fromEntries(
      Object.entries(c).filter(([, v]) => v !== undefined)) as PlayerCard;
  });
  return out;
}
