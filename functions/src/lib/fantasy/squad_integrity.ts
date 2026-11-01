// Server-side squad integrity (audit I2, owner-approved "squad hardening"
// 2026-11-01). Pure: no firebase imports; the db-coupled loading lives in
// orchestration.ts (loadIntegrityInputs) behind the FantasyDb seam.
//
// The client builds squads with the engine's validateSquad and the RTDB
// rules pin the squad's SHAPE (Squads/$uid .validate), but neither can stop
// a signed-in fan REST-writing "seven copies of the top striker at $0.0M".
// So the server judges every squad it is about to lock (the sweep's
// PublishedPicks snapshot, and a FIRST finalize's live-Squads fallback):
//
//   tooManyPlayers   — more picks than squadSize(Config)
//   tooManyStarters  — more non-bench picks than the formation's starters
//                      (startersGk + startersDef + startersAtt): the engine
//                      scores EVERY non-bench pick at full points, so a
//                      REST write flagging the bench as starters would be
//                      "Bench Boost every week" — rules can't count
//                      children, the judge can. A legitimate client never
//                      saves more starters than the formation, and an owner
//                      position change never touches bench flags.
//   duplicatePlayer  — the same player twice
//   unknownPlayer    — a NEW pick (see below) that is not a usable entry of
//                      the market (Fantasy/<sport>/<season>/Players)
//   ineligiblePlayer — a NEW pick of a guest (Players/<name>/eligible false)
//   overBudget       — the squad's cost, at TRUSTED prices, is over
//                      Config.budgetTenths
//
// An invalid squad is snapshotted VERBATIM (so the manager can see exactly
// what was judged) plus `Invalid: [issues]`, scores ZERO for the week
// (History TotalTenths 0, Invalid kept, no Breakdown), gets a
// SquadAlerts/<uid> {Gw, Kind:'invalid', Issues, CreatedAt} for the fan's
// banner, and the run warns. 'formation' and 'badCaptain' are NOT integrity
// issues: they keep today's tolerant handling (holder protection after a
// position change, the vice/no-armband rules). A squad with FEWER picks than
// squadSize is a formation problem too (it can only lose points; a Config
// that grows the squad mid-season must not zero every saved squad).
//
// TRUSTED PRICES — the budget check never believes the client's
// pick.priceTenths on its own, but it cannot simply re-price every pick at
// TODAY's market either: a pick stores the price PAID (squad.ts; spec §4 —
// no profit-split accounting) and the client's budget bar sums those, so a
// squad that bought at $50.0M stays legal when its players rise on Monday.
// Re-pricing held players at market would zero exactly the managers who
// picked well. So, per pick:
//   - NEW (bought since the last lock): at least the LOWEST market price the
//     player had during this window — the "market floor", min(current
//     Players price, the price he had during the previous gameweek,
//     PriceHistory/<gw-1>; the window opens at midnight and the Monday
//     reprice moves prices at 10:00, so a Monday-morning buy legitimately
//     paid last week's price) — max(client, market floor).
//   - HELD (in the manager's previous locked squad — the same baseline the
//     transfer counter uses, effectiveSquadAfterWeek(gw-1)): at least
//     min(the price judged last week, market floor) — lowering a held
//     player's price below what he paid buys nothing, except down to a
//     price he has since FALLEN to (the client lets a manager remove him and
//     add him back at today's price; the S15 replay does exactly that). A
//     previous squad that was itself judged Invalid is no baseline (its
//     prices were never trusted): every pick is then judged as NEW, so a
//     forged price can't be carried forward by one zeroed week.
//   - never below zero.
// A legitimate client's paid price is always >= its floor, so the server's
// verdict equals the budget bar the manager saw. DOCUMENTED LIMIT: an owner
// price edit that RAISES a player above what a manager paid earlier in the
// same window, by more than that manager's remaining budget, flags that
// squad overBudget (rare; the alert says so and the next save fixes it).
// Guests and unknown names are only rejected as NEW picks: the Manager's
// "Make ineligible" promises holders keep the player until they sell
// (fantasy_players_page.dart; spec §3), and the server never removes a
// Players entry.

import { FantasyConfig, squadSize } from './fantasy_config';
import {
  FantasySquad, squadFromMap, squadStarters, validateSquad,
} from './squad';
import {
  childEntries, isPlainMap, marketPlayersOf, marketPricesOf,
} from './orchestration_db';

export type SquadIntegrityIssue =
  | 'tooManyPlayers' | 'tooManyStarters' | 'duplicatePlayer'
  | 'unknownPlayer' | 'ineligiblePlayer' | 'overBudget';

/** Stable report order (the alert's sentence follows it). */
export const SQUAD_INTEGRITY_ISSUES: readonly SquadIntegrityIssue[] = [
  'tooManyPlayers', 'tooManyStarters', 'duplicatePlayer', 'unknownPlayer',
  'ineligiblePlayer', 'overBudget',
];

/** The marker key on PublishedPicks/<gw>/<uid> and History/<gw>/<uid>. */
export const INVALID_KEY = 'Invalid';

/** SquadAlerts/<uid> Kind for an integrity verdict (the position-change
 *  alert carries no Kind — fantasy_parsers.dart squadAlertFromNode). */
export const INVALID_ALERT_KIND = 'invalid';

export interface IntegrityMarketEntry {
  priceTenths: number;
  eligible: boolean;
}

/** What the judge needs beyond the squad itself. */
export interface IntegrityInputs {
  /** Players/<name>, usable entries only (a usable position — what the
   *  client market can show); guests included with eligible false. */
  market: Record<string, IntegrityMarketEntry>;
  /** uid -> the manager's effective squad after the previous gameweek
   *  (raw PublishedPicks/History node; absent = first squad). */
  previousByUid: Record<string, unknown>;
  /** PriceHistory/<gw-1>: the prices DURING the previous gameweek. */
  previousWeekPrices: Record<string, number>;
}

/** Players node -> the judge's market (usable entries only). */
export function integrityMarketOf(
  playersNode: unknown,
): Record<string, IntegrityMarketEntry> {
  const prices = marketPricesOf(playersNode);
  const out: Record<string, IntegrityMarketEntry> = {};
  for (const [name, p] of Object.entries(marketPlayersOf(playersNode))) {
    out[name] = { priceTenths: prices[name] ?? 0, eligible: p.eligible };
  }
  return out;
}

/** PriceHistory/<gw> node -> name -> tenths (numbers only). */
export function priceSnapshotOf(node: unknown): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [name, v] of childEntries(node)) {
    if (typeof v === 'number' && Number.isFinite(v)) out[name] = Math.trunc(v);
  }
  return out;
}

/** The Invalid marker of a snapshot/History row (a list or the index-keyed
 *  map RTDB may hand back): its issue names, in stored order; null = not
 *  invalid. Never empty when non-null (a marker without a usable name reads
 *  ['invalid']), so a History row rewritten from it keeps the marker — RTDB
 *  would drop an empty list. */
export function invalidIssuesOf(raw: unknown): string[] | null {
  if (!isPlainMap(raw)) return null;
  const marker = raw[INVALID_KEY];
  if (marker == null || marker === false) return null;
  const names = childEntries(marker).map(([, v]) => v)
    .filter((v): v is string => typeof v === 'string' && v.length > 0);
  return names.length > 0 ? names : ['invalid'];
}

/** Whether a row carries an Invalid marker at all. */
export function isInvalidRow(raw: unknown): boolean {
  return invalidIssuesOf(raw) !== null;
}

/** The previous locked squad as a price baseline: null when absent,
 *  unreadable, or itself judged Invalid (see TRUSTED PRICES). */
export function baselineSquadOf(raw: unknown): FantasySquad | null {
  if (!isPlainMap(raw) || isInvalidRow(raw)) return null;
  try {
    return squadFromMap(raw);
  } catch {
    return null;
  }
}

/** The trusted price of every pick (same order as squad.picks). */
export function trustedPrices(
  squad: FantasySquad, market: Record<string, IntegrityMarketEntry>,
  previous: FantasySquad | null, previousWeekPrices: Record<string, number>,
): number[] {
  const held = new Map<string, number>();
  for (const p of previous?.picks ?? []) {
    held.set(p.playerId, Math.max(held.get(p.playerId) ?? 0, p.priceTenths));
  }
  return squad.picks.map((p) => {
    // The lowest price the player could be BOUGHT at during this window.
    const m = market[p.playerId];
    let marketFloor: number | undefined;
    if (m !== undefined) {
      const last = previousWeekPrices[p.playerId];
      marketFloor = last === undefined
        ? m.priceTenths : Math.min(m.priceTenths, last);
    }
    const prev = held.get(p.playerId);
    const floor = prev !== undefined
      // Held: what he paid — or less, when the price has since fallen (the
      // client lets a manager sell and re-buy him at today's price).
      ? Math.min(prev, marketFloor ?? prev)
      : marketFloor ?? 0;
    return Math.max(0, p.priceTenths, floor);
  });
}

/** The integrity verdict for one squad ([] = valid). Pure. */
export function squadIntegrityIssues(
  squad: FantasySquad, cfg: FantasyConfig,
  market: Record<string, IntegrityMarketEntry>,
  previous: FantasySquad | null,
  previousWeekPrices: Record<string, number>,
): SquadIntegrityIssue[] {
  const found = new Set<SquadIntegrityIssue>();
  if (squad.picks.length > squadSize(cfg)) found.add('tooManyPlayers');
  const startersTotal = cfg.startersGk + cfg.startersDef + cfg.startersAtt;
  if (squadStarters(squad).length > startersTotal) found.add('tooManyStarters');

  const heldIds = new Set((previous?.picks ?? []).map((p) => p.playerId));
  for (const p of squad.picks) {
    if (heldIds.has(p.playerId)) continue; // holders keep guests (spec §3)
    const m = market[p.playerId];
    if (m === undefined) found.add('unknownPlayer');
    else if (!m.eligible) found.add('ineligiblePlayer');
  }

  // Duplicates + budget through the engine's own validateSquad, run on the
  // squad re-priced at the trusted prices (formation/badCaptain ignored).
  const prices = trustedPrices(squad, market, previous, previousWeekPrices);
  const repriced: FantasySquad = {
    ...squad,
    picks: squad.picks.map((p, i) => ({ ...p, priceTenths: prices[i] })),
  };
  for (const issue of validateSquad(repriced, cfg)) {
    if (issue === 'duplicatePlayer' || issue === 'overBudget') found.add(issue);
  }
  return SQUAD_INTEGRITY_ISSUES.filter((i) => found.has(i));
}

/** The verdict for a raw squad node of [uid] against [inputs]; null when
 *  the node is not a parseable squad (malformed squads keep their existing
 *  handling: snapshotted verbatim, skipped by finalize). */
export function integrityVerdictOf(
  raw: unknown, uid: string, cfg: FantasyConfig, inputs: IntegrityInputs,
): SquadIntegrityIssue[] | null {
  if (!isPlainMap(raw)) return null;
  let squad: FantasySquad;
  try {
    squad = squadFromMap(raw);
  } catch {
    return null;
  }
  return judgeSquad(squad, uid, cfg, inputs);
}

/** [squadIntegrityIssues] for [uid]'s parsed squad against [inputs]. */
export function judgeSquad(
  squad: FantasySquad, uid: string, cfg: FantasyConfig, inputs: IntegrityInputs,
): SquadIntegrityIssue[] {
  return squadIntegrityIssues(squad, cfg, inputs.market,
    baselineSquadOf(inputs.previousByUid[uid]), inputs.previousWeekPrices);
}

/** SquadAlerts/<uid> for an invalid week. */
export function invalidAlertNode(
  gw: number, issues: readonly SquadIntegrityIssue[], nowMs: number,
): Record<string, unknown> {
  return {
    Gw: gw, Kind: INVALID_ALERT_KIND, Issues: [...issues], CreatedAt: nowMs,
  };
}

/** Whether a SquadAlerts/<uid> node is an integrity alert. */
export function isInvalidAlert(node: unknown): boolean {
  return isPlainMap(node) && node['Kind'] === INVALID_ALERT_KIND;
}

/** Same Gw + same issues (CreatedAt aside) — a rerun rewrites nothing. */
export function sameInvalidAlert(
  node: unknown, gw: number, issues: readonly SquadIntegrityIssue[],
): boolean {
  if (!isInvalidAlert(node)) return false;
  const m = node as Record<string, unknown>;
  const have = childEntries(m['Issues']).map(([, v]) => v);
  return Number(m['Gw']) === gw && have.length === issues.length &&
    issues.every((i, k) => have[k] === i);
}
