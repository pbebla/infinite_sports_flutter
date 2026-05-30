import 'package:flutter/material.dart';

/// Maps a stored event-type string (case-insensitive) to the owner's custom
/// icon asset path. Returns null for unknown event types.
String? statIconAsset(String eventType) {
  switch (eventType.toLowerCase().trim()) {
    case 'goal':
      return 'assets/stat_icons/goal.png';
    case 'own goal':
      return 'assets/stat_icons/own_goal.png';
    case 'penalty goal':
      return 'assets/stat_icons/goal_penalty.png';
    case 'penalty missed':
      return 'assets/stat_icons/penalty_missed.png';
    case 'penalty saved':
      return 'assets/stat_icons/penalty_saved.png';
    case 'save':
      return 'assets/stat_icons/save.png';
    case 'assist':
      return 'assets/stat_icons/assist.png';
    case 'substitution':
      return 'assets/stat_icons/substitution.png';
    case 'yellow card':
      return 'assets/stat_icons/yellow_card.png';
    case 'red card':
      return 'assets/stat_icons/red_card.png';
    case 'second yellow':
      return 'assets/stat_icons/second_yellow.png';
    case 'foul':
      return 'assets/stat_icons/foul.png';
    case 'dpl':
      return 'assets/stat_icons/dpl.png';
    default:
      return null;
  }
}

/// Maps a fixtures leader-strip stat key to the matching icon asset, so the
/// strip reuses the same artwork as the timeline. Returns null if unknown.
String? statIconAssetForStat(String statName) {
  switch (statName.toLowerCase().trim()) {
    case 'goals':
      return statIconAsset('goal');
    case 'assists':
      return statIconAsset('assist');
    case 'saves':
      return statIconAsset('save');
    case 'dpl':
      return statIconAsset('dpl');
    default:
      return null;
  }
}

/// Renders a stat icon on a white rounded chip so the dark line-art stays
/// readable in both light and dark themes. Pass a resolved asset path (e.g.
/// from [statIconAsset]); if it is null, a neutral fallback icon is shown so
/// an unexpected event type never crashes or shows a broken image.
class StatIcon extends StatelessWidget {
  final String? asset;
  final double size;

  const StatIcon({super.key, required this.asset, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 1.5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: asset == null
          ? Icon(Icons.sports, size: size * 0.62, color: Colors.grey)
          : Image.asset(asset!, fit: BoxFit.contain),
    );
  }
}
