// Transfers in the app (plan 2026-11-03, Task 3) — the pure transfer preview
// the squad builder's transfers line and the points-hit confirm read: one
// test per rule of transferPreview (in rule order), the copy asserted
// verbatim, and the TransferState parser round trip. The same counting
// rule is cross-checked against the server's own functions in
// functions/tools/transfer_preview_parity.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_dialogs.dart';
import 'package:infinite_sports_flutter/fantasy/hub/transfer_preview.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault(); // 2 free per week, 4 pts each

  // The squad the manager came into gameweek 5 with.
  const baseline = ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7'];

  /// The baseline with its first [n] players swapped for newcomers.
  List<String> swapped(int n) =>
      [for (var i = 0; i < baseline.length; i++) i < n ? 'N$i' : baseline[i]];

  TransferStateView state({
    int? free = 2,
    int? countFromGw = 5,
    List<String>? countFrom = baseline,
    int? freeSwapsGw,
    List<String> freeSwaps = const [],
  }) =>
      TransferStateView(
        free: free,
        countFromGw: countFromGw,
        countFrom: countFrom,
        freeSwapsGw: freeSwapsGw,
        freeSwaps: freeSwaps,
      );

  TransferPreview preview(
    List<String> draft, {
    TransferStateView? s,
    bool useState = true,
    bool answered = true,
    int? editingGw = 5,
    String? chip,
  }) =>
      transferPreview(
        draftIds: draft,
        state: useState ? (s ?? state()) : null,
        answered: answered,
        editingGw: editingGw,
        chip: chip,
        cfg: cfg,
      );

  group('transferPreview rules, in order', () {
    test(
        'not answered yet (or the read failed) → notReady, whatever the '
        'node says — never a first team', () {
      expect(preview(baseline, answered: false).kind,
          TransferPreviewKind.notReady);
      expect(preview(baseline, useState: false, answered: false).kind,
          TransferPreviewKind.notReady);
    });

    test('absent node → firstTeam', () {
      final p = preview(baseline, useState: false);
      expect(p.kind, TransferPreviewKind.firstTeam);
      expect(p.costPoints, 0);
      expect(transferLineText(p),
          'Your first team is free — change anything until the deadline.');
    });

    test('absent node is a first team even before the week is known', () {
      expect(preview(baseline, useState: false, editingGw: null).kind,
          TransferPreviewKind.firstTeam);
    });

    test('node without countFromGw (pre-feature) → hidden, no line', () {
      final p = preview(swapped(4), s: state(countFromGw: null));
      expect(p.kind, TransferPreviewKind.hidden);
      expect(p.costPoints, 0);
      expect(transferLineText(p), isNull);
    });

    test('a hidden node stays hidden whatever the week or chip', () {
      expect(
          preview(baseline,
                  s: state(countFromGw: null),
                  editingGw: null,
                  chip: 'wildcard')
              .kind,
          TransferPreviewKind.hidden);
    });

    test('stale countFromGw → notReady', () {
      final p = preview(swapped(3), s: state(countFromGw: 4));
      expect(p.kind, TransferPreviewKind.notReady);
      expect(transferLineText(p), 'Transfer count updating…');
      // A baseline for a LATER week is just as unusable.
      expect(preview(swapped(3), s: state(countFromGw: 6)).kind,
          TransferPreviewKind.notReady);
    });

    test('editingGw null → notReady', () {
      expect(preview(swapped(3), editingGw: null).kind,
          TransferPreviewKind.notReady);
    });

    test('countFromGw present, no countFrom → firstTeam', () {
      final p = preview(swapped(7), s: state(countFrom: null));
      expect(p.kind, TransferPreviewKind.firstTeam);
      expect(p.costPoints, 0);
    });

    test('Wildcard → unlimited, cost 0, however many transfers', () {
      final p = preview(swapped(7), chip: 'wildcard');
      expect(p.kind, TransferPreviewKind.unlimited);
      expect(p.costPoints, 0);
      expect(transferLineText(p),
          'Wildcard on — every transfer is free this week.');
    });

    test('Free Hit → unlimited, cost 0', () {
      final p = preview(swapped(6), chip: 'freeHit');
      expect(p.kind, TransferPreviewKind.unlimited);
      expect(p.costPoints, 0);
      expect(
          transferLineText(p),
          'Free Hit on — every transfer is free, and your team comes back '
          'after this week.');
    });

    test('the other chips do not lift the count', () {
      expect(preview(swapped(4), chip: 'tripleCaptain').kind,
          TransferPreviewKind.counted);
      expect(preview(swapped(4), chip: 'benchBoost').costPoints, 8);
    });
  });

  group('counted: used vs free', () {
    test('a one-point hit (a 1-point transfer cost) reads "−1 pt"', () {
      const p = TransferPreview(
          kind: TransferPreviewKind.counted, used: 3, free: 2, costPoints: 1);
      expect(transferLineText(p), '3 transfers · 2 free · −1 pt this week');
      expect(pointsHitSaveLabel(p), 'Save (−1 pt)');
    });

    test('no changes: 0 of 2 free transfers used', () {
      final p = preview(baseline);
      expect(p.kind, TransferPreviewKind.counted);
      expect((p.used, p.free, p.costPoints), (0, 2, 0));
      expect(transferLineText(p), '0 of 2 free transfers used');
    });

    test('1 of 2 used, no cost', () {
      final p = preview(swapped(1));
      expect((p.used, p.free, p.costPoints), (1, 2, 0));
      expect(transferLineText(p), '1 of 2 free transfers used');
    });

    test('all free ones used is still no cost', () {
      final p = preview(swapped(2));
      expect(p.costPoints, 0);
      expect(transferLineText(p), '2 of 2 free transfers used');
    });

    test('3 used with 2 free → cost 4', () {
      final p = preview(swapped(3));
      expect((p.used, p.free, p.costPoints), (3, 2, 4));
      expect(transferLineText(p), '3 transfers · 2 free · −4 pts this week');
    });

    test('4 used with 2 free → cost 8', () {
      final p = preview(swapped(4));
      expect(p.costPoints, 8);
      expect(transferLineText(p), '4 transfers · 2 free · −8 pts this week');
    });

    test('one free transfer: singular copy', () {
      final p = preview(swapped(1), s: state(free: 1));
      expect(transferLineText(p), '1 of 1 free transfer used');
      expect(transferLineText(preview(swapped(2), s: state(free: 1))),
          '2 transfers · 1 free · −4 pts this week');
    });

    test('a single transfer over zero free says "transfer"', () {
      final p = preview(swapped(1), s: state(free: 0));
      expect(p.costPoints, 4);
      expect(transferLineText(p), '1 transfer · 0 free · −4 pts this week');
    });

    test('Free absent from the node → the config\'s weekly allowance', () {
      final p = preview(swapped(1), s: state(free: null));
      expect(p.free, cfg.freeTransfersPerWeek);
      expect(transferLineText(p), '1 of 2 free transfers used');
    });

    test('banked transfers: free 4, 3 used → no cost', () {
      final p = preview(swapped(3), s: state(free: 4));
      expect((p.used, p.free, p.costPoints), (3, 4, 0));
    });

    test('reordering the same players is free', () {
      expect(preview(baseline.reversed.toList()).used, 0);
    });

    test('the cost follows the config\'s per-transfer price', () {
      final dear =
          FantasyConfig.fromMap({...cfg.toMap(), 'extraTransferCost': 6});
      final p = transferPreview(
          draftIds: swapped(4),
          state: state(),
          answered: true,
          editingGw: 5,
          chip: null,
          cfg: dear);
      expect(p.costPoints, 12);
    });
  });

  group('free swaps (holder protection, same as usedAfterFreeSwaps)', () {
    test('a free-swap player sold this week is not counted', () {
      // A1 (free swap) out, N0 in: 1 raw transfer, 0 counted.
      final s = state(freeSwapsGw: 5, freeSwaps: ['A1']);
      final p = preview(swapped(1), s: s);
      expect(p.used, 0);
      expect(transferLineText(p), '0 of 2 free transfers used');
    });

    test('only the swap\'s player is discounted: 3 sold, 1 free swap → 2', () {
      final s = state(freeSwapsGw: 5, freeSwaps: ['A1']);
      expect(preview(swapped(3), s: s).used, 2);
    });

    test('a free swap from ANOTHER week is counted', () {
      final s = state(freeSwapsGw: 4, freeSwaps: ['A1']);
      expect(preview(swapped(1), s: s).used, 1);
    });

    test('a free-swap player still in the squad discounts nothing', () {
      final s = state(freeSwapsGw: 5, freeSwaps: ['A7']);
      expect(preview(swapped(1), s: s).used, 1);
    });

    test('a free-swap player not in the baseline discounts nothing', () {
      final s = state(freeSwapsGw: 5, freeSwaps: ['Ghost']);
      expect(preview(swapped(1), s: s).used, 1);
    });

    test('never below zero', () {
      final s = state(freeSwapsGw: 5, freeSwaps: ['A1', 'A2']);
      expect(preview(swapped(1), s: s).used, 0);
    });
  });

  group('copy', () {
    test('notReady / hidden / firstTeam have fixed lines (hidden: none)', () {
      expect(
          transferLineText(
              const TransferPreview(kind: TransferPreviewKind.notReady)),
          'Transfer count updating…');
      expect(
          transferLineText(
              const TransferPreview(kind: TransferPreviewKind.hidden)),
          isNull);
      expect(
          transferLineText(
              const TransferPreview(kind: TransferPreviewKind.firstTeam)),
          'Your first team is free — change anything until the deadline.');
    });
  });

  group('parseTransferState round trip', () {
    test('a full node → the view the preview counts with', () {
      final v = parseTransferState({
        'Free': 3,
        'UsedThisGw': 1,
        'CountFromGw': 5,
        'CountFrom': baseline,
        'FreeSwapsGw': 5,
        'FreeSwaps': ['A1'],
      })!;
      expect(v.free, 3);
      expect(v.usedThisGw, 1);
      expect(v.countFromGw, 5);
      expect(v.countFrom, baseline);
      expect(v.freeSwapsGw, 5);
      expect(v.freeSwaps, ['A1']);
      // 3 sold, one of them (A1) a free swap: 2 counted.
      final p = preview(swapped(3), s: v);
      expect((p.used, p.free, p.costPoints), (2, 3, 0));
    });

    test('an absent node is null, and previews as a first team', () {
      final v = parseTransferState(null);
      expect(v, isNull);
      expect(
          transferPreview(
                  draftIds: baseline,
                  state: v,
                  answered: true,
                  editingGw: 5,
                  chip: null,
                  cfg: cfg)
              .kind,
          TransferPreviewKind.firstTeam);
    });
  });
}
