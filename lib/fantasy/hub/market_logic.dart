// Pure logic for the Players market tab (P3c; round 3 redesign, spec §5) —
// no Flutter imports, fully unit-tested (test/fantasy/market_logic_test.dart).
// The widgets in players_tab.dart / price_movers_card.dart stay thin over
// these helpers: search/position/watchlist filter + the four sorts (the tab
// holds the sort and its direction in a session cache), the sort-pill state
// rules, Price Risers / Fallers by position, and the add/remove availability
// rules the market control and the player profile's button both honor.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

/// The market's sorts, in the pill order (spec §5): Total Pts (the default
/// once finalized totals exist), Form, Price, Ownership. Each runs highest
/// first or lowest first; ties always read A–Z by name.
enum MarketSort { points, form, price, ownership }

/// Total Pts / Form / Ownership read `PlayerTotals`; without it (no
/// finalized gameweek yet) only Price means anything.
bool marketSortNeedsTotals(MarketSort sort) => sort != MarketSort.price;

/// The sort the market actually applies: the chosen one, except that a
/// totals-based sort reads Price, highest first, while totals are absent
/// (the chosen sort comes back by itself once they land).
({MarketSort sort, bool descending}) effectiveMarketSort(
  MarketSort chosen, {
  required bool descending,
  required bool hasTotals,
}) =>
    marketSortNeedsTotals(chosen) && !hasTotals
        ? (sort: MarketSort.price, descending: true)
        : (sort: chosen, descending: descending);

/// A sort pill tap: the active pill flips direction; any other pill becomes
/// the sort, highest first.
({MarketSort sort, bool descending}) tapMarketSort({
  required MarketSort current,
  required bool descending,
  required MarketSort tapped,
}) =>
    tapped == current
        ? (sort: current, descending: !descending)
        : (sort: tapped, descending: true);

/// A–Z by name, case-insensitive (exact case breaks a full tie so the order
/// is stable).
int _byName(FantasyPlayer a, FantasyPlayer b) {
  final byLower = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return byLower != 0 ? byLower : a.name.compareTo(b.name);
}

/// Search + position + watchlist filter + sort over the whole market.
/// Ineligible guests are NEVER dropped — they come back in their own list
/// (rendered last under the "Not eligible" divider, disabled) so the market
/// stays honest about who exists. Both partitions share the same sort.
///
/// [descending] = highest first. Ties read A–Z by name in BOTH directions.
/// Total Pts: a player missing from [totals] has 0. Form / Ownership: a
/// player with no value (absent, or an old-shape node) sorts LAST in both
/// directions — "no data" is never ranked as a 0.
/// [watchlistOnly] keeps only names in [watchlist] (the ★ chip).
({List<FantasyPlayer> eligible, List<FantasyPlayer> ineligible})
    composeMarket({
  required List<FantasyPlayer> players,
  String query = '',
  FantasyPosition? position,
  MarketSort sort = MarketSort.price,
  required bool descending,
  Map<String, FantasyPlayerTotals>? totals,
  Set<String> watchlist = const {},
  bool watchlistOnly = false,
}) {
  final q = query.trim().toLowerCase();
  bool matches(FantasyPlayer p) =>
      (position == null || p.position == position) &&
      (!watchlistOnly || watchlist.contains(p.name)) &&
      (q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.teamName.toLowerCase().contains(q));

  num? keyOf(FantasyPlayer p) => switch (sort) {
        MarketSort.points => totals?[p.name]?.points ?? 0,
        MarketSort.form => totals?[p.name]?.formTenths,
        MarketSort.price => p.priceTenths,
        MarketSort.ownership => totals?[p.name]?.ownershipPct,
      };

  int compare(FantasyPlayer a, FantasyPlayer b) {
    final ka = keyOf(a);
    final kb = keyOf(b);
    if (ka == null || kb == null) {
      if (ka == null && kb == null) return _byName(a, b);
      return ka == null ? 1 : -1; // no value → last, either direction
    }
    final byKey = descending ? kb.compareTo(ka) : ka.compareTo(kb);
    return byKey != 0 ? byKey : _byName(a, b);
  }

  final eligible = players.where((p) => p.eligible && matches(p)).toList()
    ..sort(compare);
  final ineligible = players.where((p) => !p.eligible && matches(p)).toList()
    ..sort(compare);
  return (eligible: eligible, ineligible: ineligible);
}

// ── Price Risers / Price Fallers (spec §5) ──────────────────────────────────

/// One player's move in the latest reprice.
class PriceMove {
  const PriceMove({
    required this.player,
    required this.deltaTenths,
    required this.seasonPoints,
  });

  final FantasyPlayer player;

  /// Signed move in $0.1M units (+5 = up $0.5M); never 0.
  final int deltaTenths;

  /// His season points (0 without totals) — the tie-breaker.
  final int seasonPoints;
}

/// The card's top movers, keyed by position code (`GK` / `DEF` / `ATT`, in
/// that order). Every requested position has a key, possibly with an empty
/// list.
class PriceMovers {
  const PriceMovers({required this.risers, required this.fallers});

  final Map<String, List<PriceMove>> risers;
  final Map<String, List<PriceMove>> fallers;

  /// Nothing moved in any requested position.
  bool get isEmpty =>
      risers.values.every((l) => l.isEmpty) &&
      fallers.values.every((l) => l.isEmpty);
}

/// How many risers and fallers the card shows per position.
const int kPriceMoversPerPosition = 2;

/// The latest reprice from the whole `PriceChanges` node
/// (`allPriceChangesFromNode`): the highest gameweek and its moves. null
/// before any reprice. A flag-only latest week (voided, nothing moved) is
/// still the latest — with no moves.
({int gameweek, Map<String, int> changes})? latestPriceMoves(
    Map<int, Map<String, int>> all) {
  if (all.isEmpty) return null;
  final gw = all.keys.reduce((a, b) => a > b ? a : b);
  return (gameweek: gw, changes: all[gw] ?? const {});
}

/// Every move of [latestChanges] for players still in the market (zero
/// moves and unknown names skipped): risers and fallers, each biggest move
/// first, ties by season points (high first) then name A–Z. The "View all"
/// sheet lists these.
({List<PriceMove> risers, List<PriceMove> fallers}) sortedPriceMoves(
  Map<String, int> latestChanges,
  List<FantasyPlayer> players,
  Map<String, FantasyPlayerTotals>? totals,
) {
  final byName = {for (final p in players) p.name: p};
  final risers = <PriceMove>[];
  final fallers = <PriceMove>[];
  latestChanges.forEach((name, delta) {
    final player = byName[name];
    if (player == null || delta == 0) return;
    final move = PriceMove(
      player: player,
      deltaTenths: delta,
      seasonPoints: totals?[name]?.points ?? 0,
    );
    (delta > 0 ? risers : fallers).add(move);
  });
  int compare(PriceMove a, PriceMove b) {
    final bySize = b.deltaTenths.abs().compareTo(a.deltaTenths.abs());
    if (bySize != 0) return bySize;
    final byPoints = b.seasonPoints.compareTo(a.seasonPoints);
    return byPoints != 0 ? byPoints : _byName(a.player, b.player);
  }

  risers.sort(compare);
  fallers.sort(compare);
  return (risers: risers, fallers: fallers);
}

/// The card's Price Risers / Price Fallers: top [kPriceMoversPerPosition]
/// of each per position (biggest move first, ties by season points then
/// name). [position] (`GK` / `DEF` / `ATT`) set → only that key; null (the
/// All chip) → all three.
PriceMovers computePriceMovers(
  Map<String, int> latestChanges,
  List<FantasyPlayer> players,
  Map<String, FantasyPlayerTotals>? totals, {
  String? position,
}) {
  final keys = position != null
      ? [position]
      : [for (final p in FantasyPosition.values) p.db];
  final all = sortedPriceMoves(latestChanges, players, totals);
  Map<String, List<PriceMove>> group(List<PriceMove> moves) => {
        for (final k in keys)
          k: moves
              .where((m) => m.player.position.db == k)
              .take(kPriceMoversPerPosition)
              .toList(),
      };
  return PriceMovers(risers: group(all.risers), fallers: group(all.fallers));
}

/// The movers card's short name: "Demsin Bet varda" → "D. Bet varda" (first
/// initial + the rest, spec §5 "short name"); a one-word name stays whole.
/// Still wraps where it's shown — never ellipsized.
String shortPlayerName(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.length < 2) return parts.isEmpty ? '' : parts.first;
  return '${parts.first[0]}. ${parts.skip(1).join(' ')}';
}

/// Why a market row's add control is enabled or not. Checked in priority
/// order: the lock silences everything; a drafted player offers Remove;
/// guests never add; then formation (no empty slot for the position), then
/// money.
enum MarketAddAvailability {
  /// Tap adds the player to the shared draft's first empty matching slot.
  addable,

  /// Already in the draft — the control is Remove instead.
  inSquad,

  /// Gameweek locked (or season over) — nothing edits.
  locked,

  /// Ineligible guest (spec §3) — never selectable.
  ineligible,

  /// Every slot of the player's position (starters + bench) is filled.
  positionFull,

  /// Price exceeds the draft's remaining budget.
  unaffordable,
}

/// The add/remove state for one market row against the current draft.
/// [unplaced] = the draft's "Needs a new spot" picks (still owned, still
/// paid for — a position change left them without a fitting slot).
///
/// Money (FPL selling, spec §4) is the draft's, never recomputed here:
/// [remainingTenths] is its room (SquadDraftController.remainingTenths —
/// budget + realized sales − spent at the charged prices) and [priceOf]
/// what adding a player takes from it (SquadDraftController.addCostOf).
MarketAddAvailability marketAddState({
  required FantasyPlayer player,
  required List<SquadSlot> slots,
  required List<SquadPick?> slotPicks,
  required int remainingTenths,
  required int Function(FantasyPlayer player) priceOf,
  required bool editable,
  List<SquadPick> unplaced = const [],
}) {
  if (!editable) return MarketAddAvailability.locked;
  for (final pick in [...slotPicks, ...unplaced]) {
    if (pick?.playerId == player.name) return MarketAddAvailability.inSquad;
  }
  if (!player.eligible) return MarketAddAvailability.ineligible;
  var hasEmptySlot = false;
  for (var i = 0; i < slots.length; i++) {
    if (slots[i].position == player.position && slotPicks[i] == null) {
      hasEmptySlot = true;
      break;
    }
  }
  if (!hasEmptySlot) return MarketAddAvailability.positionFull;
  if (priceOf(player) > remainingTenths) {
    return MarketAddAvailability.unaffordable;
  }
  return MarketAddAvailability.addable;
}

/// The owned baseline player's money line beside his Remove control (FPL
/// selling, spec §4): "Bought $8.0M · Sells for $8.5M".
String sellsForLine({required int boughtTenths, required int sellsTenths}) =>
    'Bought ${formatMoneyTenths(boughtTenths)} · '
    'Sells for ${formatMoneyTenths(sellsTenths)}';

/// The budget bar's realized line (FPL selling, spec §4): "Includes +$0.5M
/// from sales" / "Includes −$0.5M from sales" (true minus sign).
String realizedSalesLine(int realizedTenths) =>
    'Includes ${formatPriceDelta(realizedTenths)} from sales';

/// The tooltip-style sentence for a disabled add control; null when the
/// control is live (addable or Remove).
String? marketAddReason(
        MarketAddAvailability availability, FantasyPosition position) =>
    switch (availability) {
      MarketAddAvailability.locked => 'Gameweek locked — no changes now.',
      MarketAddAvailability.ineligible =>
        'Guest player — not eligible for fantasy.',
      MarketAddAvailability.positionFull =>
        '${position.db} slots are full — remove someone first.',
      MarketAddAvailability.unaffordable =>
        'Over budget — free up some money first.',
      MarketAddAvailability.addable || MarketAddAvailability.inSquad => null,
    };

/// Signed price-move text: "+$0.5M" / "−$0.5M" (true minus sign — callers
/// such as the News player card pair it with the ▲/▼ glyph and the up/down
/// color).
String formatPriceDelta(int deltaTenths) {
  final sign = deltaTenths < 0 ? '−' : '+';
  return '$sign\$${(deltaTenths.abs() / 10).toStringAsFixed(1)}M';
}
