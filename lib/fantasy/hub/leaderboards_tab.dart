// The hub's Leaderboards tab (P3d, spec §9/§10; redesigned in round 3, spec
// §6): Overall / Gameweek scopes. Both render plain ranked rows (no podium) —
// gold rank, a movement cell on Overall only, the manager's real name with the
// team name under it — with the signed-in manager's row pinned when scrolled
// away; the Gameweek scope adds week chips (1..N from the real schedule's
// gameweeks). Tapping ANY manager opens their squad viewer (spec §9
// transparency).
//
// My Leagues (the mini-league create/join/share surface) is BUILT but hidden
// behind [kShowMiniLeagues]: no segment, no MiniLeagues subscription, and it
// no longer gates the reveal. Flip the constant to bring it back.
//
// Data: the functions-written Leaderboards node (friendly empty state until
// P4 writes it), the whole Managers node for team names, PublicProfiles
// (once, session-cached) for real names + avatar photos.
//
// House rules: streams/once only; SINGLE fade reveal (skeleton until the
// leaderboards+managers+dream-teams streams and the profiles read have ALL
// landed); session caches make revisits instant; theme-safe both modes;
// names wrap, never underlined; glass-navbar clearance; scope + selected
// week persist for the session (the market-sort precedent).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

enum LeaderboardScope { overall, gameweek, leagues }

/// Owner decision (round 3): mini-leagues are hidden for now. The code, rules
/// and data all stay — flip to true to restore the "My Leagues" segment, its
/// MiniLeagues subscription and its place in the reveal gate.
const bool kShowMiniLeagues = false;

/// The Leaderboards tab's test seams as ONE bundle, so the hub can forward
/// them to the tab it mounts (the hub test mounts the real tab with fake feeds
/// and proves its player-profile forwarding). null fields = the real feeds.
class FantasyLeaderboardsFeeds {
  const FantasyLeaderboardsFeeds({
    this.leaderboardsStates,
    this.managersStates,
    this.miniLeaguesStates,
    this.dreamTeamsStates,
    this.loadProfiles,
    this.selfUidOverride,
    this.viewerPublishedStates,
    this.viewerHistoryStates,
  });

  final Stream<FantasyLeaderboards>? leaderboardsStates;
  final Stream<Map<String, FantasyManager>>? managersStates;
  final Stream<List<FantasyMiniLeague>>? miniLeaguesStates;
  final Stream<Map<int, FantasyDreamTeam>>? dreamTeamsStates;
  final Future<Map<String, PublicProfile>> Function()? loadProfiles;
  final String? selfUidOverride;

  /// The squad viewer's PublishedPicks / History feeds (the tab's default
  /// viewer builder hands them to ManagerSquadViewerPage).
  final Stream<Map<int, FantasySquad>>? viewerPublishedStates;
  final Stream<Map<int, FantasySquad>>? viewerHistoryStates;
}

class FantasyLeaderboardsTab extends StatefulWidget {
  const FantasyLeaderboardsTab({
    super.key,
    required this.sport,
    required this.season,
    required this.configState,
    required this.players,
    required this.gameweeks,
    required this.squadStates,
    this.initialSquad,
    this.leaderboardsStates,
    this.managersStates,
    this.miniLeaguesStates,
    this.dreamTeamsStates,
    this.loadProfiles,
    this.selfUidOverride,
    this.createLeague,
    this.joinLeague,
    this.copyText,
    this.shareText,
    this.readClipboard,
    this.codeGenerator,
    this.squadViewerBuilder,
    this.nowUtc,
    this.onOpenPlayer,
    this.viewerPublishedStates,
    this.viewerHistoryStates,
  });

  final String sport;
  final String season;
  final FantasyConfigState configState;

  /// The live market — the squad viewer's photo source per pick.
  final List<FantasyPlayer> players;
  final List<Gameweek> gameweeks;

  /// The viewer's OWN live squad (re-listen-safe hub broadcast) + latest
  /// value — forwarded to the squad viewer for the self row (spec §9).
  final Stream<FantasySquad?> squadStates;
  final FantasySquad? initialSquad;

  /// Test seams — null = the real FantasyService / PublicProfiles reads.
  final Stream<FantasyLeaderboards>? leaderboardsStates;
  final Stream<Map<String, FantasyManager>>? managersStates;
  final Stream<List<FantasyMiniLeague>>? miniLeaguesStates;
  final Stream<Map<int, FantasyDreamTeam>>? dreamTeamsStates;
  final Future<Map<String, PublicProfile>> Function()? loadProfiles;
  final String? selfUidOverride;
  final Future<void> Function(String name, String code)? createLeague;
  final Future<void> Function(String leagueId)? joinLeague;
  final void Function(String text)? copyText;
  final void Function(String text)? shareText;
  final Future<String?> Function()? readClipboard;
  final String Function()? codeGenerator;
  final Widget Function(LeaderboardRowData row)? squadViewerBuilder;
  final DateTime Function()? nowUtc;

  /// The hub's one player-profile opener (round 3): Team of the Week chips
  /// and the squad viewer's court chips open a player's fantasy profile
  /// with the hub's shared draft. null = those chips stay inert.
  final void Function(String playerName)? onOpenPlayer;

  /// Test seams for the DEFAULT squad viewer (ignored when
  /// [squadViewerBuilder] is given): its PublishedPicks / History feeds.
  final Stream<Map<int, FantasySquad>>? viewerPublishedStates;
  final Stream<Map<int, FantasySquad>>? viewerHistoryStates;

  /// Session-persistent scope + gameweek selection (the market-sort
  /// precedent): swiping away and back lands where the manager left off.
  static LeaderboardScope sessionScope = LeaderboardScope.overall;
  static int? sessionWeek;

  /// Session cache for the PublicProfiles fallback read (a once(), not a
  /// stream — names/photos only; an empty result retries on next mount).
  static Future<Map<String, PublicProfile>>? profilesSession;

  @override
  State<FantasyLeaderboardsTab> createState() => _FantasyLeaderboardsTabState();
}

class _FantasyLeaderboardsTabState extends State<FantasyLeaderboardsTab> {
  FantasyLeaderboards? _boards;
  Map<String, FantasyManager>? _managers;
  List<FantasyMiniLeague>? _leagues;
  Map<String, PublicProfile>? _profiles;
  Map<int, FantasyDreamTeam>? _dreamTeams;

  StreamSubscription<FantasyLeaderboards>? _boardsSub;
  StreamSubscription<Map<String, FantasyManager>>? _managersSub;
  StreamSubscription<List<FantasyMiniLeague>>? _leaguesSub;
  StreamSubscription<Map<int, FantasyDreamTeam>>? _dreamTeamsSub;

  // Best-effort (utility.dart convention): widget tests never touch
  // FirebaseAuth — a missing seam degrades to "signed out", not a throw.
  String get _selfUid {
    final override = widget.selfUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _boardsSub = (widget.leaderboardsStates ??
            FantasyService.watchLeaderboards(widget.sport, widget.season))
        .listen((boards) {
      if (mounted) setState(() => _boards = boards);
    });
    _managersSub = (widget.managersStates ??
            FantasyService.watchManagers(widget.sport, widget.season))
        .listen((managers) {
      if (mounted) setState(() => _managers = managers);
    });
    if (kShowMiniLeagues) {
      _leaguesSub = (widget.miniLeaguesStates ??
              FantasyService.watchMiniLeagues(widget.sport, widget.season))
          .listen((leagues) {
        if (mounted) setState(() => _leagues = leagues);
      });
    }
    _dreamTeamsSub = (widget.dreamTeamsStates ??
            FantasyService.watchDreamTeams(widget.sport, widget.season))
        .listen((teams) {
      if (mounted) setState(() => _dreamTeams = teams);
    });
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final load = widget.loadProfiles;
    Map<String, PublicProfile> profiles;
    if (load != null) {
      profiles = await load();
    } else {
      final future =
          FantasyLeaderboardsTab.profilesSession ??= PublicProfiles.getAllOnce();
      profiles = await future;
      // A transiently-failed (empty) read shouldn't be cached for the whole
      // session — let the next mount retry.
      if (profiles.isEmpty) FantasyLeaderboardsTab.profilesSession = null;
    }
    if (mounted) setState(() => _profiles = profiles);
  }

  @override
  void dispose() {
    _boardsSub?.cancel();
    _managersSub?.cancel();
    _leaguesSub?.cancel();
    _dreamTeamsSub?.cancel();
    super.dispose();
  }

  bool get _ready =>
      _boards != null &&
      _managers != null &&
      (!kShowMiniLeagues || _leagues != null) &&
      _profiles != null &&
      _dreamTeams != null;

  /// Dream Team of the Week (P6): the top of the Overall and Gameweek
  /// scrolls — see dream_team_card.dart's header for why it lives here and
  /// not on My Team. null while no DreamTeam node exists (hidden entirely).
  Widget? _dreamTeamCard() {
    final teams = _dreamTeams;
    if (teams == null || teams.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: DreamTeamCard(
        teams: teams,
        config: widget.configState.config,
        players: widget.players,
        onOpenPlayer: widget.onOpenPlayer,
      ),
    );
  }

  void _openManager(LeaderboardRowData row) {
    final builder = widget.squadViewerBuilder ??
        (row) => ManagerSquadViewerPage(
              sport: widget.sport,
              season: widget.season,
              uid: row.uid,
              title: row.viewerTitle,
              isSelf: row.isSelf,
              config: widget.configState.config,
              players: widget.players,
              gameweeks: widget.gameweeks,
              squadStates: row.isSelf ? widget.squadStates : null,
              initialSquad: row.isSelf ? widget.initialSquad : null,
              publishedStates: widget.viewerPublishedStates,
              historyStates: widget.viewerHistoryStates,
              nowUtc: widget.nowUtc,
              onOpenPlayer: widget.onOpenPlayer,
            );
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => builder(row)));
  }

  /// The scope actually shown: a My Leagues scope restored from the session
  /// (it is a static) falls back to Overall while mini-leagues are hidden.
  LeaderboardScope get _scope {
    final scope = FantasyLeaderboardsTab.sessionScope;
    return !kShowMiniLeagues && scope == LeaderboardScope.leagues
        ? LeaderboardScope.overall
        : scope;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (!_ready) {
      body = const _LeaderboardsSkeleton(key: ValueKey('leaderboards_skeleton'));
    } else {
      body = _content(context);
    }
    // Single fade reveal once every source has landed.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: body,
    );
  }

  Widget _content(BuildContext context) {
    final scope = _scope;
    return Column(
      key: const ValueKey('leaderboards_ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SegmentedButton<LeaderboardScope>(
            key: const ValueKey('leaderboard_scope'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              const ButtonSegment(
                  value: LeaderboardScope.overall, label: Text('Overall')),
              const ButtonSegment(
                  value: LeaderboardScope.gameweek, label: Text('Gameweek')),
              if (kShowMiniLeagues)
                const ButtonSegment(
                    value: LeaderboardScope.leagues,
                    label: Text('My Leagues')),
            ],
            selected: {scope},
            onSelectionChanged: (s) => setState(
                () => FantasyLeaderboardsTab.sessionScope = s.first),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: switch (scope) {
            LeaderboardScope.overall => _overallBody(),
            LeaderboardScope.gameweek => _gameweekBody(),
            LeaderboardScope.leagues => _leaguesBody(),
          },
        ),
      ],
    );
  }

  /// The hidden My Leagues surface (only reachable while [kShowMiniLeagues]).
  Widget _leaguesBody() => MiniLeaguesView(
        leagues: _leagues ?? const [],
        overall: _boards!.overall,
        managers: _managers!,
        profiles: _profiles!,
        selfUid: _selfUid,
        onOpenManager: _openManager,
        onCreateLeague: widget.createLeague ??
            (name, code) => FantasyService.createMiniLeague(
                widget.sport, widget.season,
                name: name, code: code),
        onJoinLeague: widget.joinLeague ??
            (id) => FantasyService.joinMiniLeague(
                widget.sport, widget.season, id),
        copyText: widget.copyText,
        shareText: widget.shareText,
        readClipboard: widget.readClipboard,
        codeGenerator: widget.codeGenerator,
      );

  Widget _overallBody() {
    final entries = _boards!.overall;
    final dreamTeam = _dreamTeamCard();
    if (entries.isEmpty) {
      return _LeaderboardsEmpty(
          key: const ValueKey('leaderboards_empty'), header: dreamTeam);
    }
    return RankedLeaderboardList(
      header: dreamTeam,
      rows: composeLeaderboardRows(
        entries: entries,
        managers: _managers!,
        profiles: _profiles!,
        selfUid: _selfUid,
      ),
      showMovement: true,
      onRowTap: _openManager,
    );
  }

  Widget _gameweekBody() {
    final byWeek = _boards!.byWeek;
    final dreamTeam = _dreamTeamCard();
    if (byWeek.isEmpty) {
      return _LeaderboardsEmpty(
          key: const ValueKey('leaderboards_empty'), header: dreamTeam);
    }

    // Chips 1..N from the real schedule's gameweeks (falling back to the
    // weeks that actually hold data if the schedule hasn't streamed in).
    final weekNumbers = widget.gameweeks.isNotEmpty
        ? [for (final gw in widget.gameweeks) gw.number]
        : (byWeek.keys.toList()..sort());
    final latestScored =
        byWeek.keys.reduce((a, b) => a > b ? a : b);
    var selected = FantasyLeaderboardsTab.sessionWeek ?? latestScored;
    if (!weekNumbers.contains(selected)) selected = latestScored;

    final scheme = Theme.of(context).colorScheme;
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        children: [
          for (final week in weekNumbers) ...[
            ChoiceChip(
              key: ValueKey('leaderboard_week_$week'),
              label: Text('GW$week'),
              visualDensity: VisualDensity.compact,
              selected: selected == week,
              onSelected: (_) => setState(
                  () => FantasyLeaderboardsTab.sessionWeek = week),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );

    final entries = byWeek[selected] ?? const <FantasyLeaderboardEntry>[];
    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dreamTeam != null) Flexible(child: dreamTeam),
          chips,
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "Gameweek $selected hasn't been scored yet.",
                  key: const ValueKey('leaderboard_week_unscored'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return RankedLeaderboardList(
      header: dreamTeam == null
          ? chips
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [dreamTeam, chips],
            ),
      rows: composeLeaderboardRows(
        entries: entries,
        managers: _managers!,
        profiles: _profiles!,
        selfUid: _selfUid,
        // The pinned Gameweek shape carries no movement (by design).
        showMovement: false,
      ),
      showMovement: false,
      onRowTap: _openManager,
    );
  }
}

/// The friendly empty state while the Leaderboards node is absent (nothing
/// finalized yet — P4's functions write it after the first gameweek).
class _LeaderboardsEmpty extends StatelessWidget {
  const _LeaderboardsEmpty({super.key, this.header});

  /// Scrolled above the empty copy (the Dream Team card can exist before a
  /// board does, e.g. an admin-seeded week).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: 24),
          ],
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emoji_events_outlined,
                size: 34, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            'Leaderboards light up after the first gameweek.',
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardsSkeleton extends StatelessWidget {
  const _LeaderboardsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(width: double.infinity, height: 36, radius: 18),
            SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: 130, radius: 16),
            SizedBox(height: 14),
            SkeletonList(count: 6),
          ],
        ),
      ),
    );
  }
}
