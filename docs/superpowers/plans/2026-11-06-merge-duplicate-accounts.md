# Merge Duplicate Player Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold each of the 10 owner-confirmed duplicate players into the one account the owner chose, so every season they played shows on one profile and the extra accounts stop appearing in search; tell each person which email to use; nothing deleted and every step undoable.

**Architecture:** A dry-run-first admin tool (`functions/tools/merge_accounts.ts`, the fill tool's safety pattern: allowlisted paths, backup before write, undo from backup) relinks roster rows to the kept account, adds the "seasons played" entries and missing profile fields, and stamps the old account `MergedInto` + a partly hidden hint of the kept email. The public profile mirror drops a stamped account; the Manager's account pickers hide it; the fan app shows anyone still signed into an old account a plain notice and signs them out. A separate `--notify` step emails each old address (server-side, through the existing support mailer) and pushes the kept accounts through the existing Campaigns feature. A last, reversible step disables the old logins.

**Tech Stack:** TypeScript (tools + Cloud Functions, vitest), Flutter/Dart fan app and Manager app, Realtime Database REST with the firebase-tools admin login, Identity Toolkit REST, nodemailer (support mailer), FCM via Campaigns.

**Spec:** this document's "Design" section. Owner decisions (2026-11-06): merge all 10 clusters; keep — Hiram: the S15 email; Carlo: the S16 email (carlo11rocks); Anthony: the S14–15 email; Mishel Ushana: the S14–15 email; Robert Tatari: the S15 email; Ashor: the S12 email; Joseph Baba: the S14 email (ghadine); Mishel Lazar: the S10 email; Roben Tatari: the S11–15 email; Robert Shamoeilzadeh: the S11 account. Fix "Rabert" → "Robert". Tell them which email to use by **in-app notice + push + email**. **Revision 2 (2026-11-06):** Fable's review (`docs/superpowers/plans/2026-11-06-fable-review-scale-and-merge.md`) folded in — M1, M2, S1–S3; owner: "lets do all the recommendation and fixes".

---

## Design

### What the read-only audit found (2026-11-06)

Every account in the 10 clusters was checked against every node that stores a player or account id (Line Ups, AFC and tournament rosters, `Users`, `PublicProfiles`, Registrations, Sign Ups, Insiders/Referrals, Support, every Fantasy season's uid-keyed nodes and `Players.uid`). Only yes/no and counts were printed; the per-uid result is in the session scratchpad `prices/merge_audit.json` (local, never committed).

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
| Robert Shamoeilzadeh (S11, no second account) | Unlinked roster row **"Robert Shamoelzadeh", Futsal S10 Nineveh** (no UID); kept profile first name "Rabert" |

**No old account has:** any Fantasy data (no manager, squad, access, badge or `Players.uid`), any Registration submission (Carlo's Futsal-16 registration is already on the kept account; he is the only one of the ten registered for S16 so far), Insider/referral data, support tickets, awards, tournament rosters. Every person's most recent sign-in is on the account being kept.

### Decisions

- **D1. Relink rosters by the `UID` leaf only.** For each roster row whose `UID` is an old account: set `<Sport>/<S>/Line Ups/<team>/<name>/UID` (or `AFC San Jose/Seasons/<S>/Roster/<name>/UID`) to the kept uid. For the two name-variant rows (no UID): set their `UID` to the kept uid. **Never rename a roster key** — stats, activities, StatLog and attendance are keyed by the roster name.
- **D2. Never in a fantasy season (review M2).** `onLineupsWritten` (`functions/src/fantasy_roster.ts`) listens on `Line Ups` and only stands down for a season with no fantasy `Config`. Every planned relink is in such a season. The tool **enforces** it: the dry run snapshots `Fantasy/<sport>/<season>/Config` for every season it would touch, and `assertMergePaths` refuses any `Line Ups` relink in a season where that Config exists. A future merge that must touch a fantasy season is a deliberate extension with its own review.
- **D3. "Seasons played" index.** For each relinked league row, set `Users/<keep>/Played/<Sport>/Season <S> = <team>` — the exact shape `lineup_service.dart linkLeaguePlayer` writes (`firebase_paths.dart:214`). AFC rows need no Played entry (the profile scans AFC rosters by UID). Refuse the cluster if the kept account already has a *different* team for that Sport/Season.
- **D4. Profile fields.** Copy into the kept account only what it lacks: `ProfileUrl` (from the most recently active old account that has one) and missing `Information/<leaf>` values. Never copy `Token`, email, phone, names, date of birth, or anything else.
- **D5. Stamp, never delete (review S1).** On each old account write exactly three leaves: `Users/<old>/MergedInto = <keep>`, `Users/<old>/MergedAt = <ms>`, `Users/<old>/MergedHint = <masked kept email>`. Everything else on the old record — including its `Played` — stays as it is (nothing reads it once the mirror drops the account and the person is signed out; the undo is three deletes).
- **D6. Masked email.** `maskEmail(email)` (pure, shared by the tool and the notice trigger): local part's first 2 characters + `•` for each remaining character (at most 8), then `@domain` unchanged; a local part of 1–2 characters keeps its first character + `•`. Example shape: `ca••••••••@gmail.com`. The kept email is looked up with Identity Toolkit `accounts:lookup` and masked in memory — never printed, logged, or stored unmasked.
- **D7. Mirror drops merged accounts.** `publicProfileProjection` (`functions/src/lib/public_mirrors.ts:49`) returns `null` when the user node has a non-empty `MergedInto` string, so `onUserWritten` removes `PublicProfiles/<old>` as soon as D5 lands. (`MergedHint` is not in `PUBLIC_PROFILE_KEYS`, so it is never mirrored.)
- **D8. Manager pickers hide merged accounts.** `MyUser` gains `mergedInto` (`String?`); every Manager screen that lets the owner *choose* an account (link player, assign trophy, add to tournament roster — the implementer lists each by its `usersProvider`/`usersStreamProvider` use) filters merged accounts out. Lookups by uid (names on old sign-ups, DOBs) keep seeing them.
- **D9. In-app notice (review M1).** The fan app, while signed in, watches `Users/<me>/MergedInto` and `Users/<me>/MergedHint` (`onValue`, never `get()`; the user can read their own node — `database.rules.json` `Users/$uid`). When `MergedInto` is a non-empty string it shows one dialog, once: title **"Your accounts were combined"**, body **"All your seasons are now on your Infinite Sports account for {hint}. Please sign in with that email."** (without a hint: **"…on your other Infinite Sports account. Please sign in with your other email."**), one button **"OK"** → sign out (Firebase + Google, `FirebaseAuthService.signOut`) and clear auto sign-in. Light and dark, 360 px.
- **D10. Name fix (owner).** Robert Shamoeilzadeh's cluster includes one extra write: `Users/<keep>/First Name = "Robert"` (map field `firstNameFix`). Allowlisted for that cluster only; the mirror follows through `onUserWritten`; roster keys untouched.
- **D11. Email to each old address (owner: in-app + push + email).** The tool's `--notify` writes `MergeNotices/<old> = {KeepHint, CreatedAt}` per old account — **no email address in the database**. A new trigger `onMergeNoticeCreated` (`/MergeNotices/{uid}`, bound to the support mailer's secrets): claims the node (`Status: 'sending'` by transaction; an existing Status aborts — never sends twice), reads the old account's email from Firebase Auth (`admin.auth().getUser(uid)`), sends through the support mailer, then records `Status: 'sent' | 'no-email' | 'failed'` + `At` (a failure records the error's message only — no addresses). In the emulator: `Status: 'dry-run'`, nothing sent. Email: subject **"Your Infinite Sports accounts were combined"**; body **"Hi, we combined your Infinite Sports accounts so all of your seasons show on one profile. From now on, please sign in with {hint}. If you didn't expect this, just reply to this email."** `MergeNotices` gets no rules entry (clients denied).
- **D12. Push to the kept accounts.** `--notify` also writes one `Campaigns/<id>` with `Audience: {Type: 'users', Uids: {<keep>: true…}}` for the clusters that had an old account (8 people — the two name-variant clusters had no second account), title **"Your accounts were combined"**, body **"All your seasons are now on this profile."**, `SendAt: 0`. The existing `onCampaignCreated` sends it and it shows in the Manager's campaign list. The implementer matches every field `parseCampaign` (`functions/src/lib/campaigns.ts`) requires.
- **D13. Old logins.** After the data merge is verified, `--disable-old-logins` sets `disableUser: true` on each old Firebase Auth account (Identity Toolkit `accounts:update`), reversible with `--enable-old-logins`; refuses unless every old uid is stamped. Without it, signing in with an old email recreates `Users/<old>` and onboarding (`lib/main.dart:194-232`); a signed-in old account could also delete its own `MergedInto` (the rules let a user write their own node), which would put it back in search. Accounts are never deleted.
- **D14. Left on the old account on purpose:** Sign Ups and their comments (payment history), game votes, predictions, event RSVPs, Storage profile images (`ProfileUrl` points at them — never delete), device tokens, the old `Played`.
- **D15. Mapping file.** `functions/tools/rehearsal_out/merge_map.json` (git-ignored; full uids, no emails): `{ clusters: [{ who, keep, old: [uid], nameRows: [{ sport, season, team, name }], firstNameFix?: string }] }`. The tool never prints user field values except roster names, team names and seasons (public league data); emails only ever appear masked.
- **D16. Finding new duplicates before S16 rosters (review S3).** `npm run merge:accounts -- --find-dupes <registrationId>` (read-only): for each submission in `Registrations/<id>/Submissions`, compare the submitter's `Users` first+last name (normalized: lowercase, single spaces) with every roster row name in that registration's sport across all seasons whose `UID` is a *different* account or empty; print candidates as `name — seasons/teams — "already linked to another account" | "unlinked row"`. No emails.

## Global Constraints

- Nothing runs against production until the owner says so: dry run first, owner reads the printed plan, then a separate explicit OK for each of `--apply`, `--notify`, `--disable-old-logins`.
- Never push; local commits on `zaya-fantasy` (both repos). Functions (D7, D11) deploy with the owner's final review, before `--apply`; the fan notice (D9) ships in the next app release.
- Every production write goes through an allowlist of exactly the D1/D3/D4/D5/D10 paths for the clusters in the map (plus `MergeNotices/<old>` and one `Campaigns/<id>` for `--notify`); `--apply` backs up every touched node first (`tools/rehearsal_out/merge_backup_<ISO>.json`); `--undo <backup>` restores exactly those nodes.
- Admin calls send the firebase-tools OAuth token in an `Authorization: Bearer` header — never in a URL, log, or error message (`fill_test_season.ts` convention).
- No unmasked emails, phones, DOBs or tokens in output, logs, commits, the database, or this plan.
- Existing tests stay green: functions, fan (2841), Manager (2334).

## Review Focus

1. **A roster row's UID changed since the dry run** (someone linked or unlinked it in the Manager): `--apply` re-reads every target right before writing and refuses that cluster if anything differs from the dry-run plan.
2. **A roster row that holds a third, unrelated uid**: refused, never overwritten. Test pins it (Task 4).
3. **Running `--apply` or `--notify` twice**: the second run writes nothing and sends nothing. Tests pin it (Tasks 4, 6).
4. **The mirror change not deployed yet (review S2):** the first old account stamped is a canary — wait 90 s, check `PublicProfiles/<old>` is gone; if it is still there, stop before any other cluster and print the `--undo` command.
5. **Robert Tatari's three old accounts**: all three relink to one keep; Played gets S11, S12, S13, S14; `ProfileUrl` stays absent (none had one); all three get stamps and notices. Test pins it (Task 4).

---

### Task 1: Public mirror skips merged accounts

**Files:** Modify `functions/src/lib/public_mirrors.ts:49-59`; Test `functions/src/lib/public_mirrors.test.ts`.

- [ ] **Step 1: Failing test** — `publicProfileProjection({ 'First Name': 'A', MergedInto: 'k' })` → `null`; without `MergedInto` → unchanged; `MergedInto: ''` or a non-string → not merged; `MergedHint` never appears in a projection.
- [ ] **Step 2: Run** `cd functions && npx vitest run src/lib/public_mirrors.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** the early `return null` with a doc line pointing at this plan.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(fn): merged accounts leave the public profile mirror`.

### Task 2: Manager account pickers hide merged accounts

**Files:** Modify `lib/models/my_user.dart` and each picker the implementer finds (Manager repo); Test `test/models/my_user_merged_test.dart` + one widget test per picker family.

**Interfaces:** Produces `MyUser.mergedInto` (`String?`, from `MergedInto`; empty → null) and `bool get isMerged`.

- [ ] **Step 1: Failing tests** — parsing sets `mergedInto`; the link-player picker given two users, one merged, lists only the other; a by-uid name lookup still resolves the merged one.
- [ ] **Step 2: Run** `/c/src/flutter/bin/flutter test <files>` (Manager repo) — Expected: FAIL.
- [ ] **Step 3: Implement**; list every picker changed in the report.
- [ ] **Step 4: Run** full `flutter test` and `flutter analyze lib` — Expected: PASS, no new issues.
- [ ] **Step 5: Commit** (Manager repo) `feat: account pickers hide merged accounts`.

### Task 3: Fan app "accounts combined" notice

**Files:** Create `lib/account/merged_account_notice.dart` (pure `mergedNoticeText(hint)` + the watcher widget); Modify the signed-in shell in `lib/main.dart` (wrap the signed-in home); Test `test/account/merged_account_notice_test.dart`.

**Interfaces:** Produces `class MergedNotice { final String title; final String body; }`, `MergedNotice? mergedNoticeFor(Object? mergedInto, Object? hint)` (null when not merged), and `MergedAccountWatcher({required Widget child, Stream<Map<String, Object?>>? states, Future<void> Function()? onSignOut})` (test seams; default = `onValue` of `Users/<me>/MergedInto` + `MergedHint` and the app's sign-out + auto-sign-in clear).

- [ ] **Step 1: Failing tests** — `mergedNoticeFor('k', 'ca••@gmail.com')` → D9's title and body with the hint; no hint → the "your other email" body; `''`/null/non-string → null. Widget: a stream emitting a merged state shows the dialog once (a second emission doesn't stack a second dialog); tapping OK calls `onSignOut` once; a not-merged stream shows nothing; 360×640 light and dark: no overflow.
- [ ] **Step 2: Run** `/c/src/flutter/bin/flutter test test/account/merged_account_notice_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement** per D9.
- [ ] **Step 4: Run** `/c/src/flutter/bin/flutter test` and `flutter analyze lib/account lib/main.dart` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: tell anyone on a merged account which email to use`.

### Task 4: Merge plan builder (pure)

**Files:** Create `functions/tools/merge_accounts_logic.ts`; Create `functions/src/lib/mask_email.ts` (shared with Task 6); Test `functions/tools/merge_accounts_logic.test.ts`, `functions/src/lib/mask_email.test.ts`.

**Interfaces:**
- Produces: `maskEmail(email: string): string` (D6); `buildMergePlan(map: MergeMap, snap: MergeSnapshot, nowMs: number): { writes: PlanWrite[]; refusals: Array<{ who: string; why: string }>; summary: string[] }` where `PlanWrite = { path: string; before: unknown; after: unknown }` (`after: null` = remove) and `MergeSnapshot` holds the values of every node the plan may touch keyed by path (`Users/<uid>` per uid, each relevant roster `UID` leaf, each touched season's `Fantasy/<sport>/<season>/Config` presence) plus `keptHints: Record<keepUid, string>` (already masked); `assertMergePaths(writes, map, snap)` — the allowlist (D1/D2/D3/D4/D5/D10 paths only).

- [ ] **Step 1: Failing tests** (fake uids, fixtures shaped like the audit):
  - `maskEmail('carlo11rocks@gmail.com')` → `'ca••••••••@gmail.com'` (8 bullets max); `maskEmail('ab@x.org')` → `'a•@x.org'`; `maskEmail('a@x.org')` → `'a•@x.org'`.
  - Hiram-like: 4 Line Ups rows relinked, 4 Played entries added to keep, `ProfileUrl` copied, old account gets exactly `MergedInto`, `MergedAt`, `MergedHint` (its `Played` untouched).
  - Joseph-like: keep already has `ProfileUrl` → not overwritten.
  - Carlo-like: 3 AFC rows relinked, no Played entry for AFC.
  - Robert-Tatari-like (Review Focus 5).
  - Name-variant row with no UID → `UID` set to keep, Played `Season 10 = Nineveh` added; roster key untouched; no old account → no stamps.
  - D10: `firstNameFix: 'Robert'` → exactly one `Users/<keep>/First Name` write; other clusters none; `assertMergePaths` rejects a `First Name` write for any other cluster.
  - D2: a relink in a season whose fantasy Config exists → cluster refused, `why` names the season.
  - Row holding a third uid → cluster refused (Review Focus 2). Keep's Played has a different team for that season → cluster refused.
  - Already-merged snapshot → zero writes (Review Focus 3).
  - `Information`: only missing leaves copied; `Token` and email-like keys never appear in any write.
  - `assertMergePaths` rejects `Users/<keep>/Token`, any whole-node `Users/<uid>` write or delete, and any uid not in the map.
- [ ] **Step 2: Run** `cd functions && npx vitest run tools/merge_accounts_logic.test.ts src/lib/mask_email.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** per D1–D6, D10. Summary lines name person, season, team and roster name only.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(tools): duplicate-account merge planner`.

### Task 5: Merge tool — dry run, apply (with canary), undo, find-dupes

**Files:** Create `functions/tools/merge_accounts.ts`; Modify `functions/tools/tsconfig.json` (include), `functions/package.json` (`"merge:accounts"` script).

**Interfaces:** Consumes Task 4. Produces `npm run merge:accounts` (dry run: admin GETs of every snapshot path + Identity Toolkit lookups for the kept emails, masked in memory; prints summary + refusals; writes nothing), `-- --apply` (per cluster: re-read and compare to the dry-run plan — Review Focus 1; back up every planned path; PUT/DELETE each write through `assertMergePaths`; the first stamped old account is the canary — Review Focus 4), `-- --undo <backupFile>` (restores every backed-up path verbatim; refuses a backup of the wrong kind), `-- --find-dupes <registrationId>` (D16, read-only).

- [ ] **Step 1:** Implement, reusing the fill tool's token minting and REST helpers (extract a shared `tools/admin_rest.ts` only if it is a straight move).
- [ ] **Step 2:** Tests (in-memory REST stub, no network): backup/undo round trip; a mismatched re-read refuses the cluster; the canary stops the run when the stub keeps `PublicProfiles/<old>`; `--find-dupes` on a fixture lists an "already linked to another account" and an "unlinked row" candidate and never prints an email.
- [ ] **Step 3: Local emulator rehearsal** — seed the RTDB emulator with fixture data shaped like the audit, run dry run → `--apply` → `--undo` against it (`FIREBASE_DATABASE_EMULATOR_HOST`; Identity Toolkit lookups stubbed by a `--fake-emails` flag that only works with the emulator host set), and show before/after/undone values match. Record in the report.
- [ ] **Step 4: Production read-only runs** (safe, write nothing): `npm run merge:accounts` and `npm run merge:accounts -- --find-dupes Futsal-16` — paste both summaries (names/seasons/teams only) into the report for the owner. **Do not `--apply`.**
- [ ] **Step 5: Commit** `feat(tools): merge duplicate accounts (dry run / apply / undo / find-dupes)`.

### Task 6: Notices — email trigger and `--notify`

**Files:**
- Create: `functions/src/lib/merge_notice.ts` (pure: `mergeNoticeEmail(hint)` → `{subject, html}`; `mergeNoticeCampaign(keepUids, nowMs)` → the Campaign node)
- Create: `functions/src/merge_notice_watch.ts` (`onMergeNoticeCreated`); export it from `functions/src/index.ts`
- Modify: `functions/src/support_mail.ts` — add `sendMail(root, message): Promise<'sent' | 'skipped' | 'failed'>` that `sendSupportMail` now wraps (its behavior unchanged)
- Modify: `functions/tools/merge_accounts.ts` (`--notify`)
- Test: `functions/src/lib/merge_notice.test.ts`, `functions/src/merge_notice_watch.test.ts`, tool test

**Interfaces:** Consumes `maskEmail` (Task 4), `SUPPORT_MAIL_SECRETS`, `parseCampaign`.

- [ ] **Step 1: Failing tests** — `mergeNoticeEmail('ca••@gmail.com')` has D11's exact subject and body text with the hint, HTML-escaped. `mergeNoticeCampaign(['k1','k2'], t)` passes `parseCampaign` with audience users `[k1,k2]`, D12's title/body, `SendAt: 0`. Trigger (injected auth/mailer seams): claims once — a second invocation on a node that has `Status` sends nothing; no Auth email → `'no-email'`; mailer `'failed'` → `Status: 'failed'` with no address in the stored error; emulator → `'dry-run'`, nothing sent. Tool `--notify`: refuses unless every old uid is stamped; writes one `MergeNotices/<old>` per old uid not already present and one Campaign for the 8 kept accounts; a second run writes nothing (Review Focus 3).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** per D11/D12.
- [ ] **Step 4: Run** `npx vitest run` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(fn): merge notices — email to the old address, push to the kept account`.

### Task 7: Old-login switch

**Files:** Modify `functions/tools/merge_accounts.ts` (flags `--disable-old-logins`, `--enable-old-logins`).

- [ ] **Step 1:** Implement via Identity Toolkit `projects/infinite-sports-app/accounts:update` `{ localId, disableUser }` for each old uid in the map; refuses unless every old uid's `Users/<old>/MergedInto` is set. Prints uid prefixes only.
- [ ] **Step 2:** Unit-test the guard with a stub. Never run against production in this build.
- [ ] **Step 3: Commit** `feat(tools): reversible switch for merged accounts' old logins`.

### Task 8: Owner runbook

- [ ] **Step 1:** Create `docs/runbooks/merging-duplicate-accounts.md` (plain language, for the owner). Order: (1) owner's final review → deploy functions (Tasks 1 + 6) → the fan app release that carries Task 3; (2) `npm run merge:accounts` dry run → owner reads it; (3) owner's OK → `--apply` (canary first) → owner checks 2–3 kept profiles on the phone (all seasons show, old account gone from search, Robert's name); (4) owner's OK → `--notify` (emails + push); (5) owner's OK → `--disable-old-logins`; (6) **before building S16 rosters from sign-ups**, run `--find-dupes Futsal-16` and merge any new duplicates first. Undo commands for each step. Recommendation: wait for the app release in (1) before (3); if the owner goes earlier, the email in (4) covers it.
- [ ] **Step 2: Commit** `docs: runbook for merging duplicate accounts`.

## Not in this plan (owner can ask for later)

- A Manager screen that finds likely duplicates each season and merges with one tap (D16 is the read-only first step).
