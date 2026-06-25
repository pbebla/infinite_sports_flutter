import 'package:flutter/material.dart';

const Map<String, IconData> kTrophyIcons = {
  'trophy_gold': Icons.emoji_events,
  'medal': Icons.military_tech,
  'boot': Icons.sports_soccer,
  'gloves': Icons.sports_handball,
  'shield': Icons.shield,
  'star': Icons.star,
  'basketball': Icons.sports_basketball,
  'football': Icons.sports_football,
  'cup': Icons.emoji_events_outlined,
};

IconData trophyIconData(String key) => kTrophyIcons[key] ?? Icons.emoji_events;

Color tierColor(String tier) {
  switch (tier) {
    case 'silver':
      return const Color(0xFFB0B6BF);
    case 'bronze':
      return const Color(0xFFCD7F32);
    default:
      return const Color(0xFFFFC107); // gold
  }
}

/// Returns the asset path for a trophy icon key, for future image-based icons.
String trophyAssetFor(String key) => 'assets/trophies/$key.png';
