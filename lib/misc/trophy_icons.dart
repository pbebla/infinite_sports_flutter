import 'package:flutter/material.dart';

// ─── Material icon map (builtin) ─────────────────────────────────────────────

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

// ─── PNG asset icon map ───────────────────────────────────────────────────────

const Map<String, String> kTrophyAssetIcons = {
  'golden_boot':        'assets/trophies/golden_boot.png',
  'most_assists':       'assets/trophies/most_assists.png',
  'defensive_player':   'assets/trophies/defensive_player.png',
  'most_saves':         'assets/trophies/most_saves.png',
  'hat_trick':          'assets/trophies/hat_trick.png',
  'top_scorer':         'assets/trophies/top_scorer.png',
  'player_of_match':    'assets/trophies/player_of_match.png',
  'fastest_goal':       'assets/trophies/fastest_goal.png',
  'mvp':                'assets/trophies/mvp.png',
  'team_of_tournament': 'assets/trophies/team_of_tournament.png',
};

const List<String> kTrophyAssetIconKeys = [
  'golden_boot',
  'most_assists',
  'defensive_player',
  'most_saves',
  'hat_trick',
  'top_scorer',
  'player_of_match',
  'fastest_goal',
  'mvp',
  'team_of_tournament',
];

bool isAssetIcon(String key) => kTrophyAssetIcons.containsKey(key);

// ─── Unified renderer ─────────────────────────────────────────────────────────

/// Renders a trophy icon: PNG image tile for asset keys, Material icon for builtin keys.
Widget trophyIconWidget(String key, {double size = 32, Color? color}) {
  if (isAssetIcon(key)) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image.asset(
        kTrophyAssetIcons[key]!,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
  return Icon(trophyIconData(key), size: size, color: color);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

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
