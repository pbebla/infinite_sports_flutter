// The FPL selling rule (spec §4). Faithful twin of
// functions/src/lib/fantasy/selling.ts (sellPriceTenths). Money is integer
// TENTHS of $1M everywhere.
//
// Selling a player keeps half of any price rise (rounded down to $0.1M) and
// takes the full drop. The running profit/loss from sales (`realizedTenths`,
// may be negative) is added to the budget: spent <= budget + realizedTenths.

/// What a manager banks for a player bought at [purchaseTenths] when the market
/// price is [currentTenths]: purchase + floor(rise / 2) on a rise, else the
/// current price (the full drop is taken; an unchanged price sells for what
/// was paid).
int sellPriceTenths({required int purchaseTenths, required int currentTenths}) {
  if (currentTenths > purchaseTenths) {
    // The rise is positive here, so `~/` floors.
    return purchaseTenths + (currentTenths - purchaseTenths) ~/ 2;
  }
  return currentTenths;
}

/// The server-written `Baselines/<uid>` node: last week's locked prices and
/// the running total of realized profit/loss, so the squad builder can show the
/// same money the server will charge.
class SaleBaseline {
  const SaleBaseline({
    required this.forGw,
    required this.prices,
    required this.realizedTenths,
  });

  /// The gameweek this baseline is FOR (the week whose window it prices).
  final int forGw;

  /// playerId -> price in the baseline squad (the price PAID).
  final Map<String, int> prices;

  /// Running profit/loss from sales so far; may be negative.
  final int realizedTenths;
}

/// Parses a `Baselines/<uid>` node. Null when it is not a map or `ForGw` is
/// missing; non-int `Prices` values are dropped; an absent `RealizedTenths`
/// is 0.
SaleBaseline? saleBaselineFromNode(Object? node) {
  if (node is! Map) return null;
  final forGw = node['ForGw'];
  if (forGw is! num) return null;
  final prices = <String, int>{};
  final rawPrices = node['Prices'];
  if (rawPrices is Map) {
    rawPrices.forEach((k, v) {
      if (v is int) prices[k.toString()] = v;
    });
  }
  final realized = node['RealizedTenths'];
  return SaleBaseline(
    forGw: forGw.toInt(),
    prices: prices,
    realizedTenths: realized is num ? realized.toInt() : 0,
  );
}

/// The realized profit/loss the server will book if this squad locks now:
/// the carried [SaleBaseline.realizedTenths] plus, for every baseline player
/// NOT in [squadIds], the sale at the current price minus the price paid.
/// A sold player missing from [currentPrices] adds 0. Null baseline -> 0.
int realizedNowTenths(
  SaleBaseline? b,
  Iterable<String> squadIds,
  Map<String, int> currentPrices,
) {
  if (b == null) return 0;
  final kept = squadIds.toSet();
  var total = b.realizedTenths;
  b.prices.forEach((id, paid) {
    if (kept.contains(id)) return;
    final current = currentPrices[id] ?? paid;
    total +=
        sellPriceTenths(purchaseTenths: paid, currentTenths: current) - paid;
  });
  return total;
}

/// What a player costs the squad builder: a baseline player is HELD (or
/// re-added) at his baseline price whatever the market says; anyone else is
/// bought at the current price.
int buyPriceTenths(SaleBaseline? b, String playerId, int currentTenths) =>
    b?.prices[playerId] ?? currentTenths;
