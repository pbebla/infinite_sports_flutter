// Dream Team of the Week (P6, spec §10/§13): the gameweek's top-scoring
// formation (1 GK + 2 DEF + 2 ATT from the live config) rendered on the
// golden court in read-only mini mode, with each player's week points under
// their name. Reads the SAME `DreamTeam/<gw>` node as the weekly news post,
// so an admin correction fixes both at once.
//
// HOME: the top of the Leaderboards tab's Overall and Gameweek scrolls —
// the Dream Team is public, standings-adjacent celebration (same data
// family as the gameweek boards), while My Team is the private editing
// surface already stacked with gates (name prompt, moderation freeze, lock
// states) where a public showcase would routinely be hidden behind prompts.
//
// House rules: theme-safe both modes (the shared fantasy brand surface +
// accent), names wrap on the chips (court behavior), photos never gate
// content (initials fallback), week selection persists for the session
// (the market-sort precedent). Hidden entirely while no DreamTeam exists —
// the Leaderboards tab simply doesn't build it.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';

class DreamTeamCard extends StatefulWidget {
  const DreamTeamCard({
    super.key,
    required this.teams,
    required this.config,
    required this.players,
    this.onOpenPlayer,
  });

  /// gameweek -> team, from FantasyService.watchDreamTeams. Callers only
  /// build this card when it's non-empty.
  final Map<int, FantasyDreamTeam> teams;
  final FantasyConfig config;

  /// The live market — photo source per dream player (initials fallback).
  final List<FantasyPlayer> players;

  /// Round 3: tapping a Team of the Week player opens his fantasy profile
  /// (the hub's one opener). null = chips inert.
  final void Function(String playerName)? onOpenPlayer;

  /// Session-persistent week selection (the leaderboard-chips precedent):
  /// swiping away and back lands where the fan left off.
  static int? sessionWeek;

  @override
  State<DreamTeamCard> createState() => _DreamTeamCardState();
}

class _DreamTeamCardState extends State<DreamTeamCard> {
  @override
  Widget build(BuildContext context) {
    final weeks = widget.teams.keys.toList()..sort();
    if (weeks.isEmpty) return const SizedBox.shrink();
    final latest = weeks.last;
    var selected = DreamTeamCard.sessionWeek ?? latest;
    if (!widget.teams.containsKey(selected)) selected = latest;
    final team = widget.teams[selected]!;

    final accent = FantasyBanner.accent(context);
    final photoByName = {
      for (final p in widget.players)
        if (p.photoUrl != null) p.name: p.photoUrl,
    };
    final pointsByName = {
      for (final p in team.players) p.name: p.points,
    };

    // 5 starter slots straight from the config formation (no bench — the
    // court hides its bench surface when none exist); dream players land in
    // the first empty slot of their position, extras from a config shrink
    // are dropped.
    final slots = [
      for (final slot in buildSlots(widget.config))
        if (!slot.bench) slot,
    ];
    final slotPicks = List<SquadPick?>.filled(slots.length, null);
    for (final player in team.players) {
      for (var i = 0; i < slots.length; i++) {
        if (slotPicks[i] == null && slots[i].position == player.position) {
          slotPicks[i] = SquadPick(
            playerId: player.name,
            position: player.position,
            priceTenths: 0, // hidden: the court renders with showPrices false
          );
          break;
        }
      }
    }

    return Container(
      key: const ValueKey('dream_team_card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: FantasyBanner.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, size: 20, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Team of the Week · GW$selected',
                  key: const ValueKey('dream_team_title'),
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: FantasyBanner.foreground(context),
                  ),
                ),
              ),
            ],
          ),
          if (weeks.length > 1) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final week in weeks) ...[
                    ChoiceChip(
                      key: ValueKey('dream_week_$week'),
                      label: Text('GW$week'),
                      visualDensity: VisualDensity.compact,
                      selected: selected == week,
                      onSelected: (_) => setState(
                          () => DreamTeamCard.sessionWeek = week),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          FantasyCourtView(
            config: widget.config,
            slots: slots,
            slotPicks: slotPicks,
            // Read-only mini mode: nothing editable, smaller chips, no
            // prices — position + week points tell the story. A chip tap
            // opens the player's profile (round 3).
            onSlotTap: null,
            onPlayerTap: widget.onOpenPlayer,
            showPrices: false,
            chipWidth: 78,
            chipAvatarSize: 44,
            weekPointsFor: (name) {
              final points = pointsByName[name];
              return points == null ? null : '$points pts';
            },
            photoUrlFor: (name) => photoByName[name],
          ),
        ],
      ),
    );
  }
}
