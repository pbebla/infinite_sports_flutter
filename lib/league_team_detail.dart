import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/league_match_detail.dart';
import 'package:infinite_sports_flutter/misc/league_adapters.dart';
import 'package:infinite_sports_flutter/misc/league_form.dart';
import 'package:infinite_sports_flutter/misc/league_service.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/misc/top_stats.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';
import 'package:infinite_sports_flutter/widgets/form_chips.dart';
import 'package:infinite_sports_flutter/widgets/jersey_painter.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:intl/intl.dart';

/// League team page (P2.1 Task A3): structurally the tournament team page
/// (lib/tournamentteamdetail.dart) — same Overview / Squad / Stats inner
/// tabs on the navy SliverAppBar — but SEASON-SCOPED: record, results,
/// squad and info are all THIS season's; no cross-season history card.
/// League differences: Team Info shows Captain + Players (not
/// Established/City), the record box is titled "League Record", and the
/// Overview keeps the results & fixtures list below the info cards.
/// Metadata read contract: `{sport}/{season}/Teams/{team}/Captain|Color|
/// Coach` (all optional strings, Manager-maintained).
class LeagueTeamDetailPage extends StatefulWidget {
  final String sport;
  final String season;
  final String teamName;

  const LeagueTeamDetailPage({
    super.key,
    this.sport = 'Futsal',
    required this.season,
    required this.teamName,
  });

  @override
  State<LeagueTeamDetailPage> createState() => _LeagueTeamDetailPageState();
}

class _LeagueTeamDetailPageState extends State<LeagueTeamDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  // null = that stream's first snapshot hasn't arrived → section skeleton.
  List<TournamentMatch>? _matches;
  List<TournamentTeam>? _standings;
  Map<String, List<TournamentPlayer>>? _rosters;
  Map<String, String>? _captains;
  Map<String, String> _logos = {};
  int _startHour = 0;
  StreamSubscription<List<TournamentMatch>>? _gamesSub;
  StreamSubscription<List<TournamentTeam>>? _standingsSub;
  StreamSubscription<Map<String, List<TournamentPlayer>>>? _rostersSub;
  StreamSubscription<Map<String, String>>? _captainsSub;

  @override
  void initState() {
    super.initState();
    // First paint speed (P2.1): subscribe immediately with default seeds
    // (startHour 0, no logos); each seed re-applies when it arrives.
    _subscribeGames();
    _subscribeStandings();
    _rostersSub =
        LeagueService.watchRosters(widget.sport, widget.season).listen((r) {
      if (mounted) setState(() => _rosters = r);
    });
    _captainsSub =
        LeagueService.watchCaptains(widget.sport, widget.season).listen((c) {
      if (mounted) setState(() => _captains = c);
    });
    LeagueService.getStartHour(widget.sport, widget.season).then((h) {
      if (!mounted || h == _startHour) return;
      _startHour = h;
      _subscribeGames();
    });
    LeagueService.leagueLogoUrls(widget.sport, widget.season).then((logos) {
      if (!mounted || logos.isEmpty) return;
      setState(() => _logos = logos);
      _subscribeStandings();
    });
  }

  void _subscribeGames() {
    _gamesSub?.cancel();
    _gamesSub = LeagueService
        .watchGames(widget.sport, widget.season, startHour: _startHour)
        .listen((m) {
      if (mounted) setState(() => _matches = m);
    });
  }

  void _subscribeStandings() {
    _standingsSub?.cancel();
    _standingsSub = LeagueService
        .watchStandings(widget.sport, widget.season, _logos)
        .listen((s) {
      if (mounted) setState(() => _standings = s);
    });
  }

  @override
  void dispose() {
    _gamesSub?.cancel();
    _standingsSub?.cancel();
    _rostersSub?.cancel();
    _captainsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Live record straight from the standings stream; stub until it lands.
  TournamentTeam get _team => (_standings ?? const <TournamentTeam>[]).firstWhere(
        (t) => t.id == widget.teamName,
        orElse: () =>
            leagueTeamStub(widget.teamName, _logos[widget.teamName]),
      );

  void _openMatch(TournamentMatch m) {
    final ref = parseLeagueGameId(m.id);
    if (ref == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeagueMatchDetailPage(
          sport: widget.sport,
          season: widget.season,
          dateKey: ref.dateKey,
          gameIndex: ref.index,
          initialMatch: m,
        ),
      ),
    );
  }

  void _openPlayer(TournamentPlayer p) {
    openPlayerProfileById(context, uid: p.uid, name: p.name);
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    final matches = _matches ?? const <TournamentMatch>[];
    final myMatches = teamLeagueMatches(widget.teamName, matches);
    final form = teamLeagueForm(widget.teamName, matches);
    final roster = _rosters?[widget.teamName] ?? <TournamentPlayer>[];

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 185,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            // Force the back arrow (and actions) white in BOTH themes — the
            // global appBarTheme.iconTheme is onSurface, which goes dark on
            // this navy header in light mode (P2.1 Task A3 fix).
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            actions: [
              FollowBell(
                topic: leagueTeamTopic(
                    widget.sport, widget.season, widget.teamName),
                label: widget.teamName,
                kind: 'team',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(context, team, form),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Squad'),
                Tab(text: 'Stats'),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: infiniteSportsPrimaryColor,
              indicatorWeight: 3,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            LeagueTeamOverviewTab(
              team: team,
              captain: _captains?[widget.teamName],
              roster: roster,
              matches: myMatches,
              standingsLoaded: _standings != null,
              matchesLoaded: _matches != null,
              rosterLoaded: _rosters != null,
              onMatchTap: _openMatch,
              onPlayerTap: _openPlayer,
            ),
            LeagueTeamSquadTab(
              coach: team.coachName,
              roster: roster,
              rosterLoaded: _rosters != null,
              sport: widget.sport,
              onPlayerTap: _openPlayer,
            ),
            LeagueTeamStatsTab(
              roster: roster,
              rosterLoaded: _rosters != null,
              onPlayerTap: _openPlayer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, TournamentTeam team, List<String> form) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 8, 16, 52),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TeamLogo(url: team.logoUrl, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (_standings == null)
                      // Record skeleton until the standings stream lands.
                      const SkeletonBox(width: 170, height: 12)
                    else
                      Text(
                        'W${team.wins} D${team.draws} L${team.losses} · ${team.points} pts · Season ${widget.season}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    if (form.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FormChips(form: form),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bodies — public, Firebase-free widgets (pure data + callbacks) so
// widget tests can pump them directly, league_tabs-style.
// ---------------------------------------------------------------------------

/// Overview (tournament-team-page structure, season-scoped): Team Info
/// (Captain + Players), Jersey Color, Coaching Staff, the "League Record"
/// box, then the results & fixtures list the owner loves.
class LeagueTeamOverviewTab extends StatelessWidget {
  final TournamentTeam team;
  final String? captain;
  final List<TournamentPlayer> roster;

  /// This team's matches, sorted chronologically (teamLeagueMatches).
  final List<TournamentMatch> matches;
  final bool standingsLoaded;
  final bool matchesLoaded;
  final bool rosterLoaded;
  final void Function(TournamentMatch) onMatchTap;
  final void Function(TournamentPlayer) onPlayerTap;

  const LeagueTeamOverviewTab({
    super.key,
    required this.team,
    required this.captain,
    required this.roster,
    required this.matches,
    required this.standingsLoaded,
    required this.matchesLoaded,
    required this.rosterLoaded,
    required this.onMatchTap,
    required this.onPlayerTap,
  });

  /// The captain's roster entry when the named player is in THIS season's
  /// squad — that's what makes the captain row tappable.
  TournamentPlayer? get _captainPlayer {
    if (captain == null) return null;
    for (final p in roster) {
      if (p.name == captain) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _buildTeamInfoCard(context),
        if (team.homeColor != null) _buildJerseyCard(context),
        if (team.coachName != null && team.coachName!.isNotEmpty)
          _buildCoachCard(context),
        _buildLeagueRecordCard(context),
        _sectionHeader(context, 'RESULTS & FIXTURES'),
        if (!matchesLoaded)
          const SkeletonMatchList(count: 3)
        else if (matches.isEmpty)
          _emptyNote(context, 'No games scheduled yet'),
        ...matches.map((m) => LeagueTeamMatchRow(
              teamName: team.id,
              match: m,
              onTap: () => onMatchTap(m),
            )),
      ],
    );
  }

  Widget _buildTeamInfoCard(BuildContext context) {
    final captainPlayer = _captainPlayer;
    final captainText = captain ?? '—';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Team Info',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.military_tech, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Text('Captain: ', style: TextStyle(fontSize: 13)),
                  captainPlayer != null
                      ? InkWell(
                          onTap: () => onPlayerTap(captainPlayer),
                          child: Text(
                            captainText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      : Text(captainText,
                          style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.group, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Players: ${rosterLoaded ? '${roster.length}' : '—'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJerseyCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jersey Color',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            CustomPaint(
              size: const Size(40, 44),
              painter: JerseyPainter(color: team.homeColor!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Coaching Staff',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                const TeamLogo(url: null, size: 44, fallbackIcon: Icons.person),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.coachName!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Head Coach',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        )),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The tournament page's record box, titled "League Record" and fed by
  /// THIS season's live standings row.
  Widget _buildLeagueRecordCard(BuildContext context) {
    final stats = [
      {'label': 'W', 'value': '${team.wins}'},
      {'label': 'D', 'value': '${team.draws}'},
      {'label': 'L', 'value': '${team.losses}'},
      {'label': 'GF', 'value': '${team.gs}'},
      {'label': 'GA', 'value': '${team.gc}'},
      {'label': 'GD', 'value': team.gd >= 0 ? '+${team.gd}' : '${team.gd}'},
      {'label': 'Pts', 'value': '${team.points}'},
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('League Record',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
            if (!standingsLoaded)
              const SkeletonBox(width: double.infinity, height: 34)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: stats.map((s) {
                  return Column(
                    children: [
                      Text(
                        s['value']!,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text(
                        s['label']!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Squad (tournament-team-page structure): coaching staff section, then the
/// season roster with player-profile taps. P2.2: each row shows the
/// player's profile photo (person icon for unlinked/missing) and their 3
/// strongest stats as icon+value chips under the name (topThreeStats).
class LeagueTeamSquadTab extends StatelessWidget {
  final String? coach;
  final List<TournamentPlayer> roster;
  final bool rosterLoaded;

  /// Picks the per-sport top-stat lists (misc/top_stats.dart) — league
  /// pages serve futsal until P4, hence the default.
  final String sport;
  final void Function(TournamentPlayer) onPlayerTap;

  const LeagueTeamSquadTab({
    super.key,
    required this.coach,
    required this.roster,
    required this.rosterLoaded,
    this.sport = 'Futsal',
    required this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        if (coach != null && coach!.isNotEmpty) ...[
          _sectionHeader(context, 'COACHING STAFF', inset: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const TeamLogo(url: null, size: 44, fallbackIcon: Icons.person),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Head Coach',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        )),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
        ],
        _sectionHeader(context, 'PLAYERS', inset: 16),
        if (!rosterLoaded)
          const SkeletonMatchList(count: 3)
        else if (roster.isEmpty)
          _emptyNote(context, 'No roster yet', inset: 16),
        ...roster.map((p) => _playerRow(context, p)),
      ],
    );
  }

  Widget _playerRow(BuildContext context, TournamentPlayer p) {
    final topStats = topThreeStatsForPlayer(p, sport);
    return InkWell(
      onTap: () => onPlayerTap(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Center(
                child: Text(
                  p.number ?? '–',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // P2.2: profile photo — LeagueService.watchRosters attaches
            // Users/{uid}/ProfileUrl for linked players (the tournament
            // squad's TeamLogo+person pattern); unlinked or photo-less
            // players get the neutral person icon.
            TeamLogo(url: p.photoUrl, size: 36, fallbackIcon: Icons.person),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // The player's 3 strongest stats (fallback-filled) as
                  // icon+value chips.
                  Row(
                    children: [
                      for (final s in topStats) _statChip(context, s),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }

  /// Small icon+value chip. surfaceContainerHighest + onSurface read in
  /// BOTH light and dark mode; StatIcon's white tile keeps the line-art
  /// legible on either.
  Widget _statChip(BuildContext context, TopStat s) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatIcon(
            asset: statIconAsset(leagueTopStatIconKey(s.stat)),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '${s.value}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stats (tournament-team-page structure): expandable leader cards per stat
/// category, computed from THIS season's roster totals (season-scoped).
class LeagueTeamStatsTab extends StatefulWidget {
  final List<TournamentPlayer> roster;
  final bool rosterLoaded;
  final void Function(TournamentPlayer) onPlayerTap;

  const LeagueTeamStatsTab({
    super.key,
    required this.roster,
    required this.rosterLoaded,
    required this.onPlayerTap,
  });

  @override
  State<LeagueTeamStatsTab> createState() => _LeagueTeamStatsTabState();
}

class _LeagueTeamStatsTabState extends State<LeagueTeamStatsTab> {
  /// label → statByName key → statIconAsset key — the EXACT icon treatment
  /// of the league Player Stats tab (league_player_stats_tab.dart, P2.2
  /// owner item 3); '' = no icon, matching its iconless Clean Sheets.
  static const _categories = [
    {'label': 'Goals', 'stat': 'goals', 'icon': 'goal'},
    {'label': 'Assists', 'stat': 'assists', 'icon': 'assist'},
    {'label': 'Saves', 'stat': 'saves', 'icon': 'save'},
    {'label': 'Defensive Plays (DPL)', 'stat': 'dpl', 'icon': 'dpl'},
    {'label': 'Clean Sheets', 'stat': 'cleanSheets', 'icon': ''},
    {'label': 'Yellow Cards', 'stat': 'yellowCards', 'icon': 'yellow'},
    {'label': 'Red Cards', 'stat': 'redCards', 'icon': 'red'},
  ];

  final Set<String> _expandedStats = {};

  @override
  Widget build(BuildContext context) {
    if (!widget.rosterLoaded) {
      return const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: 8),
          child: SkeletonMatchList(count: 6),
        ),
      );
    }
    if (widget.roster.isEmpty) {
      return const Center(child: Text('No player data'));
    }

    List<TournamentPlayer> sortedFor(String stat) {
      final filtered = widget.roster
          .where((p) => p.statByName(stat) > 0)
          .toList()
        ..sort((a, b) => b.statByName(stat).compareTo(a.statByName(stat)));
      return filtered;
    }

    final cards = <Widget>[];
    for (final cat in _categories) {
      final label = cat['label']!;
      final stat = cat['stat']!;
      final icon = cat['icon']!;
      final allSorted = sortedFor(stat);
      if (allSorted.isEmpty) continue;
      cards.add(_statCard(context, label, stat, icon, allSorted));
    }

    if (cards.isEmpty) {
      return const Center(child: Text('No stats recorded yet'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      children: cards,
    );
  }

  Widget _statCard(BuildContext context, String label, String stat,
      String icon, List<TournamentPlayer> allSorted) {
    final isExpanded = _expandedStats.contains(stat);
    final displayed = isExpanded ? allSorted : allSorted.take(3).toList();

    return GestureDetector(
      onTap: () {
        setState(() {
          if (!_expandedStats.remove(stat)) _expandedStats.add(stat);
        });
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: StatIcon(asset: statIconAsset(icon), size: 18),
                    ),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...displayed.asMap().entries.map((entry) {
                final rank = entry.key;
                final player = entry.value;
                final value = player.statByName(stat);
                return InkWell(
                  onTap: () => widget.onPlayerTap(player),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        rank == 0
                            ? Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: infiniteSportsPrimaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$value',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: 32,
                                child: Center(
                                  child: Text(
                                    '$value',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// One results-&-fixtures row (the list the owner loves, kept from P2):
/// form-chip / LIVE / clock leading, score or kick-off trailing, tap →
/// the league match page.
class LeagueTeamMatchRow extends StatelessWidget {
  final String teamName;
  final TournamentMatch match;
  final VoidCallback onTap;

  const LeagueTeamMatchRow({
    super.key,
    required this.teamName,
    required this.match,
    required this.onTap,
  });

  String _shortDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final m = match;
    final isFinished = m.matchStatus.isFinished;
    final isLive = m.matchStatus.isLive;

    Widget leading;
    if (isFinished && m.stage.toLowerCase() != 'friendly') {
      leading = FormChips(form: [teamResultLetter(teamName, m)], size: 24);
    } else if (isLive) {
      leading = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'LIVE',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9),
        ),
      );
    } else {
      leading = Icon(
        Icons.schedule,
        size: 20,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      );
    }

    final trailing = (isFinished || isLive)
        ? Text(
            '${m.team1Score} - ${m.team2Score}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          )
        : Text(
            m.time ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          );

    final subtitleBits = [
      _shortDate(m.date),
      if (m.label != 'League') m.label, // Friendly / Semifinal / ...
    ];

    return ListTile(
      dense: true,
      leading: SizedBox(width: 40, child: Center(child: leading)),
      title: Text(
        '${m.team1Id} vs ${m.team2Id}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle:
          Text(subtitleBits.join(' · '), style: const TextStyle(fontSize: 11)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

// Shared bits for the tab bodies above. [inset] is the extra horizontal
// padding — the Overview list already carries 12, the Squad list none.

Widget _sectionHeader(BuildContext context, String title,
    {double inset = 4}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(inset, 14, inset, 6),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    ),
  );
}

Widget _emptyNote(BuildContext context, String text, {double inset = 4}) {
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: inset, vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    ),
  );
}
