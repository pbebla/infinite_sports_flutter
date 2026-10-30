// The Fantasy tab of the tabbed Infinite profile (round 3, spec §7): shown by
// ProfilePage only when [FantasyProfileSource] says this uid is a fantasy
// player and/or a fantasy manager of the current season (never on a limited
// profile). Two sections, in the profile's own Card look:
//
//   * Fantasy Player — price with this week's move, total pts, form, owned %,
//     the last six gameweeks' bars, and **Open in Fantasy** (the hub on its
//     Players tab, which then opens THIS player's profile);
//   * Fantasy Manager — the team name (a flagged one never shows), overall
//     rank + movement + points, and **View team** (the manager squad viewer;
//     its court chips open the fantasy player profile from outside the hub).
//
// House rules: one fade reveal (a skeleton until every feed has landed, then
// the content fades in once — never piece by piece); "—" / copy wherever the
// truth is "no data yet", never a made-up 0 or NaN; names wrap, never
// ellipsized or underlined; colours from the theme's colorScheme (the
// fantasy accent / up-down tones are the hub's brightness-aware pairs);
// the page keeps the tab alive so flipping tabs never replays the fade.

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_format.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart'
    show FantasyManager;
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_page.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_hub_route.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart'
    show movementDirection, movementLabel;
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart'
    show movementColor;
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart'
    show fantasyAccent;
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_logic.dart';
import 'package:infinite_sports_flutter/fantasy/profile/fantasy_player_profile_page.dart'
    show FantasyProfileOpener, openFantasyPlayerProfile;
import 'package:infinite_sports_flutter/fantasy/profile/profile_common.dart'
    show profileMoveColor;
import 'package:infinite_sports_flutter/fantasy/profile/profile_form_bars.dart';
import 'package:infinite_sports_flutter/profile/fantasy_profile_source.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Before the first finalized gameweek the Overall board is empty.
const String kFantasyRankPendingCopy = 'Ranking starts after Gameweek 1';

/// The headline when the team name is flagged / blank (a flagged name is
/// never shown publicly).
const String kFantasyUnnamedTeam = 'Unnamed team';

class FantasyProfileTab extends StatefulWidget {
  const FantasyProfileTab({
    super.key,
    required this.source,
    this.personName = '',
  });

  final FantasyProfileSource source;

  /// The profile owner's real name (the squad viewer's title falls back to it
  /// when the team name is flagged — the leaderboard's own fallback).
  final String personName;

  @override
  State<FantasyProfileTab> createState() => _FantasyProfileTabState();
}

class _FantasyProfileTabState extends State<FantasyProfileTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: widget.source,
      builder: (context, _) {
        final source = widget.source;
        final Widget body = source.contentReady
            ? _FantasyContent(
                key: const ValueKey('fantasy_tab_ready'),
                source: source,
                personName: widget.personName,
              )
            : _FantasySkeleton(
                key: const ValueKey('fantasy_tab_skeleton'),
                player: source.access?.player != null,
                manager: source.access?.manager != null,
              );
        // Single fade reveal once every feed has landed.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: body,
        );
      },
    );
  }
}

// ── Layout helpers ──────────────────────────────────────────────────────────

const EdgeInsets _cardMargin = EdgeInsets.fromLTRB(16, 16, 16, 0);
const EdgeInsets _cardPadding =
    EdgeInsets.symmetric(horizontal: 16, vertical: 12);

class _FantasySkeleton extends StatelessWidget {
  const _FantasySkeleton(
      {super.key, required this.player, required this.manager});

  final bool player;
  final bool manager;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (player || !manager)
          const Padding(
            padding: _cardMargin,
            child: SkeletonBox(width: double.infinity, height: 250, radius: 12),
          ),
        if (manager)
          const Padding(
            padding: _cardMargin,
            child: SkeletonBox(width: double.infinity, height: 160, radius: 12),
          ),
      ],
    );
  }
}

class _FantasyContent extends StatelessWidget {
  const _FantasyContent({
    super.key,
    required this.source,
    required this.personName,
  });

  final FantasyProfileSource source;
  final String personName;

  @override
  Widget build(BuildContext context) {
    final access = source.access;
    return ListView(
      // paddingOf().bottom carries the floating GlassNavBar's height when
      // this page sits inside the extendBody home shell (same as ProfileTab).
      padding:
          EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (access?.player != null) _PlayerCard(source: source),
        if (access?.manager != null)
          _ManagerCard(
            source: source,
            manager: access!.manager!,
            personName: personName,
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
    );
  }
}

/// One "value over label" strip cell; "—" values stay muted-looking by
/// content alone (the label says what is missing).
class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.label,
    required this.valueKey,
    this.valueColor,
  });

  final String value;
  final String label;
  final String valueKey;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            key: ValueKey(valueKey),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _divider(BuildContext context) => VerticalDivider(
      width: 1,
      thickness: 1,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );

/// A muted one-liner for "no data yet" states.
class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        softWrap: true,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

// ── Player section ──────────────────────────────────────────────────────────

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.source});

  final FantasyProfileSource source;

  @override
  Widget build(BuildContext context) {
    final model = source.playerModel!;
    final player = model.player;
    final scheme = Theme.of(context).colorScheme;
    final teamLine = [
      if (player.teamName.trim().isNotEmpty) player.teamName.trim(),
      positionLabel(player.position),
    ].join(' · ');
    final move = model.moveText;

    return Card(
      key: const ValueKey('fantasy_player_card'),
      margin: _cardMargin,
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('Fantasy Player'),
            const SizedBox(height: 10),
            Text(
              teamLine,
              key: const ValueKey('fantasy_player_line'),
              softWrap: true,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    // Wide enough that "▲ $0.5M this week" fits one line at
                    // 360px.
                    flex: 17,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            formatMoneyTenths(model.priceTenths),
                            key: const ValueKey('fantasy_price'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: fantasyAccent(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Price',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (move != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              move,
                              key: const ValueKey('fantasy_move'),
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: profileMoveColor(
                                    context, model.latestMoveTenths),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _divider(context),
                  Expanded(
                    flex: 10,
                    child: _Cell(
                        value: model.totalPointsText,
                        label: 'Total pts',
                        valueKey: 'fantasy_total'),
                  ),
                  _divider(context),
                  Expanded(
                    flex: 9,
                    child: _Cell(
                        value: model.formText,
                        label: 'Form',
                        valueKey: 'fantasy_form'),
                  ),
                  _divider(context),
                  Expanded(
                    flex: 9,
                    child: _Cell(
                        value: model.ownedText,
                        label: 'Owned',
                        valueKey: 'fantasy_owned'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Recent form'),
            const SizedBox(height: 8),
            if (model.formBars.isEmpty)
              const _Note(kPointsStartCopy,
                  key: ValueKey('fantasy_points_start'))
            else
              FantasyFormBars(bars: model.formBars),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('fantasy_open_in_fantasy'),
                onPressed: () => _openInFantasy(context, source, player),
                child: const Text('Open in Fantasy'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Open in Fantasy": the hub on its Players tab, which then pushes THIS
/// player's profile (with the hub's shared draft) once it is ready —
/// `fantasyRouteForPlayer` + `fantasyHubPageRoute`, the same helpers the
/// player-profile page's own button uses.
void _openInFantasy(
    BuildContext context, FantasyProfileSource source, FantasyPlayer player) {
  final access = source.access;
  if (access == null) return;
  final route = fantasyRouteForPlayer(
    sport: access.sport,
    season: access.season,
    playerName: player.name,
  );
  final open = source.seams.openInFantasy;
  if (open != null) {
    open(context, route);
    return;
  }
  Navigator.push(context, fantasyHubPageRoute(route));
}

// ── Manager section ─────────────────────────────────────────────────────────

class _ManagerCard extends StatelessWidget {
  const _ManagerCard({
    required this.source,
    required this.manager,
    required this.personName,
  });

  final FantasyProfileSource source;
  final FantasyManager manager;
  final String personName;

  @override
  Widget build(BuildContext context) {
    final teamName = visibleTeamName(source.uid, manager);
    final standing = source.standing ?? FantasyManagerStanding.unranked;
    final direction = movementDirection(standing.movement);

    return Card(
      key: const ValueKey('fantasy_manager_card'),
      margin: _cardMargin,
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('Fantasy Manager'),
            const SizedBox(height: 10),
            Text(
              teamName ?? kFantasyUnnamedTeam,
              key: const ValueKey('fantasy_team_name'),
              softWrap: true,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (standing.ranked)
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _Cell(
                          value: '#${standing.rank}',
                          label: 'Overall rank',
                          valueKey: 'fantasy_rank'),
                    ),
                    _divider(context),
                    Expanded(
                      child: _Cell(
                        value: movementLabel(standing.movement),
                        label: 'Movement',
                        valueKey: 'fantasy_movement',
                        valueColor: movementColor(context, direction),
                      ),
                    ),
                    _divider(context),
                    Expanded(
                      child: _Cell(
                          value: '${standing.points ?? '—'}',
                          label: 'Points',
                          valueKey: 'fantasy_points'),
                    ),
                  ],
                ),
              )
            else
              const _Note(kFantasyRankPendingCopy,
                  key: ValueKey('fantasy_rank_pending')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('fantasy_view_team'),
                onPressed: () =>
                    _viewTeam(context, source, teamName, personName),
                child: const Text('View team'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "View team": the manager squad viewer for this uid. The viewer's title is
/// the visible team name, else the profile owner's name, else "Unnamed
/// manager" (`LeaderboardRowData.viewerTitle`'s own fallback — a flagged name
/// never reaches it). On his OWN profile it shows his live squad; a court
/// chip opens that player's fantasy profile from outside the hub.
void _viewTeam(BuildContext context, FantasyProfileSource source,
    String? teamName, String personName) {
  final access = source.access;
  final config = source.config;
  if (access == null || config == null) return;
  final seams = source.seams;
  final sport = access.sport;
  final season = access.season;
  final isSelf = source.isSelf;
  final title = teamName ??
      (personName.trim().isNotEmpty ? personName.trim() : 'Unnamed manager');
  final live = isSelf
      ? (seams.viewerSquadStates ??
          FantasyService.watchMySquad(sport, season, source.uid))
      : null;
  final FantasyProfileOpener opener =
      seams.profileOpener ?? openFantasyPlayerProfile;
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (viewerContext) => ManagerSquadViewerPage(
        sport: sport,
        season: season,
        uid: source.uid,
        title: title,
        isSelf: isSelf,
        config: config,
        players: source.players,
        gameweeks: source.gameweeks,
        squadStates: live,
        publishedStates: seams.viewerPublishedStates,
        historyStates: seams.viewerHistoryStates,
        onOpenPlayer: (name) => opener(
          viewerContext,
          sport: sport,
          season: season,
          playerName: name,
          fromOutsideHub: true,
        ),
      ),
    ),
  );
}
