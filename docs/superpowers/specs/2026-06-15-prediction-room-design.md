# Prediction Room — Design Spec (Predictions Phase 2)

**Date:** 2026-06-15
**Status:** Approved by owner (brainstorm 2026-06-15, FotMob prediction-room reference)
**Branches:** `zaya/predictions` (fan + functions) · `zaya-predictions` (Manager)
**Builds on:** Predictions Phase 1 (`2026-06-15-predictions-design.md`). Phase 1's single score prediction becomes one of several **questions** per match.

---

## 1. Overview

Each match gets a **Prediction Room** — a list of prediction **questions** (Who will win? Correct score? Total goals over/under? plus owner-authored custom ones). The fan **Predict tab becomes the hub**: its Matches list is the game index; tapping a game opens that game's room; the Leaderboard sub-tab stays. The match detail's **Facts tab** gets a "Who will win?" teaser above the stats that, once answered, offers **"Enter prediction room →"** into that game's room.

Each question carries its own **points**. Common questions **auto-resolve** from the result; **custom** questions are resolved by the owner tapping the winning option in the Manager. All scoring flows into the existing per-tournament leaderboard via the already-deployed Cloud Function (extended here).

### In scope
- Question model (auto + custom), per match, with per-question points.
- Fan: Prediction Room page (per match), Predict-tab hub index, match-detail "Who will win?" teaser.
- Manager: tournament-wide **default questions** editor, **per-match** questions editor, and per-match **resolution** of custom questions.
- Functions: scoring extended to evaluate arbitrary questions (auto + custom) with per-question points.

### Build staging (one spec, two shippable stages)
- **Stage A** — questions data model + fan room/hub/teaser + the three **auto** question types (matchWinner, correctScore, totalGoals) + Manager tournament-default editor + auto scoring. This alone is a working, shippable room.
- **Stage B** — **custom** free-form questions + per-match question editor + per-match manual resolution + custom scoring.

### Out of scope (still later)
- Auto player questions (auto "first scorer" from lineup) — "Who scores first?" ships as a **custom** (manual) question.
- Tournament-outcome predictions (champion/runner-up/third) and league-season predictions.
- In-play (live) questions — **all questions lock at kickoff**.

### Test-data note
Phase 1 stored a prediction as `Predictions/{mid}/{uid} = {Team1,Team2,UpdatedAt}`. Phase 2 reshapes this to per-question answers (§2). The live store has **no real prediction data** (Phase 1 is unreleased), so there is no migration — any on-device Phase-1 test predictions under `Predictions/**` should be cleared once before testing Phase 2.

---

## 2. Data model (Firebase RTDB)

### Question definitions
A **question** = `{Text, Type, Points, Order, Options?, Line?}`.
- `Type` ∈ `matchWinner | correctScore | totalGoals | custom`.
- `Options` (list of `{Id, Label}`) only for `custom`. `Line` (number, e.g. 2.5) only for `totalGoals`.
- matchWinner/correctScore/totalGoals render their options dynamically (teams / steppers / Over-Under) — no stored Options.

Two sources, unioned per match:
- **Tournament-wide (defaults):** `Tournaments/{tid}/PredictionQuestions/{qid}` — applied to every match.
- **Per-match extras:** `Tournaments/{tid}/Matches/{mid}/PredictionQuestions/{qid}` — that match only.

**Seeded on tournament creation** (Manager `createTournament`, alongside PredictionConfig) — two tournament-wide defaults so a new tournament works with zero setup:
```
PredictionQuestions/
  q_winner { Text:"Who will win?",  Type:"matchWinner",  Points:1, Order:0 }
  q_score  { Text:"Correct score",  Type:"correctScore",  Points:3, Order:1 }
```

### Fan answers (per question)
`Tournaments/{tid}/Predictions/{matchId}/{uid}/{qid}` =
```
Answer     <value>      // see §3 per type
UpdatedAt  <ms epoch>   // for the kickoff-fairness check (per answer)
```

### Custom-question results (per match, owner-set)
`Tournaments/{tid}/Matches/{matchId}/PredictionResults/{qid}` = `<correctOptionId>`
(Auto types need no stored result — the function computes them from the final score.)

### Leaderboard (unchanged shape, function-written)
`Tournaments/{tid}/Leaderboard/{uid}` = `{Name, Points, Exact}` — `Exact` = count of correctScore exact hits (kept as a fun secondary stat; ranking is Points → Exact → name).

New path helpers both apps: `tournamentPredictionQuestions(tid)`, `matchPredictionQuestions(tid, mid)`, `matchPrediction(tid, mid, uid)`, `matchPredictionResults(tid, mid)`.

---

## 3. Question types, answers, and resolution

| Type | Fan input | Answer value | Correct answer | Points if |
|------|-----------|--------------|----------------|-----------|
| `matchWinner` | three buttons (Team1 / Draw / Team2) | `'team1' \| 'draw' \| 'team2'` | from final score sign | answer == result |
| `correctScore` | two +/− steppers | `{Team1, Team2}` | the final score | exact match (also bumps `Exact`) |
| `totalGoals` | Over / Under buttons (label shows `Line`) | `'over' \| 'under'` | `(t1+t2) > Line ? over : under` (== Line ⇒ under) | answer == computed |
| `custom` | one button per `Option` | the chosen `Option.Id` | owner-set `PredictionResults/{qid}` | answer == correctOptionId |

- Resolution is pure: a helper `resolveQuestion(question, finalScore, customResult?) → correctAnswer?` (returns null if a custom question is unresolved). Implemented identically in Dart (fan display of "you got it") and TS (leaderboard). 
- **Fairness/lock:** an answer counts only if `UpdatedAt < match.Clock.StartedAt` (same rule as Phase 1). Unresolved custom questions award nobody until the owner sets the result (then the next recompute pays them).

---

## 4. Fan UI

### 4.1 Prediction Room page — `lib/prediction_room_page.dart` (new, pushed route)
`PredictionRoomPage(tournamentId, match, teams, config, currentUid)`. Header: teams + "locks at kickoff" (or "Locked" / "Final"). Body: the match's questions (defaults ∪ per-match), ordered by `Order`, each a card with its input (per §3), its points, and — when final — the fan's earned result ("✓ +3" / "✗"). A **Save** affordance writes each changed answer with `UpdatedAt = now`. Signed-out → "Sign in to predict" CTA. Footer: **"← All games"** (pop to hub) so fans can hop to other games. Reuses the Phase-1 `predictionPoints` for the correctScore card display.

### 4.2 Predict-tab hub (enrich `lib/tournament_tabs/predict_tab.dart`)
The **Matches** sub-tab list becomes a **game index**: each row shows the game + a progress chip ("2/4 predicted" / "Predict" / "Locked"). Tapping a row **pushes `PredictionRoomPage`** for that match. (The Phase-1 inline score card is replaced by this index row.) Leaderboard sub-tab + points pill unchanged. Ordering stays "predictable first" (the post-launch fix).

### 4.3 Match-detail teaser (`lib/tournament_tabs/match_facts_tab.dart`)
At the **top of the Facts tab** (above the existing timeline/Match Leaders): a **"Who will win?"** card (Team1 / Draw / Team2). Selecting an option writes the `matchWinner` answer for that match; afterward an **"Enter prediction room →"** button pushes `PredictionRoomPage` for the match. Hidden when predictions are off or the match has no matchWinner question. Signed-out → sign-in CTA. *Fallback (judged on-device): if it crowds the Facts tab, move it to a 3rd match-detail tab "Predict".*

---

## 5. Manager UI

### 5.1 Tournament default-questions editor (Stage A)
From the tournament dashboard (near the Predictions toggle): a **"Prediction questions"** screen listing the tournament-wide `PredictionQuestions`. Add/edit/delete:
- Pick **Type** (Who-will-win / Correct-score / Total-goals / Custom).
- **Points** (number). **Order** (drag or up/down).
- Total-goals: a **Line** field (default 2.5). Custom: **question text + 2–4 options**.
Who-will-win + Correct-score are seeded by default; the owner can change their points or remove them.

### 5.2 Per-match questions + resolution (Stage B)
On each match (a "Prediction questions" button in the Manager match editor / bracket): add **per-match custom questions** (same editor), and — after the game — a **"Resolve"** view listing every **custom** question for the match with its options, where the owner taps the winning option → writes `PredictionResults/{qid}`. Auto questions show "resolves automatically." 

New Manager service methods: `getPredictionQuestions(tid)`, `savePredictionQuestion(tid, q)`, `deletePredictionQuestion(tid, qid)`, and per-match variants + `setQuestionResult(tid, mid, qid, optionId)`.

---

## 6. Scoring function (extend `functions/`)
`functions/src/lib/predict.ts` gains `resolveQuestion` + a generalized `computeLeaderboard` that, per final match: builds the effective question set (tournament defaults ∪ per-match), resolves each (auto from final score; custom from `PredictionResults`), and for every fan answer with `UpdatedAt < StartedAt` awards `question.Points` when the answer matches. Sums per uid into `{Points, Exact}` (Exact = correctScore exacts), drops zero-point users (Phase-1 fix), full overwrite (idempotent). The existing `onPredict*` triggers also need to recompute when **`PredictionResults`** or **`PredictionQuestions`** change (owner resolves a custom question / edits points) — add triggers on `Tournaments/{tid}/Matches/{mid}/PredictionResults/{qid}` and on the question paths. No new Watcher impact; deploy only the prediction functions.

---

## 7. Edge cases
- **Unresolved custom question** (owner hasn't marked it): awards nobody; leaderboard updates when resolved.
- **Question edited/points changed after a final match:** recompute trigger re-runs; leaderboard adjusts.
- **Per-match question added after kickoff:** fans can't answer (locked), so it awards nobody — acceptable; the owner should add custom questions before kickoff.
- **TBD teams (knockout):** room shows "opens when both teams are set" for matchWinner/correctScore; other questions still answerable.
- **Predictions off (`Open=false`):** hub/teaser/room hidden; function skips the tournament.
- **Signed-out:** can view; answering prompts sign-in.
- **Total goals exactly on the line:** counts as **Under** (documented).

## 8. Testing
1. **Pure Dart/TS parity:** `resolveQuestion` for each type (winner sign, exact score, over/under incl. on-the-line, custom match), and per-question scoring; leaderboard idempotency + zero-drop (extends Phase-1 tests).
2. **Widget (fan):** room renders mixed question inputs; locks at kickoff; shows earned points when final; sign-in CTA signed-out; hub index row shows progress + pushes room; Facts "Who will win?" writes the answer + reveals the room button.
3. **Manager:** default-questions editor round-trips a question; resolution writes `PredictionResults`; seed adds q_winner + q_score on create.
4. **Manual:** author a Total-goals default + a custom question; predict on the fan app from both the teaser and the room; finalize the match; resolve the custom question in the Manager → leaderboard reflects all points.

## 9. Review checklist (Paul & Bronsin)
- New subtrees: `Tournaments/{tid}/PredictionQuestions/**`, `.../Matches/{mid}/PredictionQuestions/**`, `.../Matches/{mid}/PredictionResults/**`; `Predictions/{mid}/{uid}/{qid}` replaces the Phase-1 flat shape (no live data to migrate).
- Scoring function generalized but still additive to `functions/`; Watcher untouched; deploy only `onPredict*`.
- Fan adds a pushed `PredictionRoomPage` + hub-index change + Facts teaser; Manager adds a questions editor + resolution. Built in two shippable stages (A: auto, B: custom).
