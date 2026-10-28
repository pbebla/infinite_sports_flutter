// Pure logic for the Players market tab (P3c) — no Flutter imports, fully
// unit-tested (test/fantasy/market_logic_test.dart). The widgets in
// players_tab.dart / market_player_sheet.dart stay thin over these helpers:
// search/filter/sort composition (sort PERSISTS across filter changes — the
// tab holds it in a session cache) and the add/remove availability rules the
// market control and the detail sheet's buy button both honor.

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

/// The market's sort orders. Price is the default; Points exists only while
/// finalized totals exist (the tab falls back to price when they vanish).
enum MarketSort { priceDesc, pointsDesc, nameAz }

/// Search + position filter + sort over the whole market. Ineligible guests
/// are NEVER dropped — they come back in their own list (rendered last under
/// the "Not eligible" divider, disabled) so the market stays honest about
/// who exists. Both partitions share the same sort.
({List<FantasyPlayer> eligible, List<FantasyPlayer> ineligible})
    composeMarket({
  required List<FantasyPlayer> players,
  String query = '',
  FantasyPosition? position,
  MarketSort sort = MarketSort.priceDesc,
  Map<String, FantasyPlayerTotals>? totals,
}) {
  final q = query.trim().toLowerCase();
  bool matches(FantasyPlayer p) =>
      (position == null || p.position == position) &&
      (q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.teamName.toLowerCase().contains(q));

  int compare(FantasyPlayer a, FantasyPlayer b) {
    switch (sort) {
      case MarketSort.priceDesc:
        final byPrice = b.priceTenths.compareTo(a.priceTenths);
        return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
      case MarketSort.pointsDesc:
        final byPoints = (totals?[b.name]?.points ?? 0)
            .compareTo(totals?[a.name]?.points ?? 0);
        if (byPoints != 0) return byPoints;
        final byPrice = b.priceTenths.compareTo(a.priceTenths);
        return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
      case MarketSort.nameAz:
        final byName =
            a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.name.compareTo(b.name);
    }
  }

  final eligible = players.where((p) => p.eligible && matches(p)).toList()
    ..sort(compare);
  final ineligible = players.where((p) => !p.eligible && matches(p)).toList()
    ..sort(compare);
  return (eligible: eligible, ineligible: ineligible);
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
MarketAddAvailability marketAddState({
  required FantasyPlayer player,
  required List<SquadSlot> slots,
  required List<SquadPick?> slotPicks,
  required int budgetTenths,
  required bool editable,
}) {
  if (!editable) return MarketAddAvailability.locked;
  for (final pick in slotPicks) {
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
  final remaining = budgetTenths - draftSpentTenths(slotPicks);
  if (player.priceTenths > remaining) {
    return MarketAddAvailability.unaffordable;
  }
  return MarketAddAvailability.addable;
}

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

/// Risers & fallers chip text: "+$0.5M" / "−$0.5M" (true minus sign — the
/// strip pairs it with the ▲/▼ glyph and the up/down color).
String formatPriceDelta(int deltaTenths) {
  final sign = deltaTenths < 0 ? '−' : '+';
  return '$sign\$${(deltaTenths.abs() / 10).toStringAsFixed(1)}M';
}
