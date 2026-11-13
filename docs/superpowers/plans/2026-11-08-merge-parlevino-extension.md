# Merge Extension — sign-up records move, test-season relinks, Parlevino joins the batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the merge tool bring a person's old paid sign-up records along by default, allow a roster relink in the fantasy *test* season, and add Parlevino Tamraz to the one merge batch — so all eleven people merge with one practice run and one real run.

**Architecture:** Two narrow extensions to the reviewed merge planner + CLI (`functions/tools/merge_accounts_logic.ts`, `merge_accounts.ts`): (E1) a `Line Ups` relink in a season that has fantasy set up is allowed only while that season carries the `TestFill` marker (fantasy stands down completely for it); (E2) for every cluster, each `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old>` record is copied to the kept account and then removed from the old one, with a three-way rule that finishes a half-done move on a re-run and an exact undo. Parlevino goes into the main map; the batch's plan code changes once.

**Tech Stack:** TypeScript tools + vitest; Realtime Database REST (admin login); the existing merge tool.

**Spec:** this document's Design section. Owner decisions (2026-11-08): keep Parlevino's Season 16 Gmail account and fold in the older iCloud account — "bring everything"; move the old sign-up records for **everyone**, not just him ("whichever you think" → recommendation accepted). Parent plan `docs/superpowers/plans/2026-11-06-merge-duplicate-accounts.md` (D1–D16 still bind, except D14's "Sign Ups stay on the old account", which this plan replaces). **Revision 2:** Fable's review `docs/superpowers/plans/2026-11-08-fable-review-parlevino-extension.md` folded in (M1–M3, S1–S3).

---

## Design

### What the read-only audit found (2026-11-08)

| | Kept account (Gmail, `OrOpPS…`) | Old account (iCloud, `SGSF0N…`) |
|---|---|---|
| Rosters | — | Futsal S12 Nineveh, S13 Hakkari, S14 Nimrod, **S15 Ishtar** |
| `Users` | Information, Token | Played, Information, Token |
| Player search (`PublicProfiles`) | yes | yes |
| Registrations | **Futsal-16** submission | — |
| Sign Ups | Futsal/16/Paid | **Futsal/12, 13, 14, 15 /Paid** (each a single text value = his display name) |
| Photo, awards, tournaments, AFC, fantasy manager/squad/access/badges, insiders, support | none | none |

Why the current tool refuses him: Futsal S15 has a fantasy Config (the test season), so D2 refuses the S15 relink and with it the whole person. And the tool leaves sign-up records behind (D14); the owner wants everything brought over, for everyone.

Of the first ten, eight also hold old sign-up records (Hiram S9–S14, Carlo S14, Anthony S13, Mishel Ushana S13, Robert Tatari S11–S13, Ashor S9, Joseph S9, Mishel Lazareshaghi S9 — see the parent audit table). With E2 on by default those move too, so the batch's plan code changes from `31ae18c0f5293f4a` to whatever the next practice run prints.

### Decisions

- **E1. Relinks in the fantasy test season only (review M1).** D2 stays the default. A `Line Ups` relink in a season with `Fantasy/<sport>/<S>/Config` is allowed iff `Fantasy/<sport>/<S>/TestFill` exists — at plan time **and** again in `changedSincePlan` right before the cluster's writes (the fill cleared in between → that cluster is refused, nothing written). No other fantasy season qualifies: the roster trigger syncs the whole team and would add any roster name missing from the market (`roster_sync.ts:140-195`), while a TestFill season stands the sync down before any read. The unmoved-data refusals (a fantasy manager entry for the old account, awards, tournaments, registrations) still apply. `Fantasy/<sport>/<S>/Players/<name>/uid` is never touched (he has none; Season 16 carry-over matches him by name).
- **E2. Sign-up records move, for every cluster (review M2 + M3, owner decision).** For each league+season where the old account holds `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old>`, apply the three-way rule against the kept account:
  - kept has no record in either status → plan the copy (`…/<keep>` = the old value, byte-identical — it is the display name the Manager's comment join uses) and then the remove (`…/<old>` = null);
  - kept has a record with the **same value and same status** → plan only the remove (a half-done move finishes);
  - kept has a record and old has none → nothing to do;
  - anything else (different value, or records in different statuses) → refuse the person with a plain reason (no values), nothing moved.
  A cluster may opt out with `"moveSignUps": false` in the map (a future exception; none today). `Comments/<displayName>` entries are left alone (keyed by name; the join keeps working because the value is copied verbatim). This is the tool's only allowed removal: `after: null` only for `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old uid in the map>` whose matching copy (same league/season/status, kept uid, identical value) is in the same plan and precedes it — or whose kept copy already exists with that value (the finish-the-move branch). Backed up like every write (`before` = the old value / absent); undone exactly (restore the old key, remove the kept one). No trigger watches `Sign Ups` (parent uid map); the fan app reads only the status/due/info nodes (`utility.dart:893-940`).
- **E3. Everything else is the existing tool.** Played S12–S15 on the kept account, missing `Information` leaves copied, the three stamps on the old account (MergedInto last), canary, notices (email to the old address, one push per kept account), the login switch, `--find-dupes`.
- **E4. One batch, one map (controller simplification).** Parlevino is an eleventh cluster in `functions/tools/rehearsal_out/merge_map.json` (uids only; old account listed as his one `old`). One practice run, one `--apply --expect-plan <new code>`, one `--notify`, one login switch. The per-kept-account campaigns and the per-old-account notices make the larger batch safe on re-runs. *(Cost if wrong: none — every step is idempotent and refuses what it has already done.)*
- **E5. Order (review M1/S3).** The merge runs **before** `npm run fill:s15 -- --clear …`, before the Season 16 price apply, and before Season 16 rosters are built from sign-ups. The runbook's Season 16 order gets "run the merge" as its first step.

## Global Constraints

- Nothing runs against production beyond read-only dry runs during the build. `--apply`, `--notify --send` and the login switch each wait for the owner's explicit go, after the parent plan's deploy (mirror change + `onMergeNoticeCreated`) and the app releases.
- Never push; local commits on `zaya-fantasy`.
- No emails, phones or full account ids in output, commits, docs or the database.
- Existing tests stay green (functions 2032).

## Review Focus

1. **A live fantasy season** (Config present, no TestFill — whatever lockOverride or Finished say) → the relink is refused. Test pins it (Task 1).
2. **The fill is cleared between the dry run and the apply** → `changedSincePlan` refuses that cluster, nothing written, the run reports it. Test pins it (Task 2).
3. **A crash between a copy and its remove** → the re-run plans only the remove; undo after the partial apply removes the kept copy and leaves the old record. Tests pin both (Tasks 1, 2).
4. **Kept already has a different record** (another value, or Paid vs NotPaid) → the person is refused, nothing moved. Test pins it (Task 1).
5. **The copied value is byte-identical** to the old one, including odd whitespace. Test pins it (Task 1).

---

### Task 1: Planner — E1 test-season gate, E2 sign-up moves

**Files:** Modify `functions/tools/merge_accounts_logic.ts` (snapshot contract, planner, `assertMergePaths`); Test `functions/tools/merge_accounts_logic.test.ts`.

**Interfaces:** Produces snapshot keys `Fantasy/<sport>/<S>/TestFill` (presence) for every touched season with a Config, and `Sign Ups/<league>/<S>/<Paid|NotPaid>/<uid>` values for the old uids and the kept uid (null when absent); map field `moveSignUps?: boolean` (default true); `PlanWrite` may carry `after: null` ONLY for an allowlisted sign-up remove.

- [ ] **Step 1: Failing tests** — Config + TestFill → relink planned; Config without TestFill → refused (Finished or not, any lockOverride) (Review Focus 1). Sign-ups: old holds S12–S15 Paid, kept has none → 4 copies then 4 removes, each remove after its copy; kept has S13 Paid with the same value → only the S13 remove (Review Focus 3); kept has S13 NotPaid, or S13 Paid with another value → person refused, zero writes (Review Focus 4); value with trailing space copied byte-identical (Review Focus 5); `moveSignUps: false` → no sign-up writes; `assertMergePaths` rejects a remove anywhere else (`Users/<old>/Played`, `…/Comments/x`, a kept-uid key), a remove without its copy in the plan (unless the kept copy already exists with the same value), and a copy whose value differs from the old value. Real roster-sync pin: the actual `maybeSyncRoster` with an Ishtar before/after differing only in one UID on a TestFill season → zero writes, no market read.
- [ ] **Step 2: Run** `cd functions && npx vitest run tools/merge_accounts_logic.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** per E1/E2; summary lines say "move his Season N sign-up record" / "finish moving …".
- [ ] **Step 4: Run** — Expected: PASS; full `npx vitest run` green.
- [ ] **Step 5: Commit** `feat(tools): merge — sign-up records move, relinks in the fantasy test season`.

### Task 2: CLI — reads, apply/undo of moves, emulator rehearsal, dry run

**Files:** Modify `functions/tools/merge_accounts.ts`; Test `functions/tools/merge_accounts.test.ts`; Modify `functions/tools/rehearsal_out/merge_map.json` (git-ignored — add Parlevino's cluster; the controller supplies the two uids).

- [ ] **Step 1:** Snapshot reads for E1/E2 (TestFill presence; the sign-up leaves for each old uid and the kept uid under every league/season the old uids appear in — key-only scans of `Sign Ups/<league>/<S>/<status>` to find them, never `Comments`), the read allowlist, and the write/remove allowlist for the exact sign-up move shape. `changedSincePlan` re-checks TestFill for every E1 season and each moved record (old value unchanged, kept still absent / still the same copy).
- [ ] **Step 2: Tests** — apply writes copy-then-remove with backup entries for both; undo restores exactly (Review Focus 3); a re-run after a crash between a copy and its remove completes only the remove; the fill cleared between plan and apply refuses that cluster only (Review Focus 2).
- [ ] **Step 3: Emulator rehearsal** — fixture shaped like the audit (a `Sign Ups` tree with records on the old uids; the fantasy season with Config + TestFill), dry run → `--apply` (no canary under the emulator) → `--undo`; before/after/undone match; clear the fixture's TestFill between dry run and apply → the cluster is refused.
- [ ] **Step 4: Production DRY RUN only** (read-only) with the 11-cluster map — record the plan (the first batch's 69 writes + the sign-up moves + Parlevino's 4 relinks, 4 Played, Information leaves if any, his 4 moves, 3 stamps), its new plan code, and confirm 0 refused.
- [ ] **Step 5: Commit** `feat(tools): merge CLI — sign-up moves, test-season relinks, Parlevino in the batch`.

### Task 3: Runbook

- [ ] **Step 1:** Update `docs/runbooks/merging-duplicate-accounts.md`: eleven people, the new plan code from Task 2, a line that paid sign-up records for old seasons move to the kept account (undo puts them back), and the order rule — run the merge **before** clearing the Season 15 test data, before applying Season 16 prices, and before building Season 16 rosters. Remove the Parlevino "open question" section.
- [ ] **Step 2: Commit** `docs: runbook — eleven people, sign-up records move, run before the fill clear`.
