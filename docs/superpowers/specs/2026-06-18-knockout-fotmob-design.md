# Knockout Tab — FotMob Redesign (Design Spec)

**Date:** 2026-06-18
**Status:** Approved by owner (FotMob reference screenshots, light + dark)
**Branch:** `zaya/knockout-redesign` (fan, off `zaya/predictions`)
**App:** Fan only. UI rebuild of `lib/tournament_tabs/knockout_tab.dart`. No schema change.

---

## 1. Overview
Rebuild the tournament Knockout tab to look like FotMob's bracket: boxed match cards connected by lines, a showcase **Final hero card** with a trophy + champion theming, a **3rd-place (Bronze-final)** card, kickoff times, and tap-to-open-the-match. Works in light and dark mode.

## 2. Data (all already available)
- `TournamentMatch`: `stage` (→ `TournamentStage`, `.isKnockout`, `.label`, `.sortOrder`, `finalStage`/`thirdPlace`), `bracketPosition`, `team1Id/team2Id`, `team1Seed/team2Seed`, `team1Score/team2Score`, `matchStatus` (pending/live/finished), `winnerTeamId`, `loserTeamId`, `time`, `date`, `locationInfo` (venue), `id`.
- `TournamentTeam`: `name`, `logoUrl`, `homeColor` (Color?), `awayColor`.
- Penalties: if the model exposes penalty fields use them; otherwise omit the "(n)" pens suffix. (Check `TournamentMatch`; do NOT invent a field.)
- Trophy asset: `assets/trophy.png` (added).

## 3. UI

### Round chips (top) — keep
Round of 16 · Quarter-final · Semi-final · Final (only rounds that exist), tappable. Selected chip drives the view below. Default to the first existing round.

### Non-final rounds (R16 / QF / SF) — bracket with connectors
- The selected round's matches as **boxed cards** in a vertical column (FotMob style):
  - Top: venue name (grey, small) + kickoff date/time (right or under).
  - Two team rows: `[logo] name ........ score`. Loser name struck through + dimmed once final; winner bold. TBD slots show a shield + "TBD"/"Seed #n".
  - Live match: small red "LIVE" strip.
- To the **right**, the **next round's** resulting cards shown **faded**, with **connector lines** drawn from each pair of this-round cards to their successor (CustomPainter). Matches the QF reference.
- **Tap a card → the match detail page** (`TournamentMatchDetailPage`) for that game — NOT the team page.

### Final round — hero + bronze
- **Hero final card** (full width, taller): a blue gradient by default. Layout: `[team1 logo] score(pens) — 🏆 — score(pens) [team2 logo]`, team short-names under logos, then **venue + date/time** below. Uses `assets/trophy.png` centered.
  - **Champion theming:** once final is decided, recolor the hero gradient using the **winner's `homeColor`** (fallback: gold/brand if null). Winner score bold; loser dimmed.
- **Bronze-final card** (3rd place, if a `thirdPlace` match exists): smaller card below the hero — venue, both teams + scores, loser struck through.
- Tap hero/bronze → the respective match detail.

### Card styling (light + dark)
Boxed cards use `Theme.of(context).cardColor` with rounded corners + subtle border/shadow; connector lines use a muted `dividerColor`. The hero gradient + trophy read well on both themes.

## 4. Edge cases
- No knockout matches → existing "Knockout stage not yet available".
- TBD teams (not yet decided) → shield + placeholder label (no tap to match if the match has no real teams yet / not played).
- No 3rd-place match → omit the bronze card.
- Single round only → no connectors (nothing to connect to).
- Champion `homeColor` null → gold/brand hero.

## 5. Testing
- Widget: a boxed match card renders teams/score/time + strikethrough loser; tapping invokes the match-detail nav (or a callback). Final hero renders trophy + both teams; champion tint applied when finished. (Mirror existing fan widget-test patterns; build `TournamentMatch`/`TournamentTeam` as other tests do.)
- Manual: open a tournament with a bracket → chips switch rounds; connectors link rounds; tap a card → match opens; on the Final chip the hero + bronze show; finishing the final recolors the hero to the winner's jersey color; light + dark both look right.

## 6. Review checklist (Paul)
- Fan-only; `knockout_tab.dart` rebuild + a connector CustomPainter + `assets/trophy.png`. No data/schema change. Uses existing `TournamentTeam.homeColor`.
