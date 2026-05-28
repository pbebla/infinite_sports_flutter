import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

class TournamentPlayerProfilePage extends StatefulWidget {
  final TournamentPlayer player;
  final String tournamentName;

  const TournamentPlayerProfilePage({
    super.key,
    required this.player,
    required this.tournamentName,
  });

  @override
  State<TournamentPlayerProfilePage> createState() =>
      _TournamentPlayerProfilePageState();
}

class _TournamentPlayerProfilePageState
    extends State<TournamentPlayerProfilePage> {
  Future<List<Map<String, String>>>? _historyFuture;

  @override
  void initState() {
    super.initState();
    if (widget.player.uid != null && widget.player.uid!.isNotEmpty) {
      _historyFuture = _loadHistory(widget.player.uid!);
    }
  }

  Future<List<Map<String, String>>> _loadHistory(String uid) async {
    try {
      DatabaseReference ref =
          FirebaseDatabase.instance.ref('/Users/$uid/Played');
      var snap = await ref.get();
      if (snap.value == null) return [];
      // Guard against malformed data (e.g. a list or scalar at this path)
      if (snap.value is! Map) return [];
      final data = snap.value as Map;
      final List<Map<String, String>> history = [];
      data.forEach((k, v) {
        if (v is Map) {
          history.add({
            'season': k.toString(),
            'sport': v['Sport']?.toString() ?? v['sport']?.toString() ?? '',
            'team': v['Team']?.toString() ?? v['team']?.toString() ?? '',
          });
        }
      });
      return history;
    } catch (e, st) {
      debugPrint('tournamentplayerprofile._loadHistory error: $e\n$st');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(context, player),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              _buildProfileCard(context, player),
              _buildStatsCard(context, player),
              _buildLeagueHistory(context, player),
              const SizedBox(height: 24),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TournamentPlayer player) {
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
          padding: const EdgeInsets.fromLTRB(56, 12, 16, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: player.photoUrl != null && player.photoUrl!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          player.photoUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(
                              Icons.person,
                              size: 32,
                              color: Colors.white),
                        ),
                      )
                    : const Icon(Icons.person, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      player.teamName,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, TournamentPlayer player) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _profileItem(context, 'Number', player.number ?? '-'),
            _divider(),
            _profileItem(context, 'Position', player.position ?? '-'),
            _divider(),
            _profileItem(context, 'Team', player.teamName),
          ],
        ),
      ),
    );
  }

  Widget _profileItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.grey.withValues(alpha: 0.3),
    );
  }

  Widget _buildStatsCard(BuildContext context, TournamentPlayer player) {
    final stats = [
      {'label': 'Goals', 'value': '${player.goals}'},
      {'label': 'Assists', 'value': '${player.assists}'},
      {'label': 'G+A', 'value': '${player.goalsAndAssists}'},
      {'label': 'Saves', 'value': '${player.saves}'},
      {'label': 'DPL', 'value': '${player.dpl}'},
      {'label': 'Clean Sheets', 'value': '${player.cleanSheets}'},
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.tournamentName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.0,
              children: stats.map((s) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s['value']!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    Text(
                      s['label']!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                      textAlign: TextAlign.center,
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

  Widget _buildLeagueHistory(BuildContext context, TournamentPlayer player) {
    if (player.uid == null || player.uid!.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('League History',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                'No linked account',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('League History',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            FutureBuilder<List<Map<String, String>>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final history = snapshot.data ?? [];
                if (history.isEmpty) {
                  return Text(
                    'No league history found',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
                  );
                }
                return Column(
                  children: history.map((entry) {
                    final sport = entry['sport'] ?? '';
                    IconData sportIcon;
                    switch (sport.toLowerCase()) {
                      case 'futsal':
                      case 'soccer':
                        sportIcon = Icons.sports_soccer;
                        break;
                      case 'basketball':
                        sportIcon = Icons.sports_basketball;
                        break;
                      case 'flag football':
                        sportIcon = Icons.sports_football;
                        break;
                      default:
                        sportIcon = Icons.sports;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(sportIcon,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry['season'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                                if (entry['team'] != null &&
                                    entry['team']!.isNotEmpty)
                                  Text(
                                    entry['team']!,
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
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

