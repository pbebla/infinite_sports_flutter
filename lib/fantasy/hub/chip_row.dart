// The chips row (P3b, spec §6; v2 in the owner's feedback round, Task 6):
// the four medallion assets as cards with a per-set count badge. Triple
// Captain and Bench Boost toggle FantasySquad.chip (one active per gameweek
// — selecting one deselects the other) with an accent glow when active;
// Wildcard and Free Hit render with a "Coming with transfers" caption and
// stay untappable until the transfer flows land (P3c). Effect lines, the
// set windows in the heading and the counts all read from the live config,
// never hard-coded.
//
// Counts: until per-manager chip-usage tracking lands (P4), each chip shows
// "1 left" for the active set; [usedChips] is the nullable seam P4 wires
// real usage through (ids used in the ACTIVE set → "0 left") with no UI
// rework.
//
// Motion: the active glow animates in 200ms and collapses to zero duration
// under the OS reduced-motion setting; state only changes on a tap, so a
// stream reconnect can never replay it.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

class FantasyChipRow extends StatelessWidget {
  const FantasyChipRow({
    super.key,
    required this.config,
    required this.activeChip,
    required this.enabled,
    required this.onChipChanged,
    this.usedChips,
  });

  final FantasyConfig config;

  /// 'tripleCaptain' | 'benchBoost' | null — FantasySquad.chip.
  final String? activeChip;

  /// false while locked: everything renders, nothing toggles.
  final bool enabled;
  final ValueChanged<String?> onChipChanged;

  /// Chip ids already SPENT in the active set (P4 wires real per-manager
  /// usage here). null/absent = none used: every chip shows "1 left".
  final Set<String>? usedChips;

  bool _used(String id) => usedChips?.contains(id) ?? false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            // Set windows straight from the live config (Task 6 copy fix).
            'One chip may be active per gameweek · '
            'Set 1: GW1–${config.chipSet1EndGw} · '
            'Set 2: GW${config.chipSet1EndGw + 1}–final',
            softWrap: true,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _ChipCard(
                id: 'tripleCaptain',
                asset: 'assets/fantasy/chip_triple_captain.png',
                label: 'Triple Captain',
                effect: 'Captain ×${config.tripleCaptainMultiplier} this week',
                active: activeChip == 'tripleCaptain',
                used: _used('tripleCaptain'),
                onTap: enabled ? () => _toggle('tripleCaptain') : null,
              ),
              const SizedBox(width: 10),
              _ChipCard(
                id: 'benchBoost',
                asset: 'assets/fantasy/chip_bench_boost.png',
                label: 'Bench Boost',
                effect: 'Bench scores full points this week',
                active: activeChip == 'benchBoost',
                used: _used('benchBoost'),
                onTap: enabled ? () => _toggle('benchBoost') : null,
              ),
              const SizedBox(width: 10),
              _ChipCard(
                id: 'wildcard',
                asset: 'assets/fantasy/chip_wildcard.png',
                label: 'Wildcard',
                effect: 'Unlimited transfers, permanent rebuild',
                caption: 'Coming with transfers',
                active: false,
                used: _used('wildcard'),
                onTap: null,
              ),
              const SizedBox(width: 10),
              _ChipCard(
                id: 'freeHit',
                asset: 'assets/fantasy/chip_free_hit.png',
                label: 'Free Hit',
                effect: 'One-week rebuild — squad returns after',
                caption: 'Coming with transfers',
                active: false,
                used: _used('freeHit'),
                onTap: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One active chip max: tapping the active one clears it, tapping another
  /// replaces it.
  void _toggle(String id) => onChipChanged(activeChip == id ? null : id);
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({
    required this.id,
    required this.asset,
    required this.label,
    required this.effect,
    required this.active,
    required this.used,
    required this.onTap,
    this.caption,
  });

  final String id;
  final String asset;
  final String label;
  final String effect;
  final String? caption;
  final bool active;

  /// Spent in the active set → the badge reads "0 left".
  final bool used;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final comingSoon = caption != null;

    return InkWell(
      key: ValueKey('fantasy_chip_$id'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: comingSoon ? 0.65 : 1,
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          width: 132,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          decoration: BoxDecoration(
            color: active
                ? Color.alphaBlend(
                    accent.withValues(alpha: 0.10), scheme.surfaceContainerHigh)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? accent
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: active ? 1.8 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            children: [
              Image.asset(asset, height: 44, fit: BoxFit.contain),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                key: ValueKey('chip_count_$id'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: used
                      ? scheme.surfaceContainerHighest
                      : accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: used
                        ? scheme.outlineVariant
                        : accent.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  used ? '0 left' : '1 left',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: used ? scheme.onSurfaceVariant : accent,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                effect,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (active) ...[
                const SizedBox(height: 5),
                Container(
                  key: ValueKey('chip_active_$id'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Active',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
              if (comingSoon) ...[
                const SizedBox(height: 5),
                Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
