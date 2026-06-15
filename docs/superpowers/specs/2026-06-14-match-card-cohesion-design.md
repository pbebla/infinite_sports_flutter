# Match-Card Cohesion — Design Spec (Cohesion Spec 2 of 3)

**Date:** 2026-06-14
**Status:** Approved by owner (brainstorm 2026-06-14, mockups approved)
**Branches:** `zaya/live-scores` (fan) + `zaya-live-scores` (Manager — location library)
**Part of:** "Live Tournament Cohesion" wave. Build after Spec 1 (live stats).

---

## 1. Overview

Make the match detail page polished and sensible: a clean, aligned header; date shown only before kickoff; and the location moved out of the header into a tappable **Location card** under "Match Leaders" with venue + address + field, opening the device's map app for directions. To avoid re-typing venues for every game, the **Manager gets a reusable Location Library**: pick a saved venue/field from a dropdown, or add a new one (which is then saved for reuse).

### In scope
**Fan app:**
1. **Header alignment** — score, red `LIVE` badge, and running clock share one centered baseline aligned with the team crests/names (no too-high/low).
2. **Date logic** — show date (+ time) at the top of the header ONLY when the match hasn't started; once `status==1` (live), remove the date from the header. Finished matches keep the date + show `FT`.
3. **Location card** — under the "Match Leaders" section in the Facts tab: venue name (bold), field (e.g. "Field 1 · Turf", blue), full address (grey), and a "Get directions" affordance; tapping anywhere on the card opens the map-app chooser via `url_launcher`.
5. **Match Leaders = THIS match (owner-confirmed option A)** — the "Match Leaders" box in `match_facts_tab.dart` currently shows each player's whole-tournament stored totals (`p.statByName`). Change it to show leaders **for this match only** — categories **Goals, Assists, Saves, DPL** — derived from THIS match's `team1Activity`/`team2Activity` timeline (reuse the Spec-1 engine's event-counting, scoped to one match via a small `singleMatchPlayerTallies(match)` pure helper). Updates live as events are recorded. The location card (item 3) sits directly above this section.
6. **Team-detail Tournament History — current tournament row live** — on `tournamentteamdetail.dart`, the "Tournament History" card reads each tournament's STORED `Table` node once (correct for finished tournaments, stale for the live one). Make the row whose tournament == `widget.tournamentId` use the **live-derived standing** (the `ComputedTournamentStats` already computed on that page in Spec 1) so it matches the live "Tournament Record" card. Past tournaments keep their archived stored values.

**Manager app:**
4. **Location Library + structured capture** — in the match editor, choose a saved venue from a dropdown (which auto-fills address + field options) or "Add new venue"; pick/enter a field. Saved venues persist per tournament for reuse. The match stores a **structured location** (venue + address + field) plus a human string for back-compat.

### Out of scope
- Live stats engine itself (Spec 1, done), substitutions (Spec 3).

---

## 2. Data model

### Location library (Manager writes, per tournament)
Path: `Tournaments/{tid}/Locations/{locId}` =
```
Name     "Pioneer High School"
Address  "1290 Blossom Hill Rd, San Jose, CA 95118"
Fields   ["Field 1 · Turf", "Field 2 · Grass"]   // list of field labels for this venue
```
New `FirebasePaths.tournamentLocations(tid)` → `Tournaments/{tid}/Locations`.

### Structured location on the match (denormalized snapshot)
When a match is saved, write under the match:
```
Location/
  Venue    "Pioneer High School"
  Address  "1290 Blossom Hill Rd, San Jose, CA 95118"
  Field    "Field 1 · Turf"
MatchLocation  "Pioneer High School — Field 1 · Turf"   // existing string kept for back-compat
```
Storing a snapshot on the match means the fan reads location directly (no library lookup) and old behavior keeps working. New `FirebasePaths.tournamentMatchLocationInfo(tid, mid)` → `.../Matches/{mid}/Location`.

### Fan model (`lib/model/tournamentmatch.dart`)
Add a parsed `MatchLocationInfo? locationInfo` (Venue/Address/Field) from the `Location` map; fall back to the existing `matchLocation` string (venue only, no address) when `Location` is absent. Keep `matchLocation` as-is.

---

## 3. Fan UI

### Header (`lib/tournament_match_detail.dart`, `_buildScoreboardHeader`)
- **Scheduled (`status==0`):** centered date + time line at the top; crest — "VS" — crest below. No score.
- **Live (`status==1`):** NO date; centered block: score (big), red `● LIVE` badge, green `mm:ss` clock — all vertically centered to align with the crest baseline on each side. Reuse `MatchClockText`. Remove the old in-header location/date for live.
- **Finished (`status==2`):** date at top; final score + `FT`.
- Alignment: the center column and the two team columns share `CrossAxisAlignment.center` and equal fixed widths so the score/badge/clock never sit higher or lower than the crests.

### Location card (`lib/tournament_tabs/match_facts_tab.dart`)
Insert directly **above** the "Match Leaders" header (the `_buildMatchLeaders` section), as a bordered card:
- Leading 📍 tile (brand navy), then Venue (bold 15), Field (blue 13), Address (grey 12), and a small "🧭 Get directions" pill; trailing chevron.
- Whole card `InkWell` → on tap launch maps:
  `https://www.google.com/maps/search/?api=1&query=<urlencoded: address (or venue if no address)>`
  via `launchUrl(uri, mode: LaunchMode.externalApplication)` (mirror the existing `match.link` launch in `fixtures_tab.dart`).
- Render only if location info exists; otherwise omit the card (no empty placeholder).

---

## 4. Manager UI (`lib/ui/tournaments/manage_bracket_page.dart`, `_MatchEditorDialog`)

Replace the single free-text "Match location / field" field with:
1. **Venue dropdown** populated from the tournament's saved `Locations` (load via a `watch`/`get` on `Tournaments/{tid}/Locations`), plus a trailing **"+ Add new venue"** entry.
2. Selecting a saved venue auto-fills its address (read-only display) and populates a **Field dropdown** from that venue's `Fields` (with a "+ Add field" option to type a new one, which is saved back onto the venue).
3. **"+ Add new venue"** opens a small dialog: Name, Address, first Field → saves to `Tournaments/{tid}/Locations/{locId}` and selects it.
4. On match save, write the structured `Location` snapshot + the `MatchLocation` string (§2) via the existing `saveMatch` path (extend `TournamentMatch.toFirebaseMap` in the Manager model).

New Manager service methods on `TournamentService`: `getLocations(tid)`, `saveLocation(tid, loc)`, `addFieldToLocation(tid, locId, field)`. Keep them small and focused.

YAGNI: no delete/edit-venue UI in v1 (add-and-reuse covers the owner's automation goal; editing can come later if needed).

---

## 5. Edge cases
- **Old matches** (only `MatchLocation` string, no structured `Location`): fan shows venue-only card with maps query = the string; no address line. No crash.
- **No location at all**: header shows no location (already), and the Facts location card is omitted.
- **Maps app missing / launch fails**: wrap `launchUrl` in try/catch; on failure show a SnackBar "Couldn't open maps."
- **Empty library** (first tournament use): dropdown shows only "+ Add new venue."
- **Field typed but venue not saved**: still writes the snapshot onto the match (library save is best-effort; the match always gets its location).

## 6. Testing
1. **Unit (Manager, pure):** location-library serialization round-trip (Name/Address/Fields ↔ map); match `toFirebaseMap` includes structured `Location` + string.
2. **Unit (fan, pure):** `MatchLocationInfo` parse from `Location` map + fallback from `matchLocation` string; maps-URL builder encodes the address correctly.
3. **Widget (fan):** header shows date when scheduled, hides it when live, score/LIVE/clock aligned; location card renders venue/field/address and is tappable; omitted when no location.
4. **Manual:** Manager — add a venue once, reuse it on a second match via dropdown; fan — open the match, tap the location card → map app opens to the address; start the match → date disappears, header stays aligned.

## 7. Review checklist (Paul & Bronsin)
- New DB subtree `Tournaments/{tid}/Locations/**` (Manager writes, fan never needs it — fan reads the per-match `Location` snapshot).
- Per-match `Location` snapshot is additive; `MatchLocation` string retained for back-compat.
- `url_launcher` already a dependency; maps uses the standard Google Maps search URL (opens the OS app chooser).
- Manager match-editor change is contained to `_MatchEditorDialog` + 3 small service methods + model `toFirebaseMap`.
