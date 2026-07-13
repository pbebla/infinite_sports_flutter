import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted-glass surface: blurs whatever is painted behind it and lays a
/// translucent theme-aware tint plus hairline border on top. The app-wide
/// glass building block — the nav pill and search button use it first.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark
        ? Colors.black.withOpacity(0.38)
        : Colors.white.withOpacity(0.60);
    final edge = isDark
        ? Colors.white.withOpacity(0.16)
        : Colors.black.withOpacity(0.08);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: borderRadius,
            border: Border.all(color: edge, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}
