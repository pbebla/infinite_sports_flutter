# Tournament Push Notifications — Design Spec

**Date:** 2026-06-11
**Status:** Approved by owner (brainstorm 2026-06-11)
**Branches:** `zaya/push-notifications` (fan app) · `zaya-push-notifications` (Manager app, standby — no planned changes)
**Roadmap context:** Phase 1 item 5 of `2026-05-28-tournament-enhancements-design.md` (FCM + Cloud Functions)

---

## 1. Overview

Fans who opt in receive lock-screen push notifications for tournament match moments, fully automated from the Manager app's existing live-scoring writes. No one composes or sends anything manually.

A fan follows by tapping a **bell**:
- **Tournament bell** (tournament detail page) → alerts for every match in that tournament
- **Team bell** (team detail page) → alerts only for that team's matches

Delivery is FCM **topic**-based: device-level, no account required.

### Alert types (v1)

| Moment | Trigger (DB write by Manager app) | Notification |
|---|---|---|
| ⚽ Goal | `Team1Score` or `Team2Score` **increases** while `Status == 1` | Title "GOAL! Eagles 2–1 Lions"; body "Sam Smith (Eagles) 12' · Assist: Skylar Jackson" — scorer and assist best-effort, assist line only when one exists (body renders smaller than title on lock screens) |
| 🟢 Kickoff | `Status` transitions `0 → 1` | "Kickoff: Eagles vs Lions" + field/location when set |
| 🏁 Full time | `Status` transitions `→ 2` | "Full time: Eagles 3–1 Lions" |

**Explicitly out of v1:** red/yellow card alerts, "starts in 15 min" reminders, announcement pushes (separate upcoming feature that will reuse this sender), prediction nudges, league-season alerts (parked on schedule — see §9).

### Non-goals
- No notification history screen in-app.
- No server-stored per-user follow lists (device-local only).
- No retraction/correction pushes when a recorded stat is undone.

---

## 2. Architecture (Approach A — chosen)

```
Manager app (unchanged)          Firebase RTDB                Cloud Functions ("the Watcher")        Fans' phones
─────────────────────          ────────────────              ───────────────────────────────       ─────────────
Scorekeeper records goal  ──►  Team1Score: 1 → 2   ──fires──►  onScoreChange:                 ──►  FCM topic push
Taps Start match          ──►  Status: 0 → 1       ──fires──►  onStatusChange (kickoff)       ──►  arrives 1–3 s
Taps End match            ──►  Status: 1 → 2       ──fires──►  onStatusChange (full time)     ──►  after the tap
```

- **Manager app:** zero changes. Live scoring already writes `Tournaments/{tid}/Matches/{mid}/Team{1|2}Score` and `/Status` (ints; `Status` 0=pending, 1=live, 2=finished — see fan `lib/model/match_status.dart`, manager `FirebasePaths`).
- **Cloud Functions:** new `functions/` directory in the **fan-app repo**, TypeScript, Firebase Functions v2 RTDB triggers. Requires the Blaze plan (owner confirmed active; verify before deploy).
- **Fan app:** bells, topic subscribe/unsubscribe, Settings section, tap-to-open deep link.

Rejected alternatives: (B) Manager app sends directly — needs embedded server credentials, legacy send API removed, drops alerts on scorekeeper signal loss; (C) scheduled polling — up to 60 s lag, wasteful invocations.

---

## 3. Topic model

Topic names use only `[a-zA-Z0-9_-]`; ids are sanitized (percent-style escape of other chars) by a shared pure helper.

| Channel | Topic | Subscribed by |
|---|---|---|
| Whole tournament | `tournament_{tid}` | tournament bell |
| One team in a tournament | `tournament_{tid}_team_{teamId}` | team bell |
| (future) league season | `season_{sport}_{season}` | reserved naming, not built in v1 |

**One message per event, no duplicates:** the Watcher sends a single FCM message with a **condition**:
`'tournament_{tid}' in topics || 'tournament_{tid}_team_{t1}' in topics || 'tournament_{tid}_team_{t2}' in topics`
(3 topics, under FCM's 5-topic condition limit). A fan in multiple matching topics still receives exactly one notification.

---

## 4. The Watcher (Cloud Functions)

### Files

| File | Purpose |
|---|---|
| `functions/src/index.ts` | Trigger wiring only |
| `functions/src/lib/decide.ts` | **Pure** decision logic: (path, before, after, match snapshot) → `AlertDecision \| null` (alert kind, title, body, topics condition, dedupe key). Fully unit-tested. |
| `functions/src/lib/fcm.ts` | Thin send wrapper (condition + notification + data payload) |
| `functions/src/lib/names.ts` | Read tournament/team display names with in-invocation caching |
| `functions/test/decide.test.ts` | Unit tests for every rule in §4 + §6 |

### Triggers

1. `onValueWritten('/Tournaments/{tid}/Matches/{mid}/Team1Score')` and `.../Team2Score` → shared handler:
   - Ignore unless new > old (score **decrease or unchanged = silence**; covers undo-stat removals).
   - Ignore unless match `Status == 1` (post-final corrections = silence).
   - **Grace window:** claim the dedupe key immediately (so re-fires still skip), then wait ~10 s before
     reading activity and sending — gives the scorekeeper time to enter the assist after the goal.
   - Title: `"GOAL! {Team1} {s1} – {s2} {Team2}"`. Body (best-effort, omit parts not found):
     scorer = newest goal-type event in the scoring team's activity; assist = an assist event in the
     **same minute bucket** as that goal **or the next minute** (clock may tick between taps). Tap order
     is irrelevant — both events land in minute buckets, so goal-then-assist and assist-then-goal pair
     identically; the Manager app needs no entry-order rule and no changes.
   - Assist entered after the window: the alert already went out goal-only; no follow-up push.
2. `onValueWritten('/Tournaments/{tid}/Matches/{mid}/Status')`:
   - `0 → 1` → kickoff alert (include `MatchLocation` when present).
   - `anything → 2` → full-time alert with final score.
   - Any other transition (e.g. reopened match `2 → 1`) → silence.

### Idempotency / double-fire guard

Cloud Functions may rarely re-fire for the same write. Before sending, the Watcher does a transaction-create on
`/NotificationsMeta/{tid}/{mid}/{dedupeKey}` (e.g. `kickoff`, `fulltime`, `goal_t1_3`) = server timestamp.
If the key already exists, it skips the send. This path is metadata-only and invisible to both apps.

**Re-arm on undo:** when a score *decreases*, the Watcher deletes that team's goal dedupe keys above the new
score. So undo (3 → 2) then re-recording the corrected goal (2 → 3) alerts again, as §6.1 promises, while
true double-fires (same write, seconds apart) stay blocked.

### Message payload

- `notification`: title + body (OS displays in background/killed states).
- `data`: `{ "type": "goal|kickoff|fulltime", "tournamentId": tid, "matchId": mid }` — used by tap-to-open.

---

## 5. Fan app changes

### New units

| File | Purpose |
|---|---|
| `lib/misc/notification_topics.dart` | **Pure**: topic name builders + id sanitizer (mirrors the Watcher's sanitizer; unit-tested) |
| `lib/misc/follow_store.dart` | SharedPreferences-backed list of follows `{topic, label, kind}` + master switch flag; wraps `FirebaseMessaging.subscribeToTopic` / `unsubscribeFromTopic`; master-off = unsubscribe all but **keep the stored list**, master-on = resubscribe all |
| `lib/widgets/follow_bell.dart` | Reusable AppBar bell: outline=off / filled=on, optimistic toggle, confirmation SnackBar, OS-permission check with a friendly dialog explaining how to enable notifications in phone Settings (no new dependency; plain instructions) |

### Wiring

- `lib/tournamentdetail.dart` — bell as AppBar action (topic `tournament_{tid}`, label = tournament name).
- `lib/tournamentteamdetail.dart` — bell as AppBar action (topic `tournament_{tid}_team_{teamId}`, label = team name).
- `lib/settings.dart` — new **"Notifications"** sticky section **above "League Table Info"**: master switch + one toggle row per stored follow. Hidden states handled (empty list → hint text "Turn on bells from any tournament or team page").
- **Tap-to-open:** implement `PushNotifications.onNotificationTap` + `FirebaseMessaging.onMessageOpenedApp` + `getInitialMessage()` (cold start). Payload `{tournamentId, matchId}` → navigate to the match detail page (`tournament_match_detail.dart`). Foreground display already works via the existing `onMessage` → local-notification path; its payload already carries `message.data` as JSON.

### Permission flow

First bell tap calls the existing permission request; if the OS reports denied, the bell stays off and the friendly dialog points to phone Settings (edge case §6.4).

---

## 6. Edge cases (all approved)

1. **Mistaken goal then undo:** alert already sent cannot be retracted; the score decrease sends nothing; a re-recorded correct goal sends one new alert.
2. **Edits to finished matches** (recompute, stat moves): silence — goal alerts require live status; full-time fires only on the transition to 2 (dedupe key blocks repeats).
3. **Double-fire:** `NotificationsMeta` transaction guard (§4).
4. **OS-level notifications blocked:** bell shows dialog linking to phone settings.
5. **Offline scorekeeper:** Firebase syncs the write later; alert fires on sync (late but correct).
6. **Watcher outage / failed deploy:** alerts stop silently; both apps function normally (notifications are a pure add-on layer).
7. **Reinstalled app:** follows reset to off (topic subscriptions and local list are both per-install) — fan re-taps bells, matching FotMob behavior.

---

## 7. Testing

1. **Unit (TDD):**
   - `functions/test/decide.test.ts` — every §4 rule: increase/decrease/no-change, status transitions incl. reopen, dedupe keys, exact alert wording, sanitizer.
   - Fan app: `test/notification_topics_test.dart` (topic names/sanitizer parity cases), `test/follow_store_test.dart` (list CRUD + master-switch semantics with mocked messaging+prefs).
2. **Emulator dress rehearsal:** Firebase Local Emulator Suite (database + functions). Scripted match simulation (pending → live → goals up/down → finished) asserts exactly which sends would fire, before any deploy.
3. **Live sign-off:** deploy; owner follows *Test Tournament 2026* on a real phone; kickoff/full-time buzz in 1–3 s, goals in ~10–15 s (grace window) with scorer + assist shown. Safe in production: zero fans are subscribed to any topic until they tap a bell, and bells ship in this same release.

---

## 8. One-time setup checklist (guided, ~15–20 min)

1. Verify **Blaze plan** on `infinite-sports-app` in Firebase Console (owner believes active).
2. Verify **APNs key** uploaded in Firebase Console → Project Settings → Cloud Messaging (iPhone delivery; Android needs nothing). If absent: one-time upload from the Apple Developer account.
3. `firebase deploy --only functions` from the fan-app repo (owner with guidance, or Paul/Bronsin). Code reaches GitHub through the normal PR review first.

---

## 9. Future work (parked, in planned schedule)

- **League seasons** (futsal/indoor soccer, basketball, flag football): same bells + topics (`season_*` naming reserved). Each sport needs its own "moments" design — basketball cannot alert per basket. (Owner-requested, task #95.)
- Red-card alerts (one switch away in `decide.ts` if wanted).
- Match reminders ("starts in 15 min") — needs scheduled functions.
- Announcements feed + prediction nudges plug into this same Watcher/sender.

## 10. Review checklist for Paul & Bronsin

- New `functions/` directory = first Cloud Functions code in the project (TypeScript, Functions v2, Node 20).
- New DB path: `/NotificationsMeta/**` (metadata only; consider security rules: clients need no access).
- Fan app gains no new heavyweight dependencies (uses existing `firebase_messaging`, `flutter_local_notifications`, `shared_preferences`).
- Manager app: no changes.
