// The fan app's squad-draft money (lib/fantasy/hub/squad_draft.dart +
// lib/fantasy/engine/selling.dart; FPL selling, spec §4) for the S15
// rehearsal's synthetic clients (rehearse_s15.ts). Built from what the app
// itself reads — the manager's own Baselines/<uid>, today's market prices and
// PriceHistory/<gw − 1> — so a synthetic save is legal exactly when the app
// would let the fan save it, and the lock judge (squad_integrity.ts
// judgeSale) charges the same money:
//   - a baseline player kept (or re-added) costs his BASELINE price, whatever
//     the pick says (held = id); anyone else at least the market floor
//     min(today, last week): max(0, the pick's price, floor);
//   - a sold baseline player banks sellPriceTenths(paid, today) − paid into
//     the running realized total (no usable price today = adds 0);
//   - the room is budget + realized − spent.
// Error ≠ fact: a stale (ForGw ≠ the week being edited) or unreadable
// Baselines node is not [ClientDraftMoney.ready] — the app blocks Save then.
// Pure; unit-tested in client_draft_money.test.ts (incl. parity with the
// server judge).

import { FantasyConfig } from '../src/lib/fantasy/fantasy_config';
import { sellPriceTenths } from '../src/lib/fantasy/selling';
import {
  FantasySquad, SquadIssue, SquadPick, validateSquad,
} from '../src/lib/fantasy/squad';

/** selling.dart SaleBaseline: the server-written Baselines/<uid> node. */
export interface ClientSaleBaseline {
  /** The gameweek this baseline prices (the lock of forGw − 1 wrote it). */
  forGw: number;
  /** playerId -> the price PAID (the judge's settled price). */
  prices: Record<string, number>;
  /** The running sale profit/loss so far (may be negative). */
  realizedTenths: number;
}

function isMap(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function finiteInt(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : null;
}

/** selling.dart saleBaselineFromNode: null when not a map or ForGw is not a
 *  number; non-integer Prices values dropped; absent RealizedTenths = 0. */
export function clientSaleBaselineOf(node: unknown): ClientSaleBaseline | null {
  if (!isMap(node)) return null;
  const forGw = finiteInt(node['ForGw']);
  if (forGw === null) return null;
  const prices: Record<string, number> = {};
  const raw = node['Prices'];
  if (isMap(raw)) {
    for (const [id, v] of Object.entries(raw)) {
      if (typeof v === 'number' && Number.isInteger(v)) prices[id] = v;
    }
  }
  return { forGw, prices, realizedTenths: finiteInt(node['RealizedTenths']) ?? 0 };
}

/** What the app's SquadDraftController knows about money for one manager. */
export interface ClientDraftMoney {
  /** The parsed own Baselines/<uid> (null = none: a first squad). */
  readonly baseline: ClientSaleBaseline | null;
  /** squad_draft.dart moneyReady: the baseline is known (absent counts) and
   *  FOR the week being edited. False = the app blocks Save. */
  readonly ready: boolean;
  /** priceOfPick: what [p] costs the squad (the judge's price). */
  priceOfPick(p: SquadPick): number;
  /** realizedNowTenths over the owned [ids]: carried + every baseline
   *  player not owned, sold at today's price. */
  realizedFor(ids: Iterable<string>): number;
  /** buyPriceOf: the price ON a new pick (a baseline player comes back at
   *  his baseline price, anyone else at today's). */
  buyPrice(playerId: string): number;
  /** addCostOf: what adding [playerId] takes from the room when [ownedIds]
   *  are owned (he must not be one of them): today's price for a new
   *  player, what selling him banked for a sold baseline player. */
  addCost(playerId: string, ownedIds: readonly string[]): number;
  /** The engine's validateSquad at the draft's money: picks at
   *  [priceOfPick], budget + [realizedFor] of the squad's ids. */
  issues(s: FantasySquad, cfg: FantasyConfig): SquadIssue[];
}

/** The draft money for one manager editing gameweek [editingGw]:
 *  [baselineNode] = the raw own Baselines/<uid> (null = absent),
 *  [currentPrices] = today's market (Players/<name>/priceTenths),
 *  [lastWeekPrices] = PriceHistory/<editingGw − 1> (null = unknown — the
 *  floor is then today's price, as the server's is with no history). */
export function clientDraftMoney(args: {
  baselineNode: unknown;
  currentPrices: Readonly<Record<string, number>>;
  lastWeekPrices: Readonly<Record<string, number>> | null;
  editingGw: number;
}): ClientDraftMoney {
  const { currentPrices, lastWeekPrices, editingGw } = args;
  const absent = args.baselineNode === null || args.baselineNode === undefined;
  const baseline = absent ? null : clientSaleBaselineOf(args.baselineNode);
  // selling.dart saleBaselineStateFromNode: present but unreadable = degraded.
  const degraded = !absent && baseline === null;
  const ready = !degraded && (baseline === null || baseline.forGw === editingGw);
  const paidOf = (id: string): number | undefined =>
    baseline !== null && Object.prototype.hasOwnProperty.call(baseline.prices, id)
      ? baseline.prices[id] : undefined;
  const currentOf = (id: string): number | undefined =>
    Object.prototype.hasOwnProperty.call(currentPrices, id) ? currentPrices[id] : undefined;

  const priceOfPick = (p: SquadPick): number => {
    const held = paidOf(p.playerId);
    if (held !== undefined) return held;
    const current = currentOf(p.playerId);
    let floor = 0;
    if (current !== undefined) {
      const last = lastWeekPrices !== null &&
        Object.prototype.hasOwnProperty.call(lastWeekPrices, p.playerId)
        ? lastWeekPrices[p.playerId] : undefined;
      floor = last === undefined ? current : Math.min(current, last);
    }
    return Math.max(0, p.priceTenths, floor);
  };

  const realizedFor = (ids: Iterable<string>): number => {
    if (baseline === null) return 0;
    const kept = new Set(ids);
    let total = baseline.realizedTenths;
    for (const [id, paid] of Object.entries(baseline.prices)) {
      if (kept.has(id)) continue;
      const current = currentOf(id);
      if (current === undefined || current <= 0) continue;
      total += sellPriceTenths(paid, current) - paid;
    }
    return total;
  };

  const buyPrice = (playerId: string): number =>
    paidOf(playerId) ?? currentOf(playerId) ?? 0;

  return {
    baseline,
    ready,
    priceOfPick,
    realizedFor,
    buyPrice,
    addCost(playerId, ownedIds) {
      const charged = priceOfPick({
        playerId, position: 'GK', priceTenths: buyPrice(playerId), bench: false,
      });
      return charged + realizedFor(ownedIds) - realizedFor([...ownedIds, playerId]);
    },
    issues(s, cfg) {
      const repriced: FantasySquad = {
        ...s, picks: s.picks.map((p) => ({ ...p, priceTenths: priceOfPick(p) })),
      };
      return validateSquad(repriced, cfg, realizedFor(s.picks.map((p) => p.playerId)));
    },
  };
}
