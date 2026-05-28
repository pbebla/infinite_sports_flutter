import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournament_stage.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_match_detail.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class FixturesTab extends StatelessWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;
  final String tournamentId;
  final String sport;

  const FixturesTab({
    super.key,
    required this.matches,
    required this.teams,
    required this.rosters,
    required this.tournamentId,
    required this.sport,
  });

  String _formatDate(String mmddyyyy) {
    final dt = parseDatabaseDate(mmddyyyy);
    if (dt == null) return mmddyyyy;
    return DateFormat('EEEE, MMMM d').format(dt);
  }

  Set<String> _getEliminatedTeams() {
    final eliminated = <String>{};
    for (final match in matches) {
      final stage = TournamentStage.fromString(match.stage);
      if (stage != TournamentStage.group && match.matchStatus.isFinished) {
        final loser = match.loserTeamId;
        if (loser.isNotEmpty) eliminated.add(loser);
      }
    }
    return eliminated;
  }

  String _stageLabelShort(String stage) {
    final ts = TournamentStage.fromString(stage);
    switch (ts) {
      case TournamentStage.group:
        return 'Group';
      case TournamentStage.roundOf16:
        return 'R16';
      case TournamentStage.quarterFinal:
        return 'QF';
      case TournamentStage.semiFinal:
        return 'SF';
      case TournamentStage.thirdPlace:
        return '3rd';
      case TournamentStage.finalStage:
        return 'Final';
      case TournamentStage.unknown:
        return stage;
    }
  }

  // Build a compact leaders strip for completed matches
  Widget _buildLeadersStrip(BuildContext context, TournamentMatch match) {
    if (!match.matchStatus.isFinished) return const SizedBox.shrink();
    final team1Players = match.team1Id != null ? (rosters[match.team1Id] ?? []) : <TournamentPlayer>[];
    final team2Players = match.team2Id != null ? (rosters[match.team2Id] ?? []) : <TournamentPlayer>[];
    final allPlayers = [...team1Players, ...team2Players];
    if (allPlayers.isEmpty) return const SizedBox.shrink();

    final statDefs = [
      {'label': 'G', 'icon': null, 'faIcon': null, 'emoji': '⚽', 'color': Colors.green, 'stat': 'goals'},
      {'label': 'A', 'icon': null, 'faIcon': FontAwesomeIcons.shoePrints, 'emoji': null, 'color': Colors.black87, 'stat': 'assists'},
      {'label': 'S', 'icon': Icons.back_hand, 'faIcon': null, 'emoji': null, 'color': Colors.purple, 'stat': 'saves'},
      {'label': 'DPL', 'icon': Icons.sports_kabaddi, 'faIcon': null, 'emoji': null, 'color': Colors.teal, 'stat': 'dpl'},
    ];

    final chips = <Widget>[];
    for (final def in statDefs) {
      final stat = def['stat'] as String;
      final sorted = allPlayers
          .where((p) => p.statByName(stat) > 0)
          .toList()
        ..sort((a, b) => b.statByName(stat).compareTo(a.statByName(stat)));
      if (sorted.isEmpty) continue;
      final top = sorted.first;
      final value = top.statByName(stat);
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (def['emoji'] != null)
                Text(def['emoji'] as String, style: const TextStyle(fontSize: 12))
              else if (def['faIcon'] != null)
                FaIcon(def['faIcon'] as FaIconData, size: 12, color: def['color'] as Color)
              else
                Icon(def['icon'] as IconData, size: 12, color: def['color'] as Color),
              const SizedBox(width: 3),
              Text(
                '${top.name} $value',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: chips,
      ),
    );
  }

  Widget _buildMatchCard(
    BuildContext context,
    TournamentMatch match,
    Set<String> eliminatedTeams,
  ) {
    final team1 = match.team1Id != null ? teams[match.team1Id] : null;
    final team2 = match.team2Id != null ? teams[match.team2Id] : null;

    final team1Eliminated =
        match.team1Id != null && eliminatedTeams.contains(match.team1Id);
    final team2Eliminated =
        match.team2Id != null && eliminatedTeams.contains(match.team2Id);

    final isLive = match.matchStatus.isLive;
    final isFinal = match.matchStatus.isFinished;

    final team1IsWinner = isFinal && match.winnerTeamId == match.team1Id;
    final team2IsWinner = isFinal && match.winnerTeamId == match.team2Id;

    // Display name helper
    String teamName(TournamentTeam? team, String? teamId, int? seed) {
      if (team != null) return team.name;
      if (seed != null) return 'Seed #$seed';
      if (teamId != null && teamId.isNotEmpty) return teamId;
      return 'TBD';
    }

    final name1 = teamName(team1, match.team1Id, match.team1Seed);
    final name2 = teamName(team2, match.team2Id, match.team2Seed);

    // Score / time widget in center
    Widget centerWidget;
    if (isLive) {
      centerWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${match.team1Score} - ${match.team2Score}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      );
    } else if (isFinal) {
      centerWidget = Text(
        '${match.team1Score} - ${match.team2Score}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
      );
    } else {
      centerWidget = Text(
        match.time ?? 'TBD',
        style: TextStyle(
          fontSize: 13,
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }

    // Team widget: name right-aligned or left-aligned with logo
    Widget team1Widget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name1,
            style: TextStyle(
              fontWeight: team1IsWinner ? FontWeight.bold : FontWeight.normal,
              decoration:
                  team1Eliminated ? TextDecoration.lineThrough : null,
              fontSize: 13,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        const SizedBox(width: 6),
        TeamLogo(url: team1?.logoUrl, size: 28),
      ],
    );

    Widget team2Widget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamLogo(url: team2?.logoUrl, size: 28),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name2,
            style: TextStyle(
              fontWeight: team2IsWinner ? FontWeight.bold : FontWeight.normal,
              decoration:
                  team2Eliminated ? TextDecoration.lineThrough : null,
              fontSize: 13,
            ),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TournamentMatchDetailPage(
                match: match,
                teams: teams,
                rosters: rosters,
                tournamentId: tournamentId,
                sport: sport,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: stage label + location/live badge
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _stageLabelShort(match.label),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  const Spacer(),
                  if (!isLive && match.matchLocation != null)
                    Text(
                      match.matchLocation!,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // FotMob-style: Team1 [right-aligned] | Score | Team2 [left-aligned]
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: team1Widget,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: centerWidget,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: team2Widget,
                    ),
                  ),
                ],
              ),
              // Leaders strip for completed matches
              _buildLeadersStrip(context, match),
              // Stream link
              if (match.link != null && match.link!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(match.link!);
                      if (uri != null) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Watch', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: infiniteSportsPrimaryColor,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Center(child: Text('No fixtures available'));
    }

    final eliminated = _getEliminatedTeams();

    // Sort matches by stage progression, then by date, then by bracket position
    final sortedMatches = [...matches];
    sortedMatches.sort((a, b) {
      final aStage = TournamentStage.fromString(a.stage).sortOrder;
      final bStage = TournamentStage.fromString(b.stage).sortOrder;
      if (aStage != bStage) return aStage.compareTo(bStage);
      final aDate = int.tryParse(a.date) ?? 0;
      final bDate = int.tryParse(b.date) ?? 0;
      if (aDate != bDate) return aDate.compareTo(bDate);
      return a.bracketPosition.compareTo(b.bracketPosition);
    });

    // Build date groups in stage-based order using LinkedHashMap to preserve insertion order
    final LinkedHashMap<String, List<TournamentMatch>> byDate = LinkedHashMap();
    for (final match in sortedMatches) {
      byDate.putIfAbsent(match.date, () => []).add(match);
    }

    final sortedDates = byDate.keys.toList(); // already in stage order

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: sortedDates.length,
      itemBuilder: (context, dateIdx) {
        final date = sortedDates[dateIdx];
        final dateMatches = byDate[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _formatDate(date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
            ),
            ...dateMatches.map(
                (m) => _buildMatchCard(context, m, eliminated)),
          ],
        );
      },
    );
  }
}
