// Dream Team of the Week (P6, spec §10/§13): the gameweek's top-scoring
// formation (1 GK + 2 DEF + 2 ATT from the live config) rendered on the
// golden court in read-only mini mode, with each player's week points under
// their name. Reads the SAME `DreamTeam/<gw>` node as the weekly news post,
// so an admin correction fixes both at once.
//
// HOME: the Leaderboards tab's own "Team of the week" segment (it sits beside
// Overall and Gameweek and is the ONLY content of that view — it used to
// float above both lists, which made switching them look like a no-op). The
// Dream Team is public, standings-adjacent celebration (same data family as
// the gameweek boards), while My Team is the private editing surface already
// stacked with gates (name prompt, moderation freeze, lock states) where a
// public showcase would routinely be hidden behind prompts.
//
// House rules: theme-safe both modes (the shared fantasy brand surface +
// accent), names wrap on the chips (court behavior), photos never gate
// content (initials fallback), week selection persists for the session
// (the market-sort precedent; the Leaderboards tab carries it to and from the
// Gameweek view). Renders nothing while no DreamTeam exists — the Leaderboards
// tab shows its own friendly line instead of building the card.
//
// Live everywhere (Task 6): the live gameweek's Team of the Week (the data
// layer's `live` overlay) carries the shared LIVE pill beside the title and the
// subline "Can still change until the last game ends." under it; stepping back
// to a settled week drops both. The court itself just refills in place.
//
// Share (owner follow-up): with a [DreamTeamCard.seasonLabel] the header
// carries a Share button that renders the week ON SCREEN as a branded story
// image (fantasy_share.dart — the same court + chips) and opens the share
// sheet.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/engine/fantasy_config.dart';
import 'package:infinite_sports_flutter/fantasy/hub/court_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_banner.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share_button.dart';
import 'package:infinite_sports_flutter/fantasy/hub/live_pill.dart';
import 'package:infinite_sports_flutter/fantasy/hub/squad_builder_logic.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';

/// The subline under the title while the week is still being played.
const String kDreamTeamLiveNote = 'Can still change until the last game ends.';

class DreamTeamCard extends StatefulWidget {
  const DreamTeamCard({
    super.key,
    required this.teams,
    required this.config,
    required this.players,
    this.onOpenPlayer,
    this.seasonLabel,
    this.shareImage,
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

  /// "Futsal Season 15" — the share image's season line. null = no Share
  /// button (the card is only shareable where the season is known).
  final String? seasonLabel;

  /// Test seam for the share sheet (null = the system sheet).
  final SharePng? shareImage;

  /// Session-persistent week selection (the leaderboard-chips precedent):
  /// swiping away and back lands where the fan left off.
  static int? sessionWeek;

  /// The week the card shows for these [weeks] (non-empty): the session
  /// selection while that week still exists, else the latest. ONE rule shared
  /// by the card and by the Leaderboards tab's Gameweek week-sync.
  static int resolveWeek(Iterable<int> weeks) {
    final latest = weeks.reduce((a, b) => a > b ? a : b);
    final selected = sessionWeek;
    return selected != null && weeks.contains(selected) ? selected : latest;
  }

  @override
  State<DreamTeamCard> createState() => _DreamTeamCardState();
}

class _DreamTeamCardState extends State<DreamTeamCard> {
  @override
  Widget build(BuildContext context) {
    final weeks = widget.teams.keys.toList()..sort();
    if (weeks.isEmpty) return const SizedBox.shrink();
    final selected = DreamTeamCard.resolveWeek(weeks);
    final team = widget.teams[selected]!;

    final accent = FantasyBanner.accent(context);
    final photoByName = {
      for (final p in widget.players)
        if (p.photoUrl != null) p.name: p.photoUrl,
    };
    // The 5 starter slots from the config formation (no bench — the court
    // hides its bench surface when none exist), shared with the share image.
    final court = dreamTeamCourt(widget.config, team);
    final seasonLabel = widget.seasonLabel;

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
                // The pill rides beside the title and drops under it when
                // the line is full (360 px with the share button).
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Team of the Week · GW$selected',
                      key: const ValueKey('dream_team_title'),
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: FantasyBanner.foreground(context),
                      ),
                    ),
                    if (team.live) const FantasyLivePill(),
                  ],
                ),
              ),
              if (seasonLabel != null)
                FantasyShareButton(
                  key: const ValueKey('dream_team_share'),
                  tooltip: 'Share Team of the Week',
                  // The week ON SCREEN (the chips can step back).
                  onShare: (buttonContext) => shareTeamOfWeekStory(
                    buttonContext,
                    week: selected,
                    seasonLabel: seasonLabel,
                    team: team,
                    config: widget.config,
                    photoUrlFor: (name) => photoByName[name],
                    share: widget.shareImage,
                  ),
                ),
            ],
          ),
          if (team.live)
            Padding(
              // Under the title (past the trophy icon).
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(
                kDreamTeamLiveNote,
                key: const ValueKey('dream_team_live_note'),
                softWrap: true,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  color: FantasyBanner.foregroundMuted(context),
                ),
              ),
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
            slots: court.slots,
            slotPicks: court.slotPicks,
            // Read-only mini mode: nothing editable, smaller chips, no
            // prices — position + week points tell the story. A chip tap
            // opens the player's profile (round 3).
            onSlotTap: null,
            onPlayerTap: widget.onOpenPlayer,
            showPrices: false,
            chipWidth: 78,
            chipAvatarSize: 44,
            weekPointsFor: (name) {
              final points = court.pointsByName[name];
              return points == null ? null : pointsText(points);
            },
            photoUrlFor: (name) => photoByName[name],
          ),
        ],
      ),
    );
  }
}
