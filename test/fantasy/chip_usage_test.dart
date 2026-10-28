// Chip availability counts (owner feedback round): the pure rule behind the
// My Team chip row's "1 left" / "Used" / "Active" badges — server parity
// with transfer_state.ts priorChipsOfUid + shouldVoidChip (spent = played
// in an EARLIER gameweek of the same set; voided weeks refund).

import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';

void main() {
  final cfg = FantasyConfig.futsalDefault(); // chipSet1EndGw = 6

  Map<String, ChipAvailability> avail(Map<int, ChipHistoryEntry> history,
          {required int editingGw, String? armed}) =>
      chipAvailability(
        historyByWeek: history,
        editingGw: editingGw,
        armedChip: armed,
        config: cfg,
      );

  group('chipHistoryEntryFromNode', () {
    test('reads chip + Voided:true; absent/non-map = null', () {
      expect(chipHistoryEntryFromNode(null), isNull);
      expect(chipHistoryEntryFromNode('x'), isNull);
      expect(
        chipHistoryEntryFromNode({
          'picks': [],
          'chip': 'benchBoost',
          'TotalTenths': 420,
        }),
        const ChipHistoryEntry(chip: 'benchBoost'),
      );
      expect(
        chipHistoryEntryFromNode({'chip': 'tripleCaptain', 'Voided': true}),
        const ChipHistoryEntry(chip: 'tripleCaptain', voided: true),
      );
      // Only a literal true voids; an empty chip is no chip.
      expect(chipHistoryEntryFromNode({'chip': '', 'Voided': 'true'}),
          const ChipHistoryEntry());
    });
  });

  group('chipEditingGameweek', () {
    final gws = [
      for (var n = 1; n <= 3; n++)
        Gameweek(
          number: n,
          date: '0${n}012026',
          lockUtc: DateTime.utc(2026, n, 1, 22),
          opensUtc: null,
        ),
    ];

    test('the first gameweek whose lock is still ahead', () {
      expect(chipEditingGameweek(gws, DateTime.utc(2026, 1, 1, 21)), 1);
      expect(chipEditingGameweek(gws, DateTime.utc(2026, 1, 1, 22)), 2);
      expect(chipEditingGameweek(gws, DateTime.utc(2026, 2, 15)), 3);
    });

    test('season over -> one past the last; empty schedule -> 1', () {
      expect(chipEditingGameweek(gws, DateTime.utc(2026, 4, 1)), 4);
      expect(chipEditingGameweek(const [], DateTime.utc(2026, 4, 1)), 1);
    });
  });

  group('chipAvailability', () {
    test('no history: every chip "1 left"', () {
      final a = avail({}, editingGw: 3);
      expect(a.keys, fantasyChipIds);
      expect(a.values.toSet(), {ChipAvailability.available});
    });

    test('used earlier in the SAME set -> Used; others still 1 left', () {
      final a = avail({2: const ChipHistoryEntry(chip: 'tripleCaptain')},
          editingGw: 4);
      expect(a['tripleCaptain'], ChipAvailability.used);
      expect(a['benchBoost'], ChipAvailability.available);
      expect(a['wildcard'], ChipAvailability.available);
      expect(a['freeHit'], ChipAvailability.available);
    });

    test('set 2 starts fresh: a set-1 chip is "1 left" again; set-2 usage '
        'counts', () {
      final history = {
        2: const ChipHistoryEntry(chip: 'tripleCaptain'),
        6: const ChipHistoryEntry(chip: 'benchBoost'), // last set-1 week
        7: const ChipHistoryEntry(chip: 'wildcard'), // first set-2 week
      };
      final a = avail(history, editingGw: 8);
      expect(a['tripleCaptain'], ChipAvailability.available);
      expect(a['benchBoost'], ChipAvailability.available);
      expect(a['wildcard'], ChipAvailability.used);
      // Still in set 1 (editing GW6): BB is not spent yet (GW6 is not
      // EARLIER than the edited week), TC is.
      final s1 = avail(history, editingGw: 6);
      expect(s1['tripleCaptain'], ChipAvailability.used);
      expect(s1['benchBoost'], ChipAvailability.available);
    });

    test('a voided week refunds its chip (server Voided rule)', () {
      final a = avail(
          {2: const ChipHistoryEntry(chip: 'tripleCaptain', voided: true)},
          editingGw: 4);
      expect(a['tripleCaptain'], ChipAvailability.available);
    });

    test('armed chip -> Active; a spent chip stays Used even when re-armed '
        '(the server voids that replay)', () {
      expect(avail({}, editingGw: 3, armed: 'benchBoost')['benchBoost'],
          ChipAvailability.active);
      final a = avail({1: const ChipHistoryEntry(chip: 'benchBoost')},
          editingGw: 3, armed: 'benchBoost');
      expect(a['benchBoost'], ChipAvailability.used);
    });

    test('labels', () {
      expect(chipAvailabilityLabel(ChipAvailability.available), '1 left');
      expect(chipAvailabilityLabel(ChipAvailability.used), 'Used');
      expect(chipAvailabilityLabel(ChipAvailability.active), 'Active');
    });
  });
}
