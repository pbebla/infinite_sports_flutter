import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/profile_stat_priority.dart';

/// Fixed header widget for the tabbed player profile.
///
/// Inputs are all pre-resolved by the caller (ProfilePage, Task 6):
/// - [photoUrl] — remote image URL; empty string → portrait placeholder.
/// - [fullName] — display name (e.g. "Sam Stone").
/// - [current] — active / most-recent participation stint (may be null for new
///   users with no history).
/// - [teamColor] — primary color extracted from the team logo. Falls back to
///   the app brand primary when null.
/// - [headlineStats] — exactly 3 pre-resolved stats shown in the strip below
///   the gradient, ordered by [profileStatPriority].
/// - [trophyCount] — total awards; shown as a 4th box in the strip.
/// - [isKeeper] — when true, a "🧤 GOALIE" chip is rendered next to the name.
class ProfileHero extends StatelessWidget {
  final String photoUrl;
  final String fullName;
  final ParticipationStint? current;
  final Color? teamColor;
  final List<({String label, String value})> headlineStats;
  final int trophyCount;
  final bool isKeeper;

  const ProfileHero({
    super.key,
    required this.photoUrl,
    required this.fullName,
    this.current,
    this.teamColor,
    required this.headlineStats,
    required this.trophyCount,
    this.isKeeper = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    final base = teamColor ?? brand;
    final darker = _darken(base, 0.35);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Gradient zone ──────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, darker],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Photo
              _avatar(),
              const SizedBox(width: 16),
              // Name + subtitle line
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + optional keeper chip
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (isKeeper)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: Colors.white54, width: 1),
                            ),
                            child: const Text(
                              '🧤 GOALIE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Subtitle: team · sport · #number · position
                    if (current != null) _subtitleLine(current!),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Stat strip ─────────────────────────────────────────────────────
        _statStrip(context),
      ],
    );
  }

  Widget _avatar() {
    const double r = 40;
    final ImageProvider img = photoUrl.isNotEmpty
        ? NetworkImage(photoUrl)
        : const AssetImage('assets/portraitplaceholder.png') as ImageProvider;

    return CircleAvatar(
      radius: r,
      backgroundImage: img,
      backgroundColor: Colors.white24,
      onBackgroundImageError: (_, __) {},
      child: photoUrl.isNotEmpty
          ? null
          : null, // placeholder already handled via AssetImage
    );
  }

  Widget _subtitleLine(ParticipationStint stint) {
    final parts = <String>[];
    if (stint.team.isNotEmpty) parts.add(stint.team);

    if (stint.isTournament) {
      // "Tournament (label)" instead of raw sport name
      parts.add('Tournament (${stint.label})');
    } else if (stint.sport.isNotEmpty) {
      parts.add(stint.sport);
    }

    // jersey number extracted from label if it contains a "#" prefix, or from
    // scopeId. For now, the caller can embed number in the label as "#7" — we
    // forward it as-is.  Task 6 wires the real number field.
    if (stint.position.isNotEmpty) parts.add(stint.position);

    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        height: 1.3,
      ),
    );
  }

  Widget _statStrip(BuildContext context) {
    // Build 3 stat boxes + 1 trophy box
    final boxes = <({String label, String value})>[
      ...headlineStats.take(3),
      (label: '🏆', value: trophyCount.toString()),
    ];

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          for (int i = 0; i < boxes.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 10,
                endIndent: 10,
                color: Theme.of(context).dividerColor,
              ),
            Expanded(child: _statBox(context, boxes[i])),
          ],
        ],
      ),
    );
  }

  Widget _statBox(
      BuildContext context, ({String label, String value}) stat) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            style: TextStyle(
              fontSize: 11,
              color: onSurface.withValues(alpha: 0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Darken a color by [amount] (0..1).
  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final darkened =
        hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return darkened.toColor();
  }
}
