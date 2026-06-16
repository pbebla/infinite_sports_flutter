import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/login.dart';
import 'package:infinite_sports_flutter/misc/tournament_service.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/tournament_tabs/prediction_question_card.dart';

/// Full-page view for answering all prediction questions for one match.
///
/// Does NOT call FirebaseAuth.instance — the caller passes [currentUid].
class PredictionRoomPage extends StatelessWidget {
  final String tournamentId;
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final PredictionConfig config;
  final String? currentUid;

  const PredictionRoomPage({
    super.key,
    required this.tournamentId,
    required this.match,
    required this.team1,
    required this.team2,
    required this.config,
    required this.currentUid,
  });

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _team1Name => team1?.name ?? match.team1Id ?? 'TBD';
  String get _team2Name => team2?.name ?? match.team2Id ?? 'TBD';
  bool get _hasBothTeams => match.team1Id != null && match.team2Id != null;

  String get _statusSubtitle {
    final status = match.matchStatus;
    if (status.isFinished) return 'Final';
    if (status.isLive) return 'Live';
    return 'Locks at kickoff';
  }

  void _submit(BuildContext context, String qid, String value) {
    final uid = currentUid;
    if (uid == null) return;
    TournamentService.submitAnswer(
      tournamentId,
      match.id,
      uid,
      qid,
      value,
      DateTime.now().millisecondsSinceEpoch,
    ).then((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Prediction Room',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              '$_team1Name vs $_team2Name · $_statusSubtitle',
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65)),
            ),
          ],
        ),
        titleSpacing: 12,
      ),
      body: StreamBuilder<List<PredictionQuestion>>(
        stream: TournamentService.watchTournamentQuestions(tournamentId),
        builder: (context, tourneySnap) {
          return StreamBuilder<List<PredictionQuestion>>(
            stream: TournamentService.watchMatchQuestions(tournamentId, match.id),
            builder: (context, matchSnap) {
              // Merge and sort question lists; tournament-wide + per-match
              final allQuestions = _mergeQuestions(
                tourneySnap.data ?? const [],
                matchSnap.data ?? const [],
              );

              return StreamBuilder<Map<String, String>>(
                stream: TournamentService.watchMatchResults(tournamentId, match.id),
                builder: (context, resultsSnap) {
                  final results = resultsSnap.data ?? const {};

                  // Only open the answer stream when signed in
                  if (currentUid != null) {
                    return StreamBuilder<Map<String, QuestionAnswer>>(
                      stream: TournamentService.watchMyMatchAnswers(
                          tournamentId, match.id, currentUid!),
                      builder: (context, answersSnap) {
                        final answers = answersSnap.data ?? const {};
                        return _buildBody(
                            context, allQuestions, answers, results);
                      },
                    );
                  } else {
                    return _buildBody(
                        context, allQuestions, const {}, results);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  List<PredictionQuestion> _mergeQuestions(
    List<PredictionQuestion> tournament,
    List<PredictionQuestion> matchLevel,
  ) {
    // Per-match questions override tournament-wide ones on an id clash — must
    // match the scoring function's merge direction (per-match wins).
    final byId = <String, PredictionQuestion>{
      for (final q in tournament) q.id: q,
      for (final q in matchLevel) q.id: q,
    };
    final merged = byId.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return merged;
  }

  Widget _buildBody(
    BuildContext context,
    List<PredictionQuestion> questions,
    Map<String, QuestionAnswer> answers,
    Map<String, String> results,
  ) {
    final locked = !match.matchStatus.isPending;
    final finished = match.matchStatus.isFinished;
    final signedIn = currentUid != null;

    // Filter out questions that require both teams when teams are TBD
    final visibleQuestions = questions.where((q) {
      if (!_hasBothTeams &&
          (q.type == QuestionType.matchWinner ||
              q.type == QuestionType.correctScore)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Sign-in banner for guests
        if (!signedIn) _buildSignInBanner(context),

        Expanded(
          child: visibleQuestions.isEmpty
              ? _buildEmpty(context, questions.isEmpty)
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: visibleQuestions.length + 1, // +1 for footer
                  itemBuilder: (context, index) {
                    if (index == visibleQuestions.length) {
                      return _buildFooter(context);
                    }
                    final q = visibleQuestions[index];
                    return PredictionQuestionCard(
                      question: q,
                      answer: answers[q.id]?.value,
                      customResult: results[q.id],
                      locked: locked,
                      finished: finished,
                      isSignedIn: signedIn,
                      finalTeam1: match.team1Score,
                      finalTeam2: match.team2Score,
                      team1Name: _team1Name,
                      team2Name: _team2Name,
                      onAnswer: (v) => _submit(context, q.id, v),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, bool noQuestionsAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              noQuestionsAtAll
                  ? 'No predictions for this match yet.'
                  : 'Opens when both teams are set.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('All games'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sign in to predict and earn points',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextButton.icon(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back, size: 16),
        label: const Text('All games'),
      ),
    );
  }
}
