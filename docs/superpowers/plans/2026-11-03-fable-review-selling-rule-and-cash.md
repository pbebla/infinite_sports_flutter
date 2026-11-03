# Fable review (2026-11-03): FPL selling rule plan + cash Manager-only plan

Reviewed against the code on branch `zaya-fantasy` (fan repo `e5a538c`, Manager `0f31921`). Every claim below was checked in the source, not taken from the plans.

---

## A. `2026-11-02-fantasy-fpl-selling-rule.md`

**Verdict:** the design is right (price paid stays on the pick; the server computes a running `realizedTenths` at each lock; `Baselines/<uid>` gives the app the same numbers). Execute it with the four changes under "Must fix", in the plan's task order, subagent-driven. Tasks 2 and the new preview task deserve the hardest review.

### Must fix before execution

**1. Lockout bug: `moneyReady` can block a manager forever (Tasks 3 + 4).**
`publishSaleBaselines` writes only for managers who had a squad at that lock (`Object.keys(acc.cleanSquads)`, and the finalize self-heal uses the week's History uids, the same set). A manager with no squad at the lock of week N keeps `ForGw = N`. While editing N+1 the plan's `moneyReady` (`forGw == editingGw`) is false, Save is blocked, so they have no squad at the lock of N+1 either, and so on. Deleting a squad is allowed during the open window, so this will happen.
Fix: at every lock and at every finalize self-heal, write `Baselines/<uid>` for EVERY uid in `Managers` ∪ `Squads` ∪ `PublishedPicks/<gw>`. A uid with no effective squad gets `{ForGw: gw+1, RealizedTenths: 0, Prices: {}}`. That matches the server exactly (`effectiveSquadAfterWeek` returns null for them, so the judge treats them as a fresh start). Add a Task 3 test: manager absent at the week-N lock → node `{ForGw: N+1, RealizedTenths: 0, Prices: {}}`. Keep `forGw != editingGw → not ready` for the ≤15-minute gap between the lock instant and the sweep's snapshot (the rules reject saves there anyway). Task 5 copy: "try again in a few minutes", not "in a minute".

**2. Drop the `max(current, last week)` sale credit. Credit sales at the current price. (Answers open question 1: no.)**
Verified timing: a gameweek opens at 00:00 league time the day after the previous match day (`deriveGameweeks`), the reprice runs Monday 10:00 PT (`fantasyMondayReprice`). So the race the plan guards against is real, but `max()` is the wrong guard:
- A faller sold the week he falls is never charged the drop (`sellPrice(80, max(70, 80)) = 80`). Most sales are exactly that, so "take the full drop" would rarely be true. The owner chose the FPL rule; this quietly isn't it.
- REST loophole: baseline `A@80`, market now 70. A REST write of `A@70` is a "re-buy": sale credited at 80 (realized 0) plus a buy at 70. Spent drops by 10 for free, every faller, every week. The hardening round existed to close exactly this class.
- The honest app would show −$1.0M for that sale while the server gives 0, so money "appears" after the lock.
Replace it with 3 and 4 below. The buy-side market floor (`min(current, PriceHistory/gw−1)`) stays as it is.

**3. Simplify the judge: a baseline player present in the squad is HELD at his baseline price, whatever price the client sent.**
No "re-bought at a different price" case. Per pick: baseline id → baseline price; other id → `max(0, client, market floor)` (unchanged). Sold = baseline ids absent from the squad, each `realized += sellPrice(baselinePrice, current) − baselinePrice`; a player missing from the market adds 0.
This is what the honest client already does (`newPick` restores the baseline price), it closes the loophole in 2 without `max()`, and the Dart twin becomes identical: `realizedNowTenths` held = same id (drop "AND same price"). Update the Task 2 tests: replace "re-bought at a new price is a sale plus a buy" with "a baseline player at any client price is held at baseline" (`A@90` → price 80, realized 0; `A@10` → price 80, realized 0). Drop the "reprice race credits the higher price" test. Keep the snapshot rewrite (open question 3: yes): with held-at-baseline, storing the judged prices is what makes next week's baseline trustworthy. Invalid nodes stay verbatim.

**4. Add the race protection on the fan's side: an over-budget preview in the lifecycle sweep (new task, after Task 3).**
Every sweep, while the current gameweek is open, judge every saved squad with the next lock's inputs (`loadIntegrityInputs` + `judgeSquad`, both exist; the save trigger already does this for one uid). A squad that would be `overBudget` gets:
- `SquadAlerts/<uid>` = `{Gw, Kind: 'preview', Issues: ['overBudget'], CreatedAt}` (write only when it differs, `sameInvalidAlert` pattern; generalise `isInvalidAlert` to kinds `invalid|preview` so the save trigger clears it once a clean squad is saved);
- ONE push per uid per gameweek, claimed with `PreviewPushed/<gw>/<uid>` set-if-absent: title "Your fantasy team is over budget", body "This week's price changes put your team $1.0M over. Fix it before Sunday 3:00 PM or this week won't count." (amount and deadline from config/GwState).
Fan banner for Kind `preview` (parser `squadAlertFromNode` learns the kind): "Your team is $X over budget after this week's price changes. Fix it before the deadline or this week won't count." Bright red, both themes. Only `overBudget` triggers the push: it is the only issue an honest fan can drift into. This covers the Monday reprice, an owner price edit mid-week (which `max()` never covered), and any future price mover. Cost: ~50 reads per sweep for ~50 managers.

### Accept as written
- `Baselines/<uid>` as a server-written node, rather than the app re-deriving from the public `PublishedPicks`: yes. One baseline, Free Hit and Invalid handling in one place.
- Open question 2 (Team value line): leave it out.
- Rules shape (read own + admin, no client write), the cache guard, the spec §4 edit, History carrying `realizedTenths` in both branches, the full-fantasy deploy list.
- `chipEditingGameweek` ("first gameweek whose lock is ahead") is the right `editingGw`: it flips to gw+1 at the lock instant, the same moment the lock sweep writes `ForGw = gw+1`.

### Worth adding, owner's call
- **Recount transfers at the lock from the same diff** (~2 hours). Known gap from the hardening round: the rules allow saves while GwState is `locked`/`finalized` (Sunday ~3:15 PM until Monday 00:00), but `recordSquadSave` returns before counting unless the status is `open`, so a fan who saves then and never again pays no transfer points. Task 2's judge already computes `sold` against the baseline at the lock; `lockAccounting` can set `used = max(storedUsedThisGw, sold − freeSwaps)` (unlimited chips unchanged). Recommend yes: it closes the gap for good with code this plan already writes.
- **Addendum (owner question, 2026-11-03):** the uncounted-saves gap is REST-only. The fan app already treats the squad as locked from the Sunday 3 PM lock until Monday 3 PM (`currentGameweek` keeps the lock-day gameweek for 24 h and `squadEditable` is false while it is locked), so a normal fan cannot save in that window; only a direct database write can. Owner wants it shut at the database too. Add to the plan, before the recount: tighten `Squads/$uid` `.validate` in BOTH rules files so a client save is allowed only while `GwState/status` is 'open' and `now < lockAtUtc` (plus the existing 'open' lockOverride clause and the no-GwState case). Pin it in `rules_contract.test.ts`; LOCAL emulator probe: a save under status 'locked' and under 'finalized' is DENIED, under 'open' before the lock ALLOWED, under the 'open' override ALLOWED. The delete gate stays. Note the consequence: if the sweep is down past midnight nobody can save until it recovers (today they can, uncounted); the sweep already has backstops. Keep the lock-time recount as insurance; do both.
- Write into the plan as a known limitation: an Invalid week forfeits held prices the next week (every pick re-bought at the market floor; `realizedTenths` carries). Pre-existing behaviour, slightly harsher now. Acceptable.
- Task 7: add "the S15 fill tool still replays cleanly with `--clear`" (test-only tool; its replay budgets must not fight the new judge). Never `--apply`.

### Nits
- Task 6 copy, add one sentence: "Prices change on Monday morning. If a change puts your saved team over budget, you'll get a message so you can fix it before the deadline."
- Task 2 header comment: say plainly "held = baseline id, at the baseline price; the client's price for a held player is ignored."

---

## B. `2026-11-02-fantasy-cash-manager-only.md`

**Verdict:** approve as written, plus one addition.

- **Open question → yes.** Add "Paid in cash instead" on a pending Venmo/Zelle claim row (Task 4). Reuse the approve path with a method override: record `Via: 'cash'`, `AmountCents` from the amount dialog prefilled with the season price, claim resolved `approved`. Without it the owner must Reject, then find the fan under Pick users. One tap is the "automate first" answer.
- Checked: the fan app stores `Via` as plain text (`fantasy_access.dart` line 171), so a cash record still reads as active after Task 1 removes the fan-side cash method. Nothing to change there; Opus should not "fix" it.
- Task 2 probe: also confirm the `Access/$uid` rules carry no `Via` pattern that would reject an admin write of `cash` (I believe they don't; the probe settles it).
- Optional wording: `methodLabel('cash')` renders "paid $5.00 by cash". If the owner prefers, "cash in person" reads better in both the admin alert and the receipt; one string in `access.ts` and its Manager twin.

---

## Handoff
Switch back to Opus and say: "execute the selling plan and the cash plan with Fable's review" (this file). Opus should fold A.1–A.4 into the plan before dispatching Task 1 (edit the plan doc, commit), then run subagent-driven.
