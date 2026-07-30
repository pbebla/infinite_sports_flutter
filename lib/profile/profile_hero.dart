import 'package:flutter/material.dart';

/// Fixed header widget for the tabbed player profile.
///
/// Shows only:
/// - Gradient background (brand / team color)
/// - Circular photo
/// - Player's full name (left-aligned, vertically centred next to photo)
///
/// Constructor: [photoUrl], [fullName], [teamColor].
class ProfileHero extends StatelessWidget {
  final String photoUrl;
  final String fullName;
  final Color? teamColor;

  const ProfileHero({
    super.key,
    required this.photoUrl,
    required this.fullName,
    this.teamColor,
  });

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    final base = teamColor ?? brand;
    final darker = _darken(base, 0.35);

    // Animated so the team tint (which arrives with the profile's single
    // career reveal) eases in instead of snapping.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, darker],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _avatar(),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              fullName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
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
