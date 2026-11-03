# Fantasy Transfers In The App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** written by Opus 2026-11-03 for a **Fable review before execution** (owner rule). Fable: please check the decisions in "Decisions for review" first.

**Goal:** Week 2 starts with 2 free transfers (not 4), and the fan app finally shows transfers: how many are free, how many a draft uses, the points cost before saving, and playable Wildcard / Free Hit chips.

**Architecture:** The server already counts transfers (`TransferState/<uid>`, `functions/src/lib/fantasy/transfer_state.ts`) and charges them at the lock. This plan (1) stops a first squad from banking its unused allowance, (2) has the rollover also publish the exact squad next week's transfers count against (`CountFrom` + `CountFromGw` on `TransferState/<uid>`), so the app can preview the count with the server's own baseline instead of re-deriving it, and (3) builds the missing app pieces on top: a transfers line in the builder, a confirm before a save that costs points, and the two chips that still say "Coming with transfers".

**Tech Stack:** TypeScript Cloud Functions (vitest), Flutter/Dart (flutter_test), Firebase RTDB rules (`database.rules.stage1.json` live, `database.rules.json` stage 2).

**Spec:** `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §5 (transfers) and §6 (chips), plus the owner's decision on 2026-11-03: "week 2 should be 2 transfers not 4".

## Owner decisions this plan carries (verbatim intent)

- Week 2 should be 2 transfers, not 4. Building your first team is free and does not bank.

## What was found (why this plan exists)

1. `settleTransfersAfterFinalize` (`functions/src/lib/fantasy/orchestration.ts:600`) rolls every manager's allowance with `rolloverFreeTransfers` (`functions/src/lib/fantasy/transfers.ts`). A first squad counts 0 transfers (`recordSquadSave`, no previous squad → `used = 0`), so after the first week `Free = 2 − 0 + 2 = 4`.
2. The fan app never reads `TransferState`: no free-transfer count, no "this costs −4" warning anywhere (`grep -ri transfer lib/fantasy/hub` finds only the chip captions). Fans take hits blind.
3. `lib/fantasy/hub/chip_row.dart:111-130`: Wildcard and Free Hit are `onTap: null` with the caption "Coming with transfers", a P3b placeholder that was never wired. The server already honours both (`isUnlimitedChip`, the Free Hit restore).

## Decisions for review (Opus rulings, Fable please check)

- **D1. First week = the manager's first counted week,** i.e. no effective squad after the previous week (`effectiveSquadAfterWeek(gw − 1)` is null). That covers GW1, a mid-season joiner's first week, and a manager who deleted and rebuilt their team. In each case the next week gets exactly `freeTransfersPerWeek` (2).
- **D2. The app previews the count against a server-published baseline (`CountFrom`)**, not the selling baseline (`Baselines/<uid>.Prices`). The two differ after an Invalid week (selling prices `{}`, transfer counter still the locked squad), and the counter's baseline is `effectiveSquadAfterWeek`, which only the server resolves (Free Hit recursion).
- **D3. A save that ADDS a points cost asks first.** No dialog when the cost stays the same or drops.
- **D4. Wildcard and Free Hit toggle like the other two chips** (one per week; switch off any time before the deadline). The Premier League game makes a confirmed Wildcard permanent; ours keeps the existing "chips are a draft until the deadline" behaviour. Arming either one asks for confirmation.
- **D5. Wildcard / Free Hit are disabled while the team is still a first team** (nothing to transfer). Caption: "Your first team is free".
- **D6. The rules tighten `chip` to the four names** (today any string passes, `database.rules.stage1.json:389`).

## Global Constraints

- Money and points stay integer; points cost = `extraTransferCost` (4) × extra transfers, from `FantasyConfig`, never hard-coded.
- Every new app read is a live stream (`onValue`), never RTDB `.get()`, with iOS parity. The new stream's cache is cleared on sign-out (`lib/fantasy/data/fantasy_session.dart`).
- Light and dark mode. The points cost uses the bright down red (`fantasyDownRed`: #FF5252 dark / #D32F2F light). No hard-coded light fills.
- TS and Dart engine twins change together (`transfers.ts` ↔ `lib/fantasy/engine/transfers.dart`).
- Both rules files change together and `functions/src/rules_contract.test.ts` pins every new rule.
- Deploy order: rules → functions → app. Never `--apply` the fill tool. Never push.
- Deploy before the first rollover of Season 16 (end of S16 GW1).

## Review Focus

1. **A save made while `TransferState` is stale** (rollover not run yet, deleted-and-rebuilt squad). The app must show "Transfer count updating…" and never a guessed count. Pinned in Task 3.
2. **Free Hit last week.** `CountFrom` must be the pre-Free-Hit squad (the restored one), or the preview disagrees with the server by up to 7 transfers. Pinned in Task 1.
3. **A position-change free swap** (`FreeSwaps`). Selling that player must preview as free, exactly like `usedAfterFreeSwaps`. Pinned in Task 3.
4. **A save that writes `TransferState`** (`recordSquadSave`, `freezeLockTransferState`, rollover) must carry `CountFrom`/`CountFromGw` through and never drop them. Pinned in Task 1.
5. **Wildcard armed, then transfers, then disarmed.** The cost line and the confirm come back immediately. Pinned in Task 4.

---

### Task 1: Server — first squad never banks; rollover publishes `CountFrom`

**Files:**
- Modify: `functions/src/lib/fantasy/transfers.ts` (`rolloverFreeTransfers`)
- Modify: `functions/src/lib/fantasy/transfer_state.ts` (`TransferState`, `parseTransferState`, `transferStateToNode`, `rolloverState`, header doc block)
- Modify: `functions/src/lib/fantasy/orchestration.ts` (`settleTransfersAfterFinalize`, ~line 600)
- Modify: `lib/fantasy/engine/transfers.dart` (Dart twin)
- Modify: `functions/tools/rehearse_s15.ts` (expected ledger, ~line 1420)
- Test: `functions/src/lib/fantasy/transfers.test.ts`, `functions/src/lib/fantasy/transfer_state.test.ts`, `functions/src/lib/fantasy/transfers_orchestration.test.ts`, `test/fantasy/transfers_test.dart`

**Interfaces:**
- Produces: `rolloverFreeTransfers({free, used, cfg, unlimited?, firstWeek?}): number`, where `firstWeek: true` → `cfg.freeTransfersPerWeek`. Dart twin: `rolloverFreeTransfers({..., bool firstWeek = false})`.
- Produces: `TransferState.countFrom?: { gw: number; ids: string[] | null }`. Node fields `CountFromGw:int` plus `CountFrom:[playerId]`. `CountFromGw` present with `CountFrom` absent means "no squad to count from: a first team".
- Produces: `rolloverState(state, cfg, gw, basis: { firstWeek: boolean; countFromIds: string[] | null })` sets `countFrom = { gw: gw + 1, ids: countFromIds }`.

- [ ] **Step 1: Failing tests**
  - `transfers.test.ts`: `firstWeek` with free 2, used 0 → 2; `firstWeek` + unlimited → 2; not `firstWeek` with free 2, used 0 → 4 (unchanged); not `firstWeek` with free 6, used 0 → 7 (cap unchanged).
  - `transfer_state.test.ts`: `CountFrom`/`CountFromGw` round-trip; half-written (one without the other) reads as none; `CountFromGw` alone reads as `{gw, ids: null}`; `rolloverState` writes `countFrom.gw = gw + 1`.
  - `transfers_orchestration.test.ts` (FakeDb, cold-first transactions as today):
    - (a) GW1 squad, GW1 finalized → `TransferState.Free === 2`, `CountFromGw === 2`, `CountFrom` = the GW1 locked ids.
    - (b) A manager whose first squad is GW3 → after GW3, `Free === 2`.
    - (c) GW1 squad, no save in GW2 → after GW2, `Free === 4` (a real bank still banks).
    - (d) Free Hit in GW2 → after GW2, `CountFrom` = the GW1 ids, matching what the restore wrote.
    - (e) A save (`recordSquadSave`) and the lock freeze both preserve `CountFrom`/`CountFromGw`.
  - `test/fantasy/transfers_test.dart`: the same 4 cases as the TS `transfers.test.ts` (twin parity).
- [ ] **Step 2: Run them; expect FAIL** — `cd functions && npx vitest run src/lib/fantasy/transfers.test.ts src/lib/fantasy/transfer_state.test.ts src/lib/fantasy/transfers_orchestration.test.ts` and `flutter test test/fantasy/transfers_test.dart`.
- [ ] **Step 3: Implement.** In `settleTransfersAfterFinalize`, per uid:
  - `prev = await effectiveSquadAfterWeek(db, root, uid, gw - 1)`, then `firstWeek = !isPlainMap(prev)`.
  - `after = await effectiveSquadAfterWeek(db, root, uid, gw)`, then `countFromIds` = its pick ids, or null.
  - Pass both to `rolloverState`.
  - Keep the `RolledGw` guard first, so a rerun never re-rolls.
  - Update the header doc block of `transfer_state.ts` with the new fields.
- [ ] **Step 4: Update `rehearse_s15.ts`.** The expected ledger's `e.free` after a manager's first locked week resets to `cfg.freeTransfersPerWeek`. Run `npm run rehearse:s15 -- --offline`; expect `invariants: ALL PASS`, 0 ledger mismatches.
- [ ] **Step 5: Run all functions tests** — `npx vitest run` (all green), `npx tsc --noEmit -p .`, `npx tsc --noEmit -p tools`. Run `flutter test test/fantasy/transfers_test.dart`.
- [ ] **Step 6: Commit** — `fix(fantasy): a first team never banks its allowance; rollover publishes the transfer baseline`.

### Task 2: Rules — chip names, `TransferState` stays server-written

**Files:**
- Modify: `database.rules.stage1.json` and `database.rules.json` (`Squads/$uid/chip`)
- Test: `functions/src/rules_contract.test.ts`

- [ ] **Step 1: Failing contract test.** `Squads/$uid/chip` `.validate` is exactly `newData.isString() && newData.val().matches(/^(tripleCaptain|benchBoost|wildcard|freeHit)$/)` in both files. `TransferState` still has no `.write` for clients.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Edit both rules files.**
- [ ] **Step 4: LOCAL emulator probe** (never live): a save with `chip: 'wildcard'` passes; `chip: 'superSub'` is refused. Reuse the scratchpad emulator pattern: `firebase emulators:exec --only database --project demo-transfers`, with `JAVA_HOME` set to the Android Studio jbr.
- [ ] **Step 5: Commit** — `fix(rules): squad chip must be one of the four chips`.

### Task 3: App data — `TransferState` stream and the transfer preview

**Files:**
- Modify: `lib/fantasy/data/fantasy_parsers.dart` (new `TransferStateView`, `parseTransferState`)
- Modify: `lib/fantasy/data/fantasy_service.dart` (new `watchMyTransferState(sport, season)` + `watchMyTransferStateAuto`, mirroring `watchMySquadAlert`/`watchMySquadAlertAuto` at lines 408/422)
- Modify: `lib/fantasy/data/fantasy_session.dart` (register the new stream's cache, if it caches, for sign-out clearing)
- Create: `lib/fantasy/hub/transfer_preview.dart` (pure logic + copy)
- Modify: `lib/fantasy/hub/squad_draft.dart` (`setTransferContext`, `transferPreview` getter)
- Test: `test/fantasy/transfer_preview_test.dart` (new), `test/fantasy/fantasy_parsers_test.dart`, `test/fantasy/squad_draft_test.dart`, plus a cross-check in `functions/tools/client_draft_money.test.ts` style (below)

**Interfaces:**
- Consumes: Task 1 node shape (`Free`, `UsedThisGw`, `FreeSwaps`, `FreeSwapsGw`, `CountFrom`, `CountFromGw`).
- Produces: `class TransferStateView { final int? free; final int usedThisGw; final int? countFromGw; final List<String>? countFrom; final int? freeSwapsGw; final List<String> freeSwaps; }`. `free == null` means the node is absent.
- Produces: `class TransferPreview { final TransferPreviewKind kind; final int used; final int free; final int costPoints; }` with `enum TransferPreviewKind { firstTeam, unlimited, counted, notReady }`.
- Produces: `TransferPreview transferPreview({required List<String> draftIds, required TransferStateView? state, required int? editingGw, required String? chip, required FantasyConfig cfg})`. Rules:
  - Absent node → `firstTeam`.
  - `countFromGw == editingGw` and `countFrom == null` → `firstTeam`.
  - `countFromGw != editingGw` → `notReady`.
  - Chip `wildcard`/`freeHit` → `unlimited`, cost 0.
  - Otherwise `used` = draft ids not in `countFrom`, minus free-swap players sold (only when `freeSwapsGw == editingGw`, same as `usedAfterFreeSwaps`). `free = state.free ?? cfg.freeTransfersPerWeek`, cost = `max(0, used − free) × cfg.extraTransferCost`.
- Produces: `String transferLineText(TransferPreview p)` with this exact copy:
  - firstTeam: `Your first team is free — change anything until the deadline.`
  - unlimited, Wildcard: `Wildcard on — every transfer is free this week.`
  - unlimited, Free Hit: `Free Hit on — every transfer is free, and your team comes back after this week.`
  - counted, cost 0: `{used} of {free} free transfers used` (singular `transfer` when free == 1)
  - counted, cost > 0: `{used} transfers · {free} free · −{cost} pts this week`
  - notReady: `Transfer count updating…`
- Produces: `SquadDraftController.setTransferContext({TransferStateView? state, int? editingGw})` (notify only on change) and `TransferPreview get transferPreview` (uses the draft's current picks and chip).

- [ ] **Step 1: Failing tests** in `transfer_preview_test.dart`, one per rule: absent node; first-team marker; stale `countFromGw`; wildcard; Free Hit; 1 of 2 used; 3 used with 2 free → cost 4; 4 used with 2 free → cost 8; free swap sold → not counted; free swap from another week → counted. Each copy string asserted verbatim. Add a parser round-trip test.
- [ ] **Step 2: Cross-check against the server.** In a new `functions/tools/transfer_preview_parity.test.ts`, port `transferPreview`'s counting rule as a 15-line TS mirror and assert it equals `usedAfterFreeSwaps` + `transferCost` over 8 fixtures, including a free swap, a wildcard and a Free Hit. Same pattern as `client_draft_money.test.ts`.
- [ ] **Step 3: Run; expect FAIL.**
- [ ] **Step 4: Implement.** The stream reads `Fantasy/<sport>/<season>/TransferState/<uid>` with `onValue`. Its error yields a "not ready" state, never a fake absent node: a failed read is not a first team.
- [ ] **Step 5: Run** `flutter test test/fantasy/` and `cd functions && npx vitest run tools/transfer_preview_parity.test.ts`; all green.
- [ ] **Step 6: Commit** — `feat(fantasy): the app reads the transfer state and previews the count`.

### Task 4: App UI — transfers line, confirm before a hit, Wildcard and Free Hit

**Files:**
- Modify: `lib/fantasy/hub/squad_builder.dart` (feed `setTransferContext` next to `setSaleContext`; transfers line under `_BudgetBar` while editable; confirm in `_save()` at line 350)
- Modify: `lib/fantasy/hub/chip_row.dart` (Wildcard and Free Hit become tappable; header comment updated)
- Modify: `lib/fantasy/engine/squad.dart:41` (comment lists all four chips)
- Modify: `lib/fantasy/hub/rules_tab.dart` (Transfers and Chips copy)
- Modify: `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §5 (one line: a first team never banks)
- Test: `test/fantasy/squad_builder_test.dart`, `test/fantasy/rules_tab_test.dart`, a new chip-row widget test in `test/fantasy/squad_builder_test.dart` or a new `test/fantasy/chip_row_test.dart`

**Interfaces:**
- Consumes: Task 3's `transferPreview` and `transferLineText`.

- [ ] **Step 1: Failing widget tests.**
  - The transfers line shows each `transferLineText` case. The cost text uses `fantasyDownRed` in both light and dark themes.
  - `_save()` with a draft whose cost rose from 0 to 4 shows a dialog titled `Take a points hit?` with body `This team uses 3 transfers and you have 2 free, so it costs 4 points this week.` and buttons `Cancel` / `Save (−4 pts)`. Cancel saves nothing.
  - A save whose cost does not rise shows no dialog.
  - Wildcard tap → dialog `Play your Wildcard?` with body `Every transfer this week is free and your new team stays. You can switch it off until the deadline. You get one Wildcard for Gameweeks 1–{chipSet1EndGw} and one for the rest of the season.` and buttons `Not now` / `Play Wildcard`. Confirm arms it. Tapping the armed chip disarms it with no dialog.
  - Free Hit tap → `Play your Free Hit?` with body `Every transfer this week is free. After this week's games, the team you have now comes back. You can switch it off until the deadline.` and buttons `Not now` / `Play Free Hit`.
  - Wildcard/Free Hit while `firstTeam` → untappable, caption `Your first team is free`.
  - "Used" availability still blocks arming, as for the other chips.
  - Arm Wildcard, make 4 transfers, disarm → the line shows `4 transfers · 2 free · −8 pts this week` at once.
  - Rules tab Transfers text starts `Your first team is free: change it as much as you like until your first deadline. After that you get {freeTransfersPerWeek} free transfers each gameweek;` and the rest of today's sentence follows.
  - At 360 px wide and in dark mode, nothing overflows (the hub's existing 360 px test pattern).
- [ ] **Step 2: Run; expect FAIL** — `flutter test test/fantasy/squad_builder_test.dart test/fantasy/rules_tab_test.dart`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full fan suite** — `flutter test` (all green) and `flutter analyze lib/fantasy` (no new issues).
- [ ] **Step 5: Commit** — `feat(fantasy): fans see free transfers, confirm a points hit, and can play Wildcard and Free Hit`.

### Task 5: Ship

- [ ] **Step 1:** Deploy rules (`database.rules.stage1.json`) and verify live == file with `scratchpad/compare_live_rules.js` (expect `MATCH`).
- [ ] **Step 2:** Deploy every fantasy function (rollover code is bundled in the finalize functions; deploy them together as always).
- [ ] **Step 3:** Build and install the fan APK on emulator-5554.
- [ ] **Step 4:** Report to the owner in plain language what fans now see, with one test path on the emulator.
- [ ] **Step 5:** Put an iOS check list in the PR notes: the confirm dialogs, the chip row scroll and the transfers line at the smallest iPhone width.
