# DB Security Lockdown — Implementation Plan (P0)

> **For agentic workers:** execute per phase as briefed by the coordinator.
> Spec: `docs/superpowers/specs/2026-10-27-db-security-lockdown-design.md` (v2,
> sweep-verified). Checkboxes track progress. NOT STARTED — nothing below is
> implemented yet.

**Goal:** default-deny database rules with zero loss of working features:
mirrors + callables first, fan-app read re-points second, rules flip last.

**Repos/branches:** fan `infinite_sports_flutter` on `zaya-fantasy`
(functions live here too). Manager app needs no re-points (admin by rule).

**iOS parity is a hard gate (owner directive):** every new/changed fan-app
read uses `onValue` streams or `.once()` — **RTDB `.get()` is banned** (iOS
SDK returns wrong-node/empty data under overlapping listeners). Phase B ends
with a verification grep proving no `DatabaseReference.get(` exists in
changed code. Server-side (functions) is unaffected by the iOS bug.

---

## Phase A — Functions: mirrors + callables (TypeScript, vitest)

**Files:**
- Create: `functions/src/lib/public_mirrors.ts` (pure projections + logic)
- Create: `functions/src/lib/public_mirrors.test.ts`
- Create: `functions/src/public_mirrors_watch.ts` (triggers)
- Create: `functions/src/registration_lookups.ts` (two callables)
- Modify: `functions/src/index.ts` ONLY if that is how existing modules get
  exported for deploy (study how `insiders_watch.ts` / `campaign_watch.ts`
  are exported today and copy that mechanism exactly).

- [ ] **A1. Pure projections (`lib/public_mirrors.ts`) + exhaustive tests**
  - `publicProfileProjection(userNode: unknown): Record<string, unknown> | null`
    — whitelist copy of: `First Name`, `Last Name`, `ProfileUrl`, `Played`,
    `TournamentsPlayed`, `Awards`, `Information`, `ProfileCompleted`.
    Absent keys omitted; `null`/non-map input → `null` (meaning: delete the
    mirror). NEVER copy anything else (no DOB/Phone/Token/Zip/City/Gender/
    ReferralSource/FavoriteSports/Date Joined/Email).
  - `registrationConfigProjection(configNode: unknown)` — the Config node
    verbatim if it is a map, else `null`.
  - `teamMemberEntry(submissionNode: unknown): {teamId, value} | null` —
    for a submission with a string `TeamId`, value `{DisplayName, Paid}`
    (DisplayName string fallback `''`, Paid boolean fallback `false`);
    submissions without `TeamId` (individual path) → `null`.
  - Tests cover: full node, minimal node, null, RTDB array-coercion shapes
    (a List where a Map is expected must not crash — return null/skip),
    PII fields proven absent from output.

- [ ] **A2. Triggers (`public_mirrors_watch.ts`)**
  - `onUserWritten = onValueWritten('/Users/{uid}')` → write
    `PublicProfiles/{uid}` = projection of `event.data.after` (null deletes).
  - `onRegistrationConfigWritten = onValueWritten('/Registrations/{regId}/Config')`
    → `RegistrationsPublic/{regId}` (null deletes).
  - `onSubmissionWritten = onValueWritten('/Registrations/{regId}/Submissions/{uid}')`
    → maintain `Registrations/{regId}/Teams/{teamId}/Members/{uid}`:
    write the new entry; if the BEFORE submission had a different `TeamId`
    (or the submission was deleted), remove the old member entry.
  - Match the logging + error style of `insiders_watch.ts`. No secrets needed.

- [ ] **A3. Callables (`registration_lookups.ts`)** — port the logic the fan
  app currently runs client-side; study these before writing:
  - fan `lib/registration/registration_service.dart` →
    `getAllSubmissionAnswersForMatch` (and its use in
    `registration_form_page.dart`) for the first-timer/promo match semantics.
  - fan `lib/registration/registration_service.dart` `findTeamByCode` /
    `lib/registration/join_code_page.dart` for join-code matching semantics
    (trim/case handling must match exactly).
  - `checkFirstTimer = onCall` (auth required): input `{email, phone}` →
    scans all `Registrations/*/Submissions/*/Answers` server-side, returns
    the same verdict shape the client logic produces today (document the
    shape in the file header). Normalize email lowercase; phone digits-only,
    mirroring the Dart code.
  - `resolveJoinCode = onCall` (auth required): input `{regId, code}` →
    `{found: true, teamId, teamName, codeWaivesPayment}` or `{found: false}`.
    NEVER return other teams' codes.
  - Port the matching logic into pure functions (in `lib/public_mirrors.ts`
    or a new `lib/registration_lookups_logic.ts`) so vitest covers it
    without emulators.

- [ ] **A4. Verify:** `npm test` (vitest) green, `npm run build` (tsc) clean
  in `functions/`. Do NOT deploy (coordinator deploys). Commit per step with
  trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## Phase B — Fan app read re-points (Dart, streams only)

- [ ] **B1. `PublicProfiles` reads** — new helper (e.g.
  `lib/misc/public_profiles.dart`, onValue/once only) and re-point every
  other-user read from the sweep: `getAllUsers` (utility.dart), profile
  page's other-user mode, leaderboards/scorepage/box-score/lineups/player
  stats tabs, `league_service` roster photos, `tournament_service`
  `enrichRosterPhotos`, team detail pages, search hub. Self-reads stay on
  `Users/<uid>`. Delete dead `tournamentplayerprofile.dart` read if it is
  truly dead (verify first).
- [ ] **B2. Open registrations via `RegistrationsPublic`** —
  `getOpenRegistrations` / `watchOpenRegistrations` / `getRegistration` and
  their call sites (navbar, frontpage, eventpage, registration entry).
- [ ] **B3. Captain roster via `Teams/<tid>/Members`** — replace
  `watchTeamMembers`'s Submissions-bucket scan with a Members stream.
- [ ] **B4. Promo + join-code via callables** — replace the client scans with
  `checkFirstTimer` / `resolveJoinCode` calls (cloud_functions package,
  same pattern as `createRegistrationPaymentIntent`).
- [ ] **B5. AFC vote path fix** (missing `Seasons/` segment) — fix the vote
  ref builder; sweep for the same defect class.
- [ ] **B6. Insiders leaderboard dormant empty state** (program data wiped;
  whole-node read incl. emails must go) — "coming soon" card, no root read.
- [ ] **B7. Verification:** full fan suite green; analyze clean; grep proves
  no `DatabaseReference.get(` in lib/; owner-visible flows demoed on device.

## Phase C — Rules flip (coordinator + owner)

- [ ] **C1.** Export current rules → `database.rules.backup.json`; author
  `database.rules.json` per spec §5–6; wire `firebase.json`.
- [ ] **C2.** REST test matrix script (unauth/auth/cross-uid/admin cases).
- [ ] **C3.** Backfill mirrors via REST (PublicProfiles for all users,
  RegistrationsPublic for existing registrations, Members where teams
  exist); verify counts vs live data.
- [ ] **C4.** Deploy functions (Phase A) + rules at a quiet hour, run the
  matrix, owner smoke-tests both apps on devices. Rollback = redeploy of the
  backup rules file.
- [ ] **C5.** Storage rules audit + deploy (same pattern).

**Phase D (follow-up):** store release shipping the Phase B re-points must go
out before/with any future registration that uses team join codes (codes
resolve server-side after the flip).
