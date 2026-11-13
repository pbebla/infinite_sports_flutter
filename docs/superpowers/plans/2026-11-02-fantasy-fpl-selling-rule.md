# Fantasy FPL Selling Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selling a player follows the Premier League Fantasy rule: you keep half of any price rise (rounded down to $0.1M) and take the full drop, so your spending room grows or shrinks with what you sell.

**Architecture:** Each pick keeps the price PAID (unchanged). New: every locked squad carries a server-computed `realizedTenths` (the running total of profit/loss from sales), and the budget rule becomes `sum of prices paid ≤ budget + realizedTenths`. The server judge decides, at the lock, which baseline players were sold, at the current price. A new server-written node `Baselines/<uid>` gives the fan app last week's locked prices and the running total, so the squad builder shows the same money the server will charge. A sweep-time preview warns a fan (alert + one push) when a price move during the open window puts the saved team over budget. The same round closes the "uncounted saves" gap: the `Squads` rule only accepts saves while the week is open, and the lock recounts transfers. The Manager app is unaffected: it never computes budgets.

**Tech stack:** Cloud Functions TS (vitest; `FakeDb` runs transactions cold, like RTDB), Flutter fan app (plain `onValue` streams, session caches), RTDB rules (both files).

**Spec:** `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §4. Its bullet "Buying and selling always at current price (no FPL profit-split accounting)" is REPLACED by this plan (Task 1 edits the spec). Owner decision 2026-11-02, verbatim: "yes go with premier league rule, write the plan". Review: `docs/superpowers/plans/2026-11-03-fable-review-selling-rule-and-cash.md` §A, folded in below (must-fixes A.1–A.4, the addendum and the recount, owner-approved 2026-11-03: "do both").

**Repo / branch:** fan repo `infinite_sports_flutter`, branch `zaya-fantasy`. Commit locally, never push. Ship before Futsal Season 16 gameweek 1 (changing it mid-season would be unfair). Season 15 is test data only.

## Global Constraints

- Money is integer **tenths** of $1M everywhere (`budgetTenths` 500 = $50.0M; price step 5 = $0.5M).
- **Sell price:** `purchase + floor((current − purchase) / 2)` when `current > purchase`, else `current`. Integer division floors to $0.1M. Examples (tenths): 80→90 sells 85; 80→85 sells 82; 80→70 sells 70; 80→80 sells 80. "Current" is the player's price in `Players/<name>/priceTenths` at the moment of judging. NO "max of this week and last week" credit (review A.2).
- **Spending room:** `budgetTenths + realizedTenths − Σ pick prices ≥ 0`. `realizedTenths` may be negative.
- **Held = a baseline player id present in the squad, priced at his BASELINE price whatever price the client sent** (review A.3). There is no "re-bought at a different price" case. Re-adding a sold baseline player before the deadline restores him at his baseline price (no sale, no transfer: the transfer counter compares by id).
- Baseline = the manager's effective squad after the previous gameweek (`effectiveSquadAfterWeek(gw−1)`, Free Hit aware). The server judge, the transfer counter and `Baselines/<uid>` all use this one baseline (the S15 "Bug 1" lesson).
- Known limitation (accepted): a squad judged Invalid is no baseline next week, so every pick is re-bought at the market floor; its `realizedTenths` still carries.
- Fan app: `onValue` streams only, never RTDB `.get()`; every new static cache cleared in `clearSessionCaches()` (the guard test enforces it); error ≠ fact (a failed or stale baseline never shows a made-up budget).
- Every new UI element fits light AND dark mode; negative money and over-budget warnings use `fantasyDownRed` (#FF5252 dark / #D32F2F light); layouts hold at 360 px wide.
- Rules: edit `database.rules.json` AND `database.rules.stage1.json`; pin in `functions/src/rules_contract.test.ts`; probe only in the LOCAL emulator (`JAVA_HOME` = `C:\Program Files\Android\Android Studio\jbr`; `firebase emulators:exec --only database --project demo-selling --config firebase.json`).
- Every RTDB transaction never aborts on a null first run (the 2026-11-02 refund bug class).

## Review Focus

1. **Sell and re-buy the same player in one window** costs nothing: baseline price, no sale counted, no transfer. (Task 2 server test, Task 6 draft test.)
2. **A manager with no squad at a lock** must still get a fresh `Baselines/<uid>`, or the app blocks their Save forever. (Task 3 test.)
3. **A price move while the window is open** (the Monday 10:00 reprice, an owner price edit) that pushes a saved team over budget: the fan gets an alert and one push before the deadline. (Task 4.)
4. **Free Hit week.** Its sales are temporary: the baseline after a Free Hit is the squad before it, with that squad's `realizedTenths`. (Task 3 test.)
5. **An old week re-finalized** (a score edit on gameweek 3 during gameweek 9) never moves `Baselines/<uid>` backwards. (Task 3 test.)

Bonus fix: today a squad that under-claims a pick's price can pass the lock check (the check reprices it) while the snapshot stores the under-claimed price, which becomes next week's baseline. Task 2 stores the judge's prices in valid snapshots, which closes it. Honest squads are unchanged.

---

### Task 1: The selling math, twice (server + app), and the budget rule

**Files:**
- Create: `functions/src/lib/fantasy/selling.ts`, test `functions/src/lib/fantasy/selling.test.ts`
- Create: `lib/fantasy/engine/selling.dart`, test `test/fantasy/selling_test.dart`
- Modify: `functions/src/lib/fantasy/squad.ts` (`validateSquad`), `lib/fantasy/engine/squad.dart` (`validateSquad`), and both `priceTenths` field comments ("price PAID; sells by the FPL rule, selling.ts")
- Modify: `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §4 (replace the "current price" bullet with the Global Constraints sell rule, the held rule and the examples)
- Test: `functions/src/lib/fantasy/squad.test.ts`, `test/fantasy/squad_test.dart`

**Interfaces (Produces):**
- TS `sellPriceTenths(purchaseTenths: number, currentTenths: number): number`
- TS `realizedOf(node: unknown): number`: the node's `realizedTenths` when it is a finite number (truncated), else 0
- TS `validateSquad(s, cfg, realizedTenths = 0)`: `overBudget` when `spentTenths(s) > cfg.budgetTenths + realizedTenths`
- Dart `int sellPriceTenths({required int purchaseTenths, required int currentTenths})`
- Dart `class SaleBaseline { final int forGw; final Map<String, int> prices; final int realizedTenths; }` + `SaleBaseline? saleBaselineFromNode(Object? node)` (null when not a map or `ForGw` missing; `Prices` non-int values dropped; absent `RealizedTenths` → 0)
- Dart `int realizedNowTenths(SaleBaseline? b, Iterable<String> squadIds, Map<String, int> currentPrices)` = `b.realizedTenths + Σ over baseline ids NOT in squadIds of sellPriceTenths(b.prices[id], currentPrices[id] ?? b.prices[id]) − b.prices[id]`; `b == null` → 0
- Dart `int buyPriceTenths(SaleBaseline? b, String playerId, int currentTenths)` = `b?.prices[playerId] ?? currentTenths`
- Dart `validateSquad(s, cfg, {int realizedTenths = 0})`, same rule as TS

- [ ] **Step 1: failing tests.** ONE shared table in both `selling.test.ts` and `selling_test.dart`, `(purchase, current) → sell`: `(80,90)→85, (80,85)→82, (80,81)→80, (80,80)→80, (80,70)→70, (40,150)→95, (150,40)→40`. `realizedNowTenths`: baseline `{A:80, B:60}`, realized 5, current `{A:90, B:50}`: squad `{A}` → `5 + (50−60) = −5`; squad `{B}` → A sold at 85 → `10`; squad `{A, B}` → `5`; `b == null` → 0. `buyPriceTenths`: baseline id → baseline price (even when current differs); other id → current. `validateSquad`: spent 505 with realized 5 → no overBudget; spent 506 → overBudget; spent 500 with realized −1 → overBudget.
- [ ] **Step 2:** run `cd functions; npx vitest run src/lib/fantasy/selling.test.ts src/lib/fantasy/squad.test.ts` and `flutter test test/fantasy/selling_test.dart test/fantasy/squad_test.dart`. Expected: FAIL (missing symbols).
- [ ] **Step 3:** implement the Interfaces above. Edit spec §4.
- [ ] **Step 4:** the same commands. Expected: PASS. Also `npx tsc --noEmit -p .`.
- [ ] **Step 5:** commit `feat(fantasy): FPL selling math + budget includes realized sales (both twins, spec §4)`.

### Task 2: The server judge prices sales and records `realizedTenths`

**Files:**
- Modify: `functions/src/lib/fantasy/squad_integrity.ts`, `functions/src/lib/fantasy/transfer_state.ts` (`annotateSquadIntegrity`), `functions/src/lib/fantasy/finalize_core.ts` (History rows), callers of `judgeSquad` / `integrityVerdictOf` in `orchestration.ts` (they read `.issues` now)
- Test: `functions/src/lib/fantasy/squad_integrity.test.ts`, `transfer_state.test.ts`, `finalize_core.test.ts`, `squad_hardening.test.ts`

**Interfaces:**
- Consumes: `sellPriceTenths`, `realizedOf`, `validateSquad(…, realizedTenths)` (Task 1)
- Produces: `interface LockVerdict { issues: SquadIntegrityIssue[]; prices: number[]; realizedTenths: number }`. `judgeSquad(...)` returns `LockVerdict`; `integrityVerdictOf(...)` returns `LockVerdict | null` (null = malformed). `trustedPrices` is replaced by `judgeSale(squad: FantasySquad, market, baseline: FantasySquad | null, baselineRealized: number, previousWeekPrices): { prices: number[]; realizedTenths: number }`

`judgeSale`, per pick, against the baseline's picks (`baselineSquadOf`: null when absent or Invalid, so every pick is NEW):
- **held** (the baseline has this player id): price = the baseline price. The client's price for a held player is ignored.
- **new** (any other id): price = `max(0, client price, market floor)`; the market floor is unchanged: `min(current, PriceHistory/gw−1)`.
- **sold** (each baseline id absent from the squad): `realized += sellPriceTenths(baselinePrice, current) − baselinePrice`, `current` = the market price now. A player missing from the market adds 0.
- `realizedTenths = realizedOf(baselineRaw) + Σ sold`. `realizedOf` reads the RAW baseline node even when it is Invalid (the server wrote that number; only an Invalid node's picks are untrusted).
- `overBudget` comes from `validateSquad(repriced, cfg, realizedTenths)`.

Snapshot nodes (`annotateSquadIntegrity`):
- **Valid:** picks re-written with the verdict's prices, all other keys kept, `realizedTenths` set.
- **Invalid:** verbatim, plus `Invalid`, plus `realizedTenths` = `realizedOf(baselineRaw)` (no sale credited).
- **Malformed:** untouched, as today.

History rows: `finalize_core` copies the source node's `realizedTenths` onto `History/<gw>/<uid>` in BOTH branches (invalid and scored) when it is a number.

- [ ] **Step 1: failing tests** (`squad_integrity.test.ts`, group `judgeSale`):
  - `held keeps the baseline price whatever the client sent`: baseline `A@80`, market A 90: squad `A@80` → price 80, realized 0; squad `A@90` → price 80, realized 0; squad `A@10` → price 80, realized 0.
  - `sold riser credits half the rise`: baseline `A@80`, market A 90, squad without A → realized +5.
  - `sold faller costs the full drop`: baseline `A@80`, market A 70, squad without A → realized −10 (even when PriceHistory/gw−1 has A at 80).
  - `a sold player missing from the market adds 0`.
  - `new pick keeps the market floor`: no baseline, market 85, PriceHistory/gw−1 80, client 70 → price 80.
  - `invalid baseline: picks are NEW, realized carries`: baseline node Invalid with `realizedTenths: 7` → realized starts at 7, no held picks.
  - `overBudget uses realized`: picks sum 505, realized +5 → valid; 506 → `overBudget`.
- [ ] **Step 2: failing tests** in `transfer_state.test.ts`: a valid annotated node carries the verdict's prices and `realizedTenths` and keeps unrelated keys; an invalid node keeps the client's prices and carries the baseline's realized. In `finalize_core.test.ts`: History rows copy `realizedTenths` in both branches.
- [ ] **Step 3:** run `npx vitest run src/lib/fantasy`. Expected: the new tests FAIL.
- [ ] **Step 4:** implement. Rewrite the TRUSTED PRICES header comment in `squad_integrity.ts`: "held = baseline id, at the baseline price; the client's price for a held player is ignored; sold = baseline id absent, credited by the FPL rule at the current price"; remove the "no profit-split" wording.
- [ ] **Step 5:** run `npx vitest run` (whole suite) and `npx tsc --noEmit -p .`. Expected: PASS. If `squad_hardening.test.ts` cases change because the old "sell and re-buy cheaper" behaviour is now held-at-baseline, update them and say so in the commit.
- [ ] **Step 6:** commit `feat(fantasy): the lock judge prices sales (FPL rule) and records realizedTenths; snapshots store judged prices`.

### Task 3: `Baselines/<uid>` for every manager, written at the lock, self-healing at finalize

**Files:**
- Modify: `functions/src/lib/fantasy/selling.ts` (+ `baselineNodeOf`), `functions/src/lib/fantasy/orchestration.ts`
- Modify: `database.rules.json`, `database.rules.stage1.json`
- Test: `functions/src/lib/fantasy/selling.test.ts`, `functions/src/lib/fantasy/orchestration.test.ts`, `functions/src/rules_contract.test.ts`

**Interfaces:**
- Produces: TS `baselineNodeOf(effectiveRaw: unknown, forGw: number): { ForGw: number; RealizedTenths: number; Prices: Record<string, number> }`. `Prices` = id → priceTenths of a parseable, non-Invalid node; else `{}`. `RealizedTenths` = `realizedOf(effectiveRaw)`; null node → 0.
- Produces: node `Fantasy/<sport>/<season>/Baselines/<uid>` = `baselineNodeOf(effectiveSquadAfterWeek(gw), gw + 1)`, for EVERY uid in `Managers` ∪ `Squads` ∪ `PublishedPicks/<gw>` (review A.1: a manager with no squad at a lock still gets `{ForGw: gw+1, RealizedTenths: 0, Prices: {}}`, which matches the server: the judge treats them as a fresh start).
- Produces: `async function publishSaleBaselines(db, root, gw: number): Promise<void>` in `orchestration.ts`. It reads the three uid sources itself. Per uid it skips the write when the stored node's `ForGw` is GREATER than `gw + 1` (never backwards) or equals the new node (rerun = no write).

- [ ] **Step 1: failing tests:**
  - `baselineNodeOf`: valid node → prices + realized; Invalid → `Prices {}` + realized; null → `{ForGw, RealizedTenths: 0, Prices: {}}`.
  - Orchestration with the FakeDb:
    - (a) a lock writes `Baselines/<uid>` with `ForGw = gw+1` for every snapshotted manager;
    - (b) a manager in `Managers` with no squad at the week-N lock gets `{ForGw: N+1, RealizedTenths: 0, Prices: {}}`;
    - (c) a Free Hit week's baseline equals the week-before node (prices + realized);
    - (d) re-finalizing gameweek 3 when `Baselines/<uid>.ForGw` is 10 writes nothing;
    - (e) a rerun with identical data performs no write;
    - (f) a first finalize on the live-Squads fallback writes the baselines after its History write.
- [ ] **Step 2:** call `publishSaleBaselines` (1) at the end of `snapshotPublishedPicks`, after the claim is won; and (2) in finalize, after `History/<gw>` is written, on EVERY run (self-heals a failed lock-time write; the never-backwards guard keeps old weeks harmless).
- [ ] **Step 3: rules (both files):** `Baselines` gets `.read` = admin and `$uid/.read` = `auth != null && auth.uid == $uid`, no `.write`, exactly like `TransferState`. Pin it in `rules_contract.test.ts`.
- [ ] **Step 4:** run `npx vitest run` + `npx tsc --noEmit -p .`. Expected: PASS. LOCAL emulator probe (scratchpad `hardening/*.js` pattern): a fan reads his own `Baselines/<uid>`, can't read another's, can't write his own.
- [ ] **Step 5:** commit `feat(fantasy): Baselines/<uid> for every manager (last locked prices + realized); written at lock, healed at finalize`.

### Task 4: Over-budget preview while the window is open (alert + one push)

**Files:**
- Modify: `functions/src/lib/fantasy/squad_integrity.ts` (alert kinds), `functions/src/lib/fantasy/orchestration.ts` (`sweepSeason` step, save-trigger clearing), `functions/src/lib/fantasy/pushes.ts` (the push text)
- Modify: `lib/fantasy/data/fantasy_parsers.dart` (`squadAlertFromNode` + `FantasySquadAlertKind`), `lib/fantasy/hub/squad_builder_logic.dart` (the banner sentence beside today's "Your ... didn't count" wording)
- Test: `functions/src/lib/fantasy/squad_integrity.test.ts`, `orchestration.test.ts`, `pushes.test.ts`; `test/fantasy/fantasy_parsers_test.dart`, `test/fantasy/squad_builder_logic_test.dart`, `test/fantasy/squad_builder_test.dart`

**Interfaces:**
- Consumes: `judgeSquad` → `LockVerdict` (Task 2); `loadIntegrityInputs`, `FantasyPusher.sendToUsers`, `fantasyPushData`, `formatDeadline(dateKey, lockHour)` (existing)
- Produces: `PREVIEW_ALERT_KIND = 'preview'`; `SquadAlerts/<uid>` = `{Gw, Kind: 'preview', Issues: ['overBudget'], OverTenths: int, CreatedAt}`. `isInvalidAlert` is generalised to `isIntegrityAlert(node)` (Kind `invalid` or `preview`) and every existing caller uses it, so the save trigger's "clean squad saved → alert cleared" and the lock's `settleIntegrityAlerts` (an Invalid verdict replaces a preview; a clean lock clears it) cover both kinds.
- Produces: once-only claim node `PreviewPushed/<gw>/<uid>` (set-if-absent, server-only; no rules entry needed).
- Produces (Dart): `FantasySquadAlertKind.overBudgetPreview` with `overTenths`.

Behaviour: in `sweepSeason`, after the GwState upsert, when the current gameweek is `open` and the lock override is not `locked`: judge every `Squads/<uid>` with `loadIntegrityInputs(db, root, uids, current.number)` (the next lock's inputs). A verdict whose issues include `overBudget` writes the preview alert (only when it differs: same Gw + Issues + OverTenths, the `sameInvalidAlert` pattern) and, if `PreviewPushed/<gw>/<uid>` is claimed now, ONE push. `OverTenths` = judged spend − (`budgetTenths` + `realizedTenths`). A squad with no `overBudget` that carries a preview alert has it cleared. An Invalid alert is never touched by the preview. Squads with other issues only (forged squads) get no preview and no push.

Exact copy:
- Push title: `Your fantasy team is over budget`
- Push body: `This week's price changes put your team $1.0M over. Fix it before Sunday 3:00 PM or this week won't count.` (amount from `OverTenths`, deadline from `formatDeadline`)
- Fan banner (bright red, both themes): `Your team is $1.0M over budget after this week's price changes. Fix it before the deadline or this week won't count.`

- [ ] **Step 1: failing tests:** a riser reprice makes a saved squad over by 5 → alert `{Kind:'preview', OverTenths:5}` + exactly one push; a second sweep → no new push, no rewrite; the fan saves a clean squad → the save trigger clears it; a squad back under budget by itself → the next sweep clears it; a locked week → nothing runs; the lock judging the same squad Invalid replaces the preview alert with the Invalid alert. Dart: the parser reads Kind `preview` + `OverTenths`; the banner shows the exact sentence in light and dark at 360 px.
- [ ] **Step 2:** run `npx vitest run src/lib/fantasy` and `flutter test test/fantasy/fantasy_parsers_test.dart test/fantasy/squad_builder_test.dart`. Expected: FAIL.
- [ ] **Step 3:** implement.
- [ ] **Step 4:** the same commands, then `npx vitest run` + `npx tsc --noEmit -p .`. Expected: PASS.
- [ ] **Step 5:** commit `feat(fantasy): over-budget preview alert + one push while the week is open`.

### Task 5: Close the uncounted-saves gap (rules + lock-time recount)

**Files:**
- Modify: `database.rules.json`, `database.rules.stage1.json` (`Squads/$uid` `.validate`)
- Modify: `functions/src/lib/fantasy/transfer_state.ts` (`lockAccounting`)
- Test: `functions/src/rules_contract.test.ts`, `functions/src/lib/fantasy/transfer_state.test.ts`

Rules: today the deadline group in `Squads/$uid` `.validate` accepts a save when `GwState` is absent, OR `status !== 'open'`, OR `now < lockAtUtc`, OR the effective 'open' lockOverride. Replace the middle two with ONE clause: `status === 'open' && now < lockAtUtc`. Keep the no-GwState case, the 'open' lockOverride clause and the `.write` delete gate exactly as they are. Note for the commit: if the sweep is down past midnight nobody can save until it recovers (today they could, uncounted); the sweep has backstops.

Recount: in `lockAccounting`, when `integrity` is present and the manager has a parseable non-Invalid baseline (`integrity.previousByUid[uid]`), the week's `used` = `max(state.usedThisGw, usedAfterFreeSwaps(squad, baselineSquad, state, gw))`. Unlimited chips (wildcard / freeHit) stay free. No baseline → stored value unchanged.

- [ ] **Step 1: failing tests:** `rules_contract.test.ts` pins the new clause in both files; `transfer_state.test.ts`: a squad with 3 sales locked while `UsedThisGw` says 0 and `Free` is 2 → cost = 1 extra × `extraTransferCost`; a wildcard week → cost 0; FreeSwaps players sold are not counted; no baseline → stored value kept.
- [ ] **Step 2:** run `npx vitest run src/rules_contract.test.ts src/lib/fantasy/transfer_state.test.ts`. Expected: FAIL.
- [ ] **Step 3:** implement both.
- [ ] **Step 4:** `npx vitest run` + `npx tsc --noEmit -p .`. Expected: PASS. LOCAL emulator probe: a fan save under `status 'locked'` DENIED, under `'finalized'` DENIED, under `'open'` before `lockAtUtc` ALLOWED, after `lockAtUtc` DENIED, under the effective 'open' override ALLOWED, with no `GwState` ALLOWED; a delete while open ALLOWED (gate unchanged).
- [ ] **Step 5:** commit `fix(fantasy): squads save only while the week is open; the lock recounts transfers`.

### Task 6: Fan data + the draft knows its money

**Files:**
- Modify: `lib/fantasy/data/fantasy_service.dart` (stream + cache), `lib/fantasy/hub/squad_draft.dart`, `lib/fantasy/hub/fantasy_hub_page.dart` (subscription)
- Test: `test/fantasy/squad_draft_test.dart`, `test/fantasy/fantasy_session_test.dart` (cache guard)

**Interfaces:**
- Consumes: `SaleBaseline`, `saleBaselineFromNode`, `realizedNowTenths`, `buyPriceTenths` (Task 1); node `Baselines/<uid>` (Task 3)
- Produces: `FantasyService.watchMySaleBaseline(String sport, String season) → Stream<SaleBaselineState>`, `class SaleBaselineState { final SaleBaseline? baseline; final bool loaded; final bool degraded; }`. Seeded from `_saleBaselineCache` (key `<root>|<uid>`). An absent node → `baseline: null, loaded: true` (a first squad). A stream error keeps the cached value, else `degraded: true`.
- Produces on `SquadDraftController`:
  - `void setSaleContext({SaleBaselineState? sale, Map<String, int> currentPrices, int? editingGw})`
  - `int priceOfPick(SquadPick p)`: the baseline price when `p.playerId` is a baseline id, else `p.priceTenths` (held = id, Global Constraints). `spentTenths` sums `priceOfPick`.
  - `int get realizedTenths` (via `realizedNowTenths` over the draft's ids, unplaced included)
  - `int get availableTenths` (= `config.budgetTenths + realizedTenths`), `int get remainingTenths` (= `available − spentTenths`)
  - `int remainingIfRemovedTenths(SquadPick pick)`: the room after removing `pick`, realized recomputed
  - `int buyPriceOf(FantasyPlayer p)`, `SquadPick newPick(FantasyPlayer p, {required bool bench})` priced by `buyPriceOf`
  - `int? sellPriceOf(String playerId)`: non-null only for a baseline id
  - `bool get moneyReady`: false while not loaded, degraded, or when `baseline != null && baseline.forGw != editingGw`

Every place that builds a `SquadPick` from a `FantasyPlayer` (`squad_draft.dart` `addPlayer`, `squad_builder.dart` `_pickInto` and the unplaced swap) uses `newPick`.

- [ ] **Step 1: failing draft tests:**
  - `re-adding a sold baseline player restores his baseline price`: baseline A@80, current 90, remove A, add A → pick price 80, `realizedTenths` = baseline realized.
  - `a held pick saved at another price counts at the baseline price`: draft adopts `A@90` with baseline A@80 → `spentTenths` counts 80.
  - `selling a riser grows the room`: baseline A@80, current 90, realized 0, remove A → `remainingTenths` = previous remaining + 85.
  - `remainingIfRemovedTenths matches remove-then-read`.
  - `stale baseline is not moneyReady`: `forGw` 4, editing 5 → false; absent baseline + loaded → true; degraded → false.
  - `a new player costs today's price`.
- [ ] **Step 2:** add the guard-test expectation that `_saleBaselineCache` is cleared by `clearSessionCaches()`.
- [ ] **Step 3:** run `flutter test test/fantasy/squad_draft_test.dart test/fantasy/fantasy_session_test.dart`. Expected: FAIL.
- [ ] **Step 4:** implement. In `fantasy_hub_page.dart`, subscribe `watchMySaleBaseline` next to the squad stream and feed `draft.setSaleContext`; `currentPrices` from the players list, `editingGw` from `chipEditingGameweek(gameweeks, now)` (`lib/fantasy/data/chip_usage.dart`). This stream does NOT gate the hub's fade reveal.
- [ ] **Step 5:** the same commands. Expected: PASS. Commit `feat(fantasy): the squad draft prices buys and sales by the FPL rule`.

### Task 7: Fan UI shows the real money

**Files:**
- Modify: `lib/fantasy/hub/squad_builder.dart` (budget bar, picker room), `lib/fantasy/hub/squad_picker_sheet.dart` (`showSquadPickerSheet` takes `int Function(FantasyPlayer) priceOf` and compares it to `remainingTenths`), `lib/fantasy/hub/market_logic.dart` (`marketAddState`: replace `budgetTenths` with `remainingTenths` + `priceOf`), `lib/fantasy/hub/players_tab.dart`, `lib/fantasy/hub/market_player_sheet.dart`, `lib/fantasy/profile/fantasy_player_profile_page.dart`, `lib/fantasy/hub/squad_builder_logic.dart` (the over-budget sentence uses `availableTenths`), `lib/fantasy/hub/court_view.dart` (shown prices of baseline picks use `priceOfPick`)
- Test: `test/fantasy/market_logic_test.dart`, `squad_builder_test.dart`, `squad_builder_logic_test.dart`, `players_tab_test.dart`

Exact copy:
- Budget bar: `$X spent` / `$Y left` (unchanged words; total = `availableTenths`). When `realizedTenths != 0`, a second line: `Includes +$0.5M from sales` or `Includes −$0.5M from sales`; negative in `fantasyDownRed`.
- An owned baseline player, wherever his Remove control shows (market sheet, player profile): `Bought $8.0M · Sells for $8.5M`.
- Save blocked while `!draft.moneyReady`: `Your budget is still updating — try again in a few minutes.`

- [ ] **Step 1: failing tests:**
  - `marketAddState` uses `priceOf` (a baseline player re-added at 80 is affordable with 80 left while the market says 90).
  - Builder: the bar shows the realized line with +/− and the right colour in light AND dark.
  - The sells-for line appears only for baseline players.
  - Save is disabled with the exact sentence when `moneyReady` is false.
  - The over-budget sentence counts realized.
  - Layout at 360 px in both themes.
- [ ] **Step 2:** run `flutter test test/fantasy`. Expected: the new tests FAIL.
- [ ] **Step 3:** implement. Every `budgetTenths - spent` affordability computation in `lib/fantasy/hub` and `lib/fantasy/profile` goes through the draft (grep `budgetTenths` afterwards; only config display, `fantasy_walkthrough.dart` and `rules_tab.dart`, may remain).
- [ ] **Step 4:** run `flutter test test/fantasy` + `flutter analyze lib/fantasy test/fantasy`. Expected: PASS, 0 new issues.
- [ ] **Step 5:** commit `feat(fantasy): builder, market and profiles show FPL sell prices and the real room`.

### Task 8: Rules tab explains it

**Files:** `lib/fantasy/hub/rules_tab.dart`; test `test/fantasy/rules_tab_test.dart`

- [ ] **Step 1: failing test.** The Prices section no longer says "You always buy and sell at the current price". A Selling section shows this exact copy (amounts from config where config-driven):
  - `You buy at today's price. When you sell, you keep half of any rise (rounded down to $0.1M) and take the full drop.`
  - `Example: bought at $8.0M, now $9.0M → sells for $8.5M. Bought at $8.0M, now $7.0M → sells for $7.0M.`
  - `Changed your mind? Put a player you sold this week back before the deadline and he returns at the price you paid — no transfer used.`
  - `Prices change on Monday morning. If a change puts your saved team over budget, you'll get a message so you can fix it before the deadline.`
- [ ] **Step 2:** implement. Run `flutter test test/fantasy/rules_tab_test.dart`. Expected: PASS.
- [ ] **Step 3:** commit `docs(fantasy): Rules tab explains the selling rule`.

### Task 9: Deploy, install, verify

- [ ] Full checks: `npx vitest run` (all), `npx tsc --noEmit -p .`, `flutter test` (whole fan suite), `flutter analyze`.
- [ ] LOCAL emulator rehearsal (scratchpad script, `firebase emulators:exec --only database --project demo-selling`). Seed a season with gameweeks and two managers (one without a squad), then run the lock, a save that sells a riser, a reprice that puts the other over budget (preview alert), and the next lock. Check `PublishedPicks/<gw>/<uid>/realizedTenths`, `Baselines/<uid>` for both, the preview alert, and that the budget verdict matches the app's numbers for the same inputs.
- [ ] Fill tool: run the S15 fill tool in its default dry run only (no `--apply`) and confirm its replay reports no new Invalid squads; anything else waits for the owner.
- [ ] Deploy `database` + every fantasy function (list with `firebase functions:list | grep -i fantasy`; at least the sweep, finalize, the reprice and the Squads trigger) to `infinite-sports-app`. Verify live rules == file.
- [ ] Build + install the fan APK on the emulator. The owner checks the Rules tab and the builder. Season 15's existing locked weeks have no `realizedTenths`, which reads as 0.
- [ ] PR iOS lines: the realized line, the sells-for line and the preview banner on iPhone SE width; dark mode colours; the preview push tap routes to My Team (verify on simulator).
- [ ] Memory: update `infinite_fantasy_plan.md` (spec §4 changed, `Baselines` node, judge semantics, preview alert, rules tightening).

## Self-review

- **Spec coverage:** the rule (Task 1), server truth (Task 2), the app's data (Tasks 3, 6), the open-window warning (Task 4), the uncounted-saves gap (Task 5), the app's display (Task 7), the explanation (Task 8), shipping (Task 9). Manager: no change (no budget math).
- **Types:** `LockVerdict`, `judgeSale`, `baselineNodeOf`, `publishSaleBaselines`, `isIntegrityAlert`, `SaleBaseline`, `SaleBaselineState`, `priceOfPick` and the draft API names match across tasks.
- **Review rulings folded in:** A.1 (every manager gets a baseline), A.2 (current price only), A.3 (held at baseline), A.4 (preview task), addendum (rules), recount, nits (copy).
