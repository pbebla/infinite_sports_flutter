# Merge Extension — Parlevino Tamraz (fantasy test season + sign-up records) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold Parlevino Tamraz's older account into his new one — every season, his seasons-played list, his position info and his paid sign-up records — using the existing merge tool, extended for the two things it refuses today.

**Architecture:** Two narrow extensions to the reviewed merge planner + CLI (`functions/tools/merge_accounts_logic.ts`, `merge_accounts.ts`): (E1) a roster relink is allowed in a season that has fantasy set up only when that season's fantasy is not live (the test-fill season, or a Finished league season whose engine is paused for good); (E2) a new "move a sign-up record" write that copies `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old>` to the kept account and then removes the old key, with exact backup and undo. Parlevino runs as a second batch with his own map file, so the first batch's plan code is unchanged.

**Tech Stack:** TypeScript tools + vitest; Realtime Database REST (admin login); the existing merge tool.

**Spec:** this document's Design section. Owner decisions (2026-11-08): "merge his info into the new email, bring everything" — keep the account he made for his Season 16 sign-up (Gmail, created 2026-11-06); fold in the older account (iCloud, created 2023-05, Seasons 12–15). Parent plan: `docs/superpowers/plans/2026-11-06-merge-duplicate-accounts.md` (D1–D16 still bind). Fable review 2026-11-06, merge M2: "A future merge that must touch a fantasy season becomes a deliberate extension with its own review" — this is that extension.

---

## Design

### What the read-only audit found (2026-11-08)

| | Kept account (Gmail, `OrOpPS…`) | Old account (iCloud, `SGSF0N…`) |
|---|---|---|
| Rosters | — | Futsal S12 Nineveh, S13 Hakkari, S14 Nimrod, **S15 Ishtar** |
| `Users` | Information, Token | Played, Information, Token |
| Player search (`PublicProfiles`) | yes | yes |
| Registrations | **Futsal-16** submission | — |
| Sign Ups | Futsal/16/Paid | **Futsal/12, 13, 14, 15 /Paid** (each a single text value) |
| Photo, awards, tournaments, AFC, fantasy manager/squad/access/badges, insiders, support | none | none |

Why the current tool refuses him: Futsal S15 has a fantasy Config (the test season), so D2 refuses the S15 relink and with it the whole person. D14 leaves sign-up records on the old account; the owner asked for everything.

### Decisions

- **E1. Relinks in a season whose fantasy is not live.** D2 stays the default. A `Line Ups` relink in a season with `Fantasy/<sport>/<S>/Config` is allowed only when either (a) `Fantasy/<sport>/<S>/TestFill` exists (the test season — `onLineupsWritten` stands down for it, `functions/src/fantasy_roster.ts` header), or (b) the league season is Finished (`<sport>/<S>/Finished === true`) **and** its fantasy engine is paused for good (`Config.lockOverride` is `open` or `locked` with no `lockOverrideUntil`) — then the roster trigger runs but, for a player already in the market, only sets `teamName` when it differs (`roster_sync.ts` `maybeSyncRoster`), which a same-team relink never does. Any other fantasy season (live or auto) is still refused. The D16/unmoved-data refusals (a fantasy manager entry for the old account in any season with a Config) still apply. `Fantasy/<sport>/<S>/Players/<name>/uid` is not touched (he has none; carry-over matches by name).
- **E2. Move sign-up records.** For each `Sign Ups/<league>/<S>/<Paid|NotPaid>/<old>` the old account holds: write the same value to `…/<keep>`, then remove `…/<old>`. Refuse the person if the kept account already has a record for that league+season (in either status) — never overwrite or merge two records. `Comments/<displayName>` entries (keyed by display name, text embeds a uid) are left as they are. This is the merge tool's first remove: it is allowlisted for this exact shape only, backed up like every write (`before` = the old value / absent), and undone exactly (restore the old key, remove the new one). No trigger watches `Sign Ups` (parent plan uid map).
- **E3. Everything else is the existing tool.** Played S12–S15 on the kept account, missing `Information` leaves copied, the three stamps on the old account (MergedInto last), canary, notices (email to the old iCloud address, one push to the kept account), the login switch, `--find-dupes`.
- **E4. Second batch, own map.** `functions/tools/rehearsal_out/merge_map_parlevino.json` (git-ignored; uids only) with one cluster; every command takes `--map tools/rehearsal_out/merge_map_parlevino.json`. The first batch's map and plan code (`31ae18c0f5293f4a`) are unchanged.

## Global Constraints

- Nothing runs against production beyond read-only dry runs during the build. `--apply`, `--notify --send` and the login switch each wait for the owner's explicit go, after the parent plan's deploy (mirror change + `onMergeNoticeCreated`).
- Never push; local commits on `zaya-fantasy`.
- No emails, phones or full account ids in output, commits, docs or the database (the old address appears only inside the server-side email send).
- Existing tests stay green (functions 2032).

## Review Focus

1. **A live fantasy season** (Config present, no TestFill, lockOverride `auto` or a timed override, or the league season not Finished) — a relink there is still refused. Test pins it (Task 1).
2. **The kept account already has a sign-up record for that season** — the person is refused, nothing moved. Test pins it (Task 1).
3. **Undo after a move** restores `Sign Ups/…/<old>` with its exact value and removes `…/<keep>`; a re-run after a partial apply finishes the remaining moves only. Tests pin it (Task 2).
4. **The first batch's map** produces exactly the same plan and plan code as before (no E2 writes appear for people with no movable sign-ups). Test pins it (Task 1).
5. **The S15 fill gets cleared before the apply** (runbook S16 order) — E1(b) still allows the S15 relink (Finished + paused-for-good). Test pins it (Task 1).

---

### Task 1: Planner — E1 relink gate and E2 sign-up moves

**Files:** Modify `functions/tools/merge_accounts_logic.ts` (snapshot contract, planner, `assertMergePaths`); Test `functions/tools/merge_accounts_logic.test.ts`.

**Interfaces:** Produces snapshot keys `Fantasy/<sport>/<S>/TestFill` (presence), `<sport>/<S>/Finished`, `Fantasy/<sport>/<S>/Config/lockOverride` + `lockOverrideUntil` for every touched season with a Config, and `Sign Ups/<league>/<S>/<status>/<uid>` for the old and kept uids (values for the old, presence for the kept); `PlanWrite` may carry `after: null` ONLY for an allowlisted sign-up move.

- [ ] **Step 1: Failing tests** — S15-like season with Config + TestFill → relink planned; Config + Finished + `lockOverride:'locked'` (no until) → planned; Config + `auto` → refused; Config + `locked` with `lockOverrideUntil` → refused; Config + not Finished → refused (Review Focus 1, 5). Sign-ups: old holds S12–S15 Paid, kept has none → 4 copy writes then 4 removes, removes after copies; kept already has S13 (Paid or NotPaid) → person refused, zero writes (Review Focus 2); `assertMergePaths` rejects a remove anywhere else (e.g. `Users/<old>/Played`, `Sign Ups/<league>/<S>/Comments/x`, a kept-uid key) and a copy whose value differs from the old value. The first batch's fixture map → byte-identical plan as before (Review Focus 4).
- [ ] **Step 2: Run** `cd functions && npx vitest run tools/merge_accounts_logic.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** per E1/E2; summary lines say "move his Season N sign-up record".
- [ ] **Step 4: Run** — Expected: PASS; full `npx vitest run` green.
- [ ] **Step 5: Commit** `feat(tools): merge — relinks in a non-live fantasy season, sign-up records move`.

### Task 2: CLI — reads, apply/undo of moves, emulator rehearsal, dry run

**Files:** Modify `functions/tools/merge_accounts.ts`; Test `functions/tools/merge_accounts.test.ts`; Create `functions/tools/rehearsal_out/merge_map_parlevino.json` (git-ignored).

- [ ] **Step 1:** Snapshot reads for E1/E2 (shallow/leaf only; never read `Comments`), the read allowlist, and the write/remove allowlist for the exact sign-up move shape. `changedSincePlan` re-checks each moved record (old value unchanged, kept still absent) and each E1 season's gate.
- [ ] **Step 2: Tests** — apply moves copy-then-remove in that order with backup entries for both paths; undo restores exactly (Review Focus 3); a re-run after a crash between a copy and its remove completes only the remove.
- [ ] **Step 3: Emulator rehearsal** — fixture shaped like the audit (S15 with Config + TestFill), dry run → `--apply` (no canary under the emulator) → `--undo`; before/after/undone match.
- [ ] **Step 4: Production DRY RUN only** (read-only) with `--map tools/rehearsal_out/merge_map_parlevino.json` — record the plan (4 relinks, 4 Played, Information leaves if any, 4 sign-up moves, 3 stamps) and its plan code; and re-run the first batch's dry run to confirm `31ae18c0f5293f4a` is unchanged.
- [ ] **Step 5: Commit** `feat(tools): merge CLI — sign-up moves, non-live fantasy seasons`.

### Task 3: Runbook

- [ ] **Step 1:** Add a "Second batch — Parlevino" section to `docs/runbooks/merging-duplicate-accounts.md`: same steps 2–6 with `--map tools/rehearsal_out/merge_map_parlevino.json`, his plan code from Task 2, and the note that his paid sign-up records for Seasons 12–15 move to the new account (undo puts them back). Remove the "open question" section.
- [ ] **Step 2: Commit** `docs: runbook — second batch (Parlevino)`.
