# Share Match Card — Design Spec

**Date:** 2026-06-23
**Status:** Visual approved by owner (Option B + leaders + follow CTA, app stat icons)
**App:** Fan (`infinite_sports_flutter`) only — no Manager changes.
**Branch:** `zaya-share-card` (off `zaya-features`). Commits stay local until owner says to push.
**Roadmap:** Phase 1 item #7 ("one-tap share match card to WhatsApp").

---

## 1. Overview
From a tournament match (upcoming, live, or finished), the fan taps a **Share** button and the app generates a branded match image and opens the system share sheet (WhatsApp, Instagram, Messages, etc.). The card is designed to be *player-driven viral marketing*: it celebrates the result (so winners share) and features standout players by name (so featured players share). Every shared card carries a "Follow Infinite Sports" call-to-action.

## 2. The card (visual — locked)
A square-ish portrait image (1080 × 1350), **split vertically into the two teams' home colors** (Option B). Fixed brand design, independent of app light/dark theme so the exported image is identical for everyone.

**Layout, top to bottom:**
- **Header band (overlay):** `🏆 {Tournament Name} · {Stage}` (e.g. "Test Tournament 2026 · Quarterfinal"), white text over the split.
- **Two colored halves**, each containing (top→bottom):
  - Team **logo** (real `logoUrl`; shield fallback if missing).
  - Team **name** (uppercase).
  - Team **score** (large) — omitted/replaced for upcoming (see states).
  - **👑 WINNERS** tag on the winning side only (finished + decided).
  - **Leaders block — 4 aligned rows**, one per stat category, using the app's stat PNG icons:
    - `assets/goal.png` Goals · `assets/assist.png` Assists · `assets/dpl.png` DPL · `assets/save.png` Saves
    - Each row shows that team's **top 2** for the category as `Name N · Name N`. Empty category shows `—`.
    - Rows are fixed-height and start at the same Y on both halves so the two sides line up.
- **Center pill** (overlay, depends on state): `FINAL` / live score `2-1` / kickoff `AUG 27 · 10:00 AM`.
- **Footer band:** `▶ Follow Infinite Sports` (dark band, brand-red accent on the name).

**Match states:**
| State (`match.status`) | Center pill | Scores | Leaders | Winner tag |
|---|---|---|---|---|
| Upcoming (0) | Date + kickoff time | hidden | hidden (none yet) | no |
| Live (1) | Live score + "LIVE" | shown | shown (so far) | no |
| Finished (2) | `FINAL` | shown | shown | on winner; none if draw |

## 3. Architecture & components

### 3a. Pure helper — `lib/misc/share_card_leaders.dart`
- `Map<String,int>` tallies already exist via `single_match_tallies.dart`. Add a pure function:
  - `List<LeaderEntry> topNForStat(TournamentMatch match, bool team1, String stat, {int n = 2})` returning the team's top-N `{name, count}` for `stat ∈ {goals, assists, dpl, saves}`, sorted by count desc then name; ties broken by name; zero-count players excluded.
  - `LeaderEntry { final String name; final int count; }`.
- Stat keys map to the match activity event keys (goals/assists/dpl/saves). Reuse the existing per-match tally logic; do not re-implement parsing if a helper already returns per-player per-stat counts — extend it if needed.
- Fully unit-tested (pure, no Flutter).

### 3b. Card widget — `lib/widgets/share_match_card.dart`
- `ShareMatchCard` — a `StatelessWidget` with a **fixed logical size** (e.g. 360 × 450 logical px; captured at `pixelRatio: 3` → 1080 × 1350). Inputs: `match`, `team1`, `team2`, computed leader lists, tournament name, formatted date/time.
- Hard-coded brand palette (no `Theme.of`): team `homeColor` halves, white text, `infiniteSportsPrimaryColor` accents, dark footer.
- Uses `Image.asset` for stat icons and `Image` for team logos (passed in as already-loaded `ImageProvider`s — see render flow).

### 3c. Render-and-share service — `lib/misc/share_match_card_service.dart`
- `Future<void> shareMatchCard(BuildContext context, {match, team1, team2, tournamentName})`:
  1. Compute leaders via the pure helper.
  2. **Pre-load** both team logo images (`precacheImage` of `CachedNetworkImageProvider`/`NetworkImage`) so they paint into the capture; fall back to shield on error.
  3. Render `ShareMatchCard` offscreen via a `RepaintBoundary` + `GlobalKey` (offscreen overlay or `ui` pipeline), wait one frame, `boundary.toImage(pixelRatio: 3)` → `toByteData(png)`.
  4. Write bytes to `${getTemporaryDirectory()}/match_card_{id}.png` (**add `path_provider`**).
  5. `SharePlus.instance.share(ShareParams(files: [XFile(path)], text: shareText))`.
  6. `shareText`: `"{Team1} {s1}–{s2} {Team2} · {Tournament} — follow live on Infinite Sports."` (upcoming: `"{Team1} vs {Team2} · {Tournament} — {date} {time}. Follow live on Infinite Sports."`).
- All wrapped in try/catch → on failure show `SnackBar('Couldn\'t create the share card.')`.

### 3d. Entry point — `lib/tournament_match_detail.dart`
- Add an `IconButton(Icons.share)` (then `Icons.ios_share` style) to the existing `SliverAppBar.actions` (alongside the link button), calling `shareMatchCard(...)` with `_match`, `team1`, `team2`, tournament name.

## 4. Dependencies
- **Add** `path_provider` (first-party, for the temp PNG path). `share_plus ^12.0.1` already present (uses `SharePlus.instance.share(ShareParams(...))`).

## 5. Error handling & edge cases
- Missing/failed logo → shield placeholder (already in card design).
- Upcoming match with TBD team(s) (feeder placeholder, no real team): show the placeholder label as the team name; still shareable.
- Render or share throws → caught, snackbar, no crash.
- Draw (finished, equal score) → no 👑.
- Long player names → ellipsis within the row to preserve alignment.

## 6. Testing
- **Unit:** `topNForStat` — ordering, ties, zero-exclusion, fewer-than-2, all four stats.
- **Widget:** `ShareMatchCard` builds without overflow for each state (upcoming / live / finished / draw) and with missing logos.
- **Manual:** on-device — share from a finished match (leaders + 👑), a live match, and an upcoming match; confirm the image opens in WhatsApp and looks right.

## 7. Out of scope (later)
- Sharing from the bracket/fixtures list (this spec is the match-detail entry point only).
- Custom per-tournament card themes; animated/video cards.
- A separate "story" aspect ratio — single portrait card for now.

## 8. Review checklist (Paul)
- New files: pure leaders helper (+tests), `ShareMatchCard` widget, render/share service. One new dependency: `path_provider`. One edit to `tournament_match_detail.dart` (AppBar action). No Firebase schema changes, no new reads. Theme-independent fixed-design image.
