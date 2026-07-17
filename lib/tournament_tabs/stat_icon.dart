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
    // Basketball (P4) — legacy league activity spellings, bundled art.
    case 'onepointer':
      return 'assets/onepointer.png';
    case 'twopointer':
      return 'assets/twopointer.png';
    case 'threepointer':
      return 'assets/threepointer.png';
    case 'rebound':
      return 'assets/rebound.png';
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

/// Renders a stat icon. By default it sits on a white rounded chip so the
/// dark line-art (soccer/futsal) stays readable in both themes. When
/// [badge] is true the icon is the owner's gold-on-black self-contained
/// badge art (basketball / later flag football) and is rendered AS-IS with
/// no chip, so the gold reads on both light and dark cards. Pass a resolved
/// asset path (e.g. from [statIconAsset] or [leagueStatIcon]); a null asset
/// falls back to a neutral chip icon so an unexpected type never crashes.
class StatIcon extends StatelessWidget {
  final String? asset;
  final double size;
  final bool badge;

  const StatIcon({
    super.key,
    required this.asset,
    this.size = 24,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    // Badge art: no white chip. (A null asset falls through to the chip
    // fallback below so we never render an empty bare box.)
    if (badge && asset != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(asset!, fit: BoxFit.contain),
      );
    }
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
          ? Icon(Icons.sports, size: size * 0.62, color: Colors.grey.shade700)
          : Image.asset(asset!, fit: BoxFit.contain),
    );
  }
}
