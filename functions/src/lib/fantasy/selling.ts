// The FPL selling rule (spec §4). Faithful twin of
// lib/fantasy/engine/selling.dart (sellPriceTenths). Money is integer TENTHS
// of $1M everywhere.
//
// Selling a player keeps half of any price rise (rounded down to $0.1M) and
// takes the full drop. The running profit/loss from sales (`realizedTenths`,
// may be negative) is added to the budget: spent <= budget + realizedTenths.

/** What a manager banks for a player bought at `purchaseTenths` when the
 *  market price is `currentTenths`: purchase + floor(rise / 2) on a rise,
 *  else the current price (the full drop is taken; an unchanged price
 *  sells for what was paid). */
export function sellPriceTenths(
  purchaseTenths: number, currentTenths: number,
): number {
  if (currentTenths > purchaseTenths) {
    // The rise is positive here, so floor == Dart's `~/`.
    return purchaseTenths + Math.floor((currentTenths - purchaseTenths) / 2);
  }
  return currentTenths;
}

/** The `realizedTenths` a server-written squad/baseline node carries: a
 *  finite number (truncated toward zero, Dart `.toInt()`), else 0. */
export function realizedOf(node: unknown): number {
  if (node === null || typeof node !== 'object') return 0;
  const v = (node as Record<string, unknown>)['realizedTenths'];
  if (typeof v !== 'number' || !Number.isFinite(v)) return 0;
  return Math.trunc(v);
}
