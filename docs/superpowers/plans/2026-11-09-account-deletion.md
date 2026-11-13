# Account deletion that actually deletes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make "Delete Account" in the fan app work for every sign-in method and remove the person's data the way the new Privacy Policy promises, so the app meets Apple's account-deletion rule (guideline 5.1.1(v)) and Google Play's account-deletion policy.

**Architecture:** One server-side deletion (`functions/src/lib/account_deletion.ts`, pure planner + applier over the existing `FantasyDb`-style fake-able database interface) exposed two ways: a callable `deleteAccount` the signed-in person triggers from Settings, and an admin-only callable `adminDeleteAccount` the Manager app uses for email requests. The fan app re-authenticates per provider first (email password, Google, or Sign in with Apple, which also yields the authorization code Apple requires us to revoke), then calls the function, then signs out and clears the session. The hosted page `https://infinite-sports-app.web.app/delete-account` (already written) is the web path Google requires.

**Tech Stack:** Firebase Functions v2 (TypeScript, vitest), firebase-admin (RTDB, Auth, Storage), Flutter `firebase_auth` (`reauthenticateWithCredential`, `revokeTokenWithAuthorizationCode`), `google_sign_in`, `sign_in_with_apple`.

**Spec:** The Privacy Policy §10–11 and the delete-account page (`public/privacy/index.html`, `public/delete-account/index.html`) are the promise this plan keeps. Written by Fable 5.1 on 2026-11-09 after the legal-documents audit; owner decisions in that session: accounts 13+, league records stay (name may be replaced on request), payment records stay.

---

## Why the current flow fails (audit 2026-11-09)

`lib/settings.dart` "Delete Account": asks the person to type their email, then calls `removeImage(user)` and `user.delete()` with no error handling.

1. Firebase refuses `user.delete()` unless the person signed in within the last few minutes (`requires-recent-login`). Anyone who has been signed in longer taps "Yes, Delete" and nothing happens, with no message.
2. Only the login and the profile photo go. `Users/<uid>` (DOB, phone, city, ZIP, gender, token), `PublicProfiles/<uid>`, fantasy managers/squads/picks, mini-league memberships, support tickets, notification tokens all stay.
3. Sign in with Apple users: Apple requires the app to revoke the Apple token on deletion; nothing does. Their relay email also makes "type your email" a guessing game.
4. Google requires a web page for deletion requests (now written) and an admin way to honour it (none).

## Design

### D1. What is deleted, what is kept, what is anonymised

| Data | Action |
|---|---|
| Firebase Auth user (email/Google/Apple), Apple token | delete; Apple: revoke first (client, D4) |
| `Users/<uid>` (whole node: names, email, phone, DOB, city, ZIP, gender, referral, token, Played, Awards, Information, ProfileUrl, MergedInto…) | delete |
| `PublicProfiles/<uid>` | delete (the mirror trigger also reacts to the Users delete; the applier deletes explicitly so the order never matters) |
| Storage `Users/<uid>/profileimage.jpg` | delete |
| `Fantasy/<sport>/<S>/Managers/<uid>`, `Squads/<uid>`, `Access/<uid>` private parts, `AccessClaims/<uid>`, `Badges/<uid>`, `Notified`, `SquadAlertsCheck`… (every per-uid node under a season except the ledgers below) | delete |
| `Fantasy/<sport>/<S>/PublishedPicks/<gw>/<uid>`, `History/<gw>/<uid>`, `Leaderboards/**/<uid>` rows | **anonymise**: keep points/rank rows so other managers' ranks stay true; replace `TeamName`/`ManagerName`/`DisplayName` with `Deleted manager`, drop any photo url |
| `Fantasy/<sport>/<S>/MiniLeagues/<id>/Members/<uid>` | delete; if the person is the league's creator, hand `CreatedBy` to the oldest remaining member or delete the league when empty |
| `Fantasy/<sport>/<S>/Players/<name>/uid` == uid | remove the `uid` leaf (the market row stays — it is league data) |
| `<Sport>/<S>/Line Ups/<team>/<player>/uid` == uid (and tournament rosters) | remove the `uid` leaf; the roster name stays (league record) |
| `Sign Ups/<league>/<S>/<Paid\|NotPaid>/<uid>` | keep (payment/sign-up record; value is the display name; opaque uid key) |
| `Registrations/<id>/Submissions/<uid>` | keep the payment fields (`Paid`, amounts, Stripe ids, timestamps) and the display name; delete every other answer (phone, email, emergency contact, free text) — write `Deleted: true` |
| `Support/Tickets/*` by uid | delete tickets and their screenshots in Storage |
| `MergeNotices/<uid>`, `Insiders/<uid>`, `Campaigns` claims per uid | delete |
| `EventsV2/*/Attendees/<uid>`, `Events/*/Attendees/<uid>` | delete |
| Device FCM topics | nothing server-side (the client unsubscribes on sign-out already) |
| `DeletedAccounts/<uid> = {At, Provider}` | write (no PII) — proves the deletion happened, lets the admin tool answer "was this done?" |

Payment records (`Access/<uid>` card fields, Stripe ids, `Registrations` payment fields, `Sign Ups`) are kept because the policy says so (accounting). Everything with a name on it that is not a league or payment record goes.

### D2. One planner, two callers

`planAccountDeletion(snapshot, uid) → DeletionPlan` is pure: a list of `{path, action: 'delete' | 'write', after?}` plus a list of Storage object paths, computed from a read snapshot built by `readAccountDeletionSnapshot(db, uid)` (seasons listed via `childKeys`/shallow reads, never a whole-tree read). `applyAccountDeletion(db, storage, plan)` executes it in the listed order, writes `DeletedAccounts/<uid>` last, and returns `{deleted, anonymised, storageDeleted, errors}`. Both callables share this; tests use the existing `FakeDb`.

- `deleteAccount` (callable, v2): requires `request.auth`; the uid is **always** `request.auth.uid` (never a parameter); checks `auth_time` within the last 5 minutes (the same bar Firebase sets for client deletes) else returns `failed-precondition` with code `recent-login-required`; runs the plan; deletes the Auth user with the admin SDK; returns the summary (counts only).
- `adminDeleteAccount` (callable, v2): requires an admin caller via the existing `requireAdmin(request)` in `functions/src/fantasy_messages.ts` (`/Admins/<uid> === true`); takes `{uid, reason}`; same plan; also deletes the Auth user; writes `DeletedAccounts/<uid>.By = adminUid`. Reason is stored, never emailed.

### D3. Fan app flow (`lib/account/delete_account_flow.dart`, replaces the dialog in `settings.dart`)

1. Explain screen: what is deleted / kept (same lines as the hosted page), a text field that must read `DELETE` (not the email — Apple relay users don't know theirs), a red "Delete my account" button.
2. Re-authenticate by provider (read `user.providerData.first.providerId`):
   - `password`: ask for the password in a dialog → `reauthenticateWithCredential(EmailAuthProvider.credential)`.
   - `google.com`: `GoogleSignIn().signIn()` → `reauthenticateWithCredential(GoogleAuthProvider.credential)`.
   - `apple.com`: `SignInWithApple.getAppleIDCredential(...)` → `reauthenticateWithCredential(OAuthProvider('apple.com').credential)` → `FirebaseAuth.instance.revokeTokenWithAuthorizationCode(credential.authorizationCode)` (iOS only; wrapped in try — a revoke failure is logged and does not block the delete). Mark "verify on simulator" in the PR: this path cannot be exercised on the Android emulator.
3. Call `deleteAccount`. On `recent-login-required` (clock skew, slow re-auth) → re-run step 2 once.
4. On success: `popUntil(isFirst)` then `signOutAndClearSession()` (the Auth user is already gone; `signOut()` tolerates it) → welcome wall shows a one-line snackbar "Your account was deleted."
5. On any failure: a plain message with the support email; nothing partial is hidden (the function reports what it managed; a second tap is safe because the planner is idempotent).

Dialogs with text fields are StatefulWidgets owning their controllers (standing rule, see `livestream_link_dialog.dart`). Light + dark, 360 px.

### D4. Manager app

Users page row menu → "Delete account…" (admin-only): shows the same what-is-deleted list, requires typing the person's first name, calls `adminDeleteAccount`, shows the counts, and the row disappears (the Users stream no longer finds `Users/<uid>`). This is how an emailed request (the hosted page) is honoured. The CSV export keeps working (it reads `Users`, which no longer holds the person).

### D5. The order rule with merges

If the uid is an **old** account of a completed merge (`Users/<uid>/MergedInto` set), the callable refuses with `already-merged` and the message names the kept account's masked hint — deleting the kept account is the right action, and the Manager tool points there. (The merge tool's `--find-dupes` and the Season 17 "Find duplicates" screen stay unaffected.)

## Global Constraints

- No RTDB `get()` in the fan app (iOS parity); the flow uses callables and the auth SDK only.
- Nothing runs against production during the build beyond the emulator; the first real deletion is the owner's own test account, on his go.
- No emails/phones/full uids in logs, tests, docs or commits; summaries are counts.
- Existing tests stay green (functions 2032+, fan `flutter test`).
- iOS-only steps (Apple re-auth + revoke) get a "verify on simulator" line in the PR for Paul/Bronsin.

## Review Focus

1. **Signed in for a week, taps delete** → re-auth prompt appears, delete succeeds (the exact failure today). Widget test: the flow calls the re-auth step before the callable.
2. **Apple relay email** → the flow never asks for the email; `DELETE` is the confirmation. Test pins the field.
3. **Function dies halfway** → a second call completes the rest and still ends with `DeletedAccounts/<uid>`; no row is double-anonymised into garbage. Planner test: plan from a half-deleted snapshot contains only the remaining steps.
4. **A manager ranked 3rd deletes** → the leaderboard still shows 1, 2, "Deleted manager", 4 — nobody's rank moves. Test pins the anonymised row's points and the absence of a name.
5. **Old merged account** → refused with `already-merged`, nothing written. Test pins it.

---

### Task 1: Planner + applier (server, pure)

**Files:** Create `functions/src/lib/account_deletion.ts`; Test `functions/src/lib/account_deletion.test.ts` (FakeDb from `test_support.ts`).

**Interfaces:** `readAccountDeletionSnapshot(db, uid)`, `planAccountDeletion(snapshot, uid): DeletionPlan`, `applyAccountDeletion(db, storage, plan): Promise<DeletionSummary>`; `DeletionPlan.steps: Array<{path: string; action: 'delete' | 'write'; after?: unknown}>`, `DeletionPlan.storagePaths: string[]`; `DeletionSummary = {deleted: number; anonymised: number; storageDeleted: number; errors: string[]}`.

- [ ] **Step 1: Failing tests** for every row of the D1 table (one fixture user present in Users, PublicProfiles, two fantasy seasons incl. History/PublishedPicks/Leaderboards/MiniLeagues, a roster `uid` leaf, a Players `uid` leaf, a registration with payment fields + phone, two support tickets, an event RSVP), Review Focus 3–5, and "an unknown uid plans only the `DeletedAccounts` write".
- [ ] **Step 2: Run** `cd functions && npx vitest run src/lib/account_deletion.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement.** Season discovery via `listFantasySeasons`; per-uid rows found with shallow key reads; the anonymised row keeps every numeric field and replaces name fields with `Deleted manager`; registration scrub keeps the allow-listed payment keys only.
- [ ] **Step 4: Run** — Expected: PASS; full `npx vitest run` green.
- [ ] **Step 5: Commit** `feat(functions): account deletion planner + applier`.

### Task 2: Callables

**Files:** Create `functions/src/account_deletion.ts` (`deleteAccount`, `adminDeleteAccount`); Modify `functions/src/index.ts` (export both); Test `functions/src/account_deletion.test.ts`.

- [ ] **Step 1: Tests** — unauthenticated → `unauthenticated`; stale `auth_time` → `failed-precondition` / `recent-login-required`; merged old account → `already-merged`; happy path calls the applier then `auth.deleteUser(uid)` and returns counts; `adminDeleteAccount` by a non-admin → `permission-denied`; by an admin → runs and stamps `By`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** (v2 `onCall` with the same defaults as `fantasy_access.ts` — default region, no App Check option; App Check stays off per the owner). **Step 4: Run** — PASS.
- [ ] **Step 5: Emulator rehearsal:** seed the Task 1 fixture, call both functions through the emulator, assert the tree afterwards matches the plan; record the command in the ledger.
- [ ] **Step 6: Commit** `feat(functions): deleteAccount + adminDeleteAccount callables`.

### Task 3: Fan app flow

**Files:** Create `lib/account/delete_account_flow.dart`, `lib/account/delete_account_page.dart`; Modify `lib/settings.dart` (replace the dialog with a push to the page), `lib/firebase_auth/firebase_auth_services.dart` (add `reauthenticateForDeletion()` per provider, returning the Apple authorization code when present); Test `test/account/delete_account_page_test.dart` (Firebase-free via injected `reauth` + `callDelete` closures, like `writeOverride` on About You).

- [ ] **Step 1: Tests** — button disabled until the field reads `DELETE`; tapping calls `reauth` then `callDelete` in that order; `recent-login-required` once → `reauth` runs again and `callDelete` retried; a failure shows the support email; success calls `onDeleted`.
- [ ] **Step 2: Run** `flutter test test/account/delete_account_page_test.dart` — FAIL. **Step 3: Implement** per D3. **Step 4: Run** — PASS; `flutter analyze` clean for the new files.
- [ ] **Step 5: Emulator check** on the Android emulator: email account end-to-end (password re-auth) and Google account; write the Apple path's "verify on simulator" line into the ledger for the PR.
- [ ] **Step 6: Commit** `feat(account): delete account flow — re-auth per provider, server-side deletion, Apple revoke`.

### Task 4: Manager "Delete account…"

**Files:** Modify `InfiniteSportsManagerFlutter/lib/ui/users/users_page.dart` (row action), Create `lib/ui/users/delete_account_sheet.dart`, `lib/services/firebase/account_admin_service.dart` (callable wrapper); Test `test/ui/users/delete_account_sheet_test.dart`.

- [ ] **Step 1: Tests** — confirm button enabled only when the typed name matches; calls the service with `{uid, reason}`; shows the returned counts. **Step 2: Run** — FAIL. **Step 3: Implement** (admin-only visibility reuses the page's existing admin flag). **Step 4: Run** — PASS. **Step 5: Commit** `feat(users): delete account action (admin) for emailed requests`.

### Task 5: Docs + store forms

**Files:** Modify `docs/runbooks/store-privacy-forms.md` (mark the deletion URL as live-and-working), Create `docs/runbooks/deleting-an-account.md` (owner runbook: in-app path, emailed-request path via the Manager, what to answer the person, the merged-account refusal).

- [ ] **Step 1:** Write both; **Step 2: Commit** `docs: account deletion runbook + store forms update`.
