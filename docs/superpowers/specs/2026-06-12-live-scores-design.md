# Live Scores & Real-Time Match Experience — Design Spec

**Date:** 2026-06-12
**Status:** Approved by owner (brainstorm 2026-06-12)
**Branches:** `zaya/live-scores` (fan app, stacked on `zaya/push-notifications`) · `zaya-live-scores` (Manager app, off main)
**Roadmap context:** Phase 1 item 4 ("Live bracket + scores"). This is **project 1 of 2**; the championship celebration + Man-of-the-Match voting are a separate follow-up spec ("Match-Day Delight").

---

## 1. Overview

Make the fan app feel alive: scores, tables, brackets, and match timelines update **by themselves in ~1 second** when the scorekeeper records something — no refresh button. Pages load instantly via cache + skeleton shimmer. Live matches show a **running match clock** and a **score-flash** animation, surface through a **"Happening now" rail + a "Live" filter**, and an **in-app goal toast** appears when a followed match scores while you're elsewhere in the app.

### In scope
1. Real-time auto-updating data (scores, match cards, league tables, knockout brackets, match timelines) via Firebase RTDB listeners.
2. Local cache + skeleton-shimmer loading (instant page render; fixes slow notification tap-through).
3. Running match clock — green circle minute on match-list rows, green `mm:ss` clock in the game-card header. **Requires a Manager-app change** to persist the clock (§5).
4. Score-flash animation when a score increases.
5. Pulsing red `LIVE` badge (already exists on the card — keep; add to list rows).
6. "Happening now" pinned rail (top of Matches tab) **and** a "Live" filter pill (Matches tab only).
7. In-app goal toast banner for followed matches/teams, tappable to open the match.

### Out of scope (separate specs)
- Championship celebration (confetti/trophy/medal) and Man-of-the-Match voting → "Match-Day Delight" spec.
- League-season (futsal/basketball/flag football) live scores — tournaments only for now; the listener layer is written generically so seasons can adopt it later.

### Non-goals
- No new backend/Cloud Functions (this is client listeners on data the Manager app already writes, plus the new clock fields).
- No change to how stats are computed.

---

## 2. Architecture — real-time + cache

Firebase Realtime Database already backs both apps. Today the fan app reads each screen once with `.get()`. The change:

- **Listeners, not one-shot reads.** Active screens attach `onValue` listeners (via the existing `TournamentService`, refactored to expose `Stream`s) to the specific match/tournament nodes they show. Firebase pushes every change to the listener; the widget rebuilds. Listeners are cancelled in `dispose()` so we never leak or update off-screen.
- **Disk persistence + keepSynced.** Enable `FirebaseDatabase.instance.setPersistenceEnabled(true)` once at startup (before any DB use, in `main.dart`). For the paths a screen is showing, call `keepSynced(true)` so RTDB caches them on disk and serves the last-known value **instantly** on next open, then streams fresh data. This is what makes pages feel immediate and fixes the slow notification tap-through.
- **Skeleton while truly empty.** A screen shows skeleton shimmer only when it has *no* cached value yet (first-ever open / cold cache). Once any data (cached or live) exists, it renders real content and updates in place.

### New/changed fan units
| File | Responsibility |
|---|---|
| `lib/misc/tournament_service.dart` — Modify | Add `Stream` variants alongside existing `get*` methods: `watchMatches(tid)`, `watchMatch(tid, mid)`, `watchTournament(tid)`. Each wraps a `ref().onValue` mapped to the existing models. Keep old `get*` methods for non-live callers. |
| `lib/misc/match_clock.dart` — Create | **Pure** clock math (unit-tested): `elapsed(MatchClock, nowMs) → Duration`, `minuteLabel(Duration) → "37'"`, `clockLabel(Duration) → "47:30"`, plus `MatchClock.fromMatch(...)`. No Flutter imports. |
| `lib/widgets/live_clock.dart` — Create | Two small widgets driven by `match_clock.dart` + a 1-second `Ticker`: `MinuteBall` (green circle for list rows) and `MatchClockText` (green `mm:ss` for the card). Tick only while the match is live and unpaused. |
| `lib/widgets/score_text.dart` — Create | A score number that flashes red + scales when its value increases (`AnimatedDefaultTextStyle` / implicit animation); plain when it decreases or on first build. |
| `lib/widgets/skeleton.dart` — Create | Reusable shimmer box + a few skeleton layouts (match-row, table-row, card header). |
| `lib/widgets/live_filter_bar.dart` — Create | The "Happening now" rail + the "Live" pill toggle for the Matches tab. |
| `lib/misc/goal_toast.dart` — Create | Listens for goals on followed matches while the app is foregrounded and shows the slide-down toast via an `OverlayEntry`; tapping routes to the match (reuses `notification_router.dart`). |

### Screens wired to live data
`frontpage.dart` (Matches list + rail + filter), `tournamentdetail.dart` (Fixtures / Table / Knockout tabs), `tournament_match_detail.dart` (scoreboard header clock + score flash + live timeline).

---

## 3. The four experience pieces (approved mockups)

1. **Clock** — match-list row: green **circle** minute on the left (FotMob style); game-card header: green **`mm:ss`** between the red `LIVE` badge and the day/date (date + location pushed down). Both tick locally every second while live & unpaused.
2. **Skeleton loading** — shimmer placeholders shaped like the content replace the spinner on cold loads; real data fades in.
3. **In-app goal toast** — slim dark banner slides down from the top for ~4s when a *followed* match scores while the app is open but not on that match; tap → match page. Reuses the `FollowStore` follow list.
4. **Live filter — BOTH:** a swipeable **"Happening now"** rail pinned at the top of the Matches tab showing live matches; **and** a **"Live" pill** top-right of the Matches tab (grey dot = all matches; tap → green dot = only live). The rail and pill live ONLY on the Matches tab.

Score-flash (§2) applies anywhere a live score is shown.

---

## 4. Real-time score flash & LIVE badge rules
- **Flash** fires only when a score value *increases* between two listener emissions (matches the notification "goal" rule; an undo/correction does not flash).
- **LIVE badge** shows when `status == 1`; pulses softly. On match-list rows the green minute circle replaces the kickoff time while live; pre-match rows show the scheduled time, finished rows show `FT` + final score.

---

## 5. Manager-app change — persist the match clock

The Manager clock is currently local-only (`_runningSince` + `_elapsedBefore` in `live_scoring_page.dart`). To let fans compute the live minute, the Manager writes a small clock object to the match; **fans read it once and tick locally** (no continuous writes).

**Schema (new), under `Tournaments/{tid}/Matches/{mid}/Clock`:**
```
Clock/
  StartedAt        number  — server timestamp (ms) at kickoff (status 0→1)
  PausedAccumMs    number  — total ms spent in COMPLETED pauses (default 0)
  PausedAt         number? — server timestamp (ms) when the current pause began; null/absent while running
```

**Elapsed math (shared, in `match_clock.dart` and mirrored in the Manager):**
`elapsedMs(now) = (PausedAt ?? now) − StartedAt − PausedAccumMs`

**Manager button wiring (`live_scoring_page.dart`):**
- **Start** (`_startClock`, status 0→1): write `Clock = { StartedAt: ServerValue.timestamp, PausedAccumMs: 0, PausedAt: null }`.
- **Pause** (`_pauseClock`): write `PausedAt = ServerValue.timestamp`.
- **Resume** (`_resumeClock`): `PausedAccumMs += (now − PausedAt)`; set `PausedAt = null`. (Read-modify-write via a transaction to stay correct.)
- **End** (`_stopClock`, status →2): leave `Clock` as-is (fans stop ticking because status≠1; the card switches to `FT`).
- **Reset to upcoming** (status →0): remove `Clock`.

The Manager keeps its existing local clock for the scorekeeper's own display (no behavior change they'll notice); these writes run alongside it. Manager-side elapsed math should be refactored to call the same pure helper to guarantee fan/Manager parity (a shared copy of the formula; the Manager has no access to the fan package, so it gets its own tiny tested helper with identical math).

**Fan consumption:** `MatchClock.fromMatch` reads the `Clock` object; `LiveClock` widgets tick every second using the device clock. Small device/server clock skew is acceptable (a few seconds) — the minute label is the important part. If `Clock` is absent (older matches, or Manager not yet updated), the fan simply shows `LIVE` with no minute — graceful fallback.

---

## 6. Edge cases
- **No `Clock` data** → show `LIVE` without a minute (no crash). Covers in-flight matches started before this ships.
- **Score decrease (undo)** → update silently, no flash.
- **Listener drops (network blip)** → RTDB auto-reconnects and re-emits; cached value stays on screen meanwhile.
- **Many simultaneous live matches** → rail scrolls horizontally; the Live pill filters the full list.
- **App backgrounded** → goal toast is foreground-only; background alerts are the push notifications (already shipped). No double-buzz: the toast is silent/visual.
- **Leaving a screen** → listeners cancelled in `dispose`; tickers stop.
- **Day rollover / timezone** for the "today" Matches view is unchanged (existing `game_day.dart` logic).

---

## 7. Testing
1. **Unit (pure):** `test/match_clock_test.dart` — elapsed math across running / paused / resumed / multi-pause / missing-data; minute & `mm:ss` formatting; minute is 1-based. Manager: `test/match_clock_test.dart` mirror for parity (same cases).
2. **Widget:** score-flash fires on increase only; skeleton shows when no data then swaps to content; `MinuteBall`/`MatchClockText` render expected strings for a given clock; Live filter hides non-live rows when on.
3. **Manual (owner, on device):** start a match in Manager → fan list shows green minute ticking and card shows `mm:ss`; pause in Manager → fan clock freezes; record a goal → score flashes + (if followed, app open elsewhere) toast slides down; tables/brackets update without refresh; reopen the app → pages appear instantly from cache.

---

## 8. Review checklist for Paul & Bronsin
- New DB subtree `Tournaments/{tid}/Matches/{mid}/Clock` (3 numeric fields) — Manager writes, fan reads; no security-rule change needed beyond existing tournament read/write.
- Fan app enables RTDB disk persistence (`setPersistenceEnabled(true)`) at startup — must be set before any other DB call.
- No new heavyweight dependencies (uses existing `firebase_database`; shimmer is hand-rolled, no package).
- Manager change is isolated to `live_scoring_page.dart` clock methods + a small tested helper.

## 9. Follow-up (separate "Match-Day Delight" spec, next project)
- Championship-final-only celebration: confetti + trophy + 1st-place medal.
- Man-of-the-Match fan voting (owner rules): appears under Match Leaders in the game card's Facts tab AFTER full time; **signed-in users only** — non-signed-in voters get a "Log in to vote" prompt; pick any player from either team; open until 11:59pm of the match day; at midnight the question disappears and the result locks, revealed as "Man of the Match — voted by the fans: <name>". One vote per signed-in user (stored under the match), changeable until lock.
