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
// The STARTING total has one source with the fan app: Baselines/<uid>
// (baselineNodeOf, below) when it was written FOR the judged week (ForGw ===
// gw) — it carries the total through a week with no readable squad — else
// the previous squad node's own (baselineRealizedOf; see baselineRealizedFor).
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
// way, so the server's verdict equals the budget bar the manager saw AT
// THE SAVE. But prices keep moving until the lock, and the lock judges at
// ITS prices — two honest drifts can turn a saved, legal squad overBudget:
//   - SELL SIDE: a reprice (the Monday 10:00 job) or an owner price edit
//     between a sale and the lock LOWERS the sold player's credit (a faller
//     banks his whole drop at the lock's price; a riser who falls back
//     banks less of his rise), so a squad saved at the full budget is over;
//   - BUY SIDE (rare): an owner edit that RAISES a NEW pick above what the
//     manager paid earlier in the same window, by more than his remaining
//     budget (the market floor is min(now, last week), so only a player who
//     fell and was then pushed back above his old price).
// Neither is forgiven at the lock (FPL: the rule is the rule). Instead THE
// OVER-BUDGET PREVIEW (below) warns the fan before the deadline.
//
// THE OVER-BUDGET PREVIEW (spec §4, 2026-11-03): while the current
// gameweek is open, every lifecycle sweep (orchestration.ts sweepSeason
// step 3c, every 15 minutes) re-judges each saved squad with the NEXT
// lock's inputs (loadIntegrityInputs for the current gameweek). A verdict
// that includes overBudget gets SquadAlerts/<uid> = { Gw, Kind:'preview',
// Issues:['overBudget'], OverTenths, CreatedAt } (OverTenths =
// overBudgetTenthsOf; rewritten only when Gw or the amount moved) and ONE
// push per manager per gameweek (once-only claim PreviewPushed/<gw>/<uid>).
// The preview clears once the squad is no longer over: at the next sweep,
// on a clean save (the Squads trigger), or at the lock
// (settleIntegrityAlerts: an Invalid verdict replaces it, a clean one
// clears it). It only ever owns an empty slot or its own node: an Invalid
// alert (a judged week) and a position-change alert (actionable now) are
// never touched, and their manager gets no preview push while they stand.
// Squads whose issues do not include overBudget (forged ones) get neither
// alert nor push — overBudget is the one issue an honest fan can drift
// into.
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

/** SquadAlerts/<uid> Kind for the over-budget preview while the window is
 *  open (see THE OVER-BUDGET PREVIEW). */
export const PREVIEW_ALERT_KIND = 'preview';

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
  /** uid -> Baselines/<uid>.RealizedTenths, only for a node written FOR the
   *  gameweek being judged (ForGw === gw) — the one source of the running
   *  sale total the fan app shows. A uid absent here falls back to
   *  baselineRealizedOf(previousByUid[uid]) (see baselineRealizedFor). */
  baselineRealizedByUid?: Record<string, number>;
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

/** A squad node parsed (squadFromMap), or null when absent / malformed. */
function parseableSquadOf(raw: unknown): FantasySquad | null {
  if (!isPlainMap(raw)) return null;
  try {
    return squadFromMap(raw);
  } catch {
    return null;
  }
}

/** The previous locked squad as a price baseline: null when absent,
 *  unreadable, or itself judged Invalid (see TRUSTED PRICES). */
export function baselineSquadOf(raw: unknown): FantasySquad | null {
  return isInvalidRow(raw) ? null : parseableSquadOf(raw);
}

/** The realizedTenths a baseline node carries forward: realizedOf(raw) for
 *  a node the server judged — a parseable squad, Valid OR Invalid (an
 *  Invalid node's picks are untrusted, its realizedTenths is the server's
 *  own) — else 0: absent, or malformed (snapshotted verbatim, so any
 *  realizedTenths on it was written by the client). */
export function baselineRealizedOf(raw: unknown): number {
  return parseableSquadOf(raw) === null ? 0 : realizedOf(raw);
}

/** The realizedTenths the judge starts [uid] from (ONE source with the fan
 *  app): Baselines/<uid>.RealizedTenths when that node is for the judged
 *  gameweek (inputs.baselineRealizedByUid — orchestration.ts
 *  loadIntegrityInputs), else baselineRealizedOf(previousByUid[uid]). */
export function baselineRealizedFor(inputs: IntegrityInputs, uid: string): number {
  const fromBaselines = inputs.baselineRealizedByUid;
  if (fromBaselines !== undefined &&
    Object.prototype.hasOwnProperty.call(fromBaselines, uid)) {
    return fromBaselines[uid];
  }
  return baselineRealizedOf(inputs.previousByUid[uid]);
}

// ── Baselines/<uid> (FPL selling, spec §4) ─────────────────────────────────
//
// Fantasy/<sport>/<season>/Baselines/<uid> = { ForGw, RealizedTenths,
// Prices: { <playerId>: tenths } } — the manager's effective squad after the
// last lock (orchestration.ts effectiveSquadAfterWeek, Free Hit aware) as
// the fan app needs it: the prices this judge settled (a held player's
// price next week) and the running sale total. ForGw = the gameweek whose
// window it prices (lock of gw writes gw + 1). Server-written only
// (orchestration.ts publishSaleBaselines); the lock judge reads
// RealizedTenths back when ForGw is the week it judges, so the app and the
// server count the same money. Read by lib/fantasy/engine/selling.dart
// saleBaselineFromNode.
//
// THE PREV STASH ([M3], season setup + schedule plan 2026-11-05): the
// LOCK-time write also keeps the node it replaced as `Prev: { ForGw,
// RealizedTenths, Prices }` (lockTimePrevOf), so the sweep's rewind of a
// called-off week restores it EXACTLY (recomputing is lossy: a manager with
// no squad carries RealizedTenths from the stored node — baselineNodeOf).
// Finalize-time writes carry no Prev and drop a stored one (a scored week is
// never rewound). Every reader of Baselines reads named keys only, so Prev
// is invisible to them (baselineForGwOf / baselineRealizedTenthsOf here,
// selling.dart saleBaselineFromNode, tools/client_draft_money.ts).

/** A Baselines/<uid>/Prev stash: exactly the replaced node's three money
 *  fields — never its own Prev. */
export interface SaleBaselinePrev {
  ForGw: number;
  RealizedTenths: number;
  Prices: Record<string, number>;
}

/** One Baselines/<uid> node as the server writes it. */
export interface SaleBaselineNode {
  ForGw: number;
  RealizedTenths: number;
  Prices: Record<string, number>;
  /** Lock-time writes only: the node this one replaced (THE PREV STASH). */
  Prev?: SaleBaselinePrev;
}

/** A finite number truncated toward zero (Dart `.toInt()`), else null. */
function finiteIntOf(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : null;
}

/** A Baselines/<uid> node's ForGw; null when absent or not a number. */
export function baselineForGwOf(node: unknown): number | null {
  return isPlainMap(node) ? finiteIntOf(node['ForGw']) : null;
}

/** A Baselines/<uid> node's RealizedTenths (finite numbers only), else 0. */
export function baselineRealizedTenthsOf(node: unknown): number {
  return isPlainMap(node) ? finiteIntOf(node['RealizedTenths']) ?? 0 : 0;
}

/** RTDB keys may not be empty or contain . # $ [ ] / (a write with one
 *  fails whole). Market names are keys already (Players/<name>), so only a
 *  legacy/forged id could; it is left out of Prices. */
function isRtdbKey(id: string): boolean {
  return id.length > 0 && !/[.#$[\]/]/.test(id);
}

/** The Baselines/<uid> node for [effectiveRaw] (the manager's effective
 *  squad after the lock), FOR gameweek [forGw]:
 *  - a parseable node (valid OR Invalid — the server judged both):
 *    RealizedTenths = realizedOf(node); Prices = its picks' prices by id
 *    for a valid node (a duplicated legacy id keeps its dearest copy, as
 *    judgeSale), {} for an Invalid one (its prices were never judged);
 *  - absent or malformed (no squad at the lock, or a squad the server could
 *    not read — its realizedTenths would be the client's writing):
 *    RealizedTenths = [previousBaseline]'s (the stored Baselines/<uid>;
 *    none = 0), Prices {}. Carrying it means deleting or breaking a squad
 *    before a lock can never reset a negative running total. */
export function baselineNodeOf(
  effectiveRaw: unknown, forGw: number, previousBaseline?: unknown,
): SaleBaselineNode {
  const squad = parseableSquadOf(effectiveRaw);
  if (squad === null) {
    return {
      ForGw: forGw,
      RealizedTenths: baselineRealizedTenthsOf(previousBaseline),
      Prices: {},
    };
  }
  const prices: Record<string, number> = {};
  if (!isInvalidRow(effectiveRaw)) {
    for (const p of squad.picks) {
      if (!isRtdbKey(p.playerId)) continue;
      prices[p.playerId] = Math.max(prices[p.playerId] ?? 0, p.priceTenths);
    }
  }
  return { ForGw: forGw, RealizedTenths: realizedOf(effectiveRaw), Prices: prices };
}

/** [stored] as a Prev stash: its ForGw, RealizedTenths (absent/junk = 0,
 *  as every reader reads it) and its numeric Prices (RTDB-pruned = {});
 *  null when it is not a baseline (no numeric ForGw). Its own Prev is
 *  never carried. */
function baselineAsPrev(stored: unknown): SaleBaselinePrev | null {
  const forGw = baselineForGwOf(stored);
  if (forGw === null || !isPlainMap(stored)) return null;
  const prices: Record<string, number> = {};
  for (const [id, v] of childEntries(stored['Prices'])) {
    if (typeof v === 'number') prices[id] = v;
  }
  return {
    ForGw: forGw, RealizedTenths: baselineRealizedTenthsOf(stored), Prices: prices,
  };
}

/** The Prev a LOCK-time write of a node FOR gameweek [forGw] carries, given
 *  the [stored] node it replaces (THE PREV STASH):
 *  - stored FOR an earlier week -> that node itself (baselineAsPrev);
 *  - stored FOR [forGw] already (this lock wrote it before) -> the stash it
 *    already carries, kept — it still names the node before this lock;
 *  - no stored baseline, or one for a later week -> none (null). */
export function lockTimePrevOf(stored: unknown, forGw: number): SaleBaselinePrev | null {
  const storedFor = baselineForGwOf(stored);
  if (storedFor === null || !isPlainMap(stored)) return null;
  if (storedFor < forGw) return baselineAsPrev(stored);
  if (storedFor === forGw) return baselineAsPrev(stored['Prev']);
  return null;
}

/** Whether a stored Baselines/<uid> node already says exactly [node] (a
 *  rerun writes nothing). RTDB never stores an empty map, so a stored node
 *  without Prices equals Prices {}. Only the three money fields are
 *  compared; a stored Prev (THE PREV STASH) is ignored by a lock-time call
 *  ([opts.stashPrev]) and makes any other call rewrite (a finalize-time
 *  write drops it). */
export function sameBaselineNode(
  stored: unknown, node: SaleBaselineNode, opts: { stashPrev?: boolean } = {},
): boolean {
  if (!isPlainMap(stored)) return false;
  if (opts.stashPrev !== true && stored['Prev'] != null) return false;
  if (stored['ForGw'] !== node.ForGw ||
    stored['RealizedTenths'] !== node.RealizedTenths) {
    return false;
  }
  const have = childEntries(stored['Prices']);
  const want = Object.entries(node.Prices);
  if (have.length !== want.length) return false;
  const haveById = new Map(have);
  return want.every(([id, price]) => haveById.get(id) === price);
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
 *  the RAW previousByUid[uid] node (baselineSquadOf for the trusted picks)
 *  and the realized money baselineRealizedFor gives (Baselines/<uid> when
 *  it is for this week, else the previous node's own). */
export function judgeSquad(
  squad: FantasySquad, uid: string, cfg: FantasyConfig, inputs: IntegrityInputs,
): LockVerdict {
  return lockVerdict(squad, cfg, inputs.market,
    baselineSquadOf(inputs.previousByUid[uid]),
    baselineRealizedFor(inputs, uid), inputs.previousWeekPrices);
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

/** SquadAlerts/<uid> for the open window's over-budget warning (see THE
 *  OVER-BUDGET PREVIEW): [overTenths] = how far over, in tenths. */
export function previewAlertNode(
  gw: number, overTenths: number, nowMs: number,
): Record<string, unknown> {
  return {
    Gw: gw, Kind: PREVIEW_ALERT_KIND, Issues: ['overBudget'],
    OverTenths: overTenths, CreatedAt: nowMs,
  };
}

/** Whether a SquadAlerts/<uid> node is an integrity alert of either kind
 *  (Invalid or preview) — never a position-change alert (no Kind). */
export function isIntegrityAlert(node: unknown): boolean {
  return isPlainMap(node) && (node['Kind'] === INVALID_ALERT_KIND ||
    node['Kind'] === PREVIEW_ALERT_KIND);
}

/** Whether a SquadAlerts/<uid> node is the over-budget preview. */
export function isPreviewAlert(node: unknown): boolean {
  return isPlainMap(node) && node['Kind'] === PREVIEW_ALERT_KIND;
}

/** The alert's issue names, in stored order (a list or index-keyed map). */
function alertIssuesOf(node: Record<string, unknown>): unknown[] {
  return childEntries(node['Issues']).map(([, v]) => v);
}

/** Same Gw + same issues (CreatedAt aside) — a rerun rewrites nothing. Only
 *  an Invalid node matches: a preview for the same week and issue is a
 *  different alert, which the lock's Invalid verdict replaces. */
export function sameInvalidAlert(
  node: unknown, gw: number, issues: readonly SquadIntegrityIssue[],
): boolean {
  if (!isPlainMap(node) || node['Kind'] !== INVALID_ALERT_KIND) return false;
  const have = alertIssuesOf(node);
  return Number(node['Gw']) === gw && have.length === issues.length &&
    issues.every((i, k) => have[k] === i);
}

/** Same Gw + Issues ['overBudget'] + OverTenths (CreatedAt aside) — the
 *  next sweep rewrites nothing while the amount stands. */
export function samePreviewAlert(
  node: unknown, gw: number, overTenths: number,
): boolean {
  if (!isPreviewAlert(node)) return false;
  const m = node as Record<string, unknown>;
  const have = alertIssuesOf(m);
  return Number(m['Gw']) === gw && m['OverTenths'] === overTenths &&
    have.length === 1 && have[0] === 'overBudget';
}

/** How far a verdict's squad is over budget, in tenths: the judged spend
 *  (the sum of its trusted prices) - (Config.budgetTenths +
 *  realizedTenths). > 0 exactly when the verdict says overBudget. */
export function overBudgetTenthsOf(
  verdict: LockVerdict, cfg: FantasyConfig,
): number {
  const spent = verdict.prices.reduce((a, p) => a + p, 0);
  return spent - (cfg.budgetTenths + verdict.realizedTenths);
}
