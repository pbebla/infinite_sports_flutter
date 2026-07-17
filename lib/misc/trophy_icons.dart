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
  'goal_net':           'assets/trophies/goal_net.png',
  'champion':           'assets/trophies/champion.png',
  'runner_up':          'assets/trophies/runner_up.png',
  'clean_sheet':        'assets/trophies/clean_sheet.png',
  'young_talent':       'assets/trophies/young_talent.png',
  // L6 basketball trophy badges (owner supplies real gold-on-black art later).
  'most_points':          'assets/trophies/most_points.png',
  'most_rebounds':        'assets/trophies/most_rebounds.png',
  'most_three_pointers':  'assets/trophies/most_three_pointers.png',
  'most_steals':          'assets/trophies/most_steals.png',
  'most_blocks':          'assets/trophies/most_blocks.png',
  // L6 flag-football trophy badges. best_receiver + ff_mvp carry the owner's
  // real gold-on-black art; the other two are placeholders until art lands.
  // ff_mvp is a FF-specific MVP badge (football player) so it never overwrites
  // the shared 'mvp' art that soccer/futsal/basketball trophies still use.
  'most_touchdowns':      'assets/trophies/most_touchdowns.png',
  'most_interceptions':   'assets/trophies/most_interceptions.png',
  'best_receiver':        'assets/trophies/best_receiver.png',
  'ff_mvp':               'assets/trophies/ff_mvp.png',
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
  'goal_net',
  'champion',
  'runner_up',
  'clean_sheet',
  'young_talent',
  'most_points',
  'most_rebounds',
  'most_three_pointers',
  'most_steals',
  'most_blocks',
  'most_touchdowns',
  'most_interceptions',
  'best_receiver',
  'ff_mvp',
];

bool isAssetIcon(String key) => kTrophyAssetIcons.containsKey(key);

// ─── Unified renderer ─────────────────────────────────────────────────────────

/// Renders a trophy icon: PNG image tile for asset keys, Material icon for builtin keys.
///
/// Asset icons are placed inside a fixed square ([size]×[size]) with
/// [BoxFit.contain] so the artwork is never cropped or stretched. The PNG
/// files are transparent, so no background clipping is applied — the icon
/// sits on whatever surface the parent provides, which keeps it correct in
/// both light and dark mode.
Widget trophyIconWidget(String key, {double size = 32, Color? color}) {
  if (isAssetIcon(key)) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        kTrophyAssetIcons[key]!,
        width: size,
        height: size,
        fit: BoxFit.contain,
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
