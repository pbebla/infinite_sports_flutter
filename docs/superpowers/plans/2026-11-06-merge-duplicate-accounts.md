# Merge Duplicate Player Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold each of the 10 owner-confirmed duplicate players into the one account the owner chose, so every season they played shows on one profile and the extra accounts stop appearing in search, with nothing deleted and every step undoable.

**Architecture:** A dry-run-first admin tool (`functions/tools/merge_accounts.ts`, the fill tool's safety pattern: allowlisted paths, backup before write, undo from backup) relinks roster rows to the kept account, moves the "seasons played" index and missing profile fields, and stamps the old account `MergedInto`. Two small code changes make a stamped account disappear from the public profile mirror and from the Manager's account pickers. A separate, reversible step disables the old logins.

**Tech Stack:** TypeScript (tools + Cloud Functions, vitest), Flutter/Dart Manager app (Riverpod), Realtime Database REST with the firebase-tools admin login, Identity Toolkit REST.

**Spec:** this document's "Design" section. Owner decisions (2026-11-06): merge all 10 clusters; keep — Hiram: the S15 email; Carlo: the S16 email (carlo11rocks); Anthony: the S14–15 email; Mishel Ushana: the S14–15 email; Robert Tatari: the S15 email; Ashor: the S12 email; Joseph Baba: the S14 email (ghadine); Mishel Lazar: the S10 email; Roben Tatari: the S11–15 email; Robert Shamoeilzadeh: the S11 account.

---

## Design

### What the read-only audit found (2026-11-06)

Every account in the 10 clusters was checked against every node that stores a player or account id (uid map: Line Ups, AFC and tournament rosters, `Users`, `PublicProfiles`, Registrations, Sign Ups, Insiders/Referrals, Support, every Fantasy season's uid-keyed nodes and `Players.uid`). Only yes/no and counts were printed; the per-uid result is in `scratchpad/prices/merge_audit.json` (local, never committed).

| Person (keep → old) | Old accounts hold |
|---|---|
| Hiram Alvarez (S15 → S9–S14) | Line Ups Futsal S9, S10, S11, S14; Played; **ProfileUrl** (keep has none); old Sign Ups |
| Carlo (S15+S16 → S14) | Line Ups Futsal S14; **AFC roster ×3** (Beyond the Game Turf Spring 2025, Winter 2025, Fall 2025); Played; old Sign Ups |
| Anthony Memon (S14–15 → S13) | Line Ups Futsal S13; **AFC roster** (Assyrian National Convention 2024); Played; old Sign Ups |
| Mishel Ushana (S14–15 → S13) | Line Ups Futsal S13; Played; old Sign Ups |
| Robert Tatari (S15 → 3 accounts) | Line Ups Futsal S11, S12, S13, S14; Played; old Sign Ups |
| Ashor Khodiseperghan (S12 → S9) | Line Ups Futsal S9; Played; old Sign Ups |
| Joseph Baba (S11–14 + Basketball → S9) | Line Ups Futsal S9; Played; ProfileUrl (keep already has one); old Sign Ups |
| Mishel Lazareshaghi (S10 → S9) | Line Ups Futsal S9; Played; **ProfileUrl** (keep has none); old Sign Ups |
| Roben Tatari (S11–15, no second account) | Unlinked roster row **"Robben Tatari", Futsal S10 Nineveh** (no UID) |
| Robert Shamoeilzadeh (S11, no second account) | Unlinked roster row **"Robert Shamoelzadeh", Futsal S10 Nineveh** (no UID) |

**No old account has:** any Fantasy data (no manager, squad, access, badge or `Players.uid`), any Registration submission (Carlo's Futsal-16 registration is already on the kept account), Insider/referral data, support tickets, awards, tournament rosters. So the merge never touches fantasy, payments or referrals, and no trigger that moves money or referral credit fires.

### Decisions

- **D1. Relink rosters by the `UID` leaf only.** For each roster row whose `UID` is an old account: set `<Sport>/<S>/Line Ups/<team>/<name>/UID` (or `AFC San Jose/Seasons/<S>/Roster/<name>/UID`) to the kept uid. For the two name-variant rows (no UID): set their `UID` to the kept uid. **Never rename a roster key** — stats, activities, StatLog and attendance are keyed by the roster name, so a rename would cut the season off from its stats. (The profile shows the kept account's name; the S10 rosters keep their original spelling.)
- **D2. "Seasons played" index.** For each relinked league row, set `Users/<keep>/Played/<Sport>/Season <S> = <team>` — the exact shape `lineup_service.dart linkLeaguePlayer` writes. AFC rows need no Played entry (the profile scans AFC rosters by UID). Refuse the cluster if the kept account already has a *different* team for that Sport/Season.
- **D3. Profile fields.** Copy into the kept account only what it lacks: `ProfileUrl` (from the most recently active old account that has one) and missing `Information/<leaf>` values. Never copy `Token`, email, phone, names, date of birth, or anything else — the kept account's own values win; the old values stay on the old record.
- **D4. Never delete; stamp.** On each old account: remove `Users/<old>/Played` (it now lives on the kept account) and write `Users/<old>/MergedInto = <keep>` and `Users/<old>/MergedAt = <ms>`. The rest of the old record stays, so old Sign Ups still resolve a name. *Alternative considered:* archive and delete `Users/<old>` (the mirror would then drop it with no code change) — rejected: deletion breaks name lookups for old sign-up and payment records and is harder to undo.
- **D5. Mirror drops merged accounts.** `publicProfileProjection` (`functions/src/lib/public_mirrors.ts:49`) returns `null` when the user node has a `MergedInto` string, so the `onUserWritten` trigger removes `PublicProfiles/<old>` as soon as D4 lands — the old account vanishes from fan search, attendees and profile lookups. Must be deployed **before** the tool's `--apply`.
- **D6. Manager pickers hide merged accounts.** `MyUser` gains `mergedInto` (`String?`); every Manager screen that lets the owner *choose* an account (link player, assign trophy, add to tournament roster — the implementer lists each by its `usersProvider`/`usersStreamProvider` use) filters `mergedInto != null` out. Lookups by uid (names on old sign-ups, DOBs) keep seeing them.
- **D7. Old logins.** After the data merge is verified, a separate `--disable-old-logins` step sets `disabled: true` on each old Firebase Auth account (Identity Toolkit `accounts:update`), reversible with `--enable-old-logins`. Without it, a person who signs in with an old email gets a fresh `Users/<old>` profile and onboarding (`lib/main.dart:197-228`) and the duplicate comes back. Owner-visible consequence: that email's login stops working; the person signs in with the kept email instead. Accounts are never deleted.
- **D8. Left on the old account on purpose:** Sign Ups and their comments (payment history), game votes, predictions, event RSVPs, Storage profile images (their URLs are what `ProfileUrl` points to — never delete them), device tokens.
- **D9. Mapping file.** The tool reads `functions/tools/rehearsal_out/merge_map.json` (git-ignored; holds full uids, no emails): `{ clusters: [{ who, keep, old: [uid], nameRows: [{ sport, season, team, name }] }] }`. The plan and code never contain emails; the tool never prints user field values except roster names, team names and seasons (public league data).

## Global Constraints

- Nothing runs against production until the owner says so: dry run first, owner reads the printed plan, owner's explicit OK for `--apply`, separate OK for `--disable-old-logins`.
- Never push; local commits on `zaya-fantasy`. The D5 mirror change deploys with the owner's final review, before `--apply`.
- Every production write goes through an allowlist of exactly the D1–D4 paths for the clusters in the map; `--apply` backs up every touched node first (`tools/rehearsal_out/merge_backup_<ISO>.json`); `--undo <backup>` restores exactly those nodes.
- Admin calls send the firebase-tools OAuth token in an `Authorization: Bearer` header — never in a URL, log, or error message (`fill_test_season.ts` convention).
- No emails, phones, DOBs or tokens in output, commits, artifacts, or this plan.
- Manager change: light + dark, 360 px unaffected (filter only); existing Manager tests green (2334); functions tests green.

## Review Focus

1. **A roster row's UID changed since the dry run** (someone linked or unlinked it in the Manager): `--apply` re-reads every target right before writing and refuses the whole cluster if anything differs from the dry-run plan.
2. **A roster row that holds a third, unrelated uid**: refused, never overwritten. Test pins it (Task 3).
3. **Running `--apply` twice**: the second run finds nothing to do and writes nothing. Test pins it (Task 3).
4. **The mirror change not deployed yet**: `--apply` checks `PublicProfiles/<old>` one minute after stamping and prints a loud warning per old account still mirrored (it does not fail the merge — the next `Users/<old>` write after deploy removes it).
5. **Robert Tatari's three old accounts**: all three relink to one keep; Played gets S11, S12, S13, S14; `ProfileUrl` stays absent (none had one). Test pins it (Task 3).

---

### Task 1: Public mirror skips merged accounts

**Files:** Modify `functions/src/lib/public_mirrors.ts:49-59`; Test `functions/src/lib/public_mirrors.test.ts`.

- [ ] **Step 1: Failing test** — `publicProfileProjection({ 'First Name': 'A', MergedInto: 'k' })` → `null`; without `MergedInto` → unchanged projection; `MergedInto: ''` or non-string → treated as not merged.
- [ ] **Step 2: Run** `cd functions && npx vitest run src/lib/public_mirrors.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** the early `return null` with a doc line pointing at this plan.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(fn): merged accounts leave the public profile mirror`.

### Task 2: Manager account pickers hide merged accounts

**Files:** Modify the Manager `MyUser` model (`lib/models/my_user.dart` or wherever `MyUser.fromMap` lives) and each picker the implementer finds; Test `test/models/my_user_merged_test.dart` + one widget test per picker family.

**Interfaces:** Produces `MyUser.mergedInto` (`String?`, from `MergedInto`; empty string → null) and `bool get isMerged`.

- [ ] **Step 1: Failing tests** — parsing sets `mergedInto`; the link-player picker given two users, one merged, lists only the other; a by-uid name lookup still resolves the merged one.
- [ ] **Step 2: Run** `flutter test <files>` (Manager repo) — Expected: FAIL.
- [ ] **Step 3: Implement**; list every picker changed in the report.
- [ ] **Step 4: Run** full `flutter test` and `flutter analyze lib` — Expected: PASS, no new issues.
- [ ] **Step 5: Commit** (Manager repo) `feat: account pickers hide merged accounts`.

### Task 3: Merge plan builder (pure)

**Files:** Create `functions/tools/merge_accounts_logic.ts`; Test `functions/tools/merge_accounts_logic.test.ts`.

**Interfaces:**
- Produces: `buildMergePlan(map: MergeMap, snap: MergeSnapshot, nowMs: number): { writes: PlanWrite[]; refusals: Array<{ who: string; why: string }>; summary: string[] }` where `PlanWrite = { path: string; before: unknown; after: unknown }` (`after: null` = remove); `MergeSnapshot` = the values of every node the plan may touch, keyed by path (`Users/<uid>`, each relevant `…/Line Ups/<team>/<name>/UID`, AFC roster UIDs); `assertMergePaths(writes, map)` — the allowlist (throws on any path outside D1–D4 for the map's uids/rows).

- [ ] **Step 1: Failing tests** (fixtures shaped like the audit, fake uids):
  - Hiram-like: 4 Line Ups rows relinked, 4 Played entries added to keep, `ProfileUrl` copied, old `Played` removed, `MergedInto`/`MergedAt` set.
  - Joseph-like: keep already has `ProfileUrl` → not overwritten.
  - Carlo-like: 3 AFC rows relinked, no Played entry for AFC.
  - Robert-Tatari-like (Review Focus 5).
  - Name-variant row with no UID → `UID` set to keep, Played `Season 10 = Nineveh` added; roster key untouched.
  - Row holding a third uid → cluster refused with `why` naming the season/team (Review Focus 2).
  - Keep's Played already has a different team for that season → cluster refused.
  - Already-merged snapshot → zero writes (Review Focus 3).
  - `Information`: only missing leaves copied; `Token`/email-like keys never appear in any write.
  - `assertMergePaths` rejects `Users/<keep>/Token`, `Users/<old>` whole-node deletes, and any uid not in the map.
- [ ] **Step 2: Run** `npx vitest run tools/merge_accounts_logic.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** per D1–D4. Summary lines name person, season, team, roster name only.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(tools): duplicate-account merge planner`.

### Task 4: Merge tool (dry run, apply, undo)

**Files:** Create `functions/tools/merge_accounts.ts`; Modify `functions/tools/tsconfig.json` (include), `functions/package.json` (`"merge:accounts"` script).

**Interfaces:** Consumes Task 3. Produces `npm run merge:accounts` (dry run: reads every snapshot path with admin GETs, prints summary + refusals, writes nothing), `-- --apply` (re-read and compare to the dry-run plan per cluster — Review Focus 1; back up every planned path; PUT/DELETE each write through `assertMergePaths`; Review Focus 4 check), `-- --undo <backupFile>` (restore every backed-up path verbatim; refuses a backup whose kind/format is wrong).

- [ ] **Step 1:** Implement, reusing the fill tool's token minting and REST helpers (extract a shared `tools/admin_rest.ts` only if it is a straight move; otherwise import from `fill_test_season.ts`).
- [ ] **Step 2:** Tests for the backup/undo round trip and the refusal of a mismatched re-read, against an in-memory REST stub (no network).
- [ ] **Step 3: Local emulator rehearsal** — seed the RTDB emulator with fixture data shaped like the audit, run dry run → `--apply` → `--undo` against it (`FIREBASE_DATABASE_EMULATOR_HOST`), and show the before/after/undone node values match. Record in the report.
- [ ] **Step 4: Production dry run only** (read-only, safe): `npm run merge:accounts` — paste the summary (names/seasons/teams only) into the report for the owner. **Do not `--apply`.**
- [ ] **Step 5: Commit** `feat(tools): merge duplicate accounts (dry run / apply / undo)`.

### Task 5: Old-login switch

**Files:** Modify `functions/tools/merge_accounts.ts` (flags `--disable-old-logins`, `--enable-old-logins`).

- [ ] **Step 1:** Implement via Identity Toolkit `projects/infinite-sports-app/accounts:update` `{ localId, disableUser }` for each old uid in the map; refuses unless every old uid's `Users/<old>/MergedInto` is set (data merged first). Prints uid prefixes only.
- [ ] **Step 2:** Unit-test the guard with a stub. Never run against production in this build.
- [ ] **Step 3: Commit** `feat(tools): reversible switch for merged accounts' old logins`.

### Task 6: Owner runbook

- [ ] **Step 1:** Create `docs/runbooks/merging-duplicate-accounts.md` (plain language, for the owner) with the order: deploy Task 1 (with the branch's final review) → `npm run merge:accounts` (dry run) → owner reads it → owner's OK → `--apply` → owner checks 2–3 kept profiles on the phone (all seasons show, old account gone from search) → owner's OK → `--disable-old-logins` → tell those players to sign in with their kept email. Undo commands included.
- [ ] **Step 2: Commit** `docs: runbook for merging duplicate accounts`.

## Not in this plan (owner can ask for later)

- A Manager screen that *finds* likely duplicates each season and merges with one tap (people make a new login most seasons, so this will recur).
- Fixing the kept Robert Shamoeilzadeh profile's first name ("Rabert") — owner's call; a one-field edit.
