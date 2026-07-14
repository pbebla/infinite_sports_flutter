import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/profile/open_player_profile.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

class MatchLineupTab extends StatelessWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final List<TournamentPlayer> team1Players;
  final List<TournamentPlayer> team2Players;
  final String sport;

  const MatchLineupTab({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.team1Players,
    required this.team2Players,
    required this.sport,
  });

  List<String> _positionOrder(String sport) {
    switch (sport.toLowerCase()) {
      case 'soccer':
      case 'futsal':
        return ['GK', 'GOALKEEPER', 'DEF', 'DEFENDER', 'MID', 'MIDFIELDER', 'FWD', 'FORWARD'];
      case 'basketball':
        return ['PG', 'SG', 'GUARD', 'SF', 'PF', 'FORWARD', 'C', 'CENTER'];
      case 'flag football':
        return ['QB', 'REC', 'OL', 'DEF', 'K'];
      case 'volleyball':
        return ['SETTER', 'OUTSIDE HITTER', 'MIDDLE BLOCKER', 'LIBERO', 'OPPOSITE'];
      default:
        return [];
    }
  }

  List<TournamentPlayer> _sortByPosition(List<TournamentPlayer> players) {
    final order = _positionOrder(sport);
    if (order.isEmpty) {
      return [...players]..sort((a, b) => (a.position ?? '').compareTo(b.position ?? ''));
    }
    return [...players]..sort((a, b) {
        final aPos = (a.position ?? '').toUpperCase();
        final bPos = (b.position ?? '').toUpperCase();
        int aIdx = order.indexWhere((o) => aPos.contains(o));
        int bIdx = order.indexWhere((o) => bPos.contains(o));
        if (aIdx == -1) aIdx = order.length;
        if (bIdx == -1) bIdx = order.length;
        return aIdx.compareTo(bIdx);
      });
  }

  Widget _buildFieldBackground() {
    final s = sport.toLowerCase();
    if (s == 'soccer' || s == 'futsal') {
      return SizedBox(
        height: 180,
        width: double.infinity,
        child: CustomPaint(painter: _SoccerFieldPainter()),
      );
    } else if (s == 'basketball') {
      return SizedBox(
        height: 180,
        width: double.infinity,
        child: CustomPaint(painter: _BasketballCourtPainter()),
      );
    } else if (s == 'flag football') {
      return SizedBox(
        height: 180,
        width: double.infinity,
        child: CustomPaint(painter: _FlagFootballFieldPainter()),
      );
    } else {
      return Container(
        height: 100,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          ),
        ),
      );
    }
  }

  Widget _buildPlayerRow(BuildContext context, TournamentPlayer p) {
    return InkWell(
      onTap: () => openPlayerProfileById(context, uid: p.uid, name: p.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
        child: Row(
          children: [
            // Jersey number badge
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  p.number ?? '-',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p.name,
                softWrap: true,
                overflow: TextOverflow.fade,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTeamColumn(
    BuildContext context,
    TournamentTeam? team,
    List<TournamentPlayer> players,
  ) {
    final sorted = _sortByPosition(players);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coach row if available
          if (team?.coachName != null && team!.coachName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Text(
                    'Coach',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      team.coachName!,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, thickness: 1),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No roster data',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...sorted.map((p) => _buildPlayerRow(context, p)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          _buildFieldBackground(),
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTeamColumn(context, team1, team1Players),
                Container(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                _buildTeamColumn(context, team2, team2Players),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Soccer/Futsal field painter
class _SoccerFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF2E7D32);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Center line
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), linePaint);

    // Center circle
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.22, linePaint);

    // Center dot
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(Offset(w / 2, h / 2), 3, dotPaint);

    // Left penalty area
    final penW = w * 0.12;
    final penH = h * 0.55;
    final penTop = (h - penH) / 2;
    canvas.drawRect(Rect.fromLTWH(0, penTop, penW, penH), linePaint);

    // Right penalty area
    canvas.drawRect(Rect.fromLTWH(w - penW, penTop, penW, penH), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Basketball court painter
class _BasketballCourtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF8D6E63);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Center line
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), linePaint);

    // Center circle
    canvas.drawCircle(Offset(w / 2, h / 2), h * 0.2, linePaint);

    // Left 3-point arc
    final arcRect = Rect.fromCenter(
      center: Offset(0, h / 2),
      width: w * 0.5,
      height: h * 0.8,
    );
    canvas.drawArc(arcRect, -1.2, 2.4, false, linePaint);

    // Right 3-point arc
    final arcRect2 = Rect.fromCenter(
      center: Offset(w, h / 2),
      width: w * 0.5,
      height: h * 0.8,
    );
    canvas.drawArc(arcRect2, 1.9, 2.4, false, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Flag football field painter
class _FlagFootballFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF388E3C);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Yard lines every ~12.5% of width
    for (int i = 1; i <= 7; i++) {
      final x = w * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
    }

    // End zones (slightly darker)
    final endZonePaint = Paint()..color = Colors.black.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.1, h), endZonePaint);
    canvas.drawRect(Rect.fromLTWH(w * 0.9, 0, w * 0.1, h), endZonePaint);

    // End zone borders
    canvas.drawLine(Offset(w * 0.1, 0), Offset(w * 0.1, h), linePaint);
    canvas.drawLine(Offset(w * 0.9, 0), Offset(w * 0.9, h), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
