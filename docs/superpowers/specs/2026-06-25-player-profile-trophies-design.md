# Player Profile — Trophy & Accomplishment System (Sub-project 1) — Design Spec

**Date:** 2026-06-25
**Status:** Approved by owner (built-in icons + tiers now / custom upload later; auto-awards on "Mark Finished"; 3-part split; start with trophies).
**Apps:** MANAGER (`InfiniteSportsManagerFlutter`) — catalog + assignment + auto-award engine. FAN (`infinite_sports_flutter`) — basic trophy cabinet on the profile (full profile redesign is sub-project 2).
**Branches:** `zaya-trophies` off `zaya-features` in each repo. Commits local until owner says to push.
**Part of:** Player Profile revamp. Sub-project 2 = profile redesign (career stats + history + beautiful cabinet). Sub-project 3 = delight (shareable profile card, auto milestone badges, timeline, "year in review", compare).

---

## 1. Overview
Give players a **trophy cabinet** of accomplishments. Trophies are an **extensible catalog** the admin defines (and grows every year). Each trophy is either **automatic** (computed and handed out when a competition is marked Finished) or **manual** (admin assigns subjective ones like Young Talent / MVP). Awards attach to a player's account (`uid`) and render in their cabinet. Additive only — no existing nodes change.

## 2. Identity (the gate)
A trophy can only appear on a profile if the player's roster entry is **linked to a user account (`uid`)**:
- **League** rosters store `UID` when a player is added linked (existing `Name+uid` flow); the fan profile already aggregates league career stats by `uid`.
- **Tournament** rosters store an optional `UID` (Manage Rosters editor).
- **Auto-awards** are written only for roster entries that have a `uid`; unlinked players are **skipped** (count logged). **Manual assignment** picks a user from the linked-users list.
- This sub-project adds a **"pick user" selector** (searchable Users list) to the assignment screen so linking is no longer free-text. A self-serve "claim my profile" flow is **out of scope** (later).

## 3. Data model (additive)

### 3a. Global catalog — `Trophies/{trophyId}`
```
Trophies/{trophyId}:
  Name:     "Golden Boot"
  Kind:     "auto" | "manual"
  Rule:     "<ruleKey>"          // present only when Kind == "auto"
  Sport:    "Futsal" | "Basketball" | "Flag Football" | "Soccer" | ""   // "" = any sport
  IconType: "builtin" | "url"
  Icon:     "<builtin key>" | "<https url>"
  Tier:     "gold" | "silver" | "bronze"
  Active:   true
  CreatedAt: <epoch ms>
```
- `trophyId` = Firebase push id.
- **Custom upload** (`IconType:"url"`) is modeled now but the upload UI ships later; the built-in picker ships now.

### 3b. Auto rule keys (what an "auto" trophy can compute)
Team awards (→ every linked player on that team):
- `champion`, `runnerUp`, `thirdPlace`

Individual stat-leader awards (→ leading player(s); ties share):
| ruleKey | Stat | Sports |
|---|---|---|
| `goldenBoot` | most Goals | Futsal, Soccer |
| `mostAssists` | most Assists | Futsal, Soccer, Basketball |
| `bestGoalie` | most CleanSheets, tiebreak Saves | Futsal, Soccer |
| `defensivePlayer` | most DPL | Futsal, Soccer (DPL exists on tournament rosters) |
| `mostPoints` | most total points | Basketball |
| `mostRebounds` | most Rebounds | Basketball |
| `mostThreePointers` | most ThreePoints | Basketball |
| `mostTouchdowns` | RushingTD+ReceivingTD+PassingTD | Flag Football |
| `mostInterceptions` | Interceptions | Flag Football |

The Add-Trophy form only offers rule keys valid for the chosen Sport. (Vocabulary mirrors the existing `PredictionConfig.Categories`.)

### 3c. Per-player award — `Users/{uid}/Awards/{awardId}`
```
Users/{uid}/Awards/{awardId}:
  TrophyId: "<catalog id>"
  Name:     "Golden Boot"        // denormalized for instant cabinet load
  Icon:     "<builtin key|url>"
  IconType: "builtin" | "url"
  Tier:     "gold" | "silver" | "bronze"
  Sport:    "Futsal"
  ScopeType:"tournament" | "league"
  ScopeId:  "<tournamentId>" | "<sport>"
  Season:   "5"                  // league season number, or ""
  Edition:  "2026"               // tournament edition, or ""
  Context:  "Futsal · Season 5"  // human label shown under the trophy
  Date:     "MMDDYYYY"
  Source:   "auto" | "manual"
```
- **Idempotency:** for auto-awards, `awardId` is a **deterministic, sanitized key** = `"{trophyId}_{scopeType}_{scopeId}_{season|edition}"`. Re-finishing a competition overwrites the same node rather than duplicating. Manual awards use a push id.
- The cabinet reads **only** `Users/{uid}/Awards` (one node) — no catalog read needed at display time.

## 4. Automation — on "Mark Finished"
A new **award engine** (Manager-side, mirrors the bracket-resolver pattern). When the admin marks a competition Finished it runs `awardForTournament(tid)` / `awardForLeagueSeason(sport, season)`:
1. Load **active auto-trophies** whose Sport matches (or is `""`).
2. For each: compute recipients via its `Rule`:
   - **Team rules** — determine the 1st/2nd/3rd team, then collect every roster player with a `uid`.
     - *Tournament:* champion = winner of the Final match; runnerUp = its loser; thirdPlace = winner of the Third-Place match (from the bracket/matches).
     - *League:* champion = standings rank 1, runnerUp = rank 2, thirdPlace = rank 3 (computed from the season's games — reuse existing standings logic).
   - **Stat rules** — scan the competition's rosters/stats, find the max for the stat, award all players tied at the max (with a `uid`).
3. Write `Users/{uid}/Awards/{deterministicId}` for each recipient. Idempotent; never throws (try/catch, logs skipped-unlinked count).
- **Pure compute helpers** (no Firebase) produce `[ (uid, trophy, context) ]` and are unit-tested; the service does the writes.

## 5. Manager admin UI
- **Global `/trophies` route** (new dashboard/menu tile): list the catalog (icon, name, tier, auto/manual + rule, sport). **Add / Edit / Deactivate** a trophy: name, Kind toggle, Rule picker (auto only, filtered by sport), Sport dropdown, **icon picker** (built-in grid), tier selector.
- **Assign Trophy** (manual): pick a trophy from the catalog → **pick a user** (searchable Users list) → context (free text, or pick a tournament/season) → writes one award. Also surfaces an **Undo / remove award** action.
- **Auto hook:** call the award engine from the existing tournament **Mark Finished** flow and the league-season finish flow. A **"Recompute Awards"** button (like "Recalculate Stats") re-runs it safely (idempotent) if rosters/uids were fixed after finishing.

## 6. Fan — basic trophy cabinet (this sub-project)
- On the existing profile (`lib/playerpage.dart`), add a **"Trophy Cabinet"** section reading `Users/{uid}/Awards`: a grid of trophy icons (tier-colored), each with name + context; tap → a sheet with full detail (sport, season/edition, date). Empty state: "No trophies yet — go win some!"
- Built-in icon keys map to bundled assets (Section 8). `url` icons load via network with a trophy fallback.
- **The beautiful profile + cabinet redesign is sub-project 2** — this is the minimal, testable display.

## 7. Build phases (ship value early)
- **1A** — Catalog + manual assign + `Users/{uid}/Awards` + basic fan cabinet (end-to-end, manual).
- **1B** — Auto-award engine on **tournament** Finish (champion/runner-up/3rd + stat leaders).
- **1C** — Auto-award engine on **league-season** Finish (per-sport leaders + standings 1/2/3).

## 8. Assets (built-in icon set)
Bundle a small curated set under `assets/trophies/` (admin picks one): `trophy_gold`, `medal`, `boot` (Golden Boot), `gloves` (keeper), `shield` (defense), `star` (MVP/young talent), `basketball`, `football`, `cup`. (~9 icons.) Tier color is applied as an accent. Reuse `assets/trophy.png` where fitting.

## 9. Error handling & edge cases
- Re-finish / Recompute → idempotent (deterministic ids), no duplicates.
- Stat ties → all tied linked players get the trophy.
- A player linked to teams in multiple competitions → one award per competition (expected).
- Deactivating/deleting a catalog trophy → existing awards remain (denormalized); it just stops being granted.
- Unlinked roster players → skipped; engine logs how many were skipped so the admin can link them and Recompute.
- Manual award removal → deletes that `Awards/{id}` node.

## 10. Testing
- **Pure (Manager):** team-placement resolution (tournament final/3rd; league standings 1/2/3) and stat-leader selection per sport (ties, zero-exclusion, per-sport stat math) → recipient lists. Idempotent id generation.
- **Manager:** add/edit catalog round-trips; manual assign writes an award; Mark-Finished triggers the engine; Recompute is idempotent.
- **Fan widget:** cabinet renders awards (built-in + url icons), empty state, tap-detail.
- **Manual:** define a couple of trophies, finish the test tournament, confirm champion + Golden Boot land on linked players' cabinets; manually assign a "Young Talent".

## 11. Out of scope (later sub-projects / phases)
- Profile **visual redesign** + career stats + participation history (sub-project 2).
- Delight: shareable profile card, auto-earned milestone badges, career timeline, "year in review", compare-with-teammate (sub-project 3).
- Self-serve **"claim my profile"** linking; **custom icon upload** UI; retroactive awarding to players who link *after* a competition finished.

## 12. Review checklist (Paul/Bronsin)
- New additive nodes only: global `Trophies/`, per-user `Users/{uid}/Awards/`. No existing node changes.
- Manager: new `/trophies` catalog + assign screens; award engine hooked into existing Finish flows + a Recompute button; pure recipient-computation helpers with tests.
- Fan: read-only cabinet section on the profile.
- Identity by `uid`; unlinked players skipped (documented), assignment uses a user picker.
