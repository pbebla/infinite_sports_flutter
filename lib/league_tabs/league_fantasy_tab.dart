// The league page's Fantasy tab (P3a Task 5, spec §10): the hub entry card.
// The tab itself only exists while Fantasy/<sport>/<season>/Config exists
// (stream-gated in LeagueDetailPage, so it pops in live the moment the
// season is seeded).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';

class LeagueFantasyTab extends StatelessWidget {
  const LeagueFantasyTab({
    super.key,
    required this.sport,
    required this.season,
    this.onEnter,
  });

  final String sport;
  final String season;

  /// Test seam — production leaves it null and pushes the hub.
  final VoidCallback? onEnter;

  void _openHub(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FantasyHubPage(sport: sport, season: season),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        FantasyBanner(
          subtitle: 'Fantasy is live for $sport Season $season — build your '
              'squad of real league players.',
          bottom: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onEnter ?? () => _openHub(context),
              style: FilledButton.styleFrom(
                backgroundColor: TournamentColors.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: const Text('Enter Infinite Fantasy'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _FeatureRow(
          icon: Icons.groups,
          title: 'Build your seven',
          body: 'One keeper, two defenders, two attackers and a two-player '
              'bench — all within budget.',
          scheme: scheme,
        ),
        _FeatureRow(
          icon: Icons.military_tech,
          title: 'Captain for double points',
          body: 'Armband one starter each week; the vice-captain covers a '
              'no-show.',
          scheme: scheme,
        ),
        _FeatureRow(
          icon: Icons.bolt,
          title: 'Points from real games',
          body: 'Goals, assists, saves and clean sheets on court score for '
              'you, live.',
          scheme: scheme,
        ),
        _FeatureRow(
          icon: Icons.menu_book,
          title: 'Every rule in one place',
          body: 'The hub\'s Rules tab explains scoring, deadlines, transfers '
              'and chips.',
          scheme: scheme,
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.scheme,
  });

  final IconData icon;
  final String title;
  final String body;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
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
