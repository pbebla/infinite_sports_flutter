# Fan-App Stat-Icon Redesign — Design

**Date:** 2026-05-30
**Repo:** infinite_sports_flutter (fan app)
**Branch:** zaya/tournament-enhance-app-manager
**Status:** Approved (pending written-spec review)

---

## Goal

Replace the match-timeline stat icons (and the matching icons on the fixtures leader
strip) with the owner's own custom flat icon set, and add a permanent **icon legend**
("What the icons mean") to the bottom of every match's **Facts** tab so fans can learn
what each icon stands for.

## Background

The tournament feature shows a per-match **Facts** tab (`lib/tournament_tabs/match_facts_tab.dart`)
with a chronological event timeline (goal, foul, card, save, …) and a "Match Leaders"
section. The fixtures list (`lib/tournament_tabs/fixtures_tab.dart`) shows a compact
"leaders strip" of top performers on finished match cards.

Today these icons are a mix of a `⚽` emoji, FontAwesome `shoePrints`, Material icons,
and a hand-built two-rectangle widget for the second-yellow card — visually inconsistent.
The owner has drawn a single, cohesive flat icon set (13 icons) and wants those exact
images used instead.

## Scope

**In scope:**
1. Bundle the owner's 13 icons as image assets.
2. A shared icon helper + a reusable icon widget used by both render locations.
3. `match_facts_tab.dart`: timeline icons use the new set; remove the now-redundant
   "(P)" penalty text tag.
4. `match_facts_tab.dart`: add the "What the icons mean" legend at the bottom.
5. `fixtures_tab.dart`: the 4 leader-strip icons (Goal / Assist / Save / DPL) use the
   new set.

**Out of scope (left untouched):**
- Legacy league pages (Futsal / Basketball / Flag Football) and their existing flat
  `assets/*.png` icons (`goal.png`, `assist.png`, `foul.png`, `yellow.png`, `red.png`).
- The "Match Leaders" rows themselves (they use text labels + a number badge — unchanged
  except the small leader icons are not part of that section).
- Any manager-app or Firebase schema change. Event types stored in Firebase are unchanged.
- Player-name rendering. The timeline already shows the full recorded player name
  (`match_facts_tab.dart:219`); no abbreviation is added or removed.
- The deferred second-yellow-card **notification** in the manager app (separate brainstorm).

## Confirmed Decisions (from brainstorming)

- **Artwork:** Use the owner's exact raster icons, sliced from `SoccerStats.png`. Not redrawn SVGs.
- **Dark mode:** Each icon sits on a **white rounded chip** so the dark line-art stays
  visible in both light and dark themes.
- **Coverage:** Replace icons in the match timeline **and** the fixtures leader strip.
- **Legend:** Permanent, on every match's Facts tab, below "Match Leaders". Two columns
  running downward — left column flush left, right column nudged toward the middle.
  Shows all 13 icons. Layout, wording, and order approved via mockup.
- **Timeline text:** Icon + player name only. No stat-type word after the name, and the
  old "(P)" penalty tag is removed (the dedicated penalty icons make it redundant).

---

## The 13 Icons

Sliced from `SoccerStats.png` and bundled under `assets/stat_icons/`:

| Asset file (`assets/stat_icons/`) | Event type(s) (lowercased, as stored) | Legend label |
|---|---|---|
| `goal.png`           | `goal`          | Goal |
| `own_goal.png`       | `own goal`      | Own goal |
| `goal_penalty.png`   | `penalty goal`  | Goal by penalty |
| `penalty_missed.png` | `penalty missed`| Missed penalty |
| `penalty_saved.png`  | `penalty saved` | Saved penalty |
| `save.png`           | `save`          | Save (goalkeeper) |
| `assist.png`         | `assist`        | Assist |
| `substitution.png`   | `substitution`  | Substitution |
| `yellow_card.png`    | `yellow card`   | Yellow card |
| `red_card.png`       | `red card`      | Red card |
| `second_yellow.png`  | `second yellow` | Second yellow (= red) |
| `foul.png`           | `foul`          | Foul |
| `dpl.png`            | `dpl`           | DPL — Defensive Play (Tackle, Steal, Block) |

These 13 event types match the authoritative list in `_iconForEvent` exactly — nothing
missing, nothing extra.

---

## Architecture

### New file: `lib/tournament_tabs/stat_icon.dart`

A small, self-contained unit with one responsibility: map an event type to the owner's
icon asset and render it consistently. Used by **both** `match_facts_tab.dart` and
`fixtures_tab.dart` so there is a single source of truth.

It exposes:

1. **`String? statIconAsset(String eventType)`** — pure function. Lowercases/trims the
   input and returns the asset path (e.g. `'assets/stat_icons/goal.png'`) for any of the
   13 known event types, or `null` for an unknown type. This is the unit-testable piece.

2. **`statIconAssetForStat(String statName)`** — pure helper mapping the fixtures
   stat keys (`goals` → goal, `assists` → assist, `saves` → save, `dpl` → dpl) to asset
   paths, so the fixtures strip can reuse the same images.

3. **`StatIcon` widget** — renders the asset for a given event type inside a white
   rounded chip. Parameters: `eventType` (String), `size` (chip side length, default for
   timeline; smaller value passed by the fixtures strip). If `statIconAsset` returns
   `null`, it falls back to a neutral Material icon (`Icons.sports`) so an unexpected
   event type never crashes or shows a broken image.

   The white chip is always white (not theme-dependent) with a subtle rounded corner and
   light shadow, and the image is centered with padding — this is what keeps the dark
   line-art readable in dark mode.

### `lib/tournament_tabs/match_facts_tab.dart`

- **Replace `_eventIcon(String)`** so it returns `StatIcon(eventType: …)`. Remove the
  special cases: the `⚽` emoji (`goal`), the red `sports_soccer` (`own goal`), the
  FontAwesome `shoePrints` (`assist`), the hand-built two-rectangle `Stack`
  (`second yellow`), and the `"(P)"` penalty tag branch.
- **Delete `_iconForEvent` and `_colorForEvent`** — both become unused once `_eventIcon`
  no longer references them. (Confirmed: `_colorForEvent` is referenced only inside
  `_eventIcon`; `_iconForEvent` only inside `_eventIcon`'s penalty branch.)
- **Remove the `font_awesome_flutter` import** (line 2) — no longer used in this file.
- **Add `_buildIconLegend(BuildContext)`** and append it to the bottom `Column` in
  `build`, after `_buildMatchLeaders(context)`. The legend always renders (every match's
  Facts tab), including when there are no recorded events.
- The timeline row (`_buildEventRow`) already shows icon + full player name; no text
  change is needed there beyond what the `_eventIcon` swap accomplishes.

### `lib/tournament_tabs/fixtures_tab.dart`

- In `_buildLeadersStrip`, replace the per-stat icon rendering (the `emoji` / `faIcon` /
  `icon` branch, lines ~103–108) with `StatIcon(eventType: …, size: small)` driven by the
  stat key. Simplify `statDefs` to just `{label, stat}` (the color/emoji/faIcon fields are
  no longer needed for the icon, since the new icons carry their own color).
- Remove the `font_awesome_flutter` import **only if** it is otherwise unused in the file
  (verify during implementation; if other code uses `FaIcon`, keep it).

### Legend layout (`_buildIconLegend`)

- Section divider + bold heading **"What the icons mean"**.
- A 2-column layout running downward (a `Column` of `Row`s, or a `GridView`/`Wrap` with
  2 columns). Left column flush to the left padding; right column nudged toward the middle
  with extra left padding so it sits away from the left edge (matching the approved mockup).
- Each entry: a `StatIcon` (white chip) + a short text label from the table above.
- All 13 icons shown, in the approved order: Goal, Own goal, Goal by penalty,
  Missed penalty, Saved penalty, Save, Assist, Substitution, Yellow card, Red card,
  Second yellow, Foul, DPL.

### `pubspec.yaml`

- Add `- assets/stat_icons/` under the existing `flutter: assets:` list (Flutter does not
  recurse into subfolders, so the subfolder must be listed explicitly). The existing
  top-level `assets/` entry and `.env` entry stay.

---

## Data Flow

Firebase event map → `_parseActivity` → `{eventType, playerName, …}` → `_buildEventRow` →
`StatIcon(eventType)` → `statIconAsset(eventType)` → `Image.asset(path)` inside white chip.

No data is read or written differently; only the rendering of an already-parsed
`eventType` string changes.

## Error Handling

- Unknown / unexpected `eventType`: `statIconAsset` returns `null`; `StatIcon` falls back
  to a neutral Material icon. No crash, no broken-image box.
- Empty Facts tab (no events, no rosters): the existing "Match not started yet" / "No
  activity recorded" message still shows; the legend renders below it.

## Testing

- **Unit test** `test/stat_icon_test.dart`: assert `statIconAsset` returns the correct
  asset path for each of the 13 event types (case-insensitive), and `null` for an unknown
  type; assert `statIconAssetForStat` maps the 4 fixtures stat keys correctly.
- **`flutter analyze`**: must pass clean (in particular, no "unused element" warnings from
  the deleted `_iconForEvent` / `_colorForEvent`, and no unused-import warnings).
- **Manual on-device check by the owner** (visual): timeline icons render on the white
  chips in light and dark mode; the legend appears below Match Leaders with the approved
  2-column layout; the fixtures leader strip on finished matches shows the new icons.

## Files Summary

| File | Change |
|---|---|
| `assets/stat_icons/*.png` (13 files) | **Create** — the owner's sliced icons |
| `lib/tournament_tabs/stat_icon.dart` | **Create** — shared mapping + `StatIcon` widget |
| `test/stat_icon_test.dart` | **Create** — unit tests for the mapping functions |
| `lib/tournament_tabs/match_facts_tab.dart` | **Modify** — swap `_eventIcon`, delete dead helpers, drop "(P)", remove FA import, add legend |
| `lib/tournament_tabs/fixtures_tab.dart` | **Modify** — leader strip uses `StatIcon` |
| `pubspec.yaml` | **Modify** — register `assets/stat_icons/` |
