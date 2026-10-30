// The fantasy player profile's hero (round 3, spec §4, owner mockup): a
// large photo under a dark top scrim (the floating back/star buttons read on
// any photo) fading into the page surface at the bottom, with the team logo
// badge, the name (wraps — never ellipsized, never underlined) and
// "Team · Position #N". No photo → the player's initials over the team
// colour. The bottom fade follows the theme (colorScheme.surface), so the
// name sits on the page colour in light AND dark.
//
// Photos never gate content: the initials face renders instantly and stays
// under a loading/failed photo; the photo fades in over it (200ms, zero
// under reduced motion). Same for the team logo over its initials badge.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';

/// A stable per-team colour for teams whose jersey colour isn't set (the
/// Teams node's optional `Color`): a hue hashed from the name at a mid-dark
/// tone, so white initials read on it in both themes.
Color fallbackTeamColor(String team) {
  var hash = 0;
  for (final unit in team.trim().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.42, 0.34).toColor();
}

/// Text colour that reads on [background] (white on dark, near-black on
/// light jersey colours).
Color _onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;

class FantasyProfileHero extends StatelessWidget {
  const FantasyProfileHero({
    super.key,
    required this.player,
    required this.teamColor,
    required this.height,
    this.logoUrl,
    this.shirtNumber,
  });

  final FantasyPlayer player;

  /// The team's jersey colour (or [fallbackTeamColor]).
  final Color teamColor;
  final double height;
  final String? logoUrl;

  /// From the league roster ("#3"); omitted when unknown.
  final String? shirtNumber;

  String get _subtitle {
    final number = shirtNumber?.trim() ?? '';
    final position =
        '${positionLabel(player.position)}${number.isEmpty ? '' : ' #$number'}';
    final team = player.teamName.trim();
    return team.isEmpty ? position : '$team · $position';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final photo = player.photoUrl;

    final initialsFace = Container(
      color: teamColor,
      alignment: const Alignment(0, -0.3),
      child: Text(
        initialsFor(player.name),
        style: TextStyle(
          fontSize: 92,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
          color: _onColor(teamColor).withValues(alpha: 0.9),
        ),
      ),
    );

    return SizedBox(
      key: const ValueKey('profile_hero'),
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null && photo.isNotEmpty)
            CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.4),
              fadeInDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              placeholderFadeInDuration: Duration.zero,
              placeholder: (_, __) => initialsFace,
              errorWidget: (_, __, ___) => initialsFace,
            )
          else
            initialsFace,
          // Top scrim: the floating back/star buttons and the status bar
          // read on any photo (light or dark).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x73000000), Color(0x00000000)],
                stops: [0, 0.32],
              ),
            ),
          ),
          // Bottom fade into the page surface (theme-following).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  surface.withValues(alpha: 0),
                  surface.withValues(alpha: 0.78),
                  surface,
                ],
                stops: const [0.36, 0.74, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FantasyTeamBadge(
                  team: player.teamName,
                  logoUrl: logoUrl,
                  color: teamColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        player.name,
                        key: const ValueKey('profile_name'),
                        // Wraps, never ellipsized or underlined (house rule).
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 24,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle,
                        key: const ValueKey('profile_subtitle'),
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The team logo badge: the season logo on a neutral rounded tile, or the
/// team's initials over its colour while/when there is no logo.
class FantasyTeamBadge extends StatelessWidget {
  const FantasyTeamBadge({
    super.key,
    required this.team,
    required this.color,
    this.logoUrl,
    this.size = 54,
  });

  final String team;
  final Color color;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(size * 0.28);
    final initials = Container(
      color: color,
      alignment: Alignment.center,
      child: Text(
        initialsFor(team),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: _onColor(color),
        ),
      ),
    );
    final url = logoUrl;
    return Container(
      key: const ValueKey('profile_team_badge'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.7), width: 1),
      ),
      child: (url == null || url.isEmpty)
          ? initials
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              fadeInDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              placeholderFadeInDuration: Duration.zero,
              placeholder: (_, __) => initials,
              errorWidget: (_, __, ___) => initials,
              imageBuilder: (_, image) => Padding(
                padding: EdgeInsets.all(size * 0.1),
                child: Image(image: image, fit: BoxFit.contain),
              ),
            ),
    );
  }
}
