// Tagged players under a fantasy news post (News desk 2.0, spec 2026-10-28
// §4.2). The post carries SNAPSHOTS (NewsPlayerCard) taken when it was
// built, so this renders with no listeners of its own:
//
// - 1–2 players → full cards: photo/initials, name, "POS · team · $15.0M"
//   with the latest price move (+$0.5M / −$0.5M), four stat tiles (GW pts ·
//   Goals · Assists · Owned — "–" when unknown) and a View player button.
// - 3+ players (Team of the week) → compact rows: photo, name, position
//   chip, week points. A row tap opens the player too.
//
// "View player" calls the hub's onOpenPlayer(name), which opens the full
// fantasy player profile (the same page the Players tab opens).
//
// House rules: colorScheme in both themes (the price-move colors are a
// brightness-conditional pair readable on these surfaces); names WRAP,
// never ellipsized or underlined; photos never gate text (FantasyAvatar:
// initials instantly, 200ms photo fade, zero under reduced motion).

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/hub/market_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';

/// Price-move text color: a deeper green on light surfaces and a lighter
/// green on dark ones (≥4.5:1 on the news card in both), error for drops.
Color newsPriceMoveColor(BuildContext context, {required bool up}) {
  if (!up) return fantasyDownRed(context);
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF6FD08C)
      : const Color(0xFF17692F);
}

/// The players block under a post's body: nothing for an untagged post,
/// full cards for 1–2, compact rows for 3+.
class NewsPostPlayers extends StatelessWidget {
  const NewsPostPlayers({
    super.key,
    required this.players,
    this.onOpenPlayer,
  });

  final List<NewsPlayerCard> players;
  final void Function(String name)? onOpenPlayer;

  /// Up to this many players render as full cards; more → compact rows.
  static const int fullCardLimit = 2;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    if (players.length <= fullCardLimit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            NewsPlayerCardView(card: players[i], onOpenPlayer: onOpenPlayer),
          ],
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < players.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            NewsPlayerCompactRow(card: players[i], onOpenPlayer: onOpenPlayer),
          ],
        ],
      ),
    );
  }
}

/// One full tagged-player card (1–2 player posts).
class NewsPlayerCardView extends StatelessWidget {
  const NewsPlayerCardView({
    super.key,
    required this.card,
    this.onOpenPlayer,
  });

  final NewsPlayerCard card;
  final void Function(String name)? onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = card.priceDeltaTenths;
    final pct = card.ownershipPct;
    final tiles = <(String, String, String)>[
      ('gw', card.gw == null ? 'GW pts' : 'GW${card.gw} pts',
          card.gwPoints?.toString() ?? '–'),
      ('goals', 'Goals', '${card.goals}'),
      ('assists', 'Assists', '${card.assists}'),
      ('owned', 'Owned', pct == null ? '–' : '${pct.round()}%'),
    ];
    return Container(
      key: ValueKey('news_player_card_${card.name}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FantasyAvatar(name: card.name, photoUrl: card.photoUrl, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      // Wraps, never ellipsized or underlined (house rules).
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        text: [
                          card.position.db,
                          if (card.team.isNotEmpty) card.team,
                          formatMoneyTenths(card.priceTenths),
                        ].join(' · '),
                        children: [
                          if (delta != null && delta != 0)
                            TextSpan(
                              text: '  ${formatPriceDelta(delta)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: newsPriceMoveColor(context,
                                    up: delta > 0),
                              ),
                            ),
                        ],
                      ),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _StatTile(
                    valueKey: ValueKey('news_stat_${card.name}_${tiles[i].$1}'),
                    label: tiles[i].$2,
                    value: tiles[i].$3,
                  ),
                ),
              ],
            ],
          ),
          if (onOpenPlayer != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(
              key: ValueKey('news_view_player_${card.name}'),
              onPressed: () => onOpenPlayer!(card.name),
              child: const Text('View player'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.valueKey,
    required this.label,
    required this.value,
  });

  final Key valueKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            key: valueKey,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact row (3+ player posts): photo, name, position chip, week
/// points. Tappable when the hub provides onOpenPlayer.
class NewsPlayerCompactRow extends StatelessWidget {
  const NewsPlayerCompactRow({
    super.key,
    required this.card,
    this.onOpenPlayer,
  });

  final NewsPlayerCard card;
  final void Function(String name)? onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final points = card.gwPoints;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          FantasyAvatar(name: card.name, photoUrl: card.photoUrl, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card.name,
              // Wraps, never ellipsized or underlined (house rules).
              softWrap: true,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: Text(
              card.position.db,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            points == null ? '–' : '$points pts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          if (onOpenPlayer != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ],
      ),
    );
    return Material(
      key: ValueKey('news_player_row_${card.name}'),
      type: MaterialType.transparency,
      child: onOpenPlayer == null
          ? row
          : InkWell(onTap: () => onOpenPlayer!(card.name), child: row),
    );
  }
}
