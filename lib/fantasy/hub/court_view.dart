// The code-drawn futsal pitch (P3b; FPL-style v2 from the owner's feedback
// round): a GREEN grass field painted as a trapezoid — narrow at the far
// goal end, full width near — so the whole court reads slightly lifted into
// 3D perspective. The perspective is painted directly (no Matrix4 transform):
// lines stay crisp and the slot widgets remain ordinary Aligns whose tap
// targets always match the visuals (squad_builder_logic.pitchPerspective maps
// each row into the trapezoid the painter draws from the same constants).
//
// Grass: layered vertical gradient (deeper green at the far end, lighter
// near) + subtle alternating mow stripes whose heights grow toward the near
// end + near-white line markings + a soft floodlight glow and near-edge
// vignette for depth. Green in BOTH themes (a pitch is green — that's
// theme-legitimate), with the exact shades derived per brightness: deeper/
// darker greens in dark mode, brighter in light.
//
// Starter slots sit ON the pitch (GK far row, DEF mid, ATT near — fractions
// from squad_builder_logic.starterOffsets, perspective-mapped); the bench
// lives BELOW on its own visually-distinct surface labeled from the live
// config ("Bench · 50% points").

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

/// The fantasy pitch-green family — the grass base here and the budget bar's
/// fill (Task 5 shares the family). Deeper in dark mode, brighter in light,
/// green in both themes.
Color fantasyPitchGreen(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2E8B57)
        : const Color(0xFF2FA05A);

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
    this.photoUrlFor,
  });

  final FantasyConfig config;

  /// All slots ([buildSlots] order) with their current picks; this widget
  /// renders the starters on the pitch and the bench on its surface below.
  final List<SquadSlot> slots;
  final List<SquadPick?> slotPicks;
  final String? captainId;
  final String? viceId;

  /// Called with the slot index; null = locked (nothing tappable).
  final void Function(int slotIndex)? onSlotTap;

  /// Week-points text per playerId — only rendered when provided (P4/P6).
  final String? Function(String playerId)? weekPointsFor;

  /// Market photo per playerId (Task 3) — null/absent falls back to
  /// initials (photos never gate content).
  final String? Function(String playerId)? photoUrlFor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    // Theme-derived greens: dark mode a deeper/darker green, light mode a
    // brighter one; lines near-white at a per-mode alpha.
    final green = fantasyPitchGreen(context);
    final grassFar = Color.lerp(green, Colors.black, isDark ? 0.45 : 0.22)!;
    final grassNear =
        Color.lerp(green, isDark ? Colors.black : Colors.white, 0.12)!;
    final stripe = Colors.white.withValues(alpha: isDark ? 0.045 : 0.07);
    final lines = Colors.white.withValues(alpha: isDark ? 0.60 : 0.85);
    final glow = Colors.white.withValues(alpha: isDark ? 0.07 : 0.10);

    // The trapezoid's surround (the sliver outside the pitch edges).
    final surround = scheme.surfaceContainerLow;

    // Perspective-mapped slot rows: same constants the painter draws with,
    // so hit zones match the drawn grass exactly.
    final offsets =
        starterOffsets(config).map(pitchPerspective).toList(growable: false);
    final starterCount = offsets.length;

    return Column(
      children: [
        AspectRatio(
          // Taller than wide: room for the big photo chips (Task 3) while
          // 5 starters + pitch still fit a phone width (the page scrolls).
          aspectRatio: 0.78,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: CustomPaint(
              painter: _PitchPainter(
                surround: surround,
                grassFar: grassFar,
                grassNear: grassNear,
                stripe: stripe,
                lines: lines,
                glow: glow,
              ),
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
        onPitch: !slots[i].bench,
        onTap: onSlotTap == null ? null : () => onSlotTap!(i),
      );
    }
    return FantasyPlayerChip(
      key: ValueKey('squad_chip_${pick.playerId}'),
      name: pick.playerId,
      priceTenths: pick.priceTenths,
      photoUrl: photoUrlFor?.call(pick.playerId),
      isCaptain: pick.playerId == captainId,
      isVice: pick.playerId == viceId,
      weekPoints: weekPointsFor?.call(pick.playerId),
      onTap: onSlotTap == null ? null : () => onSlotTap!(i),
    );
  }
}

/// The bench's own surface — visually distinct from the pitch so "these two
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

class _PitchPainter extends CustomPainter {
  const _PitchPainter({
    required this.surround,
    required this.grassFar,
    required this.grassNear,
    required this.stripe,
    required this.lines,
    required this.glow,
  });

  final Color surround;
  final Color grassFar;
  final Color grassNear;
  final Color stripe;
  final Color lines;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = surround);

    // The trapezoid: far (top) edge narrowed to pitchTopScale of the near
    // (bottom) edge — the painted perspective.
    final cx = size.width / 2;
    final topY = size.height * 0.030;
    final bottomY = size.height * 0.985;
    final nearHalf = size.width * 0.5 * 0.97;
    final farHalf = nearHalf * pitchTopScale;
    double halfAt(double y) =>
        farHalf + (nearHalf - farHalf) * ((y - topY) / (bottomY - topY));

    final pitch = Path()
      ..moveTo(cx - farHalf, topY)
      ..lineTo(cx + farHalf, topY)
      ..lineTo(cx + nearHalf, bottomY)
      ..lineTo(cx - nearHalf, bottomY)
      ..close();

    canvas.save();
    canvas.clipPath(pitch);

    // Grass fade: deeper at the far end, lighter near.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [grassFar, grassNear],
        ).createShader(rect),
    );

    // Alternating mow stripes whose heights grow toward the near end —
    // equal world-spacing compressed at the far end (perspective).
    const bands = 9;
    for (var i = 0; i < bands; i++) {
      if (i.isEven) continue;
      final t0 = math.pow(i / bands, 1.6).toDouble();
      final t1 = math.pow((i + 1) / bands, 1.6).toDouble();
      canvas.drawRect(
        Rect.fromLTRB(0, topY + (bottomY - topY) * t0, size.width,
            topY + (bottomY - topY) * t1),
        Paint()..color = stripe,
      );
    }

    // Soft floodlight pooling from the goal end + a near-edge vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.85),
          radius: 1.1,
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0),
          ],
          stops: const [0, 0.28],
        ).createShader(rect),
    );

    canvas.restore();

    final line = Paint()
      ..color = lines
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    // Boundary.
    canvas.drawPath(pitch, line);

    // Goal box at the far end, its sides converging with the perspective,
    // plus the penalty arc under it.
    final goalY = topY + size.height * 0.055;
    canvas.drawPath(
      Path()
        ..moveTo(cx - farHalf * 0.30, topY)
        ..lineTo(cx - halfAt(goalY) * 0.30, goalY)
        ..lineTo(cx + halfAt(goalY) * 0.30, goalY)
        ..lineTo(cx + farHalf * 0.30, topY),
      line,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, goalY),
        width: farHalf * 1.15,
        height: size.height * 0.10,
      ),
      0,
      math.pi,
      false,
      line,
    );

    // Halfway line along the near edge + the center-circle hint bulging up.
    canvas.drawLine(
        Offset(cx - nearHalf, bottomY), Offset(cx + nearHalf, bottomY), line);
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(cx, bottomY), radius: size.width * 0.14),
      math.pi,
      math.pi,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.surround != surround ||
      old.grassFar != grassFar ||
      old.grassNear != grassNear ||
      old.stripe != stripe ||
      old.lines != lines ||
      old.glow != glow;
}
