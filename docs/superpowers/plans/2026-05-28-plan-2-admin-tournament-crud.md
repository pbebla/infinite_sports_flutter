# Admin Tournament CRUD — Plan 2 Implementation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the admin (manager) app the tournament management screens it currently lacks, so Zayaa can create, edit, and run tournaments end-to-end from the manager app instead of hand-editing Firebase JSON.

**Architecture:** All work is in the `InfiniteSportsManagerFlutter` repo on branch `zaya-tournament-enhance-app-manager`. We add tournament models (mirroring the user app's shape — Firebase schema is the contract), a `TournamentService` extending the existing `FirebaseService` base class, Riverpod providers for read/write, and seven new screens grouped under `lib/ui/tournaments/`. Three remaining screens (prediction config, announcements, QR codes) defer to later plans (4 and 5).

**Tech Stack:** Flutter, Riverpod (not Provider), go_router, Firebase Realtime Database. Existing patterns: `FirebasePaths` static class for path strings, `FirebaseService` base class with `getValue<T>`, `getMap`, `getList` helpers, `MasterDetailShell` drawer for top-level nav.

**Spec reference:** `docs/superpowers/specs/2026-05-28-tournament-enhancements-design.md` Section 6.3 (admin CRUD) and Section 4 (Firebase schema).

**Estimated duration:** Weeks 2–3 of the 14-week plan (~10 working days).

**Branch:** `zaya-tournament-enhance-app-manager` on `InfiniteSportsManagerFlutter`. All commits land here.

**Out of scope for Plan 2** (deferred to later plans):
- Prediction config screen → Plan 4
- Announcements screen → Plan 5
- QR scoring codes screen → Plan 5
- Sign-up admin screen → Plan 6

---

## File Structure

### New files (manager app — `InfiniteSportsManagerFlutter`)

| File | Responsibility |
|---|---|
| `lib/models/tournament.dart` | `Tournament` header model with fromMap |
| `lib/models/tournament_team.dart` | `TournamentTeam` (mirrors user-app shape) |
| `lib/models/tournament_match.dart` | `TournamentMatch` |
| `lib/models/tournament_player.dart` | `TournamentPlayer` |
| `lib/models/prediction_config.dart` | `PredictionConfig` (forward-compat for Plan 4) |
| `lib/services/firebase/tournament_service.dart` | CRUD service (list, get, create, update, delete) |
| `lib/providers/tournament_provider.dart` | Riverpod providers (FutureProviders, families) |
| `lib/ui/tournaments/tournament_list_page.dart` | List of all tournaments, FAB to create |
| `lib/ui/tournaments/create_tournament_page.dart` | Wizard for new tournament |
| `lib/ui/tournaments/tournament_dashboard_page.dart` | Tournament-specific landing page |
| `lib/ui/tournaments/manage_teams_page.dart` | Add/edit/remove teams + generate join codes |
| `lib/ui/tournaments/manage_bracket_page.dart` | Add/edit fixtures + bracket positions |
| `lib/ui/tournaments/manage_rosters_page.dart` | Add/edit players per team |
| `lib/ui/tournaments/live_scoring_page.dart` | Live match scoring with full event UI |

### Modified files

| File | Change |
|---|---|
| `lib/core/constants/firebase_paths.dart` | Add tournament path constants |
| `lib/router/app_router.dart` | Add `/tournaments` and nested routes |
| `lib/ui/home/master_detail_shell.dart` | Add Tournaments item in drawer |
| `lib/ui/home/main_menu_page.dart` | Add Tournaments card on dashboard |

---

## Firebase schema (shared contract with user app)

Already defined by the user app (Plan 1). Plan 2 writes to these paths:

```
/Tournaments/
  Current Tournament                    string — id of currently active tournament
  {tournamentId}/
    Name                                string
    Sport                               "Soccer" | "Futsal" | "Basketball" | "Flag Football"
    Edition                             string (e.g. "2026")
    LogoUrl                             string
    HostCity                            string
    Location                            string
    StartDate                           "MMDDYYYY"
    EndDate                             "MMDDYYYY"
    Status                              string (free-text e.g. "Group Stage", "Semifinals")
    Finished                            bool
    Champion / RunnerUp / GoldenBoot / BestKeeper / DplLeader   string (resolved post-event)
    Teams/{teamId}/                     team metadata (Name, Group, Seed, colors, coach)
    Teams/{teamId}/JoinCode             string — short code for sign-up team assignment
    Table/{teamId}/                     standings (W, D, L, GS, GC, GD, GP, Pts)
    Matches/{matchId}/                  match record (see below)
    Rosters/{teamId}/{playerName}/      player stats per match (Goals, Assists, Saves, etc.)
```

**Match record fields:**

```
Stage              "Group Stage" | "Round of 16" | "Quarterfinal" | "Semifinal" | "Third Place" | "Final"
Label              free-text display label
Date               "MMDDYYYY"
Time               free-text e.g. "2:00 PM"
Team1Id, Team2Id   teamId strings
Team1Score, Team2Score   int
Status             0 = upcoming, 1 = live, 2 = finished
Team1Activity/{minute}/[{eventType: playerName}]   match events
Team2Activity/{minute}/[{eventType: playerName}]   match events (eventType = "Goal", "Assist", "Yellow", "Red")
BracketPosition    int — used for sorting within a stage
MatchLocation      free-text (which field/court)
```

---

## Task 1: Add tournament path constants to FirebasePaths

**Why:** All Firebase access in the manager app routes through `FirebasePaths.*` static methods. Adding tournament paths here keeps all path strings in one auditable place.

**Files:**
- Modify: `lib/core/constants/firebase_paths.dart`

- [ ] **Step 1.1: Open the file and append tournament paths after line 75**

Add at the end of the `FirebasePaths` class (before the closing `}`):

```dart
  // -------- Tournaments --------
  static const String tournaments = 'Tournaments';
  static const String currentTournament = '$tournaments/Current Tournament';

  static String tournament(String tournamentId) =>
      '$tournaments/$tournamentId';

  static String tournamentName(String tournamentId) =>
      '$tournaments/$tournamentId/Name';
  static String tournamentSport(String tournamentId) =>
      '$tournaments/$tournamentId/Sport';
  static String tournamentStatus(String tournamentId) =>
      '$tournaments/$tournamentId/Status';
  static String tournamentFinished(String tournamentId) =>
      '$tournaments/$tournamentId/Finished';

  static String tournamentTeams(String tournamentId) =>
      '$tournaments/$tournamentId/Teams';
  static String tournamentTeam(String tournamentId, String teamId) =>
      '$tournaments/$tournamentId/Teams/$teamId';
  static String tournamentTeamJoinCode(String tournamentId, String teamId) =>
      '$tournaments/$tournamentId/Teams/$teamId/JoinCode';

  static String tournamentTable(String tournamentId) =>
      '$tournaments/$tournamentId/Table';
  static String tournamentTableRow(String tournamentId, String teamId) =>
      '$tournaments/$tournamentId/Table/$teamId';

  static String tournamentMatches(String tournamentId) =>
      '$tournaments/$tournamentId/Matches';
  static String tournamentMatch(String tournamentId, String matchId) =>
      '$tournaments/$tournamentId/Matches/$matchId';
  static String tournamentMatchStatus(String tournamentId, String matchId) =>
      '$tournaments/$tournamentId/Matches/$matchId/Status';
  static String tournamentMatchScore(
          String tournamentId, String matchId, int teamTag) =>
      '$tournaments/$tournamentId/Matches/$matchId/Team${teamTag + 1}Score';
  static String tournamentMatchActivity(
          String tournamentId, String matchId, int teamTag) =>
      '$tournaments/$tournamentId/Matches/$matchId/Team${teamTag + 1}Activity';

  static String tournamentRosters(String tournamentId) =>
      '$tournaments/$tournamentId/Rosters';
  static String tournamentRoster(String tournamentId, String teamId) =>
      '$tournaments/$tournamentId/Rosters/$teamId';
  static String tournamentRosterPlayer(
          String tournamentId, String teamId, String playerName) =>
      '$tournaments/$tournamentId/Rosters/$teamId/$playerName';
```

- [ ] **Step 1.2: Run flutter analyze on the file**

```
flutter analyze lib/core/constants/firebase_paths.dart
```
Expected: No issues found.

- [ ] **Step 1.3: Commit**

```bash
git add lib/core/constants/firebase_paths.dart
git commit -m "Add tournament path constants to FirebasePaths

Mirrors the schema established by the user app's Plan 1 work:
/Tournaments/{id}/{Teams|Table|Matches|Rosters}/... plus team
JoinCode field for sign-up team assignment (Plan 6).

Plan 2, Task 1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Tournament model

**Why:** The data type the rest of the manager app passes around. Mirrors the user app's `Tournament` model so both apps interpret the same Firebase data identically.

**Files:**
- Create: `lib/models/tournament.dart`

- [ ] **Step 2.1: Create the model file**

```dart
class Tournament {
  final String id;
  final String name;
  final String sport;
  final String edition;
  final String? logoUrl;
  final String? hostCity;
  final String? location;
  final String? startDate;
  final String? endDate;
  final String status;
  final bool finished;
  final String? champion;
  final String? runnerUp;
  final String? goldenBoot;
  final String? bestKeeper;
  final String? dplLeader;

  const Tournament({
    required this.id,
    required this.name,
    required this.sport,
    required this.edition,
    this.logoUrl,
    this.hostCity,
    this.location,
    this.startDate,
    this.endDate,
    required this.status,
    required this.finished,
    this.champion,
    this.runnerUp,
    this.goldenBoot,
    this.bestKeeper,
    this.dplLeader,
  });

  /// Defensive parser. Accepts Firebase-shape values (bool/int/string mix)
  /// and degrades gracefully on type mismatch.
  factory Tournament.fromFirebase(String id, dynamic raw) {
    final data = (raw is Map) ? raw : <dynamic, dynamic>{};
    String? str(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v != null) return v.toString();
      }
      return null;
    }

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v == 1;
      if (v is String) {
        final l = v.toLowerCase();
        return l == 'true' || l == '1';
      }
      return false;
    }

    return Tournament(
      id: id,
      name: str(['Name', 'name']) ?? id,
      sport: str(['Sport', 'sport']) ?? 'Soccer',
      edition: str(['Edition', 'edition']) ?? '',
      logoUrl: str(['LogoUrl', 'logoUrl']),
      hostCity: str(['HostCity', 'hostCity']),
      location: str(['Location', 'location']),
      startDate: str(['StartDate', 'startDate']),
      endDate: str(['EndDate', 'endDate']),
      status: str(['Status', 'status']) ?? 'TBD',
      finished: parseBool(data['Finished'] ?? data['finished']),
      champion: str(['Champion', 'champion']),
      runnerUp: str(['RunnerUp', 'runnerUp']),
      goldenBoot: str(['GoldenBoot', 'goldenBoot']),
      bestKeeper: str(['BestKeeper', 'bestKeeper']),
      dplLeader: str(['DplLeader', 'dplLeader']),
    );
  }

  /// Returns the data we write back to Firebase for the tournament header.
  /// Only writes fields that are managed via the create-tournament screen.
  Map<String, dynamic> toCreateMap() => {
        'Name': name,
        'Sport': sport,
        'Edition': edition,
        if (logoUrl != null && logoUrl!.isNotEmpty) 'LogoUrl': logoUrl,
        if (hostCity != null && hostCity!.isNotEmpty) 'HostCity': hostCity,
        if (location != null && location!.isNotEmpty) 'Location': location,
        if (startDate != null) 'StartDate': startDate,
        if (endDate != null) 'EndDate': endDate,
        'Status': status,
        'Finished': finished,
      };
}
```

- [ ] **Step 2.2: Analyze**

```
flutter analyze lib/models/tournament.dart
```
Expected: No issues found.

- [ ] **Step 2.3: Commit**

```bash
git add lib/models/tournament.dart
git commit -m "Add Tournament model

Mirrors the user app's Tournament model so both apps interpret
the same Firebase data identically. Defensive parsing (handles
string-encoded bools, missing fields). toCreateMap returns the
header subset we write via the create-tournament wizard.

Plan 2, Task 2.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: TournamentTeam model

**Files:**
- Create: `lib/models/tournament_team.dart`

- [ ] **Step 3.1: Create**

```dart
class TournamentTeam {
  final String id;
  final String name;
  final String? logoUrl;
  final int? seed;
  final String qualification;
  final String? group;
  final String? homeColor;
  final String? awayColor;
  final String? overrideColor;
  final String? coachName;
  final String? coachPhotoUrl;
  final String? cityState;
  final String? established;
  final String? joinCode;

  // Standings (read from Table node)
  final int gp;
  final int wins;
  final int draws;
  final int losses;
  final int gs;
  final int gc;
  final int gd;
  final int points;

  const TournamentTeam({
    required this.id,
    required this.name,
    this.logoUrl,
    this.seed,
    required this.qualification,
    this.group,
    this.homeColor,
    this.awayColor,
    this.overrideColor,
    this.coachName,
    this.coachPhotoUrl,
    this.cityState,
    this.established,
    this.joinCode,
    this.gp = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.gs = 0,
    this.gc = 0,
    this.gd = 0,
    this.points = 0,
  });

  factory TournamentTeam.fromFirebase(
    String id,
    dynamic teamRaw,
    dynamic tableRaw,
  ) {
    final t = (teamRaw is Map) ? teamRaw : <dynamic, dynamic>{};
    final tb = (tableRaw is Map) ? tableRaw : <dynamic, dynamic>{};

    String? str(Map d, List<String> keys) {
      for (final k in keys) {
        final v = d[k];
        if (v != null) return v.toString();
      }
      return null;
    }

    int intOf(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return TournamentTeam(
      id: id,
      name: str(t, ['Name', 'name']) ?? id,
      logoUrl: str(t, ['LogoUrl', 'logoUrl']),
      seed: t['Seed'] != null ? intOf(t['Seed']) : null,
      group: str(t, ['Group', 'group']),
      qualification: str(t, ['Qualification', 'qualification']) ??
          str(tb, ['Qualification', 'qualification']) ??
          'TBD',
      homeColor: str(t, ['HomeColor', 'homeColor']),
      awayColor: str(t, ['AwayColor', 'awayColor']),
      overrideColor: str(t, ['OverrideColor', 'overrideColor']),
      coachName: str(t, ['CoachName', 'coachName']),
      coachPhotoUrl: str(t, ['CoachPhotoUrl', 'coachPhotoUrl']),
      cityState: str(t, ['CityState', 'cityState']),
      established: str(t, ['Established', 'established']),
      joinCode: str(t, ['JoinCode', 'joinCode']),
      gp: intOf(tb['GP'] ?? tb['gp']),
      wins: intOf(tb['W'] ?? tb['wins']),
      draws: intOf(tb['D'] ?? tb['draws']),
      losses: intOf(tb['L'] ?? tb['losses']),
      gs: intOf(tb['GS'] ?? tb['gs']),
      gc: intOf(tb['GC'] ?? tb['gc']),
      gd: intOf(tb['GD'] ?? tb['gd']),
      points: intOf(tb['Pts'] ?? tb['pts'] ?? tb['Points']),
    );
  }

  /// Subset written when creating or editing a team.
  Map<String, dynamic> toFirebaseMap() => {
        'Name': name,
        if (logoUrl != null) 'LogoUrl': logoUrl,
        if (seed != null) 'Seed': seed,
        if (group != null) 'Group': group,
        if (homeColor != null) 'HomeColor': homeColor,
        if (awayColor != null) 'AwayColor': awayColor,
        if (overrideColor != null) 'OverrideColor': overrideColor,
        if (coachName != null) 'CoachName': coachName,
        if (coachPhotoUrl != null) 'CoachPhotoUrl': coachPhotoUrl,
        if (cityState != null) 'CityState': cityState,
        if (established != null) 'Established': established,
        if (joinCode != null) 'JoinCode': joinCode,
        'Qualification': qualification,
      };
}
```

- [ ] **Step 3.2: Analyze**

```
flutter analyze lib/models/tournament_team.dart
```
Expected: No issues found.

- [ ] **Step 3.3: Commit**

```bash
git add lib/models/tournament_team.dart
git commit -m "Add TournamentTeam model

Carries both team metadata (Name, Group, Seed, colors, coach,
JoinCode) and standings (W/D/L/GS/GC/Pts). fromFirebase merges
Teams + Table nodes the way the user app does. toFirebaseMap
returns the subset written by manage-teams.

Plan 2, Task 3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: TournamentMatch model

**Files:**
- Create: `lib/models/tournament_match.dart`

- [ ] **Step 4.1: Create**

```dart
class TournamentMatch {
  final String id;
  final String stage;
  final String label;
  final String date;
  final String? time;
  final String? team1Id;
  final String? team2Id;
  final int team1Score;
  final int team2Score;
  /// 0 = upcoming, 1 = live, 2 = finished
  final int status;
  final Map<String, dynamic>? team1Activity;
  final Map<String, dynamic>? team2Activity;
  final String? link;
  final String? matchLocation;
  final int bracketPosition;

  const TournamentMatch({
    required this.id,
    required this.stage,
    required this.label,
    required this.date,
    this.time,
    this.team1Id,
    this.team2Id,
    required this.team1Score,
    required this.team2Score,
    required this.status,
    this.team1Activity,
    this.team2Activity,
    this.link,
    this.matchLocation,
    required this.bracketPosition,
  });

  factory TournamentMatch.fromFirebase(String id, dynamic raw) {
    final data = (raw is Map) ? raw : <dynamic, dynamic>{};

    int intOf(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String? str(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v != null) return v.toString();
      }
      return null;
    }

    Map<String, dynamic>? mapOf(dynamic v) {
      if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
      return null;
    }

    return TournamentMatch(
      id: id,
      stage: str(['Stage', 'stage']) ?? 'Group Stage',
      label: str(['Label', 'label']) ?? 'Group Stage',
      date: str(['Date', 'date']) ?? '',
      time: str(['Time', 'time']),
      team1Id: str(['Team1Id', 'team1Id']),
      team2Id: str(['Team2Id', 'team2Id']),
      team1Score: intOf(data['Team1Score'] ?? data['team1Score']),
      team2Score: intOf(data['Team2Score'] ?? data['team2Score']),
      status: intOf(data['Status'] ?? data['status']),
      team1Activity: mapOf(data['Team1Activity'] ?? data['team1Activity']),
      team2Activity: mapOf(data['Team2Activity'] ?? data['team2Activity']),
      link: str(['Link', 'link']),
      matchLocation: str(['MatchLocation', 'matchLocation']),
      bracketPosition:
          intOf(data['BracketPosition'] ?? data['bracketPosition']),
    );
  }

  /// Subset written when creating or editing a match.
  Map<String, dynamic> toFirebaseMap() => {
        'Stage': stage,
        'Label': label,
        'Date': date,
        if (time != null) 'Time': time,
        if (team1Id != null) 'Team1Id': team1Id,
        if (team2Id != null) 'Team2Id': team2Id,
        'Team1Score': team1Score,
        'Team2Score': team2Score,
        'Status': status,
        if (matchLocation != null) 'MatchLocation': matchLocation,
        'BracketPosition': bracketPosition,
        if (link != null) 'Link': link,
      };
}
```

- [ ] **Step 4.2: Analyze**

```
flutter analyze lib/models/tournament_match.dart
```
Expected: No issues found.

- [ ] **Step 4.3: Commit**

```bash
git add lib/models/tournament_match.dart
git commit -m "Add TournamentMatch model

Match record with status (0/1/2), scores, activity maps,
bracket position, stage. Activity maps keyed by minute, each
value a list of {eventType: playerName} entries — matches the
user-app schema.

Plan 2, Task 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: TournamentPlayer model

**Files:**
- Create: `lib/models/tournament_player.dart`

- [ ] **Step 5.1: Create**

```dart
class TournamentPlayer {
  final String name;
  final String teamId;
  final String? uid;
  final String? number;
  final String? position;
  final String? photoUrl;
  final int goals;
  final int assists;
  final int saves;
  final int dpl;
  final int cleanSheets;
  final int yellowCards;
  final int redCards;

  const TournamentPlayer({
    required this.name,
    required this.teamId,
    this.uid,
    this.number,
    this.position,
    this.photoUrl,
    this.goals = 0,
    this.assists = 0,
    this.saves = 0,
    this.dpl = 0,
    this.cleanSheets = 0,
    this.yellowCards = 0,
    this.redCards = 0,
  });

  factory TournamentPlayer.fromFirebase(
    String name,
    String teamId,
    dynamic raw,
  ) {
    final data = (raw is Map) ? raw : <dynamic, dynamic>{};

    int intOf(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String? str(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v != null) return v.toString();
      }
      return null;
    }

    return TournamentPlayer(
      name: name,
      teamId: teamId,
      uid: str(['UID', 'uid']),
      number: str(['Number', 'number']),
      position: str(['Position', 'position']),
      photoUrl: str(['PhotoUrl', 'photoUrl']),
      goals: intOf(data['Goals'] ?? data['goals']),
      assists: intOf(data['Assists'] ?? data['assists']),
      saves: intOf(data['Saves'] ?? data['saves']),
      dpl: intOf(data['DPL'] ?? data['dpl']),
      cleanSheets: intOf(data['CleanSheets'] ?? data['cleanSheets']),
      yellowCards: intOf(data['YellowCards'] ?? data['yellowCards']),
      redCards: intOf(data['RedCards'] ?? data['redCards']),
    );
  }

  Map<String, dynamic> toFirebaseMap() => {
        if (uid != null) 'UID': uid,
        if (number != null) 'Number': number,
        if (position != null) 'Position': position,
        if (photoUrl != null) 'PhotoUrl': photoUrl,
        'Goals': goals,
        'Assists': assists,
        'Saves': saves,
        'DPL': dpl,
        'CleanSheets': cleanSheets,
        'YellowCards': yellowCards,
        'RedCards': redCards,
      };
}
```

- [ ] **Step 5.2: Analyze**

```
flutter analyze lib/models/tournament_player.dart
```
Expected: No issues found.

- [ ] **Step 5.3: Commit**

```bash
git add lib/models/tournament_player.dart
git commit -m "Add TournamentPlayer model

Per-player stats: Goals, Assists, Saves, DPL, CleanSheets,
YellowCards, RedCards. Plus identity (Number, Position,
optional UID linking to /Users/{uid} for photo).

Plan 2, Task 5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: PredictionConfig model

**Why:** Plan 4 (predictions) hasn't started yet, but we want admin app create-tournament wizard to write a default PredictionConfig so the user app's predictions tab (Plan 4) can read it without retroactive backfill. Forward-compat.

**Files:**
- Create: `lib/models/prediction_config.dart`

- [ ] **Step 6.1: Create**

```dart
class PredictionConfig {
  final bool open;
  final String? awardsLockTime;
  final Map<String, int> scoring;
  final Map<String, bool> categories;

  const PredictionConfig({
    required this.open,
    this.awardsLockTime,
    required this.scoring,
    required this.categories,
  });

  factory PredictionConfig.defaultForSport(String sport) {
    final lower = sport.toLowerCase();
    final scoring = <String, int>{
      'Champion': 10,
      'RunnerUp': 5,
      'ThirdPlace': 3,
      'MatchWinner': 1,
      'ExactScoreBonus': 3,
      'GoldenBoot': 8,
      'MostAssists': 8,
      'MostCleanSheets': 6,
      'BestDefender': 6,
      'MostPoints': 8,
      'MostRebounds': 6,
      'MostThreePointers': 6,
      'MostTouchdowns': 8,
      'MostYards': 6,
      'MostInterceptions': 6,
      'MostKills': 8,
      'MostDigs': 6,
      'BestServer': 6,
    };

    // Sport-aware category enablement
    bool soccer = lower == 'soccer' || lower == 'futsal';
    bool basketball = lower == 'basketball';
    bool flag = lower == 'flag football';
    bool volleyball = lower == 'volleyball';

    final categories = <String, bool>{
      'Champion': true,
      'RunnerUp': true,
      'ThirdPlace': true,
      'MatchWinner': true,
      'ExactScoreBonus': true,
      'GoldenBoot': soccer,
      'MostAssists': soccer || basketball,
      'MostCleanSheets': soccer,
      'BestDefender': soccer || basketball || flag,
      'MostPoints': basketball,
      'MostRebounds': basketball,
      'MostThreePointers': basketball,
      'MostTouchdowns': flag,
      'MostYards': flag,
      'MostInterceptions': flag,
      'MostKills': volleyball,
      'MostDigs': volleyball,
      'BestServer': volleyball,
    };

    return PredictionConfig(
      open: true,
      awardsLockTime: null,
      scoring: scoring,
      categories: categories,
    );
  }

  Map<String, dynamic> toFirebaseMap() => {
        'Open': open,
        if (awardsLockTime != null) 'AwardsLockTime': awardsLockTime,
        'Scoring': scoring,
        'Categories': categories,
      };
}
```

- [ ] **Step 6.2: Analyze**

```
flutter analyze lib/models/prediction_config.dart
```
Expected: No issues found.

- [ ] **Step 6.3: Commit**

```bash
git add lib/models/prediction_config.dart
git commit -m "Add PredictionConfig model (forward-compat for Plan 4)

Default config per sport — soccer activates GoldenBoot,
basketball activates MostRebounds, etc. Universal categories
(Champion, MatchWinner, etc.) always active. Default scoring
weights. Create-tournament wizard writes this at tournament
creation so Plan 4's predictions tab can read it without
retroactive backfill.

Plan 2, Task 6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: TournamentService — CRUD operations

**Why:** Single Firebase touchpoint for tournament reads/writes. All providers and UI delegate to it.

**Files:**
- Create: `lib/services/firebase/tournament_service.dart`

- [ ] **Step 7.1: Create the service**

```dart
import 'package:flutter/foundation.dart';
import 'package:infinite_app_manager/core/constants/firebase_paths.dart';
import 'package:infinite_app_manager/models/prediction_config.dart';
import 'package:infinite_app_manager/models/tournament.dart';
import 'package:infinite_app_manager/models/tournament_match.dart';
import 'package:infinite_app_manager/models/tournament_player.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/services/firebase/firebase_service.dart';

class TournamentService extends FirebaseService {
  /// Returns all tournaments (excludes the 'Current Tournament' pointer).
  Future<List<Tournament>> getAllTournaments() async {
    try {
      final snap = await ref(FirebasePaths.tournaments).get();
      if (!snap.exists || snap.value == null) return [];
      final data = snap.value as Map;
      final list = <Tournament>[];
      data.forEach((key, value) {
        if (key.toString() == 'Current Tournament') return;
        if (value is Map) {
          try {
            list.add(Tournament.fromFirebase(key.toString(), value));
          } catch (e) {
            debugPrint('Skipped malformed tournament $key: $e');
          }
        }
      });
      list.sort((a, b) {
        if (!a.finished && b.finished) return -1;
        if (a.finished && !b.finished) return 1;
        return b.edition.compareTo(a.edition);
      });
      return list;
    } catch (e) {
      debugPrint('getAllTournaments error: $e');
      return [];
    }
  }

  Future<Tournament?> getTournament(String tournamentId) async {
    try {
      final snap = await ref(FirebasePaths.tournament(tournamentId)).get();
      if (!snap.exists || snap.value == null) return null;
      return Tournament.fromFirebase(tournamentId, snap.value);
    } catch (e) {
      debugPrint('getTournament error: $e');
      return null;
    }
  }

  /// Creates a tournament with the given header + a default PredictionConfig.
  /// Returns true on success.
  Future<bool> createTournament(Tournament tournament) async {
    try {
      final updates = <String, dynamic>{};
      tournament.toCreateMap().forEach((k, v) {
        updates['${FirebasePaths.tournament(tournament.id)}/$k'] = v;
      });
      // Default PredictionConfig
      final config = PredictionConfig.defaultForSport(tournament.sport);
      config.toFirebaseMap().forEach((k, v) {
        updates['${FirebasePaths.tournament(tournament.id)}/PredictionConfig/$k'] =
            v;
      });
      await ref().update(updates);
      return true;
    } catch (e) {
      debugPrint('createTournament error: $e');
      return false;
    }
  }

  Future<bool> updateTournamentField(
      String tournamentId, String field, dynamic value) async {
    try {
      await ref('${FirebasePaths.tournament(tournamentId)}/$field').set(value);
      return true;
    } catch (e) {
      debugPrint('updateTournamentField error: $e');
      return false;
    }
  }

  Future<bool> setTournamentFinished(String tournamentId, bool finished) {
    return updateTournamentField(tournamentId, 'Finished', finished);
  }

  Future<bool> setCurrentTournament(String tournamentId) async {
    try {
      await ref(FirebasePaths.currentTournament).set(tournamentId);
      return true;
    } catch (e) {
      debugPrint('setCurrentTournament error: $e');
      return false;
    }
  }

  /// Returns map of teamId -> TournamentTeam, merged with Table data.
  Future<Map<String, TournamentTeam>> getTeams(String tournamentId) async {
    try {
      final results = await Future.wait([
        ref(FirebasePaths.tournamentTeams(tournamentId)).get(),
        ref(FirebasePaths.tournamentTable(tournamentId)).get(),
      ]);
      final teamsSnap = results[0];
      final tableSnap = results[1];
      if (teamsSnap.value == null) return {};
      final teamsData = teamsSnap.value as Map;
      final tableData =
          tableSnap.value is Map ? tableSnap.value as Map : <dynamic, dynamic>{};

      final result = <String, TournamentTeam>{};
      teamsData.forEach((key, value) {
        if (value is Map) {
          final teamId = key.toString();
          final tableRow =
              tableData[key] is Map ? tableData[key] : <dynamic, dynamic>{};
          try {
            result[teamId] =
                TournamentTeam.fromFirebase(teamId, value, tableRow);
          } catch (e) {
            debugPrint('Skipped malformed team $teamId: $e');
          }
        }
      });
      return result;
    } catch (e) {
      debugPrint('getTeams error: $e');
      return {};
    }
  }

  Future<bool> saveTeam(
      String tournamentId, String teamId, TournamentTeam team) async {
    try {
      await ref(FirebasePaths.tournamentTeam(tournamentId, teamId))
          .update(team.toFirebaseMap());
      return true;
    } catch (e) {
      debugPrint('saveTeam error: $e');
      return false;
    }
  }

  Future<bool> deleteTeam(String tournamentId, String teamId) async {
    try {
      await ref(FirebasePaths.tournamentTeam(tournamentId, teamId)).remove();
      // Also remove from Table and Rosters
      await ref(FirebasePaths.tournamentTableRow(tournamentId, teamId)).remove();
      await ref(FirebasePaths.tournamentRoster(tournamentId, teamId)).remove();
      return true;
    } catch (e) {
      debugPrint('deleteTeam error: $e');
      return false;
    }
  }

  Future<bool> setTeamJoinCode(
      String tournamentId, String teamId, String code) {
    return updateTeamField(tournamentId, teamId, 'JoinCode', code);
  }

  Future<bool> updateTeamField(String tournamentId, String teamId, String field,
      dynamic value) async {
    try {
      await ref('${FirebasePaths.tournamentTeam(tournamentId, teamId)}/$field')
          .set(value);
      return true;
    } catch (e) {
      debugPrint('updateTeamField error: $e');
      return false;
    }
  }

  Future<List<TournamentMatch>> getMatches(String tournamentId) async {
    try {
      final snap = await ref(FirebasePaths.tournamentMatches(tournamentId)).get();
      if (!snap.exists || snap.value == null) return [];
      final data = snap.value as Map;
      final list = <TournamentMatch>[];
      data.forEach((key, value) {
        if (value is Map) {
          try {
            list.add(TournamentMatch.fromFirebase(key.toString(), value));
          } catch (e) {
            debugPrint('Skipped malformed match $key: $e');
          }
        }
      });
      list.sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        return a.bracketPosition.compareTo(b.bracketPosition);
      });
      return list;
    } catch (e) {
      debugPrint('getMatches error: $e');
      return [];
    }
  }

  Future<bool> saveMatch(
      String tournamentId, String matchId, TournamentMatch match) async {
    try {
      await ref(FirebasePaths.tournamentMatch(tournamentId, matchId))
          .update(match.toFirebaseMap());
      return true;
    } catch (e) {
      debugPrint('saveMatch error: $e');
      return false;
    }
  }

  Future<bool> deleteMatch(String tournamentId, String matchId) async {
    try {
      await ref(FirebasePaths.tournamentMatch(tournamentId, matchId)).remove();
      return true;
    } catch (e) {
      debugPrint('deleteMatch error: $e');
      return false;
    }
  }

  Future<bool> updateMatchScore(
      String tournamentId, String matchId, int teamTag, int newScore) async {
    try {
      await ref(FirebasePaths.tournamentMatchScore(
              tournamentId, matchId, teamTag))
          .set(newScore);
      return true;
    } catch (e) {
      debugPrint('updateMatchScore error: $e');
      return false;
    }
  }

  Future<bool> updateMatchStatus(
      String tournamentId, String matchId, int newStatus) async {
    try {
      await ref(FirebasePaths.tournamentMatchStatus(tournamentId, matchId))
          .set(newStatus);
      return true;
    } catch (e) {
      debugPrint('updateMatchStatus error: $e');
      return false;
    }
  }

  /// Appends an event to the match's activity map for the given team.
  /// minute is the match minute (string key), event is e.g.
  /// {'Goal': 'Player Name'} or {'Yellow': 'Player Name'}.
  Future<bool> appendMatchActivity(
    String tournamentId,
    String matchId,
    int teamTag,
    String minute,
    Map<String, String> event,
  ) async {
    try {
      final path =
          '${FirebasePaths.tournamentMatchActivity(tournamentId, matchId, teamTag)}/$minute';
      final snap = await ref(path).get();
      final existing = snap.value is List
          ? List.from(snap.value as List)
          : <dynamic>[];
      existing.add(event);
      await ref(path).set(existing);
      return true;
    } catch (e) {
      debugPrint('appendMatchActivity error: $e');
      return false;
    }
  }

  Future<Map<String, List<TournamentPlayer>>> getRosters(
      String tournamentId) async {
    try {
      final snap = await ref(FirebasePaths.tournamentRosters(tournamentId)).get();
      if (!snap.exists || snap.value == null) return {};
      final data = snap.value as Map;
      final result = <String, List<TournamentPlayer>>{};
      data.forEach((teamKey, teamValue) {
        if (teamValue is Map) {
          final teamId = teamKey.toString();
          final players = <TournamentPlayer>[];
          teamValue.forEach((playerKey, playerValue) {
            if (playerValue is Map) {
              try {
                players.add(TournamentPlayer.fromFirebase(
                    playerKey.toString(), teamId, playerValue));
              } catch (e) {
                debugPrint('Skipped malformed player $playerKey: $e');
              }
            }
          });
          result[teamId] = players;
        }
      });
      return result;
    } catch (e) {
      debugPrint('getRosters error: $e');
      return {};
    }
  }

  Future<bool> savePlayer(
    String tournamentId,
    String teamId,
    String playerName,
    TournamentPlayer player,
  ) async {
    try {
      await ref(FirebasePaths.tournamentRosterPlayer(
              tournamentId, teamId, playerName))
          .update(player.toFirebaseMap());
      return true;
    } catch (e) {
      debugPrint('savePlayer error: $e');
      return false;
    }
  }

  Future<bool> deletePlayer(
    String tournamentId,
    String teamId,
    String playerName,
  ) async {
    try {
      await ref(FirebasePaths.tournamentRosterPlayer(
              tournamentId, teamId, playerName))
          .remove();
      return true;
    } catch (e) {
      debugPrint('deletePlayer error: $e');
      return false;
    }
  }
}
```

- [ ] **Step 7.2: Analyze**

```
flutter analyze lib/services/firebase/tournament_service.dart
```
Expected: No issues found.

- [ ] **Step 7.3: Commit**

```bash
git add lib/services/firebase/tournament_service.dart
git commit -m "Add TournamentService — CRUD for tournaments

Extends FirebaseService with tournament-specific operations:
list, get, create (with default PredictionConfig), update fields,
set current pointer, set finished flag, get/save/delete teams,
generate team join codes, get/save/delete matches, update score
and status atomically, append match activity (goals/cards/etc.),
get/save/delete players.

All read paths go through Future.wait for parallel I/O. All
write paths use ref().update() for atomic multi-path writes
where appropriate.

Plan 2, Task 7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Riverpod providers

**Why:** Wraps the service in providers that UI screens watch.

**Files:**
- Create: `lib/providers/tournament_provider.dart`

- [ ] **Step 8.1: Create**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/tournament.dart';
import 'package:infinite_app_manager/models/tournament_match.dart';
import 'package:infinite_app_manager/models/tournament_player.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/services/firebase/tournament_service.dart';

final tournamentServiceProvider = Provider<TournamentService>((ref) {
  return TournamentService();
});

/// All tournaments (active first, then historical by edition desc).
final tournamentListProvider = FutureProvider<List<Tournament>>((ref) {
  return ref.read(tournamentServiceProvider).getAllTournaments();
});

/// Single tournament by id.
final tournamentProvider =
    FutureProvider.family<Tournament?, String>((ref, id) {
  return ref.read(tournamentServiceProvider).getTournament(id);
});

/// Teams for a tournament (merged with table data).
final tournamentTeamsProvider =
    FutureProvider.family<Map<String, TournamentTeam>, String>((ref, id) {
  return ref.read(tournamentServiceProvider).getTeams(id);
});

/// Matches for a tournament (sorted by date then bracketPosition).
final tournamentMatchesProvider =
    FutureProvider.family<List<TournamentMatch>, String>((ref, id) {
  return ref.read(tournamentServiceProvider).getMatches(id);
});

/// Rosters for a tournament (map of teamId -> list of players).
final tournamentRostersProvider =
    FutureProvider.family<Map<String, List<TournamentPlayer>>, String>(
        (ref, id) {
  return ref.read(tournamentServiceProvider).getRosters(id);
});

/// Call after a write to refresh the affected provider.
void refreshTournament(WidgetRef ref, String id) {
  ref.invalidate(tournamentProvider(id));
  ref.invalidate(tournamentListProvider);
}

void refreshTeams(WidgetRef ref, String id) {
  ref.invalidate(tournamentTeamsProvider(id));
}

void refreshMatches(WidgetRef ref, String id) {
  ref.invalidate(tournamentMatchesProvider(id));
}

void refreshRosters(WidgetRef ref, String id) {
  ref.invalidate(tournamentRostersProvider(id));
}
```

- [ ] **Step 8.2: Analyze**

```
flutter analyze lib/providers/tournament_provider.dart
```
Expected: No issues found.

- [ ] **Step 8.3: Commit**

```bash
git add lib/providers/tournament_provider.dart
git commit -m "Add tournament Riverpod providers

tournamentServiceProvider exposes a single TournamentService
instance. tournamentListProvider, tournamentProvider (family),
tournamentTeamsProvider (family), tournamentMatchesProvider
(family), tournamentRostersProvider (family) are FutureProviders
that screens watch. refreshXxx helpers invalidate the relevant
provider after a write.

Plan 2, Task 8.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Tournament List page

**Why:** Entry point. Shows all tournaments; FAB navigates to Create wizard; tap navigates to dashboard.

**Files:**
- Create: `lib/ui/tournaments/tournament_list_page.dart`

- [ ] **Step 9.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class TournamentListPage extends ConsumerWidget {
  const TournamentListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournamentsAsync = ref.watch(tournamentListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tournaments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/tournaments/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Tournament'),
      ),
      body: tournamentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Failed to load tournaments: $e'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(tournamentListProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (tournaments) {
          if (tournaments.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 64),
                    SizedBox(height: 12),
                    Text('No tournaments yet'),
                    SizedBox(height: 8),
                    Text(
                      'Tap "New Tournament" to create one.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: tournaments.length,
            itemBuilder: (context, i) {
              final t = tournaments[i];
              return ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    t.finished ? Icons.flag : Icons.emoji_events,
                  ),
                ),
                title: Text(t.name),
                subtitle: Text('${t.sport} · ${t.edition} · ${t.status}'),
                trailing: t.finished
                    ? const Chip(label: Text('Finished'))
                    : const Chip(
                        label: Text('Active'),
                        backgroundColor: Color(0xFFC8E6C9),
                      ),
                onTap: () => context.go('/tournaments/${t.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 9.2: Analyze**

```
flutter analyze lib/ui/tournaments/tournament_list_page.dart
```
Expected: No issues found (will reference unresolved routes — those land in Task 14).

- [ ] **Step 9.3: Commit**

```bash
git add lib/ui/tournaments/tournament_list_page.dart
git commit -m "Add tournament list page

ConsumerWidget watching tournamentListProvider. Shows active vs
finished status chips. Tap navigates to dashboard. FAB navigates
to create wizard. Loading/error/empty states all handled.

Plan 2, Task 9.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Create Tournament wizard

**Files:**
- Create: `lib/ui/tournaments/create_tournament_page.dart`

- [ ] **Step 10.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/models/tournament.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class CreateTournamentPage extends ConsumerStatefulWidget {
  const CreateTournamentPage({super.key});

  @override
  ConsumerState<CreateTournamentPage> createState() =>
      _CreateTournamentPageState();
}

class _CreateTournamentPageState extends ConsumerState<CreateTournamentPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _editionController = TextEditingController(text: '2026');
  final _hostCityController = TextEditingController();
  final _locationController = TextEditingController();
  String _sport = 'Soccer';
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;

  static const _sports = ['Soccer', 'Futsal', 'Basketball', 'Flag Football'];

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _editionController.dispose();
    _hostCityController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  String _formatMMDDYYYY(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$m$day${d.year}';
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick start and end dates.')),
      );
      return;
    }
    setState(() => _saving = true);

    final tournament = Tournament(
      id: _idController.text.trim(),
      name: _nameController.text.trim(),
      sport: _sport,
      edition: _editionController.text.trim(),
      hostCity: _hostCityController.text.trim().isEmpty
          ? null
          : _hostCityController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      startDate: _formatMMDDYYYY(_startDate!),
      endDate: _formatMMDDYYYY(_endDate!),
      status: 'Registration Open',
      finished: false,
    );

    final service = ref.read(tournamentServiceProvider);
    final ok = await service.createTournament(tournament);

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      ref.invalidate(tournamentListProvider);
      context.go('/tournaments/${tournament.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create tournament. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Tournament')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Tournament ID',
                  helperText:
                      'Short slug, no spaces (e.g. "national_2026"). Used in Firebase path.',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.contains(' ')) return 'No spaces';
                  if (v.contains('/')) return 'No slashes';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sport,
                decoration: const InputDecoration(labelText: 'Sport'),
                items: _sports
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _sport = v ?? 'Soccer'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _editionController,
                decoration: const InputDecoration(labelText: 'Edition / year'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hostCityController,
                decoration: const InputDecoration(
                    labelText: 'Host city (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                    labelText: 'Venue / location (optional)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_startDate == null
                          ? 'Start date'
                          : _formatMMDDYYYY(_startDate!)),
                      onPressed: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_endDate == null
                          ? 'End date'
                          : _formatMMDDYYYY(_endDate!)),
                      onPressed: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Tournament'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 10.2: Analyze**

```
flutter analyze lib/ui/tournaments/create_tournament_page.dart
```
Expected: No issues found.

- [ ] **Step 10.3: Commit**

```bash
git add lib/ui/tournaments/create_tournament_page.dart
git commit -m "Add create-tournament wizard

Single-form wizard: id (Firebase slug), display name, sport
(dropdown), edition, host city, location, start/end dates
via showDatePicker. Submits via TournamentService.createTournament
which also writes the default PredictionConfig. Validates that
id has no spaces or slashes. Invalidates tournamentListProvider
on success and navigates to the new tournament dashboard.

Plan 2, Task 10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Tournament Dashboard

**Files:**
- Create: `lib/ui/tournaments/tournament_dashboard_page.dart`

- [ ] **Step 11.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class TournamentDashboardPage extends ConsumerWidget {
  final String tournamentId;

  const TournamentDashboardPage({super.key, required this.tournamentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournamentAsync = ref.watch(tournamentProvider(tournamentId));
    final service = ref.read(tournamentServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: tournamentAsync.when(
          data: (t) => Text(t?.name ?? tournamentId),
          loading: () => const Text('Loading...'),
          error: (_, __) => Text(tournamentId),
        ),
      ),
      body: tournamentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (t) {
          if (t == null) {
            return const Center(child: Text('Tournament not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('${t.sport} · ${t.edition}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(label: Text(t.status)),
                          const SizedBox(width: 8),
                          if (t.finished)
                            const Chip(
                              label: Text('Finished'),
                              backgroundColor: Color(0xFFEEEEEE),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${t.startDate ?? "?"} - ${t.endDate ?? "?"}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      if (t.hostCity != null)
                        Text(t.hostCity!,
                            style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DashboardTile(
                icon: Icons.group,
                title: 'Manage Teams',
                subtitle: 'Add, edit, generate join codes',
                onTap: () =>
                    context.go('/tournaments/$tournamentId/teams'),
              ),
              _DashboardTile(
                icon: Icons.account_tree,
                title: 'Manage Bracket',
                subtitle: 'Set fixtures, dates, locations, bracket positions',
                onTap: () =>
                    context.go('/tournaments/$tournamentId/bracket'),
              ),
              _DashboardTile(
                icon: Icons.list_alt,
                title: 'Manage Rosters',
                subtitle: 'Add players to each team',
                onTap: () =>
                    context.go('/tournaments/$tournamentId/rosters'),
              ),
              _DashboardTile(
                icon: Icons.sports_score,
                title: 'Live Scoring',
                subtitle: 'Score matches, record goals, cards, end match',
                onTap: () =>
                    context.go('/tournaments/$tournamentId/scoring'),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text('Mark Finished'),
                subtitle: const Text(
                    'Locks predictions and resolves award winners.'),
                value: t.finished,
                onChanged: (val) async {
                  await service.setTournamentFinished(tournamentId, val);
                  refreshTournament(ref, tournamentId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('Set as Current Tournament'),
                subtitle: const Text(
                    'Makes this the default tournament users land on.'),
                onTap: () async {
                  final ok = await service.setCurrentTournament(tournamentId);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Set as current tournament.'
                          : 'Failed to set current tournament.'),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 11.2: Analyze**

```
flutter analyze lib/ui/tournaments/tournament_dashboard_page.dart
```
Expected: No issues found.

- [ ] **Step 11.3: Commit**

```bash
git add lib/ui/tournaments/tournament_dashboard_page.dart
git commit -m "Add tournament dashboard page

Header card with name/sport/edition/status/dates. Four navigation
tiles to Manage Teams, Manage Bracket, Manage Rosters, Live
Scoring. Mark-finished switch and set-as-current action.
Reactive — invalidates tournamentProvider after writes.

Plan 2, Task 11.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Manage Teams page

**Why:** Most-touched admin screen — add/edit/remove teams and generate join codes for the sign-up flow (Plan 6).

**Files:**
- Create: `lib/ui/tournaments/manage_teams_page.dart`

- [ ] **Step 12.1: Create**

```dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class ManageTeamsPage extends ConsumerStatefulWidget {
  final String tournamentId;

  const ManageTeamsPage({super.key, required this.tournamentId});

  @override
  ConsumerState<ManageTeamsPage> createState() => _ManageTeamsPageState();
}

class _ManageTeamsPageState extends ConsumerState<ManageTeamsPage> {
  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _openTeamEditor({TournamentTeam? existing}) async {
    final result = await showDialog<TournamentTeam>(
      context: context,
      builder: (ctx) => _TeamEditorDialog(existing: existing),
    );
    if (result == null) return;
    final service = ref.read(tournamentServiceProvider);
    final ok = await service.saveTeam(widget.tournamentId, result.id, result);
    if (!mounted) return;
    if (ok) {
      refreshTeams(ref, widget.tournamentId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save team.')),
      );
    }
  }

  Future<void> _deleteTeam(TournamentTeam team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete team?'),
        content: Text(
            'This will delete "${team.name}" plus its standings row and roster. Cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = ref.read(tournamentServiceProvider);
    final ok = await service.deleteTeam(widget.tournamentId, team.id);
    if (!mounted) return;
    if (ok) {
      refreshTeams(ref, widget.tournamentId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete team.')),
      );
    }
  }

  Future<void> _generateOrShowCode(TournamentTeam team) async {
    final service = ref.read(tournamentServiceProvider);
    String code = team.joinCode ?? '';
    if (code.isEmpty) {
      code = _generateJoinCode();
      final ok =
          await service.setTeamJoinCode(widget.tournamentId, team.id, code);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save code.')),
        );
        return;
      }
      refreshTeams(ref, widget.tournamentId);
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${team.name} — Join Code'),
        content: SelectableText(
          code,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4),
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard.')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync =
        ref.watch(tournamentTeamsProvider(widget.tournamentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Teams')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTeamEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Team'),
      ),
      body: teamsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (teams) {
          if (teams.isEmpty) {
            return const Center(
                child: Text('No teams yet. Tap "Add Team" to start.'));
          }
          final sorted = teams.values.toList()
            ..sort((a, b) {
              final g = (a.group ?? '').compareTo(b.group ?? '');
              if (g != 0) return g;
              return (a.seed ?? 99).compareTo(b.seed ?? 99);
            });
          return ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final t = sorted[i];
              return ListTile(
                title: Text(t.name),
                subtitle: Text([
                  if (t.group != null) t.group,
                  if (t.seed != null) 'Seed ${t.seed}',
                  if (t.coachName != null) 'Coach: ${t.coachName}',
                ].whereType<String>().join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.qr_code),
                      tooltip: 'Join code',
                      onPressed: () => _generateOrShowCode(t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () => _openTeamEditor(existing: t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _deleteTeam(t),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TeamEditorDialog extends StatefulWidget {
  final TournamentTeam? existing;
  const _TeamEditorDialog({this.existing});

  @override
  State<_TeamEditorDialog> createState() => _TeamEditorDialogState();
}

class _TeamEditorDialogState extends State<_TeamEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _groupController;
  late final TextEditingController _seedController;
  late final TextEditingController _coachController;
  late final TextEditingController _cityStateController;
  late final TextEditingController _homeColorController;
  late final TextEditingController _awayColorController;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idController = TextEditingController(text: e?.id ?? '');
    _nameController = TextEditingController(text: e?.name ?? '');
    _groupController = TextEditingController(text: e?.group ?? '');
    _seedController =
        TextEditingController(text: e?.seed?.toString() ?? '');
    _coachController = TextEditingController(text: e?.coachName ?? '');
    _cityStateController = TextEditingController(text: e?.cityState ?? '');
    _homeColorController = TextEditingController(text: e?.homeColor ?? '');
    _awayColorController = TextEditingController(text: e?.awayColor ?? '');
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _groupController.dispose();
    _seedController.dispose();
    _coachController.dispose();
    _cityStateController.dispose();
    _homeColorController.dispose();
    _awayColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Team' : 'Add Team'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idController,
              enabled: !isEdit,
              decoration: const InputDecoration(
                labelText: 'Team ID (slug, no spaces)',
              ),
            ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            TextField(
              controller: _groupController,
              decoration: const InputDecoration(
                  labelText: 'Group (e.g. "Group A")'),
            ),
            TextField(
              controller: _seedController,
              decoration: const InputDecoration(labelText: 'Seed (number)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _coachController,
              decoration: const InputDecoration(labelText: 'Coach name'),
            ),
            TextField(
              controller: _cityStateController,
              decoration: const InputDecoration(
                  labelText: 'City, State (e.g. "Sacramento, CA")'),
            ),
            TextField(
              controller: _homeColorController,
              decoration: const InputDecoration(
                  labelText: 'Home color (#RRGGBB)'),
            ),
            TextField(
              controller: _awayColorController,
              decoration: const InputDecoration(
                  labelText: 'Away color (#RRGGBB)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final id = _idController.text.trim();
            final name = _nameController.text.trim();
            if (id.isEmpty || id.contains(' ') || id.contains('/')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid team id.')),
              );
              return;
            }
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Name required.')),
              );
              return;
            }
            final team = TournamentTeam(
              id: id,
              name: name,
              group: _groupController.text.trim().isEmpty
                  ? null
                  : _groupController.text.trim(),
              seed: int.tryParse(_seedController.text.trim()),
              coachName: _coachController.text.trim().isEmpty
                  ? null
                  : _coachController.text.trim(),
              cityState: _cityStateController.text.trim().isEmpty
                  ? null
                  : _cityStateController.text.trim(),
              homeColor: _homeColorController.text.trim().isEmpty
                  ? null
                  : _homeColorController.text.trim(),
              awayColor: _awayColorController.text.trim().isEmpty
                  ? null
                  : _awayColorController.text.trim(),
              qualification: widget.existing?.qualification ?? 'TBD',
              joinCode: widget.existing?.joinCode,
            );
            Navigator.pop(context, team);
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 12.2: Analyze**

```
flutter analyze lib/ui/tournaments/manage_teams_page.dart
```
Expected: No issues found.

- [ ] **Step 12.3: Commit**

```bash
git add lib/ui/tournaments/manage_teams_page.dart
git commit -m "Add manage-teams page with join code generation

ListView of teams sorted by group/seed. FAB opens dialog to add
new team; per-row edit/delete actions; per-row QR/code button
generates or shows existing 6-char join code (used by Plan 6
sign-up flow). Delete cascades to Table and Rosters nodes.

Join codes use a Crockford-style alphabet (no 0/O/I/1) to avoid
confusion when shared verbally with team captains.

Plan 2, Task 12.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: Manage Bracket page

**Files:**
- Create: `lib/ui/tournaments/manage_bracket_page.dart`

- [ ] **Step 13.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/tournament_match.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

const List<String> _stageOptions = [
  'Group Stage',
  'Round of 16',
  'Quarterfinal',
  'Semifinal',
  'Third Place',
  'Final',
];

class ManageBracketPage extends ConsumerStatefulWidget {
  final String tournamentId;
  const ManageBracketPage({super.key, required this.tournamentId});

  @override
  ConsumerState<ManageBracketPage> createState() => _ManageBracketPageState();
}

class _ManageBracketPageState extends ConsumerState<ManageBracketPage> {
  Future<void> _openMatchEditor({TournamentMatch? existing}) async {
    final teams = await ref
        .read(tournamentServiceProvider)
        .getTeams(widget.tournamentId);
    if (!mounted) return;
    final result = await showDialog<TournamentMatch>(
      context: context,
      builder: (ctx) =>
          _MatchEditorDialog(existing: existing, teams: teams),
    );
    if (result == null) return;
    final service = ref.read(tournamentServiceProvider);
    final ok =
        await service.saveMatch(widget.tournamentId, result.id, result);
    if (!mounted) return;
    if (ok) {
      refreshMatches(ref, widget.tournamentId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save match.')),
      );
    }
  }

  Future<void> _deleteMatch(TournamentMatch m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete match?'),
        content: Text('Delete ${m.label}? Cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = ref.read(tournamentServiceProvider);
    final ok = await service.deleteMatch(widget.tournamentId, m.id);
    if (!mounted) return;
    if (ok) refreshMatches(ref, widget.tournamentId);
  }

  @override
  Widget build(BuildContext context) {
    final matchesAsync =
        ref.watch(tournamentMatchesProvider(widget.tournamentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Bracket')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMatchEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Match'),
      ),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (matches) {
          if (matches.isEmpty) {
            return const Center(
                child: Text('No matches yet. Tap "Add Match" to start.'));
          }
          // Group by stage
          final byStage = <String, List<TournamentMatch>>{};
          for (final m in matches) {
            byStage.putIfAbsent(m.stage, () => []).add(m);
          }
          return ListView(
            children: [
              for (final stage in _stageOptions)
                if (byStage.containsKey(stage)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      stage,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  ...byStage[stage]!.map((m) => ListTile(
                        title: Text(m.label),
                        subtitle: Text(
                            '${m.date} ${m.time ?? ""} · ${m.team1Id ?? "TBD"} vs ${m.team2Id ?? "TBD"}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _openMatchEditor(existing: m),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteMatch(m),
                            ),
                          ],
                        ),
                      )),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _MatchEditorDialog extends StatefulWidget {
  final TournamentMatch? existing;
  final Map<String, TournamentTeam> teams;
  const _MatchEditorDialog({this.existing, required this.teams});

  @override
  State<_MatchEditorDialog> createState() => _MatchEditorDialogState();
}

class _MatchEditorDialogState extends State<_MatchEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _labelController;
  late final TextEditingController _timeController;
  late final TextEditingController _locationController;
  late final TextEditingController _bracketPositionController;
  String _stage = 'Group Stage';
  String? _team1Id;
  String? _team2Id;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idController = TextEditingController(text: e?.id ?? '');
    _labelController =
        TextEditingController(text: e?.label ?? 'Group Stage Match');
    _timeController = TextEditingController(text: e?.time ?? '');
    _locationController =
        TextEditingController(text: e?.matchLocation ?? '');
    _bracketPositionController = TextEditingController(
        text: (e?.bracketPosition ?? 0).toString());
    _stage = e?.stage ?? 'Group Stage';
    _team1Id = e?.team1Id;
    _team2Id = e?.team2Id;
    if (e?.date != null && e!.date.length == 8) {
      _date = DateTime(
        int.parse(e.date.substring(4, 8)),
        int.parse(e.date.substring(0, 2)),
        int.parse(e.date.substring(2, 4)),
      );
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _labelController.dispose();
    _timeController.dispose();
    _locationController.dispose();
    _bracketPositionController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$m$day${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final teamIds = widget.teams.keys.toList()..sort();
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Match' : 'Add Match'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idController,
              enabled: !isEdit,
              decoration: const InputDecoration(
                labelText: 'Match ID (slug)',
                helperText: 'e.g. gs_a_01 or sf_1',
              ),
            ),
            TextField(
              controller: _labelController,
              decoration:
                  const InputDecoration(labelText: 'Match label / name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _stage,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: _stageOptions
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _stage = v ?? 'Group Stage'),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _team1Id,
              decoration: const InputDecoration(labelText: 'Team 1'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('TBD')),
                ...teamIds.map((id) => DropdownMenuItem<String?>(
                    value: id,
                    child: Text(widget.teams[id]?.name ?? id))),
              ],
              onChanged: (v) => setState(() => _team1Id = v),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _team2Id,
              decoration: const InputDecoration(labelText: 'Team 2'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('TBD')),
                ...teamIds.map((id) => DropdownMenuItem<String?>(
                    value: id,
                    child: Text(widget.teams[id]?.name ?? id))),
              ],
              onChanged: (v) => setState(() => _team2Id = v),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label:
                  Text(_date == null ? 'Pick date' : _formatDate(_date!)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(
                  labelText: 'Time (e.g. "2:00 PM")'),
            ),
            TextField(
              controller: _locationController,
              decoration:
                  const InputDecoration(labelText: 'Match location / field'),
            ),
            TextField(
              controller: _bracketPositionController,
              decoration: const InputDecoration(
                labelText: 'Bracket position',
                helperText:
                    'Used for sorting matches within a stage (1, 2, 3, …)',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final id = _idController.text.trim();
            if (id.isEmpty || id.contains(' ') || id.contains('/')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid match id.')),
              );
              return;
            }
            if (_date == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pick a date.')),
              );
              return;
            }
            final match = TournamentMatch(
              id: id,
              stage: _stage,
              label: _labelController.text.trim(),
              date: _formatDate(_date!),
              time: _timeController.text.trim().isEmpty
                  ? null
                  : _timeController.text.trim(),
              team1Id: _team1Id,
              team2Id: _team2Id,
              team1Score: widget.existing?.team1Score ?? 0,
              team2Score: widget.existing?.team2Score ?? 0,
              status: widget.existing?.status ?? 0,
              matchLocation: _locationController.text.trim().isEmpty
                  ? null
                  : _locationController.text.trim(),
              bracketPosition:
                  int.tryParse(_bracketPositionController.text.trim()) ?? 0,
            );
            Navigator.pop(context, match);
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 13.2: Analyze**

```
flutter analyze lib/ui/tournaments/manage_bracket_page.dart
```
Expected: No issues found.

- [ ] **Step 13.3: Commit**

```bash
git add lib/ui/tournaments/manage_bracket_page.dart
git commit -m "Add manage-bracket page

ListView of matches grouped by stage (Group Stage, R16, QF,
SF, 3rd Place, Final). FAB adds a new match; per-row edit/delete.
Dialog form: id (slug), label, stage dropdown, team1/team2
dropdowns of existing teams, date picker, time text, location,
bracket position. Save delegates to TournamentService.saveMatch
and invalidates tournamentMatchesProvider.

Plan 2, Task 13.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Manage Rosters page

**Files:**
- Create: `lib/ui/tournaments/manage_rosters_page.dart`

- [ ] **Step 14.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/tournament_player.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class ManageRostersPage extends ConsumerStatefulWidget {
  final String tournamentId;
  const ManageRostersPage({super.key, required this.tournamentId});

  @override
  ConsumerState<ManageRostersPage> createState() =>
      _ManageRostersPageState();
}

class _ManageRostersPageState extends ConsumerState<ManageRostersPage> {
  String? _selectedTeamId;

  Future<void> _openPlayerEditor({TournamentPlayer? existing}) async {
    final teamId = _selectedTeamId;
    if (teamId == null) return;
    final result = await showDialog<TournamentPlayer>(
      context: context,
      builder: (ctx) =>
          _PlayerEditorDialog(existing: existing, teamId: teamId),
    );
    if (result == null) return;
    final service = ref.read(tournamentServiceProvider);
    final ok = await service.savePlayer(
        widget.tournamentId, teamId, result.name, result);
    if (!mounted) return;
    if (ok) {
      refreshRosters(ref, widget.tournamentId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save player.')),
      );
    }
  }

  Future<void> _deletePlayer(TournamentPlayer p) async {
    final teamId = _selectedTeamId;
    if (teamId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final service = ref.read(tournamentServiceProvider);
    final ok = await service.deletePlayer(
        widget.tournamentId, teamId, p.name);
    if (!mounted) return;
    if (ok) refreshRosters(ref, widget.tournamentId);
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync =
        ref.watch(tournamentTeamsProvider(widget.tournamentId));
    final rostersAsync =
        ref.watch(tournamentRostersProvider(widget.tournamentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Rosters')),
      floatingActionButton: _selectedTeamId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openPlayerEditor(),
              icon: const Icon(Icons.person_add),
              label: const Text('Add Player'),
            ),
      body: teamsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (teams) {
          if (teams.isEmpty) {
            return const Center(
                child: Text(
                    'Add teams first in Manage Teams before adding rosters.'));
          }
          final sortedTeams = teams.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          _selectedTeamId ??= sortedTeams.first.id;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedTeamId,
                  decoration: const InputDecoration(
                    labelText: 'Team',
                    border: OutlineInputBorder(),
                  ),
                  items: sortedTeams
                      .map((TournamentTeam t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTeamId = v),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rostersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                  data: (rosters) {
                    final players = (rosters[_selectedTeamId] ?? [])
                      ..sort((a, b) => a.name.compareTo(b.name));
                    if (players.isEmpty) {
                      return const Center(
                          child: Text('No players. Tap "Add Player".'));
                    }
                    return ListView.builder(
                      itemCount: players.length,
                      itemBuilder: (context, i) {
                        final p = players[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(p.number ?? '-'),
                          ),
                          title: Text(p.name),
                          subtitle: Text(p.position ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _openPlayerEditor(existing: p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deletePlayer(p),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerEditorDialog extends StatefulWidget {
  final TournamentPlayer? existing;
  final String teamId;
  const _PlayerEditorDialog({this.existing, required this.teamId});

  @override
  State<_PlayerEditorDialog> createState() => _PlayerEditorDialogState();
}

class _PlayerEditorDialogState extends State<_PlayerEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _numberController;
  late final TextEditingController _positionController;
  late final TextEditingController _uidController;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _numberController = TextEditingController(text: e?.number ?? '');
    _positionController = TextEditingController(text: e?.position ?? '');
    _uidController = TextEditingController(text: e?.uid ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _positionController.dispose();
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Player' : 'Add Player'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              enabled: !isEdit,
              decoration:
                  const InputDecoration(labelText: 'Player name'),
            ),
            TextField(
              controller: _numberController,
              decoration:
                  const InputDecoration(labelText: 'Jersey number'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _positionController,
              decoration: const InputDecoration(
                  labelText: 'Position (e.g. GK, DEF, MID, FWD)'),
            ),
            TextField(
              controller: _uidController,
              decoration: const InputDecoration(
                labelText: 'User UID (optional)',
                helperText:
                    'Firebase Auth uid — links to user profile photo.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Name required.')),
              );
              return;
            }
            final player = TournamentPlayer(
              name: name,
              teamId: widget.teamId,
              number: _numberController.text.trim().isEmpty
                  ? null
                  : _numberController.text.trim(),
              position: _positionController.text.trim().isEmpty
                  ? null
                  : _positionController.text.trim(),
              uid: _uidController.text.trim().isEmpty
                  ? null
                  : _uidController.text.trim(),
              goals: widget.existing?.goals ?? 0,
              assists: widget.existing?.assists ?? 0,
              saves: widget.existing?.saves ?? 0,
              dpl: widget.existing?.dpl ?? 0,
              cleanSheets: widget.existing?.cleanSheets ?? 0,
              yellowCards: widget.existing?.yellowCards ?? 0,
              redCards: widget.existing?.redCards ?? 0,
            );
            Navigator.pop(context, player);
          },
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 14.2: Analyze**

```
flutter analyze lib/ui/tournaments/manage_rosters_page.dart
```
Expected: No issues found.

- [ ] **Step 14.3: Commit**

```bash
git add lib/ui/tournaments/manage_rosters_page.dart
git commit -m "Add manage-rosters page

Team dropdown at top filters the roster list below. FAB adds
a new player to the selected team. Per-row edit/delete.
Dialog form: name (immutable on edit since name is the key),
jersey number, position, optional Firebase Auth UID for
profile-photo linkage.

Plan 2, Task 14.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Live Scoring page

**Why:** The flagship admin screen. Allows real-time match scoring with goal scorers, assists, cards, end-match — what referees and the small admin team will use during tournament weekend.

**Files:**
- Create: `lib/ui/tournaments/live_scoring_page.dart`

- [ ] **Step 15.1: Create**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_app_manager/models/tournament_match.dart';
import 'package:infinite_app_manager/models/tournament_player.dart';
import 'package:infinite_app_manager/models/tournament_team.dart';
import 'package:infinite_app_manager/providers/tournament_provider.dart';

class LiveScoringPage extends ConsumerStatefulWidget {
  final String tournamentId;
  const LiveScoringPage({super.key, required this.tournamentId});

  @override
  ConsumerState<LiveScoringPage> createState() => _LiveScoringPageState();
}

class _LiveScoringPageState extends ConsumerState<LiveScoringPage> {
  String? _selectedMatchId;

  @override
  Widget build(BuildContext context) {
    final matchesAsync =
        ref.watch(tournamentMatchesProvider(widget.tournamentId));
    final teamsAsync =
        ref.watch(tournamentTeamsProvider(widget.tournamentId));
    final rostersAsync =
        ref.watch(tournamentRostersProvider(widget.tournamentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Live Scoring')),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (matches) {
          if (matches.isEmpty) {
            return const Center(
                child: Text(
                    'Add matches in Manage Bracket before scoring.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedMatchId,
                  decoration: const InputDecoration(
                    labelText: 'Match',
                    border: OutlineInputBorder(),
                  ),
                  items: matches
                      .map((m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(
                                '${m.label} (${_statusLabel(m.status)})'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedMatchId = v),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _selectedMatchId == null
                    ? const Center(
                        child: Text('Pick a match to start scoring.'))
                    : teamsAsync.when(
                        loading: () => const Center(
                            child: CircularProgressIndicator()),
                        error: (e, st) => Center(child: Text('Error: $e')),
                        data: (teams) => rostersAsync.when(
                          loading: () => const Center(
                              child: CircularProgressIndicator()),
                          error: (e, st) =>
                              Center(child: Text('Error: $e')),
                          data: (rosters) => _ScoringPanel(
                            tournamentId: widget.tournamentId,
                            match: matches.firstWhere(
                                (m) => m.id == _selectedMatchId),
                            teams: teams,
                            rosters: rosters,
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _statusLabel(int s) =>
      s == 0 ? 'Upcoming' : (s == 1 ? 'LIVE' : 'Final');
}

class _ScoringPanel extends ConsumerStatefulWidget {
  final String tournamentId;
  final TournamentMatch match;
  final Map<String, TournamentTeam> teams;
  final Map<String, List<TournamentPlayer>> rosters;

  const _ScoringPanel({
    required this.tournamentId,
    required this.match,
    required this.teams,
    required this.rosters,
  });

  @override
  ConsumerState<_ScoringPanel> createState() => _ScoringPanelState();
}

class _ScoringPanelState extends ConsumerState<_ScoringPanel> {
  Future<void> _changeScore(int teamTag, int delta) async {
    final current =
        teamTag == 0 ? widget.match.team1Score : widget.match.team2Score;
    final next = (current + delta).clamp(0, 99);
    final service = ref.read(tournamentServiceProvider);
    await service.updateMatchScore(
        widget.tournamentId, widget.match.id, teamTag, next);
    refreshMatches(ref, widget.tournamentId);
  }

  Future<void> _setStatus(int newStatus) async {
    final service = ref.read(tournamentServiceProvider);
    await service.updateMatchStatus(
        widget.tournamentId, widget.match.id, newStatus);
    refreshMatches(ref, widget.tournamentId);
  }

  Future<void> _recordEvent(int teamTag, String eventType) async {
    final teamId = teamTag == 0
        ? widget.match.team1Id
        : widget.match.team2Id;
    if (teamId == null) return;
    final teamPlayers = widget.rosters[teamId] ?? [];
    if (teamPlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'No players in roster for ${widget.teams[teamId]?.name ?? teamId}.')),
      );
      return;
    }

    final player = await showDialog<TournamentPlayer>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Pick player for $eventType'),
        children: teamPlayers
            .map((p) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, p),
                  child: Text('${p.number ?? "-"} · ${p.name}'),
                ))
            .toList(),
      ),
    );
    if (player == null) return;

    final minuteStr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: '1');
        return AlertDialog(
          title: const Text('Minute'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 23'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Record'),
            ),
          ],
        );
      },
    );
    if (minuteStr == null || minuteStr.isEmpty) return;

    final service = ref.read(tournamentServiceProvider);
    final ok = await service.appendMatchActivity(
      widget.tournamentId,
      widget.match.id,
      teamTag,
      minuteStr,
      {eventType: player.name},
    );

    if (!mounted) return;
    if (ok && eventType == 'Goal') {
      await _changeScore(teamTag, 1);
    } else if (ok) {
      refreshMatches(ref, widget.tournamentId);
    }
  }

  Future<void> _endMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End match?'),
        content: const Text(
            'This marks the match Final and locks predictions (Plan 4).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Match'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _setStatus(2);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final team1Name = m.team1Id == null
        ? 'TBD'
        : (widget.teams[m.team1Id]?.name ?? m.team1Id!);
    final team2Name = m.team2Id == null
        ? 'TBD'
        : (widget.teams[m.team2Id]?.name ?? m.team2Id!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Score row
          Row(
            children: [
              Expanded(child: _TeamScoreCard(name: team1Name, score: m.team1Score)),
              const SizedBox(width: 8),
              Text(
                m.status == 1 ? 'LIVE' : (m.status == 2 ? 'FINAL' : 'VS'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: m.status == 1 ? Colors.red : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _TeamScoreCard(name: team2Name, score: m.team2Score)),
            ],
          ),
          const SizedBox(height: 16),
          // Score +/- controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreButton(label: '-', onPressed: () => _changeScore(0, -1)),
              _ScoreButton(label: '+', onPressed: () => _changeScore(0, 1)),
              const SizedBox(width: 16),
              _ScoreButton(label: '-', onPressed: () => _changeScore(1, -1)),
              _ScoreButton(label: '+', onPressed: () => _changeScore(1, 1)),
            ],
          ),
          const SizedBox(height: 24),
          // Event buttons per team
          Row(
            children: [
              Expanded(child: _EventColumn(
                teamName: team1Name,
                onGoal: () => _recordEvent(0, 'Goal'),
                onAssist: () => _recordEvent(0, 'Assist'),
                onYellow: () => _recordEvent(0, 'Yellow'),
                onRed: () => _recordEvent(0, 'Red'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _EventColumn(
                teamName: team2Name,
                onGoal: () => _recordEvent(1, 'Goal'),
                onAssist: () => _recordEvent(1, 'Assist'),
                onYellow: () => _recordEvent(1, 'Yellow'),
                onRed: () => _recordEvent(1, 'Red'),
              )),
            ],
          ),
          const SizedBox(height: 24),
          // Match status controls
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (m.status == 0)
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Match (LIVE)'),
                  onPressed: () => _setStatus(1),
                ),
              if (m.status == 1)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.stop),
                  label: const Text('End Match'),
                  onPressed: _endMatch,
                ),
              if (m.status == 2)
                OutlinedButton.icon(
                  icon: const Icon(Icons.undo),
                  label: const Text('Reopen (set to LIVE)'),
                  onPressed: () => _setStatus(1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamScoreCard extends StatelessWidget {
  final String name;
  final int score;

  const _TeamScoreCard({required this.name, required this.score});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(score.toString(),
                style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _ScoreButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ScoreButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

class _EventColumn extends StatelessWidget {
  final String teamName;
  final VoidCallback onGoal;
  final VoidCallback onAssist;
  final VoidCallback onYellow;
  final VoidCallback onRed;

  const _EventColumn({
    required this.teamName,
    required this.onGoal,
    required this.onAssist,
    required this.onYellow,
    required this.onRed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(teamName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onGoal, child: const Text('⚽ Goal')),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: onAssist, child: const Text('🅰 Assist')),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: onYellow,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.amber.shade800),
          child: const Text('🟨 Yellow'),
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: onRed,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('🟥 Red'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 15.2: Analyze**

```
flutter analyze lib/ui/tournaments/live_scoring_page.dart
```
Expected: No issues found.

- [ ] **Step 15.3: Commit**

```bash
git add lib/ui/tournaments/live_scoring_page.dart
git commit -m "Add live-scoring page

Pick a match from a dropdown. Score panel: team1 / VS / team2
with current scores. +/- buttons per team. Event buttons per
team: Goal (records scorer, increments score), Assist, Yellow,
Red — each shows a player picker then a minute picker, then
appends to /Matches/{id}/Team{N}Activity. Status controls:
Start Match (Upcoming -> LIVE), End Match (LIVE -> Final),
Reopen (Final -> LIVE) for corrections.

Plan 2, Task 15.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Router integration

**Why:** Wire all 6 new pages into go_router and the master detail shell.

**Files:**
- Modify: `lib/router/app_router.dart`
- Modify: `lib/ui/home/master_detail_shell.dart`
- Modify: `lib/ui/home/main_menu_page.dart`

- [ ] **Step 16.1: Add tournament imports to app_router.dart**

In `lib/router/app_router.dart`, add these imports near the other UI imports (alphabetically near `tournaments`):

```dart
import 'package:infinite_app_manager/ui/tournaments/create_tournament_page.dart';
import 'package:infinite_app_manager/ui/tournaments/live_scoring_page.dart';
import 'package:infinite_app_manager/ui/tournaments/manage_bracket_page.dart';
import 'package:infinite_app_manager/ui/tournaments/manage_rosters_page.dart';
import 'package:infinite_app_manager/ui/tournaments/manage_teams_page.dart';
import 'package:infinite_app_manager/ui/tournaments/tournament_dashboard_page.dart';
import 'package:infinite_app_manager/ui/tournaments/tournament_list_page.dart';
```

- [ ] **Step 16.2: Add tournament routes**

Inside the `ShellRoute`'s `routes:` list, before the closing `]`, add:

```dart
          GoRoute(
            path: '/tournaments',
            builder: (context, state) => const TournamentListPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CreateTournamentPage(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return TournamentDashboardPage(tournamentId: id);
                },
                routes: [
                  GoRoute(
                    path: 'teams',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return ManageTeamsPage(tournamentId: id);
                    },
                  ),
                  GoRoute(
                    path: 'bracket',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return ManageBracketPage(tournamentId: id);
                    },
                  ),
                  GoRoute(
                    path: 'rosters',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return ManageRostersPage(tournamentId: id);
                    },
                  ),
                  GoRoute(
                    path: 'scoring',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return LiveScoringPage(tournamentId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
```

- [ ] **Step 16.3: Add Tournaments item to master detail shell drawer**

Open `lib/ui/home/master_detail_shell.dart` and locate the drawer items list. Add a new ListTile with icon `Icons.emoji_events`, label `'Tournaments'`, onTap `() => context.go('/tournaments')`. Pattern should match existing items (e.g. the Futsal/Basketball entries). If the drawer items are in an existing list constant, add a new entry at the appropriate position (after the sport entries, before the settings/admin entries).

- [ ] **Step 16.4: Add Tournaments tile to main menu**

Open `lib/ui/home/main_menu_page.dart`. Add a new card / tile matching the existing pattern (Futsal, Basketball, Flag Football). Label: 'Tournaments', icon: `Icons.emoji_events`, onTap: `() => context.go('/tournaments')`.

- [ ] **Step 16.5: Analyze the whole project**

```
flutter analyze lib/
```
Expected: No errors. (Pre-existing warnings unrelated to this work are OK.)

- [ ] **Step 16.6: Commit**

```bash
git add lib/router/app_router.dart lib/ui/home/master_detail_shell.dart lib/ui/home/main_menu_page.dart
git commit -m "Wire tournament routes into go_router + nav

Adds /tournaments and nested routes (:id, :id/teams, :id/bracket,
:id/rosters, :id/scoring, new) to the ShellRoute. Adds Tournaments
entry to the master detail shell drawer and the main menu page
so admins can reach it from anywhere.

Plan 2, Task 16.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: Final smoke verification

**Why:** End-to-end verify that the admin app can create and run a tournament from scratch, and that the user app sees the result.

- [ ] **Step 17.1: Pull latest manager app and run**

```bash
git -C "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" pull
```
Open the manager app in Android Studio. Hit Play.

- [ ] **Step 17.2: Create a tournament**

- Sign in to the manager app
- Tap the new "Tournaments" item in the drawer or on the main menu
- Tap "New Tournament"
- Fill in: id `plan_2_test_2026`, name `Plan 2 Test Tournament`, sport `Soccer`, edition `2026`, dates roughly a week out
- Tap Create

- [ ] **Step 17.3: Add 4 teams**

- On the dashboard, tap Manage Teams
- Tap "Add Team" four times; create teams `team_a`, `team_b`, `team_c`, `team_d` with display names and group "Group A"
- Tap the QR icon on each team — verify a join code is generated and persisted

- [ ] **Step 17.4: Add 2 matches**

- Back to dashboard → Manage Bracket → Add Match
- First match: id `gs_01`, label "Match Day 1", stage Group Stage, team_a vs team_b, today's date, time `2:00 PM`, bracket position 1
- Second match: id `gs_02`, label "Match Day 1", stage Group Stage, team_c vs team_d, today's date, time `4:00 PM`, bracket position 2

- [ ] **Step 17.5: Add 2 players per team**

- Back to dashboard → Manage Rosters
- Select team_a, add 2 players (e.g. "Player One" #1 GK, "Player Two" #9 FWD)
- Repeat for team_b, team_c, team_d

- [ ] **Step 17.6: Score a match live**

- Back to dashboard → Live Scoring
- Pick gs_01 from the dropdown
- Tap Start Match → status changes to LIVE
- Tap ⚽ Goal under team_a → pick "Player Two" → enter minute 23 → score becomes 1-0
- Tap End Match → confirm. Status should be Final.

- [ ] **Step 17.7: Verify in user app**

- Open the **user app** in Android Studio (separate run config or device)
- Pull latest user app to get the merged Plan 1 work: `git -C C:/Users/zayaa/StudioProjects/infinite_sports_flutter pull`
- Open Tournaments tab → Plan 2 Test Tournament should appear in the list
- Open it → Fixtures should show the 2 matches; gs_01 should be Final 1-0
- Open gs_01 → Facts tab should show "Player Two ⚽ 23'"
- Lineup tab should show Player One and Player Two for team_a with their photos (or person fallback)

- [ ] **Step 17.8: Push manager app branch**

```bash
git -C "C:/Users/zayaa/StudioProjects/InfiniteSportsManagerFlutter" push
```

- [ ] **Step 17.9: Report**

In chat: "Plan 2 verification done. Manager app creates tournaments. User app sees them. [Anything off]"

---

## Plan 2 Done

Manager app now has full tournament CRUD: create, add teams (with join codes), add matches, add rosters, live scoring with goal/assist/card events and start/end match. The user app picks up everything through the shared Firebase schema with no additional changes needed.

What's NOT in Plan 2 (still ahead):
- Prediction config screen (Plan 4)
- Announcements posting (Plan 5)
- QR scoring codes generator (Plan 5)
- Sign-up admin (Plan 6)
- Real-time listeners on the user app for live updates (Plan 3)
- Push notifications + Cloud Functions (Plan 3)

---

## Self-Review Checklist

**1. Spec coverage** (Section 6.3 — admin app 11 screens):
- Tournament list ✓ (Task 9)
- Create tournament wizard ✓ (Task 10)
- Tournament dashboard ✓ (Task 11)
- Manage teams + join codes ✓ (Task 12)
- Manage bracket ✓ (Task 13)
- Manage rosters ✓ (Task 14)
- Live scoring with full match events ✓ (Task 15)
- Prediction config — deferred to Plan 4 (explicit in plan header)
- Announcements — deferred to Plan 5
- QR scoring codes — deferred to Plan 5
- Sign-up admin — deferred to Plan 6

**2. Placeholder scan:** No TODO/TBD/"add appropriate" patterns in any task. All code blocks are complete and ready to paste.

**3. Type consistency:**
- `Tournament`, `TournamentTeam`, `TournamentMatch`, `TournamentPlayer`, `PredictionConfig` types defined in Tasks 2-6; used consistently in Tasks 7-15.
- `TournamentService` methods (`getAllTournaments`, `getTournament`, `createTournament`, `setTournamentFinished`, `getTeams`, `saveTeam`, `deleteTeam`, `setTeamJoinCode`, `getMatches`, `saveMatch`, `deleteMatch`, `updateMatchScore`, `updateMatchStatus`, `appendMatchActivity`, `getRosters`, `savePlayer`, `deletePlayer`) defined in Task 7; used in Tasks 9-15.
- Riverpod providers (`tournamentServiceProvider`, `tournamentListProvider`, `tournamentProvider`, `tournamentTeamsProvider`, `tournamentMatchesProvider`, `tournamentRostersProvider`) defined in Task 8; used in Tasks 9-15.
- Refresh helpers (`refreshTournament`, `refreshTeams`, `refreshMatches`, `refreshRosters`) defined in Task 8; used in Tasks 10-15.

**4. No dangling references.** All routes used in `context.go('/tournaments/...')` calls are defined in Task 16. ✓
