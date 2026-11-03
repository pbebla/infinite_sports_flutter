// The transfer preview (plan 2026-11-03, spec §5) — what the squad builder's
// transfers line and the "Take a points hit?" confirm tell a manager about
// the team in the draft: how many transfers it uses against the squad he
// came into the week with, and what that costs. Pure (no Flutter, no
// Firebase), unit-tested in test/fantasy/transfer_preview_test.dart.
//
// The counting rule is the server's, restated: the lock (and every save,
// recordSquadSave) counts the players in the new squad that were not in the
// previous locked squad, minus the holder-protection free swaps sold this
// week (transfer_state.ts usedAfterFreeSwaps), and charges
// max(0, used − free) × extraTransferCost, nothing in a Wildcard / Free Hit
// week (transfers.ts transferCost). The "previous locked squad" arrives as
// the published baseline (`TransferState.CountFrom`, for `CountFromGw`), so
// the app's counter and the server's recount cannot disagree.
// functions/tools/transfer_preview_parity.test.ts pins the two together.
//
// Error ≠ fact: the preview says "a first team" only when the node is
// KNOWN absent (`answered` and a null state), or the baseline publishes "no
// squad to count from". Before the feed has answered, or after it failed,
// it is [TransferPreviewKind.notReady] — never a free first team that
// would hide a real cost.

import 'dart:math';

import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/transfers.dart';

enum TransferPreviewKind {
  /// No squad to count from: building it is free until the deadline.
  firstTeam,

  /// A Wildcard / Free Hit week: every transfer is free.
  unlimited,

  /// Counted against the baseline: [TransferPreview.used] of
  /// [TransferPreview.free], a [TransferPreview.costPoints] hit past them.
  counted,

  /// Not knowable right now (feed not answered / failed, the baseline is
  /// for another week, the week is unknown): the line says "updating" and
  /// nothing is claimed or confirmed.
  notReady,

  /// An older node with no published baseline: no line at all.
  hidden,
}

class TransferPreview {
  const TransferPreview({
    required this.kind,
    this.used = 0,
    this.free = 0,
    this.costPoints = 0,
    this.chip,
  });

  final TransferPreviewKind kind;

  /// [TransferPreviewKind.counted] only: transfers the draft uses (after
  /// free swaps).
  final int used;

  /// [TransferPreviewKind.counted] only: the free transfers available.
  final int free;

  /// The points this week's transfers cost (0 unless counted past free).
  final int costPoints;

  /// [TransferPreviewKind.unlimited] only: which chip lifted the count
  /// (`wildcard` / `freeHit`) — the line names it.
  final String? chip;

  @override
  bool operator ==(Object other) =>
      other is TransferPreview &&
      other.kind == kind &&
      other.used == used &&
      other.free == free &&
      other.costPoints == costPoints &&
      other.chip == chip;

  @override
  int get hashCode => Object.hash(kind, used, free, costPoints, chip);

  @override
  String toString() => 'TransferPreview($kind, used: $used, free: $free, '
      'cost: $costPoints, chip: $chip)';
}

/// What the draft [draftIds] (every owned player id) costs in transfers.
///
/// [state] is the `TransferState/<uid>` view — null = the node is ABSENT —
/// and [answered] says the feed has really answered (false before its first
/// emission and after it failed). [editingGw] is the gameweek being edited
/// (`saleEditingGameweek`); [chip] the draft's chip.
///
/// Rules, in order:
/// 1. not [answered] → notReady;
/// 2. absent node → firstTeam;
/// 3. node without `CountFromGw` (an older node) → hidden;
/// 4. [editingGw] unknown, or not the baseline's week → notReady;
/// 5. baseline without ids (a first team) → firstTeam;
/// 6. Wildcard / Free Hit → unlimited, cost 0;
/// 7. otherwise counted: used = draft ids not in the baseline, minus the
///    free-swap players sold (only when the swaps are for [editingGw]),
///    free = the node's `Free` (the config's weekly allowance when the
///    field is absent), cost = [transferCost].
TransferPreview transferPreview({
  required List<String> draftIds,
  required TransferStateView? state,
  required bool answered,
  required int? editingGw,
  required String? chip,
  required FantasyConfig cfg,
}) {
  if (!answered) {
    return const TransferPreview(kind: TransferPreviewKind.notReady);
  }
  if (state == null) {
    return const TransferPreview(kind: TransferPreviewKind.firstTeam);
  }
  final countFromGw = state.countFromGw;
  if (countFromGw == null) {
    return const TransferPreview(kind: TransferPreviewKind.hidden);
  }
  if (editingGw == null || countFromGw != editingGw) {
    return const TransferPreview(kind: TransferPreviewKind.notReady);
  }
  final countFrom = state.countFrom;
  if (countFrom == null) {
    return const TransferPreview(kind: TransferPreviewKind.firstTeam);
  }
  if (chip == 'wildcard' || chip == 'freeHit') {
    return TransferPreview(kind: TransferPreviewKind.unlimited, chip: chip);
  }
  final before = countFrom.toSet();
  final now = draftIds.toSet();
  var used = draftIds.where((id) => !before.contains(id)).length;
  if (state.freeSwapsGw == editingGw) {
    final sold = state.freeSwaps
        .where((p) => before.contains(p) && !now.contains(p))
        .length;
    used = max(0, used - sold);
  }
  final free = state.free ?? cfg.freeTransfersPerWeek;
  return TransferPreview(
    kind: TransferPreviewKind.counted,
    used: used,
    free: free,
    costPoints: transferCost(used: used, free: free, cfg: cfg),
  );
}

/// The one line the squad builder shows under the budget bar; null = no
/// line ([TransferPreviewKind.hidden]).
String? transferLineText(TransferPreview p) {
  switch (p.kind) {
    case TransferPreviewKind.firstTeam:
      return 'Your first team is free — change anything until the deadline.';
    case TransferPreviewKind.unlimited:
      return p.chip == 'freeHit'
          ? 'Free Hit on — every transfer is free, and your team comes back '
              'after this week.'
          : 'Wildcard on — every transfer is free this week.';
    case TransferPreviewKind.counted:
      if (p.costPoints > 0) {
        return '${p.used} ${p.used == 1 ? 'transfer' : 'transfers'} · '
            '${p.free} free · −${p.costPoints} pts this week';
      }
      return '${p.used} of ${p.free} free '
          '${p.free == 1 ? 'transfer' : 'transfers'} used';
    case TransferPreviewKind.notReady:
      return 'Transfer count updating…';
    case TransferPreviewKind.hidden:
      return null;
  }
}
