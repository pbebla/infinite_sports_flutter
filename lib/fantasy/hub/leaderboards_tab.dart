// The hub's Leaderboards tab (P3d, spec §9/§10; redesigned in round 3, spec
// §6): three scopes — Overall | Gameweek | Team of the week. Overall and
// Gameweek render plain ranked rows (no podium) — gold rank, a movement cell
// on Overall only, the manager's real name with the team name under it — with
// the signed-in manager's row pinned when scrolled away; the Gameweek scope
// adds week chips (1..N from the real schedule's gameweeks). Tapping ANY
// manager — your OWN row (natural or pinned) included — opens their squad
// viewer (spec §9 transparency). Your own team page carries the "Your rank
// this season" card (rank_history_chart.dart, from Leaderboards/RankHistory,
// handed to the viewer here) with "Share my rank". Overall also badges the
// week's biggest climber(s) (flame) and biggest drop(s); Gameweek opens with
// the selected week's summary ("Average · Highest (name) · You"). Team of the
// week is the Dream Team card (dream_team_card.dart) as the ONLY content of
// its own view — it no longer floats above the two lists (switching those
// looked like a no-op). The selected week carries between Gameweek and Team
// of the week. Share (owner follow-up): the Team of the Week header and the
// "Your rank this season" card each render a branded story image
// (fantasy_share.dart) and open the share sheet.
//
// Badges (spec 2026-10-30 §5): the season's whole `Badges` node feeds a
// small military_tech + N chip beside each manager's name on Overall and
// Gameweek, and seeds the squad viewer's shelf. It does NOT gate the reveal
// (Opus audit item 1 — a whole-season node must never hold the board): the
// per-manager counts are computed ONCE per emission (not per build), and
// until the first one lands every row reserves the chip's fixed-size slot,
// so the numbers fill in after the fade without moving a row. A failing
// feed = no chips (logged). (A server-written per-row BadgeCount would drop
// this whole-node stream — a separate, functions-side change.)
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
// landed — the profiles read is bounded, bounded_read.dart); session caches
// make revisits instant; theme-safe both modes;
// names wrap, never underlined; glass-navbar clearance; scope + selected
// week persist for the session (the market-sort precedent).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_badges.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_parsers.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_player.dart';
import 'package:infinite_sports_flutter/fantasy/data/fantasy_service.dart';
import 'package:infinite_sports_flutter/fantasy/engine/gameweeks.dart';
import 'package:infinite_sports_flutter/fantasy/engine/squad.dart';
import 'package:infinite_sports_flutter/fantasy/hub/dream_team_card.dart';
import 'package:infinite_sports_flutter/fantasy/hub/fantasy_share.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_logic.dart';
import 'package:infinite_sports_flutter/fantasy/hub/leaderboard_rows.dart';
import 'package:infinite_sports_flutter/fantasy/hub/manager_squad_viewer.dart';
import 'package:infinite_sports_flutter/fantasy/hub/mini_leagues_view.dart';
import 'package:infinite_sports_flutter/fantasy/hub/player_chip.dart';
import 'package:infinite_sports_flutter/misc/public_profiles.dart';
import 'package:infinite_sports_flutter/misc/share_card_service.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

enum LeaderboardScope { overall, gameweek, teamOfWeek, leagues }

/// The third segment's label. SegmentedButton gives every segment the SAME
/// width, so at 360 px each gets only ~88 px of text. "Team of the week" needs
/// ~113 px in Roboto (it wrapped to two lines); "Team of week" fits on one
/// line. The fit is proved with real Roboto metrics in
/// leaderboards_tab_test.dart.
const String kTeamOfWeekSegmentLabel = 'Team of week';

/// The Team of the week view's friendly line while no DreamTeam node exists
/// (the functions write it once a gameweek is scored).
const String kTeamOfWeekEmptyCopy =
    'Team of the Week appears once Gameweek 1 is scored.';

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
    this.shareImage,
    this.badgesStates,
  });

  final Stream<FantasyLeaderboards>? leaderboardsStates;
  final Stream<Map<String, FantasyManager>>? managersStates;
  final Stream<List<FantasyMiniLeague>>? miniLeaguesStates;
  final Stream<Map<int, FantasyDreamTeam>>? dreamTeamsStates;
  final Future<Map<String, PublicProfile>> Function()? loadProfiles;
  final String? selfUidOverride;

  /// The season's `Badges` node (uid → awards) — the rows' badge counts.
  final Stream<Map<String, List<FantasyBadgeAward>>>? badgesStates;

  /// The squad viewer's PublishedPicks / History feeds (the tab's default
  /// viewer builder hands them to ManagerSquadViewerPage).
  final Stream<Map<int, FantasySquad>>? viewerPublishedStates;
  final Stream<Map<int, FantasySquad>>? viewerHistoryStates;

  /// The share-sheet seam for the story images (null = the system sheet).
  final SharePng? shareImage;
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
    this.shareImage,
    this.badgesStates,
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
  final ShareSheet? shareText;
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

  /// Test seam for the Team of the Week / my-rank share images: receives the
  /// rendered PNG + caption instead of the system share sheet.
  final SharePng? shareImage;

  /// Test seam: the season's badges (uid → awards); null =
  /// `FantasyService.watchBadges`.
  final Stream<Map<String, List<FantasyBadgeAward>>>? badgesStates;

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

  /// uid → achievement badges this season (the squad viewer's shelf seed);
  /// null until the feed first answers.
  Map<String, List<FantasyBadgeAward>>? _badges;

  /// uid → badge count for the Overall / Gameweek rows, computed ONCE per
  /// badges emission (never per build). null = not known yet: the rows
  /// reserve the chip's slot. A failing feed loads as "nobody has any".
  Map<String, int>? _badgeCounts;
  StreamSubscription<Map<String, List<FantasyBadgeAward>>>? _badgesSub;

  StreamSubscription<FantasyLeaderboards>? _boardsSub;

  /// Re-listen-safe copy of the boards feed for the pages this tab opens
  /// (your team page's live rank card) — one upstream subscription, however
  /// many pages are pushed.
  final _boardsForViewer = StreamController<FantasyLeaderboards>.broadcast();
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
      _boardsForViewer.add(boards);
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
    try {
      _badgesSub = (widget.badgesStates ??
              FantasyService.watchBadges(widget.sport, widget.season))
          .listen((badges) {
        // The counts are derived here, once per emission.
        final counts = {
          for (final e in badges.entries)
            if (e.value.isNotEmpty) e.key: e.value.length,
        };
        if (!mounted) return;
        setState(() {
          _badges = badges;
          _badgeCounts = counts;
        });
      }, onError: (Object e) {
        debugPrint('FantasyLeaderboardsTab: badges feed failed: $e');
        if (!mounted) return;
        setState(() {
          _badges ??= const {};
          _badgeCounts ??= const {};
        });
      });
    } catch (e) {
      debugPrint('FantasyLeaderboardsTab: badges feed failed: $e');
      _badges = const {};
      _badgeCounts = const {};
    }
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
    _boardsForViewer.close();
    _managersSub?.cancel();
    _leaguesSub?.cancel();
    _dreamTeamsSub?.cancel();
    _badgesSub?.cancel();
    super.dispose();
  }

  /// The badges feed is deliberately NOT here (see the file header): the
  /// rows reserve its slot and the counts fill in after the fade.
  bool get _ready =>
      _boards != null &&
      _managers != null &&
      (!kShowMiniLeagues || _leagues != null) &&
      _profiles != null &&
      _dreamTeams != null;

  /// Your season rank card's inputs for your own team page: the Overall
  /// rank-by-gameweek series + the "Share my rank" action (it shares your
  /// OVERALL row — "#2 of 4 · 80 pts" — whichever scope you tapped from).
  /// null when you have no Overall row yet (nothing to chart or share).
  ({List<RankPoint> series, Future<void> Function(BuildContext) share})?
      _selfRankCard() {
    final boards = _boards;
    final managers = _managers;
    final profiles = _profiles;
    if (boards == null || managers == null || profiles == null) return null;
    final rows = composeLeaderboardRows(
      entries: boards.overall,
      managers: managers,
      profiles: profiles,
      selfUid: _selfUid,
    );
    final self = rows.where((r) => r.isSelf).firstOrNull;
    if (self == null) return null;
    final series = rankSeries(boards.rankHistory[self.uid]);
    return (
      series: series,
      share: (buttonContext) => shareMyRankStory(
            buttonContext,
            row: self,
            managerCount: rows.length,
            series: series,
            seasonLabel: _seasonLabel,
            share: widget.shareImage,
          ),
    );
  }

  void _openManager(LeaderboardRowData row) {
    // Only YOUR team page carries the rank card (the viewer also gates on
    // isSelf). The opening series comes from data already on screen; the
    // card then follows the boards feed, and a share taken later renders
    // the rank as it is THEN (this tab's state stays live underneath).
    final rankCard = row.isSelf ? _selfRankCard() : null;
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
              // Once the season's badges are here the shelf paints without
              // waiting on its own first emission (null: it waits for it).
              initialBadges:
                  _badges == null ? null : (_badges![row.uid] ?? const []),
              rankSeries: rankCard?.series,
              rankStates: rankCard == null
                  ? null
                  : _boardsForViewer.stream
                      .map((b) => rankSeries(b.rankHistory[row.uid])),
              onShareRank: rankCard == null
                  ? null
                  : (buttonContext) =>
                      (_selfRankCard() ?? rankCard).share(buttonContext),
            );
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => builder(row)));
  }

  /// "Futsal Season 15" — the share images' season line.
  String get _seasonLabel => fantasySeasonLabel(widget.sport, widget.season);

  /// The scope actually shown: a My Leagues scope restored from the session
  /// (it is a static) falls back to Overall while mini-leagues are hidden.
  LeaderboardScope get _scope {
    final scope = FantasyLeaderboardsTab.sessionScope;
    return !kShowMiniLeagues && scope == LeaderboardScope.leagues
        ? LeaderboardScope.overall
        : scope;
  }

  /// Gameweek chips 1..N from the real schedule's gameweeks (falling back to
  /// the weeks that actually hold data if the schedule hasn't streamed in).
  List<int> _gameweekNumbers(Map<int, List<FantasyLeaderboardEntry>> byWeek) =>
      widget.gameweeks.isNotEmpty
          ? [for (final gw in widget.gameweeks) gw.number]
          : (byWeek.keys.toList()..sort());

  /// The Gameweek view's selected week: the session pick while it is still a
  /// chip, else the latest scored week. [byWeek] must be non-empty.
  int _selectedGameweek(Map<int, List<FantasyLeaderboardEntry>> byWeek) {
    final latestScored = byWeek.keys.reduce((a, b) => a > b ? a : b);
    final selected = FantasyLeaderboardsTab.sessionWeek ?? latestScored;
    return _gameweekNumbers(byWeek).contains(selected)
        ? selected
        : latestScored;
  }

  /// Leaving Gameweek or Team of the week carries its selected week to the
  /// other one's session selection — when that week exists there (GW8 in
  /// Gameweek -> Team of the week opens on GW8). A week the target doesn't
  /// have leaves the target's own selection alone. Runs inside setState.
  void _carryWeekFrom(LeaderboardScope leaving) {
    final byWeek =
        _boards?.byWeek ?? const <int, List<FantasyLeaderboardEntry>>{};
    final teams = _dreamTeams ?? const <int, FantasyDreamTeam>{};
    switch (leaving) {
      case LeaderboardScope.gameweek:
        if (byWeek.isEmpty || teams.isEmpty) return;
        final week = _selectedGameweek(byWeek);
        if (teams.containsKey(week)) DreamTeamCard.sessionWeek = week;
      case LeaderboardScope.teamOfWeek:
        if (byWeek.isEmpty || teams.isEmpty) return;
        final week = DreamTeamCard.resolveWeek(teams.keys);
        if (_gameweekNumbers(byWeek).contains(week)) {
          FantasyLeaderboardsTab.sessionWeek = week;
        }
      case LeaderboardScope.overall:
      case LeaderboardScope.leagues:
        break;
    }
  }

  void _onScopeChanged(LeaderboardScope next) {
    setState(() {
      _carryWeekFrom(_scope);
      FantasyLeaderboardsTab.sessionScope = next;
    });
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
            // Same compact look; segment padding trimmed 12 -> 8 so the three
            // equal-width segments keep "Team of week" on one line at 360 px
            // (88 px of text -> 96; the label needs ~89 in Roboto).
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8)),
            ),
            segments: [
              const ButtonSegment(
                  value: LeaderboardScope.overall, label: Text('Overall')),
              const ButtonSegment(
                  value: LeaderboardScope.gameweek, label: Text('Gameweek')),
              const ButtonSegment(
                  value: LeaderboardScope.teamOfWeek,
                  label: Text(kTeamOfWeekSegmentLabel)),
              if (kShowMiniLeagues)
                const ButtonSegment(
                    value: LeaderboardScope.leagues,
                    label: Text('My Leagues')),
            ],
            selected: {scope},
            onSelectionChanged: (s) => _onScopeChanged(s.first),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: switch (scope) {
            LeaderboardScope.overall => _overallBody(),
            LeaderboardScope.gameweek => _gameweekBody(),
            LeaderboardScope.teamOfWeek => _teamOfWeekBody(),
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
    if (entries.isEmpty) {
      return const _LeaderboardsEmpty(key: ValueKey('leaderboards_empty'));
    }
    final rows = composeLeaderboardRows(
      entries: entries,
      managers: _managers!,
      profiles: _profiles!,
      selfUid: _selfUid,
    );
    return RankedLeaderboardList(
      rows: rows,
      showMovement: true,
      onRowTap: _openManager,
      movers: weeklyMovers(rows),
      badgeCounts: _badgeCounts,
    );
  }

  Widget _gameweekBody() {
    final byWeek = _boards!.byWeek;
    if (byWeek.isEmpty) {
      return const _LeaderboardsEmpty(key: ValueKey('leaderboards_empty'));
    }

    final weekNumbers = _gameweekNumbers(byWeek);
    final selected = _selectedGameweek(byWeek);

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
    final rows = composeLeaderboardRows(
      entries: entries,
      managers: _managers!,
      profiles: _profiles!,
      selfUid: _selfUid,
      // The pinned Gameweek shape carries no movement (by design).
      showMovement: false,
    );
    final summary = gameweekSummary(rows);
    return RankedLeaderboardList(
      // The week chips, then the selected week's summary line.
      header: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chips,
          if (summary != null) _GameweekSummaryCard(summary: summary),
        ],
      ),
      rows: rows,
      showMovement: false,
      onRowTap: _openManager,
      badgeCounts: _badgeCounts,
    );
  }

  /// Team of the week (P6): the Dream Team card as the ONLY content of its
  /// view — its own week chips, pitch, points and player taps (the hub's
  /// profile opener) are the card's, unchanged. Friendly line while no
  /// DreamTeam node exists yet.
  Widget _teamOfWeekBody() {
    final teams = _dreamTeams!;
    if (teams.isEmpty) {
      return const _LeaderboardsEmpty(
        key: ValueKey('dream_team_empty'),
        message: kTeamOfWeekEmptyCopy,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('team_of_week_scroll'),
      padding: EdgeInsets.fromLTRB(
          12, 6, 12, 24 + MediaQuery.paddingOf(context).bottom),
      child: DreamTeamCard(
        teams: teams,
        config: widget.configState.config,
        players: widget.players,
        onOpenPlayer: widget.onOpenPlayer,
        seasonLabel: _seasonLabel,
        shareImage: widget.shareImage,
      ),
    );
  }
}

/// The Gameweek view's compact week summary: "Average 48 pts · Highest 96
/// (Sweeper Keepers) · You 52" — numbers bold, yours in the accent. One
/// wrapping paragraph (long names wrap at 360 px, never clip).
class _GameweekSummaryCard extends StatelessWidget {
  const _GameweekSummaryCard({required this.summary});

  final GameweekSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strong = TextStyle(
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
    );
    final you = summary.you;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // Same words as GameweekSummary.label, styled per part.
          child: Text.rich(
            key: const ValueKey('gameweek_summary'),
            TextSpan(
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
              children: [
                const TextSpan(text: 'Average '),
                TextSpan(text: '${summary.average} pts', style: strong),
                const TextSpan(text: ' · Highest '),
                TextSpan(text: '${summary.highest}', style: strong),
                TextSpan(text: ' (${summary.highestWho})'),
                if (you != null) ...[
                  const TextSpan(text: ' · You '),
                  TextSpan(
                    text: '$you',
                    style: strong.copyWith(color: fantasyAccent(context)),
                  ),
                ],
              ],
            ),
            softWrap: true,
          ),
        ),
      ),
    );
  }
}

/// The friendly empty state while the Leaderboards node is absent (nothing
/// finalized yet — P4's functions write it after the first gameweek). Also the
/// Team of the week view's empty state, with its own [message].
class _LeaderboardsEmpty extends StatelessWidget {
  const _LeaderboardsEmpty({
    super.key,
    this.message = 'Leaderboards light up after the first gameweek.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 48, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
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
            message,
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
