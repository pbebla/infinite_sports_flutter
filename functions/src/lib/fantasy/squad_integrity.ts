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
//                      Config.budgetTenths + realizedTenths (see below)
//
// An invalid squad is snapshotted VERBATIM (so the manager can see exactly
// what was judged) plus `Invalid: [issues]` (and the baseline's
// realizedTenths — see TRUSTED PRICES), scores ZERO for the week
// (History TotalTenths 0, Invalid kept, no Breakdown), gets a
// SquadAlerts/<uid> {Gw, Kind:'invalid', Issues, CreatedAt} for the fan's
// banner, and the run warns. 'formation' and 'badCaptain' are NOT integrity
// issues: they keep today's tolerant handling (holder protection after a
// position change, the vice/no-armband rules). A squad with FEWER picks than
// squadSize is a formation problem too (it can only lose points; a Config
// that grows the squad mid-season must not zero every saved squad).
//
// TRUSTED PRICES + THE FPL SELLING RULE (spec §4; selling.ts) — the budget
// check never believes the client's pick.priceTenths on its own. A pick
// stores the price PAID, and money moves only when a player is SOLD: the
// sale banks sellPriceTenths(paid, current) (half of any rise, rounded down;
// the full drop), and the running profit/loss of every sale since the
// season began, `realizedTenths` (may be negative), widens or narrows the
// budget: spent <= Config.budgetTenths + realizedTenths. The BASELINE is
// the manager's previous locked squad — the same one the transfer counter
// uses, effectiveSquadAfterWeek(gw-1), Free Hit aware — whose snapshot
// carries the prices this judge settled last week and its realizedTenths.
// Per pick (judgeSale):
//   - HELD = a baseline player id still in the squad: priced at the
//     baseline price. The client's price for a held player is ignored —
//     lowering it buys nothing, raising it costs nothing, and removing him
//     and adding him back before the deadline is no sale and no cheaper
//     re-buy (FPL).
//   - NEW (any other id): at least the LOWEST market price the player had
//     during this window — the "market floor", min(current Players price,
//     the price he had during the previous gameweek, PriceHistory/<gw-1>;
//     the window opens at midnight and the Monday reprice moves prices at
//     10:00, so a Monday-morning buy legitimately paid last week's price) —
//     max(0, client, market floor).
//   - SOLD = a baseline id absent from the squad: credited by the FPL rule
//     at the price he has NOW (market Players price; no "max(current, last
//     week)"): realized += sellPriceTenths(paid, current) - paid. A sold
//     player missing from the market — or priced <= 0 there (no usable
//     price) — adds 0.
// realizedTenths = the baseline's realizedTenths + every sale this week.
// A previous squad that was itself judged Invalid has no trusted picks (its
// prices were never judged): every pick is then NEW and nothing is sold, so
// a forged price can't be carried forward by one zeroed week — but its
// realizedTenths still carries (the server wrote that number: an Invalid
// snapshot keeps last week's realized, no sale credited). A MALFORMED
// baseline (no parseable squad) carries nothing: the snapshot keeps it
// verbatim, so any realizedTenths on it is the client's own writing.
// A VALID snapshot is re-written at the judged prices with its
// realizedTenths (transfer_state.ts annotateSquadIntegrity), so next week's
// held prices are the judge's own, never the client's.
// A legitimate client (the app's FPL-rule draft) prices its picks the same
// way, so the server's verdict equals the budget bar the manager saw.
// DOCUMENTED LIMIT: an owner price edit that RAISES a player above what a
// manager paid earlier in the same window, by more than that manager's
// remaining budget, flags that squad overBudget (rare; the alert says so
// and the next save fixes it).
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
import { realizedOf, sellPriceTenths } from './selling';

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

/** The judge's verdict on one squad at a lock. */
export interface LockVerdict {
  /** [] = valid. */
  issues: SquadIntegrityIssue[];
  /** The trusted price of every pick (same order as squad.picks). */
  prices: number[];
  /** The running sale profit/loss after this squad's sales (may be
   *  negative): the baseline's realizedTenths + this week's sales. */
  realizedTenths: number;
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

/** The realizedTenths a baseline node carries forward: realizedOf(raw) for
 *  a node the server judged — a parseable squad, Valid OR Invalid (an
 *  Invalid node's picks are untrusted, its realizedTenths is the server's
 *  own) — else 0: absent, or malformed (snapshotted verbatim, so any
 *  realizedTenths on it was written by the client). */
export function baselineRealizedOf(raw: unknown): number {
  if (!isPlainMap(raw)) return 0;
  try {
    squadFromMap(raw);
  } catch {
    return 0;
  }
  return realizedOf(raw);
}

/** The FPL selling rule at a lock (see TRUSTED PRICES): the trusted price
 *  of every pick (same order as squad.picks) and the realizedTenths after
 *  this squad's sales, against [baseline] (null = no trusted picks: absent
 *  or Invalid — every pick NEW, nothing sold) and the realizedTenths
 *  [baselineRealized] it carries (derive it with baselineRealizedOf). */
export function judgeSale(
  squad: FantasySquad, market: Record<string, IntegrityMarketEntry>,
  baseline: FantasySquad | null, baselineRealized: number,
  previousWeekPrices: Record<string, number>,
): { prices: number[]; realizedTenths: number } {
  // What each baseline player was paid (a judged-valid baseline holds each
  // id once; a duplicated legacy row counts its dearest copy), never < 0.
  const paid = new Map<string, number>();
  for (const p of baseline?.picks ?? []) {
    paid.set(p.playerId, Math.max(paid.get(p.playerId) ?? 0, p.priceTenths));
  }
  const prices = squad.picks.map((p) => {
    const held = paid.get(p.playerId);
    if (held !== undefined) return held; // the client's price is ignored
    // NEW: the lowest price he could be BOUGHT at during this window.
    const m = market[p.playerId];
    let marketFloor = 0;
    if (m !== undefined) {
      const last = previousWeekPrices[p.playerId];
      marketFloor = last === undefined
        ? m.priceTenths : Math.min(m.priceTenths, last);
    }
    return Math.max(0, p.priceTenths, marketFloor);
  });
  const kept = new Set(squad.picks.map((p) => p.playerId));
  let realizedTenths = baselineRealized;
  for (const [id, bought] of paid) {
    if (kept.has(id)) continue;
    const m = market[id];
    // Gone from the market, or no usable price (a Players entry without a
    // price reads 0): adds 0 — never a "sale at 0" that books the full loss.
    if (m === undefined || m.priceTenths <= 0) continue;
    realizedTenths += sellPriceTenths(bought, m.priceTenths) - bought;
  }
  return { prices, realizedTenths };
}

/** The whole verdict on one squad. Pure. */
function lockVerdict(
  squad: FantasySquad, cfg: FantasyConfig,
  market: Record<string, IntegrityMarketEntry>,
  baseline: FantasySquad | null, baselineRealized: number,
  previousWeekPrices: Record<string, number>,
): LockVerdict {
  const found = new Set<SquadIntegrityIssue>();
  if (squad.picks.length > squadSize(cfg)) found.add('tooManyPlayers');
  const startersTotal = cfg.startersGk + cfg.startersDef + cfg.startersAtt;
  if (squadStarters(squad).length > startersTotal) found.add('tooManyStarters');

  const heldIds = new Set((baseline?.picks ?? []).map((p) => p.playerId));
  for (const p of squad.picks) {
    if (heldIds.has(p.playerId)) continue; // holders keep guests (spec §3)
    const m = market[p.playerId];
    if (m === undefined) found.add('unknownPlayer');
    else if (!m.eligible) found.add('ineligiblePlayer');
  }

  // Duplicates + budget through the engine's own validateSquad, run on the
  // squad re-priced at the trusted prices with the realized sale money
  // (formation/badCaptain ignored).
  const sale = judgeSale(
    squad, market, baseline, baselineRealized, previousWeekPrices);
  const repriced: FantasySquad = {
    ...squad,
    picks: squad.picks.map((p, i) => ({ ...p, priceTenths: sale.prices[i] })),
  };
  for (const issue of validateSquad(repriced, cfg, sale.realizedTenths)) {
    if (issue === 'duplicatePlayer' || issue === 'overBudget') found.add(issue);
  }
  return {
    issues: SQUAD_INTEGRITY_ISSUES.filter((i) => found.has(i)),
    prices: sale.prices,
    realizedTenths: sale.realizedTenths,
  };
}

/** The integrity issues for one squad ([] = valid) against a parsed
 *  [previous] baseline carrying [baselineRealized] (judgeSale's order).
 *  Pure. */
export function squadIntegrityIssues(
  squad: FantasySquad, cfg: FantasyConfig,
  market: Record<string, IntegrityMarketEntry>,
  previous: FantasySquad | null, baselineRealized: number,
  previousWeekPrices: Record<string, number>,
): SquadIntegrityIssue[] {
  return lockVerdict(squad, cfg, market, previous, baselineRealized,
    previousWeekPrices).issues;
}

/** The verdict for a raw squad node of [uid] against [inputs]; null when
 *  the node is not a parseable squad (malformed squads keep their existing
 *  handling: snapshotted verbatim, skipped by finalize). */
export function integrityVerdictOf(
  raw: unknown, uid: string, cfg: FantasyConfig, inputs: IntegrityInputs,
): LockVerdict | null {
  if (!isPlainMap(raw)) return null;
  let squad: FantasySquad;
  try {
    squad = squadFromMap(raw);
  } catch {
    return null;
  }
  return judgeSquad(squad, uid, cfg, inputs);
}

/** The verdict for [uid]'s parsed squad against [inputs]: its baseline is
 *  the RAW previousByUid[uid] node (baselineSquadOf for the trusted picks,
 *  baselineRealizedOf for the realized money it carries). */
export function judgeSquad(
  squad: FantasySquad, uid: string, cfg: FantasyConfig, inputs: IntegrityInputs,
): LockVerdict {
  const baselineRaw = inputs.previousByUid[uid];
  return lockVerdict(squad, cfg, inputs.market, baselineSquadOf(baselineRaw),
    baselineRealizedOf(baselineRaw), inputs.previousWeekPrices);
}

/** A parseable squad node's `picks` list re-priced at a verdict's [prices]:
 *  the k-th pick squadFromMap reads (it skips non-map entries) gets
 *  prices[k]; every other key of every pick, and any non-map entry, is
 *  kept as it was. */
export function picksAtJudgedPrices(
  rawPicks: unknown, prices: readonly number[],
): unknown {
  if (!Array.isArray(rawPicks)) return rawPicks;
  let k = 0;
  return rawPicks.map((p) => {
    if (p === null || typeof p !== 'object' || Array.isArray(p)) return p;
    return { ...(p as Record<string, unknown>), priceTenths: prices[k++] };
  });
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
