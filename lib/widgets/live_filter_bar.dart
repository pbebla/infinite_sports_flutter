import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/match_clock.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';

/// Pure helper: the live (status==1) subset, preserving order.
List<TournamentMatch> liveMatches(List<TournamentMatch> all) =>
    all.where((m) => m.status == 1).toList();

/// Grey-dot/green-dot "Live" pill for the top of the Matches tab.
class LivePill extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const LivePill({super.key, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF27E07C);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFEAFAF0) : Colors.transparent,
          border: Border.all(color: on ? green : Colors.grey),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: on ? green : Colors.grey, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text('Live',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? const Color(0xFF0A7D2C) : Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

/// Horizontal "Happening now" rail of live matches. Renders nothing if empty.
/// [onTapMatch] opens the match. Each chip shows "ABBR s-s" + live minute.
class HappeningNowRail extends StatelessWidget {
  final List<TournamentMatch> live;
  final String Function(String teamId) abbr;
  final void Function(TournamentMatch) onTapMatch;
  const HappeningNowRail({
    super.key,
    required this.live,
    required this.abbr,
    required this.onTapMatch,
  });

  @override
  Widget build(BuildContext context) {
    if (live.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            _LiveDot(),
            SizedBox(width: 5),
            Text('HAPPENING NOW',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFFFF1F1F))),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: live.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = live[i];
                final t1 = m.team1Id == null ? '?' : abbr(m.team1Id!);
                final t2 = m.team2Id == null ? '?' : abbr(m.team2Id!);
                return InkWell(
                  onTap: () => onTapMatch(m),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$t1 ${m.team1Score}–${m.team2Score} $t2',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        const SizedBox(height: 3),
                        _RailMinute(clock: m.clock),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RailMinute extends StatelessWidget {
  final MatchClock? clock;
  const _RailMinute({required this.clock});
  @override
  Widget build(BuildContext context) {
    final label = clock == null
        ? 'LIVE'
        : minuteLabel(clock!.elapsedAt(DateTime.now().millisecondsSinceEpoch));
    return Text(label,
        style: const TextStyle(
            color: Color(0xFF7CFC9A), fontWeight: FontWeight.w700, fontSize: 11));
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
            color: Color(0xFFFF1F1F), shape: BoxShape.circle),
      ),
    );
  }
}
