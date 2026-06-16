# Predictions — Design Spec (Phase 1: Match Predictions + Leaderboard)

**Date:** 2026-06-15
**Status:** Approved by owner (brainstorm 2026-06-15, FotMob Predict reference)
**Branches:** `zaya/predictions` (fan, off `zaya/live-scores`) + a Manager branch off `zaya-live-scores` (toggle only)
**Apps:** Fan (predict UI + leaderboard + scoring function) · Manager (on/off toggle)

---

## 1. Overview

Signed-in fans predict the **exact score** of each tournament match before kickoff. A score pick **is** a winner pick: getting the result right scores points, and nailing the exact score scores a bonus. A per-tournament **leaderboard** ranks everyone. This is the flagship engagement feature, modeled on FotMob Predict.

**Phase 1 scope (this spec):**
- **Tournament system only**, but **all sports** (a tournament already carries its sport; "predict the score" works for any scored sport).
- **Match predictions** (winner + exact score) and a **per-tournament leaderboard**.

**Explicitly later phases (NOT this spec):**
- Tournament-outcome predictions (Champion/Runner-up/Third) and player-award predictions (Golden Boot, etc.) — the config already carries these categories; we ignore them in Phase 1.
- Predictions for the legacy **League seasons** (different, older subsystem) — separate future spec.

### Decisions locked in brainstorming
1. **Card style = score-first (Option A).** Fan sets the exact score with +/− steppers; the **winner is derived and shown** ("By predicting 2–1, you're backing Eagles to win"). A small breakdown spells out the two tiers of points.
2. **Scoring = +1 correct result, +3 exact score** (additive → up to 4/match). These are the defaults already in `PredictionConfig.Scoring` (`MatchWinner`, `ExactScoreBonus`) and remain per-tournament adjustable.
3. **Lock at kickoff.** Editable any time while the match is *scheduled*; locked once it goes live.
4. **Sign-in required to predict.** The fan's profile name shows on the leaderboard. Anyone can view the leaderboard.
5. **Placement:** a new **"Predict" tab** inside the tournament (6th tab) with a **Matches ⇄ Leaderboard** toggle, plus a **banner on the Fixtures tab** that opens the Predict tab. A points pill (the fan's total) sits in the Predict tab header.
6. **On by default per tournament**, with a Manager dashboard **on/off toggle** (`PredictionConfig.Open`).
7. **Auto-scored** by a Cloud Function (same `functions/` infra as the notification Watcher); recomputes the tournament's leaderboard whenever a match is finalized or its final score is corrected.
8. **Leaderboard columns:** rank · player · **Pts** · **Exact** (count of exact-score hits); ranked by Pts, ties broken by Exact, then name.

---

## 2. Data model (Firebase RTDB)

### Existing (already written on tournament creation — unchanged)
`Tournaments/{tid}/PredictionConfig`
```
Open        true                       // master on/off for this tournament
Scoring/    { MatchWinner: 1, ExactScoreBonus: 3, ... }
Categories/ { MatchWinner: true, ExactScoreBonus: true, ... }   // other categories ignored in Phase 1
```

### New — a fan's prediction for one match
`Tournaments/{tid}/Predictions/{matchId}/{uid}`
```
Team1      2          // predicted goals/points for team1
Team2      1          // predicted for team2
UpdatedAt  <ms epoch> // last edit time (used for the kickoff-fairness check)
```
- Written by the fan app when a signed-in user locks/changes a prediction while the match is **scheduled** (status 0).
- One node per (match, user). Re-saving overwrites.

### New — the computed leaderboard (written ONLY by the Cloud Function)
`Tournaments/{tid}/Leaderboard/{uid}`
```
Name    "Maria G."   // composed from Users/{uid} First+Last (or a fallback)
Points  18
Exact   4            // number of matches with an exact-score hit
```
- The fan app reads/streams this node directly (small, already-ranked data) — it never reads other users' raw predictions.

New path helpers (fan `utility.dart`-style + Manager `FirebasePaths`): `tournamentPredictions(tid)`, `tournamentMatchPredictions(tid, matchId)`, `tournamentMyPrediction(tid, matchId, uid)`, `tournamentLeaderboard(tid)`.

---

## 3. Scoring rule (the single source of truth — implemented identically in Dart and TS)

Given a prediction `(a, b)` = (team1, team2) and the match's final score `(x, y)`, with scoring `S` (`mw = MatchWinner`, `eb = ExactScoreBonus`):

```
resultCorrect = sign(a - b) == sign(x - y)      // both home-win, both away-win, or both draw
exactCorrect  = (a == x) && (b == y)
points        = (resultCorrect ? mw : 0) + (exactCorrect ? eb : 0)
```
- `exactCorrect` implies `resultCorrect`, so an exact hit scores `mw + eb` (default 4).
- **Fairness / lock:** a prediction counts only if it was submitted before kickoff. The function ignores any prediction whose `UpdatedAt` is **not** strictly before the match kickoff (`Clock.StartedAt`). If a match has no clock yet it isn't final, so nothing to score.
- **Exact column** = count of matches where `exactCorrect` for that user.

This rule is small and pure. It is implemented as a pure Dart helper (`predictionPoints`) for the fan's own-card display ("you scored +4"), and re-implemented (with a mirrored unit test) in the TS function for the leaderboard. Like the `MatchClock` parity pattern, both must agree by construction.

---

## 4. Leaderboard resolution (Cloud Function, `functions/`)

A new trigger (alongside the existing Watcher) recomputes a tournament's leaderboard whenever a match becomes final **or a finalized match's score changes** (corrections via the undo-stat feature must re-resolve).

**Trigger:** RTDB write on `Tournaments/{tid}/Matches/{matchId}/Status` (and `/Team1Score`, `/Team2Score`). Debounced/guarded so a burst of writes collapses to one recompute.

**Recompute (full, idempotent):**
1. Read `PredictionConfig` (skip if `Open == false`).
2. Read all matches for the tournament; keep those that are **final** (status 2) with a `Clock.StartedAt`.
3. For each final match, read `Predictions/{matchId}/*`; for each `(uid, pick)` with `UpdatedAt < StartedAt`, add `predictionPoints(pick, finalScore, Scoring)` and increment the user's exact count if exact.
4. Compose each user's `{ Points, Exact }`; look up `Name` from `Users/{uid}` (cached, like the Watcher's name cache).
5. Overwrite `Tournaments/{tid}/Leaderboard` with the recomputed per-uid totals (removing users who now have zero — e.g., a match was reopened).

Full recompute (vs incremental) is chosen for correctness under score corrections and match reopen/reset — the same philosophy as "recompute stats on finish." Tournaments are community-scale (tens of matches, up to hundreds of players), so a full pass per finalization is cheap.

**No deploy ordering risk:** this function is additive to the existing `functions/` workspace; it does not touch the Watcher.

---

## 5. Fan app UI

### 5.1 Predict tab (`lib/tournament_tabs/predict_tab.dart`, new)
Added as the 6th tab in `tournamentdetail.dart` (`Tab(text: 'Predict')`), shown only when `PredictionConfig.Open`. Header right shows the fan's **points pill** (their `Leaderboard/{uid}.Points`, or "—" if none). A segmented control switches:
- **Matches** — predict cards grouped by day (reuse the day-grouping used by `FixturesTab`/`TournamentDayView`). Each card = §5.2.
- **Leaderboard** — streamed list from `Tournaments/{tid}/Leaderboard`, sorted Pts desc → Exact desc → Name; columns rank · player · Pts · Exact; the signed-in user's row highlighted.

### 5.2 Predict card (the score-first card)
For a single match:
- Team1 — `[ +/ n /− ]` stepper — stepper — Team2, with crests and names.
- **Scheduled (status 0), signed in:** steppers editable; below them a derived line ("By predicting 2–1, you're backing **Eagles to win**" / "…a **draw**"); a small breakdown (✓ Right winner +1 · ✓ Exact score +3 more · Best case 4); a **Lock prediction** button (or "Update pick" once saved). Saving writes §2 with `UpdatedAt = now`.
- **Not signed in:** steppers disabled; a "Sign in to predict" CTA routing to the existing login flow.
- **Live/Final (status 1/2):** steppers locked (read-only) showing the fan's pick; once final, show the fan's earned points for this match using the pure `predictionPoints` helper ("You scored +4 · exact!" / "+1 result" / "0 pts"). The actual score is shown alongside.
- **Teams TBD** (knockout placeholder, team not yet known): no steppers; "Prediction opens when both teams are set."

### 5.3 Fixtures banner (`lib/tournament_tabs/fixtures_tab.dart`)
When `PredictionConfig.Open`, render a compact banner at the top of the Fixtures list: "🔮 Predictions — predict every match · You: N pts" → tapping switches the tournament's tab controller to the Predict tab. Hidden when predictions are off.

### 5.4 Models & service (fan)
- Model `MatchPrediction { int team1, int team2, int updatedAt }` + parse; `PredictionConfig` parse (`open`, `scoring`).
- Service (`utility.dart` or a small `prediction_service.dart`): `submitPrediction(tid, matchId, uid, t1, t2)`, `watchMyPrediction(tid, matchId, uid)` / `watchMyPredictions(tid, uid)`, `watchLeaderboard(tid)`, `watchPredictionConfig(tid)`.
- Pure helper `predictionPoints(pred, actual, scoring) → (resultCorrect, exactCorrect, points)` + tests.

---

## 6. Manager app UI

- **Dashboard toggle** (`tournament_dashboard_page.dart`): a switch "Predictions — let fans predict scores and compete on a leaderboard" bound to `PredictionConfig.Open`. Service method `setPredictionsOpen(tid, bool)`.
- No other Manager changes in Phase 1 (the default config is already written on tournament creation; scoring values stay at defaults). Editing scoring values is a later enhancement.

---

## 7. Edge cases
- **Not signed in:** can view leaderboard; predicting shows a sign-in CTA.
- **Predictions off (`Open=false`):** Predict tab and Fixtures banner hidden; function skips the tournament.
- **Match reopened/reset (final → scheduled):** card becomes editable again; next recompute drops that match's points until it finalizes again.
- **Score correction after final** (undo-stat): the function re-resolves (full recompute), leaderboard adjusts.
- **Late prediction** (somehow written after kickoff): ignored by the function (`UpdatedAt < StartedAt` check); client also prevents it.
- **TBD opponents (knockout):** no prediction until both teams set.
- **Tie on leaderboard:** Pts → Exact → name (stable).
- **No predictions yet:** leaderboard empty-state ("Be the first to predict"); points pill shows "—".

## 8. Testing
1. **Pure Dart (`predictionPoints`):** result-only, exact, wrong, draw-correct, draw-exact, zero — point totals and flags.
2. **Pure Dart (leaderboard sort/tiebreak helper):** Pts desc, Exact tiebreak, name tiebreak.
3. **Pure TS (function scoring):** mirror of the Dart cases (parity guard) + the `UpdatedAt < StartedAt` exclusion + full-recompute idempotency (running twice yields the same leaderboard) + score-correction re-resolve.
4. **Widget (fan):** predict card editable when scheduled + signed in; locked when live; shows earned points when final; sign-in CTA when signed out; leaderboard renders sorted rows with the user highlighted; Fixtures banner shows only when Open.
5. **Manual:** sign in on the fan app → predict a few matches in a tournament → Manager finalizes a match → fan leaderboard updates with correct points; toggle predictions off in Manager → tab + banner disappear.

## 9. Review checklist (Paul & Bronsin)
- New DB subtrees: `Tournaments/{tid}/Predictions/**` (fans write own node) and `Tournaments/{tid}/Leaderboard/**` (function writes only). Both additive; `PredictionConfig` already existed.
- Recommend Firebase security rules (hardening, can follow): a user may write only `Predictions/{matchId}/{ownUid}` and only while the match is scheduled; `Leaderboard` is function-write-only. Phase-1 fairness is enforced by the function's `UpdatedAt < StartedAt` check regardless.
- New Cloud Function is additive to `functions/`; does not touch the Watcher; full-recompute design is correction-safe.
- Fan changes are contained to a new Predict tab + a Fixtures banner + a small service/model/helper. Manager change is a single dashboard toggle.
