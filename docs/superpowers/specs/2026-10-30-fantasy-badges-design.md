# Infinite Fantasy — Achievement badges

**Status:** owner-approved in chat 2026-10-30 ("yes go ahead and build it") after the plan
below was described to him. Extends `2026-10-26-infinite-fantasy-design.md` and the round-3
spec `2026-10-29-fantasy-players-profiles-leaderboards-design.md`.

Repos/branches: fan repo `infinite_sports_flutter` (app + `functions/`) and Manager
`InfiniteSportsManagerFlutter`, both `zaya-fantasy`. House rules: automation-first (memory
`feedback_automate_first.md`), live streams, no RTDB `.get()` in Flutter, light + dark via
colorScheme, names wrap (never ellipsize/underline), one fade reveal, destructive actions
confirm, never delete files, iOS parity, down red = `fantasyDownRed`.

## 1. Intent

Fantasy managers earn badges for playing well — the right captain, the right bench, spotting
a bargain — so the game has small wins every week, not just the leaderboard. Badges are
awarded automatically by the engine; the owner can also give any badge to anyone by hand
(contests, MVP of the month) and create new badges later without code.

**Non-goals:** badge-based points/prizes, badge leaderboards, user-to-user badges.
**Anti-goals:** a badge given for a voided week; a badge that silently disappears after the
owner gave it by hand; pushes sent twice; test-season data landing in a real trophy cabinet.

## 2. Starter set (automatic)

| Id | Name | Earned when (per finalized, non-voided gameweek unless noted) | Repeatable |
|---|---|---|---|
| `captainGenius` | Captain Genius | Your captain's raw week points ≥ every other starter's raw week points in your scored squad (ties count) and > 0 | yes |
| `crystalBall` | Crystal Ball | ≥ 3 of that week's Team of the Week players were in your squad (starters or bench) | yes |
| `benchBoss` | Bench Boss | No bench player outscored (raw) any starter of the same position who played; not awarded in a Bench Boost week; needs at least one bench player who played | yes |
| `hiddenGem` | Hidden Gem | A starter in your squad scored ≥ 10 raw points that week while owned by < 10% of that week's managers | yes |
| `topOfTheWeek` | Top of the Week | Gameweek rank 1 (ties all win) | yes |
| `everPresent` | Ever Present | Season end: you had a scored team in every gameweek of the season | once/season |
| `champion` / `runnerUp` / `thirdPlace` | Champion / Runner-up / Third place | Season end: final Overall rank 1 / 2 / 3 (competition ranks; ties share) | once/season |

"Season end" = the league flag `/<sport>/<season>/Finished == true` AND every gameweek of the
season is finalized. (Claude's call: "Ever Present" counts scored weeks — a team carried over
counts — because "saved every week" isn't recorded per week.)

## 3. Data

- **Catalog** (global, all sports/seasons): `Fantasy/BadgeCatalog/<badgeId>` =
  `{Name, Description, Icon (curated material-icon key), ImageUrl?, Kind: 'auto'|'manual',
  Rule?: '<ruleKey>', Repeatable: bool, Order: int, Active: bool}`. The server seeds the
  starter set with set-if-absent on every sweep (so owner edits are never overwritten).
  `Rule` must be one of the engine's known rule keys (the starter ids); a new automatic rule
  needs code, a manual badge never does.
- **Awards:** `Fantasy/<sport>/<season>/Badges/<uid>/<awardId>` =
  `{Badge, Gw?, At, Source: 'auto'|'manual', Note?, By?}`.
  - Auto ids are deterministic: `<badgeId>_gw<N>` (weekly) or `<badgeId>_season`.
  - Manual ids: push ids written by the Manager (`Source: 'manual'`, `By: <admin uid>`).
- **Push claims:** `Fantasy/<sport>/<season>/BadgePushClaims/<uid>/<awardId>` (once-only,
  like `News/PushClaims`).
- **Trophy cabinet:** season-end `champion`/`runnerUp`/`thirdPlace` ALSO write an award to
  the existing cabinet `Users/<uid>/Awards/<id>` using the existing `Award` shape
  (`TrophyId: 'fantasy_<badgeId>'`, `Name`, `Icon`, `IconType: 'builtin'`, `Tier`
  gold/silver/bronze, `Sport`, `ScopeType: 'fantasy'`, `ScopeId: '<sport>/<season>'`,
  `Season`, `Context: 'Infinite Fantasy'`, `Date`, `Source: 'auto'`; id via the same
  deterministic-id helper the Manager's award engine uses). The fan app's trophy cabinet must
  render `ScopeType 'fantasy'` sensibly.
- **Rules (both rules files):** BadgeCatalog and Badges public read; writes admin only
  (server writes bypass rules). BadgePushClaims no client access.

## 4. Engine (functions)

- After every finalize of week N (same pipeline, rerun-idempotent): recompute all AUTO weekly
  awards for week N — write earned ones, remove previously-written auto awards for week N no
  longer earned. A voided week removes its auto awards. Manual awards are never touched.
- Season-end awards: computed when the season-end condition holds (sweep check + after the
  final week's finalize); rerun-safe; cabinet writes once (deterministic id).
- Inactive catalog entries (`Active: false`) are not awarded (existing awards stay).
- **Push:** a trigger on `Fantasy/{sport}/{season}/Badges/{uid}/{awardId}` CREATE sends one
  push to that user ("You earned Captain Genius 🏅" / manual: "You received a badge: <Name>"
  + Note), guarded by the once-only claim, payload `{type:'fantasy', sport, season,
  badge: awardId}` → opens Fantasy. Paused (Open/Locked) seasons: no auto awards are computed
  (engine stands down) — manual awards still push.
- **Test season (S15 fill):** the replay produces Badges + claims (stub pusher) for the test
  season, including season-end badges (the replay must read `Futsal/15/Finished`); the fill
  allowlist gains `Badges` and `BadgePushClaims`; nothing outside `Fantasy/Futsal/15/` is
  written (no cabinet writes from test data).

## 5. Fan app

- **Badge shelf** (horizontal wrap of badge chips: icon/picture + name + "×3" when repeated):
  on the Infinite-profile Fantasy tab (manager section) and at the top of the manager squad
  viewer. Tap a chip → bottom sheet: name, description, when earned ("GW3, GW7, GW9" /
  "Season 15"), and the owner's note for manual ones.
- **Leaderboard:** a small badge-count chip (`Icons.military_tech` + N) next to the manager
  name on Overall and Gameweek rows (only when N > 0); wraps at 360 px.
- Catalog + awards are live streams; unknown/removed catalog ids fall back to a generic badge.

## 6. Manager

- **Fantasy → Badges** page: catalog list (icon, name, description, Auto/Manual tag, Active
  switch, "N managers"), **New badge** / edit (name, description, icon from a curated list or
  uploaded picture → Storage `FantasyBadges/<badgeId>.<ext>`, Kind; Auto requires choosing an
  existing rule key; Repeatable), never delete (Active off hides it).
- **Fantasy profile detail** gains a **Badges** section: earned list (grouped, with weeks and
  notes) + **Give badge** (pick badge, optional note, optional gameweek → confirm) + remove a
  badge (confirm; removing an auto badge only lasts until that week is re-scored — say so).

## 7. Testing

Functions: each rule with hand-made squads (ties, bench boost exclusion, voided week,
rerun removes no-longer-earned, manual untouched, season-end + cabinet id determinism,
push once-only incl. manual). Fan: parsers, shelf/sheet/count widgets (light/dark, 360 px).
Manager: catalog CRUD, give/remove with confirm, guard test. S15 fill dry run passes.
