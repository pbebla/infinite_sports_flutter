// The Infinite Fantasy banner card (P3a Task 2, centered layout from the
// owner's P3a feedback round): a dark gradient surface in BOTH themes
// carrying the gold wordmark — the house rule for the fantasy brand (plan
// hard gates). Reused by the hub header and the league page's Fantasy entry
// card. Everything stacks CENTERED: logo, then the manager's team name once
// set, then the season line, then the bottom row (deadline chip / button).

import 'package:flutter/material.dart';

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

  /// Optional row pinned under the text (e.g. the deadline chip or the entry
  /// button), rendered centered.
  final Widget? bottom;

  /// The manager's fantasy team name — shown big under the logo once set
  /// (P3a Task 3). Wraps rather than truncates (house rule: names wrap).
  final String? teamName;

  /// Rename affordance: a small edit icon next to [teamName]. Hidden while
  /// null (e.g. the league entry card shows no name at all).
  final VoidCallback? onEditTeamName;

  /// Deliberately NOT theme-derived: the banner stays a dark, subtly-lit
  /// card in light mode too, so the gold wordmark always sits on dark.
  static const Color gradientTop = Color(0xFF15171E);
  static const Color gradientBottom = Color(0xFF262A38);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientTop, gradientBottom],
        ),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/fantasy/fantasy_logo.png',
            height: 72,
            fit: BoxFit.contain,
          ),
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
                    style: const TextStyle(
                      color: Colors.white,
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
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child:
                          Icon(Icons.edit, size: 16, color: Colors.white70),
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
              style: const TextStyle(
                color: Colors.white70,
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
