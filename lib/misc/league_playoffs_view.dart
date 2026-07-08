// Pure view-model for the league `Playoffs` node (L3 schema:
// {Format, ThirdPlace, Slots: {sf1: {team1Seed, team2Seed,
// gameRef: {date, index}, winnerTo, loserTo?}}, Champion}) + assembly of
// the match list the reused tournament KnockoutTab renders.
// League Experience P2. NO Flutter/Firebase imports.

import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// One bracket slot from `Playoffs/Slots` ('qf1', 'sf2', 'f1', 'tp1').
class LeaguePlayoffSlot {
  final String key;
  final int? team1Seed;
  final int? team2Seed;
  final String? dateKey;
  final int? gameIndex;

  const LeaguePlayoffSlot({
    required this.key,
    this.team1Seed,
    this.team2Seed,
    this.dateKey,
    this.gameIndex,
  });

  /// Position within its round: the slot key's trailing number ('qf3' → 3).
  int get position => int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// The league game id this slot points at (null when gameRef is absent).
  String? get gameId => (dateKey == null || gameIndex == null)
      ? null
      : leagueGameId(dateKey!, gameIndex!);
}

/// Parsed `/{sport}/{season}/Playoffs` node.
class LeaguePlayoffs {
  final int format; // 4 or 8
  final bool thirdPlace;
  final String champion; // '' until the final resolves
  final List<LeaguePlayoffSlot> slots;

  const LeaguePlayoffs({
    required this.format,
    required this.thirdPlace,
    required this.champion,
    required this.slots,
  });

  static LeaguePlayoffs? fromNode(dynamic raw) {
    if (raw is! Map) return null;
    final slots = <LeaguePlayoffSlot>[];
    final rawSlots = raw['Slots'];
    if (rawSlots is Map) {
      rawSlots.forEach((k, v) {
        if (v is! Map) return;
        final ref = v['gameRef'];
        slots.add(LeaguePlayoffSlot(
          key: k.toString(),
          team1Seed:
              v['team1Seed'] == null ? null : parseInt(v['team1Seed']),
          team2Seed:
              v['team2Seed'] == null ? null : parseInt(v['team2Seed']),
          dateKey: (ref is Map) ? ref['date']?.toString() : null,
          gameIndex: (ref is Map && ref['index'] != null)
              ? parseInt(ref['index'])
              : null,
        ));
      });
    }
    return LeaguePlayoffs(
      format: parseInt(raw['Format'], defaultValue: 4),
      thirdPlace: parseBool(raw['ThirdPlace']),
      champion: (raw['Champion'] ?? '').toString(),
      slots: slots,
    );
  }
}

/// The bracket the KnockoutTab renders: all knockout-staged matches
/// (friendlies and regular-season games drop out via TournamentStage), with
/// bracketPosition — and round-1 seeds — overridden from the Playoffs slots
/// whenever a gameRef points at the match. That keeps connector pairing
/// true to the Manager's bracket wiring even when games move between dates.
/// Staged matches with no slot (manual insertions) still render, keeping
/// their in-date index as position.
List<TournamentMatch> leagueBracketMatches(
    LeaguePlayoffs? playoffs, List<TournamentMatch> matches) {
  final staged = matches
      .where((m) => TournamentStage.fromString(m.stage).isKnockout)
      .toList();
  if (playoffs == null || playoffs.slots.isEmpty) return staged;

  final slotByGameId = <String, LeaguePlayoffSlot>{};
  for (final s in playoffs.slots) {
    final id = s.gameId;
    if (id != null) slotByGameId[id] = s;
  }

  return [
    for (final m in staged)
      slotByGameId.containsKey(m.id)
          ? _withBracketSlot(m, slotByGameId[m.id]!)
          : m,
  ];
}

/// TournamentMatch has no copyWith — rebuild with the slot's position/seeds.
TournamentMatch _withBracketSlot(TournamentMatch m, LeaguePlayoffSlot slot) {
  return TournamentMatch(
    id: m.id,
    stage: m.stage,
    label: m.label,
    date: m.date,
    time: m.time,
    team1Id: m.team1Id,
    team2Id: m.team2Id,
    team1Score: m.team1Score,
    team2Score: m.team2Score,
    status: m.status,
    clock: m.clock,
    team1Activity: m.team1Activity,
    team2Activity: m.team2Activity,
    link: m.link,
    matchLocation: m.matchLocation,
    locationInfo: m.locationInfo,
    team1Keeper: m.team1Keeper,
    team2Keeper: m.team2Keeper,
    bracketPosition: slot.position,
    team1Seed: slot.team1Seed,
    team2Seed: slot.team2Seed,
    team1Source: m.team1Source,
    team2Source: m.team2Source,
  );
}
