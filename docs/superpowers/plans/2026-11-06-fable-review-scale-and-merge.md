# Fable review — Fantasy scale fixes + duplicate-account merge (2026-11-06)

**Reviewed:** `docs/superpowers/plans/2026-11-06-fantasy-scale-fixes.md` (fan d287dc7) and `docs/superpowers/plans/2026-11-06-merge-duplicate-accounts.md` (fan 3a3dac5 + a60c977, plus D10 added today at the owner's request).
**Reviewer:** Fable 5.1, at the owner's request, after both plans were written by Opus 5.5.
**Verdict:** **Approve both, with 2 must-fixes each.** Neither must-fix changes what gets built; they make the scale fix simpler and more robust, close one gap in the same bug class, and give the merge the two safety pieces the people being merged will actually notice. Fold them in before executing. Nothing below needs an owner decision except where marked.

## How I checked

I re-read both plans cold and then read the code each claim rests on: the sweep and reprice entry points (`functions/src/lib/fantasy/orchestration.ts:2867-2890, 2996-3020`), every whole-node `History`/`PublishedPicks`/`Squads` read in the engine (lines 514, 614, 1175, 1211, 1618-1619, 1842, 2469, 2482, 2650, 2765, 2843, 2928, 3015; `schedule_rewind.ts:196, 302, 387, 512`; `badges.ts:678-693`), the admin SDK's query surface (`@firebase/database-types`: `limitToFirst`, `Query.get()`), the fan squad viewer's feeds (`manager_squad_viewer.dart:244-262, 369-392`; `fantasy_service.dart:708-723`), the public-profile mirror (`public_mirrors.ts:29-59`, `public_mirrors_watch.ts:36-55`), the Manager's link/Played writes (`lineup_service.dart:205-235`, `firebase_paths.dart:214`), the fan app's sign-in profile bootstrap (`main.dart:194-232`), and the local merge audit output (`scratchpad/prices/merge_audit.json` — uids and node names only). I also re-ran the local load-test harness to confirm the numbers in the plan's Design table.

---

# Plan 1 — Fantasy scale fixes

## Must-fixes

### M1. Use the database's own "first child only" query for the week checks; keep REST shallow for season discovery only

The plan routes every "is week N scored yet?" check (the biggest per-sweep cost in the test) through a new REST `?shallow=true` call: an OAuth token, a timeout, two result shapes, and a full-read fallback — on the hot path, several times per sweep per season.

The admin SDK already has a cheaper, native answer: `ref(path).orderByKey().limitToFirst(1).get()` returns at most **one** manager's row (~1 KB) over the connection the engine already holds, and `snapshot.exists()` is the answer. No token, no timeout handling, no fallback needed, and the list-coerced-array case doesn't exist (a query result is always a snapshot).

**Fix.**
- Add `exists(path: string): Promise<boolean>` to `FantasyDb` as a **required** member (three implementations: `rtdbFantasyDb`, `FakeDb`, the rehearsal's `OverlayDb` — FakeDb/OverlayDb implement it as read-and-check so the replay stays exact). Production: `root.child(path).orderByKey().limitToFirst(1).get()` → `.exists()`.
- Every D3 site (`orchestration.ts:1618, 1619, 2469, 2650, 2765`; `schedule_rewind.ts:196, 302, 387, 512`) becomes `await db.exists(...)` **at the same position in its function** — several are race guards and must stay fresh. The backstop loop does one `exists` per lock-passed week (≤ 12 tiny reads a sweep at season end). Drop `historyWeeks`/`publishedWeeks`.
- Keep `childKeys` (optional member) + `childKeysOf` with the full-read fallback **only** for D2 season discovery — 1 + #sports calls per sweep. Review Focus 1 and 2 now apply to that call only. Review Focus 3 ("week finalized in the same sweep") resolves by construction and its test stays.
- Tests: FakeDb gains the `reads` log as planned; assert the sweep's read log never contains a bare `<root>/History/<n>` or `<root>/PublishedPicks/<n>` path, and that `exists` is called with those paths instead.

### M2. Same bug class, missed: the daily reprice reads every season's whole `History`

`runMondayReprice` (`orchestration.ts:3015`) reads `<root>/History` whole just to find the largest finalized week number — 6 runs a day, for every season on `auto`, forever. At 250 managers that is 3.7 MB × 6 × seasons per day; it is the same defect the plan fixes in the sweep.

**Fix.** The latest scored week is already recorded in a node a few hundred bytes long: `LockedWeeks/<n>` carries `Scored: true` once finalize's `markWeekScored` lands (`orchestration.ts:58-86` header). Read `LockedWeeks`, take the largest `n` with `Scored === true`; only when no entry is scored (a season locked before the ledger existed) fall back to `childKeysOf(<root>/History)` and take the max key. Test: the reprice's read log never contains a bare `<root>/History`.

For Opus, so no one chases them: the remaining whole-node reads are once-per-week and need the contents — finalize (`:1175`, cumulative totals), the lock snapshot (`:2482`), `liveBaseFor` (`:1842`, once per week when `LiveBase/<gw>` is absent), `publishSaleBaselines` (`:514`), and `settleSeasonBadges` when it actually settles. Leave them.

## Should-fixes

### S1. A finished season should stand down by itself

Today the only thing stopping a finished season from running the full sweep forever is the owner remembering to flip it off `auto` ("never flip S15 to auto" lives in a memory file, not in code). The owner's standing rule is automate-first. Add an early return in `sweepSeason`, after the lockOverride/TestFill stand-downs: when `<Sport>/<S>/Finished === true` **and** `SeasonBadgesSettledAt` (D4) is present **and** no `LockedWeeks/<n>` carries a `Finalizing` or `Rewinding` stamp, run only 0b (scheduled messages — already before this point), 2b (news auto-publish) and 2d (lost-settle heal, one small `Live/Meta` read — needed because the badge marker can land in the sweep before the heal's margin passes), log `fantasy sweep: season over — standing down` at info, and return. This also removes the per-sweep league `Date` read (~85 KB a sweep at S15 size) for finished seasons, which the plan deferred in D6.

### S2. Step 3c reads every saved squad every sweep while the week is open

`previewOverBudget` (`orchestration.ts:614`) reads `Squads` whole each sweep to warn managers whose saved squad went over budget after a price move. Prices move only at the reprice (weekly) or an owner edit; over-budget saves are refused client-side, so a fresh save never needs this pass. Gate the pass: compute a stable fingerprint of `Players/*/priceTenths` (Players is ~9 KB and already needed by `loadIntegrityInputs`), store `SquadAlertsCheck = {gw, pricesHash}` after each full pass, and run the full pass only when the fingerprint changed **or** any preview alert is standing in `SquadAlerts` (so a manager who fixes their squad gets the alert cleared). If Opus prefers to defer this to D6, record why — at 1,000 managers it is ~60 MB/day, at the real league size it is small.

### S3. Fan viewer: one per-week History listener, not two

With D5, each `History/<gw>/<uid>` node gets two listeners in the squad sheet: the new per-week history feed (the squad) and the existing `_syncSettledWeeks` (`manager_squad_viewer.dart:369-392`, the week's points). The SDK dedups the wire subscription, so no extra download — but the node is parsed twice and two subscription sets must stay in step. Prefer one per-week History feed that yields both (`FantasySquad` + `HistoryWeek`, parsed once) and drop `_settledSubs`; if both are kept, say so in a comment so the next reader doesn't "fix" it.

### S4. Load-test harness hygiene (Task 6)

- Extract `saveSpacingMs(count)` as a pure function and unit-test that it returns exactly 3 minutes for every count ≤ 480 — that is the proof the S15 fill output is unchanged, instead of a manual byte-size diff.
- Give load-test managers their own uid prefix (`load-0001`…) rather than `test-NNN`: `FAKE_UID_PATTERN` is `^test-\d{2}$` and sits in the fill tool's write allowlist. The load test never writes, but a 4-digit `test-` uid invites someone to widen that pattern later.

## Minor

- D1's emulator branch: with the legacy database URL (`infinite-sports-app.firebaseio.com`) the emulator namespace is `ns=infinite-sports-app`; read it from `databaseURL`, not from the project id.
- Review Focus 2 (list-coerced arrays) still matters for `childKeys` on `Fantasy/<sport>`: season keys `15`, `16` can list-coerce. Keep the test.

---

# Plan 2 — Merge duplicate player accounts

## Must-fixes

### M1. The person's own phone: a "this account was merged" notice, not a dead login

After `--apply`, anyone still auto-signed-in on an **old** account sees a profile with its seasons gone, and once D7 disables the login they get a bare sign-in failure with no explanation. That is the only part of this merge a player will actually experience.

**Fix (new Task 2b, fan app).** The app shell watches `Users/<me>/MergedInto` (an `onValue` stream, never `get()`); when it is a non-empty string, show one plain dialog — *"This account was merged into your other Infinite Sports account. Please sign in with your other email."* — then sign out (clearing auto sign-in). Light and dark; a widget test with a fake stream. Ships with Task 1 and must be on phones **before** `--apply`. D7 (disabling the old login) then becomes the backstop for phones that never updated, not the user experience.

### M2. A hard guard: never relink a roster row in a fantasy-enabled season

The plan says "no trigger that moves money or referral credit fires", which the audit supports — but the trigger that *does* listen on `Line Ups` writes is `onLineupsWritten` (`fantasy_roster.ts`), and it only stands down for a season **without** a fantasy `Config`. Every planned relink is in such a season (Futsal S9–S14, the two S10 name rows, the AFC rosters); the S15 rows are untouched because for all five S15 players the kept account *is* the S15 account. Make that a rule the tool enforces, not a fact we happen to know: `assertMergePaths` refuses any `Line Ups` relink in a season where `Fantasy/<sport>/<season>/Config` exists (snapshot it in the dry run), and a Review Focus line + test pins it. A future merge that must touch a fantasy season becomes a deliberate extension with its own review.

## Should-fixes

### S1. Leave `Users/<old>/Played` in place

D4 removes the old account's `Played` index. With D5 (the mirror drops merged accounts) and M1 (the person is signed out), nothing reads it any more. Leaving it means the old record changes by exactly two stamps, the backup is smaller, the undo is two deletes, and one fewer trigger firing per account. If Opus keeps the removal, say why in the plan.

### S2. Make the first cluster a canary for the mirror change

Review Focus 4 only *warns* if an old account is still in `PublicProfiles` after stamping. Turn it into a check: stamp the first old account, wait ~90 s, verify `PublicProfiles/<old>` is gone; if it is still there the Task 1 deploy is not live — stop before the other clusters and print the `--undo` command. One extra minute, and a real guarantee instead of a warning.

### S3. Season 16 will create new duplicates unless the roster build checks first

I checked the local Futsal-16 submissions by name: only Carlo has registered so far, on his kept account. But people make a new login most seasons, and "Build lineup from sign-ups" links whatever uid the submission carries. Add to the S16 runbook (Task 6): before building rosters from sign-ups, re-run the duplicate check against the S16 submissions (the scratchpad audit script, names only) and merge first. The durable fix is the deferred Manager "find likely duplicates" screen — keep it deferred, but it is now the obvious next Manager feature after S16 starts.

## Owner decision folded in today

**D10** (added to the plan): Robert Shamoeilzadeh's kept profile first name "Rabert" → "Robert", one `First Name` leaf in that cluster's allowlist; the mirror follows automatically; roster keys are never renamed.

## Minor

- `Users/<keep>/Played/<Sport>/Season <S>` shape confirmed against `firebase_paths.dart:214` (the Manager's own writer) — the plan's D2 is exact.
- Task 1: treating `MergedInto: ""` as not merged is right; keep the projection pure.
- For the separate, still-pending price apply: the uid written into S15 `Players` for any merged person must be the **kept** uid. It already is for every S15 player in the clusters (kept = S15 account), so this is an assertion, not a change.
- Task 4 Step 4 (production dry run, read-only, fill-tool pattern) is fine to run before the owner's go — it writes nothing.

---

## Order of work after folding in

1. Scale plan (server + fan), full test runs, local load test with `wholeFantasyReads: 0`.
2. Merge plan Tasks 1–5 (code + tool), the emulator rehearsal, the production **dry run** only.
3. Everything waits on the owner's final review before deploy; `--apply` and `--disable-old-logins` each wait for a separate explicit go.
