# Substitution In/Out — Design Spec (Cohesion Spec 3 of 3)

**Date:** 2026-06-14
**Status:** Approved by owner (brainstorm 2026-06-14, FotMob screenshot ref)
**Branches:** `zaya-live-scores` (Manager) + `zaya/live-scores` (fan)
**Part of:** "Live Tournament Cohesion" wave. Build after Specs 1 & 2.

---

## 1. Overview

Today a substitution stores a single player name, so fans can't tell who came on vs off. Make it capture **both** players and show it FotMob-style in the fan timeline: **green ↗ player IN** (green text) over **red ↘ player OUT** (red text), at the minute.

### In scope
- **Manager:** recording a Substitution asks for two players — "Coming OFF" then "Coming ON" — and stores both.
- **Storage:** an activity entry that carries both names while staying compatible with `flattenActivityBucket` / the undo-stat editor / the stats engine.
- **Fan:** timeline row renders the two names with arrows + colors.

### Out of scope
- Subs still contribute **no** player counter (unchanged); they're timeline-only.

---

## 2. Storage format

Activity entries are `{EventType: value}` under `Team{1|2}Activity/{minute}`. For a substitution, the value becomes a small map:
```
{ "substitution": { "Off": "Jamal Musiala", "On": "Deniz Undav" } }
```
- `flattenActivityBucket` already does `entry.map((k,v)=>MapEntry(k.toString(), v))` — it preserves the nested map as the value, so flatten/remove still work (remove deletes the whole entry regardless of value shape).
- `tournament_stats_engine` already **skips** substitution (no counter) in both apps — no stats impact.
- **Undo-stat editor (`match_activity_editor.dart`):** `RecordedStat.playerName` currently does `e[type].toString()`. Special-case substitution: build a readable label `"{On} ↗ / {Off} ↘"` (or `"On ⇄ Off"`) and set a flag `isSubstitution = true`. **Remove** is allowed (removes the sub). **Move-to-player (reassign)** is **hidden/disabled** for substitution rows (reassigning a single player doesn't apply to a two-player sub). The "Recent stats" panel shows the sub with both names and only the Remove action.
- Back-compat: an old substitution stored as `{substitution: "Name"}` (scalar) still parses — treat the scalar as the OUT player, ON empty; fan shows just the red ↘ name. No crash.

---

## 3. Manager capture (`lib/ui/tournaments/live_scoring_page.dart`)

When the scorekeeper taps **🔁 Substitution**, instead of the single-player picker, run a two-step pick from the team's players:
1. Dialog "Coming OFF — pick player" → player A.
2. Dialog "Coming ON — pick player" → player B (exclude A from the list).
Then append the activity entry `{substitution: {Off: A.name, On: B.name}}` at the current minute via the existing `appendMatchActivity` path (it already accepts an arbitrary entry map — confirm and pass the nested value).

Other event types are unchanged (still single-player). Keep the change isolated to the substitution branch of `_recordEvent`.

---

## 4. Fan timeline display (`lib/tournament_tabs/match_facts_tab.dart`)

In the event-row builder, when `eventType == 'substitution'`:
- Parse the value: if it's a map, read `On`/`Off`; if it's a scalar string (legacy), treat as `Off` only.
- Render two stacked lines on the team's side:
  - `↗ {On}` in green (`Color(0xFF0A7D2C)`, weight 600)
  - `↘ {Off}` in red (`Color(0xFFC62828)`, weight 600)
- Keep the existing substitution icon (`assets/substitution.png`) as the row's center/minute marker, consistent with other event rows. Left/right side placement follows the same team-side logic the timeline already uses for other events.

---

## 5. Edge cases
- **Only one player chosen / cancel mid-flow:** if the scorekeeper cancels the second pick, record nothing (no half sub). 
- **Legacy scalar sub:** shows red ↘ name only (no green line). 
- **Undo of a sub:** Remove deletes the whole `{substitution:{…}}` entry; recompute (on Final) unaffected since subs never counted.
- **Same player off & on:** Manager excludes the already-picked player from the second list, so this can't happen.

## 6. Testing
1. **Unit (both apps):** `flattenActivityBucket` preserves a nested substitution entry; `recordedStatsForMatch` labels a sub with both names + `isSubstitution=true` + Remove-only; legacy scalar sub parses as Off-only. Stats engine: a substitution yields no player counter (regression guard).
2. **Widget (fan):** timeline renders green ↗ On / red ↘ Off for a map sub; renders red ↘ only for a legacy scalar sub.
3. **Manual:** Manager — record a sub (off then on); fan timeline shows both with arrows/colors at the minute; remove it from the Recent-stats panel and confirm it disappears; confirm player goal/assist counters are unchanged by the sub.

## 7. Review checklist (Paul & Bronsin)
- Substitution value changes scalar→map; flatten/remove/stats untouched in behavior (subs were already counter-less); reassign hidden for subs.
- Back-compat path for legacy scalar subs is explicit.
- Change is contained: Manager `_recordEvent` sub branch + `match_activity_editor` sub labeling; fan `match_facts_tab` sub row. No schema migration of old data required.
