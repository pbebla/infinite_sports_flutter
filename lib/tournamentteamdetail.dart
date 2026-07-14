import 'dart:async';

import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/tournament_stats_engine.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/widgets/jersey_painter.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:infinite_sports_flutter/misc/notification_topics.dart';
import 'package:infinite_sports_flutter/widgets/follow_bell.dart';

class TournamentTeamDetailPage extends StatefulWidget {
  final String teamId;
  final String tournamentId;

  /// Optional — if the parent already loaded teams + rosters for this
  /// tournament, pass them through so we don't re-fetch them.
  final Map<String, TournamentTeam>? preloadedTeams;
  final Map<String, List<TournamentPlayer>>? preloadedRosters;

  const TournamentTeamDetailPage({
    super.key,
    required this.teamId,
    required this.tournamentId,
    this.preloadedTeams,
    this.preloadedRosters,
  });

  @override
  State<TournamentTeamDetailPage> createState() =>
      _TournamentTeamDetailPageState();
}

class _TournamentTeamDetailPageState extends State<TournamentTeamDetailPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _loadError;
  TournamentTeam? _team;
  List<TournamentPlayer> _players = [];
  Map<String, List<TournamentPlayer>> _rosters = {};
  List<TournamentMatch> _matches = [];
  StreamSubscription<List<TournamentMatch>>? _matchesSub;
  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _historyFuture;
  final Set<String> _expandedStats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _historyFuture =
        TournamentService.getTeamTournamentHistory(widget.teamId);
    _loadData();
    _matchesSub = TournamentService.watchMatches(widget.tournamentId).listen((live) {
      if (!mounted) return;
      setState(() => _matches = live);
    });
  }

  @override
  void dispose() {
    _matchesSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Reuse parent-loaded data when available.
      final teams = widget.preloadedTeams ??
          await TournamentService.getTeams(widget.tournamentId);
      final rosters = widget.preloadedRosters ??
          await TournamentService.getRosters(widget.tournamentId, teams);
      final players = rosters[widget.teamId] ?? [];

      if (!mounted) return;
      setState(() {
        _team = teams[widget.teamId];
        _players = players;
        _rosters = rosters;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e, st) {
      debugPrint('TournamentTeamDetailPage._loadData error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load team. Tap retry.';
      });
    }
  }

  // ---- Helpers ----

  // Position ordering
  List<String> _positionOrder() {
    return ['GK', 'GOALKEEPER', 'DEF', 'DEFENDER', 'MID', 'MIDFIELDER', 'FWD', 'FORWARD',
      'PG', 'SG', 'GUARD', 'SF', 'PF', 'CENTER', 'C',
      'QB', 'REC', 'OL', 'K',
    ];
  }

  List<TournamentPlayer> _sortedPlayers() {
    final order = _positionOrder();
    return [..._players]..sort((a, b) {
        final aPos = (a.position ?? '').toUpperCase();
        final bPos = (b.position ?? '').toUpperCase();
        int aIdx = order.indexWhere((o) => aPos.contains(o));
        int bIdx = order.indexWhere((o) => bPos.contains(o));
        if (aIdx == -1) aIdx = order.length;
        if (bIdx == -1) bIdx = order.length;
        if (aIdx != bIdx) return aIdx.compareTo(bIdx);
        return a.name.compareTo(b.name);
      });
  }

  String _getFullStateName(String? cityState) {
    if (cityState == null || cityState.isEmpty) return '';
    final parts = cityState.split(',');
    if (parts.length < 2) return cityState;
    final abbr = parts.last.trim().toUpperCase();
    const stateMap = {
      'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas',
      'CA': 'California', 'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware',
      'FL': 'Florida', 'GA': 'Georgia', 'HI': 'Hawaii', 'ID': 'Idaho',
      'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas',
      'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
      'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi',
      'MO': 'Missouri', 'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada',
      'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York',
      'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma',
      'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
      'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah',
      'VT': 'Vermont', 'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia',
      'WI': 'Wisconsin', 'WY': 'Wyoming', 'DC': 'Washington D.C.',
    };
    return stateMap[abbr] ?? abbr;
  }

  // ---- Widgets ----

  Widget _buildHeader(BuildContext context) {
    final team = _team;
    // Determine header color — a team overrideColor always wins (both
    // modes); only the DEFAULT follows light navy / dark grey (P3.2).
    Color headerColor =
        team?.overrideColor ?? TournamentColors.headerBackground(context);

    final darkened = Color.fromARGB(
      255,
      ((headerColor.r * 255.0).round().clamp(0, 255) * 0.75).round(),
      ((headerColor.g * 255.0).round().clamp(0, 255) * 0.75).round(),
      ((headerColor.b * 255.0).round().clamp(0, 255) * 0.75).round(),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [headerColor, darkened],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TeamLogo(
                    url: team?.logoUrl,
                    size: 60,
                    fallbackBackground: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team?.name ?? widget.teamId,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (team?.cityState != null && team!.cityState!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 12, color: Colors.white70),
                              const SizedBox(width: 3),
                              Text(
                                _getFullStateName(team.cityState),
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJerseySwatch(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(20, 22),
          painter: JerseyPainter(color: color),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    final team = _team;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      children: [
        // Team Info card
        Card(
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
                if (team != null && team.cityState != null && team.cityState!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 16,
                            color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(team.cityState!,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                if (team != null && team.established != null &&
                    team.established!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16,
                            color: Colors.grey),
                        const SizedBox(width: 6),
                        Text('Est. ${team.established}',
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    const Icon(Icons.group, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('${_players.length} Players',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Jersey Colors card
        if (team != null && (team.homeColor != null || team.awayColor != null))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Jersey Colors',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (team.homeColor != null) ...[
                        Column(
                          children: [
                            CustomPaint(
                              size: const Size(40, 44),
                              painter: JerseyPainter(
                                  color: team.homeColor!),
                            ),
                            const SizedBox(height: 4),
                            const Text('Home',
                                style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        const SizedBox(width: 20),
                      ],
                      if (team.awayColor != null)
                        Column(
                          children: [
                            CustomPaint(
                              size: const Size(40, 44),
                              painter: JerseyPainter(
                                  color: team.awayColor!),
                            ),
                            const SizedBox(height: 4),
                            const Text('Away',
                                style: TextStyle(fontSize: 11)),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        // Coaching Staff card
        if (team != null && team.coachName != null && team.coachName!.isNotEmpty)
          Card(
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
                      TeamLogo(
                        url: team.coachPhotoUrl,
                        size: 44,
                        fallbackIcon: Icons.person,
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(team.coachName!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
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
          ),
        // Tournament Record card
        _buildSeasonRecord(context),
        // Tournament History card
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final history = snapshot.data ?? [];
            if (history.isEmpty) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tournament History',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...history.map((entry) {
                      final name =
                          entry['tournamentName'] as String? ?? '';
                      final isChamp =
                          entry['isChampion'] as bool? ?? false;
                      final isRunner =
                          entry['isRunnerUp'] as bool? ?? false;
                      final stage =
                          entry['furthestStage'] as String? ??
                              'Group Stage';
                      final isCurrent =
                          entry['tournamentId']?.toString() ==
                              widget.tournamentId;
                      final live = isCurrent
                          ? computeTournamentStats(
                                  matches: _matches, rosters: _rosters)
                              .standingFor(widget.teamId)
                          : null;
                      final w = live?.w ?? (entry['wins'] as int? ?? 0);
                      final d = live?.d ?? (entry['draws'] as int? ?? 0);
                      final l = live?.l ?? (entry['losses'] as int? ?? 0);
                      String resultText;
                      String resultEmoji;
                      if (isChamp) {
                        resultEmoji = '🏆';
                        resultText = 'Champion';
                      } else if (isRunner) {
                        resultEmoji = '🥈';
                        resultText = 'Runner-Up';
                      } else {
                        resultEmoji = '';
                        resultText = stage;
                      }
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                      overflow:
                                          TextOverflow.ellipsis),
                                  Text(
                                    '$resultEmoji $resultText'
                                        .trim(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isChamp
                                          ? const Color(0xFFFFD700)
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$w W / $d D / $l L',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSquadTab(BuildContext context) {
    final sorted = _sortedPlayers();
    final team = _team;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // Coach section
        if (team?.coachName != null && team!.coachName!.isNotEmpty) ...[
          _sectionHeader(context, 'COACHING STAFF'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                TeamLogo(
                  url: team.coachPhotoUrl,
                  size: 44,
                  fallbackIcon: Icons.person,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.coachName!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      'Head Coach',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
        ],
        _sectionHeader(context, 'PLAYERS'),
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No roster data available',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
          )
        else
          ...sorted.map((p) => _buildPlayerRow(context, p)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildPlayerRow(BuildContext context, TournamentPlayer p) {
    return InkWell(
      onTap: () => openPlayerProfileById(context, uid: p.uid, name: p.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            // Jersey number
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  p.number ?? '-',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Photo
            TeamLogo(
              url: p.photoUrl,
              size: 36,
              fallbackIcon: Icons.person,
            ),
            const SizedBox(width: 10),
            // Name + position
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  if (p.position != null && p.position!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.position!,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab(BuildContext context) {
    final players = _players;
    if (players.isEmpty) {
      return const Center(child: Text('No player data'));
    }

    final categories = [
      {'label': 'Goals', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'Defensive Plays (DPL)', 'stat': 'dpl'},
      {'label': 'Clean Sheets', 'stat': 'cleanSheets'},
      {'label': 'Yellow Cards', 'stat': 'yellowCards'},
      {'label': 'Red Cards', 'stat': 'redCards'},
    ];

    final stats = computeTournamentStats(matches: _matches, rosters: _rosters);
    int getValue(TournamentPlayer p, String stat) =>
        stats.statByName(p.teamId, p.name, stat);

    List<TournamentPlayer> getAllSorted(String stat) {
      final filtered = players.where((p) => getValue(p, stat) > 0).toList()
        ..sort((a, b) => getValue(b, stat).compareTo(getValue(a, stat)));
      return filtered;
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: categories.length,
      itemBuilder: (context, idx) {
        final cat = categories[idx];
        final label = cat['label']!;
        final stat = cat['stat']!;
        final allSorted = getAllSorted(stat);
        if (allSorted.isEmpty) return const SizedBox.shrink();

        final isExpanded = _expandedStats.contains(stat);
        final displayed =
            isExpanded ? allSorted : allSorted.take(3).toList();

        return GestureDetector(
          onTap: () {
            setState(() {
              if (_expandedStats.contains(stat)) {
                _expandedStats.remove(stat);
              } else {
                _expandedStats.add(stat);
              }
            });
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
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
                    final value = getValue(player, stat);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          TeamLogo(
                            url: player.photoUrl,
                            size: 36,
                            fallbackIcon: Icons.person,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              player.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
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
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeasonRecord(BuildContext context) {
    if (_team == null) return const SizedBox.shrink();

    final computed = computeTournamentStats(matches: _matches, rosters: _rosters);
    final s = computed.standingFor(widget.teamId);

    final stats = [
      {'label': 'W', 'value': '${s.w}'},
      {'label': 'D', 'value': '${s.d}'},
      {'label': 'L', 'value': '${s.l}'},
      {'label': 'GF', 'value': '${s.gs}'},
      {'label': 'GA', 'value': '${s.gc}'},
      {'label': 'GD', 'value': s.gd >= 0 ? '+${s.gd}' : '${s.gd}'},
      {'label': 'Pts', 'value': '${s.pts}'},
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tournament Record',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: TournamentColors.headerBackground(context),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'Something went wrong.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _loadError = null;
                    });
                    _loadData();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: TournamentColors.headerBackground(context),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: TournamentColors.headerBackground(context),
              foregroundColor: Colors.white,
              actions: [
                FollowBell(
                  topic: teamTopic(widget.tournamentId, widget.teamId),
                  label: _team?.name ?? 'this team',
                  kind: 'team',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeader(context),
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
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(context),
            _buildSquadTab(context),
            _buildStatsTab(context),
          ],
        ),
      ),
    );
  }
}
