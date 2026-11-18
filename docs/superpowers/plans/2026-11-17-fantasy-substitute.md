# Fantasy Substitute + Auto-subs on the Pitch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written 2026-11-17 on Opus 5.5. **Reviewed, amended and APPROVED by Fable 5.2 on 2026-11-17** (see "Fable review" at the end). Owner confirmed decision 4 and said go on 2026-11-17 ("yes rename it to replace, go ahead and build it"). Ready to build.

**Goal:** Let a fantasy manager swap a starter and a bench player of the same position for free before the deadline, and show the automatic substitutions that already happen in scoring on the pitch.

**Architecture:**
- **Part A (fan app only).** A `Substitute` action on the editable squad court, built on a new pure draft operation. It only moves picks between the draft's own slots, so money, transfers and the server are untouched.
- **Part B (additive server change + fan display).** Scoring records which starter each auto-sub replaced. The locked court and the leaderboard squad viewer then draw the sub in that starter's place and the starter on the bench, for that week only.

**Tech Stack:** Flutter/Dart (fan app `infinite_sports_flutter`), Firebase RTDB, Cloud Functions (TypeScript, vitest), flutter_test.

**Spec:** "Owner decisions" below (chat, 2026-11-17) + support ticket #5.

## Owner decisions (the spec)

1. Ticket #5 (a fantasy manager, 2026-11-17), verbatim: "I can’t sub in somebody from my bench for somebody in my starting lineup. I’d have to sell them and re-buy them but then I lose money."
2. Owner, verbatim: "agree with 5 lets do it". The agreed proposal:
   - **What:** a Substitute button. Tap a starter, tap Substitute, pick one of your bench players in the same position, and they trade places.
   - **Free:** no money, and it is not a transfer.
   - **Same position only.**
   - **Until the deadline**, like every other change.
   - **Armband:** if you bench your captain or vice-captain, the armband passes to the player coming on, and the app says so.
3. Owner, verbatim: "if one of your starter is not playing like he is absent the subsitute automatically replaces him and gets full score so for that manager the sub replaces the absent player and it will show on the soccer map and shows the points and once the games are done either the sub remains as a starter until manager changes him or he can go back to bench again automatically whichever you think makes more sense."
   - **Already built:** scoring has done the substitution since launch (`functions/src/lib/fantasy/squad_week.ts`, Dart twin `lib/fantasy/engine/squad_week.dart`). An absent starter is covered by the first bench player of the same position who played, at FULL points. If the captain did not play, the vice gets the armband. The Rules tab explains it.
   - **Missing:** the pitch does not show it. The sub stays drawn on the bench and the absent starter on the pitch.
   - **Decided (owner left it to us): the sub goes back to the bench after the week.** This is how scoring works today, because the saved squad never changes and the swap applies only to that week's points. It matches the fantasy game players know. The absent starter may be back next week, and nobody's lineup changes behind their back. No code is needed for this; the pitch shows the swap only for the week it happened.
4. **Owner confirmed 2026-11-17 ("yes rename it to replace"):** rename the chip action `Swap` (which sells the player and opens the market) to `Replace`, so it is not mistaken for the free Substitute. That mix-up is what ticket #5 describes. The "Needs a new spot" strip keeps its own `Swap` button; that is a different flow.

## Data contract (additive)

Each scored slot row gains the id of the starter an auto-sub replaced. It is written only on the bench player who came on:

| Where | Today | Added |
|---|---|---|
| `History/<gw>/<uid>/Breakdown[i]` (finalize) | `{playerId, countedTenths, multiplier, autoSubbedIn}` | `replaces: <starter playerId>` |
| `Live/Squads/<uid>/Slots[i]` (live) | `{p, c, x, s?}` | `r: <starter playerId>` |

Older rows have no `replaces`/`r`. That includes GW1, which was finalized before this change. Apps in the store ignore the new keys.

## Global Constraints

- Copy, exactly (fan app):
  - Chip action, when the tapped player has exactly ONE counterpart: `Substitute with <Counterpart>`. Tapping it swaps the two at once, with no second sheet. Today's formation has one bench defender and one bench attacker, so every starter is this case.
  - Chip action, when he has several counterparts (a bench player has two starters of his position): `Substitute`, which opens the sheet below.
  - The Substitute tile sits above the market tile, with `Icons.swap_vert`. The market tile `Swap` now reads `Replace` (owner decision 4); its icon and behaviour stay.
  - The sheet: title `Substitute <Name>`, line under it `Pick who swaps places. It's free and not a transfer.` Each row shows the candidate's name and position.
  - Armband passed: SnackBar `<Name> is now your captain.` or `<Name> is now your vice-captain.`
  - Rules tab, added to the "Auto-subs, captain & bench" section: `Before the deadline you can Substitute a starter and a bench player in the same position. It's free and it is not a transfer.`
  - Auto-sub on the pitch: the sub's chip shows his points as today, plus a small "came on" badge. The replaced starter's chip, drawn on the bench, shows `Out` and a small "went off" badge. Badge colours: green for on, the app's down red (`fantasyDownRed`) for off. Icons are `Icons.arrow_upward` / `Icons.arrow_downward` on the photo's TOP-LEFT corner (the captain / vice badge owns the top-right, `player_chip.dart:162`). Each badge has a semantics label: `Came on as a substitute` / `Did not play`.
- Substitute is offered only while the squad is editable, and only when the tapped player has at least one counterpart: same position, on the other side of the bench line. A keeper has none (there is no bench keeper), so his sheet has no Substitute.
- Substitute never changes money, prices, the transfer count or the chip in play. It only moves two picks between their slots. Checked: the app's transfer preview and the server's recount both count by player id only (`transfer_preview.dart` rule 7, `transfer_state.ts:160,176`); the squad rules validate each pick's shape, not who is on the bench; and the server's integrity judge counts starters, which a swap leaves unchanged.
- Substitute is a draft edit like every other one: it marks the draft unsaved and takes effect when the manager taps `Save squad`.
- Armbands are starter-only (existing invariant, `squad_picker_sheet.dart` "Armbands are starter-only"). A substitution that benches the captain or vice hands that armband to the player coming on.
- Display only: nothing in Part B changes a saved squad, a score or a rule. The swap shows only in the locked views of the week it happened.
- Light and dark mode for every new element; works at 360 px. Real-time streams only (no RTDB `get()`, no bare `.once()`). iOS parity: nothing platform-specific; the PR gets "verify on iPhone simulator" lines.
- Server and Dart engine twins stay faithful ports: `squad_week.ts` and `squad_week.dart` produce the same `replaces` for the same input. The golden fixtures pin it.
- Made-up names in tests. Commit trailer: the executing model's own `Co-Authored-By` line. Do not push, deploy or install without the owner's go.
- Branch: fan `zaya-fantasy-subs` (from `zaya-review-fixes` @ `3bd0b29`). It also carries the Team of the Week share-image fix, which is a separate commit and not part of this plan.

## Review Focus

1. **Benching the captain.** Substitute the captain for a bench player: the incoming player is captain, the SnackBar says so, and saving keeps the armband valid. Test in Task 1 (pure) and Task 2 (sheet → SnackBar).
2. **Substitute, then Save.** The saved squad has the two players' bench flags swapped. The transfer preview stays at 0 transfers with the same money left, and the save is not refused by the rules or the server's integrity judge (starter count unchanged). Test in Task 2.
3. **Two starters of a position absent, one bench player of that position.** Only the first absent starter (pick order) is replaced, and the pitch moves only that pair. The second absent starter stays on the pitch showing `Out`. Test in Task 3 (server + Dart) and Task 4 (display).
4. **A week scored before this change** (no `replaces`). Nothing moves. The bench player who came on keeps his place with the "came on" badge and his full points, so the picture is never wrong. Test in Task 4.
5. **The live week, before the absent starter's game is final.** No sub is shown until scoring makes it (the pending rule already keeps him on the pitch). The display follows the live rows only. Test in Task 4.

---

## Part A — Substitute

### Task 1: The draft's substitute operation

**Files:**
- Modify: `lib/fantasy/hub/squad_draft.dart` (`SquadDraftController`, next to `setPickAt` / `makeCaptain`; armband helpers `_clearArmbandFor`)
- Test: `test/fantasy/squad_draft_test.dart` (or the existing draft test file; grep `SquadDraftController(` under `test/fantasy/`)

**Interfaces:**
- Produces: `List<int> substituteCandidates(int slot)`. Returns the slot indexes holding a pick whose SLOT has the same position and sits on the other side of the bench line, in slot order; empty for an empty slot or a keeper. Empty slots are never candidates.
- Produces: `String? substitute(int slotA, int slotB)`.
  - It swaps the two picks between the slots. Each pick keeps its id, position and price and takes its new slot's `bench` flag.
  - The armband passes as in Global Constraints: the id that held it is replaced by the incoming player's id, directly. Do not go through `_clearArmbandFor`, which would report a lost armband.
  - It marks the draft dirty, returns the SnackBar sentence when an armband passed, else null, and notifies listeners.
  - It throws `ArgumentError` if the slots are not a valid pair (same position, one starter + one bench, both filled).

- [ ] **Step 1: failing tests.**
  - Candidates: a starting DEF's candidates are the bench DEF slots; a bench ATT's are the starting ATT slots; the GK slot has none; an empty slot has none.
  - Substitute swaps the picks. Both picks keep their ids and prices, `bench` follows the slot, `spentTenths`, `remainingTenths` and `transferPreview` are unchanged, and `squad` validates.
  - The captain on a starting DEF substituted for a bench DEF: the incoming player is captain and the result is `<Name> is now your captain.`. The same for the vice, with `<Name> is now your vice-captain.`
  - An invalid pair (two starters, two positions, an empty slot) throws.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test test/fantasy/`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(fantasy): the squad draft can substitute a starter and a bench player`

### Task 2: The Substitute action, the sheet and the Rules line

**Files:**
- Modify: `lib/fantasy/hub/squad_picker_sheet.dart` (`SquadChipAction`, `showSquadChipActions` ~:271; add the substitute sheet here)
- Modify: `lib/fantasy/hub/squad_builder.dart` (`_chipActions` ~:332, `_announceArmbandLoss`)
- Modify: `lib/fantasy/hub/rules_tab.dart` (~:298 "Auto-subs, captain & bench")
- Test: the existing squad builder / picker sheet widget tests (grep `action_swap` under `test/fantasy/`)

**Interfaces:**
- Consumes: Task 1 `substituteCandidates`, `substitute`.
- Produces: `SquadChipAction.substitute`; `showSquadChipActions(..., String? substituteLabel)` (null hides the tile; the builder passes `Substitute with <Name>` for one candidate, `Substitute` for several); `Future<int?> showSubstituteSheet(BuildContext, {required String playerName, required List<({int slot, String name, FantasyPosition position})> candidates})`, which returns the chosen slot.

- [ ] **Step 1: failing tests.**
  - A starting DEF's action sheet has `Substitute with <bench DEF>` (key `action_substitute`), and tapping it swaps them on the court with no second sheet. The GK's sheet has no Substitute tile.
  - The bench DEF's sheet has `Substitute`; it opens the sheet listing both starting DEFs, and picking one swaps them.
  - Substituting the captain shows `<Name> is now your captain.`
  - After Save, the stored squad has the swapped bench flags and the transfer line still reads 0 transfers (Review Focus 2).
  - A locked court offers no Substitute.
  - The Rules tab shows the new sentence.
  - The old `Swap` tile reads `Replace` and still opens the market picker (owner decision 4). Update the tests that pinned `Swap`, and keep the strip's `Swap`.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(fantasy): Substitute swaps a starter and a bench player for free`

## Part B — Auto-subs on the pitch

### Task 3: Scoring records which starter each auto-sub replaced

**Files:**
- Modify: `functions/src/lib/fantasy/squad_week.ts` (`SlotResult`, `scoreSquadWeek`)
- Modify: `functions/src/lib/fantasy/finalize_core.ts` (~:628 Breakdown row)
- Modify: `functions/src/lib/fantasy/live_core.ts` (~:460 live slot row)
- Modify: `lib/fantasy/engine/squad_week.dart` (the Dart twin's `SlotResult`)
- Test: `functions/src/lib/fantasy/squad_week.test.ts`, `finalize_core.test.ts`, `live_core.test.ts`, the golden replay tests and `test/fantasy/fixtures/golden_*.json`, the Dart engine tests

**Interfaces:**
- Produces:
  - `SlotResult.replacesId?: string` (TS) / `final String? replacesId` (Dart): set only on a promoted bench slot, as the starter it covered.
  - Breakdown rows add `replaces` only when set (`BreakdownRow` in `live_core.ts` gains the optional field).
  - Live slot rows add `r` only when set.
  - Nothing else reads these rows strictly: the fan parser `_slotFromRow` is tolerant, and the Manager only mentions `Breakdown` in a comment.

- [ ] **Step 1: failing tests.**
  - One absent starting DEF and one bench DEF who played: the bench slot's `replacesId` is that starter.
  - Two absent starting DEFs and one bench DEF: `replacesId` is the first absent starter in pick order (Review Focus 3).
  - A pending starter (the live pending rule) is not replaced.
  - Breakdown and live rows carry `replaces` / `r` only on that slot.
  - The Dart twin gives the same results for the same input, and the golden fixtures are updated and replay in both engines.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `npm test` in `functions/`, `npm run build`; `flutter test test/fantasy/`.
- [ ] **Step 5: commit** `feat(fantasy): scoring records which starter each auto-sub replaced`

### Task 4: The locked court shows the auto-sub

**Files:**
- Modify: `lib/fantasy/data/fantasy_parsers.dart` (`LiveSlot` ~:744, `_slotFromRow` ~:876: parse `replaces` / `r` into `replacesId`)
- Create: a small pure helper next to `live_logic.dart` (e.g. `lib/fantasy/hub/auto_sub_view.dart`)
- Modify: `lib/fantasy/hub/live_logic.dart` (`LockedWeekModel` ~:300 gains `rows`, the `LiveSlot` list its chip texts were built from; empty when no lines are shown)
- Modify: `lib/fantasy/hub/court_view.dart` and `lib/fantasy/hub/player_chip.dart` (optional `subbedIn` / `subbedOut` id sets, drawn as corner badges)
- Modify: `lib/fantasy/hub/squad_builder.dart` (~:578, the locked court: `picksToSlots(lockedSquad, _draft.slots)`) and `lib/fantasy/hub/manager_squad_viewer.dart` (~:756, `picksToSlots(squad, slots)`). Both pass the result through `autoSubDisplay` with their model's rows.
- Test: new `test/fantasy/auto_sub_view_test.dart`, plus the locked-court / squad-viewer widget tests

**Interfaces:**
- Produces: `({List<SquadPick?> slotPicks, Set<String> subbedIn, Set<String> subbedOut}) autoSubDisplay(List<SquadSlot> slots, List<SquadPick?> slotPicks, List<LiveSlot> rows)`.
  - For every row with `replacesId` whose starter and bench player both sit in the given slots, it swaps their two slot positions for display.
  - It puts the bench player in `subbedIn` and the starter in `subbedOut`.
  - A row with `autoSubbedIn` but no `replacesId` moves nothing and goes in `subbedIn` only.
- The replaced starter's chip text is `Out` in these views, whatever the status source says.

- [ ] **Step 1: failing tests.**
  - Pure: one pair swaps and returns both sets. Two absent starters with one sub swap only the recorded pair (Review Focus 3). A row without `replacesId` moves nothing (Review Focus 4). Rows naming a player not in the squad are ignored.
  - Widget, locked My Team (live week): the sub is drawn on the pitch in the starter's place with his points and the "came on" badge, and the starter is on the bench with `Out` and the "went off" badge. Before the rows carry the sub, nothing moves (Review Focus 5). A settled week does the same from History. The leaderboard squad viewer does the same. The editable builder never moves anything. Light and dark mode; 360 px without overflow.
- [ ] **Step 2:** run, expect FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** `flutter test`, `flutter analyze`.
- [ ] **Step 5: commit** `feat(fantasy): the pitch shows who came on for an absent starter`

---

## Rollout (each step needs the owner's go)

1. Fan build on the emulator for the owner to try Substitute on his own squad, and Save before the deadline.
2. Functions deploy of the scoring functions: the groups `fantasyFutsal`, `fantasyBasketball` and `fantasyFlagFootball` (each holds that sport's finalize and live triggers, `functions/src/index.ts:375-389`), `fantasyLifecycleSweep` (`fantasy_lifecycle.ts:38`) and `onFantasyVoidWritten` (`functions/src/index.ts:401`; voiding or un-voiding a week re-settles it through the same scoring code). It is additive: store apps ignore `replaces` / `r`. From then on, live and newly finalized weeks carry them.
3. Fan app: merge `zaya-fantasy-subs` into `zaya-review-fixes` for PR #18, with the share-image fix. iPhone simulator checks: Substitute on a starter and on a bench player; the captain SnackBar; an auto-sub drawn on the pitch.

## Not in this plan

- Recomputing GW1 so its rows gain `replaces` (it already scored correctly; only the picture is plain).
- Moving the captain/vice badge onto the vice when the captain did not play (scoring already does it; the points show it).
- Cross-position substitutions or a bench keeper (the formation is fixed).
- Push notifications about auto-subs.

## Fable review (2026-11-17)

Checked against the fan repo at `zaya-fantasy-subs` (`3bd0b29` plus the share-image work in progress), the server functions and the Manager. Verdict: **approved with the amendments below, all written into the plan above.** The owner has since confirmed decision 4 (rename `Swap` to `Replace`).

1. **One tap, not two.** The formation has one bench defender and one bench attacker, so every starter has exactly one possible substitute. The draft would have opened a second sheet listing that one name. The action now reads `Substitute with <Name>` and swaps at once; the sheet opens only when there is a real choice (a bench player has two starters of his position).
2. **The armband passes without a false alarm.** The draft said only "the armband passes". The existing helper for a removed player reports a LOST armband, which would have told the manager to pick a new captain right after the app picked one. The swap now moves the armband directly and says `<Name> is now your captain.`
3. **"Free" is confirmed in the code, not assumed.** The app's transfer preview and the server's recount both count by player id only; the squad rules check each pick's shape, not who is benched; the server's integrity judge counts starters, which a swap never changes. No server, rules or money change is needed for Part A.
4. **Badges have their own corner.** The captain / vice badge sits on the photo's top-right, so the "came on" / "went off" badges go top-left and get screen-reader labels.
5. **The models carry the rows.** `LockedWeekModel` holds only finished chip texts today. It now also carries the scored rows, so My Team and the leaderboard squad viewer use the same `autoSubDisplay` and cannot drift apart.
6. **Deploy targets are named.** The rollout lists the exact function groups instead of leaving it to the PR.
7. **Checked and left as written:**
   - Auto-subs really are already scored (first bench player of the same position who played, full points; the vice inherits the armband), so the owner's request is a display change plus one recorded field.
   - "Back to the bench after the week" needs no code, because the saved squad never changes.
   - A week scored before this change (GW1) shows the badge without moving anyone, which is plain but never wrong.
   - A Bench Boost week still records the substitution, so the picture stays consistent.
   - Nothing else reads the score rows strictly.
