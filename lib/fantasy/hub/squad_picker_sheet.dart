// The squad builder's two bottom sheets (P3b).
//
// showSquadPickerSheet: tap an empty slot (or Swap) → a position-filtered
// picker. Search, price-desc default sort with a name toggle, rows of
// avatar / name (wraps, never underlined) / team / price. Players already in
// the squad and ineligible guests never appear (squad_builder_logic
// .pickerCandidates); unaffordable players show DISABLED with their price in
// the error color.
//
// showSquadChipActions: tap a filled chip → Player profile / Make Captain /
// Make Vice-Captain / Swap / Remove. Bench chips offer only Player profile /
// Swap / Remove — a bench armband is impossible by construction, not by error
// message. "Player profile" (round 3) leads the list and is offered whenever
// the hub supplies an opener.
//
// The search sheet is a StatefulWidget owning its TextEditingController
// (house dialog-controller rule).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

/// [remainingTenths] is the shared draft's room for this pick (a swap: the
/// room after the outgoing player leaves) and [priceOf] what a candidate
/// takes from it (SquadDraftController.addCostOf) — the price each row
/// shows and is judged affordable by (FPL selling, spec §4). While
/// [moneyReady] is false (SquadDraftController.moneyReady) the header
/// claims no room ("— left"); the rows still use the draft's numbers.
Future<FantasyPlayer?> showSquadPickerSheet(
  BuildContext context, {
  required FantasyPosition position,
  required List<FantasyPlayer> players,
  required Set<String> excludeIds,
  required int remainingTenths,
  required int Function(FantasyPlayer player) priceOf,
  required bool moneyReady,
}) {
  return showModalBottomSheet<FantasyPlayer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(
      position: position,
      players: players,
      excludeIds: excludeIds,
      remainingTenths: remainingTenths,
      priceOf: priceOf,
      moneyReady: moneyReady,
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.position,
    required this.players,
    required this.excludeIds,
    required this.remainingTenths,
    required this.priceOf,
    required this.moneyReady,
  });

  final FantasyPosition position;
  final List<FantasyPlayer> players;
  final Set<String> excludeIds;
  final int remainingTenths;
  final int Function(FantasyPlayer player) priceOf;
  final bool moneyReady;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final TextEditingController _search = TextEditingController();
  bool _sortByPrice = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final candidates = pickerCandidates(
      players: widget.players,
      position: widget.position,
      excludeIds: widget.excludeIds,
      query: _search.text,
      sortByPrice: _sortByPrice,
      priceOf: widget.priceOf,
    );

    return Padding(
      // Rise above the keyboard while searching.
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pickerTitle(widget.position),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    widget.moneyReady
                        ? '${formatMoneyTenths(widget.remainingTenths)} left'
                        : '— left',
                    key: const ValueKey('picker_left'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: widget.moneyReady && widget.remainingTenths < 0
                          ? fantasyDownRed(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('picker_search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search players or teams',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    key: const ValueKey('picker_sort'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: true, label: Text('\$')),
                      ButtonSegment(value: false, label: Text('A–Z')),
                    ],
                    selected: {_sortByPrice},
                    onSelectionChanged: (s) =>
                        setState(() => _sortByPrice = s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: candidates.isEmpty
                  ? Center(
                      child: Text(
                        'No players match.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                          bottom:
                              16 + MediaQuery.paddingOf(context).bottom),
                      itemCount: candidates.length,
                      itemBuilder: (context, i) =>
                          _row(context, candidates[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, FantasyPlayer p) {
    final scheme = Theme.of(context).colorScheme;
    final price = widget.priceOf(p);
    final affordable = price <= widget.remainingTenths;
    return InkWell(
      key: ValueKey('picker_row_${p.name}'),
      onTap: affordable ? () => Navigator.of(context).pop(p) : null,
      child: Opacity(
        opacity: affordable ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Text(
                  initialsFor(p.name),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      // Wraps, never ellipsized or underlined (house rules).
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '${p.teamName} · ${p.position.db}',
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoneyTenths(price),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  // Unaffordable = the price itself carries the warning.
                  color: affordable ? scheme.onSurface : fantasyDownRed(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Actions available on a filled chip.
enum SquadChipAction { profile, makeCaptain, makeVice, swap, remove }

Future<SquadChipAction?> showSquadChipActions(
  BuildContext context, {
  required String playerName,
  required bool bench,
  bool isCaptain = false,
  bool isVice = false,
  bool showProfile = false,
}) {
  return showModalBottomSheet<SquadChipAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      final accent = fantasyAccent(sheetContext);
      ListTile tile(Key key, IconData icon, String label,
              SquadChipAction action, {Color? color}) =>
          ListTile(
            key: key,
            leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
            title: Text(label,
                style: TextStyle(color: color ?? scheme.onSurface)),
            onTap: () => Navigator.of(sheetContext).pop(action),
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                playerName,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            // Viewing a profile is always allowed — the first item (round 3).
            if (showProfile)
              tile(const ValueKey('action_profile'), Icons.person_outline,
                  'Player profile', SquadChipAction.profile),
            // Armbands are starter-only: bench chips simply never offer
            // them (spec §2 — the kind way to enforce the invariant).
            if (!bench && !isCaptain)
              tile(const ValueKey('action_make_captain'), Icons.copyright,
                  'Make Captain', SquadChipAction.makeCaptain,
                  color: accent),
            if (!bench && !isVice)
              tile(const ValueKey('action_make_vice'), Icons.verified_outlined,
                  'Make Vice-Captain', SquadChipAction.makeVice),
            tile(const ValueKey('action_swap'), Icons.swap_horiz, 'Swap',
                SquadChipAction.swap),
            tile(const ValueKey('action_remove'), Icons.person_remove_outlined,
                'Remove', SquadChipAction.remove,
                color: fantasyDownRed(context)),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}
