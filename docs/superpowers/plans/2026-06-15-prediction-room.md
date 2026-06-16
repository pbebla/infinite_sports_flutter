# Prediction Room Implementation Plan (Predictions Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn the single score prediction into a per-match **Prediction Room** of questions (auto + custom), with the Predict tab as the hub, a match-detail "Who will win?" teaser, Manager question authoring + resolution, and a generalized scoring function.

**Architecture:** Each match's questions = tournament-wide defaults (`Tournaments/{tid}/PredictionQuestions`) ∪ per-match extras (`.../Matches/{mid}/PredictionQuestions`). Fans answer per question at `Predictions/{mid}/{uid}/{qid} = {Answer, UpdatedAt}`. Auto questions resolve from the final score; custom from owner-set `.../Matches/{mid}/PredictionResults/{qid}`. A pure `questionPoints` helper (Dart + TS parity) scores one answer; the deployed Cloud Function sums into the leaderboard.

**Tech Stack:** Flutter (fan + Manager), Firebase RTDB, TypeScript Cloud Functions (vitest).

**Spec:** `docs/superpowers/specs/2026-06-15-prediction-room-design.md`. Builds on Phase 1 (`prediction_scoring.dart`, models, `TournamentService` predict methods, `functions/src/lib/predict.ts`).

## Ground rules
- Fan + functions: `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch `zaya/predictions`. Manager: `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`, branch `zaya-predictions`. Verify branch before committing.
- Commits LOCAL only. Stage exact paths (never `git add -A`). Fan never stages `PROJECT_REFERENCE.md`/`SoccerStats.png`; `git restore pubspec.lock` if it drifts. Windows + git-bash; Manager ops use ABSOLUTE `cd` paths.
- TDD for pure helpers. Dart `questionPoints` and TS `questionPoints` MUST stay in parity (mirrored tests).
- Cloud Functions: extend, build, and **deploy ONLY `onPredict*`** (`--only functions:onPredictMatchStatus,functions:onPredictTeam1Score,functions:onPredictTeam2Score,functions:onPredictResult,functions:onPredictQuestion`) — never touch the Watcher. Deploy only in the final task, after owner OK.

---

# STAGE A — Question model + room/hub/teaser + 3 auto types + Manager defaults + auto scoring

### Task A1: PredictionQuestion model + `questionPoints` helper (fan, pure) [Stage A]

**Files:** Create `lib/model/prediction_question.dart`; Modify `lib/misc/prediction_scoring.dart`; Test `test/prediction_question_test.dart`.

- [ ] **Step 1: Write the failing test** `test/prediction_question_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction_question.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';

void main() {
  group('PredictionQuestion.fromFirebase', () {
    test('matchWinner parses with points/order', () {
      final q = PredictionQuestion.fromFirebase('q_winner',
          {'Text': 'Who will win?', 'Type': 'matchWinner', 'Points': 1, 'Order': 0});
      expect(q.type, QuestionType.matchWinner);
      expect(q.points, 1);
      expect(q.order, 0);
    });
    test('totalGoals parses Line', () {
      final q = PredictionQuestion.fromFirebase('q_tg',
          {'Text': 'Total goals', 'Type': 'totalGoals', 'Points': 2, 'Line': 2.5, 'Order': 2});
      expect(q.type, QuestionType.totalGoals);
      expect(q.line, 2.5);
    });
    test('custom parses Options', () {
      final q = PredictionQuestion.fromFirebase('q_c', {
        'Text': 'Who scores first?', 'Type': 'custom', 'Points': 2, 'Order': 3,
        'Options': {'o1': {'Label': 'Eagles'}, 'o2': {'Label': 'Lions'}},
      });
      expect(q.type, QuestionType.custom);
      expect(q.options.length, 2);
      expect(q.options.map((o) => o.label), containsAll(['Eagles', 'Lions']));
    });
    test('unknown type falls back to custom (no crash)', () {
      final q = PredictionQuestion.fromFirebase('q_x', {'Type': 'weird', 'Points': 1});
      expect(q.type, QuestionType.custom);
    });
  });

  group('questionPoints', () {
    PredictionQuestion winner(int pts) => PredictionQuestion(
        id: 'w', text: 'Who will win?', type: QuestionType.matchWinner,
        points: pts, order: 0, options: const [], line: null);
    test('matchWinner correct', () {
      final r = questionPoints(question: winner(1), answer: 'team1',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, true); expect(r.points, 1); expect(r.isExactScore, false);
    });
    test('matchWinner wrong', () {
      final r = questionPoints(question: winner(1), answer: 'draw',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, false); expect(r.points, 0);
    });
    test('correctScore exact gives points + isExactScore', () {
      final q = PredictionQuestion(id: 's', text: 'Score', type: QuestionType.correctScore,
          points: 3, order: 1, options: const [], line: null);
      final r = questionPoints(question: q, answer: '2-1',
          finalTeam1: 2, finalTeam2: 1, customResult: null);
      expect(r.correct, true); expect(r.points, 3); expect(r.isExactScore, true);
    });
    test('totalGoals over/under (on-the-line counts as under)', () {
      final q = PredictionQuestion(id: 't', text: 'TG', type: QuestionType.totalGoals,
          points: 2, order: 2, options: const [], line: 2.5);
      expect(questionPoints(question: q, answer: 'over', finalTeam1: 2, finalTeam2: 1, customResult: null).correct, true);
      expect(questionPoints(question: q, answer: 'under', finalTeam1: 1, finalTeam2: 1, customResult: null).correct, true);
      final q3 = PredictionQuestion(id: 't', text: 'TG', type: QuestionType.totalGoals,
          points: 2, order: 2, options: const [], line: 3.0);
      // total 3, line 3.0 -> under
      expect(questionPoints(question: q3, answer: 'under', finalTeam1: 2, finalTeam2: 1, customResult: null).correct, true);
    });
    test('custom matches owner-set result; unresolved => not correct', () {
      final q = PredictionQuestion(id: 'c', text: 'First?', type: QuestionType.custom,
          points: 2, order: 3, options: const [QuestionOption('o1','Eagles'), QuestionOption('o2','Lions')], line: null);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: 'o1').points, 2);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: null).points, 0);
      expect(questionPoints(question: q, answer: 'o1', finalTeam1: 0, finalTeam2: 0, customResult: 'o2').points, 0);
    });
  });
}
```

- [ ] **Step 2: Run it — expect FAIL.** `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/prediction_question_test.dart`

- [ ] **Step 3: Create `lib/model/prediction_question.dart`:**
```dart
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

enum QuestionType { matchWinner, correctScore, totalGoals, custom }

QuestionType questionTypeFromString(String? s) {
  switch ((s ?? '').toString()) {
    case 'matchWinner':
      return QuestionType.matchWinner;
    case 'correctScore':
      return QuestionType.correctScore;
    case 'totalGoals':
      return QuestionType.totalGoals;
    default:
      return QuestionType.custom;
  }
}

String questionTypeToString(QuestionType t) => t.name;

class QuestionOption {
  final String id;
  final String label;
  const QuestionOption(this.id, this.label);
}

class PredictionQuestion {
  final String id;
  final String text;
  final QuestionType type;
  final int points;
  final int order;
  final List<QuestionOption> options; // custom only
  final double? line; // totalGoals only

  const PredictionQuestion({
    required this.id,
    required this.text,
    required this.type,
    required this.points,
    required this.order,
    required this.options,
    required this.line,
  });

  factory PredictionQuestion.fromFirebase(String id, dynamic raw) {
    final data = (raw is Map) ? raw : const {};
    final optsRaw = firstNonNull(data, ['Options', 'options']);
    final options = <QuestionOption>[];
    if (optsRaw is Map) {
      optsRaw.forEach((oid, ov) {
        final label = (ov is Map)
            ? (firstNonNull(ov, ['Label', 'label'])?.toString() ?? oid.toString())
            : ov.toString();
        options.add(QuestionOption(oid.toString(), label));
      });
    }
    final lineRaw = firstNonNull(data, ['Line', 'line']);
    return PredictionQuestion(
      id: id,
      text: firstNonNull(data, ['Text', 'text'])?.toString() ?? '',
      type: questionTypeFromString(firstNonNull(data, ['Type', 'type'])?.toString()),
      points: parseInt(firstNonNull(data, ['Points', 'points'])),
      order: parseInt(firstNonNull(data, ['Order', 'order'])),
      options: options,
      line: lineRaw == null ? null : double.tryParse(lineRaw.toString()),
    );
  }

  Map<String, dynamic> toFirebase() => {
        'Text': text,
        'Type': questionTypeToString(type),
        'Points': points,
        'Order': order,
        if (line != null) 'Line': line,
        if (options.isNotEmpty)
          'Options': {for (final o in options) o.id: {'Label': o.label}},
      };
}
```

- [ ] **Step 4: Add `questionPoints` to `lib/misc/prediction_scoring.dart`** (append; keep the existing `predictionPoints`/`PredictionResult`). Add the import at the top of the file: `import 'package:infinite_sports_flutter/model/prediction_question.dart';`
```dart
class QuestionScore {
  final bool correct;
  final int points;
  final bool isExactScore;
  const QuestionScore(
      {required this.correct, required this.points, required this.isExactScore});
}

/// Pure scoring for ONE answer to ONE question. Mirrors functions/src/lib/predict.ts.
/// `answer` encodings: matchWinner -> 'team1'|'draw'|'team2'; totalGoals -> 'over'|'under';
/// correctScore -> 'T1-T2' (e.g. '2-1'); custom -> the chosen option id.
/// `customResult` is the owner-set winning option id for custom questions (null = unresolved).
QuestionScore questionPoints({
  required PredictionQuestion question,
  required String answer,
  required int finalTeam1,
  required int finalTeam2,
  required String? customResult,
}) {
  bool correct = false;
  bool exact = false;
  switch (question.type) {
    case QuestionType.matchWinner:
      final res = finalTeam1 > finalTeam2
          ? 'team1'
          : (finalTeam1 < finalTeam2 ? 'team2' : 'draw');
      correct = answer == res;
      break;
    case QuestionType.correctScore:
      correct = answer == '$finalTeam1-$finalTeam2';
      exact = correct;
      break;
    case QuestionType.totalGoals:
      final line = question.line ?? 2.5;
      final over = (finalTeam1 + finalTeam2) > line;
      correct = answer == (over ? 'over' : 'under');
      break;
    case QuestionType.custom:
      correct = customResult != null && answer == customResult;
      break;
  }
  return QuestionScore(
      correct: correct, points: correct ? question.points : 0, isExactScore: exact);
}
```

- [ ] **Step 5: Run tests — expect PASS** + `flutter analyze lib/model/prediction_question.dart lib/misc/prediction_scoring.dart`. Confirm `firstNonNull`/`parseInt` names against `lib/misc/parse_helpers.dart` (used in Phase 1); adapt if different.

- [ ] **Step 6: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git restore pubspec.lock 2>/dev/null || true
git add lib/model/prediction_question.dart lib/misc/prediction_scoring.dart test/prediction_question_test.dart
git commit -m "feat: prediction question model + questionPoints helper (auto+custom)"
```

---

### Task A2: per-question answer model + service methods (fan) [Stage A]

**Files:** Modify `lib/model/prediction.dart` (add `QuestionAnswer`); Modify `lib/misc/tournament_service.dart`; Test `test/prediction_answer_test.dart`.

- [ ] **Step 1: Failing test** `test/prediction_answer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';

void main() {
  test('QuestionAnswer round-trips', () {
    final a = QuestionAnswer.fromFirebase({'Answer': 'team1', 'UpdatedAt': 123});
    expect(a!.value, 'team1');
    expect(a.updatedAt, 123);
    expect(a.toFirebase(), {'Answer': 'team1', 'UpdatedAt': 123});
  });
  test('null/!map => null', () {
    expect(QuestionAnswer.fromFirebase(null), isNull);
    expect(QuestionAnswer.fromFirebase('x'), isNull);
  });
}
```

- [ ] **Step 2: Run — FAIL.** `flutter test test/prediction_answer_test.dart`

- [ ] **Step 3: Add `QuestionAnswer` to `lib/model/prediction.dart`** (keep the existing `MatchPrediction` for back-compat of any code; new code uses `QuestionAnswer`):
```dart
class QuestionAnswer {
  final String value; // see questionPoints encodings
  final int updatedAt;
  const QuestionAnswer({required this.value, required this.updatedAt});

  static QuestionAnswer? fromFirebase(dynamic raw) {
    if (raw is! Map) return null;
    final v = (raw['Answer'] ?? raw['answer']);
    if (v == null) return null;
    return QuestionAnswer(
      value: v.toString(),
      updatedAt: parseInt(raw['UpdatedAt'] ?? raw['updatedAt']),
    );
  }

  Map<String, dynamic> toFirebase() => {'Answer': value, 'UpdatedAt': updatedAt};
}
```
(`parseInt` is already imported in prediction.dart from Phase 1.)

- [ ] **Step 4: Add service methods to `lib/misc/tournament_service.dart`** (near the Phase-1 predict methods). Add import `import 'package:infinite_sports_flutter/model/prediction_question.dart';`:
```dart
  /// Tournament-wide default questions.
  static Stream<List<PredictionQuestion>> watchTournamentQuestions(String tid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/PredictionQuestions')
        .onValue
        .map((e) => _parseQuestions(e.snapshot.value));
  }

  /// Per-match extra questions.
  static Stream<List<PredictionQuestion>> watchMatchQuestions(String tid, String mid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Matches/$mid/PredictionQuestions')
        .onValue
        .map((e) => _parseQuestions(e.snapshot.value));
  }

  static List<PredictionQuestion> _parseQuestions(dynamic value) {
    final out = <PredictionQuestion>[];
    if (value is Map) {
      value.forEach((qid, q) =>
          out.add(PredictionQuestion.fromFirebase(qid.toString(), q)));
    }
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  /// The signed-in user's answers for one match, keyed by questionId.
  static Stream<Map<String, QuestionAnswer>> watchMyMatchAnswers(
      String tid, String mid, String uid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Predictions/$mid/$uid')
        .onValue
        .map((e) {
      final out = <String, QuestionAnswer>{};
      final v = e.snapshot.value;
      if (v is Map) {
        v.forEach((qid, raw) {
          final a = QuestionAnswer.fromFirebase(raw);
          if (a != null) out[qid.toString()] = a;
        });
      }
      return out;
    });
  }

  static Future<void> submitAnswer(
      String tid, String mid, String uid, String qid, String value, int nowMs) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Predictions/$mid/$uid/$qid')
        .set({'Answer': value, 'UpdatedAt': nowMs});
  }

  /// Owner-set correct option for custom questions (read by the room to show results).
  static Stream<Map<String, String>> watchMatchResults(String tid, String mid) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tid/Matches/$mid/PredictionResults')
        .onValue
        .map((e) {
      final out = <String, String>{};
      final v = e.snapshot.value;
      if (v is Map) v.forEach((qid, opt) => out[qid.toString()] = opt.toString());
      return out;
    });
  }

  /// Count of a user's answered questions for a match (for the hub progress chip).
  static Stream<int> watchMyAnswerCount(String tid, String mid, String uid) =>
      watchMyMatchAnswers(tid, mid, uid).map((m) => m.length);
```
Confirm `QuestionAnswer` is imported (it's in `prediction.dart`, already imported by Phase-1 service code).

- [ ] **Step 5: Run** `flutter test test/prediction_answer_test.dart` (PASS) + `flutter analyze lib/misc/tournament_service.dart lib/model/prediction.dart` (no new errors) + full `flutter test`.

- [ ] **Step 6: Commit**
```bash
git add lib/model/prediction.dart lib/misc/tournament_service.dart test/prediction_answer_test.dart
git commit -m "feat: per-question answer model + question/answer/result service methods"
```

---

### Task A3: Prediction Room page (fan) [Stage A]

**Files:** Create `lib/prediction_room_page.dart`; Test `test/prediction_room_test.dart`.

- [ ] **Step 1: Build the page.** Create `lib/prediction_room_page.dart`. It is a pushed route showing one match's questions. It combines tournament-wide + per-match questions, the user's answers, and (when final) results. Inputs: `tournamentId, match, team1, team2, config, currentUid`. Render per question type:
  - matchWinner: 3 buttons (team1 name / Draw / team2 name) → `submitAnswer(qid, 'team1'|'draw'|'team2')`.
  - correctScore: two +/- steppers → on change, `submitAnswer(qid, '$t1-$t2')`.
  - totalGoals: Over/Under buttons (label uses `question.line`) → `submitAnswer(qid, 'over'|'under')`.
  - custom: one button per option → `submitAnswer(qid, option.id)`.
  Lock all inputs when `match.matchStatus.isPending == false` (i.e., not scheduled). When `match.matchStatus.isFinished`, show each question's outcome using `questionPoints` (auto types) or the result map (custom). Signed-out → a single "Sign in to predict" CTA (reuse the Phase-1 pattern from predict_card.dart). Footer: a `TextButton` "← All games" that `Navigator.pop(context)`.

  Use two `StreamBuilder`s: `watchTournamentQuestions(tid)` + `watchMatchQuestions(tid, mid)` merged (combine via a small `StreamBuilder` nesting or `rxdart`-free nested builders), plus `watchMyMatchAnswers` (skip when signed out) and `watchMatchResults`. Keep it readable: a top-level `StreamBuilder` on tournament questions, nested on match questions, nested on answers+results — or fetch results/answers with their own builders inside each card. Prefer: gather `questions = [...tournamentQs, ...matchQs]..sort(order)` then a `ListView` of `_QuestionCard` widgets, each its own small consumer of the answer/result it needs. Mirror the visual style of the Phase-1 predict card (Card, +/- steppers, green `0xFF0A7D2C` for selected/correct).

  EXACT widget code: model it on `lib/tournament_tabs/predict_card.dart` (steppers, sign-in CTA, finished-result footer) — reuse those building blocks. Each question card shows the question text + its points; selected option highlighted green; on a finished match show "✓ +N" (correct) or "✗" (wrong) or "awaiting result" (unresolved custom).

  NOTE for the implementer: keep this file focused (one page + private `_QuestionCard`). Do not call `FirebaseAuth.instance` inside — take `currentUid` as a param (testability, per Phase-1 lesson).

- [ ] **Step 2: Widget test** `test/prediction_room_test.dart`: pump `PredictionRoomPage` with `currentUid: null`, an empty question set (pass empty via a test-only constructor path OR a match with no questions — since streams hit Firebase, gate the page so that with `currentUid == null` and no Firebase it still renders a header + "Sign in to predict"). If Firebase access blocks a pure widget test (as in Phase 1), assert only the signed-out header/CTA with no questions, and document that full rendering is covered manually. Do NOT add a flaky test.
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/prediction_room_page.dart';

const _cfg = PredictionConfig(open: true, matchWinnerPoints: 1, exactScorePoints: 3);
TournamentMatch _m() => TournamentMatch(
    id: 'm1', stage: 'Group Stage', label: 'Group A', date: '08272026',
    time: '6:00 PM', team1Id: 'A', team2Id: 'B',
    team1Score: 0, team2Score: 0, status: 0, bracketPosition: 0);

void main() {
  testWidgets('signed-out room shows sign-in CTA', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PredictionRoomPage(
        tournamentId: 't1', match: _m(), team1: null, team2: null,
        config: _cfg, currentUid: null,
      ),
    ));
    await tester.pump();
    expect(find.textContaining('Sign in'), findsWidgets);
  });
}
```
If the streams throw without Firebase during `pump`, guard the stream creation behind `currentUid != null` for answers and wrap the questions `StreamBuilder` so a null/empty snapshot renders the empty room — the signed-out test must pass without Firebase init.

- [ ] **Step 3: Run** `flutter test test/prediction_room_test.dart` + `flutter analyze lib/prediction_room_page.dart`. Iterate until the signed-out test passes and analyze is clean.

- [ ] **Step 4: Commit**
```bash
git add lib/prediction_room_page.dart test/prediction_room_test.dart
git commit -m "feat: Prediction Room page (per-match question list, all input types)"
```

---

### Task A4: Predict-tab hub index → push room (fan) [Stage A]

**Files:** Modify `lib/tournament_tabs/predict_tab.dart`.

- [ ] **Step 1:** Replace `_matchesView`'s per-match `PredictCard(...)` with an **index row** that pushes `PredictionRoomPage`. Keep the day grouping + "predictable first" sort already there. Replace the `...dayMatches.map((m) => PredictCard(...))` block with:
```dart
                ...dayMatches.map((m) => _matchIndexRow(context, m)),
```
and add the row builder + remove the now-unused `_submit` and `PredictCard` import (and `MatchPrediction` import if unused):
```dart
  Widget _matchIndexRow(BuildContext context, TournamentMatch m) {
    final n1 = m.team1Id != null ? (widget.teams[m.team1Id]?.name ?? m.team1Id!) : 'TBD';
    final n2 = m.team2Id != null ? (widget.teams[m.team2Id]?.name ?? m.team2Id!) : 'TBD';
    final locked = m.status != 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text('$n1  vs  $n2', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(locked
            ? (m.status == 2 ? 'Final · predictions closed' : 'Live · predictions closed')
            : '${m.time ?? ''} · tap to predict'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PredictionRoomPage(
            tournamentId: widget.tournamentId,
            match: m,
            team1: m.team1Id != null ? widget.teams[m.team1Id] : null,
            team2: m.team2Id != null ? widget.teams[m.team2Id] : null,
            config: widget.config,
            currentUid: widget.currentUid,
          ),
        )),
      ),
    );
  }
```
Add `import 'package:infinite_sports_flutter/prediction_room_page.dart';`. Since the row no longer needs the per-match prediction stream, you may simplify `_matchesView` to drop the `watchMyPredictions` StreamBuilder wrapper (the progress chip is optional — if kept, wrap each row in a small `StreamBuilder<int>` on `watchMyAnswerCount`; for Stage A a simple "tap to predict" subtitle is fine — keep it simple). Remove `_submit`, the `predict_card.dart` import, and `MatchPrediction` import if now unused (let `flutter analyze` guide you).

- [ ] **Step 2: Run** `flutter test` (the existing `predict_tab_test.dart` empty-state test must still pass — the empty list still shows "No matches to predict yet") + `flutter analyze lib/tournament_tabs/predict_tab.dart`.

- [ ] **Step 3: Commit**
```bash
git add lib/tournament_tabs/predict_tab.dart
git commit -m "feat: Predict tab Matches list is now a game index that opens each room"
```

---

### Task A5: Match-detail "Who will win?" teaser (fan) [Stage A]

**Files:** Modify `lib/tournament_tabs/match_facts_tab.dart`.

- [ ] **Step 1:** At the TOP of the Facts tab body (before the existing timeline/Match-Leaders content), add a "Who will win?" teaser, shown only when predictions are open and a matchWinner question exists for the match. Because `MatchFactsTab` is currently a `StatelessWidget` without prediction context, add the needed inputs to its constructor (with defaults so existing call sites keep compiling): `final PredictionConfig? predictionConfig; final String? currentUid;` plus `this.predictionConfig, this.currentUid,`. The match detail (`tournament_match_detail.dart`) passes them (Task A6). The teaser:
  - reads the tournament's matchWinner question via `TournamentService.watchTournamentQuestions(tournamentId)` (pick the first `QuestionType.matchWinner`); hide if none or `predictionConfig?.open != true`.
  - shows 3 buttons (team1 / Draw / team2); reads the user's current answer via `watchMyMatchAnswers`; on tap (signed in + scheduled) calls `submitAnswer(tid, mid, uid, q.id, 'team1'|'draw'|'team2', now)`; once answered shows an "Enter prediction room →" button that pushes `PredictionRoomPage`.
  - signed-out → "Sign in to predict" routing to `LoginPage`.
  - `MatchFactsTab` needs the `tournamentId` — confirm it's already available (the page passes match/team data; add `final String tournamentId;` to the constructor if missing, defaulting safely, and pass it from A6).
  Build this as a private `_WhoWillWinTeaser` widget inside match_facts_tab.dart (or a new `lib/tournament_tabs/who_will_win_teaser.dart` — implementer's choice; keep match_facts_tab readable). Reuse green `0xFF0A7D2C` for the selected option.

- [ ] **Step 2: Run** `flutter test` (existing match-facts/widget tests must still pass — new constructor args are optional) + `flutter analyze lib/tournament_tabs/match_facts_tab.dart`.

- [ ] **Step 3: Commit**
```bash
git add lib/tournament_tabs/match_facts_tab.dart   # + who_will_win_teaser.dart if created
git commit -m "feat: 'Who will win?' teaser atop match Facts -> enter prediction room"
```

---

### Task A6: Wire teaser inputs through match detail (fan) [Stage A]

**Files:** Modify `lib/tournament_match_detail.dart`.

- [ ] **Step 1:** The match detail builds `MatchFactsTab(...)`. Load the tournament's `PredictionConfig` (reuse `TournamentService.getPredictionConfig(widget.tournamentId)` from Phase 1) in this page's state (a `Future`/`FutureBuilder` or in initState into a field), and pass to `MatchFactsTab`: `tournamentId: widget.tournamentId, predictionConfig: _predictionConfig, currentUid: FirebaseAuth.instance.currentUser?.uid`. Confirm `widget.tournamentId` exists on this page (Phase-1 cohesion passed it); if not, thread it from the caller. Import `firebase_auth` (already used app-wide) + the prediction_config model.

- [ ] **Step 2: Run** `flutter analyze lib/tournament_match_detail.dart` + full `flutter test`.

- [ ] **Step 3: Commit**
```bash
git add lib/tournament_match_detail.dart
git commit -m "feat: pass prediction config + uid into match Facts for the teaser"
```

---

### Task A7: Generalize the scoring function (functions) [Stage A]

**Files:** Modify `functions/src/lib/predict.ts`; Modify `functions/src/index.ts`; Test `functions/test/predict.test.ts`.

- [ ] **Step 1: Failing tests** — extend `functions/test/predict.test.ts` with a `questionPoints` + generalized `computeLeaderboard` suite:
```typescript
import { questionPoints, computeLeaderboardV2 } from '../src/lib/predict';

describe('questionPoints', () => {
  const winner = { id: 'w', type: 'matchWinner', points: 1, line: null };
  test('winner correct/wrong', () => {
    expect(questionPoints(winner, 'team1', 2, 1, null).points).toBe(1);
    expect(questionPoints(winner, 'draw', 2, 1, null).points).toBe(0);
  });
  test('correctScore exact', () => {
    const r = questionPoints({ id: 's', type: 'correctScore', points: 3, line: null }, '2-1', 2, 1, null);
    expect(r.points).toBe(3); expect(r.isExactScore).toBe(true);
  });
  test('totalGoals on-the-line is under', () => {
    const q = { id: 't', type: 'totalGoals', points: 2, line: 3 };
    expect(questionPoints(q, 'under', 2, 1, null).points).toBe(2);
    expect(questionPoints(q, 'over', 2, 1, null).points).toBe(0);
  });
  test('custom needs result', () => {
    const q = { id: 'c', type: 'custom', points: 2, line: null };
    expect(questionPoints(q, 'o1', 0, 0, 'o1').points).toBe(2);
    expect(questionPoints(q, 'o1', 0, 0, null).points).toBe(0);
  });
});

describe('computeLeaderboardV2', () => {
  test('sums per-question points across questions + matches, drops zero, honors lock', () => {
    const finals = [{ id: 'm1', team1Score: 2, team2Score: 1, startedAtMs: 1000 }];
    const questionsByMatch = { m1: [
      { id: 'w', type: 'matchWinner', points: 1, line: null },
      { id: 's', type: 'correctScore', points: 3, line: null },
    ]};
    const answers = { m1: {
      u1: { w: { value: 'team1', updatedAt: 900 }, s: { value: '2-1', updatedAt: 900 } },
      u2: { w: { value: 'team1', updatedAt: 900 }, s: { value: '0-0', updatedAt: 900 } },
      u3: { w: { value: 'team1', updatedAt: 1500 } }, // late -> ignored
    }};
    const results = {}; // no custom
    const lb = computeLeaderboardV2(finals, questionsByMatch, answers, results);
    expect(lb['u1']).toEqual({ points: 4, exact: 1 });
    expect(lb['u2']).toEqual({ points: 1, exact: 0 });
    expect(lb['u3']).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run — FAIL.** `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test`

- [ ] **Step 3: Add to `functions/src/lib/predict.ts`:**
```typescript
export interface PredQuestion {
  id: string;
  type: 'matchWinner' | 'correctScore' | 'totalGoals' | 'custom';
  points: number;
  line: number | null;
}
export interface QAnswer { value: string; updatedAt: number }
export interface QScore { correct: boolean; points: number; isExactScore: boolean }

export function questionPoints(
  q: PredQuestion, answer: string, a1: number, a2: number, customResult: string | null,
): QScore {
  let correct = false, exact = false;
  switch (q.type) {
    case 'matchWinner': {
      const res = a1 > a2 ? 'team1' : a1 < a2 ? 'team2' : 'draw';
      correct = answer === res; break;
    }
    case 'correctScore':
      correct = answer === `${a1}-${a2}`; exact = correct; break;
    case 'totalGoals': {
      const line = q.line ?? 2.5;
      correct = answer === ((a1 + a2) > line ? 'over' : 'under'); break;
    }
    case 'custom':
      correct = customResult != null && answer === customResult; break;
  }
  return { correct, points: correct ? q.points : 0, isExactScore: exact };
}

export function computeLeaderboardV2(
  finals: FinalMatch[],
  questionsByMatch: Record<string, PredQuestion[]>,
  answersByMatch: Record<string, Record<string, Record<string, QAnswer>>>,
  resultsByMatch: Record<string, Record<string, string>>,
): Record<string, { points: number; exact: number }> {
  const out: Record<string, { points: number; exact: number }> = {};
  for (const m of finals) {
    const qs = questionsByMatch[m.id] ?? [];
    const users = answersByMatch[m.id] ?? {};
    const results = resultsByMatch[m.id] ?? {};
    for (const [uid, byQ] of Object.entries(users)) {
      for (const q of qs) {
        const ans = byQ[q.id];
        if (!ans || !(ans.updatedAt < m.startedAtMs)) continue;
        const r = questionPoints(q, ans.value, m.team1Score, m.team2Score, results[q.id] ?? null);
        if (r.points === 0 && !r.correct) continue;
        const cur = out[uid] ?? { points: 0, exact: 0 };
        cur.points += r.points;
        if (r.isExactScore) cur.exact += 1;
        out[uid] = cur;
      }
    }
  }
  for (const uid of Object.keys(out)) if (out[uid].points === 0) delete out[uid];
  return out;
}
```
(`FinalMatch` already exists from Phase 1.)

- [ ] **Step 4: Rewrite `recomputeLeaderboard` in `functions/src/index.ts`** to use V2: read `Tournaments/{tid}/PredictionQuestions` (tournament-wide) and each final match's `Matches/{mid}/PredictionQuestions` (merge), `Matches/{mid}/PredictionResults`, and the per-question answers under `Predictions/{mid}/{uid}/{qid}` (shape `{Answer, UpdatedAt}`). Map raw nodes to `PredQuestion`/`QAnswer` (Pascal keys: `Type/Points/Line`, `Answer/UpdatedAt`), build the three maps, call `computeLeaderboardV2`, then write `Leaderboard/{uid} = {Name, Points, Exact}` (reuse `readUserName`). Keep the `Open===false` clear-and-return. Add two new triggers so resolution/edits recompute:
```typescript
export const onPredictResult = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/PredictionResults/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);
export const onPredictQuestion = onValueWritten(
  '/Tournaments/{tid}/PredictionQuestions/{qid}',
  async (event) => { await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string); },
);
```

- [ ] **Step 5: Run** `npm test` (PASS) + `npm run build` (clean). Do NOT deploy yet.

- [ ] **Step 6: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/src/lib/predict.ts functions/src/index.ts functions/test/predict.test.ts
git commit -m "feat(functions): generalized question scoring + V2 leaderboard + resolution triggers"
```

---

### Task A8: Manager — seed defaults + tournament default-questions editor [Stage A]

**Files (Manager):** Modify `lib/services/firebase/tournament_service.dart` (seed on create + question CRUD); Modify `lib/core/constants/firebase_paths.dart`; Create `lib/ui/tournaments/manage_prediction_questions_page.dart`; Modify `lib/ui/tournaments/tournament_dashboard_page.dart` (entry tile); Modify `lib/models/prediction_config.dart` or a new `lib/models/prediction_question.dart`; Test `test/prediction_question_mgr_test.dart`.

- [ ] **Step 1: Failing test** for a Manager `PredictionQuestion` model round-trip (mirror the fan model) `test/prediction_question_mgr_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/prediction_question.dart';

void main() {
  test('round-trips a totalGoals question', () {
    final q = PredictionQuestion(id: 'q1', text: 'Total goals',
        type: 'totalGoals', points: 2, order: 2, options: const {}, line: 2.5);
    final map = q.toFirebaseMap();
    expect(map['Type'], 'totalGoals');
    expect(map['Line'], 2.5);
    final back = PredictionQuestion.fromFirebase('q1', map);
    expect(back.points, 2); expect(back.line, 2.5);
  });
  test('custom round-trips options', () {
    final q = PredictionQuestion(id: 'q2', text: 'First?', type: 'custom',
        points: 2, order: 3, options: const {'o1': 'Eagles', 'o2': 'Lions'}, line: null);
    final back = PredictionQuestion.fromFirebase('q2', q.toFirebaseMap());
    expect(back.options, {'o1': 'Eagles', 'o2': 'Lions'});
  });
}
```

- [ ] **Step 2: Run — FAIL.** `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test test/prediction_question_mgr_test.dart`

- [ ] **Step 3: Create `lib/models/prediction_question.dart`** (Manager; type is a plain String here, options a `Map<String,String>` id→label):
```dart
class PredictionQuestion {
  final String id;
  final String text;
  final String type; // matchWinner | correctScore | totalGoals | custom
  final int points;
  final int order;
  final Map<String, String> options; // custom: id -> label
  final double? line; // totalGoals

  const PredictionQuestion({
    required this.id, required this.text, required this.type,
    required this.points, required this.order, required this.options, this.line,
  });

  factory PredictionQuestion.fromFirebase(String id, dynamic raw) {
    final m = (raw is Map) ? raw : const {};
    final opts = <String, String>{};
    final o = m['Options'] ?? m['options'];
    if (o is Map) {
      o.forEach((k, v) => opts[k.toString()] =
          (v is Map ? (v['Label'] ?? v['label'] ?? k).toString() : v.toString()));
    }
    final line = m['Line'] ?? m['line'];
    return PredictionQuestion(
      id: id,
      text: (m['Text'] ?? m['text'] ?? '').toString(),
      type: (m['Type'] ?? m['type'] ?? 'custom').toString(),
      points: int.tryParse('${m['Points'] ?? m['points'] ?? 0}') ?? 0,
      order: int.tryParse('${m['Order'] ?? m['order'] ?? 0}') ?? 0,
      options: opts,
      line: line == null ? null : double.tryParse(line.toString()),
    );
  }

  Map<String, dynamic> toFirebaseMap() => {
        'Text': text, 'Type': type, 'Points': points, 'Order': order,
        if (line != null) 'Line': line,
        if (options.isNotEmpty)
          'Options': {for (final e in options.entries) e.key: {'Label': e.value}},
      };
}
```

- [ ] **Step 4: Seed defaults on create.** In Manager `tournament_service.dart` `createTournament`, after the PredictionConfig block, add two seeded questions:
```dart
      final seedQs = <String, Map<String, dynamic>>{
        'q_winner': {'Text': 'Who will win?', 'Type': 'matchWinner', 'Points': 1, 'Order': 0},
        'q_score': {'Text': 'Correct score', 'Type': 'correctScore', 'Points': 3, 'Order': 1},
      };
      seedQs.forEach((qid, q) {
        q.forEach((k, v) {
          updates['${FirebasePaths.tournament(tournament.id)}/PredictionQuestions/$qid/$k'] = v;
        });
      });
```
Add path helpers in `firebase_paths.dart`:
```dart
  static String tournamentPredictionQuestions(String tid) =>
      '$tournaments/$tid/PredictionQuestions';
  static String tournamentPredictionQuestion(String tid, String qid) =>
      '$tournaments/$tid/PredictionQuestions/$qid';
```

- [ ] **Step 5: Add service CRUD** to Manager `tournament_service.dart`:
```dart
  Future<List<PredictionQuestion>> getTournamentQuestions(String tid) async {
    final snap = await _db.ref(FirebasePaths.tournamentPredictionQuestions(tid)).get();
    final out = <PredictionQuestion>[];
    final v = snap.value;
    if (v is Map) v.forEach((k, q) => out.add(PredictionQuestion.fromFirebase(k.toString(), q)));
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }

  Future<void> saveTournamentQuestion(String tid, PredictionQuestion q) {
    return _db.ref(FirebasePaths.tournamentPredictionQuestion(tid, q.id)).set(q.toFirebaseMap());
  }

  Future<void> deleteTournamentQuestion(String tid, String qid) {
    return _db.ref(FirebasePaths.tournamentPredictionQuestion(tid, qid)).remove();
  }
```
Match the real DB accessor name used in this service (e.g. `_db`/`FirebaseDatabase.instance`/`ref()`) — read the file and mirror it. Generate new ids with the existing id pattern used elsewhere (e.g. `ref(...).push().key`).

- [ ] **Step 6: Build the editor page** `lib/ui/tournaments/manage_prediction_questions_page.dart`: a `ConsumerStatefulWidget` (Riverpod, like other Manager pages) listing the tournament's questions (sorted by order) with add/edit/delete. An add/edit dialog: Type dropdown (Who-will-win / Correct-score / Total-goals / Custom), Points field, Line field (shown for Total-goals), and for Custom a Text field + 2–4 option text fields. Save via `saveTournamentQuestion`; delete via `deleteTournamentQuestion`. Mirror the structure of `manage_venues_page.dart` (built in the Venues feature) for list/add/edit/delete + dialog conventions.

- [ ] **Step 7: Dashboard entry.** In `tournament_dashboard_page.dart`, add a tile/button "Prediction questions" that routes to the new page (mirror how the Manage Venues tile/route was added). Pass the tournamentId.

- [ ] **Step 8: Verify** `flutter test` (incl. the new model test) + `flutter analyze lib/` (no new errors) on the Manager app.

- [ ] **Step 9: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/models/prediction_question.dart lib/core/constants/firebase_paths.dart lib/services/firebase/tournament_service.dart lib/ui/tournaments/manage_prediction_questions_page.dart lib/ui/tournaments/tournament_dashboard_page.dart test/prediction_question_mgr_test.dart
git commit -m "feat: seed default questions + tournament prediction-questions editor"
```

---

# STAGE B — Custom questions: per-match editor + resolution + custom scoring

(The room already renders custom questions and the function already scores them given a result. Stage B adds the Manager authoring of per-match custom questions and the post-game resolution UI.)

### Task B1: Manager per-match questions + resolution [Stage B]

**Files (Manager):** Modify `lib/core/constants/firebase_paths.dart`; Modify `lib/services/firebase/tournament_service.dart`; Create `lib/ui/tournaments/match_prediction_questions_page.dart`; add an entry point from the match editor/bracket; Test extend `test/prediction_question_mgr_test.dart`.

- [ ] **Step 1:** Add path helpers:
```dart
  static String matchPredictionQuestions(String tid, String mid) =>
      '$tournaments/$tid/Matches/$mid/PredictionQuestions';
  static String matchPredictionQuestion(String tid, String mid, String qid) =>
      '$tournaments/$tid/Matches/$mid/PredictionQuestions/$qid';
  static String matchPredictionResult(String tid, String mid, String qid) =>
      '$tournaments/$tid/Matches/$mid/PredictionResults/$qid';
```
- [ ] **Step 2:** Service methods (mirror Task A8 step 5 but per-match) + `setQuestionResult`:
```dart
  Future<List<PredictionQuestion>> getMatchQuestions(String tid, String mid) async {
    final snap = await _db.ref(FirebasePaths.matchPredictionQuestions(tid, mid)).get();
    final out = <PredictionQuestion>[];
    final v = snap.value;
    if (v is Map) v.forEach((k, q) => out.add(PredictionQuestion.fromFirebase(k.toString(), q)));
    out.sort((a, b) => a.order.compareTo(b.order));
    return out;
  }
  Future<void> saveMatchQuestion(String tid, String mid, PredictionQuestion q) =>
      _db.ref(FirebasePaths.matchPredictionQuestion(tid, mid, q.id)).set(q.toFirebaseMap());
  Future<void> deleteMatchQuestion(String tid, String mid, String qid) =>
      _db.ref(FirebasePaths.matchPredictionQuestion(tid, mid, qid)).remove();
  Future<void> setQuestionResult(String tid, String mid, String qid, String optionId) =>
      _db.ref(FirebasePaths.matchPredictionResult(tid, mid, qid)).set(optionId);
```
- [ ] **Step 3:** Page `match_prediction_questions_page.dart`: two sections — (1) **Add per-match questions** (same editor as A8, scoped to the match), and (2) **Resolve**: list every custom question for the match (tournament-wide customs + per-match customs), each with its options as choices; tapping an option calls `setQuestionResult`. Auto questions display "resolves automatically." Reuse the A8 editor widgets. Add an entry point: a "Prediction questions" action on the match in the Manager bracket/match editor (mirror existing per-match actions).
- [ ] **Step 4:** Extend the Manager model test with a per-match round-trip if useful; `flutter test` + `flutter analyze lib/`.
- [ ] **Step 5: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/core/constants/firebase_paths.dart lib/services/firebase/tournament_service.dart lib/ui/tournaments/match_prediction_questions_page.dart <match-editor-file> test/prediction_question_mgr_test.dart
git commit -m "feat: per-match custom prediction questions + post-game resolution"
```

---

### Task B2: Verification, build/install both apps, deploy, surface (SURFACE TO OWNER) [Stage B]

- [ ] **Step 1:** Fan `flutter test` + `flutter analyze lib/`; functions `npm test` + `npm run build`; Manager `flutter test` + `flutter analyze lib/`. All green / no new errors.
- [ ] **Step 2:** Final whole-feature review across both branches' Phase-2 diffs (parity of Dart/TS `questionPoints`; data-key agreement Answer/UpdatedAt/Type/Points/Line/Options/PredictionResults; lock fairness; idempotent V2 recompute; teaser writes the matchWinner answer; hub pushes the room; signed-out safety).
- [ ] **Step 3:** Build + install both release APKs on both devices (`GN434J02403404RL`, `emulator-5554`).
- [ ] **Step 4:** Deploy ONLY the prediction functions (after owner OK):
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
cd functions && npm run build && cd ..
npx firebase-tools deploy --only "functions:onPredictMatchStatus,functions:onPredictTeam1Score,functions:onPredictTeam2Score,functions:onPredictResult,functions:onPredictQuestion"
npx firebase-tools functions:list   # confirm Watcher + all onPredict* healthy
```
- [ ] **Step 5: STOP and surface** the on-device test recipe: author a Total-goals default + a custom question (Manager) → predict from the match teaser and the room (fan) → finalize the match → resolve the custom question (Manager) → leaderboard reflects all the points.

---

## Self-review notes
- **Spec coverage:** question model + 3 auto types (A1) · per-question answers + service (A2) · room (A3) · hub index (A4) · teaser (A5/A6) · auto scoring + V2 leaderboard + triggers (A7) · seed + tournament editor (A8) · per-match custom + resolution (B1) · verify/deploy/surface (B2). All §spec sections mapped.
- **Parity:** Dart `questionPoints` (A1) and TS `questionPoints` (A7) implement the identical rule (winner sign, `T1-T2` exact, over/under with on-the-line=under, custom==result) with mirrored tests.
- **Keys:** `{Text,Type,Points,Order,Line,Options{id:{Label}}}` for questions; `{Answer,UpdatedAt}` for answers; `PredictionResults/{qid}=optionId`; `Leaderboard/{uid}={Name,Points,Exact}` — consistent fan ↔ functions ↔ Manager.
- **Back-compat:** Phase-1 flat `Predictions/{mid}/{uid}={Team1,Team2,UpdatedAt}` is superseded by per-question; no live data (test note in spec). The V2 function no longer reads the flat shape.
