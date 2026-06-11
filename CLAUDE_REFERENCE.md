# Infinite Sports — Claude Reference Document

**Last updated:** May 20, 2026 (updated with Firebase JSON export analysis)  
**Project location:** `C:\Users\zayaa\StudioProjects\infinite_sports_flutter`  
**App version:** 3.0.0+10  
**Built with:** Flutter (Dart), Firebase, Google Maps

This is the working reference document written by Claude for use in future coding sessions. It is written so that both the developer and Claude can pick up where we left off without re-reading all the code from scratch.

---

## What The App Is

Infinite Sports is a mobile app (Android + iOS) for an Assyrian community sports league. It shows live game scores, historical league seasons, player stats, standings, a Google Map of local businesses and events, and handles user accounts with sign-up forms for joining leagues.

**Four supported sports:**
- Futsal (indoor soccer)
- Basketball
- Flag Football
- AFC San Jose (outdoor soccer)

---

## The Three Main Tabs

The app opens to a bottom navigation bar with three tabs. This never changes — it is always visible.

| Tab | Name | Entry File |
|-----|------|-----------|
| 0 | Live Scores | `lib/frontpage.dart` |
| 1 | Leagues | `lib/leagues.dart` |
| 2 | Around You | `lib/aroundyou.dart` |

There is also a **side drawer** (hamburger menu) for account management, sign-up forms, settings, and dark mode.

---

## App Startup — What Happens When The App Opens

**File:** [`lib/main.dart`](lib/main.dart)

1. Flutter engine starts
2. Environment variables loaded from `.env` file (holds API keys)
3. Firebase initialized using keys from [`lib/firebase_options.dart`](lib/firebase_options.dart)
4. Push notifications initialized via [`lib/misc/pushnotifications.dart`](lib/misc/pushnotifications.dart)
5. Dark mode setting and auto-sign-in setting loaded from local device storage
6. If user was previously signed in and auto-sign-in is on → sign them in silently, upload their device notification token
7. App shell (`MyHomePage`) rendered with bottom nav bar

The root widget tree is: `MyApp` → `ChangeNotifierProvider(ThemeProvider)` → `MyHomePage`

---

## Folder & File Map

```
lib/
├── main.dart                         App entry point, shell widget, bottom nav
├── frontpage.dart                    Live Scores tab home
├── livescore.dart                    Game cards list for one date
├── scorepage.dart                    Full game detail (LARGEST FILE — 1057 lines)
├── leaderboard.dart                  Player leaderboard for a season
├── table.dart                        Standings table for a season
├── showleague.dart                   All dates in a season, tabbed view
├── leagues.dart                      League selection page
├── aroundyou.dart                    Google Maps + businesses/events
├── businesspage.dart                 Business detail view
├── eventpage.dart                    Event detail with attendee list
├── navbar.dart                       Side drawer
├── login.dart                        Email/password login
├── createaccountpage.dart            New account registration
├── forgotpasswordpage.dart           Password reset
├── settings.dart                     Settings & info pages
├── playerpage.dart                   Player career stats
├── signup.dart                       League sign-up list
├── leagueform.dart                   Sign-up form
├── globalappbar.dart                 Reusable top bar with table/leaderboard icons
├── botnavbar.dart                    Old bottom nav — no longer used
├── leaders.dart                      EMPTY FILE — unused
│
├── misc/
│   ├── utility.dart                  THE HUB — all shared state + Firebase helpers (1169 lines)
│   ├── theme_provider.dart           Dark/light theme toggle logic
│   ├── pushnotifications.dart        Firebase Cloud Messaging + local notifications
│   ├── navigation_controls.dart      Back/forward/reload buttons for WebView
│   └── web_view_stack.dart           Wrapper that loads a URL in a WebView
│
├── firebase_auth/
│   └── firebase_auth_services.dart   Sign in, sign up, sign out wrappers
│
├── firebase_options.dart             Firebase platform configuration
│
├── navigations/
│   ├── current_livescore_navigation.dart   Navigator wrapper for Live Scores tab
│   └── leagues_navigation.dart             Navigator wrapper for Leagues tab
│
└── model/
    ├── game.dart                     Abstract Game base class
    ├── futsalgame.dart               Futsal game data
    ├── basketballgame.dart           Basketball game data
    ├── flagfootballgame.dart         Flag Football game data
    ├── soccergame.dart               AFC San Jose game data
    ├── futsalplayer.dart             Futsal player
    ├── basketballplayer.dart         Basketball player
    ├── flagfootballplayer.dart       Flag Football player
    ├── soccerplayer.dart             AFC San Jose player
    ├── player.dart                   Abstract player base
    ├── playerstats.dart              Abstract stats base
    ├── futsalplayerstats.dart        Futsal per-game stats
    ├── basketballplayerstats.dart    Basketball per-game stats
    ├── flagfootballplayerstats.dart  Flag Football per-game stats
    ├── futsalteaminfo.dart           Futsal standings row
    ├── basketballteaminfo.dart       Basketball standings row
    ├── flagfootballteaminfo.dart     Flag Football standings row
    ├── soccerteaminfo.dart           AFC San Jose standings row
    ├── teaminfo.dart                 Abstract team base
    ├── business.dart                 Business map pin data
    ├── event.dart                    Community event data
    ├── attendee.dart                 Event attendee (uid + photo)
    ├── myuser.dart                   User display data (name + photo)
    ├── userinformation.dart          Extended user info (age, height, positions)
    ├── gameactivity.dart             Individual game action (goal, foul, etc.)
    ├── leaguemenu.dart               League list item for Leagues tab
    ├── playerinfo.dart               EMPTY FILE — unused
    └── soccerplayer.dart             (see above)

assets/                               All image/icon files (see Assets section)
android/                              Android native project
ios/                                  iOS native project
test/                                 Unit tests (currently only a placeholder)
pubspec.yaml                          Package dependencies
.env                                  API keys (NOT committed to git)
```

---

## The Hub File: `utility.dart`

**File:** [`lib/misc/utility.dart`](lib/misc/utility.dart) — **read this before changing anything Firebase-related**

This file is the center of the app. It holds all shared global variables AND all the functions that talk to Firebase to load data.

### Global Variables

| Variable | Type | What It Is |
|----------|------|------------|
| `signedIn` | bool | Whether a user is currently logged in |
| `autoSignIn` | bool | User's preference to stay signed in |
| `darkModeEnabled` | bool | Current theme setting |
| `auth` | FirebaseAuthService | The single sign-in/out service used everywhere |
| `mainContext` | BuildContext? | Global context used for navigation from outside a widget |
| `mainScaffoldContext` | BuildContext? | Global context used to open the drawer |
| `headerNotifier` | ValueNotifier | Triggers rebuilds when sport/season changes |
| `infiniteSportsPrimaryColor` | Color | The app's red color — `RGB(208, 0, 0)` |
| `futsalLineups` | Map | Cached Futsal rosters (keyed by season → team → player name) |
| `basketballLineups` | Map | Cached Basketball rosters |
| `flagFootballLineups` | Map | Cached Flag Football rosters |
| `teamLogos` | Map | Team logo URLs (keyed by sport → season → team name) |

### Key Firebase Helper Functions

| Function | What It Does |
|----------|-------------|
| `getCurrentSport()` | Reads which sport is currently active from Firebase |
| `getCurrentSeason(sport)` | Gets the current season number for a sport |
| `getAFCCurrentSeason()` | Gets AFC San Jose's current season |
| `getDates(sport, season)` | Returns list of game dates for a season |
| `getCurrentDate(sport, season)` | Finds today's date or the closest game date |
| `getAllFutsalLineUps(season)` | Loads all Futsal rosters into `futsalLineups` cache |
| `getAllBasketballLineUps(season)` | Loads all Basketball rosters into cache |
| `getAllFlagFootballLineUps(season)` | Loads all Flag Football rosters into cache |
| `getSoccerRoster(sport, season)` | Loads AFC San Jose roster, returns Map |
| `getAllTeamLogo()` | Loads all team logo URLs into `teamLogos` cache |
| `getLeaderboard(sport, season)` | Returns player leaderboard data |
| `getTeamStats(sport, season)` | Returns team standings data |
| `isSeasonFinished(sport, season)` | Returns true if a season is over |
| `getSignUpStatus(sport, season)` | Returns sign-up open/closed state |
| `uploadToken(user, token)` | Saves the device notification token to Firebase |
| `setImage(uid, file)` | Uploads profile picture to Firebase Storage |
| `retrieveProfilePic(uid)` | Downloads and caches profile picture URL |

### Date Format — IMPORTANT

**All dates in Firebase are stored as `MMDDYYYY` strings.**  
Example: May 20, 2026 → `"05202026"`

The helper functions `convertDatabaseDateToFormatDate()`, `convertStringDateToDatabase()`, and `convertDateToDatabase()` handle converting between this format and readable dates. Never store or send dates in a different format or those functions will crash.

---

## Firebase Database Structure

The app uses **Firebase Realtime Database** (not Firestore). The paths below are the exact strings used in the code.

```
Firebase Realtime Database
│
├── Current League                    String — which sport is currently active
│
├── {Sport} Season                    String — e.g. "Futsal Season" → current season number
│
├── {Sport}/
│   └── {Season}/
│       ├── Date/
│       │   └── {MMDDYYYY}/
│       │       └── Game {N}/        Game data (teams, score, time, link, votes)
│       ├── Line Ups/
│       │   └── {Team}/
│       │       └── {PlayerName}/    Player data (number, position, uid, stats)
│       ├── Teams/
│       │   └── {Team}/              Standings data (wins, losses, points, etc.)
│       └── Finished                 Boolean — true if season is over
│
├── AFC San Jose/
│   ├── Current Season               String — current AFC season
│   └── Seasons/
│       └── {Season}/
│           ├── Table/{Team}/        Standings row
│           ├── Roster/{Player}/     Player stats
│           └── Date/{MMDDYYYY}/     Game data
│
├── Users/
│   └── {uid}/
│       ├── First Name
│       ├── Last Name
│       ├── ProfileUrl
│       ├── DeviceTokens/{token}
│       ├── Information/             Extended profile (age, height, positions)
│       └── Played/{Sport}/Season X/{Team}   Career history
│
├── Sign Ups/                        Sign-up form data
├── Logo Urls/                       Team logo URLs by sport/season/team
├── Map/                             Business marker data
└── Events/
    └── {event_id}/
        └── Attendees/{uid}          Photo URL or 1 (attended marker)
```

**Firebase Storage** (for images):
- `Users/{uid}/profileimage.jpg` — user profile pictures

---

## Firebase Database: Real Structure (from JSON Export)

This section was written from a full export of the real Firebase database. It is more detailed and accurate than the structural overview above.

### Top-Level Keys in the Database

| Key | Type | What It Holds |
|-----|------|--------------|
| `AFC San Jose` | Object | All AFC San Jose seasons, roster, table, current season name |
| `Basketball` | Object | All basketball seasons (numbered 9–13+) |
| `Basketball Season` | Number | The current basketball season number (currently **13**) |
| `Current League` | String | The sport currently featured on the Live Scores home tab (currently **"Flag Football"**) |
| `Down` | Boolean | Maintenance/downtime flag. If `true`, the app likely shows a "down for maintenance" message |
| `Events` | Array | List of community event objects |
| `Flag Football` | Object | All flag football seasons (numbered 1–3+) |
| `Flag Football Season` | Number | The current flag football season number (currently **3**) |
| `Futsal` | Object | All futsal seasons (numbered 8–15+) |
| `Futsal Season` | Number | The current futsal season number (currently **15**) |
| `Logo Urls` | Object | Team logo image URLs organized by sport → season number → team name |
| `Map` | Array | List of community business objects |
| `NotifPopUp` | Object | Optional popup banner for the app (`Show`, `Title`, `Subtitle`) |
| `Notifications` | Array | Historical push notification log (title:body strings) |
| `Sign Ups` | Object | League registration data by sport → season |
| `Users` | Object | All user profiles keyed by Firebase UID |

---

### Game Status Codes

Every game object has a `status` field. The three possible values are:

| Value | Meaning | What The App Shows |
|-------|---------|--------------------|
| `0` | Upcoming / Scheduled | Displays scheduled time, score shows as 0–0 |
| `1` | Live / In Progress | Shows "LIVE" badge, score updates in real time |
| `2` | Final / Finished | Shows final score |

---

### Game Object: Exact Fields

Each game is stored as an array item under `{Sport}/{Season}/Date/{MMDDYYYY}/`.

**Fields present on all sports:**

| Field | Type | Description |
|-------|------|-------------|
| `date` or `Date` | String | Human-readable date (e.g., `"April 5, 2026"`) |
| `status` | Number | 0 = upcoming, 1 = live, 2 = final |
| `team1` | String | Team 1 name |
| `team2` | String | Team 2 name |
| `team1score` | Number | Team 1 score |
| `team2score` | Number | Team 2 score |
| `team1activity` | Object | Game activity log keyed by time string (e.g., `"45'"`) |
| `team2activity` | Object | Same for team 2 |
| `team1vote` | Object | Map of UID → 1 for users who voted team 1 |
| `team2vote` | Object | Map of UID → 1 for users who voted team 2 |
| `link` | String | YouTube/stream URL (optional — not all games have one) |
| `location` | String | Venue name (optional) |
| `startTime` | String | Display time (e.g., `"9:30 AM"`) |
| `type` | String | Round label for AFC San Jose (e.g., `"Group C"`, `"Semifinals"`, `"Championship"`) |

**Game Activity format — IMPORTANT:**  
Activities are stored as a map where the **key is the time** (e.g., `"45'"`) and the **value is a list of action objects**. Each action object has one key (the action type) and the player name as the value.

```
"team1activity": {
  "45'": [
    { "Goal": "Player Name" },
    { "Assist": "Player Name" }
  ]
}
```

**Action types by sport:**
- **Futsal:** `Goal`, `Assist`, `Save`, `Yellow`, `Blue`, `Red`, `Foul`
- **Basketball:** `OnePointer`, `TwoPointer`, `ThreePointer`, `Rebound`, `Foul`
- **Flag Football:** `Receiving TD`, `Pass TD`, `Rushing TD`, `Interception`, `Sack`, `Safety`, `Rec`, `RecTD`, `PAT1`, `TwoPT`
- **AFC San Jose:** `Goal`, `Assist`, `Yellow`, `Red`

---

### Player Stats in Line Ups: Exact Fields per Sport

Players are stored under `{Sport}/{Season}/Line Ups/{Team}/{PlayerName}/`.

**Futsal player fields:**

| Field | Description |
|-------|-------------|
| `number` | Jersey number (string or int) |
| `Goals` | Total goals scored |
| `Assists` | Total assists |
| `Saves` | Total saves (goalkeepers) |
| `Yellow` | Yellow cards received |
| `Blue` | Blue cards received |
| `Red` | Red cards received |
| `UID` | Firebase user UID (optional — not all players have accounts) |

**Basketball player fields:**

| Field | Description |
|-------|-------------|
| `number` | Jersey number |
| `OnePoint` | Total 1-point shots made (free throws) |
| `TwoPoints` | Total 2-point shots made |
| `ThreePoints` | Total 3-point shots made |
| `Rebounds` | Total rebounds |
| `Misses` | Total missed shots |
| `UID` | Firebase user UID (optional) |

**Flag Football player fields (Season 3 — most detailed):**

| Field | Description |
|-------|-------------|
| `number` | Jersey number |
| `FP` | Fantasy Points |
| `INT` | Interceptions caught |
| `INTTD` | Interception touchdowns |
| `PAT1` | 1-point PAT (point after touchdown) made |
| `PAT1Miss` | 1-point PAT missed |
| `PBU` | Pass breakups |
| `PassINT` | Passes intercepted (QB stat) |
| `PassTD` | Passing touchdowns |
| `QBComp` | QB completions |
| `QBInc` | QB incompletions |
| `REC` | Receptions |
| `RECMiss` | Reception drops |
| `RECTD` | Receiving touchdowns |
| `RushTD` | Rushing touchdowns |
| `Sack` | Sacks |
| `TwoPT` | 2-point conversion made |
| `TwoPTMiss` | 2-point conversion missed |
| `UID` | Firebase user UID (optional) |

**AFC San Jose roster fields:**

| Field | Description |
|-------|-------------|
| `Number` | Jersey number |
| `Position` | Position (GK, D, M, F, or `-`) |
| `Goals` | Total goals |
| `Assists` | Total assists |
| `Yellow` | Yellow cards |
| `Red` | Red cards |
| `UID` | Firebase user UID (optional) |

---

### Team Standings: Exact Fields per Sport

Teams are stored under `{Sport}/{Season}/Teams/{TeamName}/`.

**Futsal:**
`GP` (games played), `Wins`, `Draws`, `Losses`, `GS` (goals scored), `GC` (goals conceded), `GD` (goal difference), `Points`

**Basketball:**
`Wins`, `Losses`, `PD` (point differential), `PPG` (points per game), `PCPG` (points conceded per game), `PCT` (win percentage), `Points`

**Flag Football:**
`Wins`, `Losses`, `Ties`, `PF` (points for), `PA` (points against)

**AFC San Jose:**
`Wins`, `Draws`, `Losses`, `GF` (goals for), `GA` (goals against)

---

### Season-Level Fields (inside each sport season object)

Each season object (e.g., `Futsal/15/`) has these extra fields beyond dates and lineups:

| Field | Description |
|-------|-------------|
| `Finished` | Boolean — `true` if the season is over, `false` if active |
| `Start Time` | Integer — number of minutes in each game half (used by App Manager) |
| `Teams` | Object — standings data for all teams in the season |
| `Line Ups` | Object — all player rosters |
| `Date` | Object — all game dates and game data |

---

### Season Numbering History

| Sport | First Season # | Current Season # | Notes |
|-------|---------------|-----------------|-------|
| Futsal | 8 (test data) | **15** | Active seasons started at 9 |
| Basketball | 9 | **13** | |
| Flag Football | 1 | **3** (active, Finished: false) | Newest sport |
| AFC San Jose | Named seasons | Named strings | Not numbered — uses full season name strings |

**Current active season as of export:** Flag Football Season 3 (games in April–May 2026, `Finished: false`)

---

### Recurring Team Names Across Sports

The same team names appear across multiple sports and seasons. These are the core community teams:

**Ashur, Babylon, Nimrod, Nineveh, Ishtar, Hakkari, Lamassu**

Flag Football Season 2 added: **Nineveh** (new in FF), and uses the same core names.
AFC San Jose uses different opponents since they play external league games, but AFC San Jose itself is one of the teams.

---

### AFC San Jose: Structure Differences

AFC San Jose is structured differently from the other three sports:

- Lives under key `AFC San Jose` (not a sport name)
- `Current Season` is a **full string name** like `"Beyond the Game Turf Open Division Fall 2025"` — not a number
- Seasons are nested under `Seasons/{season name string}/`
- Has `Roster/` (not `Line Ups/`) and `Table/` (not `Teams/`)
- Games have an extra `type` field for tournament round labels
- Does not have a `Start Time` or `Init Season` field
- Has a separate `Logo URL` field at the `AFC San Jose` top level for the AFC logo itself

---

### Logo URLs

Stored under `Logo Urls/{Sport}/{SeasonNumber}/{TeamName}`.

- Sport keys: `"Futsal"`, `"Basketball"`, `"Flag Football"`
- Season keys are **integers as strings**: `"9"`, `"10"`, `"13"`, `"15"`, etc.
- **Note:** Basketball Logo URLs used Futsal season images for earlier seasons (9–11). This is expected — the logos were shared across sports in early seasons.
- Team logos are stored in Firebase Storage under paths like `Futsal/Season 15/Ashur_Logo_400.png`
- There is a quirk: Flag Football also has a key `"'1'"` (with quotes in the key name) in addition to `"1"`. This appears to be a duplicate/error.

---

### Sign Ups Structure

Stored under `Sign Ups/{Sport}/{SeasonNumber}/`.

Each season has three sub-keys:

| Key | Structure | Description |
|-----|-----------|-------------|
| `Paid` | `{uid: "Full Name"}` | Users who have paid their league fee |
| `NotPaid` | `{uid: "Full Name"}` | Users who signed up but haven't paid yet |
| `Comments` | `{"Full Name": "uid:comment text"}` | Free-text comments submitted with sign-up form |

The app uses `Paid` to determine if a user is registered. `NotPaid` is an admin-side tracking list.

---

### Users Structure

Each user is stored under `Users/{firebase_uid}/`.

| Field | Type | Description |
|-------|------|-------------|
| `First Name` | String | User's first name |
| `Last Name` | String | User's last name |
| `Phone Number` | String | Phone number from registration |
| `Date Joined` | String | Account creation timestamp (inconsistent format across old/new accounts) |
| `ProfileUrl` | String | Firebase Storage URL for profile image (optional) |
| `Token` | String | Latest FCM device token for push notifications |
| `Information/Age` | Number | Age from sign-up form |
| `Information/Height` | String | Height (e.g., `"6'0"`) |
| `Information/FutsalPosition` | String | Position(s), semicolon or colon separated (e.g., `"Midfielder;Striker"`) |
| `Information/BasketballPosition` | String | Position(s) |
| `Information/FlagFootballPosition` | String | Position(s) |
| `Played/{Sport}/Season {N}` | String | Team name they played for that season |

**Important:** Some older users have `DeviceTokens/{token}` instead of `Token` — this is the old token storage format. New accounts write to `Token`.

---

### Map (Businesses) Structure

The `Map` array holds community business listings. Each business object:

| Field | Required | Description |
|-------|----------|-------------|
| `Name` | Yes | Business name |
| `Description` | Yes | Full description text |
| `LogoUrl` | Yes | Business logo image URL |
| `Url` | No | Website URL |
| `Phone` | No | Phone number (digits only, no formatting) |
| `Lat` | No | Latitude (decimal) — used for map pin placement |
| `Long` | No | Longitude (decimal) — used for map pin placement |

**Note:** Not all businesses have `Lat`/`Long`. If missing, the business appears in the list sheet but not as a map marker.

---

### Events Structure

The `Events` array holds community event listings. Each event object:

| Field | Required | Description |
|-------|----------|-------------|
| `Title` | Yes | Event name |
| `Info` | Yes | Full description |
| `ImageUrl` | Yes | Event flyer/image URL |
| `Location` | Yes | Venue name |
| `Address` | Yes | Full street address |
| `StartTime` | Yes | Start time display string (e.g., `"6:00PM"`) |
| `EndTime` | No | End time display string |
| `Date` | Yes | Date this listing was posted — `MMDDYYYY` format |
| `EventDate` | Yes | Actual event date — `MMDDYYYY` format |
| `Attendees` | No | Sub-object: `{uid: photoUrl or 1}` — added when users RSVP |

**Note:** `Date` is the posting/display date. `EventDate` is when the event actually happens. The app uses `EventDate` for display.

---

### App-Level Control Fields

| Key | Type | What It Does |
|-----|------|-------------|
| `Down` | Boolean | When `true`, the app may show a maintenance screen. Set to `false` to keep app running normally |
| `NotifPopUp/Show` | Boolean | When `true`, shows a popup banner to all users on app open |
| `NotifPopUp/Title` | String | The banner headline |
| `NotifPopUp/Subtitle` | String | The banner body text |
| `Notifications` | Array | Historical log of past push notifications. Each item has `Date` and `Notif` (formatted as `"Title:Body"`) |

---

### The App Manager

There is a **separate app** called **App Manager** (not part of this Flutter codebase) that is used to enter game data. It is what Zayaa or the league admin uses to:

- Set current scores during live games
- Input player stats (goals, assists, rebounds, etc.)
- Manage rosters and team data
- Control the game clock
- Mark games as live (status 1) or final (status 2)
- Add game activity feed entries (goal scored, foul, etc.)

The App Manager writes directly to the same Firebase Realtime Database that the Infinite Sports app reads from. This is how score and stat updates appear in real time for users.

**When designing new features:** if a feature requires entering or updating data (not just reading it), consider whether it also needs an update to the App Manager side. The Infinite Sports Flutter app is read-only for most game data — it does not enter scores or stats.

---

## Screen-by-Screen Breakdown

### Live Scores Tab

**`frontpage.dart`** — the first thing you see in this tab.
- Reads current sport from Firebase, loads AFC San Jose season too
- Displays two rows of tabs: sport tabs on top, season/date tabs inside
- Each tab shows a `LiveScorePage`

**`livescore.dart`** — shows game cards for one date.
- Each card shows both teams, score (or scheduled time), vote buttons, and a "Watch" button if there's a stream link
- Tapping a game card → opens `ScorePage` as an overlay

**`scorepage.dart`** — the biggest and most complex screen (1057 lines).
- Shows full game detail: scoreboard, 3 tabs (Overview, Team 1 Stats, Team 2 Stats)
- Pulls team colors from the team logo image using `material_color_utilities`
- Sport-specific stat tables: Futsal (goals/assists/saves), Basketball (pts/reb/ast), Flag Football (long stat columns)
- Game activity feed (list of goals, fouls, etc. with icons)
- Voting UI with percentages
- WebView button if a stream link exists

**`table.dart`** — standings table.
- Different columns per sport (Futsal: GP/W/D/L/GS/GC/GD/Pts; Basketball: W/L/PCT/PPG; Flag Football: W/L/T/Pts)
- Tapping a team row shows team logo + record

**`leaderboard.dart`** — player stat leaders for a season.
- Sortable `DataTable2` table
- Different columns per sport
- Tapping a player name → `PlayerPage`

### Leagues Tab

**`leagues.dart`** — shows 4 league options with icons.
- Tapping a league → `ShowLeaguePage` for that league's seasons

**`showleague.dart`** — shows all seasons for a sport, each as a tab.
- Each tab contains the games for that season organized by date
- Has buttons to jump to standings and leaderboard

### Around You Tab

**`aroundyou.dart`** — Google Maps view.
- Requests location permission on first open
- Loads businesses and events from Firebase
- Creates map markers for each
- Draggable bottom sheet with a Business tab and Events tab
- Tapping a business marker or row → `BusinessPage` bottom sheet
- Tapping an event row → `EventPage` full screen

**`businesspage.dart`** — business card.
- Shows logo, description, buttons for Directions, Website, Call

**`eventpage.dart`** — event detail.
- Shows image, date/time, location, attendee profile pictures
- Signed-in users can tap to attend or remove attendance
- Share button

### Drawer (Side Menu)

**`navbar.dart`** — the side drawer that slides in from the left.
- If signed in: profile picture (tap to change), display name, Stats, Sign Up List, Settings, Dark Mode toggle, Logout
- If not signed in: Login / Sign Up button
- Profile picture change uses `ImagePicker` (camera or gallery) → uploads to Firebase Storage

### Account Pages

**`login.dart`** — email + password + "Stay signed in" checkbox.

**`createaccountpage.dart`** — registration form.
- First name, last name, email, phone, password
- Optional profile picture from camera or gallery
- On submit: creates Firebase Auth account, writes to database, uploads photo

**`forgotpasswordpage.dart`** — sends password reset email.

**`settings.dart`** — settings page.
- Change Password
- Auto Log In toggle
- League table column legends (explains what GP, GD, PCT etc. mean)
- Links to About, T&Cs, Privacy Policy, EULA (all open in WebView)
- Contact info

**`playerpage.dart`** — player career stats (470 lines).
- Shows a player's history across all sports and seasons they played in
- Separate career table for each sport
- Data fetched by iterating through all cached lineups to find matching UID

### Sign-Up Flow

**`signup.dart`** — shows which leagues are currently accepting sign-ups.
- Reads sign-up status from Firebase
- Each open slot links to `LeagueForm`

**`leagueform.dart`** — the sign-up form.
- Collects: height, age, position checkboxes, phone number, comments
- Requires user to read Season Rules and Waivers (opens WebViews)
- Submits to Firebase under `Sign Ups/`
- Success dialog shows Venmo payment link

---

## Navigation: How Screens Connect

The app uses **nested navigators** inside each tab. This means when you push a new page inside the Live Scores tab, you can go back to Live Scores without losing your place in the other tabs.

```
MyHomePage (bottom nav)
├── Tab 0: CurrentLivescoreNavigation
│   └── FrontPage
│       └── LiveScorePage
│           └── ScorePage (overlay)
│               ├── PlayerPage
│               ├── TablePage
│               └── LeaderboardPage
│
├── Tab 1: LeaguesNavigation
│   └── LeaguesPage
│       └── ShowLeaguePage
│           ├── TablePage
│           └── LeaderboardPage
│
└── Tab 2: AroundYou (no nested navigator)
    ├── BusinessPage (bottom sheet)
    └── EventPage (full page)

Drawer (NavBar) → uses mainContext for global navigation
├── LoginPage
├── CreateAccountPage
├── ForgotPasswordPage
├── PlayerPage (own stats)
├── Signup
│   └── LeagueForm
└── Settings
    └── WebView (rules, T&Cs, Privacy Policy)
```

**Important:** The drawer uses `mainContext` (a global context variable) to navigate. This is why you can navigate to Settings or PlayerPage from the drawer regardless of which tab you're on. It works, but it means those navigations happen outside the tab navigators.

---

## Theme & Colors

**File:** [`lib/misc/theme_provider.dart`](lib/misc/theme_provider.dart)

- The app supports light mode and dark mode
- The primary color is always red: `Color.fromARGB(255, 208, 0, 0)`
- Theme is toggled by a switch in the drawer (`NavBar`)
- The current theme is saved to device storage under the key `'darkMode'`
- Uses Flutter's Material 3 color system

---

## Data Models — What Fields Each Model Has

These are the Dart model classes in `lib/model/`. They mirror the Firebase data described in the section above.

### Game Models (Dart classes)

**Base fields on every game object (from Firebase → Dart):**
`date`, `team1`, `team2`, `team1score`, `team2score`, `team1activity`, `team2activity`, `team1vote`, `team2vote`, `status` (0/1/2), `statusColor` (computed from status), `team1SourcePath` (logo URL), `link` (stream URL), `voted` (bool — has current user voted?), `GameNum`, `Time`

**Computed voting fields:** `vote1`, `vote2` (raw vote counts), `finalvote1`, `finalvote2`, `percvote1`, `percvote2` (percentages shown in the UI)

See the "Firebase Database: Real Structure" section above for the exact Firebase field names and values.

### Player Models (Dart classes)

| Field | Description |
|-------|-------------|
| `name` | Full player name (used as the Firebase key) |
| `number` | Jersey number |
| `uid` | Firebase user UID — used to link to their account page (optional) |
| `profileImagePath` | URL to profile picture (optional) |

Stat fields are sport-specific — see the Line Ups section above for the exact field names from the real database.

### Team Standings (Dart classes)

| Sport | Real Firebase Fields |
|-------|---------------------|
| Futsal | `GP`, `Wins`, `Draws`, `Losses`, `GS`, `GC`, `GD`, `Points` |
| Basketball | `Wins`, `Losses`, `PCT`, `PPG`, `PCPG`, `PD`, `Points` |
| Flag Football | `Wins`, `Losses`, `Ties`, `PF`, `PA` |
| AFC San Jose | `Wins`, `Draws`, `Losses`, `GF`, `GA` |

### Business (Dart class)

`name`, `description`, `logoUrl`, `logo` (loaded Image widget), `lat`, `long`, `url`, `phone`  
Method: `getMiles(position)` — calculates distance from user's GPS location  
Note: `lat` and `long` are optional in Firebase. Businesses without them appear only in the list, not on the map.

### Event (Dart class)

`title`, `info`, `date` (posted date), `startTime`, `endTime`, `address`, `location`, `imageUrl`, `imageSrc` (loaded Image widget), `buttons`, `attendees` (map of uid → photoUrl)  
Note: There are two date fields — `Date` (when posted) and `EventDate` (when the event happens). The app shows `EventDate`.

### User

`firstName`, `lastName`, `profileURL`  
Extended (`Information`): `age`, `height`, `futsalPosition`, `basketballPosition`, `flagFootballPosition`

### GameActivity (individual action in game log)

Each entry in the game activity feed has: player name, action type (Goal/Assist/TwoPointer/Receiving TD/etc.), team, and the time it happened.

---

## Assets Reference

All image files are in `assets/`. They are bundled into the app.

| File | Used For |
|------|----------|
| `infinite.png` | Small app logo (login screen, about page) |
| `infinitelarge.png` | Large logo (light mode) |
| `infinitelarge_dark.png` | Large logo (dark mode) |
| `infinitelarge_tint.png` | Tinted logo variant |
| `infinitesmall.png` | Tiny logo |
| `infinitesplash.png` | Splash screen logo |
| `scores.png` | Live Scores tab icon |
| `leagues.png` | Leagues tab icon |
| `aroundyou.png` | Around You tab icon |
| `table.png` | Standings button icon |
| `leader.png` | Leaderboard button icon |
| `playerstats.png` | Player stats icon |
| `profile.png` | Profile/drawer icon |
| `events.png` | Events icon |
| `settings.png` | Settings icon |
| `FutsalLeague.png` | Futsal league card image |
| `BasketLeague.png` | Basketball league card image |
| `FlagFootballLeague.png` | Flag Football league card image |
| `goal.png` | Goal action in game activity |
| `assist.png` | Assist action |
| `yellow.png` | Yellow card |
| `blue.png` | Blue card |
| `red.png` | Red card |
| `foul.png` | Foul action |
| `onepointer.png` | Basketball 1-point (free throw) |
| `twopointer.png` | Basketball 2-point |
| `threepointer.png` | Basketball 3-point |
| `rebound.png` | Rebound action |
| `portraitplaceholder.png` | Default profile picture when none uploaded |
| `ninevehware.png` | Developer company logo (settings page) |
| `watch.png` | Live stream watch button |
| `notif.png` | Notification icon |
| `notifnew.png` | Notification with badge icon |

---

## Dependencies (Key Packages)

| Package | What It Does |
|---------|-------------|
| `firebase_core` | Required to initialize Firebase |
| `firebase_database` | Realtime Database reads/writes |
| `firebase_auth` | User sign in and sign up |
| `firebase_storage` | Upload/download profile images |
| `firebase_messaging` | Push notifications from Firebase |
| `flutter_local_notifications` | Show notifications while app is open (foreground) |
| `provider` | Theme state management |
| `shared_preferences` | Save dark mode and auto-sign-in to device |
| `google_maps_flutter` | Google Maps widget |
| `geolocator` | Get user's GPS location |
| `geocoding` | Convert coordinates to address text |
| `data_table_2` | Advanced sortable data tables |
| `flutter_sticky_header` | Sticky section headers in lists |
| `percent_indicator` | Circular/linear progress bars (vote percentages) |
| `material_color_utilities` | Extract colors from team logo images |
| `webview_flutter` | In-app browser (rules, T&Cs, stream) |
| `url_launcher` | Open external URLs, maps, phone calls |
| `share_plus` | Share event/game via phone share sheet |
| `image_picker` | Pick photo from camera or gallery |
| `intl` | Date formatting |
| `email_validator` | Validate email addresses on login/signup |
| `flutter_config` | Load `.env` file (API keys) |
| `flutter_dotenv` | Alternative env file loading |
| `flutter_native_splash` | Splash screen on app launch |

---

## Known Issues (Do Not Change Without Awareness)

1. **Force-unwrap crashes** — Several places use `FirebaseAuth.instance.currentUser!` which will crash if the user gets signed out unexpectedly. Always check `signedIn` first.

2. **Silent errors** — Many `try/catch` blocks catch errors and return empty data without logging. Makes debugging hard. If something is showing blank data, check these catches.

3. **Duplicate navigator key** — Both `current_livescore_navigation.dart` and `leagues_navigation.dart` declare a key named `wishListNavigatorKey`. This is a known bug that hasn't caused a visible problem yet but could.

4. **Empty files** — `lib/leaders.dart` and `lib/model/playerinfo.dart` are empty. Do not delete without confirming they are not imported anywhere.

5. **Date format crashes** — If a date string from Firebase is not exactly 8 characters in `MMDDYYYY` format, the `.substring()` calls will crash the app.

6. **Stale lineup cache** — The cached lineups (`futsalLineups`, etc.) are loaded once and stay until the app restarts. If the roster changes in Firebase, the user won't see it until they restart.

7. **`botnavbar.dart`** — This file exists but is no longer used. The bottom navigation was moved to `main.dart`.

8. **`flutter analyze` may timeout** — The analyzer can be slow on this project. If it times out, that does not mean there are no errors — run it again or check specific files.

---

## Rules For Making Changes Safely

- **Before deleting any file** → ask first. Empty files may still be imported somewhere.
- **Before changing `utility.dart`** → note which screens call the function you're changing. It affects almost every screen.
- **Before changing `scorepage.dart`** → it has complex sport-specific branching. Test all four sports after any change.
- **For Firebase path changes** → the path strings are hardcoded everywhere. A typo means silent empty data, not an error message.
- **For UI changes** → test both light mode and dark mode.
- **For sign-in related changes** → test both signed-in and signed-out states.
- **For date-related changes** → remember dates are `MMDDYYYY` strings, not Date objects.
- **For navigation changes** → remember the app uses nested navigators, so `Navigator.of(context)` may not always reach the top-level navigator. Use `mainContext` when needed.

---

## Related Documents

- [`CLAUDE.md`](CLAUDE.md) — Technical instructions and architecture overview (used by Claude automatically)
- [`PROJECT_REFERENCE.md`](PROJECT_REFERENCE.md) — Plain-language reference created by Codex (May 19, 2026)
- [`README.md`](README.md) — Default Flutter README (minimal content)
- [`pubspec.yaml`](pubspec.yaml) — All package dependencies with version numbers
- [`.env`](.env) — API keys (never commit this to git)
- `C:\Users\zayaa\Downloads\infinite-sports-app-export.json` — Full Firebase Realtime Database export (used to write the "Real Structure" section above). Not in the project folder — stored in Downloads.
