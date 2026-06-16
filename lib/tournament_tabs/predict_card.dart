import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/model/tournamentteam.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

const _greenWin = Color(0xFF0A7D2C);

class PredictCard extends StatefulWidget {
  final TournamentMatch match;
  final TournamentTeam? team1;
  final TournamentTeam? team2;
  final PredictionConfig config;
  final MatchPrediction? myPrediction;
  final bool isSignedIn;
  final void Function(int team1, int team2) onSubmit;
  final VoidCallback onSignIn;

  const PredictCard({
    super.key,
    required this.match,
    required this.team1,
    required this.team2,
    required this.config,
    required this.myPrediction,
    required this.isSignedIn,
    required this.onSubmit,
    required this.onSignIn,
  });

  @override
  State<PredictCard> createState() => _PredictCardState();
}

class _PredictCardState extends State<PredictCard> {
  late int _t1;
  late int _t2;

  @override
  void initState() {
    super.initState();
    _t1 = widget.myPrediction?.team1 ?? 0;
    _t2 = widget.myPrediction?.team2 ?? 0;
  }

  @override
  void didUpdateWidget(covariant PredictCard old) {
    super.didUpdateWidget(old);
    if (widget.myPrediction != null &&
        (widget.myPrediction!.team1 != old.myPrediction?.team1 ||
            widget.myPrediction!.team2 != old.myPrediction?.team2)) {
      _t1 = widget.myPrediction!.team1;
      _t2 = widget.myPrediction!.team2;
    }
  }

  String _name(TournamentTeam? t, String? id) => t?.name ?? id ?? 'TBD';

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final scheduled = m.matchStatus.isPending;
    final finished = m.matchStatus.isFinished;
    final hasBothTeams = m.team1Id != null && m.team2Id != null;
    final n1 = _name(widget.team1, m.team1Id);
    final n2 = _name(widget.team2, m.team2Id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.time ?? ''} · ${m.label}',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 10),
            if (!hasBothTeams)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Prediction opens when both teams are set.',
                    style: TextStyle(fontSize: 12.5)),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                      child: _teamCell(widget.team1, n1, alignEnd: true)),
                  _stepper(value: _t1, enabled: scheduled && widget.isSignedIn,
                      onChange: (v) => setState(() => _t1 = v)),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(':', style: TextStyle(fontSize: 18))),
                  _stepper(value: _t2, enabled: scheduled && widget.isSignedIn,
                      onChange: (v) => setState(() => _t2 = v)),
                  Expanded(child: _teamCell(widget.team2, n2, alignEnd: false)),
                ],
              ),
              const SizedBox(height: 10),
              if (!widget.isSignedIn)
                _signInCta()
              else if (scheduled)
                _scheduledFooter(n1, n2)
              else if (finished)
                _resultFooter(m)
              else
                _lockedFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamCell(TournamentTeam? t, String name, {required bool alignEnd}) {
    final logo = TeamLogo(url: t?.logoUrl, size: 26);
    final text = Flexible(
      child: Text(name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [text, const SizedBox(width: 6), logo]
          : [logo, const SizedBox(width: 6), text],
    );
  }

  Widget _stepper(
      {required int value,
      required bool enabled,
      required ValueChanged<int> onChange}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(Icons.add, enabled ? () => onChange(value + 1) : null),
        Text('$value',
            style:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        _stepBtn(Icons.remove,
            (enabled && value > 0) ? () => onChange(value - 1) : null),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(
                  color: onTap == null ? Colors.grey.shade300 : Colors.grey),
              borderRadius: BorderRadius.circular(5)),
          child: Icon(icon,
              size: 14, color: onTap == null ? Colors.grey.shade300 : null),
        ),
      );

  Widget _signInCta() => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: widget.onSignIn,
          child: const Text('Sign in to predict'),
        ),
      );

  Widget _scheduledFooter(String n1, String n2) {
    final pick = _t1 > _t2
        ? 'backing $n1 to win'
        : _t1 < _t2
            ? 'backing $n2 to win'
            : 'predicting a draw';
    final mw = widget.config.matchWinnerPoints;
    final eb = widget.config.exactScorePoints;
    final saved = widget.myPrediction != null &&
        widget.myPrediction!.team1 == _t1 &&
        widget.myPrediction!.team2 == _t2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('By predicting $_t1–$_t2, you\'re $pick.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 8),
        Text('+$mw correct winner · +$eb exact score (up to ${mw + eb})',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6))),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: saved ? null : () => widget.onSubmit(_t1, _t2),
          child: Text(saved
              ? 'Locked in — tap a stepper to change'
              : (widget.myPrediction == null
                  ? 'Lock prediction'
                  : 'Update pick')),
        ),
      ],
    );
  }

  Widget _lockedFooter() => Text(
        widget.myPrediction == null
            ? 'No prediction — locked at kickoff.'
            : 'Locked: your pick ${widget.myPrediction!.team1}–${widget.myPrediction!.team2}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      );

  Widget _resultFooter(TournamentMatch m) {
    if (widget.myPrediction == null) {
      return Text('No prediction · Final ${m.team1Score}–${m.team2Score}',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12));
    }
    final r = predictionPoints(
      predTeam1: widget.myPrediction!.team1,
      predTeam2: widget.myPrediction!.team2,
      actualTeam1: m.team1Score,
      actualTeam2: m.team2Score,
      matchWinnerPoints: widget.config.matchWinnerPoints,
      exactScorePoints: widget.config.exactScorePoints,
    );
    final label = r.exactCorrect
        ? 'Exact! +${r.points} pts'
        : r.resultCorrect
            ? 'Right winner +${r.points}'
            : '0 pts';
    return Text(
      'Your pick ${widget.myPrediction!.team1}–${widget.myPrediction!.team2} · '
      'Final ${m.team1Score}–${m.team2Score} · $label',
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: r.points > 0 ? _greenWin : null),
    );
  }
}
