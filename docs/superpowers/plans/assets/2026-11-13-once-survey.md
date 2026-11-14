# One-shot read (`once()`) survey: Infinite Sports FAN app, `lib/` only

Snapshot taken 2026-11-13 (read-only; another agent was editing the repo, so line numbers are as of this read).

## 0. Ground rules used for the "live stream?" column

Paths a typical fan has under a PERMANENT live `onValue` (mounted for the whole session):

| Live path | Who holds it | Why permanent |
|---|---|---|
| `/Tournaments` (root) | FrontPage.initState -> `watchAllTournaments` (frontpage.dart:101); CalendarTab -> `watchTournamentDays` (calendar_sources.dart:131) | Matches and Calendar tabs live in the MyHomePage IndexedStack (main.dart:640), which builds every tab at start |
| `EventsV2`, `Events` | CalendarTab -> `watchAllEvents` (event_repo.dart:118/124) | same |
| `Categories` | CalendarTab -> `watchCategories` | same |
| `Futsal/<curSeason>/Date`, `Basketball/<curSeason>/Date`, `Flag Football/<curSeason>/Date` | CalendarTab -> `watchLeagueDays` (calendar_sources.dart:167); `<curSeason>` comes from a one-shot `getCurrentSeason` read once at subscribe time | same |
| `<curSport>/<curSeason>/Date/<curDate>` | LeagueDayView on Matches tab (league_day_view.dart:86) | Matches tab |
| `Fantasy/<curSport>/<curSeason>/Config`, `/<curSport>/<curSeason>/Finished` | FantasyHomeBanner (frontpage.dart:324) via FantasyScheduleFeed / FantasySeasonFinishedFeed | only while the banner is shown (`isCurrentFinished` read false) |
| `Logo Urls`, `AFC San Jose/Logo URL` | TeamLogoFeed (team_logos.dart:115-116), started in main.dart:559 | app lifetime |
| `Insiders/<myUid>` | MyHomePage `_insiderStream` (main.dart:409) | always |
| `Users/<myUid>/MergedInto`, `/MergedHint` | MergedAccountWatcher (main.dart:151; merged_account_notice.dart:179-180) | always when signed in; CHILD paths only, they do NOT refresh the rest of `Users/<uid>` |

NOT live anywhere: `Current League`, `<Sport> Season`, `AFC San Jose/Current Season`, any other part of `Users/<uid>`, `PublicProfiles/*`, `/<sport>/<season>/Teams` and `/Line Ups` (only while a league detail/match/team page for that season is open), all `AFC San Jose/Seasons/*`, `Sign Ups/*`, `Registrations/<regId>/*` (Submissions/<uid> and Teams/<tid> only while the status/payment page is open; `RegistrationsPublic` only while RegistrationEntryPage is open), `InsiderCodes`, `ReferredUsers`, `AppConfig/*`.

Caveat for every "covered" row: a once() at cold start that runs in parallel with the stream's first attach (e.g. FrontPage reads vs CalendarTab listeners) can still answer from disk before the stream has synced. "Covered" means fresh on later reads.

This client's own writes update the local cache immediately, so staleness comes from other writers (Manager, Cloud Functions/mirror triggers, other devices).

## 1. Every `.once()` hit (grep = 86 hits: 84 real calls + 2 comment lines)

DEAD = function has no caller in `lib/`.

| # | file:line | function | path read | used for | session memo / early return | same path live elsewhere | category | stale symptom |
|---|---|---|---|---|---|---|---|---|
| 1 | fantasy/data/fantasy_season_resolver.dart:137 | `_configExists` | `Fantasy/<sport>/<season>/Config` (current, then up to 30 earlier) | does the season have fantasy -> which season the profile Fantasy tab uses | found season memoised in `_lastResolved` (:126), early return in FantasyProfileSource.start (fantasy_profile_source.dart:488) all session; "none" memoised 5 min | current season only: FantasyHomeBanner / search hub / league_detail_page `watchConfig` | GATE | Profile Fantasy tab missing or tied to an older season. |
| 2 | fantasy/data/fantasy_season_resolver.dart:149 | `_readPointer` | `Current League`, `<Sport> Season` | resolve current fantasy season | same `_lastResolved` | no stream | GATE | Profile Fantasy tab stuck on last season after a new one starts. |
| 3 | insiders/insiders_info_page.dart:112 | `_loadPlaybookUrl` | `AppConfig/InsidersPlaybookUrl` | playbook link (empty URL = terms allowed without opening) | none | no | STATIC | Old playbook opened. |
| 4 | insiders/insiders_info_page.dart:142 | `_loadPrefill` | `Users/<uid>` (First/Last Name) | read-only name on application, written to `Insiders/<uid>/Name` by apply | none | no | OWN-WRITE | Application filed under old name. |
| 5 | leagues.dart:108 | `getSeasonTiles` | `AFC San Jose/Seasons` (whole subtree) | AFC season list, Leagues tab | none | no | DISPLAY | New AFC season missing. |
| 6 | main.dart:214 | `_handleGoogleSignIn` | `Users/<uid>` (exists?) | new-user decision -> base profile write + About You | none | no | GATE | Only if cached: re-created account skips onboarding, or returning user re-onboarded. |
| 7 | main.dart:304 | `_handleAppleSignIn` | `Users/<uid>` (exists?) | same (dormant on Android) | none | no | GATE | As #6. |
| 8 | main.dart:504 | `_showAboutYouIfIncomplete` | `Users/<uid>` (ProfileCompleted, Phone Number, MergedInto) | mandatory About You gate, askPhone, merged skip, then favorites prompt | none (once per launch) | partial: MergedInto child live; ProfileCompleted not | GATE | Mandatory About You (no skip) shown again after completing elsewhere. |
| 9 | misc/app_config.dart:27 | `getStoreLinks` | `AppConfig/StoreLinks` | store links in event share text | `_cached` (:16), early return, never cleared | no | STATIC | Old store link in shares. |
| 10 | misc/categories.dart:58 | `getCategories` | `Categories` | favorites onboarding + Settings category list | none | YES CalendarTab | DISPLAY | Harmless (cold-start race). |
| 11 | misc/event_repo.dart:91 | `getAllEvents` | `EventsV2` | search-hub event index | none | YES CalendarTab | DISPLAY | Harmless. |
| 12 | misc/event_repo.dart:97 | `getAllEvents` | `Events` | same | none | YES CalendarTab | DISPLAY | Harmless. |
| 13 | misc/event_repo.dart:142 | `getEventV2` (DEAD) | `EventsV2/<id>` | - | none | YES (ancestor) | DISPLAY | n/a |
| 14 | misc/insider_service.dart:35 | `InsiderService.apply` | `Insiders/<uid>` | guard: write only if absent/declined | none | YES watchMyInsider (MyHomePage, info page, NavBar) | OWN-WRITE | Harmless. |
| 15 | misc/insider_service.dart:64 | `lookupCode` | `InsiderCodes/<CODE>` | promo code -> owner uid | none | no | GATE | New code rejected / revoked code accepted. |
| 16 | misc/insider_service.dart:78 | `insiderStatus` | `Insiders/<ownerUid>/Status` | code owner must be active | none | no (only own uid live) | GATE | Suspended Insider code still discounts. |
| 17 | misc/insider_service.dart:92 | `alreadyReferred` | `ReferredUsers/<myUid>` | once-ever referral guard | none | no | GATE | Second referral discount allowed. |
| 18 | misc/insider_service.dart:106 | `getInsiderName` | `Insiders/<ownerUid>/Name` | "Code accepted" message name | none | no | DISPLAY | Old name. |
| 19 | misc/league_service.dart:29 | `LeagueService.getStartHour` | `/<sport>/<season>/Start Time` | derived kick-off hour | `FantasyLeagueGamesFeed._startHourSession` (fantasy_schedule_feed.dart:660, early return :718) for fantasy; none for league pages | no | STATIC | Kick-off times wrong if Start Time edited. |
| 20 | misc/league_service.dart:213 | `_withProfileUrls` (in watchRosters) | `PublicProfiles/<uid>/ProfileUrl` | league roster avatars | `LeagueService._profileUrlCache` (:112) skip-if-cached; `clearProfileUrlCache()` has NO caller | no | DISPLAY | New/changed photos never appear. |
| 21 | misc/notification_prefs.dart:75 | `serverFavorites` | `Users/<uid>/FavoriteSports` | whether favorites prompt shows | none | no | GATE | Prompt shown again. |
| 22 | misc/notification_prefs.dart:104 | `hasAnswered` | `Users/<uid>/FavoriteSportsAnswered` | same | none | no | GATE | Prompt shown again. |
| 23 | misc/public_profiles.dart:133 | `PublicProfiles._readRoot` (getAllOnceOrNull/getAllOnce, bounded) | `PublicProfiles` (whole) | search players, event attendees, fantasy leaderboard names | `FantasyLeaderboardsTab.profilesSession` (leaderboards_tab.dart:219/355), cleared on empty + sign-out; none for search/event | no | DISPLAY | New players missing from search; old names/photos. |
| 24 | misc/public_profiles.dart:159 | `getProfileUrlOnce` (DEAD) | `PublicProfiles/<uid>/ProfileUrl` | - | none | no | DISPLAY | n/a |
| 25 | misc/tournament_service.dart:63 | `getAllTournaments` (+getActiveTournaments) | `/Tournaments` | home active tournament tabs, search index | none | YES FrontPage + CalendarTab | DISPLAY | Cold-start race only. |
| 26 | misc/tournament_service.dart:97 | `getCurrentTournamentId` (DEAD) | `/Tournaments/Current Tournament` | - | none | YES | DISPLAY | n/a |
| 27 | misc/tournament_service.dart:118 | `getTournamentHeader` (DEAD) | `/Tournaments/<id>` | - | none | YES | DISPLAY | n/a |
| 28 | misc/tournament_service.dart:195 | `getTournamentBundle` | `/Tournaments/<id>` | home tournament tab teams/rosters (matches streamed separately), deep link, profile appearances, tournament match detail | profile: inside `_careerCache` | YES ancestor | DISPLAY | Cold-start race; home tab teams/rosters re-read only when active set changes. |
| 29 | misc/tournament_service.dart:249 | `getTeams` | `/Tournaments/<id>/Teams` | tournament team detail | none | YES | DISPLAY | Harmless. |
| 30 | misc/tournament_service.dart:250 | `getTeams` | `/Tournaments/<id>/Table` | same | none | YES | DISPLAY | Harmless. |
| 31 | misc/tournament_service.dart:284 | `getMatches` (DEAD) | `/Tournaments/<id>/Matches` | - | none | YES | DISPLAY | n/a |
| 32 | misc/tournament_service.dart:353 | `getRostersNode` (via getRosters) | `/Tournaments/<id>/Rosters` | team detail roster | none | YES | DISPLAY | Harmless. |
| 33 | misc/tournament_service.dart:416 | `enrichRosterPhotos` | `PublicProfiles/<uid>/ProfileUrl` | tournament roster avatars | `TournamentService._profileUrlCache` (:27); `clearProfileUrlCache()` has NO caller | no | DISPLAY | New/changed photos never appear. |
| 34 | misc/tournament_service.dart:483 | `getH2HMatches` (DEAD) | `/Tournaments` | - | none | YES | DISPLAY | n/a |
| 35 | misc/tournament_service.dart:529 | `getPredictionConfig` (DEAD) | `/Tournaments/<id>/PredictionConfig` | - | none | YES | DISPLAY | n/a |
| 36 | misc/tournament_service.dart:670 | `getTeamTournamentHistory` | `/Tournaments` | team history | none | YES | DISPLAY | Harmless. |
| 37 | misc/utility.dart:192 | `getCurrentSport` | `Current League` | which league the Matches tab, top-bar table/leaderboard (`headerNotifier`) and search fantasy card use | kept in FrontPage fields and `headerNotifier` for the session | **no stream anywhere** | DISPLAY (high impact) | Home stays on the old league after the admin switches league. |
| 38 | misc/utility.dart:205 | `getCurrentSeason` | `<Sport> Season` | current season: Matches tab, top bar, Leagues tab max season, CalendarTab subscribe season, profile active flag, search fantasy card | FrontPage fields / `headerNotifier` / CalendarTab subscription for the session | **no stream anywhere** | DISPLAY (high impact) | New season invisible: home, top bar and calendar show last season; Leagues tab has no tile for it. |
| 39 | misc/utility.dart:218 | `isSeasonFinished` | `/<sport>/<season>/Finished` | Matches tab: hide league section + fantasy banner; profile active flag | FrontPage field | partial: FantasySeasonFinishedFeed streams it, but only after the banner mounts (i.e. only if this read said not finished) | DISPLAY | League section stuck hidden ("No Upcoming Games") or shown after season end. |
| 40 | misc/utility.dart:231 | `getAFCCurrentSeason` | `AFC San Jose/Current Season` | home AFC section, profile | FrontPage field | no | DISPLAY | Home AFC section on old season. |
| 41 | misc/utility.dart:245 | `isAFCSeasonFinished` | `AFC San Jose/Seasons/<s>/Finished` | home AFC section visibility, profile | FrontPage field | no | DISPLAY | AFC section hidden/shown wrongly. |
| 42 | misc/utility.dart:261 | `getDates` (via getCurrentDate, ShowLeaguePage.buildLeague) | `/<sport>/<season>/Date` or `AFC San Jose/Seasons/<s>/Date` | which match day the Matches tab opens on; AFC season date tabs | FrontPage field | current league season: YES CalendarTab; AFC: no | DISPLAY | Home opens on the wrong match day; new AFC dates missing. |
| 43 | misc/utility.dart:297 | `getMinSeason` | `/<sport>/Init Season` | first season tile, Leagues tab | none | no | STATIC | Harmless. |
| 44 | misc/utility.dart:309 | `getSoccerSeasons` | `AFC San Jose/Seasons` (whole) | profile AFC stints | `_careerCache` | no | DISPLAY | Profile misses new AFC season. |
| 45 | misc/utility.dart:321 | `getSoccerRoster` | `AFC San Jose/Seasons/<s>/Roster` | AFC leaderboard, AFC game lineups, profile AFC stats | profile: `_careerCache` | no | DISPLAY | AFC stats/roster stale. |
| 46 | misc/utility.dart:343 | `getAllFutsalLineUps` | `/Futsal/<s>/Line Ups` | top-bar leaderboard, profile fallback, legacy game lineups | overwrites global `futsalLineups[season]` each call (no early return) | only while a league detail/match/team page for that season is open (watchRosters) | DISPLAY | Top-bar leaderboard shows old goals/assists. |
| 47 | misc/utility.dart:367 | `getAllFlagFootballLineUps` | `/Flag Football/<s>/Line Ups` | same | global `flagFootballLineups` | same | DISPLAY | Same. |
| 48 | misc/utility.dart:412 | `getAllBasketballLineUps` | `/Basketball/<s>/Line Ups` | same | global `basketballLineups` | same | DISPLAY | Same. |
| 49 | misc/utility.dart:523 | `getAllSoccerGames` (via getGames) | `AFC San Jose/Seasons/<s>/Date` | AFC games on Matches tab (LiveScorePage), ShowLeaguePage, ScorePage incl. vote counts | `times` map per page only | no | DISPLAY | AFC scores/status/votes stale on home; pull-to-refresh re-reads the same cache. |
| 50 | misc/utility.dart:570 | `getAllFutsalGames` (via getGames) | `/Futsal/<s>/Date` | legacy path only (LeagueDayView legacy tap is for non-engine sports) | none | current season: YES CalendarTab | DISPLAY | Effectively unreachable for Futsal. |
| 51 | misc/utility.dart:617 | `getAllBasketballGames` | `/Basketball/<s>/Date` | same | none | same | DISPLAY | Same. |
| 52 | misc/utility.dart:664 | `getAllFlagFootballGames` | `/Flag Football/<s>/Date` | same | none | same | DISPLAY | Same. |
| 53 | misc/utility.dart:806 | `getSeasonStartTime` | `/<sport>/<season>/Start Time` | legacy derived game time (non-AFC) | caller `times` map | no | STATIC | Harmless. |
| 54 | misc/utility.dart:898 | `getSignUpStatus` | `Sign Ups/Sign Up Status` | legacy drawer "Sign Up List" row enabled + label (when no new-style registration open) | none (NavBar re-inits each drawer open) | no | GATE | Sign-ups shown closed when open (locked out) or open when closed. |
| 55 | misc/utility.dart:914 | `getSignUpDue` (DEAD) | `Sign Ups/Due` | - | none | no | DISPLAY | n/a |
| 56 | misc/utility.dart:930 | `getSignUpInformation` | `Sign Ups/Information` | legacy LeagueForm pre-submit alert | none | no | DISPLAY | Old notice text. |
| 57 | misc/utility.dart:945 | `getInformation` | `Users/<uid>/Information/` | legacy LeagueForm prefill; form then `.set()`s Information via addUpdateInfo | none | no | OWN-WRITE | Old age/height/positions written back. |
| 58 | misc/utility.dart:1213 | `isSignedUp` | `Sign Ups/<league>/<season>/NotPaid/` | signup.dart: disables season tile; leagueform.dart:394: post-write check | none | no | GATE | Tile disabled though not signed up, or enabled -> duplicate sign-up. |
| 59 | misc/utility.dart:1215 | `isSignedUp` | `Sign Ups/<league>/<season>/Paid/` | same | none | no | GATE | Same. |
| 60 | misc/utility.dart:1231 | `getPhone` | `Users/<uid>/Phone Number/` | legacy LeagueForm prefill, written back by addUpdateInfo | none | no | OWN-WRITE | Old phone written back. |
| 61 | misc/utility.dart:1248 | `getSignUpRules` | `Sign Ups/Rules` | rules URL (legacy form + dynamic_form fallback) | none | no | DISPLAY | Old rules doc opened. |
| 62 | misc/utility.dart:1264 | `getSignUpWaiver` | `Sign Ups/Waiver` | waiver URL (same) | none | no | DISPLAY | Old waiver opened. |
| 63 | misc/utility.dart:1278 | `getSeason` | `<league> Season` | legacy sign-up season number (= current + 1), shown in drawer and written by signUpToPlay | none | no | GATE | Fan signs up for the wrong season number. |
| 64 | misc/utility.dart:1291 | `getOtherSignups` | `Sign Ups` (whole node, incl. everyone NotPaid/Paid lists) | which other sign-up forms are open (Sign Up Status == 1, Form URL) | none | no | GATE | Closed forms still listed / new ones missing. |
| 65 | misc/utility.dart:1303 | `getBusinesses` | `Map` | Around You businesses/markers | none | YES: called from the AroundYou `Map` onValue listener (aroundyou.dart:60) | DISPLAY | Harmless. |
| 66 | misc/utility.dart:1329 | `getEvents` (DEAD; only getEvent, itself uncalled) | `Events` | - | none | YES | DISPLAY | n/a |
| 67 | navbar.dart:88 | `retrieveProfilePic` | `Users/<uid>` (whole) | drawer avatar | none | no | DISPLAY | Old photo (if changed on another device). |
| 68 | profile/profile_page.dart:968 | `_loadIdentity` (bounded) | `Users/<uid>` (own) or `PublicProfiles/<uid>` (others) | name, photo, Information, Played (feeds career), Awards | re-read every open, also on cache hit (`_refreshIdentity`); Played-derived career in `_careerCache` | no | DISPLAY | Awards/photo/name updated by the Manager not shown. |
| 69 | profile/profile_page.dart:1129 | `_extractFromTeamNode` (bounded) | `/<sport>/<season>/Line Ups/<team>` | career stats per stint | `_careerCache` (:1502): cache hit returns early at :861 and skips ALL career reads for the session; cleared only on sign-out | ancestor Line Ups live only while a league page for that season is open | DISPLAY | Career stats stale. |
| 70 | profile/profile_page.dart:1235 | `_loadTournamentAppearances` (bounded) | `Users/<uid>/TournamentsPlayed` or `PublicProfiles/<uid>/TournamentsPlayed` | tournament appearances index | `_careerCache` | no | DISPLAY | Newly linked tournament missing. |
| 71 | registration/payment_screen.dart:153 | `_loadPublishableKey` | `AppConfig/StripePublishableKey` | Stripe init for card payment | none | no | GATE | After a key rotation, card payment fails or targets the old account. |
| 72 | registration/registration_service.dart:44 | `getOpenRegistrations` | `RegistrationsPublic` | home banner, drawer row, event page Register (its config incl. fee is passed into the whole flow) | none (FrontPage field for the session) | only while RegistrationEntryPage is open | GATE | Event page lets the fan into a closed registration or with an old fee; banner/drawer wrong. |
| 73 | registration/registration_service.dart:77 | `getForm` | `Registrations/<regId>/Form` | question list (form page, status page) | none | no | DISPLAY | Old/missing questions; answers saved against the old form. |
| 74 | registration/registration_service.dart:92 | `getMySubmission` | `Registrations/<regId>/Submissions/<uid>` | routing: status page vs new registration (entry page, event page) | none | watchMySubmission only while status/payment page open | GATE | Fan sent to register again over an existing (maybe paid) submission. |
| 75 | registration/registration_service.dart:126 | `getPrefill` | `Users/<uid>` | form prefill; answers written back by `_writeBackProfile` | none | no | OWN-WRITE | Old name/phone/age written back over newer values. |
| 76 | registration/registration_service.dart:166 | `getPromo` | `Registrations/<regId>/Promo` | first-timer promo % shown and stamped onto submission | none | no | GATE | Promo applied/refused wrongly -> wrong amount owed. |
| 77 | registration/registration_service.dart:325 | `getTeam` (DEAD) | `Registrations/<regId>/Teams/<tid>` | - | none | watchTeam on status page | DISPLAY | n/a |
| 78 | support/support_form_page.dart:63 | comment line, not a call | - | - | - | - | - | - |
| 79 | support/support_form_page.dart:146 | `_loadIdentity` | `Users/<uid>` (First/Last Name) | name stamped on a ticket when displayName empty | none | no | OWN-WRITE | Ticket carries an old name. |
| 80 | support/support_service.dart:45 | comment line, not a call | - | - | - | - | - | - |
| 81 | support/support_service.dart:172 | `_myRecentCreatedAts` | `Support/UserTickets/<uid>` | soft rate limit before createTicket | none | watchMyTicketNums only while My Tickets open | GATE | Harmless: own tickets are in cache; other-device tickets not counted. |
| 82 | support/support_service.dart:177 | `_myRecentCreatedAts` | `Support/Tickets/<n>/CreatedAt` | same | none | watchTicket while that ticket open | STATIC | Harmless. |
| 83 | table.dart:38 | `getSeasonTable` | `/Futsal/<s>/Teams` | top-bar standings table | none | watchStandings only while a league detail/team page for that season is open | DISPLAY | Top-bar table shows old points/W-D-L. |
| 84 | table.dart:60 | `getSeasonTable` | `AFC San Jose/Seasons/<s>/Table` | AFC table | none | no | DISPLAY | Same. |
| 85 | table.dart:80 | `getSeasonTable` | `/Flag Football/<s>/Teams` | top-bar table | none | as #83 | DISPLAY | Same. |
| 86 | table.dart:99 | `getSeasonTable` | `/Basketball/<s>/Teams` | top-bar table | none | as #83 | DISPLAY | Same. |

### Category counts (84 real calls)
- GATE: 20 (#1, 2, 6, 7, 8, 15, 16, 17, 21, 22, 54, 58, 59, 63, 64, 71, 72, 74, 76, 81)
- DISPLAY: 52 (10 of them DEAD: #13, 24, 26, 27, 31, 34, 35, 55, 66, 77)
- OWN-WRITE: 6 (#4, 14, 57, 60, 75, 79)
- STATIC: 6 (#3, 9, 19, 43, 53, 82)

## 2. Other one-shot forms

- `.get()`: none in `lib/` (only comments saying it is banned).
- `.onValue.first`: none literally. ONE stream-first read: `registration/registration_form_page.dart:135` `_loadMyInsider` -> `InsiderService.watchMyInsider(uid).first` (path `Insiders/<uid>`, the fan own Insider tier discount on the individual path). Category GATE (money). Low risk: MyHomePage keeps `Insiders/<uid>` live all session.
- `lib/misc/bounded_read.dart` does NOT call `once()`. It is a timeout extension on any Future; bounding fixes "offline read never answers", NOT staleness. Its 19 call sites wrap reads already counted above:

| call site | wraps | underlying row(s) |
|---|---|---|
| fantasy/data/fantasy_schedule_feed.dart:725 | LeagueService.getStartHour (orElse 0) | #19 |
| fantasy/data/fantasy_season_resolver.dart:165 | readSport | #2 |
| fantasy/data/fantasy_season_resolver.dart:170 | readSeason | #2 |
| fantasy/data/fantasy_season_resolver.dart:176 | hasConfig | #1 |
| misc/public_profiles.dart:142 | `_readRoot` | #23 |
| profile/profile_page.dart:262 | getAllTeamLogo() (live feed, not a once) | - |
| profile/profile_page.dart:363 | getSoccerSeasons | #44 |
| profile/profile_page.dart:366 | getSoccerRoster | #45 |
| profile/profile_page.dart:969 | profile node | #68 |
| profile/profile_page.dart:1105 / 1107 / 1109 | getAllFutsal / Basketball / FlagFootball LineUps | #46 / #48 / #47 |
| profile/profile_page.dart:1130 | team Line Ups node | #69 |
| profile/profile_page.dart:1139 | getAllTeamLogo() | - |
| profile/profile_page.dart:1236 | TournamentsPlayed | #70 |
| profile/profile_page.dart:1249 | getTournamentBundle | #28 |
| profile/profile_page.dart:1256 | enrichRosterPhotos | #33 |
| profile/profile_page.dart:1301 | getAFCCurrentSeason / getCurrentSeason | #40 / #38 |
| profile/profile_page.dart:1321 | isAFCSeasonFinished / isSeasonFinished | #41 / #39 |

### bounded_read.dart contents (exact API)
- Header comment: one-shot reads that gate a reveal must be BOUNDED (Opus audit item 6); live streams are not bounded.
- Imports: `dart:async`, `package:flutter/foundation.dart`.
- `const Duration kRevealReadTimeout = Duration(seconds: 8);` (the only timeout constant)
- private `String _describe(Duration d)` -> "8s" or "<n>ms".
- `extension BoundedRead<T> on Future<T>` with one method:
  `Future<T> bounded(String what, {FutureOr<T> Function()? orElse, Duration timeout = kRevealReadTimeout})`
  Hand-rolled Completer + Timer (not Future.timeout). On timeout: with orElse, debugPrint "`<what>: no answer after 8s — degrading`" and complete with orElse(); without, debugPrint "`— failing`" and completeError(TimeoutException). Late value/error ignored.
- Imported by 5 files: fantasy_schedule_feed.dart, fantasy_season_resolver.dart, public_profiles.dart, team_logos.dart (uses kRevealReadTimeout only), profile_page.dart. **19 `.bounded(` call sites** (1 + 3 + 1 + 14).

## 3. Callers of helpers that call `once()` internally

| helper (row) | caller file:line | screen / purpose |
|---|---|---|
| getCurrentSport (#37) | frontpage.dart:138 | Matches tab league section |
| | main.dart:556 | headerNotifier -> top-bar Table/Leaderboard target |
| | search_hub_page.dart:114 | search fantasy card |
| getCurrentSeason (#38) | frontpage.dart:139 | Matches tab |
| | leagues.dart:126 | Leagues tab last season tile |
| | main.dart:557 | headerNotifier |
| | misc/calendar_sources.dart:160 | calendar: which season to stream |
| | profile/profile_page.dart:1300 | career active stint |
| | search_hub_page.dart:115 | search fantasy card |
| isSeasonFinished (#39) | frontpage.dart:146; profile/profile_page.dart:1320 | home section/banner; active stint |
| getAFCCurrentSeason (#40) | frontpage.dart:151; profile/profile_page.dart:1299 | home AFC; profile |
| isAFCSeasonFinished (#41) | frontpage.dart:159; profile/profile_page.dart:1319 | home AFC; profile |
| getDates (#42) | utility.dart:277 (getCurrentDate <- frontpage.dart:142, 155); showleague.dart:45 | home match day; AFC season tabs |
| getMinSeason (#43) | leagues.dart:125 | Leagues tab |
| getSoccerSeasons (#44) | profile/profile_page.dart:362 | profile |
| getSoccerRoster (#45) | leaderboard.dart:77; utility.dart:714, 718 (fillInNull); profile/profile_page.dart:366 | AFC leaderboard; AFC games; profile |
| getAllFutsalLineUps (#46) | leaderboard.dart:65; utility.dart:834 (getFutsalLineUp <- fillInNull 727-728); profile/profile_page.dart:1105 | top-bar leaderboard; legacy games; profile |
| getAllFlagFootballLineUps (#47) | leaderboard.dart:81; utility.dart:840 (<- 774-775); profile/profile_page.dart:1109 | same |
| getAllBasketballLineUps (#48) | leaderboard.dart:93; utility.dart:846 (<- 753-754); profile/profile_page.dart:1107 | same |
| getGames / getGame (#49-53 + fillInNull reads) | livescore.dart:52, 271 (AFC on Matches tab, ShowLeaguePage); widgets/league_day_view.dart:151 (legacy tap); scorepage.dart:959 (refresh, incl. after vote write) | AFC games, ScorePage |
| getSignUpStatus (#54) | navbar.dart:105 | drawer sign-up row |
| getSignUpInformation (#56) | leagueform.dart:288 | legacy form alert |
| getInformation (#57) | signup.dart:34 | legacy prefill |
| isSignedUp (#58-59) | signup.dart:36; leagueform.dart:394 | tile enable; post-write check |
| getPhone (#60) | signup.dart:35 | prefill |
| getSignUpRules (#61) | leagueform.dart:194; registration/dynamic_form.dart:401 | rules link |
| getSignUpWaiver (#62) | leagueform.dart:230; registration/dynamic_form.dart:403 | waiver link |
| getSeason (#63) | navbar.dart:113, 119 | legacy sign-up season |
| getOtherSignups (#64) | signup.dart:50 | other forms list |
| getBusinesses (#65) | aroundyou.dart:139 (inside Map onValue) | Around You |
| getAllUsers -> PublicProfiles.getAllOnceOrNull (#23) | eventpage.dart:97; search_hub_page.dart:193 | attendees; search players |
| PublicProfiles.getAllOnce (#23) | fantasy/hub/leaderboards_tab.dart:355 | fantasy leaderboard names |
| getAllEvents (#11-12) | search_hub_page.dart:180 | search |
| getCategories (#10) | onboarding/favorite_sports_page.dart:48; settings.dart:53 | category lists |
| getStoreLinks (#9) | eventpage.dart:174 | share |
| RegistrationService.getOpenRegistrations (#72) | eventpage.dart:258; frontpage.dart:165; navbar.dart:97 | event Register; banner; drawer |
| RegistrationService.getForm (#73) | registration/registration_form_page.dart:99; registration/registration_status_page.dart:67 | form; status |
| RegistrationService.getMySubmission (#74) | eventpage.dart:267; registration/registration_entry_page.dart:33 | routing |
| RegistrationService.getPrefill (#75) | registration/registration_form_page.dart:100 | prefill |
| RegistrationService.getPromo (#76) | registration/registration_form_page.dart:111 | promo |
| InsiderService.apply (#14) | insiders/insiders_info_page.dart:170 | apply |
| InsiderService.lookupCode / insiderStatus / alreadyReferred / getInsiderName (#15-18) | registration/insider_promo_field.dart:149-155 (invoked 157-160) | promo code field |
| NotificationPrefs.hasAnswered / serverFavorites (#22, #21) | main.dart:472, 473 | favorites prompt |
| LeagueService.getStartHour (#19) | widgets/league_day_view.dart:71; league_detail_page.dart:240; league_match_detail.dart:110; league_team_detail.dart:86; fantasy/data/fantasy_schedule_feed.dart:636 | kick-off hour |
| TournamentService.getActiveTournaments / getAllTournaments (#25) | frontpage.dart:177; search_hub_page.dart:175 | home tabs; search |
| TournamentService.getTournamentBundle (#28) | frontpage.dart:182; misc/notification_router.dart:131; profile/profile_page.dart:1247; tournament_match_detail.dart:75 | various |
| TournamentService.enrichRosterPhotos (#33) | frontpage.dart:186; misc/notification_router.dart:136; profile/profile_page.dart:1255; tournamentdetail.dart:190; getRosters <- tournamentteamdetail.dart:98 | avatars |
| TournamentService.getTeams (#29-30) | tournamentteamdetail.dart:96 | team detail |
| TournamentService.getRosters (#32, #33) | tournamentteamdetail.dart:98 | team detail |
| TournamentService.getTeamTournamentHistory (#36) | tournamentteamdetail.dart:74 | team history |
| resolveFantasySeason (#1-2) | profile/fantasy_profile_source.dart:493 (via resolveSeasonShared) | profile Fantasy tab |

## A. Rows where a stale value could cause a WRONG ACTION

1. **#72 getOpenRegistrations via event page Register (eventpage.dart:258).** The stale config (Status, fee, form) is passed into RegistrationPathPage -> form -> PaymentScreen, where `amountOwed(config: widget.config, ...)` sets the amount. A closed registration can be entered, an open one refused ("Registration is closed"), and the OLD FEE is shown and charged. (The drawer and the home banner route through RegistrationEntryPage, which is live.)
2. **#74 getMySubmission** (entry page, event page). A stale "no submission" sends a fan who already registered (on another device, or created by an admin) back to the path page; submitting `.set()`s `Registrations/<regId>/Submissions/<uid>`, OVERWRITING a Paid/discounted submission with Paid:false, plus a legacy NotPaid entry.
3. **#76 getPromo.** A stale first-timer promo config is stamped onto the submission (DiscountPct / EligibleFee) -> wrong amount owed on PaymentScreen.
4. **#15-17 Insider code checks** (`InsiderCodes/<code>`, `Insiders/<owner>/Status`, `ReferredUsers/<me>`). A suspended or revoked Insider code still grants the discount, a newly issued code is rejected, an already-referred fan can get a second referral discount. Stamped into the submission -> wrong amount and wrong referral credit.
5. **#71 AppConfig/StripePublishableKey.** After a key rotation the payment sheet is initialised with the old key -> card payment fails or targets the old account.
6. **#75 getPrefill -> _writeBackProfile, and #57/#60 getInformation/getPhone -> addUpdateInfo (`.set` on Information + Phone Number).** Stale profile values are pre-filled and written back over newer values set by the Manager or another device.
7. **#63 getSeason** (legacy drawer): season = stale `<league> Season` + 1 -> signUpToPlay writes `Sign Ups/<league>/<wrongSeason>/NotPaid/<uid>`: fan signs up for the wrong season. **#54 getSignUpStatus**: sign-ups shown closed (fan locked out) or open when closed. **#64 getOtherSignups**: closed forms listed, open ones hidden.
8. **#58/59 isSignedUp** (signup.dart): season tile disabled though not signed up (locked out), or enabled -> duplicate sign-up.
9. **#8 onboarding gate** (`Users/<uid>` ProfileCompleted): a stale "incomplete" forces the mandatory, no-skip About You page on a fan who already completed it. **#6/#7** (`Users/<uid>` exists): a cached stale node can skip onboarding/base-profile writes for a re-created account (rare). **#21/#22** re-show the favorites prompt.
10. **#1/#2 fantasy season resolver + `_lastResolved` memo**: profile Fantasy tab missing or tied to the previous season after a new season starts.
11. **#4 Insider application name, #79 support ticket name**: write an old name (minor).
12. **registration_form_page.dart:135 `watchMyInsider(uid).first`**: wrong Insider tier discount possible, but `Insiders/<uid>` is permanently live via MyHomePage, so low risk. **#14 InsiderService.apply** is protected the same way.
13. Not money, but highest-impact "wrong place": **#37/#38 `Current League` / `<Sport> Season` have no live stream anywhere.** The whole Matches tab, the top-bar Table/Leaderboard, the calendar league days, the Leagues tab last tile, the search fantasy card and the profile active flag can stay on the previous league/season on that phone indefinitely. The fan cannot reach the new season from the Leagues tab, and the home fantasy banner watches the old season Config.

## B. Session-memoised globals fed by one-shot reads

| global | where filled | readers | early return / cleared? |
|---|---|---|---|
| `futsalLineups`, `basketballLineups`, `flagFootballLineups` (misc/utility.dart:55-57) | getAllFutsalLineUps :361, getAllFlagFootballLineUps :406, getAllBasketballLineUps :434 (#46-48) | leaderboard.dart:67/83/95; profile/profile_page.dart:270, 289, 309 (_extractHelper), 337, 343, 349 (_extractPlayerStats); utility.dart:835/841/847 (getXLineUp) | No early return now (overwritten each call), but every refill is itself a stale once(). Never cleared. |
| `_careerCache` (profile/profile_page.dart:1502) | _loadCareer :1041, _runCareerOverride :892, _refreshIdentity :902 | _doLoad :861 (hit -> _restoreCareer, skips all career reads) | EARLY RETURN all session: Line Ups (#69), AFC (#44/45), TournamentsPlayed (#70), bundles (#28/33), current season/finished (#38-41) never re-read for that uid. Cleared only by signOutAndClearSession (account/session_sign_out.dart:41). |
| `LeagueService._profileUrlCache` (misc/league_service.dart:112) | _withProfileUrls :213 (#20) | _uncachedLinkedUids, _substituteCachedPhotos, _withProfileUrls | skip-if-cached; `clearProfileUrlCache()` (:115) has NO caller, not even sign-out. |
| `TournamentService._profileUrlCache` (misc/tournament_service.dart:27) | enrichRosterPhotos :416 (#33) | parseRosters/_substituteCachedRosterPhotos, rosterPhotosPending, enrichRosterPhotos | skip-if-cached; `clearProfileUrlCache()` (:31) has NO caller. |
| `FantasyLeaderboardsTab.profilesSession` (fantasy/hub/leaderboards_tab.dart:219) | _loadProfiles :355 (`??= PublicProfiles.getAllOnce()`, #23) | same method | early return all session; reset on empty result (:359) and in clearFantasySessionState (fantasy_session.dart:36). |
| `_lastResolved` / `lastResolvedFantasySeason` (fantasy/data/fantasy_season_resolver.dart:126) | resolveFantasySeason (#1, #2) | FantasyProfileSource.start (profile/fantasy_profile_source.dart:488) | early return all session; NEVER cleared ("not user-specific"). Also `_noSeasonAt` (5-min none memo) and `_resolving` in fantasy_profile_source.dart. |
| `FantasyLeagueGamesFeed._startHourSession` (fantasy/data/fantasy_schedule_feed.dart:660) | start() -> _onHour from LeagueService.getStartHour (#19) | start() :718 | early return for real hours (>0); cleared via clearSessionCache (fantasy session clear). |
| `_cached` StoreLinks (misc/app_config.dart:16) | getStoreLinks (#9) | eventpage.dart:174 | early return; never cleared. |
| `headerNotifier` (misc/utility.dart:77) | main.dart:558 from getCurrentSport/getCurrentSeason (#37/#38), once per MyHomePage init | frontpage.dart:260 (TablePage target), :282 (LeaderboardPage target) | session-long; nothing re-reads it. |
| FrontPage fields currentSport/currentSeason/currentDate/isCurrentFinished/currentAFCSeason/currentAFCDate/isCurrentAFCFinished/openRegistrations (frontpage.dart:57-66) | getFrontPageValues :132 (#37-42, #72) | FrontPage build | FrontPage lives all session in the IndexedStack; re-read only by its manual refresh (:523), which hits the same cache. |
| CalendarTab league-days season (misc/calendar_sources.dart:160) | getCurrentSeason once at subscribe (#38) | per-sport Date stream | season fixed for the session. |
| `times` maps (livescore.dart:45, ScorePage widget.times) | getSeasonStartTime (#53) | getGames | per page. |

(`LeagueService._rostersSnapshotCache` and `teamLogos` are now fed by live streams, not one-shots.)

## C. Screens that are entirely one-shot (no stream), most-opened first

1. **Top-bar Leaderboard** (LeaderboardPage, from the Matches tab app bar): Line Ups via #46-48 (AFC #45). Opened constantly; stale stats.
2. **Top-bar Table** (TablePage): Teams #83/85/86, AFC Table #84. Stale standings.
3. **Matches tab "frame" decisions** (not the live day list): which league/season/date, finished flags, AFC section, registration banner (#37-42, #72). The **AFC San Jose section of the Matches tab** (LiveScorePage, #49 + #45) is fully one-shot incl. scores and vote counts; pull-to-refresh does not help.
4. **Drawer (NavBar)**: avatar #67, sign-up row #72/#54/#63.
5. **Player profile (ProfilePage)**: identity #68 every open; career (#69, 70, 44, 45, 28, 33, 38-41) memoised in `_careerCache`. No stream apart from the separate Fantasy tab feeds.
6. **Leagues tab season list** (getSeasonTiles): #43, #38, #5. New season missing while `<Sport> Season` is stale.
7. **AFC league pages**: ShowLeaguePage (#42), its per-date LiveScorePage (#49), ScorePage (#49/#45 via getGame), AFC Table/Leaderboard.
8. **Search hub index**: tournaments/events covered by permanent streams; players (PublicProfiles #23) pure one-shot; fantasy card pointer (#37/38).
9. **Event page attendee list** (#23 via getAllUsers) and the event Register routing (#72, #74). The event itself is live (watchEvent).
10. **Registration form page** (#73, 75, 76, registration_form_page.dart:135, Insider code checks #15-18) and the routing into it (#74). Status/payment pages are live except the publishable key (#71) and the form (#73).
11. **Tournament team detail**: teams/rosters/history (#29, 30, 32, 36) one-shot but covered by the permanent /Tournaments stream; matches live.
12. **Insiders info page** prefill/playbook (#3, #4; Insider state live). **Support form** (#79, #81, #82).
13. **Legacy Signup / LeagueForm** (#54-64): rarely reached (only when no new-style registration is open and legacy Sign Up Status != 0).

Not one-shot: Around You (Map + events live; #65 runs inside the live listener), Calendar, league detail/match/team pages, tournament detail/match pages, Matches-tab day list (LeagueDayView), fantasy hub, registration entry/status/payment pages, My Tickets.
