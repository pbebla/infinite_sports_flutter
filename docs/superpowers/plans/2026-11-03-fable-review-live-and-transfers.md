# Fable review — "Transfers in the app" and "Live everywhere" (2026-11-03)

Reviewed: `2026-11-03-fantasy-transfers-in-app.md`, `2026-11-03-fantasy-live-everywhere.md` and its spec `specs/2026-11-03-fantasy-live-design.md`, against the engine code they change (`transfer_state.ts`, `orchestration.ts`, `finalize_core.ts`, `squad_week.ts`, the two rules files, `chip_row.dart`, `squad_builder.dart`) and the Manager's game writes.

**Verdict:** both plans are sound and should be built, transfers first. Fold in the must-fixes below before execution; the suggestions are the owner's call. Nothing here changes the owner's two decisions (week 2 = 2 free transfers; live numbers everywhere, prices still Monday-only).

---

## Plan 1 — Transfers in the app

### Must-fix

**T1. Delete the "deleted and rebuilt" claim in D1; it contradicts D1's own rule.**
D1 defines a first week as "no effective squad after the previous week" (`effectiveSquadAfterWeek(gw − 1)` is null). A manager who deletes and rebuilds mid-week still has a locked squad from last week, so the rebuild counts as up to 7 transfers against it. That is the **right** behaviour (otherwise "delete, then rebuild" would be a free-transfer reset), but the plan text says the opposite. Remove the claim and pin the real behaviour with a test in Task 1: delete-and-rebuild in an open week → `UsedThisGw` = picks not in last week's locked squad.

**T2. The rollover only runs for managers scored this week, so `CountFrom` goes stale for anyone who sat out a week — and the app would say "Transfer count updating…" for the whole week they rebuild.**
`settleTransfersAfterFinalize` is called with `Object.keys(out.historyByUid)` (`orchestration.ts:1164`). Fix in Task 1: roll over every uid in `TransferState` ∪ `historyByUid`. For a manager not scored this week: `countFrom` = the ids of `effectiveSquadAfterWeek(gw)` (null when he had no locked squad → `CountFromGw` alone → the app reads it as a first team), `Free` rolls as usual (a team banks even when it sits out, as in FPL), `firstWeek` as D1 defines it. Add the test: GW1 scored, GW2 skipped (squad deleted), GW3 rebuild → the app preview says first team and the server counts 0, and both agree.
Consequence to record (not close): sitting out a week resets transfers, at the price of a zero-point week. Never worth doing (at most 20 points saved for ~40 lost), so leave it; ledger it as a ruling.

**T3. Define Save while the preview is `notReady`, and pre-feature nodes.**
- `notReady` (stale `CountFromGw`, e.g. Monday 3 PM to a late finalize): **Save proceeds, no confirm**, the line says "Transfer count updating…". A miscount only costs points at the lock; it never zeroes a week, unlike money, so blocking is wrong here. Say this in Task 3's rules and test it in Task 4.
- A node with no `CountFromGw` at all (every node written before this ships, including the S15 fill): **hide the line**, don't say "updating". Otherwise the owner sees "updating…" forever on the emulator.
- Add to Task 5: re-fill S15 after Task 1 (owner OK for `--clear` + `--apply`, as before) so the transfers line is visible on the test season.

### Agreed as written
D2 (count against a server-published baseline, not the selling baseline), D3 (confirm only when the cost rises), D4 (chips stay drafts until the deadline, confirm on arming), D5 (first-team guard), D6 (chip regex). The copy is good. The `rehearse_s15.ts` ledger change (Task 1 Step 4) is the right regression net.

### Small
- Task 1 adds 2–4 reads per manager to the rollover (`effectiveSquadAfterWeek` twice). Fine at 200 managers; note it.
- `chip_usage.dart` already treats any chip string, so "Used" for wildcard/freeHit works without change; the implementer should still add the two ids to its test.

---

## Plan 2 — Live everywhere

The core is right: the server computes once from the finalize engine's own stages, phones overlay, and a contract test pins live == finalize at full time. D1–D7 all agreed, including the tint-not-slide choice (D6: a lazy list with a pinned own-row is the wrong place for sliding rows).

### Must-fix

**L1. Drop the settled *mirror* (`liveFromFinalize`); keep `settled` as a tombstone only.**
Why: (a) a mirror goes stale the moment the owner edits the Team of the Week in the Manager (admin edit, `Auto` removed — finalize never rewrites it), and any future admin override has the same trap; (b) it triples the surface (Task 2 `liveFromFinalize`, Task 3 settle rewrite, Task 4 overlay-when-settled) to prevent a flash that does not happen: finalize writes every official node several steps before it settles `Live`, and a phone receives updates on one connection in server order, so it moves from live numbers to official ones with no gap; a phone opening later has only official nodes.
Replace with:
- Finalize, after all official writes: transaction on `Live` → when `cur` is null or `cur.Meta.Gw ≤ gw`, replace the whole node with `{ Meta: { Gw, State: 'settled', UpdatedAt } }`; otherwise leave it. Then remove `LiveBase`.
- Live run: abort on `settled` (already there) **and** stand down before any heavy read when `History/<gw>` exists, so a score correction after settle can never resurrect LIVE. Keep the `ReadAt` guard.
- Client: `liveAppliesTo = meta?.gw == week && meta.state == live`; one function, not two. Anything else → official nodes. Remove Review Focus 5 (keep the 2-second reveal-gate wait for the live feed; that is the only thing it needs).
- Task 2 loses `liveFromFinalize`; the contract test compares `computeLiveWeek` (all games Final, no pending) directly to finalize's `gameweekBoard`, `overallBoard`, `playerTotals`, `playerWeekStats`, `dreamTeam.Players` and History `TotalTenths`/`Breakdown`, as the plan first listed them.

**L2. The trigger must diff before/after on the fantasy-relevant keys and return with zero reads when nothing relevant changed.**
The Manager writes more than scores to a live game node: `Clock` at kickoff/pause/resume (`FirebasePaths.gameClock`, not per second — I checked), undo bookkeeping, livestream links, resultApplied claims. Each would otherwise cost a full recompute. Compare exactly the keys the mapper reads: `team1`, `team2`, `team{n}activity`, `team{n}score`/`team{n}Score`, `team{n}attendance`, `team{n}keepers`, `forfeitedBy`, `status`. Test: a `Clock` write → no reads, no write.

**L3. Pin the `St` priority; today's text makes an absent player in a live game "live".**
Order: present (not marked absent) in a status-1 game → `live`; else his team still has a status-0 game and he has not played → `pending`; else played → `done`; else `out`. Test each.

**L4. Void mid-day: after removing `LiveBase`, call `refreshLiveWeek` for the live gameweek with `eventAtMs = now`.**
Otherwise phones keep the pre-void numbers until the next game write or the 15-minute sweep.

**L5. Add `Live` to the fill tool's `EXPECTED_NODES` (+ the shape test), as Task 9a did for `Baselines`.**
The S15 replay runs finalize, which now writes the `Live` tombstone; without the allowlist entry the fill tool refuses ("the replay produced Live…"). `LiveBase` removal is a no-op there.

### Suggestions (owner's call)

**S1. Market re-sort under the thumb.** The plan re-sorts the Players list live. A list that reshuffles while someone is scrolling reads as a glitch, and it is the one "live" effect that can. Recommended: numbers update in place at once; the order changes only when the list is at the top or on re-open, with a small "Order changed — tap to refresh" pill otherwise. The owner asked for placement changing live everywhere, so this is his decision.

**S2. Match tab vs My Team can differ for the same player.** The match tab shows raw per-game points; My Team shows counted points with provisional bonus and captain/bench rules. Add to the match tab's existing footnote: "Bonus, captain and bench counting show on My Team." Cheap, avoids support questions.

**S3. A demo the owner can watch before Season 16.** S15 is a test fill, so the engine stands down there and the owner sees nothing live on the emulator. One small addition: a `--dart-define=RTDB_EMULATOR=1` switch in the fan app that points `FirebaseDatabase` at the local emulator, so Opus can run the real app against the Task 3 rehearsal and record it (or let the owner drive it). Worth one task.

**S4. Cost, for the record.** Per relevant game write: ~10 reads (`PublishedPicks` ≈ 150 KB at 200 managers, `Players`, `Line Ups`, the date, `LiveBase`) and one transaction on a ~60 KB node. A match day is ~150 relevant writes → ~25 MB of reads. Fine on the Blaze plan; the first event of the day will lag 3–5 s (cold start), later ones 1–3 s.

### Questions for the owner
1. S1 — reshuffle the Players list live even while you're scrolling it, or keep the order steady and offer a "refresh" pill?
2. S3 — want the demo build so you can watch live points on the emulator before Season 16?

### Order
Transfers plan first (must be live before Season 16's first rollover), then Live. Both touch `squad_builder.dart`, `fantasy_service.dart` and `fantasy_session.dart`; sequential execution avoids the merge.
