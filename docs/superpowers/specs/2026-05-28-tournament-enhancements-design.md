# Tournament Enhancements — Design Spec

**Date:** 2026-05-28
**Branch (user app):** `zaya/tournament-enhance-app-manager` on `infinite_sports_flutter`
**Branch (admin app):** `zaya-tournament-enhance-app-manager` on `InfiniteSportsManagerFlutter`
**Target launch:** September 4–7, 2026 (Assyrian National Convention Tournament)
**Owner:** Zayaa (product) + Claude (implementation)

---

## 1. Background

Infinite Sports is two Flutter apps sharing one Firebase backend (`infinite-sports-app`):

- **`infinite_sports_flutter`** (user app) — public app for the Assyrian community sports league. Live scores, historical seasons, Google Map of businesses/events, accounts, league sign-ups. ~Flutter + Provider + nested-navigator tabs.
- **`InfiniteSportsManagerFlutter`** (admin/manager app) — fresh Flutter rewrite of a previous Kotlin admin app. Manages futsal/basketball/flag football seasons, games, lineups, sign-ups, users, events, notifications. ~Flutter + Riverpod + go_router.

The user app is mid-development of a Tournament feature on the `zaya/features` branch — full models, service layer, 9 tab files, and a Tournaments bottom-nav tab are wired in. A read-only code review identified ~26 issues across crashes, performance, and code quality.

The admin app has **zero tournament support** today. Tournament data can only be created by hand-editing Firebase JSON in the console, which is both error-prone and the root cause of several of the bugs in the user app (parsing errors on string-vs-bool fields, for example).

This spec defines the work needed to:

1. Fix the existing tournament feature's bugs and performance issues
2. Build admin-app tournament management
3. Add user-facing features that make the September tournament magical for the community
4. Set up future-phase commitments so we don't lose them

---

## 2. Goals and non-goals

### Goals

- A reliable, fast, beautiful tournament experience for the Sept 4–7 outdoor soccer event
- Admin tooling so Zayaa (and a small trusted team) can run the tournament from a phone or laptop
- Per-field QR-based scoring so designated referees can update their own matches without admin credentials
- Push notifications so the 50% of the audience watching remotely feels present
- A flagship Predictions / Fantasy layer that drives community engagement and bragging rights
- A foundation that makes future monetization (paid predictions, league fantasy) and other tournaments easy to plug in

### Non-goals (deferred to later phases)

- In-app paid sign-up or paid predictions (Phase 1.5 / Phase 4)
- Real-money prizes / regulated fantasy contests (Phase 4)
- Live match chat with moderation (Phase 3)
- Live stream embedding (Phase 3)
- Historical archive + cross-tournament career stats (Phase 3)
- Photo / video gallery (Phase 2)
- MVP / Goal-of-the-Tournament voting (Phase 2)
- Player check-in / attendance (Phase 2)
- Season-long league fantasy with power cards (Phase 4)

---

## 3. Scope summary

### Phase 1 — Committed by Sept 4, 2026

| # | Feature | Effort (days) |
|---|---|---:|
| 1 | Critical bug fixes (crashes, infinite spinner) | 5 |
| 2 | Performance cleanup (N+1 reads, lazy loading, image cache) | 5 |
| 3 | Admin app tournament CRUD (11 management screens) | 15 |
| 4 | Live bracket + scores (Firebase listeners) | 5 |
| 5 | Push notifications (FCM + Cloud Functions) | 7 |
| 6 | QR per-field scoring (referees can record goals, cards, end match) | 11 |
| 7 | One-tap share match card to WhatsApp | 4 |
| 8 | Tournament announcements feed | 4 |
| 9 | "My Tournament" view (your team, next match, schedule) | 6 |
| 10 | 🌟 Tournament predictions (flagship) | 14 |
| 11 | Tournament sign-up MVP (form adapt, team codes, manual Venmo) | 6 |
| 12 | Testing + polish + fake tournament setup + dress rehearsal | 8 |
|   | **Total** | **~90** |

Available working days: ~70 (14 weeks calendar × ~5 working days). **We are ~20 days over.** This is why the drop list below matters.

### Pre-agreed drop list (cut in order if slipping)

1. Live stream embedding (already Phase 3)
2. Live match chat (already Phase 3)
3. Historical archive (already Phase 3)
4. Photo gallery (Phase 2)
5. MVP / Goal-of-the-Tournament voting (Phase 2)
6. Player check-in (Phase 2)
7. Bracket predictions polish (Phase 2)

**Phase 1 items are non-negotiable.** Only stretch/Phase 2/3 items get cut.

### Phase 2 stretch (Sept–Dec 2026)

- Photo & video gallery per match
- MVP / Goal-of-the-Tournament voting
- Player check-in / attendance
- Achievement badges on profile (Bracket Buster, Champion Caller, Perfect Group Stage)
- Shareable "I called it" prediction result cards
- Hall of Fame (top 3 predictors permanently displayed)
- Sound effects with mute toggle
- Deeper player stats screens

### Phase 1.5 (Sept–Dec 2026, parallel with Phase 2)

- Full Stripe payment integration (cards + Apple Pay + Google Pay)
- Sign-up form builder (admin designs custom fields per tournament)
- Dropdown team selection (with team coaches pre-registering teams)
- Cloud Function for payment webhook handling
- Automated paid status updates from Stripe events
- Refund flow

### Phase 3 stretch (Jan–Apr 2027)

- Historical archive + cross-tournament career stats
- Live match chat with moderation tooling
- Live stream embedding (YouTube / Twitch)
- "Hall of Fame" cross-tournament

### Phase 4+ committed backlog

- Premium predictions tier (paid, after legal review of fantasy/gambling rules)
- Season-long league predictions for futsal, basketball, flag football
- Power cards (triple captain, etc.) for league fantasy
- Full fantasy team league play (draft, weekly scoring, season standings)
- Persistent cross-tournament fantasy leaderboards

---

## 4. Architecture and Firebase data model

### Principle: additive only

All new features add new Firebase paths. We do not rename, restructure, or delete any existing paths. Existing tournament data (the `zaya/features` work-in-progress) and all league seasons stay untouched.

### Existing Firebase paths (unchanged)

```
/Current League
/Futsal/{Season}/...
/Basketball/{Season}/...
/Flag Football/{Season}/...
/AFC San Jose/Seasons/{Season}/...
/Sign Ups/{league}/{season}/{NotPaid|Paid|Comments}
/Users/{uid}/{First Name|Last Name|Phone Number|Date Joined|ProfileUrl|Token|Information|Played}
/Map
/Events
/Notifications
/Logo Urls
/Tournaments/{id}/{Teams|Matches|Rosters|Table}/...   ← existing tournament work
/Tournaments/Current Tournament
```

### New Firebase paths (Phase 1)

#### Predictions

```
/Tournaments/{id}/PredictionConfig/
   Open                bool        — predictions open for entry
   AwardsLockTime      ISO datetime — when award categories lock
   Scoring/                          — admin-configurable point values
      Champion         int (default 10)
      RunnerUp         int (default 5)
      ThirdPlace       int (default 3)
      GoldenBoot       int (default 8)
      MostAssists      int (default 8)
      MostCleanSheets  int (default 6)
      BestDefender     int (default 6)
      MatchWinner      int (default 1)
      ExactScoreBonus  int (default 3)
      ...              (other sport-specific categories)
   Categories/                       — which categories are active for this tournament
      Champion         bool
      RunnerUp         bool
      ...
   Prizes/                           — optional free-text prize per category (UI hook for paid tier)
      Champion         string?      — e.g. "Apple Watch"
      GoldenBoot       string?
      ...

/Tournaments/{id}/Predictions/{uid}/
   DisplayName         string       — cached from /Users
   Awards/
      Champion         teamId
      RunnerUp         teamId
      ThirdPlace       teamId
      GoldenBoot       "teamId:PlayerName"
      MostAssists      "teamId:PlayerName"
      ...
   Matches/{matchId}/
      Team1Score       int
      Team2Score       int
      WinnerTeamId     teamId       — computed but stored for speed
      SubmittedAt      ISO datetime

/Tournaments/{id}/PredictionLeaderboard/{uid}/
   DisplayName         string
   TotalPoints         int          — computed by Cloud Function
   Correct/                          — null until resolved
      Champion         bool?
      RunnerUp         bool?
      ...
   Streak              int          — consecutive correct match predictions
   Updated             ISO datetime
```

#### Announcements

```
/Tournaments/{id}/Announcements/{announcementId}/
   Title               string
   Body                string
   PostedAt            ISO datetime
   PostedBy            uid
   PushSent            bool
```

#### Push subscriptions

```
/PushSubscriptions/{uid}/
   Tournaments/{tournamentId}                bool  — following this tournament
   Teams/{tournamentId}/{teamId}             bool  — following this team in this tournament
   PrimaryTeam/{tournamentId}                teamId — auto-detected from roster or manually picked
   Settings/
      MatchStart                             bool
      Goal                                   bool
      Final                                  bool
      Announcement                           bool
      PredictionResult                       bool
```

#### QR scoring tokens

```
/MatchScoringTokens/{token}/
   TournamentId        string
   MatchId             string
   ExpiresAt           ISO datetime
   CreatedBy           uid (admin)
   UsedBy              uid?         — referee who scanned, null until used
   RevokedAt           ISO datetime? — optional revoke
```

#### Tournament sign-up (MVP, Phase 1)

```
/Tournaments/{id}/SignUps/
   Config/
      Open             bool          — sign-up form accepting submissions
      PaymentEnabled   bool          — sign-up requires payment
      PaymentAmount    number        — amount in USD
      PaymentMethod    string        — "Venmo" | "Zelle" | "Stripe" (Phase 1.5)
      PaymentHandle    string        — "@InfiniteSports" or Zelle email
      DueDate          ISO date
      RulesUrl         string?       — optional rules PDF
      WaiverUrl        string?       — optional waiver PDF
   Teams/{teamId}/
      Code             string        — short code (e.g. "BLUE-2026") for player join
      Name             string        — team display name
   NotPaid/{uid}                     — same pattern as existing /Sign Ups
      DisplayName      string
      TeamId           teamId        — assigned via code
      SubmittedAt      ISO datetime
   Paid/{uid}                        — same fields, after admin confirms
   Comments/{displayName}            — optional comment field
```

### Cloud Functions (NEW dependency)

Cloud Functions sits next to the Firebase project. New directory `functions/` in the user-app repo, written in TypeScript.

| Function | Trigger | Action |
|---|---|---|
| `onMatchScoreChange` | Write to `/Tournaments/{id}/Matches/{matchId}/{team1score\|team2score}` | Send FCM push to followers of either team |
| `onAnnouncementPost` | Write to `/Tournaments/{id}/Announcements/{id}` | Send FCM push to tournament followers |
| `onMatchComplete` | Write to `/Tournaments/{id}/Matches/{matchId}/status` = 2 | Resolve match-winner predictions, update leaderboard, send FCM to users who got it right |
| `onTournamentComplete` | Write to `/Tournaments/{id}/finished` = true | Resolve all award predictions, finalize leaderboard, send FCM to award winners |
| `generateScoringToken` | Callable HTTPS | Admin app calls this to create a one-use QR scoring token |

Free tier covers our scale (estimated <15,000 invocations per tournament).

### Sport-aware prediction categories

Each sport defines which prediction categories make sense. The admin's tournament creation screen filters categories based on selected sport.

| Category | Soccer/Futsal | Basketball | Flag Football | Volleyball |
|---|:-:|:-:|:-:|:-:|
| Champion | ✅ | ✅ | ✅ | ✅ |
| Runner-up | ✅ | ✅ | ✅ | ✅ |
| Third place | ✅ | ✅ | ✅ | ✅ |
| Match winner | ✅ | ✅ | ✅ | ✅ |
| Exact score bonus | ✅ | ✅ | ✅ | ✅ |
| Golden Boot | ✅ | — | — | — |
| Most assists | ✅ | ✅ | — | — |
| Most clean sheets | ✅ | — | — | — |
| Best defender | ✅ | ✅ | ✅ | — |
| Most points | — | ✅ | — | — |
| Most rebounds | — | ✅ | — | — |
| Most 3-pointers | — | ✅ | — | — |
| Most touchdowns | — | — | ✅ | — |
| Most yards | — | — | ✅ | — |
| Most interceptions | — | — | ✅ | — |
| Most kills | — | — | — | ✅ |
| Most digs | — | — | — | ✅ |
| Best server | — | — | — | ✅ |

For September 2026: only the Soccer/Futsal column is active. The remaining columns are wired in for future tournaments.

---

## 5. New code modules

### User app (`infinite_sports_flutter`)

| New file | Purpose |
|---|---|
| `lib/misc/parse_helpers.dart` | Safe Firebase parsing (`parseBool`, `parseInt`, `parseStr`, `parseMap`) |
| `lib/misc/prediction_service.dart` | Submit/get predictions, fetch leaderboard |
| `lib/misc/push_subscription_service.dart` | Follow/unfollow team or tournament |
| `lib/misc/share_card_service.dart` | Generate WhatsApp-shareable match card image |
| `lib/widgets/team_logo.dart` | Unified logo widget (replaces 12+ duplicates) |
| `lib/widgets/match_score_row.dart` | Unified two-team score row (replaces 4 duplicates) |
| `lib/widgets/match_status_badge.dart` | LIVE / FINAL / VS badge |
| `lib/tournament_tabs/predictions_tab.dart` | Make/view predictions inside tournament |
| `lib/tournament_predictions_leaderboard.dart` | Full leaderboard screen with celebration |
| `lib/tournament_announcements.dart` | Announcements feed |
| `lib/my_tournament.dart` | "My Tournament" personalized view |
| `lib/match_scoring_qr.dart` | QR-link entry to per-field scoring (no login) |
| `lib/tournament_signup.dart` | Tournament-specific sign-up flow |

Plus refactors to:
- `lib/misc/tournament_service.dart` — parallel reads, narrow queries, photo URL caching
- `lib/model/tournament*.dart` — use `parse_helpers.dart`, MatchStatus enum, TournamentStage enum
- `lib/signup.dart` / `lib/leagueform.dart` — accept optional `tournamentId` parameter
- `lib/main.dart` — wrap Tournaments tab in lazy builder
- Existing tournament screens — adopt `TeamLogo` widget, drop duplicate date formatters, error handling

### Admin app (`InfiniteSportsManagerFlutter`)

| New file | Purpose |
|---|---|
| `lib/models/tournament.dart` | Mirrors user-app `Tournament` |
| `lib/models/tournament_match.dart` | Mirrors user-app `TournamentMatch` |
| `lib/models/tournament_team.dart` | Mirrors user-app `TournamentTeam` |
| `lib/models/tournament_player.dart` | Mirrors user-app `TournamentPlayer` |
| `lib/models/prediction_config.dart` | Scoring weights + active categories |
| `lib/services/firebase/tournament_service.dart` | CRUD for tournaments, teams, matches |
| `lib/services/firebase/qr_token_service.dart` | Generate single-use scoring tokens |
| `lib/services/firebase/prediction_admin_service.dart` | Manage prediction config |
| `lib/services/firebase/announcement_service.dart` | Post tournament announcements |
| `lib/services/firebase/tournament_signup_service.dart` | Admin side of sign-up flow |
| `lib/providers/tournament_provider.dart` | Riverpod providers for tournament data |
| `lib/providers/prediction_config_provider.dart` | Riverpod for prediction config |
| `lib/providers/announcement_provider.dart` | Riverpod for announcements |
| `lib/ui/tournaments/tournament_list_page.dart` | List of tournaments |
| `lib/ui/tournaments/create_tournament_page.dart` | Wizard: name, sport, dates, num teams, format |
| `lib/ui/tournaments/tournament_dashboard.dart` | Overview screen per tournament |
| `lib/ui/tournaments/manage_teams_page.dart` | Add/edit teams in tournament, generate codes |
| `lib/ui/tournaments/manage_bracket_page.dart` | Set bracket structure / fixtures |
| `lib/ui/tournaments/live_scoring_page.dart` | Enter scores live, full match-event UI |
| `lib/ui/tournaments/manage_rosters_page.dart` | Add/edit players per team |
| `lib/ui/tournaments/prediction_config_page.dart` | Toggle categories + set scoring weights + prize text |
| `lib/ui/tournaments/announcements_page.dart` | Post and manage announcements |
| `lib/ui/tournaments/qr_scoring_codes_page.dart` | Print QR codes for referees |
| `lib/ui/tournaments/tournament_signup_admin_page.dart` | View sign-ups, confirm payments |
| `lib/core/constants/firebase_paths.dart` | Updated with new Tournament sub-paths |
| `lib/router/app_router.dart` | New `/tournaments/*` routes |

### Cloud Functions repo (NEW)

| File | Purpose |
|---|---|
| `functions/src/index.ts` | Function entry points |
| `functions/src/notifications/on_match_score_change.ts` | Push to team followers when score changes |
| `functions/src/notifications/on_announcement_post.ts` | Push to tournament followers |
| `functions/src/predictions/on_match_complete.ts` | Resolve match predictions, update leaderboard |
| `functions/src/predictions/on_tournament_complete.ts` | Resolve award predictions, finalize leaderboard |
| `functions/src/qr/generate_scoring_token.ts` | HTTPS callable for token creation |
| `functions/src/lib/fcm.ts` | FCM helper |
| `functions/src/lib/prediction_scoring.ts` | Pure-function scoring math |
| `functions/package.json` | Dependencies |
| `functions/tsconfig.json` | TypeScript config |
| `firebase.json` | Firebase project config (in repo root) |

---

## 6. Feature designs

### 6.1 Critical bug fixes (5 days)

- Safe-parse helpers replacing brittle casts (`as bool?`, `as int`, `as Map`)
- Try/catch + error state UI on `TournamentDetailPage._loadData`
- `MatchStatus` enum replacing `int 0/1/2` magic numbers
- `TournamentStage` enum replacing raw stage name strings
- Remove or guard 8 unused `TournamentMatch` fields that crash on bad data
- Defensive `is Map` checks before all `as Map` casts

### 6.2 Performance cleanup (5 days)

- `Future.wait` for parallel Firebase reads in `getTeams`, `_loadData`
- Player photo URL cache (replace N+1 reads with parallelized + cached lookups)
- `/Tournaments/{id}/Header` summary node for list view
- Lazy `TournamentsNavigation` build (don't instantiate at app launch)
- Denormalized H2H index at `/TournamentH2H/{teamA}_{teamB}/...` and team history at `/TeamHistory/{teamId}/...`
- `cached_network_image` package replaces bare `Image.network` everywhere
- Explicit `cacheWidth`/`cacheHeight` for thumbnail sizes
- Forward already-loaded state to child pages (no duplicate re-fetches)

### 6.3 Admin app tournament CRUD (15 days)

**11 screens**, each focused on one task:

1. **Tournament list** — see all tournaments, status badges, tap to open
2. **Create tournament** wizard — name, sport, dates, num teams, format
3. **Tournament dashboard** — overview, links to all management screens
4. **Manage teams** — add/edit/remove teams, generate join codes
5. **Manage bracket** — set bracket structure, drag-drop seeding
6. **Live scoring** — enter scores during matches, full match-event UI (goals, assists, cards, end match)
7. **Manage rosters** — add/edit players per team
8. **Prediction config** — toggle categories, set scoring weights, set prize text
9. **Announcements** — post announcements, see history
10. **QR scoring codes** — generate and print QR codes for referees
11. **Sign-up admin** — view sign-ups, confirm payments, mark Paid

### 6.4 Live bracket + scores (5 days)

Replace `.get()` one-shot reads with `.onValue` listeners on the critical paths (`/Tournaments/{id}/Matches/*`, `/Tournaments/{id}/Table/*`). Within ~1 second of admin entering a score, every user's bracket and scores screen updates without a refresh.

### 6.5 Push notifications (7 days)

**User side:** "Follow" button on tournament page and each team. Settings screen lets user pick which event types they want notified for (match start, goal, final, announcement, prediction result).

**Cloud Functions side:** 4 triggers as documented above. FCM messages fan out to followers of the relevant teams/tournaments.

**One-time setup:** Initialize Firebase Functions project, configure FCM credentials, deploy.

### 6.6 QR per-field scoring (11 days)

Flow:

1. Admin opens "QR Scoring Codes" screen → selects which matches to generate codes for → admin app calls `generateScoringToken` Cloud Function for each → returns unique tokens → admin app generates printable PDF with QR codes for each match
2. Admin prints the sheet and brings to venue
3. Referee at field scans the QR code → opens deep link `infinitesports://scoring/{token}` or web URL fallback `https://infinitesports.org/scoring/{token}`
4. App opens **focused scoring screen** for just THIS match — team logos, current score, +1 score buttons, goal-scorer picker, assist picker, yellow card per player, red card per player, end-match button
5. Referee enters events as they happen — each tap writes immediately to Firebase
6. End match → token is marked used → admin gets push: "Match X finalized by referee Y"
7. Admin can still override anything via Live Scoring screen

Token scope: ONE match only. Expires after tournament. Revocable.

### 6.7 One-tap share match card (4 days)

After every finished match, user taps Share → on-device image rendering generates a branded PNG (team logos, final score, date, tournament branding) → system share sheet opens → user picks WhatsApp / Instagram / etc.

**Implementation:** `screenshot` or `widgets_to_image` package + `share_plus` (already in pubspec).

**No Firebase storage** — images are generated fresh on every share, never persisted.

### 6.8 Tournament announcements feed (4 days)

Admin posts a title + body. User app shows a new "Announcements" tab in tournament detail, plus a banner if unread announcements exist. Cloud Function fans out push to tournament followers.

### 6.9 My Tournament view (6 days)

A personalized card visible on the Tournaments tab once a tournament is active. Shows:

- **YOUR team** (logo + current standing)
- **YOUR next match** (with live countdown timer)
- **YOUR full schedule** (chronological list of your team's matches)

Auto-detects "your team" from `/Users/{uid}/Played/{tournamentId}` if you're on a roster. Falls back to manual "I'm following TeamX" pick if auto-detect fails.

### 6.10 Tournament predictions — flagship (14 days)

**Three user flows:**

1. **Awards picks** (locks at tournament start): Open Predictions tab → see active award categories → pick a team or player for each → submit → confirmation + countdown to lock

2. **Match picks** (locks at each match kickoff): Below awards, list of upcoming matches → tap a match → pick winner OR enter exact score → submit → match shows your pick with a lock countdown

3. **Leaderboard** (live updating): Separate "Leaderboard" tab → ranked list with user's position highlighted → tap a name to see their picks (only finished items visible — live items stay private until they lock)

**Resolution + celebration:**

When a match completes (admin marks status=2 in Live Scoring, OR token-scoped referee taps End Match):
- Cloud Function resolves all match predictions for that match
- Leaderboard updates points and streaks
- Push sent to users who got the prediction right
- Next time they open the app:
  - **Confetti** rains over the affected card
  - **Animated reveal sequence** ("YOUR PICK → WINNER → +N PTS")
  - **Rank-change animation** ("You moved from #14 → #6!")
  - **Streak indicator** if applicable ("🔥 3 in a row!")
  - **Haptic feedback** on result reveal

Scoring weights default per category but are **fully admin-configurable per tournament** via the admin app's Prediction Config screen. Prize text per category (free-text string for now) is a forward-compat UI hook for Phase 4 paid tier.

### 6.11 Tournament sign-up MVP (6 days)

Adapt the existing `lib/signup.dart` + `lib/leagueform.dart` flow:

- Add `tournamentId` parameter so the form knows it's for a tournament
- Add team-code input field — admin generates code in Manage Teams screen, captain shares with players, player enters code → auto-assigned to team
- Add payment instructions section (visible only when admin enabled paid mode)
- Manual payment for September: app displays "Pay $X via Venmo @InfiniteSports" → user pays manually → admin moves them from NotPaid → Paid in the admin app
- Paid/free toggle per tournament

### 6.12 Testing + polish + dress rehearsal (8 days)

- Set up fake Test Tournament 2026 in Firebase JSON
- Continuous testing every chunk
- Final QA on real iOS + Android devices
- Tournament-day dress rehearsal (Week 14) — run the fake tournament end-to-end

---

## 7. Cross-app coordination

### Build order — parallel, foundation-first

| Week | User app | Admin app | Firebase | Cloud Functions |
|---|---|---|---|---|
| 1 | Bug fixes + perf | Tournament CRUD basics | Fake Test Tournament imported | — |
| 2–3 | Live listeners | Live scoring + rosters | Schema for predictions/announcements/push | onMatchScoreChange + onAnnouncementPost deployed |
| 4–5 | Prediction submission UI | Prediction config + announcements | — | onMatchComplete |
| 6–7 | Leaderboard + confetti | QR codes generator | — | onTournamentComplete + generateScoringToken |
| 8–9 | QR receiver + share cards + announcements feed + sign-up | Sign-up admin | — | — |
| 10–11 | My Tournament + push settings | Push notification settings | — | — |
| 12–13 | Phase 2 stretch | Phase 2 stretch | — | — |
| 14 | Final QA + rehearsal | Final QA | — | — |

### Schema as contract

The Firebase paths in Section 4 are the source of truth. Both apps reference this design doc. When a schema field changes, both apps update in the same work session — never a single side.

### Model code lives twice

Tournament/TournamentMatch/TournamentTeam/TournamentPlayer models exist in both repos. Sharing across repos via git submodules or a published package is more complexity than it's worth for a solo developer. The drift risk is low because the same developer (Claude) updates both. The design doc remains the canonical field list.

### Cloud Functions setup

One-time: `firebase login` via terminal (already done as of 2026-05-28). Then `functions/` directory in user-app repo with TypeScript. Deploy via `firebase deploy --only functions` from project root.

Free tier covers our scale (~15,000 invocations per tournament; free tier allows 2,000,000).

---

## 8. Decision conventions

**Medium autonomy:** Claude picks small UI defaults (colors, spacing, button positions, default sort orders). Claude stops and asks at flow/UX decisions (which-screen-shows-what, opt-in vs always-on behaviors, what happens in edge cases). Claude always pauses at end-of-week chunks for verification.

### Communication patterns Claude uses

- **"Pull from main app and run"** = something for Zayaa to test
- **"Heads up: data shape changed"** = need to re-import Test Tournament JSON
- **"Cloud function deploy needed"** = Claude does it, Zayaa confirms
- **"Decision time"** = fork in the road, Claude pauses
- **"Phase 1 step N complete"** = checkpoint — confirm before proceeding

---

## 9. Testing approach

### Fake Test Tournament — workhorse

Week 1: Zayaa exports Firebase JSON from Firebase Console. Claude adds a `test-tournament-2026` node with:
- 8 fake teams (Team Alpha, Team Bravo, …) with placeholder logos
- Group stage + knockout fixtures spanning the same dates as the real tournament
- 10 fake players per team with sensible position distribution
- Prediction config pre-set with default scoring weights, Soccer/Futsal categories active
- Empty announcements feed
- Sign-up config open, paid mode off

Zayaa re-imports. From that point on, every feature is built and tested against this fake tournament before touching real tournament data.

### Verification cadence

For every feature, before "done":

1. Code compiles, lints clean
2. Claude describes the exact tap-by-tap test flow
3. Zayaa pulls the branch, runs on phone, tests against Test Tournament
4. Zayaa reports back in chat
5. Claude fixes anything broken before moving on

**No "trust me it works."** Every feature gets verified by Zayaa on a real device.

### Tournament-day dress rehearsal (Week 14)

End of Phase 1, full end-to-end run of the fake tournament in compressed time:
- Zayaa logs in as a real user
- Claude "plays admin" via manager app
- Run scoring, announcements, predictions, share cards, the full flow
- Anything that feels off gets fixed before September 4

### Out of scope for Phase 1 testing

- Load testing (we're at ~150 players, no risk)
- Multi-region testing (audience is mostly US)
- Cross-version testing beyond latest Flutter stable + iOS 14+ / Android API 21+
- A/B testing (not enough users)

---

## 10. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Phase 1 scope is ~20 days over available time | High | High | Pre-agreed drop list. Stretch items cut before committed items. |
| Firebase schema drift between apps | Medium | High | Single design doc is source of truth. Schema changes coordinated in same work session. |
| Cloud Functions auth or deploy issues | Low | Medium | Already verified `firebase login` works. Deploy procedure documented. |
| Push notifications missed on iOS due to APNS misconfiguration | Medium | Medium | Test on real iOS device early in Week 2. Backup: in-app notifications even if push fails. |
| Internet at venue unreliable | Medium | High | Cache-first reads on mobile. Offline-friendly score entry (sync on reconnect) considered if Phase 2 reveals real issue. |
| Predictions feature has bugs that affect leaderboard correctness | Medium | High | Pure-function scoring math in `prediction_scoring.ts` is unit-testable. Cloud Function calls this on every resolve. Add audit logging so we can replay if needed. |
| Manual Venmo confirmations missed during sign-up window | Low | Low | Existing league sign-up flow already uses this pattern. ~5 sec per confirmation. |
| Referee tokens get shared or abused | Low | Low | Tokens scoped to ONE match, expire after tournament, revocable. Admin override always available. |

---

## 11. Open questions

None at time of writing. All design decisions resolved during brainstorming.

---

## 12. Future phases — committed backlog

(Recorded so we don't lose them.)

### Phase 1.5 (Sept–Dec 2026)
- Full Stripe payment integration (cards + Apple Pay + Google Pay + webhooks)
- Sign-up form builder (admin designs custom fields per tournament)
- Dropdown team selection with team coaches pre-registering teams
- Refund flow

### Phase 2 (Sept–Dec 2026, parallel with Phase 1.5)
- Photo & video gallery per match
- MVP / Goal-of-the-Tournament voting
- Player check-in / attendance
- Achievement badges on profile
- Shareable "I called it" prediction result cards
- Hall of Fame top 3 predictors
- Sound effects with mute toggle
- Deeper player stats screens

### Phase 3 (Jan–Apr 2027)
- Historical archive + cross-tournament career stats
- Live match chat with moderation
- Live stream embedding (YouTube / Twitch)
- Cross-tournament Hall of Fame

### Phase 4+ (TBD)
- Premium predictions tier (paid, post-legal review)
- Season-long league predictions for futsal, basketball, flag football
- Power cards (triple captain, etc.) for league fantasy
- Full fantasy team league play (draft, weekly scoring, season standings)
- Persistent cross-tournament fantasy leaderboards

---

## Appendix A — Critical bugs from the read-only code review (May 28, 2026)

Reference list for Phase 1.1 work. Numbered to track in implementation plan.

1. `lib/model/tournament.dart:50` — `data['Finished'] as bool?` crashes on string/int
2. `lib/model/tournamentmatch.dart:87-88` — same crash on DirectBye fields
3. `lib/tournamentdetail.dart:60-82` — infinite spinner on Firebase error
4. `lib/tournamentplayerprofile.dart:38` — `as Map` crash on malformed data
5. All `fromFirebase` factories — brittle casts
6. `lib/misc/tournament_service.dart:157-166` — N+1 ProfileUrl fetches
7. `lib/misc/tournament_service.dart:9-35` — full-tree read for tournament list
8. `lib/main.dart:157` — Tournaments tab eager build
9. `lib/misc/tournament_service.dart:193-229, 238-327` — H2H and team history scan all tournaments
10. `lib/tournamentteamdetail.dart:48-50` — duplicate re-fetch from parent
11. `lib/misc/tournament_service.dart:68-69` — sequential Teams + Table queries
12. All `Image.network(...)` — no disk cache
13. 3 duplicate `_formatDate` functions (use `utility.dart:58-63`)
14. 12+ duplicate Image.network + Icons.shield patterns (→ `TeamLogo` widget)
15. 5 duplicate `getValue(player, stat)` switches (→ method on `TournamentPlayer`)
16. Status `int 0/1/2` as magic numbers (→ enum)
17. Stage names as raw strings (→ enum)
18. Hardcoded navy `Color(0xFF1A237E)` in 10+ places
19. `tournamentplayerprofile.dart` duplicates `/Users/{uid}/Played` fetch
20. 8 unused fields on TournamentMatch (votes, byes, bracket refs)

(Full review report archived in conversation history of brainstorming session 2026-05-28.)
