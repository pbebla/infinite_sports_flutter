import 'package:flutter/material.dart';

/// Maps a stored event-type string (case-insensitive) to the owner's custom
/// icon asset path. Returns null for unknown event types.
String? statIconAsset(String eventType) {
  switch (eventType.toLowerCase().trim()) {
    case 'goal':
      return 'assets/goal.png';
    case 'own goal':
      return 'assets/own_goal.png';
    case 'penalty goal':
      return 'assets/goal_penalty.png';
    case 'penalty missed':
      return 'assets/penalty_missed.png';
    case 'penalty saved':
      return 'assets/penalty_saved.png';
    case 'save':
      return 'assets/save.png';
    case 'assist':
      return 'assets/assist.png';
    case 'substitution':
      return 'assets/substitution.png';
    case 'yellow card':
      return 'assets/yellow.png';
    case 'red card':
      return 'assets/red.png';
    case 'second yellow':
      return 'assets/second_yellow.png';
    case 'foul':
      return 'assets/foul.png';
    case 'dpl':
      return 'assets/dpl.png';
    // League Experience P2 — league activity-type spellings (P1 capture
    // writes these verbatim; the tournament spellings above keep working).
    case 'pengoal':
      return 'assets/goal_penalty.png';
    case 'penmissed':
      return 'assets/penalty_missed.png';
    case 'pensaved':
      return 'assets/penalty_saved.png';
    case 'owngoal':
      return 'assets/own_goal.png';
    case 'yellow':
      return 'assets/yellow.png';
    case 'secondyellow':
      return 'assets/second_yellow.png';
    case 'red':
      return 'assets/red.png';
    // Legacy league blue card — retired for new capture, still renders.
    case 'blue':
      return 'assets/blue.png';
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
          // grey.shade700 keeps the fallback readable against the white chip.
          ? Icon(Icons.sports, size: size * 0.62, color: Colors.grey.shade700)
          : Image.asset(asset!, fit: BoxFit.contain),
    );
  }
}
