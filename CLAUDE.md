# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Infinite Sports** is a Flutter mobile app for sports leagues and community events. It provides live scores, historical league seasons (Futsal, Basketball, Flag Football, AFC San Jose), local business/event discovery via Google Maps, and user account management with Firebase authentication.

**Current version:** 3.0.0+10
**Minimum SDK:** Dart 3.3.4, Flutter 3.x, Android API 21, iOS 14.0
**App namespace:** com.infinitesports.Infinite_Sports_App

---

## Development Commands

### Build and Run
```bash
flutter run
flutter build apk
flutter build ios
flutter clean
flutter pub get
```

### Testing and Linting
```bash
flutter test
flutter test test/widget_test.dart
flutter analyze
dart format lib/
```

### Dependency Management
```bash
flutter pub outdated
flutter pub upgrade
flutter pub upgrade --major-versions
```

### Environment Setup
The app uses `flutter_config` to load `.env` with API keys:
```
ANDROID_API_KEY=...
IOS_API_KEY=...
GOOGLE_MAPS_API_KEY=...
```

---

## Architecture Overview

### Entry Point and App Structure
**File:** `lib/main.dart`

Startup sequence:
1. Flutter binding initialization
2. Load environment variables via `flutter_config`
3. Initialize Firebase using `lib/firebase_options.dart`
4. Setup push notifications (`lib/misc/pushnotifications.dart`)
5. Restore saved preferences (dark mode, auto-sign-in)
6. Upload Firebase Messaging token if signed in
7. Run `MyApp` → `MyHomePage`

**Main Shell:** `MyHomePage` contains bottom navigation (3 tabs) and a navigation drawer.

### Navigation Structure

The app uses **nested navigators within tabs** rather than a single global router:

- **Tab 0 - Live Scores:** `CurrentLivescoreNavigation` (nested navigator)
  - Entry: `lib/frontpage.dart` (loads current league/season/date)
  - Displays sport-specific tabs with season tabs
  - Pushes to: LiveScorePage, ScorePage (game detail), TablePage, LeaderboardPage

- **Tab 1 - Leagues:** `LeaguesNavigation` (nested navigator)
  - Entry: `lib/leagues.dart` (season list)
  - Pushes season detail pages inside the navigator

- **Tab 2 - Around You:** `lib/aroundyou.dart` (direct widget, no nesting)
  - Google Maps with business/event markers
  - Draggable bottom sheet for listings

**Drawer:** `lib/navbar.dart`
- Login/signup, profile, settings, dark mode, logout
- Uses global `mainContext` from utility.dart for navigation

**Navigation files:**
- `lib/navigations/current_livescore_navigation.dart`
- `lib/navigations/leagues_navigation.dart`

### Centralized State: utility.dart

**File:** `lib/misc/utility.dart` (1169 lines) — **the app's hub for shared state and Firebase operations**

**Global Variables:**
- `signedIn`, `autoSignIn`, `darkModeEnabled` — authentication and theme state
- `mainContext`, `mainScaffoldContext` — global context references
- `headerNotifier` — current sport/season ValueNotifier
- Cached lineups: `futsalLineups`, `basketballLineups`, `flagFootballLineups` (Maps of rosters by season/team)
- `teamLogos` — cached team logo URLs from Firebase Storage
- `auth` — shared `FirebaseAuthService` instance
- `infiniteSportsPrimaryColor` — red theme color (RGB 208, 0, 0)

**Firebase Helper Functions:**
- Season/sport queries: `getCurrentSport()`, `getCurrentSeason()`, `getAFCCurrentSeason()`, `isSeasonFinished()`, `isAFCSeasonFinished()`
- Date handling: `getDates()`, `getCurrentDate()`, `convertDatabaseDateToFormatDate()`, `convertStringDateToDatabase()`, `convertDateToDatabase()`
- Roster caching: `getAllFutsalLineUps()`, `getAllBasketballLineUps()`, `getAllFlagFootballLineUps()`, `getSoccerRoster()` (AFC San Jose)
- Team data: `getAllTeamLogo()` — caches team logos from Firebase Storage
- Signup: `getSignUpStatus()`, `getSeason()`, `getSoccerSeasons()`
- Profile: `uploadToken()`, `setImage()`, `retrieveProfilePic()` — Firebase Auth/Storage operations
- Stats: `getLeaderboard()`, `getTeamStats()` — leader and team stat queries

**Key Pattern:** Many screens depend on this file. Changes here affect multiple screens. Test broadly after modifications.

### Theme and State Management

**Theme:** `lib/misc/theme_provider.dart`
- Uses `Provider` package (ChangeNotifier pattern)
- Stores light/dark `ThemeData` with Material 3 color scheme
- Color scheme uses `ColorScheme.fromSeed` with `infiniteSportsPrimaryColor`
- Persists to `shared_preferences` under key `'darkMode'`

**State Management Approach:**
- Mostly stateful widgets with `setState` for local UI updates
- `Provider` for theme switching (global)
- `shared_preferences` for user preferences persistence
- Firebase Realtime Database listeners trigger manual updates
- No centralized state container (Redux, Riverpod, etc.)

### Firebase Integration

**Project ID:** `infinite-sports-app`

**Configuration:** `lib/firebase_options.dart`
- Loads API keys from `.env` via `flutter_config`
- Separate Android and iOS configurations
- Initialized in `main.dart` before app runs

**Authentication:** `lib/firebase_auth/firebase_auth_services.dart`
- Email/password sign-in only
- Methods: `signUpWithEmailAndPassword()`, `signInWithEmailAndPassword()`, `signOut()`

**Database Paths:**
```
Current League                  (current sport name)
<Sport> Season                 (season number, e.g., "Futsal Season")
<Sport>/<Season>/Date          (game date map)
<Sport>/<Season>/Line Ups      (team rosters)
<Sport>/<Season>/Finished      (boolean season flag)
AFC San Jose/Current Season    (current AFC season)
AFC San Jose/Seasons/<Season>  (AFC season data with rosters)
Logo Urls                      (team logo URL mapping)
Users/<uid>                    (user profile data)
Users/<uid>/Information        (extended user data)
Sign Ups                       (signup forms and status)
Map                            (businesses, events)
Events                         (community events)
```

**Storage:**
- User profile images: `Users/<uid>/profileimage.jpg`
- Team logos: stored as URLs in database

**Messaging:**
- Firebase Cloud Messaging for device tokens
- Token uploaded to user profile on sign-in
- Foreground notifications via `flutter_local_notifications`
- Token refresh listener in `main.dart` re-uploads on change
- Payload handling in `PushNotifications.onNotificationTap()`

### Core Screens

**Large Files (refactor candidates):**
- `lib/scorepage.dart` (1057 lines) — detailed game page with scoreboard, stats, voting, livestream
- `lib/playerpage.dart` (470 lines) — player detail and career stats

**Screen Hierarchy:**
```
FrontPage (current league tabs)
├─ LiveScorePage (games for a date)
│  └─ ScorePage (single game detail)
│     ├─ PlayerPage (player stats)
│     ├─ TablePage (standings)
│     └─ LeaderboardPage (leaders)
├─ ShowLeaguePage (season overview)

LeaguesPage (historical seasons)
└─ ShowLeaguePage (season detail)

AroundYou (Google Maps)
├─ BusinessPage (business detail)
└─ EventPage (event detail)

NavBar (drawer) → Login/Settings/PlayerPage
```

### Data Models

**Location:** `lib/model/`

**Game Models** (implement abstract `Game` interface):
- `game.dart` — base with voting, colors, status
- Sport-specific: `futsalgame.dart`, `basketballgame.dart`, `flagfootballgame.dart`, `soccergame.dart`

**Player and Stats Models:**
- Players: `futsalplayer.dart`, `basketballplayer.dart`, `flagfootballplayer.dart`, `soccerplayer.dart`
- Stats: `playerstats.dart` and sport-specific variants

**Other Models:**
- `myuser.dart`, `userinformation.dart` — user data
- `business.dart`, `event.dart`, `attendee.dart` — community features
- `teaminfo.dart` and variants — team data
- `gameactivity.dart` — game events
- **Empty:** `lib/leaders.dart`, `lib/model/playerinfo.dart`

---

## Important Patterns

### Firebase Data Fetching
```dart
DatabaseReference newClient = FirebaseDatabase.instance.ref("/<path>");
var event = await newClient.child("<subpath>").get();
var data = event.snapshot.value as Map;
```
Most calls wrapped in try-catch with sensible defaults. Errors often silent (logging opportunity).

### Global Context Usage
Screens sometimes use `mainContext` from utility.dart to navigate globally. Makes navigation harder to trace.

### Voting System
Implemented in each game screen. Vote counts stored in Firebase under game data. Duplicated logic across game types (refactor opportunity).

### Team Color Extraction
Colors from team logos extracted using `material_color_utilities` to dynamically theme scoreboards.

### Date Format
Firebase dates stored as `MMDDYYYY` strings (e.g., "05202026"). Helper functions in utility.dart handle conversions.

---

## Testing

**Current coverage:** Minimal (placeholder smoke test only)

**Test file:** `test/widget_test.dart`

**Future targets:**
- Unit tests for date conversion (utility.dart)
- Unit tests for signup status logic
- Widget tests for ScorePage with various game types

---

## Known Issues

- `flutter analyze` can timeout
- Some code uses `FirebaseAuth.instance.currentUser!` (crashes if unexpectedly signed out)
- Duplicate global navigator key: `wishListNavigatorKey` in both navigation files
- Silent error handling makes debugging difficult
- Files `lib/leaders.dart` and `lib/model/playerinfo.dart` are empty

## Refactor Targets (Not Urgent)

1. **Split utility.dart** into: Firebase data layer, auth service, preference helpers
2. **Split scorepage.dart** into smaller widgets
3. **Consolidate voting logic** across game types
4. **Add logging** instead of silent catches
5. **Fix flutter_config dependency** (currently `git://`, consider HTTPS)
6. **Reduce global context usage** — pass context through widget tree

---

## Dependencies

**Firebase:** `firebase_core: ^4.2.1`, `firebase_database: ^12.0.4`, `firebase_auth: ^6.1.2`, `firebase_storage: ^13.0.4`, `firebase_messaging: ^16.0.4`

**UI/State:** `provider: ^6.1.2`, `shared_preferences: ^2.3.2`, `percent_indicator: ^4.2.3`, `data_table_2: ^2.5.15`, `flutter_sticky_header: ^0.8.0`

**Maps/Location:** `google_maps_flutter: ^2.9.0`, `geolocator: ^14.0.2`, `geocoding: ^4.0.0`

**Notifications:** `flutter_local_notifications: ^19.5.0`

**Web/Content:** `webview_flutter: ^4.8.0`, `url_launcher: ^6.3.0`, `share_plus: ^12.0.1`

**Config/Images:** `flutter_config` (Git URL), `flutter_dotenv: ^6.0.0`, `image_picker: ^1.1.2`

**Other:** `intl: ^0.20.2`, `email_validator: ^3.0.0`, `material_color_utilities: ^0.13.0`

---

## Platform-Specific Setup

**Android:** Min SDK 21, Compile SDK 36, Kotlin enabled, google-services.json required
**iOS:** Deployment target 14.0, use Runner.xcworkspace (CocoaPods)
**Both:** Require API keys in `.env` and Firebase config from `lib/firebase_options.dart`

---

## Quick Reference

| Task | File(s) |
|------|---------|
| Startup, bottom nav | `lib/main.dart` |
| Live Scores tab | `lib/frontpage.dart`, `lib/livescore.dart`, `lib/scorepage.dart` |
| Game detail (largest) | `lib/scorepage.dart` |
| Leagues tab | `lib/leagues.dart`, `lib/navigations/leagues_navigation.dart` |
| Around You tab | `lib/aroundyou.dart`, `lib/businesspage.dart`, `lib/eventpage.dart` |
| Account/drawer | `lib/navbar.dart`, `lib/login.dart`, `lib/settings.dart` |
| Signup flow | `lib/signup.dart`, `lib/leagueform.dart` |
| Theme | `lib/misc/theme_provider.dart` |
| Shared state | `lib/misc/utility.dart` |
| Firebase auth | `lib/firebase_auth/firebase_auth_services.dart` |
| Notifications | `lib/misc/pushnotifications.dart` |
| Models | `lib/model/` |
| Tests | `test/widget_test.dart` |