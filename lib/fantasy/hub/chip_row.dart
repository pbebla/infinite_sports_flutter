// The chips row (P3b, spec §6; v2 in the owner's feedback round, Task 6):
// the four medallion assets as cards with a per-set count badge. Triple
// Captain and Bench Boost toggle FantasySquad.chip (one active per gameweek
// — selecting one deselects the other) with an accent glow when active;
// Wildcard and Free Hit render with a "Coming with transfers" caption and
// stay untappable until the transfer flows land (P3c). Effect lines, the
// set windows in the heading and the counts all read from the live config,
// never hard-coded.
//
// Counts (owner feedback round): each badge reads the manager's REAL usage
// (chip_usage.dart chipAvailability over their History): "1 left" while
// unspent in the active set, "Used" once spent in it (a set-1 chip is fresh
// again in set 2; a voided week refunds), "Active" while armed on the squad
// on screen. A spent chip can't be armed again (the server would void the
// replay at lock) — tapping it does nothing unless it is the one armed.
//
// Motion: the active glow animates in 200ms and collapses to zero duration
// under the OS reduced-motion setting; state only changes on a tap, so a
// stream reconnect can never replay it.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/chip_usage.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';

class FantasyChipRow extends StatelessWidget {
  const FantasyChipRow({
    super.key,
    required this.config,
    required this.activeChip,
    required this.enabled,
    required this.onChipChanged,
    this.availability,
  });

  final FantasyConfig config;

  /// 'tripleCaptain' | 'benchBoost' | null — FantasySquad.chip.
  final String? activeChip;

  /// false while locked: everything renders, nothing toggles.
  final bool enabled;
  final ValueChanged<String?> onChipChanged;

  /// Per-chip availability (chip_usage.dart chipAvailability). null = no
  /// usage known (signed out / no history yet): every chip "1 left", the
  /// armed one "Active".
  final Map<String, ChipAvailability>? availability;

  ChipAvailability _availability(String id) =>
      availability?[id] ??
      (id == activeChip ? ChipAvailability.active : ChipAvailability.available);

  /// A spent chip only taps to DISARM (it was armed anyway); otherwise the
  /// usual toggle while editable.
  VoidCallback? _tap(String id) {
    if (!enabled) return null;
    if (_availability(id) == ChipAvailability.used && activeChip != id) {
      return null;
    }
    return () => _toggle(id);
  }

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
                availability: _availability('tripleCaptain'),
                onTap: _tap('tripleCaptain'),
              ),
              const SizedBox(width: 10),
              _ChipCard(
                id: 'benchBoost',
                asset: 'assets/fantasy/chip_bench_boost.png',
                label: 'Bench Boost',
                effect: 'Bench scores full points this week',
                active: activeChip == 'benchBoost',
                availability: _availability('benchBoost'),
                onTap: _tap('benchBoost'),
              ),
              const SizedBox(width: 10),
              _ChipCard(
                id: 'wildcard',
                asset: 'assets/fantasy/chip_wildcard.png',
                label: 'Wildcard',
                effect: 'Unlimited transfers, permanent rebuild',
                caption: 'Coming with transfers',
                active: false,
                availability: _availability('wildcard'),
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
                availability: _availability('freeHit'),
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
    required this.availability,
    required this.onTap,
    this.caption,
  });

  final String id;
  final String asset;
  final String label;
  final String effect;
  final String? caption;

  /// Armed on the squad on screen — the accent glow.
  final bool active;

  /// The badge: "1 left" / "Used" / "Active".
  final ChipAvailability availability;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = fantasyAccent(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final comingSoon = caption != null;
    final used = availability == ChipAvailability.used;
    final badge = Container(
      key: ValueKey('chip_count_$id'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: used
            ? scheme.surfaceContainerHighest
            : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: used ? scheme.outlineVariant : accent.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Text(
        chipAvailabilityLabel(availability),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: used ? scheme.onSurfaceVariant : accent,
        ),
      ),
    );

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
              // The armed chip's badge reads "Active" (it replaces the old
              // separate pill — one status per card, never two).
              availability == ChipAvailability.active
                  ? KeyedSubtree(key: ValueKey('chip_active_$id'), child: badge)
                  : badge,
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
