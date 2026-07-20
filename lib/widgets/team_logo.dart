import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Unified team logo widget. Replaces 12+ duplicated
/// CircleAvatar / ClipOval + Image.network + errorBuilder patterns
/// across tournament screens.
///
/// Provides:
/// - Persistent disk caching via cached_network_image (vs Image.network
///   which only caches in memory and re-downloads on cold launch)
/// - Explicit cacheWidth / cacheHeight sized to the rendered size so the
///   decoded bitmap matches what we actually display
/// - Consistent fallback icon when URL is null/empty/fails
///
/// L6.2 Task 3: the logo image itself is NEVER cropped or stretched — it
/// renders with [BoxFit.contain] inside a [size]x[size] box, so non-square
/// crests (wide wordmarks, tall shields, ...) show in full. Only the
/// MISSING-logo fallback keeps its circular shield shape.
class TeamLogo extends StatelessWidget {
  final String? url;
  final double size;
  final IconData fallbackIcon;
  final Color? fallbackBackground;

  const TeamLogo({
    super.key,
    required this.url,
    this.size = 32,
    this.fallbackIcon = Icons.shield_outlined,
    this.fallbackBackground,
  });

  @override
  Widget build(BuildContext context) {
    final bg = fallbackBackground ??
        Theme.of(context).colorScheme.surfaceContainerHighest;

    if (url == null || url!.isEmpty) {
      return _fallback(bg);
    }

    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        // Contain (not cover + ClipOval): the full crest always renders,
        // undistorted — no crop, no oval mask on the real logo.
        fit: BoxFit.contain,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        placeholder: (context, url) => _fallback(bg),
        errorWidget: (context, url, error) => _fallback(bg),
      ),
    );
  }

  Widget _fallback(Color bg) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(fallbackIcon, size: size * 0.6, color: Colors.grey.shade600),
    );
  }
}
