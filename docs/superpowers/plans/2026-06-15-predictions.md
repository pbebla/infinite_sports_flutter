# Predictions (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Signed-in fans predict a tournament match's exact score before kickoff (winner is derived); +1 for the right result, +3 for the exact score; a per-tournament leaderboard ranks everyone, auto-scored by a Cloud Function.

**Architecture:** Fan app writes a per-user prediction per match (`Tournaments/{tid}/Predictions/{matchId}/{uid}`). A Cloud Function recomputes the whole tournament leaderboard (`Tournaments/{tid}/Leaderboard/{uid}`) whenever a match finalizes or a final score is corrected. The fan reads only the small leaderboard node, never other users' raw picks. A pure scoring rule is implemented identically in Dart (fan, for "you scored X") and TypeScript (function, for the leaderboard). Manager gets one on/off toggle.

**Tech Stack:** Flutter/Dart (fan + Manager), Firebase RTDB, firebase-functions v2 (TypeScript, vitest).

**Spec:** `docs/superpowers/specs/2026-06-15-predictions-design.md`.

---

## Ground rules (apply to every task)
- **Fan app:** `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`, branch **`zaya/predictions`** (already created, off `zaya/live-scores`). Verify with `git -C "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" branch --show-current` before committing.
- **Manager app:** `C:\Users\zayaa\StudioProjects\InfiniteSportsManagerFlutter`. Task 9 creates branch **`zaya-predictions`** off `zaya-live-scores`. Use ABSOLUTE paths for Manager: `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"`.
- **Commits LOCAL only.** Never push. Stage EXACT paths only — never `git add -A` / `git add .`.
- **Fan repo hygiene:** never stage `PROJECT_REFERENCE.md` or `SoccerStats.png`. If `git status` shows `pubspec.lock` modified, run `git restore pubspec.lock` before committing.
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Scoring defaults: **MatchWinner = 1, ExactScoreBonus = 3** (read from `PredictionConfig.Scoring`; fall back to these if missing).

## The scoring rule (single source of truth — Tasks 1 and 7 must agree)
Given predicted `(p1, p2)` and actual final `(a1, a2)`, scoring `mw` (MatchWinner) and `eb` (ExactScoreBonus):
- `resultCorrect = sign(p1 - p2) == sign(a1 - a2)` (both home-win / both away-win / both draw)
- `exactCorrect = (p1 == a1) && (p2 == a2)`
- `points = (resultCorrect ? mw : 0) + (exactCorrect ? eb : 0)` (exact implies result → max `mw+eb`)

## File map
**Fan (new):** `lib/misc/prediction_scoring.dart`, `lib/model/prediction.dart`, `lib/model/prediction_config.dart`, `lib/model/leaderboard_entry.dart`, `lib/tournament_tabs/predict_card.dart`, `lib/tournament_tabs/predict_tab.dart`. **Fan (modify):** `lib/misc/tournament_service.dart`, `lib/tournamentdetail.dart`, `lib/tournament_tabs/fixtures_tab.dart`. **Fan tests:** `test/prediction_scoring_test.dart`, `test/prediction_models_test.dart`, `test/predict_widgets_test.dart`.
**Functions (new):** `functions/src/lib/predict.ts`, `functions/test/predict.test.ts`. **Functions (modify):** `functions/src/index.ts`.
**Manager (new branch):** modify `lib/core/constants/firebase_paths.dart`, `lib/models/tournament.dart`, `lib/services/firebase/tournament_service.dart`, `lib/ui/tournaments/tournament_dashboard_page.dart`. **Manager test:** `test/tournament_predictions_open_test.dart`.

---

### Task 1 (Fan): Pure scoring helper

**Files:** Create `lib/misc/prediction_scoring.dart`; Test `test/prediction_scoring_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/prediction_scoring_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';

void main() {
  PredictionResult score(int p1, int p2, int a1, int a2) => predictionPoints(
        predTeam1: p1, predTeam2: p2, actualTeam1: a1, actualTeam2: a2,
        matchWinnerPoints: 1, exactScorePoints: 3,
      );

  test('exact score: result + exact bonus', () {
    final r = score(2, 1, 2, 1);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, true);
    expect(r.points, 4);
  });
  test('right winner, wrong score: result only', () {
    final r = score(2, 1, 3, 0);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, false);
    expect(r.points, 1);
  });
  test('wrong winner: zero', () {
    final r = score(2, 1, 0, 1);
    expect(r.resultCorrect, false);
    expect(r.exactCorrect, false);
    expect(r.points, 0);
  });
  test('correct draw, wrong score: result only', () {
    final r = score(1, 1, 2, 2);
    expect(r.resultCorrect, true);
    expect(r.exactCorrect, false);
    expect(r.points, 1);
  });
  test('exact draw: result + exact', () {
    final r = score(0, 0, 0, 0);
    expect(r.points, 4);
  });
  test('predicted draw, actual not draw: zero', () {
    expect(score(1, 1, 2, 1).points, 0);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test test/prediction_scoring_test.dart` → fails to compile (no `prediction_scoring.dart`).

- [ ] **Step 3: Implement** — `lib/misc/prediction_scoring.dart`:
```dart
/// Pure scoring rule for a single match prediction.
/// Mirrors functions/src/lib/predict.ts predictionPoints — keep both in sync.
class PredictionResult {
  final bool resultCorrect;
  final bool exactCorrect;
  final int points;
  const PredictionResult({
    required this.resultCorrect,
    required this.exactCorrect,
    required this.points,
  });
}

PredictionResult predictionPoints({
  required int predTeam1,
  required int predTeam2,
  required int actualTeam1,
  required int actualTeam2,
  required int matchWinnerPoints,
  required int exactScorePoints,
}) {
  final resultCorrect =
      (predTeam1 - predTeam2).sign == (actualTeam1 - actualTeam2).sign;
  final exactCorrect = predTeam1 == actualTeam1 && predTeam2 == actualTeam2;
  final points = (resultCorrect ? matchWinnerPoints : 0) +
      (exactCorrect ? exactScorePoints : 0);
  return PredictionResult(
    resultCorrect: resultCorrect,
    exactCorrect: exactCorrect,
    points: points,
  );
}
```

- [ ] **Step 4: Run it, expect PASS** — `flutter test test/prediction_scoring_test.dart`.

- [ ] **Step 5: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add lib/misc/prediction_scoring.dart test/prediction_scoring_test.dart
git commit -m "feat: pure prediction scoring helper (+1 result, +3 exact)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2 (Fan): Models — prediction, config, leaderboard entry

**Files:** Create `lib/model/prediction.dart`, `lib/model/prediction_config.dart`, `lib/model/leaderboard_entry.dart`; Test `test/prediction_models_test.dart`.

- [ ] **Step 1: Write the failing test** — `test/prediction_models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';

void main() {
  test('MatchPrediction round-trips (Pascal keys)', () {
    final p = MatchPrediction.fromFirebase(
        {'Team1': 2, 'Team2': 1, 'UpdatedAt': 1700000000000});
    expect(p!.team1, 2);
    expect(p.team2, 1);
    expect(p.updatedAt, 1700000000000);
    expect(p.toFirebase()['Team1'], 2);
  });

  test('PredictionConfig defaults when fields missing', () {
    final c = PredictionConfig.fromFirebase({});
    expect(c.open, true);
    expect(c.matchWinnerPoints, 1);
    expect(c.exactScorePoints, 3);
  });

  test('PredictionConfig reads Open + Scoring', () {
    final c = PredictionConfig.fromFirebase({
      'Open': false,
      'Scoring': {'MatchWinner': 2, 'ExactScoreBonus': 5},
    });
    expect(c.open, false);
    expect(c.matchWinnerPoints, 2);
    expect(c.exactScorePoints, 5);
  });

  test('LeaderboardEntry parse + sort (points desc, exact desc, name asc)', () {
    final a = LeaderboardEntry.fromFirebase(
        'u1', {'Name': 'Bea', 'Points': 10, 'Exact': 1});
    final b = LeaderboardEntry.fromFirebase(
        'u2', {'Name': 'Ann', 'Points': 10, 'Exact': 1});
    final c = LeaderboardEntry.fromFirebase(
        'u3', {'Name': 'Cy', 'Points': 12, 'Exact': 0});
    final list = [a, b, c]..sort(compareLeaderboard);
    expect(list.map((e) => e.uid).toList(), ['u3', 'u2', 'u1']); // 12 first, then Ann<Bea
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** — `flutter test test/prediction_models_test.dart` → fails to compile.

- [ ] **Step 3: Implement `lib/model/prediction.dart`**:
```dart
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

/// A fan's predicted score for one match.
class MatchPrediction {
  final int team1;
  final int team2;
  final int updatedAt; // ms epoch

  const MatchPrediction({
    required this.team1,
    required this.team2,
    required this.updatedAt,
  });

  static MatchPrediction? fromFirebase(dynamic raw) {
    if (raw is! Map) return null;
    return MatchPrediction(
      team1: parseInt(firstNonNull(raw, ['Team1', 'team1'])),
      team2: parseInt(firstNonNull(raw, ['Team2', 'team2'])),
      updatedAt: parseInt(firstNonNull(raw, ['UpdatedAt', 'updatedAt'])),
    );
  }

  Map<String, dynamic> toFirebase() => {
        'Team1': team1,
        'Team2': team2,
        'UpdatedAt': updatedAt,
      };
}
```
NOTE: confirm `parseInt` and `firstNonNull` exist in `lib/misc/parse_helpers.dart` (they are used by `TournamentMatch.fromFirebase`). If their names differ, use the actual ones.

- [ ] **Step 4: Implement `lib/model/prediction_config.dart`**:
```dart
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

/// Fan-side view of Tournaments/{tid}/PredictionConfig (Phase 1 fields only).
class PredictionConfig {
  final bool open;
  final int matchWinnerPoints;
  final int exactScorePoints;

  const PredictionConfig({
    required this.open,
    required this.matchWinnerPoints,
    required this.exactScorePoints,
  });

  factory PredictionConfig.fromFirebase(dynamic raw) {
    final data = (raw is Map) ? raw : const {};
    final open = firstNonNull(data, ['Open', 'open']);
    final scoring = firstNonNull(data, ['Scoring', 'scoring']);
    int score(String pascal, String camel, int dflt) {
      if (scoring is Map) {
        final v = firstNonNull(scoring, [pascal, camel]);
        if (v != null) return parseInt(v);
      }
      return dflt;
    }
    return PredictionConfig(
      open: open is bool ? open : (open == null ? true : open.toString() == 'true'),
      matchWinnerPoints: score('MatchWinner', 'matchWinner', 1),
      exactScorePoints: score('ExactScoreBonus', 'exactScoreBonus', 3),
    );
  }
}
```

- [ ] **Step 5: Implement `lib/model/leaderboard_entry.dart`**:
```dart
import 'package:infinite_sports_flutter/misc/parse_helpers.dart';

class LeaderboardEntry {
  final String uid;
  final String name;
  final int points;
  final int exact;

  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.points,
    required this.exact,
  });

  factory LeaderboardEntry.fromFirebase(String uid, dynamic raw) {
    final data = (raw is Map) ? raw : const {};
    return LeaderboardEntry(
      uid: uid,
      name: firstNonNull(data, ['Name', 'name'])?.toString() ?? 'Player',
      points: parseInt(firstNonNull(data, ['Points', 'points'])),
      exact: parseInt(firstNonNull(data, ['Exact', 'exact'])),
    );
  }
}

/// Sort: points desc, then exact desc, then name asc (stable, case-insensitive).
int compareLeaderboard(LeaderboardEntry a, LeaderboardEntry b) {
  if (a.points != b.points) return b.points.compareTo(a.points);
  if (a.exact != b.exact) return b.exact.compareTo(a.exact);
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
```

- [ ] **Step 6: Run it, expect PASS** — `flutter test test/prediction_models_test.dart`.

- [ ] **Step 7: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add lib/model/prediction.dart lib/model/prediction_config.dart lib/model/leaderboard_entry.dart test/prediction_models_test.dart
git commit -m "feat: prediction, config, and leaderboard-entry models + sort

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3 (Fan): Service methods (config / submit / my predictions / leaderboard)

**Files:** Modify `lib/misc/tournament_service.dart`.

Read the existing `TournamentService` static stream methods (`watchMatches`, `watchMatch`, `getMatches`) and mirror them exactly. Add these methods inside the class.

- [ ] **Step 1: Add imports** (top of `lib/misc/tournament_service.dart`, if not present):
```dart
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/leaderboard_entry.dart';
```

- [ ] **Step 2: Add the methods** (mirror the existing `watch*`/`get*` idioms — `FirebaseDatabase.instance.ref('/Tournaments/...')`, `.onValue.map(...)`, `.get()`):
```dart
  /// Reads PredictionConfig once (defaults applied when absent).
  static Future<PredictionConfig> getPredictionConfig(String tournamentId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref('/Tournaments/$tournamentId/PredictionConfig')
          .get();
      return PredictionConfig.fromFirebase(snap.value);
    } catch (_) {
      return PredictionConfig.fromFirebase(const {});
    }
  }

  static Stream<PredictionConfig> watchPredictionConfig(String tournamentId) {
    return FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/PredictionConfig')
        .onValue
        .map((e) => PredictionConfig.fromFirebase(e.snapshot.value));
  }

  /// Writes the signed-in user's prediction for one match.
  static Future<void> submitPrediction(
    String tournamentId,
    String matchId,
    String uid,
    int team1,
    int team2,
    int nowMs,
  ) async {
    final pred = MatchPrediction(team1: team1, team2: team2, updatedAt: nowMs);
    await FirebaseDatabase.instance
        .ref('/Tournaments/$tournamentId/Predictions/$matchId/$uid')
        .set(pred.toFirebase());
  }

  /// Streams the signed-in user's predictions across the tournament, keyed by matchId.
  static Stream<Map<String, MatchPrediction>> watchMyPredictions(
      String tournamentId, String uid) {
    final ref =
        FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Predictions');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      final out = <String, MatchPrediction>{};
      if (value is Map) {
        value.forEach((matchId, byUser) {
          if (byUser is Map && byUser[uid] is Map) {
            final p = MatchPrediction.fromFirebase(byUser[uid]);
            if (p != null) out[matchId.toString()] = p;
          }
        });
      }
      return out;
    });
  }

  /// Streams the tournament leaderboard, already sorted.
  static Stream<List<LeaderboardEntry>> watchLeaderboard(String tournamentId) {
    final ref =
        FirebaseDatabase.instance.ref('/Tournaments/$tournamentId/Leaderboard');
    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      final out = <LeaderboardEntry>[];
      if (value is Map) {
        value.forEach((uid, v) {
          out.add(LeaderboardEntry.fromFirebase(uid.toString(), v));
        });
      }
      out.sort(compareLeaderboard);
      return out;
    });
  }
```
NOTE: pass `nowMs` into `submitPrediction` (the caller supplies `DateTime.now().millisecondsSinceEpoch`) so the method stays pure-ish and testable; do not call `DateTime.now()` inside the service.

- [ ] **Step 3: Verify it compiles** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/misc/tournament_service.dart` → no new errors.

- [ ] **Step 4: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add lib/misc/tournament_service.dart
git commit -m "feat: prediction service methods (config, submit, my picks, leaderboard)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4 (Fan): Predict card widget

**Files:** Create `lib/tournament_tabs/predict_card.dart`; Test `test/predict_widgets_test.dart` (created here, extended in Task 5).

A `StatefulWidget` showing one match: two team columns with +/− score steppers, a derived-winner line, a points breakdown, and a Lock/Update button. Locked (read-only) when the match is not scheduled; shows earned points when final; shows a sign-in CTA when signed out.

- [ ] **Step 1: Implement `lib/tournament_tabs/predict_card.dart`**:
```dart
import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/prediction_scoring.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/model/match_status.dart';
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
    // Adopt an incoming saved prediction only if the user hasn't been editing.
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
```
NOTE: confirm `TeamLogo` constructor (`url`, `size`) by reading `lib/widgets/team_logo.dart` (used by `fixtures_tab.dart`); match its real parameter names. `infiniteSportsPrimaryColor` is available from `utility.dart` if you want brand accents.

- [ ] **Step 2: Write a widget test** — `test/predict_widgets_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_sports_flutter/model/prediction.dart';
import 'package:infinite_sports_flutter/model/prediction_config.dart';
import 'package:infinite_sports_flutter/model/tournamentmatch.dart';
import 'package:infinite_sports_flutter/tournament_tabs/predict_card.dart';

TournamentMatch _m({required int status, int s1 = 0, int s2 = 0}) =>
    TournamentMatch(
      id: 'm1', stage: 'Group Stage', label: 'Group A', date: '08272026',
      time: '6:00 PM', team1Id: 'A', team2Id: 'B',
      team1Score: s1, team2Score: s2, status: status, bracketPosition: 0,
    );

const _cfg = PredictionConfig(open: true, matchWinnerPoints: 1, exactScorePoints: 3);

void main() {
  testWidgets('signed-out shows sign-in CTA', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 0), team1: null, team2: null, config: _cfg,
          myPrediction: null, isSignedIn: false,
          onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.text('Sign in to predict'), findsOneWidget);
  });

  testWidgets('scheduled + signed-in shows Lock prediction', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 0), team1: null, team2: null, config: _cfg,
          myPrediction: null, isSignedIn: true,
          onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.text('Lock prediction'), findsOneWidget);
  });

  testWidgets('finished shows earned points for an exact pick', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictCard(
          match: _m(status: 2, s1: 2, s2: 1), team1: null, team2: null,
          config: _cfg,
          myPrediction: const MatchPrediction(team1: 2, team2: 1, updatedAt: 1),
          isSignedIn: true, onSubmit: (_, __) {}, onSignIn: () {},
        ),
      ),
    ));
    expect(find.textContaining('Exact! +4'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests, expect PASS** — `flutter test test/predict_widgets_test.dart`. (If `TeamLogo` tries to load a network image and throws in tests, confirm it tolerates a null/!mounted url — it already renders in other widget tests via FixturesTab indirectly; if needed, pass `team1: null` so no logo URL is fetched, as the tests above do.)

- [ ] **Step 4: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add lib/tournament_tabs/predict_card.dart test/predict_widgets_test.dart
git commit -m "feat: predict card (score steppers, derived winner, points, lock/result states)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5 (Fan): Predict tab (Matches ⇄ Leaderboard + points pill)

**Files:** Create `lib/tournament_tabs/predict_tab.dart`; extend `test/predict_widgets_test.dart`.

- [ ] **Step 1: Implement `lib/tournament_tabs/predict_tab.dart`**:
```dart
import 'dart:collection';
import 'package:firebase_auth/firebase_auth.dart';
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

  const PredictTab({
    super.key,
    required this.matches,
    required this.teams,
    required this.tournamentId,
    required this.config,
  });

  @override
  State<PredictTab> createState() => _PredictTabState();
}

class _PredictTabState extends State<PredictTab> {
  bool _showLeaderboard = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
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
    if (!_signedIn) return const SizedBox.shrink();
    return StreamBuilder<List<LeaderboardEntry>>(
      stream: TournamentService.watchLeaderboard(widget.tournamentId),
      builder: (context, snap) {
        final me = (snap.data ?? const [])
            .where((e) => e.uid == _uid)
            .fold<int?>(null, (_, e) => e.points);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: infiniteSportsPrimaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${me ?? '—'} pts',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: infiniteSportsPrimaryColor)),
        );
      },
    );
  }

  Widget _matchesView() {
    if (!_signedIn) {
      // Still allow viewing/predicting per-card; cards show their own CTA.
    }
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
        .then((_) => setState(() {}));
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
```
NOTE: this references `formatDayHeading(date)` — a helper that turns `MMDDYYYY` into "Friday, August 27". `FixturesTab._formatDate` does exactly this via `parseDatabaseDate` + `DateFormat('EEEE, MMMM d')`. To DRY it, in this task add a top-level `String formatDayHeading(String mmddyyyy)` to `lib/misc/utility.dart` (next to `parseDatabaseDate`) and have `FixturesTab._formatDate` call it. If you prefer not to touch FixturesTab, inline the same two lines here using `parseDatabaseDate` + `DateFormat`. Confirm `parseDatabaseDate` exists in utility.dart (it's used by FixturesTab and TournamentDayView).

- [ ] **Step 2: Add a leaderboard widget test** to `test/predict_widgets_test.dart`:
```dart
// add inside main():
  testWidgets('PredictTab empty leaderboard shows prompt', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PredictTab(
          matches: const [], teams: const {}, tournamentId: 't1',
          config: _cfg,
        ),
      ),
    ));
    // Default view = Matches; with no matches it prompts.
    expect(find.text('No matches to predict yet'), findsOneWidget);
  });
```
Add the import `import 'package:infinite_sports_flutter/tournament_tabs/predict_tab.dart';` at the top.

- [ ] **Step 3: Run tests, expect PASS** — `flutter test test/predict_widgets_test.dart`. (The StreamBuilder for leaderboard/predictions will emit nothing in the test harness without Firebase; the Matches empty-state path renders synchronously, so the test above is safe. Do NOT assert leaderboard rows in a unit test — that needs Firebase.)

- [ ] **Step 4: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add lib/tournament_tabs/predict_tab.dart lib/misc/utility.dart lib/tournament_tabs/fixtures_tab.dart test/predict_widgets_test.dart
git commit -m "feat: Predict tab (Matches/Leaderboard toggle, points pill, day-grouped cards)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
(Only stage `fixtures_tab.dart`/`utility.dart` if you touched them for `formatDayHeading`.)

---

### Task 6 (Fan): Wire Predict tab into tournament detail + Fixtures banner

**Files:** Modify `lib/tournamentdetail.dart`, `lib/tournament_tabs/fixtures_tab.dart`.

- [ ] **Step 1: Make the tab list dynamic in `tournamentdetail.dart`.** Replace the `static const List<Tab> _tabs` + initState controller creation with a config-driven setup. Change the state so the `TabController` is created AFTER load (guarding `build()` on `_tabController != null`):
```dart
  // state fields
  PredictionConfig? _predictionConfig;
  List<Tab> _tabs = const [];
  TabController? _tabController;
  int _predictIndex = -1;

  static const List<Tab> _baseTabs = [
    Tab(text: 'Fixtures'),
    Tab(text: 'Table'),
    Tab(text: 'Knockout'),
    Tab(text: 'Player Stats'),
    Tab(text: 'Teams'),
  ];

  @override
  void initState() {
    super.initState();
    _loadData(); // do NOT create the controller here anymore
  }
```
In `_loadData()`, add `TournamentService.getPredictionConfig(widget.tournamentId)` to the parallel loads, then build tabs + controller inside `setState`:
```dart
    final config = await TournamentService.getPredictionConfig(widget.tournamentId);
    final tabs = <Tab>[..._baseTabs];
    if (config.open) tabs.add(const Tab(text: 'Predict'));
    setState(() {
      _tournament = tournament;
      _teams = teams;
      _matches = matches;
      _rosters = rosters;
      _predictionConfig = config;
      _tabs = tabs;
      _predictIndex = config.open ? tabs.length - 1 : -1;
      _tabController = TabController(length: tabs.length, vsync: this);
      _isLoading = false;
      _loadError = null;
    });
```
Update `build()` so the loading branch also triggers when `_tabController == null` (`if (_isLoading || _tabController == null) return <spinner>;`), and pass `controller: _tabController!` and `tabs: _tabs` to the `TabBar`. Update `dispose()` to `_tabController?.dispose();`.

- [ ] **Step 2: Add the Predict tab view.** In the `TabBarView.children` list, after the existing 5, add (guarded so it's only present when the tab exists):
```dart
              if (_predictionConfig?.open ?? false)
                PredictTab(
                  matches: _matches,
                  teams: _teams,
                  tournamentId: widget.tournamentId,
                  config: _predictionConfig!,
                ),
```
Add imports: `import 'package:infinite_sports_flutter/model/prediction_config.dart';` and `import 'package:infinite_sports_flutter/tournament_tabs/predict_tab.dart';`. The `children` count must equal `_tabs.length` — since both the `Tab` and this child are added under the same `config.open` condition, they stay in sync.

- [ ] **Step 3: Pass a banner callback to FixturesTab.** Where `FixturesTab(...)` is constructed in the `TabBarView`, add:
```dart
                FixturesTab(
                  matches: _matches,
                  teams: _teams,
                  rosters: _rosters,
                  tournamentId: widget.tournamentId,
                  sport: _tournament?.sport ?? 'Soccer',
                  predictionsOpen: _predictionConfig?.open ?? false,
                  onOpenPredict: (_predictIndex >= 0)
                      ? () => _tabController?.animateTo(_predictIndex)
                      : null,
                ),
```

- [ ] **Step 4: Add the banner to `FixturesTab`.** Add two optional fields + a banner widget:
```dart
  final bool predictionsOpen;
  final VoidCallback? onOpenPredict;
```
(add to constructor with defaults `this.predictionsOpen = false, this.onOpenPredict,`). Then in `build()`, when `matches` is non-empty, prepend the banner above the `ListView` by wrapping the return in a `Column` (or insert as the first item of the `ListView`). Minimal: make the `ListView.builder` itemCount `sortedDates.length + (showBanner ? 1 : 0)` and render the banner at index 0:
```dart
    final showBanner = predictionsOpen && onOpenPredict != null;
    // in itemBuilder:
    //   if (showBanner && index == 0) return _predictBanner(context);
    //   final dateIdx = showBanner ? index - 1 : index;  ... use dateIdx
```
Banner widget:
```dart
  Widget _predictBanner(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: InkWell(
          onTap: onOpenPredict,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF0A7D2C), Color(0xFF0C9636)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: const [
              Text('🔮', style: TextStyle(fontSize: 20)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Predictions',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text('Predict every match · climb the leaderboard',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ]),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ]),
          ),
        ),
      );
```

- [ ] **Step 5: Verify** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter analyze lib/ 2>&1 | grep -E "error •" ; flutter test` → no new ERRORS (pre-existing warnings OK); all tests pass. Existing `widget_test.dart` still builds `FixturesTab` with the old args (new args are optional) — confirm it still passes.

- [ ] **Step 6: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git restore pubspec.lock 2>/dev/null || true
git add lib/tournamentdetail.dart lib/tournament_tabs/fixtures_tab.dart
git commit -m "feat: Predict tab in tournament + Fixtures predictions banner (gated on config.open)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7 (Functions): Pure prediction scoring + leaderboard compute (TypeScript)

**Files:** Create `functions/src/lib/predict.ts`, `functions/test/predict.test.ts`.

- [ ] **Step 1: Write the failing test** — `functions/test/predict.test.ts`:
```typescript
import { describe, expect, test } from 'vitest';
import { predictionPoints, computeLeaderboard } from '../src/lib/predict';

const SCORING = { matchWinner: 1, exactScore: 3 };

describe('predictionPoints', () => {
  test('exact', () => {
    expect(predictionPoints(2, 1, 2, 1, SCORING)).toEqual(
      { resultCorrect: true, exactCorrect: true, points: 4 });
  });
  test('result only', () => {
    expect(predictionPoints(2, 1, 3, 0, SCORING).points).toBe(1);
  });
  test('wrong', () => {
    expect(predictionPoints(2, 1, 0, 1, SCORING).points).toBe(0);
  });
  test('draw exact', () => {
    expect(predictionPoints(0, 0, 0, 0, SCORING).points).toBe(4);
  });
});

describe('computeLeaderboard', () => {
  const finals = [
    { id: 'm1', team1Score: 2, team2Score: 1, startedAtMs: 1000 },
    { id: 'm2', team1Score: 0, team2Score: 0, startedAtMs: 2000 },
  ];
  const preds = {
    m1: [
      { uid: 'u1', team1: 2, team2: 1, updatedAt: 900 }, // exact -> 4
      { uid: 'u2', team1: 1, team2: 0, updatedAt: 900 }, // result -> 1
      { uid: 'u3', team1: 2, team2: 1, updatedAt: 1500 }, // LATE -> ignored
    ],
    m2: [
      { uid: 'u1', team1: 0, team2: 0, updatedAt: 1000 }, // exact draw -> 4
    ],
  };

  test('sums points, counts exact, ignores late picks', () => {
    const lb = computeLeaderboard(finals, preds, SCORING);
    expect(lb['u1']).toEqual({ points: 8, exact: 2 });
    expect(lb['u2']).toEqual({ points: 1, exact: 0 });
    expect(lb['u3']).toBeUndefined(); // late prediction ignored entirely
  });

  test('idempotent (running twice is identical)', () => {
    const a = computeLeaderboard(finals, preds, SCORING);
    const b = computeLeaderboard(finals, preds, SCORING);
    expect(a).toEqual(b);
  });
});
```

- [ ] **Step 2: Run it, expect FAIL** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test` → fails (no `predict.ts`).

- [ ] **Step 3: Implement `functions/src/lib/predict.ts`**:
```typescript
export interface PredScoring { matchWinner: number; exactScore: number }

export interface FinalMatch {
  id: string;
  team1Score: number;
  team2Score: number;
  startedAtMs: number; // kickoff; predictions must predate this to count
}

export interface UserPrediction {
  uid: string;
  team1: number;
  team2: number;
  updatedAt: number;
}

export interface PredResult { resultCorrect: boolean; exactCorrect: boolean; points: number }

export function predictionPoints(
  p1: number, p2: number, a1: number, a2: number, s: PredScoring,
): PredResult {
  const resultCorrect = Math.sign(p1 - p2) === Math.sign(a1 - a2);
  const exactCorrect = p1 === a1 && p2 === a2;
  const points = (resultCorrect ? s.matchWinner : 0) + (exactCorrect ? s.exactScore : 0);
  return { resultCorrect, exactCorrect, points };
}

/** Full recompute of a tournament's prediction leaderboard. Idempotent. */
export function computeLeaderboard(
  finals: FinalMatch[],
  predsByMatch: Record<string, UserPrediction[]>,
  scoring: PredScoring,
): Record<string, { points: number; exact: number }> {
  const out: Record<string, { points: number; exact: number }> = {};
  for (const m of finals) {
    const preds = predsByMatch[m.id] ?? [];
    for (const p of preds) {
      if (!(p.updatedAt < m.startedAtMs)) continue; // fairness: predate kickoff
      const r = predictionPoints(p.team1, p.team2, m.team1Score, m.team2Score, scoring);
      const cur = out[p.uid] ?? { points: 0, exact: 0 };
      cur.points += r.points;
      if (r.exactCorrect) cur.exact += 1;
      out[p.uid] = cur;
    }
  }
  return out;
}
```

- [ ] **Step 4: Run it, expect PASS** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test`.

- [ ] **Step 5: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/src/lib/predict.ts functions/test/predict.test.ts
git commit -m "feat(functions): pure prediction scoring + idempotent leaderboard compute

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8 (Functions): Trigger — recompute leaderboard on match finalize / score change

**Files:** Modify `functions/src/index.ts`.

Read the existing trigger declarations (`onTeam1Score`, `onTeam2Score`, `onMatchStatus`) and the `dbRoot(event)` helper and name-read helper. Mirror them. Multiple functions may listen on the same RTDB path, so these new triggers coexist with the Watcher.

- [ ] **Step 1: Add a recompute helper + name lookup** in `functions/src/index.ts`:
```typescript
import { computeLeaderboard, FinalMatch, UserPrediction, PredScoring }
  from './lib/predict';

async function readUserName(root: Reference, uid: string): Promise<string> {
  try {
    const [f, l] = await Promise.all([
      root.child(`Users/${uid}/First Name`).get(),
      root.child(`Users/${uid}/Last Name`).get(),
    ]);
    const name = `${f.val() ?? ''} ${l.val() ?? ''}`.trim();
    return name.length > 0 ? name : 'Player';
  } catch {
    return 'Player';
  }
}

async function recomputeLeaderboard(root: Reference, tid: string): Promise<void> {
  const cfgSnap = await root.child(`Tournaments/${tid}/PredictionConfig`).get();
  const cfg = (cfgSnap.val() ?? {}) as Record<string, unknown>;
  if (cfg['Open'] === false) {
    await root.child(`Tournaments/${tid}/Leaderboard`).remove();
    return;
  }
  const scoringRaw = (cfg['Scoring'] ?? {}) as Record<string, unknown>;
  const scoring: PredScoring = {
    matchWinner: Number(scoringRaw['MatchWinner'] ?? 1),
    exactScore: Number(scoringRaw['ExactScoreBonus'] ?? 3),
  };

  const matchesSnap = await root.child(`Tournaments/${tid}/Matches`).get();
  const matches = (matchesSnap.val() ?? {}) as Record<string, any>;
  const finals: FinalMatch[] = [];
  for (const [mid, m] of Object.entries(matches)) {
    const status = Number(m?.Status ?? m?.status ?? 0);
    const startedAtMs = Number(m?.Clock?.StartedAt ?? m?.clock?.startedAt ?? 0);
    if (status === 2 && startedAtMs > 0) {
      finals.push({
        id: mid,
        team1Score: Number(m?.Team1Score ?? m?.team1Score ?? 0),
        team2Score: Number(m?.Team2Score ?? m?.team2Score ?? 0),
        startedAtMs,
      });
    }
  }

  const predsByMatch: Record<string, UserPrediction[]> = {};
  const predsSnap = await root.child(`Tournaments/${tid}/Predictions`).get();
  const preds = (predsSnap.val() ?? {}) as Record<string, any>;
  for (const f of finals) {
    const byUser = (preds[f.id] ?? {}) as Record<string, any>;
    predsByMatch[f.id] = Object.entries(byUser).map(([uid, p]) => ({
      uid,
      team1: Number(p?.Team1 ?? p?.team1 ?? 0),
      team2: Number(p?.Team2 ?? p?.team2 ?? 0),
      updatedAt: Number(p?.UpdatedAt ?? p?.updatedAt ?? 0),
    }));
  }

  const totals = computeLeaderboard(finals, predsByMatch, scoring);

  // Compose the leaderboard node with display names.
  const board: Record<string, { Name: string; Points: number; Exact: number }> = {};
  await Promise.all(Object.entries(totals).map(async ([uid, t]) => {
    board[uid] = { Name: await readUserName(root, uid), Points: t.points, Exact: t.exact };
  }));
  await root.child(`Tournaments/${tid}/Leaderboard`).set(board);
}
```
NOTE: confirm `Reference` is imported in index.ts (the Watcher uses it for `dbRoot`). Reuse the existing `dbRoot(event)` helper to get `root`.

- [ ] **Step 2: Add the triggers** (mirror the existing `onValueWritten` declarations; new export names so they don't collide with the Watcher's):
```typescript
export const onPredictMatchStatus = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Status',
  async (event) => {
    const tid = event.params['tid'] as string;
    await recomputeLeaderboard(dbRoot(event), tid);
  },
);

export const onPredictTeam1Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team1Score',
  async (event) => {
    await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string);
  },
);

export const onPredictTeam2Score = onValueWritten(
  '/Tournaments/{tid}/Matches/{mid}/Team2Score',
  async (event) => {
    await recomputeLeaderboard(dbRoot(event), event.params['tid'] as string);
  },
);
```

- [ ] **Step 3: Build** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm run build` → compiles clean. Then `npm test` → all tests still pass.

- [ ] **Step 4: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter"
git add functions/src/index.ts
git commit -m "feat(functions): recompute prediction leaderboard on finalize/score-change

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
NOTE: Do NOT deploy in this task. Deployment is a separate, owner-gated step (see `functions/REHEARSAL.md`). The fan app reads `Leaderboard` regardless; until deployed it simply stays empty.

---

### Task 9 (Manager): Predictions on/off toggle

**Files:** New branch `zaya-predictions`; modify `lib/core/constants/firebase_paths.dart`, `lib/models/tournament.dart`, `lib/services/firebase/tournament_service.dart`, `lib/ui/tournaments/tournament_dashboard_page.dart`; Test `test/tournament_predictions_open_test.dart`.

- [ ] **Step 1: Create the branch**
```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git checkout zaya-live-scores && git checkout -b zaya-predictions
git branch --show-current   # expect: zaya-predictions
```

- [ ] **Step 2: Write the failing test** — `test/tournament_predictions_open_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:infinite_app_manager/models/tournament.dart';

void main() {
  test('predictionsOpen defaults true when PredictionConfig absent', () {
    final t = Tournament.fromFirebase('t1', {'Name': 'Cup'});
    expect(t.predictionsOpen, true);
  });
  test('predictionsOpen reads PredictionConfig/Open=false', () {
    final t = Tournament.fromFirebase('t1', {
      'Name': 'Cup',
      'PredictionConfig': {'Open': false},
    });
    expect(t.predictionsOpen, false);
  });
}
```

- [ ] **Step 3: Run it, expect FAIL** — `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test test/tournament_predictions_open_test.dart`.

- [ ] **Step 4: Add `predictionsOpen` to `lib/models/tournament.dart`.** Add `final bool predictionsOpen;` to the fields and constructor (default not needed — it's required-with-parse). In `fromFirebase`, after the existing `parseBool` helper, add:
```dart
    final predCfg = data['PredictionConfig'];
    final predOpenRaw = (predCfg is Map) ? (predCfg['Open'] ?? predCfg['open']) : null;
```
and in the returned `Tournament(...)`:
```dart
      predictionsOpen: predOpenRaw == null ? true : parseBool(predOpenRaw),
```
Add `required this.predictionsOpen,` to the constructor — OR give it a default `this.predictionsOpen = true,` so other constructions (e.g. wizard) don't break. Prefer the default to avoid touching unrelated call sites; confirm by `flutter analyze`.

- [ ] **Step 5: Add path helpers** to `lib/core/constants/firebase_paths.dart` (next to the other tournament helpers):
```dart
  static String tournamentPredictionConfig(String tournamentId) =>
      '$tournaments/$tournamentId/PredictionConfig';
  static String tournamentPredictionOpen(String tournamentId) =>
      '$tournaments/$tournamentId/PredictionConfig/Open';
```

- [ ] **Step 6: Add the service method** to `lib/services/firebase/tournament_service.dart` (mirror `setTournamentFinished`):
```dart
  Future<bool> setPredictionsOpen(String tournamentId, bool open) {
    return updateTournamentField(tournamentId, 'PredictionConfig/Open', open);
  }
```

- [ ] **Step 7: Run the test, expect PASS** — `flutter test test/tournament_predictions_open_test.dart`.

- [ ] **Step 8: Add the dashboard toggle** in `lib/ui/tournaments/tournament_dashboard_page.dart`, right after the "Mark Finished" `SwitchListTile`:
```dart
              SwitchListTile(
                title: const Text('Predictions'),
                subtitle: const Text(
                    'Let fans predict scores and compete on a leaderboard.'),
                value: t.predictionsOpen,
                onChanged: (val) async {
                  await service.setPredictionsOpen(tournamentId, val);
                  refreshTournament(ref, tournamentId);
                },
              ),
```

- [ ] **Step 9: Verify** — `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter analyze lib/ 2>&1 | grep -E "error •" ; flutter test` → no new errors; all tests pass.

- [ ] **Step 10: Commit**
```bash
cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter"
git add lib/core/constants/firebase_paths.dart lib/models/tournament.dart lib/services/firebase/tournament_service.dart lib/ui/tournaments/tournament_dashboard_page.dart test/tournament_predictions_open_test.dart
git commit -m "feat: Manager dashboard toggle for tournament Predictions on/off

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Full verification + build/install + SURFACE TO OWNER

- [ ] **Step 1: Fan tests + analyze** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter" && flutter test && flutter analyze lib/ 2>&1 | grep -E "error •" || echo "no errors"`. All tests pass; no new errors.
- [ ] **Step 2: Functions** — `cd "C:/Users/zayaa/StudioProjects/infinite_sports_flutter/functions" && npm test && npm run build`. Green + compiles.
- [ ] **Step 3: Manager tests + analyze** — `cd "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" && flutter test && flutter analyze lib/ 2>&1 | grep -E "error •" || echo "no errors"`.
- [ ] **Step 4: Final whole-feature review** (dispatch a reviewer): scoring parity (Dart `predictionPoints` vs TS), lock fairness (`UpdatedAt < StartedAt`), tab gating on `config.open` (tab + banner appear/disappear together), sign-in CTA path, leaderboard sort/tiebreak, idempotent recompute, no stray files staged, all commits local.
- [ ] **Step 5: Build + install both apps** on the owner's devices (release APKs, install to `GN434J02403404RL` + `emulator-5554`). STOP and surface the test recipe: sign in on the fan app → open a tournament → tap the Fixtures **Predictions** banner → predict a few scores in the **Predict** tab → in the Manager, finalize one of those matches → confirm the fan **Leaderboard** updates with the right points (and the points pill). Toggle Predictions **off** in the Manager dashboard → confirm the Predict tab + banner disappear in the fan app. NOTE the leaderboard only populates after the Cloud Function is **deployed** (owner-gated, separate step) — call this out so the owner knows live leaderboard scoring needs a deploy.

---

## Self-review notes
- **Spec coverage:** §2 data model → Tasks 2,3,7,8,9 (paths/models/read/write). §3 scoring rule → Tasks 1 (Dart) & 7 (TS), parity asserted. §4 resolution function → Tasks 7,8 (full idempotent recompute, UpdatedAt<StartedAt, name lookup, skip when closed). §5 fan UI → Tasks 4 (card), 5 (tab+leaderboard+pill), 6 (tab wiring + banner + sign-in CTA). §6 Manager toggle → Task 9. §7 edge cases: not-signed-in (Task 4 CTA), off (Tasks 6 gating + 8 remove), TBD teams (Task 4 hasBothTeams), reopen/correction (Task 7 full recompute), late pick (Task 7/8 UpdatedAt check), ties (Task 2 compareLeaderboard), empty (Task 5 empty states). §8 testing → pure (1,2,7), widget (4,5), manual (10).
- **Type consistency:** `predictionPoints` named args (Dart) vs positional (TS) — intentional per language idiom, same rule. `MatchPrediction{team1,team2,updatedAt}` ↔ Firebase `Team1/Team2/UpdatedAt` consistent across Tasks 2,3,7,8. `LeaderboardEntry{uid,name,points,exact}` ↔ `Name/Points/Exact` consistent (Tasks 2,8). `PredictionConfig{open,matchWinnerPoints,exactScorePoints}` (fan) reads `Open/Scoring.MatchWinner/ExactScoreBonus` (Tasks 2,3); function reads same keys (Task 8). `config.open` gates tab+banner together (Task 6).
- **No placeholders:** every code step contains real code; NOTE lines flag the 3 facts the implementer must confirm against source (parse_helpers names, TeamLogo params, Reference import) rather than leaving them vague.
