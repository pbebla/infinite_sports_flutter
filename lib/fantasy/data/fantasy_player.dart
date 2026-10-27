// Fantasy market player (P3a Task 1) — one row of
// `Fantasy/<sport>/<season>/Players`, seeded by tool/seed_fantasy.dart and
// owner-edited in the Manager app later. The player's NAME is the id (it
// matches the league lineup name the scoring pipeline keys by).

import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';

class FantasyPlayer {
  const FantasyPlayer({
    required this.name,
    required this.position,
    required this.priceTenths,
    required this.eligible,
    required this.teamName,
  });

  /// Identity: the league lineup player name.
  final String name;
  final FantasyPosition position;

  /// Current price in $0.1M units (85 = $8.5M) — engine tenths math.
  final int priceTenths;

  /// Guests are false until promoted (spec §3) — visible nowhere in the
  /// market, never selectable.
  final bool eligible;
  final String teamName;

  /// Tolerant RTDB parse; null when the entry isn't usable (bad position
  /// string, non-map node) so callers can skip it.
  static FantasyPlayer? fromNode(String name, Object? node) {
    if (node is! Map) return null;
    final FantasyPosition position;
    try {
      position = FantasyPosition.parse(node['position']?.toString() ?? '');
    } on ArgumentError {
      return null;
    }
    final rawPrice = node['priceTenths'];
    return FantasyPlayer(
      name: name,
      position: position,
      priceTenths: rawPrice is num
          ? rawPrice.toInt()
          : int.tryParse(rawPrice?.toString() ?? '') ?? 0,
      eligible: node['eligible'] == true,
      teamName: node['teamName']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'position': position.db,
        'priceTenths': priceTenths,
        'eligible': eligible,
        'teamName': teamName,
      };
}
