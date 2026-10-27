# Database Security Lockdown — Design (P0 of Infinite Fantasy)

**Date:** 2026-10-27 (v2, matrix finalized against the full fan-app code sweep)
Companion epic to `2026-10-26-infinite-fantasy-design.md` §17 P0.

## 1. Problem

RTDB rules are `.read: true, .write: true` **at the root**: the entire database
is world-readable and world-writable without signing in — including Users PII
(DOB, phone numbers, FCM tokens), registration submissions (emergency contacts),
and support tickets. Anyone with the database URL can also overwrite scores,
seasons, or wipe nodes. Fantasy creates per-user squads and must be born under
real rules, so this ships first.

The code sweep (2026-10-27) additionally found client-side patterns that are
privacy bugs in their own right and get fixed here:
- The registration form downloads **every submission of every registration**
  (`getAllSubmissionAnswersForMatch`) to check first-timer promos client-side.
- The join-code page downloads **all team join codes** and matches locally —
  any signed-in user could read codes, including payment-waiving ones.
- The Insiders leaderboard reads the whole `Insiders` node including every
  applicant's **email**.

## 2. Facts the design rests on (verified in code)

- **Hard login wall is live on `main`** since commit `ca403f2` (2026-07-25) and
  is in store 4.1.0: signed-out users reach only Welcome/Login/CreateAccount,
  which do no RTDB reads. So every current-app read/write runs authenticated.
- Builds older than the wall could browse signed-out → they keep working for
  **public reads only** (scores, standings). Owner accepted this.
- Email verification is NOT enforced → `auth != null` means "has an account",
  not "trusted". Nothing below grants broad rights to mere account holders.
- Cloud Functions use the Admin SDK and bypass rules entirely.
- RTDB reads fail unless the user can read the **whole** subtree requested —
  so every whole-node read of a mixed public/private node must be re-pointed
  (section 5 lists each one).

## 3. Admin gate

```
"adminGate": root.child('Admins').child(auth.uid).exists()
```
`/Admins/<uid>: true` already exists (owner + Manager login).
`Admins/$uid` read: `auth.uid == $uid` (clients may check only their own
flag); write: nobody (console/Admin SDK only).

## 4. The mirror pattern (one pattern, three mirrors)

When a node mixes private data with a public subset that screens need, a
Cloud Function maintains a read-only public mirror (+ one-time backfill):

| Mirror (new node) | Source | Contents |
|---|---|---|
| `PublicProfiles/<uid>` | `Users/<uid>` onWrite | First/Last Name, ProfileUrl, Played, TournamentsPlayed, Awards, Information (positions/height), ProfileCompleted — **no DOB/phone/token/zip/city/gender/email** |
| `RegistrationsPublic/<regId>` | `Registrations/<regId>/Config` onWrite | the Config node verbatim (it is public content: fees, dates, paths) |
| `Registrations/<regId>/Teams/<tid>/Members/<uid>` | `Submissions/<uid>` onWrite | DisplayName + Paid flag, so captains see their roster without reading submissions |

Mirrors: **public read** (Members: captain + members + admin), functions-only
write. `Users/<uid>` itself becomes owner+admin only — one simple rule, full
PII protection, no migration of existing fields.

Two flows move server-side as callables (both small, pattern exists from
support functions):
- `checkFirstTimer(email, phone)` → replaces the all-submissions client scan.
- `resolveJoinCode(regId, code)` → `{teamId, teamName, codeWaivesPayment}` —
  replaces the all-teams client scan; join codes stop being readable.

## 5. Per-node rules matrix (v2 — from the verified write/read sweep)

| Node | Read | Write |
|---|---|---|
| `Current League`, `<Sport> Season`, `Futsal`, `Basketball`, `Flag Football`, `AFC San Jose`, `Tournaments`, `Logo Urls`, `Events`, `EventsV2`, `Map`, `Categories`, `Trophies`, `NotifPopUp`, `Down`, `Notifications`, `AppConfig` | public | admin |
| — game votes `<sport>/<season>/Date/$d/$g/team1vote/$uid`, `team2vote/$uid` | public (inherited) | `auth.uid == $uid`, validate value `1` |
| — league predictions `<sport>/<season>/Predictions/$match/$uid/$qid` | public (inherited) | `auth.uid == $uid` |
| — tournament predictions `Tournaments/$tid/Predictions/$match/$uid` | public (inherited) | `auth.uid == $uid` |
| — event RSVPs `Events/$i/Attendees/$uid`, `EventsV2/$id/Attendees/$uid`, `EventsV2/$id/Reminders/$uid` | public (inherited) | `auth.uid == $uid` |
| `PublicProfiles` (new) | public | functions only |
| `Users/$uid` | owner + admin | owner + admin |
| `RegistrationsPublic` (new) | public | functions only |
| `Registrations/$id/Config`, `/Form` | public | admin |
| `Registrations/$id/Submissions/$uid` | owner + admin | owner create/update while Config.Open + admin. Validate: joiner `Paid:true` only when its team's `CodeWaivesPayment` is true |
| `Registrations/$id/Teams/$tid` | captain (`CaptainUid == auth.uid`) + admin; `Members` also readable by its members | captain create (own uid as CaptainUid) + admin; `Members` functions-only |
| `FormTemplates` | admin | admin |
| `Sign Ups` (legacy, no sensitive fields; display names only) | public | admin, except: `…/NotPaid/$uid` and `…/Paid/$uid` own-uid (Paid only via the validated joiner flow), `…/Comments/$name` create-only with value `beginsWith(auth.uid + ':')` |
| `Support/Tickets/$n` | ticket's Uid + admin | creator (create, `Uid == auth.uid`), Uid/admin (Thread); `Notes` admin-only read+write |
| `Support/UserTickets/$uid` | owner + admin | owner + admin |
| `Support/Counter` | auth | auth, validate `newData.val() === data.val() + 1` |
| `Support/MailLog` | admin | functions/admin |
| `Insiders/$uid` | owner + admin | owner create when absent/declined (validate `Status == 'pending'`, no tier fields) + admin. **Deny writes at `/Insiders` root** (empty-uid bug guard) |
| `Referrals` | admin | functions/admin |
| `NotificationsMeta` | admin | admin/functions |
| `CategorySuggestions` | admin | auth'd create-only |
| `Admins/$uid` | that uid | nobody (console only) |
| `Fantasy/*` (new, §6) | see §6 | see §6 |
| anything not listed | **deny** | **deny** |

## 6. Fantasy node (born locked)

```
Fantasy/<sport>/<season>/
  Config            read: public      write: admin
  Players (prices/positions/eligibility)
                    read: public      write: admin/functions
  Squads/$uid       read: owner+admin write: owner (pre-lock) + admin
  PublishedPicks/<gw>/$uid
                    read: public      write: functions (copied at lock)
  History/<gw>/$uid read: public      write: functions
  Leaderboards      read: public      write: functions
  News              read: public (published), admin (drafts)
  DreamTeam/<gw>    read: public      write: functions + admin override
  Analytics         read: admin       write: functions
```

Pick-privacy before lock is enforced structurally: live `Squads/$uid` is
owner-only; the public only ever sees `PublishedPicks`/`History`, which
functions copy **at lock**. No clever rule logic needed.

## 7. App changes required (fan repo — each read re-pointed, streams only)

| Today | Becomes |
|---|---|
| `Users` root (`getAllUsers`: event attendees, search index) | `PublicProfiles` root |
| `Users/<other>` whole-node (profile page + ~14 screens incl. leaderboards, box scores, lineups, roster photo enrichment) | `PublicProfiles/<other>`; self-reads stay on `Users/<uid>` |
| `Registrations` root (navbar, frontpage, eventpage, entry page) | `RegistrationsPublic` |
| `Submissions` bucket scan (captain roster) | `Teams/<tid>/Members` mirror |
| All-registrations submissions scan (first-timer promo) | `checkFirstTimer` callable |
| All-teams join-code scan | `resolveJoinCode` callable |
| Insiders leaderboard (whole node incl. emails) | program is dormant (data wiped 2026-07-31): page shows a friendly "coming soon" empty state until the Insiders build adds its own public mirror |
| AFC vote writes to `AFC San Jose/<season>/…` (bug: misses `Seasons/`) | fixed to the real path; rules only allow the correct one |

Manager app: no read restructuring (admin reads everything by rule); verify
its login account stays in `/Admins`.

## 8. Known-accepted gaps (documented, not blocking)

Found during Phase B implementation (2026-10-27):
- **Joiner's team card:** `Teams/$tid` is captain+admin read, so joiners can't
  load the team node. Fix shipped app-side: the joiner's own submission stores
  `TeamName` (from `resolveJoinCode`) and the status page prefers it. No team
  submissions exist anywhere yet, so no migration.
- **Insiders is dormant** (data wiped 2026-07-31) and its reads go
  admin/owner-only: referral lists, cross-uid insider status, and promo-code
  checks degrade to "inactive/empty" without crashing. The **Insiders rebuild
  must move code validation + referral queries server-side** (callables or
  mirrors) — recorded as a hard prerequisite in that epic.
- `Registrations/$id/Promo` is public-read in the rules (promo config is not
  sensitive) so future promos need no rules change.
- **Support `Notes` caveat:** ticket owners technically could read
  `Tickets/$n/Notes` by direct path (read cascade; UI never shows it).
  Relocate notes to `Support/TicketNotes/<n>` (admin-only) when PR #16 merges
  — Manager-side path change only.

- Submissions carry client-set `DiscountPct/EligibleFee/FirstTimer` — the
  Manager verifies payment amounts by hand today; a validation pass can come
  with Stripe go-live work.
- Account deletion leaves `Users/<uid>` data behind (only ProfileUrl removed)
  — follow-up cleanup function.
- Email verification unenforced — future tightening, orthogonal to rules.
- Prediction `UpdatedAt` is client-clock — cosmetic.

## 9. Compatibility & rollout

- **Store 4.1.0:** fully authed; all mapped writes keep working under the
  matrix; reads keep working once §7 re-points ship in the same release wave.
  Ordering: deploy mirrors + backfill → ship app update that reads mirrors →
  flip rules. Old-but-authed builds in the gap: public reads fine; their
  `Users/<other>` profile reads fail gracefully (empty profile UI, no crash —
  verify in testing).
- **Pre-wall builds:** view-only (public reads); their writes die. Accepted.
- **Rollout:** export current rules to repo as rollback → deploy
  `database.rules.json` at a quiet hour (no live games) → REST test matrix
  (unauth read public ✓ / unauth read Users ✗ / unauth write ✗ / auth write
  own ✓ / cross-uid write ✗ / vote write ✓ / admin write ✓ / joiner Paid
  validation ✓) → owner smoke-tests both apps → instant revert available.
- Rules live in the fan repo (`database.rules.json`), deployed via
  `firebase deploy --only database` — code-reviewed history, not console
  state.

## 10. Storage rules (follow-up task in this epic)

Audit + lock Firebase Storage: public read for `Public/*`, logos, profile
images; writes owner-path (`Users/$uid/*`) or admin; support screenshots
(`support/*`) write auth'd create, read admin + matching ticket owner.

## 11. Build order (this epic)

1. ~~Write sweep~~ ✅ done 2026-10-27 (matrix above is sweep-verified).
2. Functions: PublicProfiles + RegistrationsPublic + Team Members mirrors,
   backfill script, `checkFirstTimer` + `resolveJoinCode` callables.
3. Fan app: re-point the §7 reads (streams only, iOS parity), AFC vote path
   fix, Insiders leaderboard empty state.
4. `database.rules.json` + deploy + REST test matrix + owner smoke test.
5. Storage rules.
