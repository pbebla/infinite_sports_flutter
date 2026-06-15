import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';

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
  /// Each entry: {minute, eventType, playerName, subOn, subOff, isTeam1}
  List<Map<String, dynamic>> _parseActivity(
      Map<String, dynamic>? activity, bool isTeam1) {
    if (activity == null) return [];
    final List<Map<String, dynamic>> events = [];
    activity.forEach((minute, value) {
      if (value is List) {
        for (final item in value) {
          if (item is Map) {
            item.forEach((eventType, playerName) {
              final isSub = eventType.toString() == 'substitution';
              String? subOn, subOff, displayName;
              if (isSub && playerName is Map) {
                subOn = (playerName['On'] ?? playerName['on'])?.toString();
                subOff = (playerName['Off'] ?? playerName['off'])?.toString();
                displayName = subOff;
              } else if (isSub) {
                // Legacy scalar substitution: treat the name as the OUT player.
                subOff = playerName?.toString();
                displayName = subOff ?? '';
              } else {
                displayName = playerName?.toString() ?? '';
              }
              events.add({
                'minute': minute.toString(),
                'eventType': eventType.toString(),
                'playerName': displayName ?? '',
                'subOn': subOn,
                'subOff': subOff,
                'isTeam1': isTeam1,
              });
            });
          }
        }
      } else if (value is Map) {
        value.forEach((eventType, playerName) {
          final isSub = eventType.toString() == 'substitution';
          String? subOn, subOff, displayName;
          if (isSub && playerName is Map) {
            subOn = (playerName['On'] ?? playerName['on'])?.toString();
            subOff = (playerName['Off'] ?? playerName['off'])?.toString();
            displayName = subOff;
          } else if (isSub) {
            // Legacy scalar substitution: treat the name as the OUT player.
            subOff = playerName?.toString();
            displayName = subOff ?? '';
          } else {
            displayName = playerName?.toString() ?? '';
          }
          events.add({
            'minute': minute.toString(),
            'eventType': eventType.toString(),
            'playerName': displayName ?? '',
            'subOn': subOn,
            'subOff': subOff,
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
    final subOn = event['subOn'] as String?;
    final subOff = event['subOff'] as String?;

    Widget nameWidget;
    if (eventType == 'substitution' && (subOn != null || subOff != null)) {
      nameWidget = Column(
        crossAxisAlignment:
            isTeam1 ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subOn != null)
            Text(subOn,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0A7D2C),
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          if (subOff != null)
            Text(subOff,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
        ],
      );
    } else {
      nameWidget = Text(
        playerName,
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
        textAlign: isTeam1 ? TextAlign.left : TextAlign.right,
      );
    }

    Widget eventContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isTeam1) ...[
          _eventIcon(eventType),
          const SizedBox(width: 4),
          Flexible(child: nameWidget),
        ] else ...[
          Flexible(child: nameWidget),
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

  Widget _buildLocationCard(BuildContext context) {
    final info = match.locationInfo;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final ok = await launchUrl(Uri.parse(info.mapsUrl()),
                  mode: LaunchMode.externalApplication);
              if (!ok) {
                messenger.showSnackBar(
                    const SnackBar(content: Text("Couldn't open maps.")));
              }
            } catch (_) {
              messenger.showSnackBar(
                  const SnackBar(content: Text("Couldn't open maps.")));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info.venue,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (info.field != null) ...[
                        const SizedBox(height: 2),
                        Text(info.field!,
                            style: const TextStyle(
                                color: Color(0xFF1A237E), fontSize: 13)),
                      ],
                      if (info.address != null) ...[
                        const SizedBox(height: 3),
                        Text(info.address!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6),
                                fontSize: 12)),
                      ],
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions, size: 14, color: Color(0xFF1A237E)),
                          SizedBox(width: 4),
                          Text('Get directions',
                              style: TextStyle(
                                  color: Color(0xFF1A237E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatchLeaders(BuildContext context) {
    final allPlayers = [...team1Players, ...team2Players];
    final tallies = singleMatchPlayerTallies(match);

    final categories = [
      {'label': 'Goals', 'stat': 'goals'},
      {'label': 'Assists', 'stat': 'assists'},
      {'label': 'Saves', 'stat': 'saves'},
      {'label': 'DPL', 'stat': 'dpl'},
    ];

    int getValue(TournamentPlayer p, String stat) =>
        tallies[p.name]?.byStat(stat) ?? 0;

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
            _buildLocationCard(context),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _buildLocationCard(context)
        ],
      ),
    );
  }
}
