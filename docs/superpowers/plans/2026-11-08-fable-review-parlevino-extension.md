# Fable review — Merge extension for Parlevino Tamraz (2026-11-08)

**Reviewed:** `docs/superpowers/plans/2026-11-08-merge-parlevino-extension.md` (fan 0a6dd7d), written by Opus 5.5 after the owner's decision "merge his info into the new email, bring everything".
**Reviewer:** Fable 5.1, at the owner's request.
**Verdict:** **Approve with 3 must-fixes.** The shape is right — a second batch with its own map, the existing tool doing everything it already does, and two narrow extensions for the two things it refuses. All three must-fixes are defects in the plan text, not in the idea; fold them in before executing. One owner question at the end.

## How I checked

I read the plan cold, then the code each extension leans on: the roster trigger (`functions/src/fantasy_roster.ts:30-46` — it calls `maybeSyncRoster` unconditionally; the stand-downs live inside the sync), the add-to-market branch of the sync (`functions/src/lib/fantasy/roster_sync.ts:140-195`), the merge tool's remove rule (`merge_accounts_logic.ts:720` — "a merge never removes data") and its `--map` flag (`merge_accounts.ts:103, 1522-1555` — already exists), the Manager's sign-up writer (`sign_up_service.dart:36-47` — the record's value is the player's **name**; its comments join by name, `user_service.dart:98,112`), and the fan app's sign-up reads (`utility.dart:893-940` — status/due/info nodes only, never per-season records). Findings M1–M3 are confirmed against that code.

## Must-fixes

### M1. Drop E1(b). Only the test season qualifies, and the apply must run before the S15 fill is cleared

E1(b) says a relink in a Finished, paused fantasy season is safe because the roster trigger "only sets teamName when it differs". That is true for a player already in the market — but the trigger syncs the **whole team**, and any roster name on Ishtar that is not in the S15 market joins it at the position-average price, with carry-over, photo and sign-up-position reads (`roster_sync.ts:152-195`). Nothing in the plan checks that every Ishtar name is already in the market, so (b) can write fantasy data the plan promises it won't.

(a) is the clean case: for a TestFill season the sync stands down before any read (the trigger's own header; pin it — see test below). So:

- **E1 = TestFill only.** A `Line Ups` relink in a season with a fantasy Config is allowed iff `Fantasy/<sport>/<S>/TestFill` exists at plan time **and** again at `changedSincePlan` time (if the fill was cleared in between, the cluster is refused). Delete E1(b) and Review Focus 5's "Finished + paused" wording.
- **Order:** Parlevino's `--apply` runs **before** `npm run fill:s15 -- --clear …`. Put it in the runbook's second-batch section and in the Season 16 order (the fill clear is that order's first step today). If the owner clears the fill first, the tool refuses him safely and the runbook says why.
- **Test (Task 1):** run the real `maybeSyncRoster` with a before/after Ishtar node that differs only in Parlevino's UID, on a season whose `TestFill` exists → zero writes, no market read. And the same change on a season with a Config and no TestFill → the cluster is refused at plan time.

### M2. Review Focus 2 and 3 contradict each other — a crash between the copy and the remove would strand him

E2 refuses the person when "the kept account already has a record for that league+season". E2 also copies first and removes second, with a backup save between every write. So a run that dies after the copy and before the remove leaves a record on **both** accounts — and the re-run refuses him (Review Focus 2) instead of finishing the move (Review Focus 3).

**Fix — a three-way rule per league+season:**
- kept has no record, old has one → plan the copy then the remove;
- kept has a record with the **same value and same status** as the old → plan only the remove (finish the move);
- kept has a record and old has none → nothing (done);
- anything else (different value, or the two in different statuses) → refuse the person, nothing moved.

Undo after a partial apply: the backup holds the copy (attempted) and the remove (not attempted) → undo removes the kept copy and leaves the old record. Test all four branches plus the undo.

The remove stays the tool's only allowed removal: `after: null` only for `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old uid in the map>`, only when its matching copy (same league/season/status, kept uid, identical value) is in the same plan and precedes it.

### M3. E2 as written silently changes the first batch — make it opt-in

Review Focus 4 says the first batch's map "produces exactly the same plan and plan code as before". It can't: eight of the ten people hold old sign-up records (Hiram S9–S14, Robert Tatari S11–S14, and so on — see the parent audit table), and E2 would now move all of them. The parent plan's D14 deliberately leaves those records where they are, and that decision passed review.

**Fix:** E2 runs only for a cluster whose map entry says `"moveSignUps": true`. Parlevino's map sets it; the first batch's map does not, so its plan and code (`31ae18c0f5293f4a`) are unchanged by construction. `assertMergePaths` refuses any sign-up write for a cluster without the flag. Review Focus 4 then holds and its test is meaningful.

## Should-fixes

- **S1.** The sign-up record's value is the player's display name (the Manager writes `set(name)`), and the Manager's export joins comments by that name. Copy the value verbatim (the plan already says so) — add a test that the kept record's value is byte-identical to the old one, so the comment join keeps working for old seasons.
- **S2.** Task 2's emulator fixture needs a `Sign Ups` tree and a `TestFill` node on the fantasy season, or the rehearsal proves nothing about E1/E2.
- **S3.** Runbook: Parlevino's merge also goes before the Season 16 price apply and the Season 16 roster build (both already read `Line Ups` UIDs live, so the order is "merge first", nothing more).

## Minor

- `--map <file>` already exists in the tool; E4 needs no new flag.
- The notice email goes to an iCloud address he last used in June 2025; the push goes to the Gmail account he is using now. That is the right pair — nothing to change.

## Owner question

**Move the first ten people's old sign-up records too?** Today the parent plan leaves them on the old accounts (they're payment history; the old account is stamped "merged" and hidden). If you want "bring everything" for all of them, I set `moveSignUps` for those eight clusters and the first batch gets a new plan code — one more practice run before the real one. If not, only Parlevino's move.
