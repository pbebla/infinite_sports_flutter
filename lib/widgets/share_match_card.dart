import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/share_card_leaders.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';

/// Fixed-size, theme-independent match card rendered to a PNG for sharing.
/// Logical size 360x450; capture at pixelRatio 3 -> 1080x1350.
class ShareMatchCard extends StatelessWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final String tournamentName;

  const ShareMatchCard({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.tournamentName,
  });

  static const double kWidth = 360;
  static const double kHeight = 450;
  static const Color _primary = Color(0xFFD00000);
  static const Color _default1 = Color(0xFF1565C0);
  static const Color _default2 = Color(0xFFC62828);
  static const Color _footer = Color(0xFF111111);

  static const _statIcons = <String, String>{
    'goals': 'assets/goal.png',
    'assists': 'assets/assist.png',
    'dpl': 'assets/dpl.png',
    'saves': 'assets/save.png',
  };

  @override
  Widget build(BuildContext context) {
    final finished = match.matchStatus.isFinished;
    final live = match.matchStatus.isLive;
    final showStats = finished || live;
    final winnerId = match.winnerTeamId; // '' if draw or not finished
    final name1 = team1?.name ?? match.team1Id ?? 'TBD';
    final name2 = team2?.name ?? match.team2Id ?? 'TBD';
    final c1 = team1?.homeColor ?? _default1;
    final c2 = team2?.homeColor ?? _default2;
    final header = tournamentName.isNotEmpty
        ? '$tournamentName · ${match.stage}'
        : match.stage;

    return SizedBox(
      width: kWidth,
      height: kHeight,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _half(
                  name: name1,
                  score: match.team1Score,
                  color: c1,
                  team1: true,
                  showStats: showStats,
                  isWinner:
                      winnerId.isNotEmpty && winnerId == (match.team1Id ?? '#'),
                  logoUrl: team1?.logoUrl,
                ),
              ),
              Expanded(
                child: _half(
                  name: name2,
                  score: match.team2Score,
                  color: c2,
                  team1: false,
                  showStats: showStats,
                  isWinner:
                      winnerId.isNotEmpty && winnerId == (match.team2Id ?? '#'),
                  logoUrl: team2?.logoUrl,
                ),
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 10,
            right: 10,
            child: Text(
              header.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
              ),
            ),
          ),
          Align(
              alignment: const Alignment(0, -0.36),
              child: _centerPill(finished, live)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: _footer,
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '▶ Follow '),
                    TextSpan(
                        text: 'Infinite Sports',
                        style: TextStyle(color: Color(0xFFFF5A5A))),
                    TextSpan(text: ' for live scores'),
                  ],
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _half({
    required String name,
    required int score,
    required Color color,
    required bool team1,
    required bool showStats,
    required bool isWinner,
    required String? logoUrl,
  }) {
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(10, 34, 10, 52),
      child: Column(
        mainAxisAlignment:
            showStats ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          _logo(logoUrl),
          const SizedBox(height: 6),
          Text(name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          if (showStats) ...[
            Text('$score',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w800)),
            SizedBox(
              height: 16,
              child: isWinner
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(7)),
                      child: Text('👑 WINNERS',
                          style: TextStyle(
                              color: color,
                              fontSize: 8,
                              fontWeight: FontWeight.w800)))
                  : null,
            ),
            const SizedBox(height: 8),
            _statRow('goals', team1),
            _statRow('assists', team1),
            _statRow('dpl', team1),
            _statRow('saves', team1),
          ],
        ],
      ),
    );
  }

  Widget _logo(String? url) {
    const double size = 44;
    final shield = Container(
      width: size,
      height: size,
      decoration:
          const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
      child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
    );
    if (url == null || url.isEmpty) return shield;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => shield,
      ),
    );
  }

  Widget _statRow(String stat, bool team1) {
    final list = topNForStat(match, team1, stat);
    final text = list.isEmpty
        ? '—'
        : list.map((e) => '${e.name} ${e.count}').join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Image.asset(_statIcons[stat]!, width: 13, height: 13),
          const SizedBox(width: 5),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 9, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _centerPill(bool finished, bool live) {
    String label;
    if (finished) {
      label = 'FINAL';
    } else if (live) {
      label = 'LIVE  ${match.team1Score}-${match.team2Score}';
    } else {
      final t = match.time;
      label = t != null && t.isNotEmpty ? 'KICKOFF\n$t' : 'UPCOMING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)]),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: live ? _primary : const Color(0xFF111111),
              fontSize: 9,
              height: 1.3,
              fontWeight: FontWeight.w800)),
    );
  }
}
