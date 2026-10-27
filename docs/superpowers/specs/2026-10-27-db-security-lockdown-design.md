# Database Security Lockdown — Design (P0 of Infinite Fantasy)

**Date:** 2026-10-27 · Companion epic to `2026-10-26-infinite-fantasy-design.md` §17 P0.

## 1. Problem

RTDB rules are `.read: true, .write: true` **at the root**: the entire database
is world-readable and world-writable without signing in — including Users PII
(DOB, phone numbers, FCM tokens), registration submissions (emergency contacts),
and support tickets. Anyone with the database URL can also overwrite scores,
seasons, or wipe nodes. Fantasy creates per-user squads and must be born under
real rules, so this ships first.

## 2. Goals / non-goals

**Goals**
- Default-deny at root; every grant explicit per node.
- Genuinely public content (scores, standings, logos, events) stays
  **world-readable** so older installed versions keep *viewing* everything.
- All **writes** require auth and are scoped (own-uid paths, validated vote
  keys) or admin-gated via `/Admins`.
- PII readable only by its owner and admins.
- Cloud Functions (Admin SDK) bypass rules — unaffected.

**Non-goals (here):** restructuring existing Users fields (solved with a
mirror, below); encryption; Firestore migration. **Storage rules** are a
follow-up task inside this epic (section 8).

## 3. Admin gate

```
"adminGate": root.child('Admins').child(auth.uid).exists()
```
`/Admins/<uid>: true` already exists (owner + Manager login). The `/Admins`
node itself: readable by the signed-in user's own key only
(`Admins/$uid` read: `auth.uid == $uid`), writable by nobody (console/Admin
SDK only) — so clients can check "am I admin" without enumerating admins.

## 4. The PublicProfiles mirror (key design decision)

`Users/<uid>` mixes public display fields (name, photo, awards, played) with
private PII (DOB, Phone Number, Token, Zip, City, Gender) in one flat node.
Per-field read rules would force every profile screen into N listeners; moving
fields would mean a risky migration touching every screen.

**Instead:** a Cloud Function mirrors the public subset on every
`Users/<uid>` write to a new node:

```
PublicProfiles/<uid>: { First Name, Last Name, ProfileUrl, Played,
                        TournamentsPlayed, Awards, Information (positions,
                        height), ProfileCompleted }
```

- `PublicProfiles`: **public read**, functions-only write.
- `Users/<uid>`: read/write **owner + admin only** — one simple rule, full PII
  protection, no data migration.
- One-time backfill script seeds the mirror for all existing users.
- Both apps switch other-user profile reads to `PublicProfiles` (self reads
  keep using `Users/<uid>`). Fantasy reads manager names from it too.
- DOB stays in `Users` (private); age-dependent displays (e.g. Wonder Kid
  checks, submission age) are admin/Manager-side, which reads `Users` as admin.

## 5. Per-node rules matrix

| Node | Read | Write |
|---|---|---|
| `Current League`, `<Sport> Season`, `Futsal`, `Basketball`, `Flag Football`, `AFC San Jose`, `Tournaments`, `Logo Urls`, `Events`, `Map`, `Categories`, `Trophies`, `NotifPopUp`, `Down`, `Notifications`, `AppConfig` | public | admin |
| — game vote keys `…/Date/$d/$g/team1vote`, `team2vote` (and prediction answer paths found in the write sweep) | public | **auth'd**, validated shape |
| `PublicProfiles` (new) | public | functions only (no client rule) |
| `Users/$uid` | owner + admin | owner + admin (`Token` owner-only) |
| `Registrations/$id/Config`, `/Form` | public | admin |
| `Registrations/$id/Submissions/$uid` | owner + admin | owner (while reg. Open) + admin |
| `FormTemplates` | admin | admin |
| `Sign Ups/Rules`, `Sign Ups/Waiver` | public | admin |
| `Sign Ups/*` (rest, legacy) | admin | admin |
| `Support/Tickets/$n` | ticket's Uid + admin | creator (create), Uid/admin (thread); `Notes` admin-only read+write |
| `Support/UserTickets/$uid` | owner + admin | owner + admin |
| `Support/Counter` | auth | auth, validate `newData.isNumber() && newData.val() === data.val()+1` |
| `Support/MailLog` | admin | functions/admin |
| `NotificationsMeta` | admin | admin/functions |
| `CategorySuggestions` | admin | auth'd create-only (no edit/delete) |
| `Admins/$uid` | that uid | nobody (console only) |
| `Fantasy/*` (new, §6) | see §6 | see §6 |
| anything not listed | **deny** | **deny** |

Validation extras: votes/suggestions get `.validate` on shape; submission
writes require `auth.uid === $uid`.

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

## 7. Compatibility & rollout

- **Current store apps (4.1.0, fully authed):** unaffected for reads; writes
  (votes, tickets, registration, profile) already run signed-in. The write
  sweep (plan task 1) enumerates every fan-app write path from code —
  the matrix above is finalized against that list, not assumptions.
- **Older installs (pre-auth-wall):** keep viewing everything public; their
  anonymous writes (if any) stop working. Owner accepted this.
- **Rollout:** export current rules to the repo as rollback → deploy new rules
  at a quiet hour (no live games) → run the REST test matrix (unauth read
  public ✓ / unauth read Users ✗ / unauth write ✗ / auth write own ✓ /
  cross-uid write ✗ / admin write ✓ / vote write ✓) → owner smoke-tests both
  apps on phone + tablet → rollback file ready for instant revert.
- Rules file lives in the fan repo (`database.rules.json`) and deploys via
  `firebase deploy --only database`, so rules become code-reviewed history
  instead of console state.

## 8. Storage rules (follow-up task in this epic)

Audit + lock Firebase Storage: public read for `Public/*`, logos, profile
images; writes owner-path (`Users/$uid/*`) or admin; support screenshots
(`support/*`) write auth'd create, read admin + the matching ticket owner.

## 9. Build order (this epic)

1. **Write sweep** — grep both apps + functions for every RTDB write/read
   path; finalize the matrix against reality.
2. **PublicProfiles function + backfill + app reads switch** (both apps,
   streams only, iOS parity).
3. **Rules file + deploy + REST test matrix + owner smoke test.**
4. **Storage rules.**
