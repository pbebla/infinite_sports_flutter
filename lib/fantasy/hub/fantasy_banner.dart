// The Infinite Fantasy banner card (P3b feedback round, Task 1): the surface
// now FOLLOWS the theme. Light mode renders a normal elevated light card
// (colorScheme surfaces) with red (primary) accents; dark mode keeps the dark
// gradient card with gold accents. The gold wordmark carries dark outlines
// that wash out on a light card, so light mode paints a subtle dark rounded
// backdrop JUST behind the logo (a pill), never the whole card.
//
// This file is the single source of the fantasy brand surface: the hub
// header, the league page's Fantasy entry card and the search hub's entry
// card all read [cardDecoration]/[foreground]/[accent]/[logo] from here so
// the three can never drift apart. Everything stacks CENTERED: logo, then
// the manager's team name once set, then the season line, then the bottom
// row (deadline countdown / entry button).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

/// The gold Infinite Fantasy wordmark (the banner, the share images).
const String kFantasyLogoAsset = 'assets/fantasy/fantasy_logo.png';

class FantasyBanner extends StatelessWidget {
  const FantasyBanner({
    super.key,
    this.subtitle,
    this.bottom,
    this.teamName,
    this.onEditTeamName,
  });

  /// Muted line under the wordmark (e.g. "Futsal · Season 15").
  final String? subtitle;

  /// Optional row pinned under the text (e.g. the deadline countdown or the
  /// entry button), rendered centered.
  final Widget? bottom;

  /// The manager's fantasy team name — shown big under the logo once set
  /// (P3a Task 3). Wraps rather than truncates (house rule: names wrap).
  final String? teamName;

  /// Rename affordance: a small edit icon next to [teamName]. Hidden while
  /// null (e.g. the league entry card shows no name at all).
  final VoidCallback? onEditTeamName;

  /// The dark-card gradient pair — the banner surface in dark mode, the
  /// walkthrough's full-bleed backdrop, and the logo's backdrop pill in
  /// light mode.
  static const Color gradientTop = Color(0xFF15171E);
  static const Color gradientBottom = Color(0xFF262A38);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// The fantasy accent for this theme: gold on the dark card, primary red
  /// on the light one (the deadline chip's pairing — shared app-wide via
  /// player_chip.dart's fantasyAccent).
  static Color accent(BuildContext context) => _isDark(context)
      ? TournamentColors.gold
      : Theme.of(context).colorScheme.primary;

  /// Primary text/icon color ON the banner surface.
  static Color foreground(BuildContext context) => _isDark(context)
      ? Colors.white
      : Theme.of(context).colorScheme.onSurface;

  /// Muted text/icon color ON the banner surface (subtitles, chevrons).
  static Color foregroundMuted(BuildContext context) => _isDark(context)
      ? Colors.white70
      : Theme.of(context).colorScheme.onSurfaceVariant;

  /// The shared brand surface: dark gradient card in dark mode, a normal
  /// elevated light card (colorScheme) with a hairline border in light mode.
  static BoxDecoration cardDecoration(BuildContext context,
      {double radius = 20}) {
    if (_isDark(context)) {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientTop, gradientBottom],
        ),
        borderRadius: BorderRadius.circular(radius),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    );
  }

  /// The gold wordmark, legible on BOTH surfaces: bare on the dark card; on
  /// the light card it sits on a subtle dark rounded pill (the logo's dark
  /// outlines need dark behind them — the pill, never the whole card).
  static Widget logo(
    BuildContext context, {
    double height = 72,
    double? width,
    EdgeInsets backdropPadding =
        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  }) {
    final image = Image.asset(
      kFantasyLogoAsset,
      height: height,
      width: width,
      fit: BoxFit.contain,
    );
    if (_isDark(context)) return image;
    return Container(
      key: const ValueKey('fantasy_logo_backdrop'),
      padding: backdropPadding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientTop, gradientBottom],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: image,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          logo(context),
          if (teamName != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    teamName!,
                    textAlign: TextAlign.center,
                    // Wraps onto further lines, never underlined, never
                    // truncated (house rules).
                    style: TextStyle(
                      color: foreground(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
                if (onEditTeamName != null) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    key: const ValueKey('fantasy_edit_team_name'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: onEditTeamName,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit,
                          size: 16, color: foregroundMuted(context)),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (subtitle != null) ...[
            SizedBox(height: teamName != null ? 4 : 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foregroundMuted(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (bottom != null) ...[
            const SizedBox(height: 14),
            Center(child: bottom!),
          ],
        ],
      ),
    );
  }
}
