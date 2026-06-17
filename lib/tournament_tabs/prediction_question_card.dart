import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';

const _greenWin = Color(0xFF0A7D2C);

/// A Firebase-free, testable card for a single prediction question.
///
/// The parent is responsible for all Firebase I/O; this widget is pure UI.
class PredictionQuestionCard extends StatefulWidget {
  final PredictionQuestion question;
  final String? answer; // current saved answer value (null = unanswered)
  final String? customResult; // owner-set winning option id for custom questions
  final bool locked; // match not pending -> inputs disabled
  final bool finished; // match final -> show outcome chip
  final bool isSignedIn;
  final int finalTeam1;
  final int finalTeam2;
  final String team1Name;
  final String team2Name;
  final List<TournamentPlayer> team1Players;
  final List<TournamentPlayer> team2Players;
  final Set<String> playerLeaders; // actual stat leaders; empty until finished
  final void Function(String value) onAnswer;

  const PredictionQuestionCard({
    super.key,
    required this.question,
    required this.answer,
    required this.customResult,
    required this.locked,
    required this.finished,
    required this.isSignedIn,
    required this.finalTeam1,
    required this.finalTeam2,
    required this.team1Name,
    required this.team2Name,
    this.team1Players = const [],
    this.team2Players = const [],
    this.playerLeaders = const {},
    required this.onAnswer,
  });

  @override
  State<PredictionQuestionCard> createState() => _PredictionQuestionCardState();
}

class _PredictionQuestionCardState extends State<PredictionQuestionCard> {
  // Local stepper state for correctScore — mirrors what was saved, or 0/0.
  late int _t1;
  late int _t2;

  @override
  void initState() {
    super.initState();
    _initScoreFromAnswer(widget.answer);
  }

  @override
  void didUpdateWidget(covariant PredictionQuestionCard old) {
    super.didUpdateWidget(old);
    if (widget.answer != old.answer) {
      _initScoreFromAnswer(widget.answer);
    }
  }

  void _initScoreFromAnswer(String? answer) {
    if (answer != null && answer.contains('-')) {
      final parts = answer.split('-');
      _t1 = int.tryParse(parts[0]) ?? 0;
      _t2 = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    } else {
      _t1 = 0;
      _t2 = 0;
    }
  }

  bool get _interactive =>
      widget.isSignedIn && !widget.locked && !widget.finished;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: question text + points pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(q.text,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _greenWin.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${q.points} pts',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _greenWin)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Input area
            _buildInput(context),
            // Outcome chip (finished state)
            if (widget.finished) ...[
              const SizedBox(height: 10),
              _buildOutcome(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (widget.question.type) {
      case QuestionType.matchWinner:
        return _buildMatchWinner();
      case QuestionType.correctScore:
        return _buildCorrectScore();
      case QuestionType.totalGoals:
        return _buildTotalGoals();
      case QuestionType.custom:
        return _buildCustom();
      case QuestionType.playerAward:
        return _buildPlayerAward();
    }
  }

  // ── matchWinner ─────────────────────────────────────────────────────────────

  Widget _buildMatchWinner() {
    return Row(
      children: [
        _optionBtn(widget.team1Name, 'team1'),
        const SizedBox(width: 6),
        _optionBtn('Draw', 'draw'),
        const SizedBox(width: 6),
        _optionBtn(widget.team2Name, 'team2'),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  // ── correctScore ─────────────────────────────────────────────────────────────

  Widget _buildCorrectScore() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: Text(widget.team1Name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
        _stepper(
          value: _t1,
          enabled: _interactive,
          onChange: (v) {
            setState(() => _t1 = v);
            widget.onAnswer('$v-$_t2');
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(':', style: TextStyle(fontSize: 18)),
        ),
        _stepper(
          value: _t2,
          enabled: _interactive,
          onChange: (v) {
            setState(() => _t2 = v);
            widget.onAnswer('$_t1-$v');
          },
        ),
        Expanded(
          child: Center(
            child: Text(widget.team2Name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── totalGoals ──────────────────────────────────────────────────────────────

  Widget _buildTotalGoals() {
    final line = widget.question.line ?? 2.5;
    // Drop trailing .0 for whole numbers
    final lineStr =
        line == line.truncateToDouble() ? line.toInt().toString() : '$line';
    return Row(
      children: [
        _optionBtn('Over $lineStr', 'over'),
        const SizedBox(width: 8),
        _optionBtn('Under $lineStr', 'under'),
      ].map((w) => Expanded(child: w)).toList(),
    );
  }

  // ── playerAward ──────────────────────────────────────────────────────────────

  Widget _buildPlayerAward() {
    final t1 = widget.team1Players;
    final t2 = widget.team2Players;
    if (t1.isEmpty && t2.isEmpty) {
      return const Text('No roster available.',
          style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t1.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(widget.team1Name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: t1.map((p) => _playerChip(p)).toList(),
          ),
          const SizedBox(height: 8),
        ],
        if (t2.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(widget.team2Name,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: t2.map((p) => _playerChip(p)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _playerChip(TournamentPlayer player) {
    final selected = widget.answer == player.name;
    final canTap = _interactive;
    final label = player.number != null ? '#${player.number} ${player.name}' : player.name;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : null)),
      selected: selected,
      selectedColor: _greenWin,
      onSelected: canTap ? (_) => widget.onAnswer(player.name) : null,
    );
  }

  // ── custom ───────────────────────────────────────────────────────────────────

  Widget _buildCustom() {
    final opts = widget.question.options;
    if (opts.isEmpty) {
      return const Text('No options available.',
          style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: opts.map((o) => _optionBtn(o.label, o.id)).toList(),
    );
  }

  // ── shared helpers ────────────────────────────────────────────────────────

  /// A toggle-style button; highlighted in green when selected.
  Widget _optionBtn(String label, String value) {
    final selected = widget.answer == value;
    final canTap = _interactive;
    return OutlinedButton(
      onPressed: canTap ? () => widget.onAnswer(value) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        side: BorderSide(
            color: selected ? _greenWin : Colors.grey.shade400, width: 1.5),
        backgroundColor: selected ? _greenWin.withValues(alpha: 0.1) : null,
        foregroundColor: selected ? _greenWin : null,
        disabledBackgroundColor:
            selected ? _greenWin.withValues(alpha: 0.08) : null,
        disabledForegroundColor: selected ? _greenWin : Colors.grey,
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500)),
    );
  }

  Widget _stepper({
    required int value,
    required bool enabled,
    required ValueChanged<int> onChange,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBtn(Icons.add, enabled ? () => onChange(value + 1) : null),
        Text('$value',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800)),
        _stepBtn(
            Icons.remove, (enabled && value > 0) ? () => onChange(value - 1) : null),
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
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon,
              size: 14,
              color: onTap == null ? Colors.grey.shade300 : null),
        ),
      );

  // ── outcome chip ─────────────────────────────────────────────────────────

  Widget _buildOutcome(BuildContext context) {
    final q = widget.question;
    final answer = widget.answer;

    // playerAward outcome uses leader membership, not the generic scoring fn.
    if (q.type == QuestionType.playerAward) {
      return _buildPlayerAwardOutcome(context, answer);
    }

    String label;
    Color color;

    if (answer == null) {
      label = 'No answer';
      color = Colors.grey;
    } else if (q.type == QuestionType.custom && widget.customResult == null) {
      label = 'Awaiting result';
      color = Colors.orange.shade700;
    } else {
      final score = questionPoints(
        question: q,
        answer: answer,
        finalTeam1: widget.finalTeam1,
        finalTeam2: widget.finalTeam2,
        customResult: widget.customResult,
      );
      if (score.correct) {
        label = '✓ +${score.points}';
        color = _greenWin;
      } else {
        label = '✗';
        color = Colors.grey;
      }
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color)),
      ),
    );
  }

  Widget _buildPlayerAwardOutcome(BuildContext context, String? answer) {
    final leaders = widget.playerLeaders;
    final q = widget.question;

    String label;
    Color color;

    if (answer == null) {
      label = 'No answer';
      color = Colors.grey;
    } else if (leaders.isEmpty) {
      label = 'No result';
      color = Colors.orange.shade700;
    } else if (leaders.contains(answer)) {
      label = '✓ +${q.points}';
      color = _greenWin;
    } else {
      label = '✗';
      color = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
        ),
        if (leaders.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Led by: ${leaders.join(', ')}',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55)),
            textAlign: TextAlign.right,
          ),
        ],
      ],
    );
  }
}
