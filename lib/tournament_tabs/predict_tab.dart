import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_card.dart';

class PredictTab extends StatefulWidget {
  final List<TournamentMatch> matches;
  final Map<String, TournamentTeam> teams;
  final String tournamentId;
  final PredictionConfig config;
  final String? currentUid; // null = signed out

  const PredictTab({
    super.key,
    required this.matches,
    required this.teams,
    required this.tournamentId,
    required this.config,
    required this.currentUid,
  });

  @override
  State<PredictTab> createState() => _PredictTabState();
}

class _PredictTabState extends State<PredictTab> {
  bool _showLeaderboard = false;

  String? get _uid => widget.currentUid;
  bool get _signedIn => _uid != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: _showLeaderboard ? _leaderboardView() : _matchesView(),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Matches')),
                ButtonSegment(value: true, label: Text('Leaderboard')),
              ],
              selected: {_showLeaderboard},
              onSelectionChanged: (s) =>
                  setState(() => _showLeaderboard = s.first),
            ),
          ),
          const SizedBox(width: 10),
          _pointsPill(),
        ],
      ),
    );
  }

  Widget _pointsPill() {
    final uid = _uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<LeaderboardEntry>>(
      stream: TournamentService.watchLeaderboard(widget.tournamentId),
      builder: (context, snap) {
        int? pts;
        for (final e in (snap.data ?? const <LeaderboardEntry>[])) {
          if (e.uid == uid) pts = e.points;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: infiniteSportsPrimaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${pts ?? '—'} pts',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: infiniteSportsPrimaryColor)),
        );
      },
    );
  }

  Widget _matchesView() {
    final uid = _uid;
    return StreamBuilder<Map<String, MatchPrediction>>(
      stream: uid == null
          ? const Stream.empty()
          : TournamentService.watchMyPredictions(widget.tournamentId, uid),
      builder: (context, snap) {
        final mine = snap.data ?? const <String, MatchPrediction>{};
        final sorted = [...widget.matches]..sort((a, b) {
            final d = (int.tryParse(a.date) ?? 0)
                .compareTo(int.tryParse(b.date) ?? 0);
            if (d != 0) return d;
            return a.bracketPosition.compareTo(b.bracketPosition);
          });
        final LinkedHashMap<String, List<TournamentMatch>> byDate =
            LinkedHashMap();
        for (final m in sorted) {
          byDate.putIfAbsent(m.date, () => []).add(m);
        }
        if (byDate.isEmpty) {
          return const Center(child: Text('No matches to predict yet'));
        }
        final dates = byDate.keys.toList();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: dates.length,
          itemBuilder: (context, i) {
            final date = dates[i];
            final dayMatches = byDate[date]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(formatDayHeading(date),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ...dayMatches.map((m) => PredictCard(
                      match: m,
                      team1: m.team1Id != null ? widget.teams[m.team1Id] : null,
                      team2: m.team2Id != null ? widget.teams[m.team2Id] : null,
                      config: widget.config,
                      myPrediction: mine[m.id],
                      isSignedIn: _signedIn,
                      onSignIn: _goSignIn,
                      onSubmit: (t1, t2) => _submit(m.id, t1, t2),
                    )),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit(String matchId, int t1, int t2) async {
    final uid = _uid;
    if (uid == null) return;
    await TournamentService.submitPrediction(
      widget.tournamentId, matchId, uid, t1, t2,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prediction saved')));
    }
  }

  void _goSignIn() {
    Navigator.push(context,
            MaterialPageRoute(builder: (context) => const LoginPage()))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _leaderboardView() {
    return StreamBuilder<List<LeaderboardEntry>>(
      stream: TournamentService.watchLeaderboard(widget.tournamentId),
      builder: (context, snap) {
        final rows = snap.data ?? const <LeaderboardEntry>[];
        if (rows.isEmpty) {
          return const Center(child: Text('Be the first to predict'));
        }
        return ListView.builder(
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(children: [
                  SizedBox(width: 28, child: Text('#', style: TextStyle(fontSize: 11))),
                  Expanded(child: Text('Player', style: TextStyle(fontSize: 11))),
                  SizedBox(width: 44, child: Text('Pts', textAlign: TextAlign.right, style: TextStyle(fontSize: 11))),
                  SizedBox(width: 48, child: Text('Exact', textAlign: TextAlign.right, style: TextStyle(fontSize: 11))),
                ]),
              );
            }
            final e = rows[i - 1];
            final mine = e.uid == _uid;
            return Container(
              color: mine
                  ? infiniteSportsPrimaryColor.withValues(alpha: 0.06)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(children: [
                SizedBox(width: 28, child: Text('$i', style: const TextStyle(fontWeight: FontWeight.bold))),
                Expanded(child: Text(mine ? '${e.name} (you)' : e.name,
                    style: TextStyle(fontWeight: mine ? FontWeight.bold : FontWeight.normal))),
                SizedBox(width: 44, child: Text('${e.points}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                SizedBox(width: 48, child: Text('${e.exact}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF0A7D2C), fontWeight: FontWeight.w700))),
              ]),
            );
          },
        );
      },
    );
  }
}
