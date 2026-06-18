import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/model/tournamentplayer.dart';
import 'package:infinite_sports_flutter/widgets/team_logo.dart';

// Change 1: calm blue accent, replaces brand red inside the prediction room/card
const Color predictionAccent = Color(0xFF2D6CDF);

// Correct answer green — ONLY used when finished + correct (Change 2)
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
  final String? team1LogoUrl;
  final String? team2LogoUrl;
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
    this.team1LogoUrl,
    this.team2LogoUrl,
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

  // Player-award wheel state
  int _awardTeam = 0; // 0 = team1, 1 = team2
  late FixedExtentScrollController _awardController;

  @override
  void initState() {
    super.initState();
    _initScoreFromAnswer(widget.answer);
    _initAwardFromAnswer(widget.answer);
  }

  @override
  void didUpdateWidget(covariant PredictionQuestionCard old) {
    super.didUpdateWidget(old);
    if (widget.answer != old.answer) {
      _initScoreFromAnswer(widget.answer);
      // Only re-sync wheel if the answer changed externally (not from user
      // interaction in this widget — avoid jumpy re-init mid-scroll).
      _syncAwardFromAnswer(widget.answer);
    }
  }

  @override
  void dispose() {
    _awardController.dispose();
    super.dispose();
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

  void _initAwardFromAnswer(String? answer) {
    int team = 0;
    int idx = 0;
    if (answer != null) {
      final t2idx = widget.team2Players.indexWhere((p) => p.name == answer);
      if (t2idx >= 0) {
        team = 1;
        idx = t2idx;
      } else {
        final t1idx = widget.team1Players.indexWhere((p) => p.name == answer);
        if (t1idx >= 0) idx = t1idx;
      }
    }
    _awardTeam = team;
    _awardController = FixedExtentScrollController(initialItem: idx);
  }

  /// Sync wheel position when answer changes externally (no setState needed for
  /// controller — jumpToItem handles it).
  void _syncAwardFromAnswer(String? answer) {
    if (answer == null) return;
    final t2idx = widget.team2Players.indexWhere((p) => p.name == answer);
    if (t2idx >= 0) {
      if (_awardTeam != 1) setState(() => _awardTeam = 1);
      _awardController.jumpToItem(t2idx);
    } else {
      final t1idx = widget.team1Players.indexWhere((p) => p.name == answer);
      if (t1idx >= 0) {
        if (_awardTeam != 0) setState(() => _awardTeam = 0);
        _awardController.jumpToItem(t1idx);
      }
    }
  }

  bool get _interactive =>
      widget.isSignedIn && !widget.locked && !widget.finished;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    // Change 7: pluralize points
    final pts = q.points;
    final ptsLabel = '$pts ${pts == 1 ? 'pt' : 'pts'}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Change 1: blue-tinted header strip; Change 3: derived question text
          Container(
            color: predictionAccent.withValues(alpha: 0.06),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(questionDisplayText(q),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                // Change 1: blue points pill; Change 7: pluralized
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: predictionAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(ptsLabel,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          // Input area
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInput(context),
                // Outcome chip (finished state)
                if (widget.finished) ...[
                  const SizedBox(height: 10),
                  _buildOutcome(context),
                ],
              ],
            ),
          ),
        ],
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
        return _buildPlayerAward(context);
    }
  }

  // ── matchWinner ─────────────────────────────────────────────────────────────
  // Change 4: 3 Expanded buttons of equal width, radius ~8, no pill rounding

  Widget _buildMatchWinner() {
    return Row(
      children: [
        Expanded(child: _optionBtnWithLogo(widget.team1Name, 'team1', widget.team1LogoUrl)),
        const SizedBox(width: 6),
        Expanded(child: _optionBtn('Draw', 'draw')),
        const SizedBox(width: 6),
        Expanded(child: _optionBtnWithLogo(widget.team2Name, 'team2', widget.team2LogoUrl)),
      ],
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

  Widget _buildPlayerAward(BuildContext context) {
    final t1 = widget.team1Players;
    final t2 = widget.team2Players;

    if (t1.isEmpty && t2.isEmpty) {
      return const Text('No roster available.',
          style: TextStyle(fontSize: 12, color: Colors.grey));
    }

    // Read-only when locked/finished
    if (!_interactive) {
      final answer = widget.answer;
      return Text(
        answer != null && answer.isNotEmpty ? 'Your pick: $answer' : 'No pick',
        style: TextStyle(
            fontSize: 13,
            color: answer != null && answer.isNotEmpty
                ? null
                : Colors.grey),
      );
    }

    final activePlayers = _awardTeam == 0 ? t1 : t2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Team toggle — Change 1: blue accent; Change 5: size 24 logos
        Row(
          children: [
            Expanded(child: _teamToggleBtn(0, widget.team1Name, widget.team1LogoUrl)),
            const SizedBox(width: 8),
            Expanded(child: _teamToggleBtn(1, widget.team2Name, widget.team2LogoUrl)),
          ],
        ),
        const SizedBox(height: 10),
        // Scroll wheel
        if (activePlayers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No roster for this team.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          )
        else
          SizedBox(
            height: 140,
            child: CupertinoPicker(
              scrollController: _awardController,
              itemExtent: 36,
              onSelectedItemChanged: (index) {
                if (index < activePlayers.length) {
                  widget.onAnswer(activePlayers[index].name);
                }
              },
              children: activePlayers.map((p) {
                final label =
                    '#${p.number ?? '-'}  ${p.name}';
                return Center(
                  child: Text(label,
                      style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // Change 1: use predictionAccent; Change 5: size 24 logos
  Widget _teamToggleBtn(int teamIdx, String name, String? logoUrl) {
    final selected = _awardTeam == teamIdx;
    return GestureDetector(
      onTap: () {
        if (_awardTeam == teamIdx) return;
        setState(() {
          _awardTeam = teamIdx;
        });
        // Jump to item 0 on the new controller (rebuild creates same controller)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _awardController.hasClients) {
            _awardController.jumpToItem(0);
            // Submit the first player of the newly selected team
            final players =
                teamIdx == 0 ? widget.team1Players : widget.team2Players;
            if (players.isNotEmpty) {
              widget.onAnswer(players[0].name);
            }
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? predictionAccent.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: selected ? predictionAccent : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Change 5: size 24
            TeamLogo(url: logoUrl, size: 24),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  // Change 1: blue accent for selected text
                  color: selected ? predictionAccent : null,
                ),
              ),
            ),
          ],
        ),
      ),
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

  /// A toggle-style button.
  /// Change 2: selected PRE-finish = blue (predictionAccent); finished+correct = green (handled by outcome chip).
  /// Change 4 (matchWinner): radius 8 applied at call site via OutlinedButton shape override.
  Widget _optionBtn(String label, String value) {
    final selected = widget.answer == value;
    final canTap = _interactive;
    // Change 2: blue for selected-before-finish; no special coloring post-finish
    // (outcome chip shows green/grey; option boxes stay neutral when finished)
    final Color borderColor =
        selected ? predictionAccent : Colors.grey.shade400;
    final Color? bgColor =
        selected ? predictionAccent.withValues(alpha: 0.1) : null;
    final Color? fgColor = selected ? predictionAccent : null;

    return OutlinedButton(
      onPressed: canTap ? () => widget.onAnswer(value) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        // Change 4: smaller corner radius for matchWinner-style buttons
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: borderColor, width: 1.5),
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        disabledBackgroundColor:
            selected ? predictionAccent.withValues(alpha: 0.08) : null,
        disabledForegroundColor:
            selected ? predictionAccent : Colors.grey,
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500)),
    );
  }

  /// Like [_optionBtn] but with a small team logo leading the label.
  /// Change 2: selected = blue (predictionAccent) not green.
  /// Change 4: radius 8, 2-line text.
  /// Change 5: size 24 logos.
  Widget _optionBtnWithLogo(String label, String value, String? logoUrl) {
    final selected = widget.answer == value;
    final canTap = _interactive;
    final Color borderColor =
        selected ? predictionAccent : Colors.grey.shade400;
    final Color? bgColor =
        selected ? predictionAccent.withValues(alpha: 0.1) : null;
    final Color? fgColor = selected ? predictionAccent : null;

    return OutlinedButton(
      onPressed: canTap ? () => widget.onAnswer(value) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: borderColor, width: 1.5),
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        disabledBackgroundColor:
            selected ? predictionAccent.withValues(alpha: 0.08) : null,
        disabledForegroundColor:
            selected ? predictionAccent : Colors.grey,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Change 5: size 24
          TeamLogo(url: logoUrl, size: 24),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
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
  // Change 2: green ONLY shown here (finished+correct). Option boxes use blue
  // when selected pre-finish; no special color when just disabled post-finish.

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
        color = _greenWin; // green ONLY here (correct after finish)
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
      color = _greenWin; // green ONLY here (correct after finish)
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
