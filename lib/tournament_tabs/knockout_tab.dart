import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournamentteamdetail.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

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
    final knockoutMatches = widget.matches
        .where((m) => TournamentStage.fromString(m.stage).isKnockout)
        .toList();
    if (knockoutMatches.isNotEmpty) {
      final roundsSet = <String>{};
      for (final m in knockoutMatches) {
        roundsSet.add(TournamentStage.fromString(m.stage).label);
      }
      final rounds = _roundOrder.where((r) => roundsSet.contains(r)).toList();
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

  /// Ordered list of knockout-round display labels, sorted by stage progression.
  static final List<String> _roundOrder = (TournamentStage.values
          .where((s) => s.isKnockout)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      .map((s) => s.label)
      .toList();

  @override
  Widget build(BuildContext context) {
    final knockoutMatches = widget.matches
        .where((m) => TournamentStage.fromString(m.stage).isKnockout)
        .toList();

    if (knockoutMatches.isEmpty) {
      return const Center(child: Text('Knockout stage not yet available'));
    }

    // Build ordered unique rounds
    final roundsSet = <String>{};
    for (final m in knockoutMatches) {
      roundsSet.add(TournamentStage.fromString(m.stage).label);
    }
    final rounds = _roundOrder
        .where((r) => roundsSet.contains(r))
        .toList();

    // Group by normalised round
    final Map<String, List<TournamentMatch>> byRound = {};
    for (final m in knockoutMatches) {
      final nr = TournamentStage.fromString(m.stage).label;
      byRound.putIfAbsent(nr, () => []).add(m);
    }
    for (final r in byRound.keys) {
      byRound[r]!.sort((a, b) => a.bracketPosition.compareTo(b.bracketPosition));
    }

    // Eliminated teams across all knockout matches
    final eliminated = <String>{};
    for (final m in knockoutMatches) {
      if (m.matchStatus.isFinished) {
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
                showCheckmark: false,
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
                final isFinal = round == TournamentStage.finalStage.label;
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
    final isLive = match.matchStatus.isLive;
    final isComplete = match.matchStatus.isFinished;
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
            isLive: isLive,
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
            isLive: isLive,
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
    required bool isLive,
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

    Widget logoWidget = TeamLogo(url: team?.logoUrl, size: 24);
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
                            preloadedTeams: widget.teams,
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
          if (isFinal || isLive)
            Text(
              '$score',
              style: TextStyle(
                fontSize: 15,
                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                color: isLive && !isFinal
                    ? const Color(0xFFD00000)
                    : isEliminated
                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                        : null,
              ),
            ),
        ],
      ),
    );
  }
}

