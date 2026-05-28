import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentplayerprofile.dart';

class TournamentTeamDetailPage extends StatefulWidget {
  final String teamId;
  final String tournamentId;

  const TournamentTeamDetailPage({
    super.key,
    required this.teamId,
    required this.tournamentId,
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final teams = await TournamentService.getTeams(widget.tournamentId);
      final rosters =
          await TournamentService.getRosters(widget.tournamentId, teams);
      final players = rosters[widget.teamId] ?? [];

      if (!mounted) return;
      setState(() {
        _team = teams[widget.teamId];
        _players = players;
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
    // Determine header color
    Color headerColor = team?.overrideColor ?? const Color(0xFF1A237E);

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
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: (team?.logoUrl != null && team!.logoUrl!.isNotEmpty)
                        ? ClipOval(
                            child: Image.network(
                              team.logoUrl!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(
                                  Icons.shield,
                                  size: 34,
                                  color: Colors.white),
                            ),
                          )
                        : const Icon(Icons.shield, size: 34, color: Colors.white),
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
          painter: _JerseyPainter(color: color),
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
                              painter: _JerseyPainter(
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
                              painter: _JerseyPainter(
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
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: (team.coachPhotoUrl != null &&
                                team.coachPhotoUrl!.isNotEmpty)
                            ? ClipOval(
                                child: Image.network(
                                  team.coachPhotoUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => const Icon(
                                      Icons.person,
                                      size: 24,
                                      color: Colors.grey),
                                ),
                              )
                            : const Icon(Icons.person,
                                size: 24, color: Colors.grey),
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
                      final w = entry['wins'] as int? ?? 0;
                      final d = entry['draws'] as int? ?? 0;
                      final l = entry['losses'] as int? ?? 0;
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: (team.coachPhotoUrl != null && team.coachPhotoUrl!.isNotEmpty)
                      ? ClipOval(
                          child: Image.network(
                            team.coachPhotoUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) =>
                                const Icon(Icons.person, size: 24, color: Colors.grey),
                          ),
                        )
                      : const Icon(Icons.person, size: 24, color: Colors.grey),
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
    final team = _team;
    final tournamentName = team?.name ?? widget.tournamentId;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TournamentPlayerProfilePage(
              player: p,
              tournamentName: tournamentName,
            ),
          ),
        );
      },
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
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
                  ? ClipOval(
                      child: Image.network(
                        p.photoUrl!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            const Icon(Icons.person, size: 20, color: Colors.grey),
                      ),
                    )
                  : const Icon(Icons.person, size: 20, color: Colors.grey),
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
      {'label': 'Top Scorer', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'Defensive Plays (DPL)', 'stat': 'dpl'},
      {'label': 'Clean Sheets', 'stat': 'cleanSheets'},
      {'label': 'Yellow Cards', 'stat': 'yellowCards'},
      {'label': 'Red Cards', 'stat': 'redCards'},
    ];

    int getValue(TournamentPlayer p, String stat) {
      switch (stat) {
        case 'goals': return p.goals;
        case 'assists': return p.assists;
        case 'saves': return p.saves;
        case 'dpl': return p.dpl;
        case 'cleanSheets': return p.cleanSheets;
        case 'yellowCards': return p.yellowCards;
        case 'redCards': return p.redCards;
        default: return 0;
      }
    }

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
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: (player.photoUrl != null &&
                                    player.photoUrl!.isNotEmpty)
                                ? ClipOval(
                                    child: Image.network(
                                      player.photoUrl!,
                                      width: 36,
                                      height: 36,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Icon(
                                          Icons.person,
                                          size: 22,
                                          color: Colors.grey),
                                    ),
                                  )
                                : const Icon(Icons.person,
                                    size: 22, color: Colors.grey),
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
    final team = _team;
    if (team == null) return const SizedBox.shrink();

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
          backgroundColor: const Color(0xFF1A237E),
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
          backgroundColor: const Color(0xFF1A237E),
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
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
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

class _JerseyPainter extends CustomPainter {
  final Color color;
  const _JerseyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h * 0.2);
    path.lineTo(w * 0.25, h * 0.08);
    path.lineTo(w * 0.35, 0);
    path.lineTo(w * 0.5, h * 0.12);
    path.lineTo(w * 0.65, 0);
    path.lineTo(w * 0.75, h * 0.08);
    path.lineTo(w, h * 0.2);
    path.lineTo(w * 0.75, h * 0.38);
    path.lineTo(w * 0.75, h);
    path.lineTo(w * 0.25, h);
    path.lineTo(w * 0.25, h * 0.38);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _JerseyPainter old) => old.color != color;
}
