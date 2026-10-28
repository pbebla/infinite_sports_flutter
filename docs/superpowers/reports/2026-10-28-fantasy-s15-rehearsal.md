# Infinite Fantasy — Season 15 dress rehearsal (read-only)

**Date:** 2026-10-28 · **Branch:** `zaya-fantasy` · **Tool:** `functions/tools/rehearse_s15.ts`
(`npm run rehearse:s15` from `functions/`) · **Data:** live public snapshot of Futsal Season 15,
taken 2026-10-28 15:42 UTC.

Nothing in this rehearsal was written to the real database. The tool only *reads* the
public season data, then replays the whole season inside the computer's memory.

---

## Part 1 — The short version (for the owner)

### Did the season score cleanly?

**Mostly yes. The scoring itself is right.** We replayed all 12 Season 15 match days
(33 games) through the real fantasy server code, exactly as it will run live: the
every-15-minute check, the "game is final" trigger, and the Monday price update.

- **Every player's points in every week matched** a separate from-scratch recount:
  588 out of 588.
- **Prices moved exactly as the rules say:** 217 price moves, all ±$0.5M, never below
  $4.0M or above $15.0M.
- **All 17 safety checks passed.** Leaderboards add up, ranks are right, ties share a
  rank, ownership % is always 0–100, every Team of the Week has 1 GK + 2 DEF + 2 ATT,
  and no broken values were written anywhere.
- **Re-scoring a week gives the same answer.** A score correction re-runs the week and
  produces the same numbers, even months later.

**But we found 2 real bugs and some messy Season 15 data:**

1. **Free Hit bug (real money-losing bug).** After a Free Hit week the app puts your old
   squad back, which is correct. But the next time you save anything, even just a
   captain change, the server counts that swap-back as transfers and can take points
   off you. Our test manager lost 8 points for 1 real transfer.
2. **"Sticky chip" problem (needs your decision).** If a manager plays Bench Boost or
   Triple Captain and never switches it off, the chip stays switched on. The server
   correctly blocks it for the rest of chip set 1, then **quietly uses it again** in the
   first week of set 2 (GW7). Our test manager got Bench Boost twice without asking.
3. **Messy Season 15 data that would give out wrong points** (details in Part 2):
   - The 7–0 game on Oct 5 has no goals or events recorded, which looks like a forfeit.
     It still gave 7 Nimrod players 9–12 points each, including all three bonus points.
   - Some names are misspelled or belong to people not on any team list.
   - Three players have the wrong position. One "goalkeeper" scored 11 goals at
     10 points each.
   - Saves were never logged as events in S15, so real goalkeepers score about zero.

### Top 5 players (season total, bonus included)

| # | Player | Pos | Team | Points | Price start → end |
|---|---|---|---|---|---|
| 1 | Demsin Bet varda | DEF | Ishtar | 331 | $15.0M → $15.0M (already at the max) |
| 2 | Bruno Siva | ATT | Nimrod | 243 | $15.0M → $15.0M (already at the max) |
| 3 | David Gewargis | DEF | Nimrod | 229 | $12.0M → $15.0M |
| 4 | Netibel Shamoon | ATT | Hakkari | 189 | $12.5M → $15.0M |
| 5 | Carlo Gewargis | ATT | Babylon | 135 | $10.0M → $11.5M |

### Team of the Week — three sample weeks

- **GW1 (Jun 29):** Daniel Youkhanna (GK) 16 · Demsin Bet varda (DEF) 32 · Raman Nissan (DEF) 23 ·
  Bruno Siva (ATT) 36 · Carlo Gewargis (ATT) 31
- **GW6 (Aug 10):** Anthony Memon (GK) 41 · David Gewargis (DEF) 38 · Demsin Bet varda (DEF) 33 ·
  Bruno Siva (ATT) 40 · Netibel Shamoon (ATT) 25
- **GW10 (Oct 5):** Anthony Memon (GK) 12 · Demsin Bet varda (DEF) 27 · Raman Nissan (DEF) 25 ·
  Netibel Shamoon (ATT) 20 · Ramsin Nissan (ATT) 13. All 12 of Anthony's points that week came
  from the 7–0 game with no events (see the forfeit finding).

All 12 weeks are listed in Part 2. One thing looks odd: in **GW12 the goalkeeper of the
week is Brandon Zaya with 0 points, but Babylon didn't play that week.** Every goalkeeper
who did play scored below zero, so the next-best 0 won.

### Biggest price movers (over the season)

| Up | | Down | |
|---|---|---|---|
| David Gewargis (DEF) | $12.0M → $15.0M | Hiram Alvarez (ATT) | $6.5M → $5.0M |
| Netibel Shamoon (ATT) | $12.5M → $15.0M | Ninos Sarkis (DEF) | $6.5M → $5.0M |
| Eli Derazizyan (ATT) | $9.0M → $11.0M | Konstantin Bertos (DEF) | $5.5M → $4.0M |
| Pedro Siva (DEF) | $8.5M → $10.5M | Ninos Rihan (ATT) | $6.0M → $4.5M |
| Raman Nissan (DEF) | $9.0M → $11.0M | Roben Tatari / Yosip Aprim (ATT) | $6.0M → $4.5M |

The top three players (Demsin, Bruno and GK Anthony Memon) started at the $15.0M maximum
and could not rise any further.

### The six test managers (made-up people, real players and prices)

| Rank | Manager | Points | What they tested | Result |
|---|---|---|---|---|
| 1 | Triple Tina | 697 | Triple Captain in GW3; tried it again in GW5 | ✅ GW3 tripled; the GW5 repeat was correctly blocked |
| 2 | Absent-Captain Ava | 576 | Captain's team had no game (GW11, GW12) | ✅ GW11 the vice-captain got the ×2; GW12 nobody played, 0 points |
| 3 | Steady Eddie | 565 | No transfers; a free bench/captain shuffle | ✅ shuffle cost nothing |
| 4 | Bench Boost Bob | 551 | Bench Boost in GW4, then never opened the app | ⚠️ Bench Boost fired **again** in GW7 (should be 544) |
| 5 | Free Hit Fiona | 451 | Free Hit in GW5, Wildcard in GW8 | ⚠️ charged −8 in GW6 for the squad being put back (should be 459) |
| 6 | Churn Charlie | 372 | Transfers every week; 3 transfers with only 2 free in GW3 | ✅ −4 charged exactly once; undoing a transfer before the deadline un-counted it |

### What I need from you

1. **Bug 1 (Free Hit):** OK to fix it? It's a small server change, and the test that proves
   it is already written.
2. **Sticky chips:** should a chip switch itself off after its week? (I recommend yes.) Or
   should managers have to switch it off themselves? There's a matching gap in the app: it
   still shows a used chip as "Active" and "1 left".
3. **Season 15 data clean-up** (only matters if S15 stays the test season, or for the S16
   price seeding):
   - the forfeit marker
   - the misspelled or unknown names
   - three positions to change in the Manager app

---

## Part 2 — Technical findings

### 2.1 How the rehearsal ran

| Item | Value |
|---|---|
| Snapshot (HTTP GET, no auth) | `Futsal/15/Date`, `Futsal/15/Line Ups`, `Futsal/15/Teams`, `Fantasy/Futsal/15/Config`, `Fantasy/Futsal/15/Players`, `Fantasy/Futsal/15/Voided` (null). **No path needed auth; none skipped.** Real `Squads`/`Managers` deliberately NOT read (private user data; synthetic managers used instead). |
| Config override | `lockOverride` `'open'` (live) → `'auto'` **in memory only** |
| Gameweeks | 12 (GW1 06/29 … GW12 10/19), lock Sunday 15:00 PT (22:00 UTC) |
| Simulated clock | 2025-06-26 22:00Z → 2025-10-22 22:00Z |
| Production entry points driven | `runLifecycleSweep` ×11,329 (every 15 min) · `maybeFinalizeGame` ×46 (33 game-finals + 12 next-day re-fires + 1 late GW1 correction) · `runMondayReprice` ×17 (every Monday 10:00 PT, incl. 5 no-op gap Mondays) · `recordSquadSave` ×32 (31 client saves + 1 server Free Hit restore write, which fires the same trigger in production) |
| Pipeline writes captured | 701, all in memory → `functions/tools/rehearsal_out/captured_writes.json` (gitignored, 1.1 MB, includes the final `Fantasy/Futsal/15` state) |
| Reads served | 126,936 |

**Production sequencing reproduced:**
- Every S15 game is already final in the snapshot, so the replay first sets each game's
  `status` to 0 in memory. It then sets each game back to its real status at a realistic
  final time (lock +1h37m, then one game per hour) and fires the per-game trigger. So
  finalize runs on the last game's trigger, after lock, as it would live.
- The sweep at the lock instant takes the `PublishedPicks` snapshot.
- The Monday reprice runs at 10:00 PT, before the next window opens at Monday 15:00 PT
  (lock + 24h). Client saves happen inside the open window at post-reprice prices. Kept
  picks keep their paid price, as in `squad_draft.dart`.

**How the in-memory database copies real RTDB (`OverlayDb`):**
- Storage never holds arrays, nulls or empty maps. Reads come back in RTDB's form:
  integer-keyed maps with maxKey < 2·count become null-padded arrays, and children come
  back key-ordered.
- `writeIfAbsent` is a set-if-null claim.
- Read results are deep-frozen, so the pipeline can't change stored data through a read.
- Writes made by the server itself to `Squads/<uid>` re-fire `recordSquadSave`, as the
  real trigger would.

**Safety proof:**
- A case-insensitive grep of `rehearse_s15.ts` for `\b(put|patch|post|delete)\b` finds
  **0** matches. The only `method:` values in the file are `'GET'`.
- No `firebase-admin` or `firebase-functions` import anywhere in the compiled closure.
- At runtime, a guard wraps `globalThis.fetch`. Any method other than GET, or any other
  host, throws. **After the snapshot loads, all network access throws.**
- The only network call in the imported pipeline is the Anthropic call in `news.ts`. It
  can't be reached here because the rehearsal passes no `deps` (no API key, no pusher).
- Live run: 6 GETs, 0 blocked attempts. The `--offline` re-run made 0 network requests.

### 2.2 Invariants — all PASS

| Invariant | Result |
|---|---|
| Each `History/<gw>/<uid>.TotalTenths` = Σ `Breakdown.countedTenths` − 10 × `TransferCosts/<gw>/<uid>` | PASS, checked after every scoring job and at the end |
| `Leaderboards/Gameweek/<gw>` points = trunc(TotalTenths/10) | PASS |
| `Leaderboards/Overall` points = Σ weekly whole points; `movement` = rank change vs the standings before the latest week | PASS |
| Ranks are 1-based, competition style (ties share) | PASS (both boards) |
| `ownershipPct` is an integer in 0..100 | PASS |
| `PlayerTotals.points` = Σ `PlayerWeeks` | PASS |
| `DreamTeam` has exactly 1 GK, 2 DEF, 2 ATT, all eligible, points = `PlayerWeeks`, and is the optimal pick | PASS (12/12 weeks) |
| `PriceChanges` deltas are ±5 tenths; every price write is an integer in 40..150, on the step, and exactly one step from the previous price | PASS (217 moves) |
| No NaN, Infinity or undefined; no invalid RTDB keys or path segments in any captured write | PASS (701 writes) |
| `PublishedPicks/<gw>` claimed exactly once; `Repriced/<gw>` written once | PASS |
| `GwState` only moves forward (open → locked → finalized → next open) | PASS |
| Every finalize used source `publishedPicks`; no crash or "season failed" log | PASS |

### 2.3 Cross-checks

| Cross-check | Result |
|---|---|
| **Player weeks.** All 49 market players × 12 gameweeks, recomputed independently: the pure engine `mapGameToStats` → `scorePlayerWeek`, plus a per-game `bpsScore` / `awardBonus` pool keyed by **team + name** | **588/588 match** |
| **Season total vs seed tool.** The `tool/seed_fantasy_logic.dart` `seasonPointsByPlayer` semantics reimplemented: every game node regardless of status or stage, full roster present, base points only, `futsalDefault()` config | **0 gaps beyond bonus.** Pipeline season total − bonus = seed aggregate for all 49 players. Same strays the seed reports: Barsin, Guest, Larsin, Own Goal, Pilers Aldo. |
| **Opening prices.** `buildOpeningPrices` re-run on that aggregate | **49/49 equal to the live market prices.** So the S15 market was priced from S15's own results ("hindsight pricing"). Expected from the seed tool; worth knowing when reading the price dynamics. |
| **Monday repricing.** Independent price ledger: engine `repriceDeltas` / `applyDelta` on the independent week points, week by week | 0 mismatches (per-week `PriceChanges` and final prices) |
| **Rerun idempotence.** Every rewrite of `History/<gw>`, `PlayerWeeks/<gw>`, `Leaderboards/Gameweek/<gw>`, `TransferCosts/<gw>`, `DreamTeam/<gw>` (ignoring `ComputedAt`) | 0 divergent rewrites |
| **Late GW1 correction re-run** at season end | History, both boards and PlayerTotals points unchanged. `ownershipPct` changed for 16 players (finding 2.5c). |
| **Manager ledger.** An independent spec ledger (free transfers, used, cost, chip-set rule, Free Hit return) vs the pipeline's `TransferState` / `TransferCosts` / `PublishedPicks` / `History` / `Overall` | **10 mismatches, all explained by Bugs 1 and 2 below** (Bob GW7; Fiona GW6 and its bank cascade) |

An emulator artifact was caught and fixed during the run. My first version re-inserted a
rewritten child key at the end of its map, so `PlayerWeeks` key order changed after each
reprice and 12 "divergent rewrites" appeared. Real RTDB returns children key-ordered;
after modeling that, comparing values gave 0 divergences. The pipeline was never at fault.

### 2.4 Bugs

#### Bug 1 — a transfer after a Free Hit is counted against the Free Hit squad (server, confirmed)

**Root cause:**
- `functions/src/lib/fantasy/orchestration.ts:262-263` (`recordSquadSave`) counts used
  transfers against `PublishedPicks/<gw-1>` (else `History/<gw-1>`).
- After a Free Hit week, `<gw-1>` is the Free Hit squad. But
  `settleTransfersAfterFinalize` (`orchestration.ts:186-215`; the restore is the write at
  `:205`) has already put the manager's previous squad back into `Squads/<uid>`.
- So any save in the following week counts the restored players as "bought". That
  includes an armband-only change.
- `lockAccounting` then charges that inflated `UsedThisGw`, and the rollover drains the
  bank.

**Rehearsal evidence (Free Hit Fiona):**

| GW | Field | Pipeline | Expected |
|---|---|---|---|
| GW6 (1 real transfer, Yousif Audisho → Polus Gorgees) | `UsedThisGw` | 6 | 1 |
| GW6 | `TransferCosts` | 8 | 0 |
| GW6 | Week score | 32 | 40 |
| Free transfers at GW7 / GW8 / GW9 locks (cascade) | `Free` | 2 / 4 / 6 | 5 / 7 / 7 |
| Season | Overall | 451 | 459 |

**Minimal repro:** `functions/src/lib/fantasy/rehearsal_findings.test.ts` (new, marked
`it.fails` with "KNOWN BUG").
- Setup: world2 plus a GW3 date. churn plays Free Hit in GW2, GW2 finalizes and its squad
  is restored, then GW3 opens.
- An armband-only save gives `UsedThisGw` **2** (expected 0).
- One transfer gives **3** (expected 1).
- I checked that the two cases fail with exactly those values when run as plain `it`. A
  plain `it` setup test guards the scenario itself.
- The suite stays green (513/513). **Flip `it.fails` → `it` once fixed.**

**Suggested fix (not applied):** in `recordSquadSave`, when the gw-1 locked squad's
`chip == 'freeHit'`, count against `PublishedPicks/<gw-2>` ?? `History/<gw-2>`, which is
the squad the restore wrote back. The app never counts transfers itself, so the fix is
server-only.

#### Bug 2 — a played chip stays on `Squads/<uid>` and re-fires in the next chip set (contract gap, needs a decision)

**Root cause:**
- Nothing ever clears `chip` on the live squad after its week.
  - The app adopts the saved chip (`lib/fantasy/hub/squad_draft.dart:85`,
    `_chip = squad?.chip`).
  - `usedChips` is not wired (`lib/fantasy/hub/chip_row.dart:42-46`), so a spent chip
    still shows "1 left" / "Active".
  - The server only strips the chip on the Free Hit restore (`orchestration.ts:194-205`).
- At each later lock, `lockAccounting` (`transfer_state.ts:179-192`) /
  `shouldVoidChip` (`transfer_state.ts:116-130`) voids the repeat only **within the same
  set**.
- So the leftover chip is voided (with a warn log) every week until GW6. At the first
  set-2 lock it is **honored again**.

**Rehearsal evidence (Bench Boost Bob, no app activity after GW4):**
- The voided-chip warning was logged at the GW5, GW6, and GW8–GW12 locks.
- Bench Boost was honored again at GW7: 740 tenths vs the intended 675 (74 vs 67 points).
- Overall 551 vs 544.

**No test was added on purpose.** The existing `transfers_orchestration.test.ts`
"the same chip is honored again in set 2" pins a *deliberate* set-2 replay, and the
server can't tell deliberate from leftover. Fixing this is a product decision.

**Recommended:** at rollover (`settleTransfersAfterFinalize`), strip `chip` from
`Squads/<uid>` for every manager whose locked squad carried one, whether it was honored
or voided. A set-2 replay then needs a fresh tap. Also wire `usedChips` in the app.

### 2.5 Other pipeline observations (not invariant failures)

**a. Team of the Week can show a player who didn't play.** `pickDreamTeam`
(`finalize_core.ts:226`) ranks every eligible player, and a non-player counts as 0.

- GW12: Brandon Zaya (Babylon, no game) is "GK of the week" with 0 points, because every
  GK who played scored below zero.
- GW4: the GK of the week also has 0 points (he did play).
- Suggestion: filter to `played` (and probably points > 0), and allow an empty slot.

**b. Duplicate names in one game share one bonus-pool entry.** Finalize merges both
teams' stats with `Object.assign` (`finalize_core.ts:261`), so a name that appears on
**both** sides of one game keeps only team2's entry in the bonus pool.

- 'Guest' was on both sides in 5 S15 games (07/20#2, 08/03#1, 09/07#2, 09/14#2, 09/21#1).
- My recount keeps both guests (keyed by team), and it changed **no** market player's
  bonus this season. So this is latent, not a live error.
- Real-name collisions across teams: none in S15.

**c. Stale ownership after an old-week re-run.** `ownershipPct` is computed from the
re-run week's squads (`finalize_core.ts:330`, `:377`). Finalize then writes the whole
`PlayerTotals` node (`orchestration.ts:457`).

- Re-running GW1 at season end (a late score correction) reset 16 players' ownership to
  GW1 values. Example: Christian Lachinpour 50% → 33%, Netibel Shamoon 17% → 33%.
- Points are unaffected.
- Suggestion: take ownership from the latest finalized week, or only write
  `ownershipPct` when gw is the latest.

**d. Not exercised, from reading the code only.** `recordSquadSave` gates on the stored
`GwState` (`orchestration.ts:247`), not on the schedule. The sweep flips `GwState` to the
new week on its first run at or after Monday 15:00 PT.

- A save made in the seconds before that sweep lands is not counted.
- If that is the manager's only save that week, the transfers are free.
- Low risk, but if the sweep fails the window widens.
- Deriving the current week from the schedule in `recordSquadSave` would close it.

**e. Any write to a final game re-runs the whole finalize.** The trigger watches the
whole game node, so any write to a final game (for example `team1vote`/`team2vote` or
`link`) re-runs finalize.

- Re-runs were verified idempotent.
- Each one rewrites PlayerWeeks, History, both boards, the 49-row PlayerTotals and the
  DreamTeam.

**f. Not exercised here:** pushes (no pusher injected, so no `RecapSent`/`ReminderSent`
claims) and AI news (no key). The Team of the Week news drafts *were* written
(`News/Drafts/gw<n>dreamteam`, 12 of them, no `AutoPublishAt` since auto-publish
defaults off).

### 2.6 Data-quality findings (real S15 data)

Clean:
- All 33 games have `status` 2 and numeric `team1score`/`team2score`.
- No friendlies, no attendance nodes.
- No duplicate names across teams.
- The `Teams` standings table matches the results exactly.
- Goal events match the scoreboard in every game except the forfeit.

**Would mis-score:**

1. **Probable forfeit, 10/05 #0: Nimrod 7–0 Nineveh, with zero activity events.**
   - Every rostered player defaults to present, so each Nimrod player gets an appearance
     point plus a clean sheet: GK 9, DEF 6, ATT 3 base.
   - All 7 tie on BPS 5 (clean-sheet weight only), so **all 7 get the full +3 bonus**:
     21 bonus points from one game.
   - Anthony Memon and Jose Ramirez make 12 points each.
   - Nineveh's 8 rostered players each get +1 appearance; their GK/DEFs get −2.
   - **Fix:** add a forfeit marker (or Stage) that fantasy excludes. At minimum, award no
     bonus in a game with no events.
2. **Activity names not in the acting team's roster:**

   | Name | Recorded for | Events | Games | Impact |
   |---|---|---|---|---|
   | Netibel Shamoon | Nineveh (he's Hakkari) | 1 Assist | 06/29 #1 | +4 pts in GW1 for a game his team didn't play (extra appearance + assist) |
   | Pilers Aldo | Nineveh | 1 G, 1 A, 3 Y, 1 R, 3 fouls | 08/03 #0, 08/10 #0 | unrostered, so never a market player; points lost or untracked |
   | Barsin / Larsin | Ashur | 1 Goal each, both at 14' | 07/13 #0 | likely typos (maybe "Ramsin"?): owner to confirm |
   | Own Goal | Hakkari ×3, Ishtar, Ashur | 5 "Goal" events | — | own goals are logged as a goal by the pseudo-player "Own Goal". The real culprit never gets the −2 penalty, and the pseudo-player sits in the bonus pool with 12 BPS (it won no bonus this season). |
   | Guest | all 6 teams | 36 G, 2 A, 23 fouls, 3 Y | 24 game-sides | by design (spec §3), but guests took **4 bonus slots** (08/03 #1, 08/10 #1, 09/14 #2, 09/21 #2) |

3. **Line Ups totals vs activity log disagree for 12 players.** The worst is **Brayan Elie:
   Line Ups 5 goals vs 14 goal events**. Fantasy follows the events, which is +36 points if
   the events are wrong. The other 11 are off by 1–2 goals or assists.
4. **Positions** (the registration's first-listed position):

   | Player | Fantasy position | Evidence |
   |---|---|---|
   | Anthony Memon (Nimrod) | GK | 11 goals × 10 = 110 points (66 as DEF), GK of the week 7 of 12 weeks |
   | Daniel Youkhanna (Ishtar) | GK | 3 goals |
   | Tony Guevar (Ishtar) | ATT | lineup number "GK", 181 saves: he looks like Ishtar's real keeper |

   Also worth a glance: top scorers Demsin Bet varda (44 goals) and David Gewargis
   (25 goals) are DEF, which earns 6 per goal vs 4 for ATT.
5. **No Save, PenSaved, PenMissed, OwnGoal, DPL, SecondYellow or Substitution events
   exist in S15.** The only types are Goal, Assist, Foul, Yellow and Red. Line Ups carry
   save totals (Brandon Zaya 192, Christian Lachinpour 171), but none were ever logged as
   events. So:
   - GK save points and the save, DPL and penalty weights in the bonus formula never fire.
   - Real keepers score about zero or negative each week.
   - S16 will need save and attendance capture for GK scoring to mean anything.
6. **Bonus "floods".** In 7 games, ties gave more than 3 players a bonus (the FPL tie rule
   as designed). The forfeit above is the extreme case.

### 2.7 Recommended fixes (priority order)

1. **Bug 1 (Free Hit counting).** Change the server baseline as described in 2.4, then
   flip the two `it.fails` tests in `rehearsal_findings.test.ts` to `it`.
2. **Bug 2 (sticky chips).** Owner decision. Then clear the chip at rollover and wire
   `usedChips` in the app.
3. **Forfeits.** Add a marker and exclude forfeits from fantasy (or skip the bonus for
   no-event games).
4. **Team of the Week.** Only include players who played.
5. **Ownership.** Take `ownershipPct` from the latest finalized week only.
6. **Data clean-up in the Manager app:**
   - names: Barsin/Larsin, Pilers Aldo, Netibel's Nineveh assist
   - Brayan Elie's goal count
   - positions: Memon, Youkhanna, Guevar
   - own goals logged as an OwnGoal event against the real player

   Caveat on positions: the spec revision committed today (`3a5ae2a`) freezes each
   week's positions at lock. The pipeline tested here does **not** do that yet. Finalize
   reads the live `Players` positions on every run (`orchestration.ts:346`), so changing
   a position and then re-running an old week would re-score that week at the new
   position. That snapshot step should land before position fixes are made mid-season.
7. **S16 readiness.** Log Save, DPL and attendance events in live scoring.
8. **Optional:**
   - derive the open week from the schedule in `recordSquadSave` (2.5d)
   - debounce finalize re-runs on non-scoring game writes (2.5e)

### 2.8 Reproduce

```
cd functions
npm run rehearse:s15              # live public GET snapshot (cached), then the replay
npm run rehearse:s15 -- --offline # replay from tools/rehearsal_out/snapshot.json only
```

Outputs (all gitignored, under `functions/tools/rehearsal_out/`):
- `captured_writes.json`: every pipeline write in order, with the job that made it; the
  simulated client and live-scoring inputs; logs; the final in-memory state.
- `summary.json`: every check, cross-check and data-quality list.
- `report_tables.md`: full top-10, all 12 Teams of the Week, movers, and the managers'
  week-by-week table.
- `snapshot.json`: the GET snapshot.

Note: `firebase.json` has no `functions.ignore`. Delete `tools/rehearsal_out/` (or add an
ignore) before a deploy so the 1 MB+ outputs aren't uploaded with the functions source.
