import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

class MatchFactsTab extends StatelessWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final List<TournamentPlayer> team1Players;
  final List<TournamentPlayer> team2Players;

  const MatchFactsTab({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.team1Players,
    required this.team2Players,
  });

  // Parse minute string to sortable double: "90+3'" -> 90.3, "45'" -> 45.0
  double _parseMinute(String min) {
    final clean = min.replaceAll("'", '').trim();
    if (clean.contains('+')) {
      final parts = clean.split('+');
      final base = double.tryParse(parts[0].trim()) ?? 0;
      final extra = double.tryParse(parts[1].trim()) ?? 0;
      return base + extra * 0.1;
    }
    return double.tryParse(clean) ?? 0;
  }

  /// Flattens an activity map into a list of events.
  /// Each entry: {minute, eventType, playerName, isTeam1}
  List<Map<String, dynamic>> _parseActivity(
      Map<String, dynamic>? activity, bool isTeam1) {
    if (activity == null) return [];
    final List<Map<String, dynamic>> events = [];
    activity.forEach((minute, value) {
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            item.forEach((eventType, playerName) {
              events.add({
                'minute': minute.toString(),
                'eventType': eventType.toString(),
                'playerName': playerName?.toString() ?? '',
                'isTeam1': isTeam1,
              });
            });
          }
        }
      } else if (value is Map) {
        value.forEach((eventType, playerName) {
          events.add({
            'minute': minute.toString(),
            'eventType': eventType.toString(),
            'playerName': playerName?.toString() ?? '',
            'isTeam1': isTeam1,
          });
        });
      }
    });
    return events;
  }

  IconData _iconForEvent(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'goal':
        return Icons.sports_soccer;
      case 'own goal':
        return Icons.sports_soccer;
      case 'assist':
        return Icons.directions_run;
      case 'yellow card':
        return Icons.square;
      case 'red card':
        return Icons.square;
      case 'second yellow':
        return Icons.square;
      case 'dpl':
        return Icons.sports_kabaddi;
      case 'save':
        return Icons.back_hand;
      case 'foul':
        return Icons.warning_amber;
      default:
        return Icons.sports;
    }
  }

  Color _colorForEvent(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'goal':
        return Colors.green;
      case 'own goal':
        return Colors.red;
      case 'assist':
        return Colors.lightGreen;
      case 'yellow card':
        return Colors.amber;
      case 'red card':
        return Colors.red;
      case 'second yellow':
        return Colors.orange;
      case 'dpl':
        return Colors.deepOrange;
      case 'save':
        return Colors.purple;
      case 'foul':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _eventIcon(String eventType) {
    final lower = eventType.toLowerCase();
    // Goal: emoji soccer ball
    if (lower == 'goal') {
      return const Text('⚽', style: TextStyle(fontSize: 16));
    }
    // Own goal: red soccer icon
    if (lower == 'own goal') {
      return const Icon(Icons.sports_soccer, color: Colors.red, size: 18);
    }
    // Assist: soccer boot icon
    if (lower == 'assist') {
      return const FaIcon(FontAwesomeIcons.shoePrints, size: 15, color: Colors.black87);
    }
    // Second yellow: stacked yellow + red card widget
    if (lower == 'second yellow') {
      return Stack(
        children: [
          Transform.rotate(
            angle: -0.15,
            child: Container(
              width: 11,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 5,
            child: Transform.rotate(
              angle: 0.15,
              child: Container(
                width: 11,
                height: 15,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final icon = _iconForEvent(eventType);
    final color = _colorForEvent(eventType);
    if (lower == 'yellow card' || lower == 'red card') {
      return Icon(icon, color: color, size: 16);
    }
    return Icon(icon, color: color, size: 18);
  }

  Widget _buildEventRow(BuildContext context, Map<String, dynamic> event) {
    final isTeam1 = event['isTeam1'] as bool;
    final minute = event['minute'] as String;
    final eventType = event['eventType'] as String;
    final playerName = event['playerName'] as String;

    Widget eventContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isTeam1) ...[
          _eventIcon(eventType),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              playerName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else ...[
          Flexible(
            child: Text(
              playerName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          _eventIcon(eventType),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: isTeam1 ? eventContent : const SizedBox.shrink(),
          ),
          Container(
            width: 48,
            alignment: Alignment.center,
            child: Text(
              minute,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: !isTeam1
                ? Align(alignment: Alignment.centerRight, child: eventContent)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchLeaders(BuildContext context) {
    final allPlayers = [...team1Players, ...team2Players];

    final categories = [
      {'label': 'Goals', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'DPL', 'stat': 'dpl'},
      {'label': 'Yellow Cards', 'stat': 'yellowCards'},
    ];

    int getValue(TournamentPlayer p, String stat) {
      switch (stat) {
        case 'goals':
          return p.goals;
        case 'assists':
          return p.assists;
        case 'saves':
          return p.saves;
        case 'dpl':
          return p.dpl;
        case 'yellowCards':
          return p.yellowCards;
        default:
          return 0;
      }
    }

    final List<Widget> rows = [];
    for (final cat in categories) {
      final label = cat['label']!;
      final stat = cat['stat']!;
      final sorted = allPlayers
          .where((p) => getValue(p, stat) > 0)
          .toList()
        ..sort((a, b) => getValue(b, stat).compareTo(getValue(a, stat)));
      if (sorted.isEmpty) continue;
      final top = sorted.first;
      final value = getValue(top, stat);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${top.name} (${top.teamName})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: infiniteSportsPrimaryColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            'Match Leaders',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: rows),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Parse and merge all events
    final List<Map<String, dynamic>> allEvents = [
      ..._parseActivity(match.team1Activity, true),
      ..._parseActivity(match.team2Activity, false),
    ];

    // Sort by minute
    allEvents.sort((a, b) {
      return _parseMinute(a['minute'] as String)
          .compareTo(_parseMinute(b['minute'] as String));
    });

    if (allEvents.isEmpty && team1Players.isEmpty && team2Players.isEmpty) {
      return Center(
        child: Text(
          match.matchStatus.isPending ? 'Match not started yet' : 'No activity recorded',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Header row showing team names
    Widget teamHeader = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              team1?.name ?? 'Team 1',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 48),
          Expanded(
            child: Text(
              team2?.name ?? 'Team 2',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          teamHeader,
          const Divider(height: 1),
          if (allEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No activity recorded yet',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            ...allEvents.map((e) => _buildEventRow(context, e)),
          _buildMatchLeaders(context),
        ],
      ),
    );
  }
}
