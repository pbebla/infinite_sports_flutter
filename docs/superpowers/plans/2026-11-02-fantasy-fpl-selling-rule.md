# Fantasy FPL Selling Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selling a player follows the Premier League Fantasy rule: you keep half of any price rise (rounded down to $0.1M) and take the full drop, so your spending room grows or shrinks with what you sell.

**Architecture:** Each pick keeps the price PAID (unchanged). New: every locked squad carries a server-computed `realizedTenths` (the running total of profit/loss from sales), and the budget rule becomes `sum of prices paid ≤ budget + realizedTenths`. The server judge decides, at the lock, which baseline players were sold and at what trusted price. A new server-written node `Baselines/<uid>` gives the fan app last week's locked prices and the running total, so the squad builder shows the same money the server will charge. The Manager app is unaffected: it never computes budgets.

**Tech stack:** Cloud Functions TS (vitest, `FakeDb` now runs transactions cold), Flutter fan app (plain `onValue` streams, session caches), RTDB rules (both files).

**Spec:** `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §4. Its bullet "Buying and selling always at current price (no FPL profit-split accounting)" is REPLACED by this plan (Task 1 edits the spec). Owner decision 2026-11-02, verbatim: "yes go with premier league rule, write the plan".

**Repo / branch:** fan repo `infinite_sports_flutter`, branch `zaya-fantasy`. Commit locally, never push. Ship before Futsal Season 16 gameweek 1 (changing it mid-season would be unfair). Season 15 is test data only.

## Global Constraints

- Money is integer **tenths** of $1M everywhere (`budgetTenths` 500 = $50.0M; price step 5 = $0.5M).
- **Sell price:** `purchase + floor((current − purchase) / 2)` when `current > purchase`, else `current`. Integer division floors to $0.1M. Examples (tenths): 80→90 sells 85; 80→85 sells 82; 80→70 sells 70; 80→80 sells 80.
- **Spending room:** `budgetTenths + realizedTenths − Σ pick.priceTenths ≥ 0`. `realizedTenths` may be negative.
- **"Held" means same player AND same price as the baseline.** Re-adding a player from last week's locked squad restores his baseline price (no sale, no transfer: the transfer counter already compares by player id). A baseline player present at a DIFFERENT price is a sale plus a re-buy.
- Baseline = the manager's effective squad after the previous gameweek (`effectiveSquadAfterWeek(gw−1)`, Free Hit aware). The server judge, the transfer counter and `Baselines/<uid>` all use this one baseline (the S15 "Bug 1" lesson).
- Fan app: `onValue` streams only, never RTDB `.get()`; every new static cache cleared in `clearSessionCaches()` (the guard test enforces it); error ≠ fact (a failed or stale baseline never shows a made-up budget).
- Every new UI element fits light AND dark mode; negative money uses `fantasyDownRed` (#FF5252 dark / #D32F2F light); layouts hold at 360 px wide.
- Rules: edit `database.rules.json` AND `database.rules.stage1.json`; probe only in the LOCAL emulator.
- Every RTDB transaction never aborts on a null first run (the 2026-11-02 refund bug class).

## Review Focus

1. **Sell and re-buy the same player in one window** must cost nothing: price restored, no sale counted, no transfer. (Task 2 server test, Task 4 draft test.)
2. **The Monday reprice race.** The window opens at midnight and prices move at 10:00, so a 9 am sale used last week's price. The server credits a sold player at the HIGHER of his current and last-week price, while the app uses the current price. The app can only ever show less room than the server allows, never more. (Task 2 test.)
3. **Free Hit week.** Its sales are temporary: the baseline after a Free Hit is the squad before it, with that squad's `realizedTenths`. (Task 3 test.)
4. **An old week re-finalized** (a score edit on gameweek 3 during gameweek 9) must never move `Baselines/<uid>` backwards. (Task 3 test.)
5. **Stale or failed baseline in the app.** Save is blocked with a plain sentence. The budget bar never shows a wrong number. (Task 5 test.)

Bonus fix, flagged for review: today a squad that under-claims a pick's price can pass the lock check, because the check reprices it, while the snapshot stores the under-claimed price. Next week that low price becomes the "held" baseline. Task 2 stores the judge's trusted prices in valid snapshots, which closes this. Honest squads are unchanged, because their price equals the trusted price.

---

### Task 1: The selling math, twice (server + app), and the budget rule

**Files:**
- Create: `functions/src/lib/fantasy/selling.ts`, test `functions/src/lib/fantasy/selling.test.ts`
- Create: `lib/fantasy/engine/selling.dart`, test `test/fantasy/selling_test.dart`
- Modify: `functions/src/lib/fantasy/squad.ts` (`validateSquad`), `lib/fantasy/engine/squad.dart` (`validateSquad`), and both pick comments ("price PAID; sells by the FPL rule, selling.ts")
- Modify: `docs/superpowers/specs/2026-10-26-infinite-fantasy-design.md` §4 (replace the "current price" bullet with the Global Constraints rule and the examples)
- Test: `functions/src/lib/fantasy/squad.test.ts`, `test/fantasy/squad_test.dart`

**Interfaces (Produces):**
- TS `sellPriceTenths(purchaseTenths: number, currentTenths: number): number`
- TS `realizedOf(node: unknown): number`: the node's `realizedTenths` when it is a finite number (truncated), else 0
- TS `validateSquad(s, cfg, realizedTenths = 0)`: `overBudget` when `spentTenths(s) > cfg.budgetTenths + realizedTenths`
- Dart `int sellPriceTenths({required int purchaseTenths, required int currentTenths})`
- Dart `class SaleBaseline { final int forGw; final Map<String, int> prices; final int realizedTenths; }` + `SaleBaseline? saleBaselineFromNode(Object? node)` (null when not a map or `ForGw` missing; `Prices` non-int values dropped; absent `RealizedTenths` → 0)
- Dart `int realizedNowTenths(SaleBaseline? b, Iterable<SquadPick> picks, Map<String, int> currentPrices)` = `b.realizedTenths + Σ over baseline ids NOT held (held = a pick with that id at exactly b.prices[id]) of sellPriceTenths(b.prices[id], currentPrices[id] ?? b.prices[id]) − b.prices[id]`; `b == null` → 0
- Dart `int buyPriceTenths(SaleBaseline? b, String playerId, int currentTenths)` = `b?.prices[playerId] ?? currentTenths`
- Dart `validateSquad(s, cfg, {int realizedTenths = 0})`, same rule as TS

- [ ] **Step 1: failing tests.** Use ONE shared table in both `selling.test.ts` and `selling_test.dart`, `(purchase, current) → sell`: `(80,90)→85, (80,85)→82, (80,81)→80, (80,80)→80, (80,70)→70, (40,150)→95, (150,40)→40`. `realizedNowTenths`: baseline `{A:80, B:60}`, realized 5, current `{A:90, B:50}`, picks `[A@80]` → `5 + (50−60) = −5`; picks `[A@90, B@60]` → A sold at 85 (+5), B held → `10`; `b == null` → 0. `validateSquad`: spent 505 with realized 5 → no overBudget; spent 506 → overBudget; spent 500 with realized −1 → overBudget.
- [ ] **Step 2:** run `cd functions; npx vitest run src/lib/fantasy/selling.test.ts src/lib/fantasy/squad.test.ts` and `flutter test test/fantasy/selling_test.dart test/fantasy/squad_test.dart`. Expected: FAIL (missing symbols).
- [ ] **Step 3:** implement the Interfaces above. Edit spec §4.
- [ ] **Step 4:** the same commands. Expected: PASS. Also run `npx tsc --noEmit -p .`.
- [ ] **Step 5:** commit `feat(fantasy): FPL selling math + budget includes realized sales (both twins, spec §4)`.

### Task 2: The server judge prices sales and records `realizedTenths`

**Files:**
- Modify: `functions/src/lib/fantasy/squad_integrity.ts`, `functions/src/lib/fantasy/transfer_state.ts` (`annotateSquadIntegrity`), `functions/src/lib/fantasy/finalize_core.ts` (History rows)
- Test: `functions/src/lib/fantasy/squad_integrity.test.ts`, `transfer_state.test.ts`, `finalize_core.test.ts`, `squad_hardening.test.ts`

**Interfaces:**
- Consumes: `sellPriceTenths`, `realizedOf`, `validateSquad(…, realizedTenths)` (Task 1)
- Produces: `interface LockVerdict { issues: SquadIntegrityIssue[]; prices: number[]; realizedTenths: number }`. `judgeSquad(...)` and `integrityVerdictOf(...)` return `LockVerdict` (`integrityVerdictOf` → `LockVerdict | null` for malformed). `trustedPrices` is replaced by `judgeSale(squad, market, baseline: FantasySquad | null, baselineRealized: number, previousWeekPrices): { prices: number[]; realizedTenths: number }`

Rules `judgeSale` implements, per pick, against the baseline's picks (`baselineSquadOf`, which is null when absent or Invalid, so every pick is NEW):
- **held** (baseline has this id at exactly this `priceTenths`): price = baseline price.
- **new or re-bought** (anything else): price = `max(0, client price, market floor)`. The market floor is unchanged: `min(current, PriceHistory/gw−1)`.
- **sold** (each baseline id not held): `realized += sellPriceTenths(baselinePrice, max(current, previousWeekPrices[id] ?? current)) − baselinePrice`. A player missing from the market sells at his baseline price, so he adds 0.
- `realizedTenths = realizedOf(baselineRaw) + Σ sold`. `realizedOf` reads the RAW baseline node even when it is Invalid, because the server wrote that number. Only an Invalid node's picks are untrusted.
- `overBudget` comes from `validateSquad(repriced, cfg, realizedTenths)`.

Snapshot nodes (`annotateSquadIntegrity`):
- **Valid:** the picks are re-written with the verdict's prices, other keys are kept, and `realizedTenths` is set. For an honest squad nothing visible changes. This closes the under-claim hole.
- **Invalid:** verbatim, plus `Invalid`, plus `realizedTenths` = `realizedOf(baselineRaw)`. No sale is credited.
- **Malformed:** untouched, as today.

History rows: `finalize_core` copies the source node's `realizedTenths` onto `History/<gw>/<uid>` in BOTH branches (invalid and scored) when it is a number.

- [ ] **Step 1: failing tests** (`squad_integrity.test.ts`, group `judgeSale`):
  - `held keeps the baseline price`: baseline `A@80`, market A 90, squad `A@80` → prices `[80]`, realized 0.
  - `sold riser credits half the rise`: baseline `A@80`, market A 90, squad without A → realized +5.
  - `sold faller costs the full drop`: baseline `A@80`, market A 70 → realized −10.
  - `re-bought at a new price is a sale plus a buy`: baseline `A@80`, market A 90, squad `A@90` → realized +5 and price 90. The budget counts 90.
  - `under-claimed held price is a re-buy at the market floor`: baseline `A@80`, market A 80, squad `A@10` → price 80, realized 0.
  - `reprice race credits the higher price`: baseline `A@80`, market A 85, PriceHistory/gw−1 A 90, sold → realized +5 (the higher price, 90, gives 85, so 85 − 80 = 5).
  - `invalid baseline: picks are NEW, realized carries`: baseline node Invalid with `realizedTenths: 7` → realized starts at 7, no held picks.
  - `overBudget uses realized`: picks sum 505, realized +5 → valid; sum 506 → `overBudget`.
- [ ] **Step 2: failing tests** in `transfer_state.test.ts`: a valid annotated node carries the verdict's prices and `realizedTenths`, and keeps unrelated keys. An invalid node keeps the client's prices and carries the baseline's realized. And in `finalize_core.test.ts`: History rows copy `realizedTenths` in both branches.
- [ ] **Step 3:** run `npx vitest run src/lib/fantasy`. Expected: the new tests FAIL.
- [ ] **Step 4:** implement. Update the TRUSTED PRICES header comment in `squad_integrity.ts` to describe held, sold and re-bought, and remove the "no profit-split" wording.
- [ ] **Step 5:** run `npx vitest run` (the whole suite) and `npx tsc --noEmit -p .`. Expected: PASS. If `squad_hardening.test.ts` cases change because a held price under the old "sell and re-buy cheaper" behaviour is now priced as a sale plus a re-buy, update them and say so in the commit.
- [ ] **Step 6:** commit `feat(fantasy): the lock judge prices sales (FPL rule) and records realizedTenths; snapshots store trusted prices`.

### Task 3: `Baselines/<uid>`, written at the lock, self-healing at finalize

**Files:**
- Modify: `functions/src/lib/fantasy/selling.ts` (+ `baselineNodeOf`), `functions/src/lib/fantasy/orchestration.ts`
- Modify: `database.rules.json`, `database.rules.stage1.json`
- Test: `functions/src/lib/fantasy/selling.test.ts`, `functions/src/lib/fantasy/orchestration.test.ts`, `functions/src/rules_contract.test.ts`

**Interfaces:**
- Produces: TS `baselineNodeOf(effectiveRaw: unknown, forGw: number): { ForGw: number; RealizedTenths: number; Prices: Record<string, number> }`. `Prices` = id → priceTenths of a parseable, non-Invalid node; else `{}`. `RealizedTenths` = `realizedOf(effectiveRaw)`.
- Produces: node `Fantasy/<sport>/<season>/Baselines/<uid>` = `baselineNodeOf(effectiveSquadAfterWeek(gw), gw + 1)`. The fan app reads it in Task 4.
- Produces: `async function publishSaleBaselines(db, root, uids: string[], gw: number)` in `orchestration.ts`. For each uid it computes the node. It skips the write when the stored node's `ForGw` is GREATER than `gw + 1` (never backwards) or when it is equal to the new node (rerun = no write).

- [ ] **Step 1: failing tests:**
  - `baselineNodeOf`: valid node → prices + realized; Invalid → `Prices {}` + realized; null → `{ForGw, RealizedTenths: 0, Prices: {}}`.
  - Orchestration with the FakeDb:
    - (a) a lock writes `Baselines/<uid>` with `ForGw = gw+1` for every snapshotted manager;
    - (b) a Free Hit week's baseline equals the week-before node (prices + realized);
    - (c) re-finalizing gameweek 3 when `Baselines/<uid>.ForGw` is 10 writes nothing;
    - (d) a rerun with identical data performs no write;
    - (e) a first finalize on the live-Squads fallback writes the baselines after its History write.
- [ ] **Step 2:** call `publishSaleBaselines` (1) at the end of `snapshotPublishedPicks`, after the claim is won, for `Object.keys(acc.cleanSquads)`; and (2) in finalize, after `History/<gw>` is written, for the week's uids, on EVERY run (self-heals a failed lock-time write; the never-backwards guard keeps old weeks harmless).
- [ ] **Step 3: rules (both files):** `Baselines` gets `.read` = admin and `$uid/.read` = `auth != null && auth.uid == $uid`, with no `.write`, exactly like `TransferState`. Pin it in `rules_contract.test.ts`.
- [ ] **Step 4:** run `npx vitest run` + `npx tsc --noEmit -p .`. Expected: PASS. LOCAL emulator probe (scratchpad pattern `hardening/*.js`, `JAVA_HOME` = Android Studio jbr): the owner can read his own `Baselines/<uid>`, can't read anyone else's, and can't write his own.
- [ ] **Step 5:** commit `feat(fantasy): Baselines/<uid> (last locked prices + realized) for the app; written at lock, healed at finalize`.

### Task 4: Fan data + the draft knows its money

**Files:**
- Modify: `lib/fantasy/data/fantasy_service.dart` (stream + cache), `lib/fantasy/hub/squad_draft.dart`
- Test: `test/fantasy/squad_draft_test.dart`, `test/fantasy/fantasy_session_test.dart` (cache guard)

**Interfaces:**
- Consumes: `SaleBaseline`, `saleBaselineFromNode`, `realizedNowTenths`, `buyPriceTenths` (Task 1); the node `Baselines/<uid>` (Task 3)
- Produces: `FantasyService.watchMySaleBaseline(String sport, String season) → Stream<SaleBaselineState>`, with `class SaleBaselineState { final SaleBaseline? baseline; final bool loaded; final bool degraded; }`. It is seeded from `_saleBaselineCache` (key `<root>|<uid>`). An absent node means `baseline: null, loaded: true` (a first squad). A stream error keeps the cached value, else `degraded: true`.
- Produces on `SquadDraftController`:
  - `void setSaleContext({SaleBaselineState? sale, Map<String, int> currentPrices, int? editingGw})`
  - `int get realizedTenths`
  - `int get availableTenths` (= `config.budgetTenths + realizedTenths`)
  - `int get remainingTenths` (= `available − spentTenths`)
  - `int remainingIfRemovedTenths(SquadPick pick)`: the room after removing `pick`, with the realized value recomputed
  - `int buyPriceOf(FantasyPlayer p)`
  - `SquadPick newPick(FantasyPlayer p, {required bool bench})`: priced by `buyPriceOf`
  - `int? sellPriceOf(String playerId)`: non-null only for a baseline id
  - `bool get moneyReady` (false while loading, degraded, or when `baseline.forGw != editingGw`)

Every place that builds a `SquadPick` from a `FantasyPlayer` (`squad_draft.dart` `addPlayer`, `squad_builder.dart` `_pickInto` and the unplaced swap) uses `newPick`.

- [ ] **Step 1: failing draft tests:**
  - `re-adding a sold baseline player restores his baseline price`: baseline A@80, current 90, remove A, add A → pick price 80, `realizedTenths` = baseline realized.
  - `selling a riser grows the room`: baseline A@80, current 90, realized 0, remove A → `remainingTenths` = previous remaining + 85.
  - `remainingIfRemovedTenths matches remove-then-read`.
  - `stale baseline is not moneyReady`: `forGw` 4, editing 5 → false. Absent baseline + loaded → true.
  - `a new player costs today's price`.
- [ ] **Step 2:** add the guard-test expectation that `_saleBaselineCache` is cleared by `clearSessionCaches()`.
- [ ] **Step 3:** run `flutter test test/fantasy/squad_draft_test.dart test/fantasy/fantasy_session_test.dart`. Expected: FAIL.
- [ ] **Step 4:** implement. In `fantasy_hub_page.dart`, subscribe `watchMySaleBaseline` next to the squad stream and feed `draft.setSaleContext`. `currentPrices` comes from the players list and `editingGw` from `chipEditingGameweek(gameweeks, now)`. This stream does NOT gate the hub's fade reveal.
- [ ] **Step 5:** the same commands. Expected: PASS. Commit `feat(fantasy): the squad draft prices buys and sales by the FPL rule`.

### Task 5: Fan UI shows the real money

**Files:**
- Modify: `lib/fantasy/hub/squad_builder.dart` (budget bar, picker room), `lib/fantasy/hub/squad_picker_sheet.dart` (`showSquadPickerSheet` takes `int Function(FantasyPlayer) priceOf` and compares it to `remainingTenths`), `lib/fantasy/hub/market_logic.dart` (`marketAddState`: replace `budgetTenths` with `remainingTenths` + `priceOf`), `lib/fantasy/hub/players_tab.dart`, `lib/fantasy/hub/market_player_sheet.dart`, `lib/fantasy/profile/fantasy_player_profile_page.dart`, `lib/fantasy/hub/squad_builder_logic.dart` (the over-budget sentence uses `availableTenths`)
- Test: `test/fantasy/market_logic_test.dart`, `squad_builder_test.dart`, `squad_builder_logic_test.dart`, `players_tab_test.dart`

Exact copy:
- Budget bar: `$X spent` / `$Y left` (unchanged words; total = `availableTenths`). When `realizedTenths != 0`, a second line reads `Includes +$0.5M from sales` or `Includes −$0.5M from sales`. A negative value uses `fantasyDownRed`.
- An owned baseline player, wherever his Remove control shows (market sheet, player profile): `Bought $8.0M · Sells for $8.5M`.
- Save blocked while `!draft.moneyReady`: `Your budget is still updating — try again in a minute.`

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

### Task 6: Rules tab explains it

**Files:** `lib/fantasy/hub/rules_tab.dart`; test `test/fantasy/rules_tab_test.dart`

- [ ] **Step 1: failing test.** The Prices section no longer says "You always buy and sell at the current price". A Selling section shows this exact copy, with amounts from config where the numbers are config-driven:
  - `You buy at today's price. When you sell, you keep half of any rise (rounded down to $0.1M) and take the full drop.`
  - `Example: bought at $8.0M, now $9.0M → sells for $8.5M. Bought at $8.0M, now $7.0M → sells for $7.0M.`
  - `Changed your mind? Put a player you sold this week back before the deadline and he returns at the price you paid — no transfer used.`
- [ ] **Step 2:** implement. Run `flutter test test/fantasy/rules_tab_test.dart`. Expected: PASS.
- [ ] **Step 3:** commit `docs(fantasy): Rules tab explains the selling rule`.

### Task 7: Deploy, install, verify

- [ ] Full checks: `npx vitest run` (all), `npx tsc --noEmit -p .`, `flutter test` (whole fan suite), `flutter analyze`.
- [ ] LOCAL emulator rehearsal (scratchpad script, `firebase emulators:exec --only database --project demo-selling`). Seed a season with gameweeks and two managers, then run the lock, a save that sells a riser, and the next lock. Check `PublishedPicks/<gw>/<uid>/realizedTenths`, `Baselines/<uid>` and that the budget verdict matches the app's numbers for the same inputs. Never run the S15 fill tool with `--apply`.
- [ ] Deploy `database` + every fantasy function (list them with `firebase functions:list | grep -i fantasy`; the sweep, finalize and the Squads trigger at least) to `infinite-sports-app`. Verify live rules == file.
- [ ] Build + install the fan APK on the emulator. The owner checks the Rules tab and the builder. Season 15's existing locked weeks have no `realizedTenths`, which reads as 0, so nothing changes for them.
- [ ] PR iOS lines: the realized line and sells-for line on iPhone SE width; dark mode colours (verify on simulator).
- [ ] Memory: update `infinite_fantasy_plan.md` (spec §4 changed, `Baselines` node, judge semantics).

## Self-review

- **Spec coverage:** the rule (Task 1), server truth (Task 2), the app's data (Tasks 3–4), the app's display (Task 5), the explanation (Task 6), shipping (Task 7). Manager: no change, checked: it has no budget math.
- **Types:** `LockVerdict`, `judgeSale`, `baselineNodeOf`, `publishSaleBaselines`, `SaleBaseline`, `SaleBaselineState` and the draft API names match across tasks.
- **Open questions for Fable:**
  1. Is crediting a sold player at the higher of his current and last-week price, to cover the Monday race, acceptable? The alternative is moving the reprice to before the window opens.
  2. Should the budget bar also show "Team value" like Premier League Fantasy? This plan leaves it out.
  3. Is rewriting valid snapshots with trusted prices acceptable? The alternative is a separate `TrustedPrices` key.
