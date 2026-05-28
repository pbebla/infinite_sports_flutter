import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';

class KnockoutTab extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final String? tournamentId;

  const KnockoutTab({
    super.key,
    required this.matches,
    required this.teams,
    this.tournamentId,
  });

  @override
  State<KnockoutTab> createState() => _KnockoutTabState();
}

class _KnockoutTabState extends State<KnockoutTab> {
  String? _selectedRound;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Pre-select the first knockout round
    final knockoutMatches =
        widget.matches.where((m) => _isKnockout(m.stage)).toList();
    if (knockoutMatches.isNotEmpty) {
      final roundsSet = <String>{};
      for (final m in knockoutMatches) {
        roundsSet.add(_normaliseRound(m.stage));
      }
      final rounds =
          _roundOrder.where((r) => roundsSet.contains(r)).toList();
      if (rounds.isNotEmpty) _selectedRound = rounds.first;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToRound(List<String> rounds, int index) {
    if (!_scrollController.hasClients) return;
    final offset = (index * 204.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  static const List<String> _roundOrder = [
    'Quarterfinal',
    'Quarterfinals',
    'Semifinal',
    'Semifinals',
    'Final',
    'Championship',
  ];

  // Normalise stage name for display and ordering
  String _normaliseRound(String stage) {
    switch (stage.toLowerCase()) {
      case 'quarterfinal':
      case 'quarterfinals':
        return 'Quarterfinal';
      case 'semifinal':
      case 'semifinals':
        return 'Semifinal';
      case 'final':
      case 'championship':
        return 'Final';
      default:
        return stage;
    }
  }

  bool _isKnockout(String stage) {
    final s = stage.toLowerCase();
    return s == 'quarterfinal' ||
        s == 'quarterfinals' ||
        s == 'semifinal' ||
        s == 'semifinals' ||
        s == 'final' ||
        s == 'championship';
  }

  @override
  Widget build(BuildContext context) {
    final knockoutMatches =
        widget.matches.where((m) => _isKnockout(m.stage)).toList();

    if (knockoutMatches.isEmpty) {
      return const Center(child: Text('Knockout stage not yet available'));
    }

    // Build ordered unique rounds
    final roundsSet = <String>{};
    for (final m in knockoutMatches) {
      roundsSet.add(_normaliseRound(m.stage));
    }
    final rounds = _roundOrder
        .where((r) => roundsSet.contains(r))
        .toList();

    // Group by normalised round
    final Map<String, List<TournamentMatch>> byRound = {};
    for (final m in knockoutMatches) {
      final nr = _normaliseRound(m.stage);
      byRound.putIfAbsent(nr, () => []).add(m);
    }
    for (final r in byRound.keys) {
      byRound[r]!.sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));
    }

    // Eliminated teams across all knockout matches
    final eliminated = <String>{};
    for (final m in knockoutMatches) {
      if (m.status == 2) {
        final loser = m.loserTeamId;
        if (loser.isNotEmpty) eliminated.add(loser);
      }
    }

    return Column(
      children: [
        // Round selector chips
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rounds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final round = rounds[index];
              final selected = round == _selectedRound;
              return ChoiceChip(
                label: Text(round),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedRound = round);
                  _scrollToRound(rounds, index);
                },
                selectedColor: Theme.of(context).colorScheme.primary,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            },
          ),
        ),
        // Bracket view – horizontal scroll with all rounds visible
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rounds.map((round) {
                final roundMatches = byRound[round] ?? [];
                final isFinal = round == 'Final';
                return Container(
                  width: isFinal ? 200 : 180,
                  margin: const EdgeInsets.only(right: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          round,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: round == _selectedRound
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      ...roundMatches.map((match) => _buildMatchCard(
                          context, match, eliminated, isFinal)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchCard(
    BuildContext context,
    TournamentMatch match,
    Set<String> eliminated,
    bool isFinal,
  ) {
    final team1 = match.team1Id != null ? widget.teams[match.team1Id] : null;
    final team2 = match.team2Id != null ? widget.teams[match.team2Id] : null;

    final isFinalMatch = isFinal;
    final isLive = match.status == 1;
    final isComplete = match.status == 2;
    final winner = isComplete ? match.winnerTeamId : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: isFinalMatch
            ? Border.all(color: const Color(0xFFFFD700), width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          if (isFinalMatch)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(Icons.emoji_events,
                  size: 20, color: const Color(0xFFFFD700)),
            ),
          _teamRow(
            context: context,
            match: match,
            teamId: match.team1Id,
            team: team1,
            seed: match.team1Seed,
            score: match.team1Score,
            isEliminated: match.team1Id != null &&
                eliminated.contains(match.team1Id) &&
                !(winner == match.team1Id),
            isWinner: winner == match.team1Id,
            isFinal: isComplete,
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          _teamRow(
            context: context,
            match: match,
            teamId: match.team2Id,
            team: team2,
            seed: match.team2Seed,
            score: match.team2Score,
            isEliminated: match.team2Id != null &&
                eliminated.contains(match.team2Id) &&
                !(winner == match.team2Id),
            isWinner: winner == match.team2Id,
            isFinal: isComplete,
          ),
          if (isLive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: const Center(
                child: Text(
                  'LIVE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamRow({
    required BuildContext context,
    required TournamentMatch match,
    required String? teamId,
    required TournamentTeam? team,
    required int? seed,
    required int score,
    required bool isEliminated,
    required bool isWinner,
    required bool isFinal,
  }) {
    String displayName;
    if (team != null) {
      displayName = team.name;
    } else if (seed != null) {
      displayName = 'Seed #$seed';
    } else if (teamId != null && teamId.isNotEmpty) {
      displayName = teamId;
    } else {
      displayName = 'TBD';
    }

    Widget logoWidget;
    if (team?.logoUrl != null && team!.logoUrl!.isNotEmpty) {
      logoWidget = ClipOval(
        child: Image.network(
          team.logoUrl!,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.shield, size: 24, color: Colors.grey),
        ),
      );
    } else {
      logoWidget = const Icon(Icons.shield, size: 24, color: Colors.grey);
    }

    if (isEliminated) {
      logoWidget = Opacity(opacity: 0.5, child: logoWidget);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          logoWidget,
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: (team != null && widget.tournamentId != null)
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TournamentTeamDetailPage(
                            teamId: team.id,
                            tournamentId: widget.tournamentId!,
                          ),
                        ),
                      );
                    }
                  : null,
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                  fontStyle: (team == null && seed != null)
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: isEliminated
                      ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                      : team == null
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)
                          : null,
                  decoration: isEliminated ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (isFinal)
            Text(
              '$score',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                color: isEliminated
                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

