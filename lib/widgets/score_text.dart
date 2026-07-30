import 'package:flutter/material.dart';

/// A score number that briefly flashes brand red and scales up when its value
/// INCREASES (a goal). Decreases (corrections) and the first build are silent.
class ScoreText extends StatefulWidget {
  final int value;
  final double fontSize;
  final Color baseColor;
  const ScoreText({
    super.key,
    required this.value,
    this.fontSize = 16,
    this.baseColor = const Color(0xFF111111),
  });

  @override
  State<ScoreText> createState() => _ScoreTextState();
}

class _ScoreTextState extends State<ScoreText>
    with SingleTickerProviderStateMixin {
  static const _flash = Color.fromARGB(255, 208, 0, 0);
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late int _shown = widget.value;

  @override
  void didUpdateWidget(covariant ScoreText old) {
    super.didUpdateWidget(old);
    if (widget.value > old.value) {
      _c.forward(from: 0);
    }
    _shown = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // 0 -> 1 -> 0 pulse curve.
        final t = (1 - (2 * _c.value - 1).abs()).clamp(0.0, 1.0);
        final color = Color.lerp(widget.baseColor, _flash, t)!;
        final scale = 1.0 + 0.35 * t;
        return Transform.scale(
          scale: scale,
          child: Text(
            '$_shown',
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        );
      },
    );
  }
}
