// The code-drawn futsal court (P3b) — a portrait half-court CustomPaint:
// outer boundary, the goal area at the top, a center line + half-circle hint
// at the bottom. Theme-aware by rule (spec §10): dark mode is a subtly-lit
// dark court with gold-accent lines, light mode a light court with red-accent
// lines — everything derived from the Theme, never a baked image.
//
// Starter slots sit ON the court (GK top-center, DEF row, ATT row — fractions
// from squad_builder_logic.starterOffsets); the bench lives BELOW on its own
// visually-distinct surface labeled from the live config ("Bench · 50%
// points") per the adopted same-layout design.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

class FantasyCourtView extends StatelessWidget {
  const FantasyCourtView({
    super.key,
    required this.config,
    required this.slots,
    required this.slotPicks,
    this.captainId,
    this.viceId,
    this.onSlotTap,
    this.weekPointsFor,
  });

  final FantasyConfig config;

  /// All slots ([buildSlots] order) with their current picks; this widget
  /// renders the starters on the court and the bench on its surface below.
  final List<SquadSlot> slots;
  final List<SquadPick?> slotPicks;
  final String? captainId;
  final String? viceId;

  /// Called with the slot index; null = locked (nothing tappable).
  final void Function(int slotIndex)? onSlotTap;

  /// Week-points text per playerId — only rendered when provided (P4/P6).
  final String? Function(String playerId)? weekPointsFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = fantasyAccent(context);

    // Dark: near-black court with a soft accent glow ("subtly lit"); light:
    // a light surface with stronger primary lines. All colorScheme-derived.
    final surface = isDark
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.05), scheme.surfaceContainerLow)
        : scheme.surfaceContainerLow;
    final lines = accent.withValues(alpha: isDark ? 0.55 : 0.45);
    final glow = accent.withValues(alpha: isDark ? 0.10 : 0.05);

    final offsets = starterOffsets(config);
    final starterCount = offsets.length;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 0.92,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(
              painter: _CourtPainter(
                  surface: surface, lines: lines, glow: glow),
              child: Stack(
                children: [
                  for (var i = 0; i < starterCount; i++)
                    Align(
                      alignment: Alignment(
                          offsets[i].x * 2 - 1, offsets[i].y * 2 - 1),
                      child: _slotWidget(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _BenchSurface(
          label: 'Bench · ${config.benchFactorPercent}% points',
          children: [
            for (var i = starterCount; i < slots.length; i++) _slotWidget(i),
          ],
        ),
      ],
    );
  }

  Widget _slotWidget(int i) {
    final pick = slotPicks[i];
    if (pick == null) {
      return FantasyEmptySlot(
        key: ValueKey('empty_slot_$i'),
        position: slots[i].position,
        onTap: onSlotTap == null ? null : () => onSlotTap!(i),
      );
    }
    return FantasyPlayerChip(
      key: ValueKey('squad_chip_${pick.playerId}'),
      name: pick.playerId,
      priceTenths: pick.priceTenths,
      isCaptain: pick.playerId == captainId,
      isVice: pick.playerId == viceId,
      weekPoints: weekPointsFor?.call(pick.playerId),
      onTap: onSlotTap == null ? null : () => onSlotTap!(i),
    );
  }
}

/// The bench's own surface — visually distinct from the court so "these two
/// score differently" reads at a glance.
class _BenchSurface extends StatelessWidget {
  const _BenchSurface({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  const _CourtPainter({
    required this.surface,
    required this.lines,
    required this.glow,
  });

  final Color surface;
  final Color lines;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Court surface with a soft light pooling from the goal end.
    canvas.drawRect(rect, Paint()..color = surface);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.75),
          radius: 1.2,
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(rect),
    );

    final line = Paint()
      ..color = lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // Outer boundary.
    final inset = size.width * 0.035;
    final bounds = Rect.fromLTRB(
        inset, inset, size.width - inset, size.height - inset);
    canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(6)), line);

    // Goal mouth on the top line + the penalty-area arc under it.
    final goalW = size.width * 0.22;
    final goalH = size.height * 0.035;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, bounds.top + goalH / 2),
        width: goalW,
        height: goalH,
      ),
      line,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, bounds.top),
        radius: size.width * 0.24,
      ),
      0,
      3.14159265,
      false,
      line,
    );

    // Half-court line along the bottom + the center-circle hint bulging up.
    canvas.drawLine(Offset(bounds.left, bounds.bottom),
        Offset(bounds.right, bounds.bottom), line);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, bounds.bottom),
        radius: size.width * 0.13,
      ),
      3.14159265,
      3.14159265,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(_CourtPainter old) =>
      old.surface != surface || old.lines != lines || old.glow != glow;
}
