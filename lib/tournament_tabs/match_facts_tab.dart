import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
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

  Widget _eventIcon(String eventType) {
    return StatIcon(asset: statIconAsset(eventType), size: 24);
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

    int getValue(TournamentPlayer p, String stat) => p.statByName(stat);

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

  Widget _buildIconLegend(BuildContext context) {
    // [eventType, label] for all 13 icons, in approved order.
    const items = <List<String>>[
      ['goal', 'Goal'],
      ['own goal', 'Own goal'],
      ['penalty goal', 'Goal by penalty'],
      ['penalty missed', 'Missed penalty'],
      ['penalty saved', 'Saved penalty'],
      ['save', 'Save (goalkeeper)'],
      ['assist', 'Assist'],
      ['substitution', 'Substitution'],
      ['yellow card', 'Yellow card'],
      ['red card', 'Red card'],
      ['second yellow', 'Second yellow (= red)'],
      ['foul', 'Foul'],
      ['dpl', 'DPL — Defensive Play (Tackle, Steal, Block)'],
    ];

    Widget cell(List<String> item, {required bool rightColumn}) {
      return Padding(
        // Right column is nudged toward the middle, away from the left line.
        padding: EdgeInsets.only(left: rightColumn ? 14 : 0, bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StatIcon(asset: statIconAsset(item[0]), size: 30),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item[1],
                style: const TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
          ],
        ),
      );
    }

    // Two columns running downward: pair items (left, right). A trailing odd
    // item occupies the left column only.
    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cell(items[i], rightColumn: false)),
          Expanded(
            child: (i + 1 < items.length)
                ? cell(items[i + 1], rightColumn: true)
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'What the icons mean',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(children: rows),
        ),
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
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  match.matchStatus.isPending ? 'Match not started yet' : 'No activity recorded',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            _buildIconLegend(context),
          ],
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
          _buildIconLegend(context),
        ],
      ),
    );
  }
}
