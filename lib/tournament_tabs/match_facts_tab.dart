import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/tournament_tabs/stat_icon.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/prediction_room_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:infinite_sports_flutter/misc/single_match_tallies.dart';

class MatchFactsTab extends StatelessWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final List<TournamentPlayer> team1Players;
  final List<TournamentPlayer> team2Players;

  // Optional prediction context — Task A6 will pass these from the match-detail
  // page. Defaults to null so all existing call sites keep compiling unchanged.
  final String? tournamentId;
  final PredictionConfig? predictionConfig;
  final String? currentUid;

  const MatchFactsTab({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.team1Players,
    required this.team2Players,
    this.tournamentId,
    this.predictionConfig,
    this.currentUid,
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

    // Teaser visibility: only when prediction context is fully provided and both
    // teams are confirmed — rendered at the very top of either code path.
    final showTeaser = tournamentId != null &&
        predictionConfig?.open == true &&
        match.team1Id != null &&
        match.team2Id != null;

    final teaser = showTeaser
        ? _WhoWillWinTeaser(
            tournamentId: tournamentId!,
            match: match,
            team1: team1,
            team2: team2,
            predictionConfig: predictionConfig!,
            currentUid: currentUid,
            team1Players: team1Players,
            team2Players: team2Players,
          )
        : const SizedBox.shrink();

    if (allEvents.isEmpty && team1Players.isEmpty && team2Players.isEmpty) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            teaser,
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
          teaser,
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

// ── Who Will Win Teaser ───────────────────────────────────────────────────────

const _greenWin = Color(0xFF0A7D2C);

class _WhoWillWinTeaser extends StatefulWidget {
  final String tournamentId;
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final PredictionConfig predictionConfig;
  final String? currentUid;
  final List<TournamentPlayer> team1Players;
  final List<TournamentPlayer> team2Players;

  const _WhoWillWinTeaser({
    required this.tournamentId,
    required this.match,
    required this.team1,
    required this.team2,
    required this.predictionConfig,
    required this.currentUid,
    this.team1Players = const [],
    this.team2Players = const [],
  });

  @override
  State<_WhoWillWinTeaser> createState() => _WhoWillWinTeaserState();
}

class _WhoWillWinTeaserState extends State<_WhoWillWinTeaser> {
  // Whether we are in the middle of submitting (prevents double-taps).
  bool _submitting = false;

  String get _team1Name => widget.team1?.name ?? widget.match.team1Id ?? 'Team 1';
  String get _team2Name => widget.team2?.name ?? widget.match.team2Id ?? 'Team 2';

  Future<void> _submit(String value, String qid) async {
    final uid = widget.currentUid;
    if (uid == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await TournamentService.submitAnswer(
        widget.tournamentId,
        widget.match.id,
        uid,
        qid,
        value,
        DateTime.now().millisecondsSinceEpoch,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _pushRoom(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PredictionRoomPage(
          tournamentId: widget.tournamentId,
          match: widget.match,
          team1: widget.team1,
          team2: widget.team2,
          config: widget.predictionConfig,
          currentUid: widget.currentUid,
          team1Players: widget.team1Players,
          team2Players: widget.team2Players,
        ),
      ),
    );
  }

  void _pushLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Stream the tournament-wide questions and pick the first matchWinner.
    return StreamBuilder<List<PredictionQuestion>>(
      stream: TournamentService.watchTournamentQuestions(widget.tournamentId),
      builder: (context, qSnap) {
        final questions = qSnap.data ?? const [];
        final PredictionQuestion? winnerQ = questions
            .where((q) => q.type == QuestionType.matchWinner)
            .cast<PredictionQuestion?>()
            .firstOrNull;

        if (winnerQ == null) return const SizedBox.shrink();

        final uid = widget.currentUid;
        final isPending = widget.match.matchStatus.isPending;

        // When signed in, also stream the user's current answers for this match.
        if (uid != null) {
          return StreamBuilder<Map<String, QuestionAnswer>>(
            stream: TournamentService.watchMyMatchAnswers(
                widget.tournamentId, widget.match.id, uid),
            builder: (context, ansSnap) {
              final answers = ansSnap.data ?? const {};
              final currentAnswer = answers[winnerQ.id]?.value;
              return _buildCard(
                  context, winnerQ, isPending, currentAnswer, hasAnswer: currentAnswer != null);
            },
          );
        }

        return _buildCard(context, winnerQ, isPending, null, hasAnswer: false);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    PredictionQuestion q,
    bool isPending,
    String? currentAnswer, {
    required bool hasAnswer,
  }) {
    final uid = widget.currentUid;
    final signedIn = uid != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: title + points badge
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Who will win?',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _greenWin.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+${q.points} pt',
                      style: const TextStyle(
                          fontSize: 11,
                          color: _greenWin,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // The three option buttons (team1 / Draw / team2)
              _buildOptions(context, q, isPending, currentAnswer, signedIn),

              const SizedBox(height: 10),

              // Signed-out CTA
              if (!signedIn) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _pushLogin(context),
                    child: const Text('Sign in to predict'),
                  ),
                ),
              ]
              // Signed in + has an answer → show "Enter prediction room →"
              else if (hasAnswer) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: _greenWin.withValues(alpha: 0.12),
                      foregroundColor: _greenWin,
                    ),
                    onPressed: () => _pushRoom(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Image(
                          image: AssetImage('assets/predict_symbolic_256.png'),
                          width: 20,
                          height: 20,
                        ),
                        SizedBox(width: 8),
                        Text('Enter prediction room  →'),
                      ],
                    ),
                  ),
                ),
              ]
              // Locked (live / finished) without having answered → room link still available
              else if (!isPending) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _pushRoom(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Image(
                          image: AssetImage('assets/predict_symbolic_256.png'),
                          width: 20,
                          height: 20,
                        ),
                        SizedBox(width: 8),
                        Text('Enter prediction room  →'),
                      ],
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

  Widget _buildOptions(
    BuildContext context,
    PredictionQuestion q,
    bool isPending,
    String? currentAnswer,
    bool signedIn,
  ) {
    final canTap = signedIn && isPending && !_submitting;

    return Row(
      children: [
        Expanded(
          child: _optionButton(
            label: _team1Name,
            value: 'team1',
            isSelected: currentAnswer == 'team1',
            onTap: canTap ? () => _submit('team1', q.id) : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _optionButton(
            label: 'Draw',
            value: 'draw',
            isSelected: currentAnswer == 'draw',
            onTap: canTap ? () => _submit('draw', q.id) : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _optionButton(
            label: _team2Name,
            value: 'team2',
            isSelected: currentAnswer == 'team2',
            onTap: canTap ? () => _submit('team2', q.id) : null,
          ),
        ),
      ],
    );
  }

  Widget _optionButton({
    required String label,
    required String value,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    final selected = isSelected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? _greenWin : Colors.transparent,
          border: Border.all(
            color: selected ? _greenWin : Colors.grey.shade400,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}
