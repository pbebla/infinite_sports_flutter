// RULES CONTRACT (audit C1, 2026-10-31): every path the Manager or the fan
// app WRITES under Fantasy/ must be granted `.write` by the RTDB rules — on
// the node itself or on some ancestor (RTDB write grants cascade down; a
// deeper `.write` never grants a write made higher up). The Manager's VOID
// toggle (Voided/<gw>) and Manual-price flag (PriceChanges/<gw>/Manual)
// shipped with NO grant anywhere on their chain, so the owner's taps were
// permission_denied in production and nothing caught it. This test would
// have.
//
// The expected list is hard-coded on purpose, one entry per client write,
// with where it comes from:
//   - Manager (InfiniteSportsManagerFlutter): lib/core/constants/
//     fantasy_paths.dart helpers written by lib/services/firebase/
//     fantasy_admin_service.dart (`.set(` / `.update(` / `.remove(` /
//     `runTransaction(` — the race-safe ones go through lib/services/
//     fantasy_guarded_writes.dart's store seam, which adds no paths of its
//     own).
//   - Fan app: lib/fantasy/data/fantasy_service.dart.
// A NEW client write path must be added here, with its kind; a rules edit
// that drops a grant fails with the path's name.
//
// Kinds:
//   admin        — some `.write` on the chain is the admin gate
//                  (root.child('Admins').child(auth.uid)).
//   own          — some `.write` on the chain compares auth.uid with the
//                  wildcard bound to the path's UID segment (the writer's own
//                  uid).
//   ownerCreate  — some `.write` on the chain requires the NEW row's Owner to
//                  be auth.uid (mini-league create under a fresh push id).
//   captainCreate — some `.write` on the chain requires the NEW team's
//                  CaptainUid to be auth.uid (registration team create under
//                  a fresh push id).
//   uidCreate    — some `.write` on the chain requires the NEW row's Uid to
//                  be auth.uid (support ticket create).
//   ticketReply  — some `.write` on the chain requires the EXISTING ticket's
//                  Uid (root.child('Support').child('Tickets').child($n)) to
//                  be auth.uid (a user's reply on their own ticket).
//   signedIn     — some `.write` on the chain is exactly `auth != null`,
//                  optionally create-only (`&& !data.exists()`): any
//                  signed-in person may write and `.validate` does the rest
//                  (Support/Counter, sign-up comments, category
//                  suggestions).
//
// Both rules files are checked: database.rules.stage1.json is what firebase.json
// deploys today (live), database.rules.json the target posture — a grant must
// exist in both.

import * as fs from 'fs';
import * as path from 'path';
import { describe, expect, it } from 'vitest';
import { configFromMap, squadSize } from './lib/fantasy/fantasy_config';

type Json = Record<string, any>;
type Kind = 'admin' | 'own' | 'ownerCreate' | 'captainCreate' | 'uidCreate' | 'ticketReply' |
  'signedIn';
const ALL_KINDS: readonly Kind[] = ['admin', 'own', 'ownerCreate', 'captainCreate', 'uidCreate',
  'ticketReply', 'signedIn'];

interface ContractEntry {
  /** Root-relative RTDB path, as the client writes it. `UID` = the signed-in
   *  writer's own uid; every other segment is a representative value. */
  path: string;
  kind: Kind;
  /** Who writes it, and how. */
  note: string;
}

const S = 'Fantasy/Futsal/16'; // any <sport>/<season>

const CONTRACT: ContractEntry[] = [
  // ── Manager (admin) — fantasy_admin_service.dart ──────────────────────────
  { path: `${S}/Config`, kind: 'admin',
    note: 'setLockOverride: Config update {lockOverride, lockOverrideUntil}' },
  { path: `${S}/Config/lockHour`, kind: 'admin',
    note: 'setLockHour: set' },
  { path: `${S}/Config/Reminder`, kind: 'admin',
    note: 'saveReminderConfig: set' },
  { path: `${S}/Config/NewsAutopilot`, kind: 'admin',
    note: 'saveNewsAutopilot: set' },
  { path: `${S}/Config/NewsAutopilot/Enabled`, kind: 'admin',
    note: 'turnNewsAutopilotOff: root multi-path update (also Weekday/Hour)' },
  { path: `${S}/Config/DreamTeamPost`, kind: 'admin',
    note: 'saveDreamTeamPostConfig (legacy): set' },
  { path: `${S}/Players/Some Player/priceTenths`, kind: 'admin',
    note: 'setPlayerPrice: set' },
  { path: `${S}/Players/Some Player/eligible`, kind: 'admin',
    note: 'setPlayerEligible: set' },
  { path: `${S}/Players/Some Player`, kind: 'admin',
    note: 'setPlayerPosition: update {position, priceTenths?}' },
  { path: `${S}/Managers/someUid/NameFlagged`, kind: 'admin',
    note: 'setNameFlagged: set' },
  { path: `${S}/Voided/5`, kind: 'admin',
    note: 'setVoided: set(true) / remove() — spec §15 owner void (C1)' },
  { path: `${S}/PriceChanges/5/Manual`, kind: 'admin',
    note: 'setManualReprice: set(true) / remove() — Monday-job stand-down (C1)' },
  { path: `${S}/ScheduledPushes/-pushId`, kind: 'admin',
    note: 'scheduleManagerMessage: push().set; cancelScheduledMessage: runTransaction' },
  { path: `${S}/News/Drafts/-pushId`, kind: 'admin',
    note: 'saveDraft: push().set / runTransaction edit; discardDraft + publishDraft: root update (null)' },
  { path: `${S}/News/Drafts/-pushId/AutoPublishAt`, kind: 'admin',
    note: 'turnNewsAutopilotOff: root multi-path update (null)' },
  { path: `${S}/News/Published/-pushId`, kind: 'admin',
    note: 'composePost: push().set; publishDraft/updatePublishedPost/discardDraft: runTransaction; deletePublishedPost: remove' },
  { path: `${S}/News/Published/-pushId/At`, kind: 'admin',
    note: 'publishDraft: root update re-stamping the server At' },
  { path: 'Fantasy/BadgeCatalog/someBadge', kind: 'admin',
    note: 'createBadge: create-only runTransaction; updateBadge: update' },
  { path: 'Fantasy/BadgeCatalog/someBadge/ImageUrl', kind: 'admin',
    note: 'createBadge: set after the picture upload' },
  { path: 'Fantasy/BadgeCatalog/someBadge/Active', kind: 'admin',
    note: 'setBadgeActive: set' },
  { path: `${S}/Badges/someUid/-pushId`, kind: 'admin',
    note: 'giveBadge: push().set; removeBadgeAward: remove' },
  // Season setup + schedule (plan 2026-11-05): the owner's per-date
  // deadline override and skipped game day, under the admin Config grant.
  { path: `${S}/Config/Deadlines/10042026`, kind: 'admin',
    note: 'setDeadlineOverride: set(epoch ms) / remove()' },
  { path: `${S}/Config/SkippedDates/10042026`, kind: 'admin',
    note: 'setDateSkipped: set(true) / remove()' },

  // ── Fan app (signed-in user) — fantasy_service.dart ───────────────────────
  { path: `${S}/Squads/UID`, kind: 'own',
    note: 'saveMySquad: set the whole squad' },
  { path: `${S}/Managers/UID`, kind: 'own',
    note: 'saveTeamName: set {TeamName, NameFlagged:false}' },
  { path: `${S}/Watchlists/UID/Some Player`, kind: 'own',
    note: 'setWatchlisted: set(true) / remove()' },
  { path: `${S}/MiniLeagues/-pushId`, kind: 'ownerCreate',
    note: 'createMiniLeague: push().set {Name, Code, Owner:uid, CreatedAt, Members}' },
  { path: `${S}/MiniLeagues/-leagueId/Members/UID`, kind: 'own',
    note: 'joinMiniLeague: set(true)' },

  // ── Paid access (spec 2026-11-01) ─────────────────────────────────────────
  { path: `${S}/AccessClaims/UID/-pushId`, kind: 'own',
    note: 'fan submitAccessClaim: push().set {Method, AmountDollars, Note, At} (create-only)' },
  { path: `${S}/Config/Access`, kind: 'admin',
    note: 'Manager saveConfig: multi-path update (+ grandfathered Access rows)' },
  { path: `${S}/Access/someUid`, kind: 'admin',
    note: 'Manager grant / approve / reject / revoke: transaction + multi-path update' },
  { path: `${S}/AccessClaims/someUid/-pushId/Resolved`, kind: 'admin',
    note: 'Manager approve / reject: claim Resolved patch' },
  { path: 'Fantasy/Templates/Access/claimAdmin', kind: 'admin',
    note: 'Manager saveTemplate: set; resetTemplate: remove' },
  { path: 'Fantasy/Templates/Access/AdminEmail', kind: 'admin',
    note: 'Manager saveAdminEmail: set' },

  // ── Insiders program, audit rows, push campaigns (2026-11-13) ─────────────
  // The Oct-27 lockdown wrote rules for Insiders + Referrals only; these
  // nodes had NO rule at all, so the Manager's approve (an atomic multi-path
  // update that also reserves the code), every audit row (Insider actions and
  // manual registration fee adjustments) and every push campaign were
  // permission_denied in production with no message. Sources: Manager
  // lib/services/firebase/{insider,registration,campaign}_service.dart; fan
  // lib/misc/insider_service.dart.
  { path: 'Insiders/UID', kind: 'own',
    note: 'fan apply: set {Status: pending, Name, Email, AppliedAt}' },
  { path: 'Insiders/UID/PublicLeaderboardOptIn', kind: 'own',
    note: 'fan Insider hub opt-in toggle: set(bool)' },
  { path: 'Insiders/UID/ProfileBadgeOptIn', kind: 'own',
    note: 'fan Insider hub opt-in toggle: set(bool)' },
  { path: 'Insiders/someUid/Status', kind: 'admin',
    note: 'Manager approve: root multi-path update (Status/Code/ApprovedBy/ApprovedAt + InsiderCodes); decline/suspend/reactivate: set' },
  { path: 'Insiders/someUid/CurrentStanding', kind: 'admin',
    note: 'Manager setStanding / referral counters: update' },
  { path: 'InsiderCodes/ABCD12', kind: 'admin',
    note: 'Manager approve: the code reservation leg of the multi-path update' },
  { path: 'InsiderAudit/-pushId', kind: 'admin',
    note: 'Manager audit rows: insider_service._audit + registration_service fee / first-timer / promo audits (push().set)' },
  { path: 'Referrals/-pushId', kind: 'admin',
    note: 'Manager addManualReferral: push().set; voidReferral: root multi-path update' },
  { path: 'ReferredUsers/someUid', kind: 'admin',
    note: 'Manager voidReferral: root multi-path update (null)' },
  { path: 'Campaigns/-pushId', kind: 'admin',
    note: 'Manager createCampaign: push().set (the send itself is the functions trigger)' },

  // ── Every other fan-app client write (2026-11-13) ─────────────────────────
  // Paths resolved from the writer code; `UID` = the signed-in writer.
  // Game votes: lib/livescore.dart + lib/scorepage.dart write
  // game.databaseReference/<GameNum>/team{1,2}vote/<uid> = 1; the reference
  // is built in lib/misc/utility.dart (<sport>/<season>/Date/<date>, AFC
  // under "AFC San Jose/Seasons").
  ...(['Futsal', 'Basketball', 'Flag Football'] as const).flatMap((sport) => [
    { path: `${sport}/16/Date/10042026/0/team1vote/UID`, kind: 'own' as const,
      note: 'livescore.dart / scorepage.dart vote: set(1)' },
    { path: `${sport}/16/Date/10042026/0/team2vote/UID`, kind: 'own' as const,
      note: 'livescore.dart / scorepage.dart vote: set(1)' },
    { path: `${sport}/16/Predictions/10042026_0/UID/q1`, kind: 'own' as const,
      note: 'league_service.dart submitAnswer: set {Answer, UpdatedAt} (key = leaguePredictionMatchKey)' },
  ]),
  { path: 'AFC San Jose/Seasons/2026/Date/10042026/0/team1vote/UID', kind: 'own',
    note: 'livescore.dart / scorepage.dart AFC vote: set(1) (utility.dart builds the Seasons path)' },
  { path: 'AFC San Jose/Seasons/2026/Date/10042026/0/team2vote/UID', kind: 'own',
    note: 'livescore.dart / scorepage.dart AFC vote: set(1)' },
  { path: 'Tournaments/t1/Predictions/m1/UID', kind: 'own',
    note: 'tournament_service.dart submitPrediction: set(pred.toFirebase())' },
  { path: 'Tournaments/t1/Predictions/m1/UID/q1', kind: 'own',
    note: 'tournament_service.dart submitAnswer: set {Answer, UpdatedAt}' },
  { path: 'Events/0/Attendees/UID', kind: 'own',
    note: 'eventpage.dart attend_Clicked: set(photoURL | 1) / remove()' },
  { path: 'EventsV2/e1/Attendees/UID', kind: 'own',
    note: 'eventpage.dart attend_Clicked (v2 record): set(photoURL | 1) / remove()' },
  { path: 'EventsV2/e1/Reminders/UID', kind: 'own',
    note: 'notification_prefs.dart setEventReminder: set(true) / remove()' },
  // Users/<uid> — every real child (inventory in the 2026-11-13 rules fix
  // report): main.dart Google/Apple base profile update {First Name, Last
  // Name, Date Joined}; onboarding/about_you_page.dart update {DOB, City,
  // Zip, Gender, ReferralSource, ProfileCompleted, Phone Number?};
  // utility.dart createDatabaseLocation / uploadToken / setImage /
  // removeImage / addUpdateInfo; registration_service.dart
  // _writeBackProfile; notification_prefs.dart favourites.
  //
  // NEVER WRITE `Users/<uid>` BACK WHOLE FROM A CLIENT; UPDATE SPECIFIC KEYS.
  // Awards / Played / TournamentsPlayed / MergedInto / MergedAt / MergedHint
  // / MergedFrom carry an admin-only `.validate`, which runs on every child
  // present in the new data: a `.set()` of the whole node that re-sends a
  // person's own trophies UNCHANGED is refused. Every writer below uses
  // `.update()` or a child `.set()`; keep it that way (probe_rules.ts pins
  // the whole-node behaviour).
  { path: 'Users/UID', kind: 'own',
    note: 'main.dart + about_you_page.dart + registration_service.dart _writeBackProfile: update' },
  ...['First Name', 'Last Name', 'Phone Number', 'Date Joined', 'Token', 'ProfileUrl'].map((k) => (
    { path: `Users/UID/${k}`, kind: 'own' as const,
      note: 'utility.dart createDatabaseLocation / uploadToken / setImage / removeImage / addUpdateInfo: set / remove' })),
  { path: 'Users/UID/Information', kind: 'own',
    note: 'utility.dart addUpdateInfo: set; registration_service.dart _writeBackProfile: update' },
  { path: 'Users/UID/FavoriteSports/Futsal', kind: 'own',
    note: 'notification_prefs.dart setCategory: set(true) / remove()' },
  { path: 'Users/UID/FavoriteSportsAnswered', kind: 'own',
    note: 'notification_prefs.dart markAnswered: set(true)' },
  { path: 'Registrations/Reg-1/Submissions/UID', kind: 'own',
    note: 'registration_service.dart submitIndividual / submitCaptain / submitJoiner: set' },
  { path: 'Registrations/Reg-1/Teams/-pushId', kind: 'captainCreate',
    note: 'registration_service.dart submitCaptain: push().set {Name, CaptainUid, Status:pending, CodeWaivesPayment:false, CreatedAt}' },
  { path: 'Sign Ups/Futsal/16/NotPaid/UID', kind: 'own',
    note: 'registration_service.dart legacy dual-write + utility.dart signUpToPlay: set(displayName)' },
  { path: 'Sign Ups/Futsal/16/Paid/UID', kind: 'own',
    note: 'registration_service.dart submitJoiner on a waiving team: set(displayName)' },
  { path: 'Sign Ups/Futsal/16/Comments/Some Name', kind: 'signedIn',
    note: 'utility.dart addComment: set("<uid>:<comment>") (create-only; validate pins the uid prefix)' },
  { path: 'Support/Counter', kind: 'signedIn',
    note: 'support/support_service.dart createTicket: runTransaction(+1) (validate pins +1)' },
  { path: 'Support/Tickets/12', kind: 'uidCreate',
    note: 'support_service.dart createTicket: root multi-path update {Num, Uid, ...} under the Counter-issued integer key ($n validated numeric)' },
  { path: 'Support/UserTickets/UID/12', kind: 'own',
    note: 'support_service.dart createTicket: same multi-path update (true); $n validated numeric' },
  { path: 'Support/Tickets/12/Thread/-pushId', kind: 'ticketReply',
    note: "support_service.dart addUserReply: push().set {From:'user', Uid, Name, Text, At}" },
  { path: 'CategorySuggestions/-pushId', kind: 'signedIn',
    note: 'notification_prefs.dart submitCategorySuggestion: push().set {Text, Uid, CreatedAt}' },
];

/** The paid-access gate (spec §5) appended to the Squads/$uid and
 *  Managers/$uid .write expressions: a client save needs the season NOT in
 *  pass mode, or an active Access record for that uid. Admin SDK writes
 *  (functions) bypass rules. */
const ACCESS_GATE =
  "(root.child('Fantasy/' + $sport + '/' + $season + '/Config/Access/Mode').val() !== 'pass' || " +
  "root.child('Fantasy/' + $sport + '/' + $season + '/Access/' + $uid + '/Status').val() === 'active')";

// ── Rules walking ───────────────────────────────────────────────────────────

function repoRoot(): string {
  let dir = process.cwd();
  for (; ;) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) {
      throw new Error(`Could not find the Flutter repo root above ${process.cwd()}`);
    }
    dir = parent;
  }
}

function loadRules(file: string): Json {
  return JSON.parse(fs.readFileSync(path.join(repoRoot(), file), 'utf8'));
}

interface ChainLink {
  /** The rules node's location, wildcards as written (e.g. Squads/$uid). */
  at: string;
  write: unknown;
}

/** Every `.write` on [p]'s chain, root first, plus the wildcard bindings
 *  ($name -> path segment). A literal child wins over a $wildcard sibling,
 *  as in RTDB; segments past the deepest rules node add nothing. */
function writeChain(rules: Json, p: string): {
  links: ChainLink[]; bindings: Record<string, string>;
} {
  const links: ChainLink[] = [];
  const bindings: Record<string, string> = {};
  let node: Json | undefined = rules['rules'];
  const at: string[] = [];
  if (node && '.write' in node) links.push({ at: '/', write: node['.write'] });
  for (const seg of p.split('/')) {
    if (!node) break;
    let next: Json | undefined;
    if (Object.prototype.hasOwnProperty.call(node, seg) && !seg.startsWith('$') &&
      !seg.startsWith('.')) {
      next = node[seg];
      at.push(seg);
    } else {
      const wild = Object.keys(node).find((k) => k.startsWith('$'));
      if (wild !== undefined) {
        next = node[wild];
        bindings[wild] = seg;
        at.push(wild);
      }
    }
    if (next === undefined) break;
    node = next;
    if ('.write' in node) links.push({ at: at.join('/'), write: node['.write'] });
  }
  return { links, bindings };
}

const ADMIN_GATE = "root.child('Admins').child(auth.uid)";

function grants(kind: Kind, link: ChainLink, bindings: Record<string, string>): boolean {
  const w = link.write;
  if (typeof w !== 'string') return false; // `false` (or junk) grants nothing
  switch (kind) {
    case 'admin':
      return w.includes(ADMIN_GATE);
    case 'own': {
      const re = /auth\.uid\s*={2,3}\s*(\$\w+)|(\$\w+)\s*={2,3}\s*auth\.uid/g;
      for (const m of w.matchAll(re)) {
        if (bindings[m[1] ?? m[2]] === 'UID') return true;
      }
      return false;
    }
    case 'ownerCreate':
      return /newData\.child\('Owner'\)\.val\(\)\s*={2,3}\s*auth\.uid/.test(w);
    case 'captainCreate':
      return /newData\.child\('CaptainUid'\)\.val\(\)\s*={2,3}\s*auth\.uid/.test(w);
    case 'uidCreate':
      return /newData\.child\('Uid'\)\.val\(\)\s*={2,3}\s*auth\.uid/.test(w);
    case 'ticketReply':
      return /root\.child\('Support'\)\.child\('Tickets'\)\.child\(\$n\)\.child\('Uid'\)\.val\(\)\s*={2,3}\s*auth\.uid/
        .test(w);
    case 'signedIn':
      return /^auth != null( && !data\.exists\(\))?$/.test(w.trim());
  }
}

const RULES_FILES = ['database.rules.stage1.json', 'database.rules.json'];

for (const file of RULES_FILES) {
  describe(`rules contract: ${file}`, () => {
    const rules = loadRules(file);

    it.each(CONTRACT.map((e) => [e.path, e] as const))(
      'grants the client write %s', (p, entry) => {
        const { links, bindings } = writeChain(rules, p);
        const ok = links.some((l) => grants(entry.kind, l, bindings));
        expect(ok, `${file}: NO ${entry.kind} .write grant for client write path ` +
          `"${p}" (${entry.note}); chain .write rules seen: ` +
          `${JSON.stringify(links)}`).toBe(true);
      });

    // The C1 shape: the owner may set/remove the VOID flag and the Manual
    // flag, and nothing else under PriceChanges (the server's
    // {name: {delta}} rows are functions-only). A grant at PriceChanges/<gw>
    // or above would let an admin client rewrite the published moves.
    it('PriceChanges: admin writes ONLY <gw>/Manual (validated true), never the delta rows', () => {
      for (const p of [`${S}/PriceChanges`, `${S}/PriceChanges/5`, `${S}/PriceChanges/5/Some Player`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
      const manual = rules['rules']['Fantasy']['$sport']['$season']['PriceChanges']['$gw']['Manual'];
      expect(manual['.validate']).toBe('newData.val() === true');
    });

    // SQUAD HARDENING (audit I2/I3, owner-approved 2026-11-01): a client
    // save of Squads/<uid> must be squad-SHAPED (picks + captainId + viceId,
    // each pick playerId <= 60 / priceTenths number / bench bool, at most
    // squadSize picks) and must land BEFORE the lock by Firebase's SERVER
    // clock (`now`) — so a skewed phone clock or a REST write can't edit a
    // locked week.
    //
    // UNCOUNTED SAVES (FPL selling plan Task 5, owner 2026-11-03 "do
    // both"; fix round 1): the save trigger (recordSquadSave) counts
    // transfers only while GwState says 'open' and before lockAtUtc (or
    // under the effective 'open' override while GwState says 'open'); it
    // stands down under a 'locked' override. So a save is accepted only:
    //   - with no GwState yet (the season hasn't started);
    //   - while GwState says 'open' AND the server clock is before
    //     lockAtUtc (the counted window);
    //   - once 24 h have passed since the stored lockAtUtc while GwState
    //     still says 'locked'/'finalized' — the fan app reopens the next
    //     week exactly at lock + 24 h (gameweeks.dart currentGameweek), a
    //     sweep may flip GwState up to 15 min later, and a save refused in
    //     that gap would drop the fan's edits;
    //   - under the owner's effective 'open' lockOverride.
    // 'locked'/'finalized' before lock + 24 h used to accept saves the
    // trigger never counted (the app shows that window as locked; only a
    // REST write could use it) — now refused. Saves the trigger misses
    // (the +24 h gap, a 'locked' override before the lock, an 'open'
    // override after GwState left 'open', a failed trigger) are caught by
    // the next lock's recount, which is charged AND persisted into
    // TransferState.UsedThisGw (transfer_state.ts lockAccounting usedByUid,
    // orchestration.ts freezeLockTransferState).
    //
    // A delete (null) skips .validate, so a deadline sits on .write for
    // deletes only (`newData.exists() || <window>`): nobody wipes a squad
    // between the lock and the sweep's snapshot (the client never deletes a
    // squad; the server's own deletes bypass rules). That delete gate keeps
    // the ORIGINAL deadline group verbatim (review ruling, Task 5 — "the
    // delete gate stays"). Admin SDK writes (functions) bypass rules
    // entirely, so the Free Hit restore / chip switch-off still land.
    //
    // realizedTenths (FPL selling, spec §4) is the server's own number on
    // a LOCKED snapshot; a client may never write it on Squads/<uid> (a
    // malformed squad is snapshotted verbatim, so a planted value would
    // survive into the record). The fan app never sends it.
    //
    // KEEP IN SYNC WITH CONFIG: the pick-key regex hard-codes the squad
    // size (keys 0..squadSize-1 — RTDB lists are index-keyed, and rules have
    // no child count). It is pinned here against the futsal default
    // squadSize(Config); a Config formation change that grows the squad
    // must widen `$i.matches(/^[0-N]$/)` in BOTH rules files (single digit:
    // up to 10 picks).
    it('Squads/$uid: .validate pins the squad shape and the server-clock deadline', () => {
      const uidNode = rules['rules']['Fantasy']['$sport']['$season']['Squads']['$uid'];
      // The owner-only read grant is unchanged; the write grant is the
      // owner's, plus the deadline for deletes (a null write skips
      // .validate).
      expect(uidNode['.read']).toBe('auth != null && auth.uid == $uid');
      const w = String(uidNode['.write'] ?? '');
      expect(w.startsWith('auth != null && auth.uid == $uid && (newData.exists() || ')).toBe(true);

      const gw = "root.child('Fantasy/' + $sport + '/' + $season + '/GwState";
      const cfgP = "root.child('Fantasy/' + $sport + '/' + $season + '/Config";
      const openOverride =
        `(${cfgP}/lockOverride').val() === 'open' && ` +
        `(!${cfgP}/lockOverrideUntil').isNumber() || now < ${cfgP}/lockOverrideUntil').val()))`;
      // The squad shape (unchanged since the hardening round).
      const shape =
        "newData.hasChildren(['picks', 'captainId', 'viceId']) && " +
        "newData.child('captainId').isString() && newData.child('captainId').val().length <= 60 && " +
        "newData.child('viceId').isString() && newData.child('viceId').val().length <= 60";
      // The save window: no GwState, OR (open AND before the lock), OR (not
      // open AND 24 h past the stored lock — the app's own reopen), OR the
      // effective 'open' override — and nothing else.
      const saveWindow =
        `(!${gw}').exists() || ` +
        `(${gw}/status').val() === 'open' && now < ${gw}/lockAtUtc').val()) || ` +
        `(${gw}/status').val() !== 'open' && now >= ${gw}/lockAtUtc').val() + 86400000) || ` +
        `${openOverride})`;
      expect(uidNode['.validate'], `${file}: Squads/$uid .validate`)
        .toBe(`${shape} && ${saveWindow}`);
      // The delete gate keeps its ORIGINAL deadline group verbatim (review
      // ruling), then the paid-access gate (spec 2026-11-01 §5).
      const deleteWindow =
        `(!${gw}').exists() || ${gw}/status').val() !== 'open' || ` +
        `now < ${gw}/lockAtUtc').val() || ${openOverride})`;
      expect(w).toBe(
        `auth != null && auth.uid == $uid && (newData.exists() || ${deleteWindow}) && ${ACCESS_GATE}`);
      // A client never writes the server's realizedTenths.
      expect(uidNode['realizedTenths'], `${file}: Squads/$uid lets a client write realizedTenths`)
        .toEqual({ '.validate': false });

      const pick = String(uidNode['picks']?.['$i']?.['.validate'] ?? '');
      const n = squadSize(configFromMap({}));
      expect(n).toBeLessThanOrEqual(10); // the single-digit key regex
      expect(pick).toContain(`$i.matches(/^[0-${n - 1}]$/)`);
      expect(pick).toContain("newData.child('playerId').isString()");
      expect(pick).toContain("newData.child('playerId').val().length <= 60");
      expect(pick).toContain("newData.child('priceTenths').isNumber()");
      expect(pick).toContain("newData.child('bench').isBoolean()");
    });

    // TRANSFERS IN-APP (plan 2026-11-03 Task 2): the squad's chip is one of
    // the four chip names and nothing else (it used to be any string, so a
    // REST write could plant 'superSub' and the Wildcard / Free Hit /
    // Triple Captain / Bench Boost handling downstream would misread it).
    // `.validate` only runs on NON-null new data, so removing the field (the
    // chip switch-off / a save with no chip) stays allowed. TransferState
    // stays server-written: no client `.write` anywhere on its chain, so a
    // fan can't forge the transfer budget the app shows.
    it('Squads/$uid/chip: .validate pins the four chip names; TransferState has no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['Squads']['$uid']['chip'], `${file}: Squads/$uid/chip`).toEqual({
        '.validate':
          "newData.isString() && newData.val().matches(/^(tripleCaptain|benchBoost|wildcard|freeHit)$/)",
      });
      const ts = season['TransferState'];
      expect(ts, `${file}: no TransferState rules`).toBeDefined();
      expect(ts['.write']).toBeUndefined();
      expect(ts['$uid']['.write']).toBeUndefined();
      for (const p of [`${S}/TransferState`, `${S}/TransferState/UID`,
        `${S}/TransferState/UID/UsedThisGw`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    // PAID ACCESS (spec 2026-11-01 §4–§6, plan A5): the Squads/Managers gate
    // on both nodes; Access = admin-written, own-or-admin read; AccessClaims =
    // fan create-only with a validated shape, admin resolve; Templates/Access
    // = admin only. The fan app and the Manager are built against these.
    it('paid access: Squads/$uid and Managers/$uid .write end with the Mode/Status gate', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(String(season['Squads']['$uid']['.write']).endsWith(` && ${ACCESS_GATE}`)).toBe(true);
      // newData.exists(): the owner may never DELETE their row (a .validate
      // never runs on a delete, so delete-then-recreate cleared a flagged
      // name - 2026-11-13). Admins delete through the Managers-level grant.
      expect(season['Managers']['$uid']['.write'])
        .toBe(`auth != null && auth.uid == $uid && newData.exists() && ${ACCESS_GATE}`);
      expect(String(season['Managers']['.write'])).toContain(ADMIN_GATE);
      // The gate never leaks into .validate (validate binds admins too; an
      // admin client write to Managers/<uid>/NameFlagged must still land).
      expect(String(season['Managers']['$uid']['.validate'])).not.toContain('Config/Access');
      expect(String(season['Squads']['$uid']['.validate'])).not.toContain('Config/Access');
    });

    it('paid access: Access is admin-written, whole-node admin read, own-or-admin per uid', () => {
      const access = rules['rules']['Fantasy']['$sport']['$season']['Access'];
      expect(String(access['.read'])).toContain(ADMIN_GATE);
      expect(String(access['.write'])).toContain(ADMIN_GATE);
      expect(access['$uid']['.read'])
        .toBe("auth != null && (auth.uid == $uid || root.child('Admins').child(auth.uid).exists())");
      expect(access['$uid']['.write']).toBeUndefined(); // the fan never writes their own record
    });

    it('paid access: AccessClaims — fan create-only own claim, validated; admin resolves', () => {
      const claims = rules['rules']['Fantasy']['$sport']['$season']['AccessClaims'];
      expect(String(claims['.read'])).toContain(ADMIN_GATE);
      expect(String(claims['.write'])).toContain(ADMIN_GATE);
      expect(claims['$uid']['.read'])
        .toBe("auth != null && (auth.uid == $uid || root.child('Admins').child(auth.uid).exists())");
      expect(claims['$uid']['$key']['.write'])
        .toBe('auth != null && auth.uid == $uid && !data.exists() && newData.exists()');
      const v = String(claims['$uid']['$key']['.validate']);
      expect(v).toContain("newData.hasChildren(['Method', 'AmountDollars', 'At'])");
      expect(v).toContain("newData.child('Method').val().matches(/^(venmo|zelle)$/)");
      // Cash is recorded by an admin (Access/<uid> Via 'cash'); a fan can't claim it.
      expect(v).not.toContain('cash');
      expect(v).toContain("newData.child('AmountDollars').isNumber()");
      expect(v).toContain("newData.child('AmountDollars').val() >= 0");
      expect(v).toContain("newData.child('At').isNumber()");
      expect(v).toContain("(!newData.hasChild('Note') || (newData.child('Note').isString() && newData.child('Note').val().length <= 120))");
      // Only an admin may write the resolution / notification fields.
      expect(v).toContain(`(${ADMIN_GATE}.exists() || (!newData.hasChild('Resolved')`);
    });

    it('paid access: Fantasy/Templates/Access is admin read + write (a literal child, not a $sport)', () => {
      const templates = rules['rules']['Fantasy']['Templates']['Access'];
      expect(String(templates['.read'])).toContain(ADMIN_GATE);
      expect(String(templates['.write'])).toContain(ADMIN_GATE);
    });

    // FPL SELLING (spec §4, plan Task 3): Baselines/<uid> = { ForGw,
    // RealizedTenths, Prices } is the server's own money record (written
    // by functions at each lock + finalize). A fan reads his own (the squad
    // builder's budget), an admin reads the node, NOBODY writes — exactly
    // TransferState's shape. A client write here would forge the budget
    // the app shows.
    it('Baselines: admin reads the node, a fan reads only his own, no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      const b = season['Baselines'];
      expect(b, `${file}: no Baselines rules`).toBeDefined();
      expect(b['.read']).toBe("auth != null && root.child('Admins').child(auth.uid).exists()");
      expect(b['$uid']['.read']).toBe('auth != null && auth.uid == $uid');
      expect(b['.write']).toBeUndefined();
      expect(b['$uid']['.write']).toBeUndefined();
      expect(b).toEqual(season['TransferState']);
    });

    // LIVE (live design 2026-11-03 §5, plan Task 3): Live/** is the server's
    // provisional gameweek (Meta/Board/Players/Squads/TeamOfWeek, or the
    // settled tombstone) — any signed-in user reads it, NOBODY writes it
    // (functions only, Admin SDK). LiveBase/<gw> is its functions-only
    // settled base: admin read (TransferState's node read), no client
    // write anywhere on either chain.
    it('Live: signed-in read, no client write; LiveBase: admin read only, no client write', () => {
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['Live'], `${file}: Live`).toEqual({ '.read': 'auth != null' });
      expect(season['LiveBase'], `${file}: LiveBase`).toEqual({
        '.read': "auth != null && root.child('Admins').child(auth.uid).exists()",
      });
      expect(season['LiveBase']['.read']).toBe(season['TransferState']['.read']);
      for (const p of [`${S}/Live`, `${S}/Live/Meta`, `${S}/Live/Board/UID`,
        `${S}/Live/Squads/UID`, `${S}/LiveBase`, `${S}/LiveBase/3`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    // SEASON SETUP + SCHEDULE (plan 2026-11-05, Task 3): the Manager writes
    // the owner's Config/Deadlines/<date> and Config/SkippedDates/<date> —
    // every grant on their chain is the admin gate, so a fan can never move
    // a deadline or skip a game day. LockedWeeks/<n> = {Date, LockAtUtc,
    // Scored?} is the server's frozen-week ledger (functions only, Admin
    // SDK): any signed-in user reads it (the apps' week lists), NOBODY
    // writes it.
    it('Config/Deadlines + SkippedDates: admin write only; LockedWeeks: signed-in read, no client write', () => {
      for (const p of [`${S}/Config/Deadlines/10042026`, `${S}/Config/SkippedDates/10042026`]) {
        const { links, bindings } = writeChain(rules, p);
        const grantsSeen = links.filter((l) => typeof l.write === 'string' && l.write !== 'false');
        expect(grantsSeen.length, `${file}: no .write on ${p}`).toBeGreaterThan(0);
        for (const l of grantsSeen) {
          expect(String(l.write), `${file}: non-admin .write at ${l.at} for ${p}`)
            .toContain(ADMIN_GATE);
        }
        expect(links.some((l) => grants('own', l, bindings) ||
          grants('ownerCreate', l, bindings)), `${file}: fan grant on ${p}`).toBe(false);
      }
      const season = rules['rules']['Fantasy']['$sport']['$season'];
      expect(season['LockedWeeks'], `${file}: LockedWeeks`).toEqual({ '.read': 'auth != null' });
      for (const p of [`${S}/LockedWeeks`, `${S}/LockedWeeks/3`, `${S}/LockedWeeks/3/Scored`]) {
        const { links } = writeChain(rules, p);
        expect(links.filter((l) => typeof l.write === 'string' && l.write !== 'false'),
          `${file}: unexpected .write on ${p}`).toEqual([]);
      }
    });

    it('Voided: public read, admin write, each <gw> validated true', () => {
      const voided = rules['rules']['Fantasy']['$sport']['$season']['Voided'];
      expect(voided['.read']).toBe(true);
      expect(String(voided['.write'])).toContain(ADMIN_GATE);
      expect(voided['$gw']['.validate']).toBe('newData.val() === true');
    });
  });
}

describe('rules contract: the walker itself', () => {
  const rules = loadRules('database.rules.json');

  it('a functions-only path has no client grant (the check can fail)', () => {
    for (const p of [`${S}/History/3/someUid`, `${S}/BadgePushClaims/u/a`,
      `${S}/TransferState/UID`, `${S}/Repriced/5`, `${S}/Baselines/UID`,
      `${S}/Baselines/UID/RealizedTenths`, `${S}/Baselines/UID/Prev`,
      `${S}/Live/Board/UID`, `${S}/LiveBase/3`, `${S}/LockedWeeks/3`]) {
      const { links, bindings } = writeChain(rules, p);
      for (const kind of ALL_KINDS) {
        expect(links.some((l) => grants(kind, l, bindings)), `${p} ${kind}`).toBe(false);
      }
    }
  });

  it("paid access: a fan has no 'own' grant on their Access record or another uid's claims", () => {
    for (const p of [`${S}/Access/UID`, `${S}/AccessClaims/otherUid/-pushId`]) {
      const { links, bindings } = writeChain(rules, p);
      expect(links.some((l) => grants('own', l, bindings)), p).toBe(false);
    }
  });

  it("'own' binds to the writer's uid only — another uid's squad is not granted", () => {
    const { links, bindings } = writeChain(rules, `${S}/Squads/otherUid`);
    expect(links.some((l) => grants('own', l, bindings))).toBe(false);
  });
});

// Both files: the guard must survive the move to the target posture
// (2026-11-13: it had landed in stage 1 only).
describe.each(RULES_FILES)('rules contract: account deletion (I4) - %s', (file) => {
  const rules = loadRules(file);

  it("nobody's client writes a deleted account's Users node back - admins included (no ancestor grant)", () => {
    for (const p of ['Users/someUid', 'Users/someUid/First Name', 'Users/someUid/Information/Age']) {
      const { links } = writeChain(rules, p);
      expect(links.map((l) => l.at), p).toEqual(['Users/$uid']);
      expect(String(links[0].write)).toContain("!root.child('DeletedAccounts').child($uid).exists()");
    }
  });

  it('DeletedAccounts is functions-only: no client read or write', () => {
    expect(rules['rules']['DeletedAccounts']).toEqual({ '.read': false, '.write': false });
    const { links, bindings } = writeChain(rules, 'DeletedAccounts/someUid');
    for (const kind of ALL_KINDS) {
      expect(links.some((l) => grants(kind, l, bindings)), kind).toBe(false);
    }
  });
});

// ── Insiders / audit / campaigns shapes + the whole-node gap (2026-11-13) ───
for (const file of RULES_FILES) {
  describe(`rules contract: insiders, audit, campaigns - ${file}`, () => {
    const rules = loadRules(file)['rules'];
    const ADMIN = "auth != null && root.child('Admins').child(auth.uid).exists()";

    it('InsiderCodes: one code is readable by a signed-in user, written by admins only, never the whole list', () => {
      const node = rules['InsiderCodes'];
      expect(node['.write'], 'a node-level write would let one call wipe every code').toBeUndefined();
      expect(node['$code']['.read']).toBe('auth != null');
      expect(node['$code']['.write']).toBe(ADMIN);
      // value = the owning uid; key = the stored code format (4-15 A-Z / 0-9,
      // validateInsiderCode in both apps).
      expect(node['$code']['.validate']).toContain('newData.isString()');
      expect(node['$code']['.validate']).toContain('$code.matches(/^[A-Z0-9]{4,15}$/)');
    });

    it('InsiderAudit: rows are create-only and carry the writing admin', () => {
      const row = rules['InsiderAudit']['$id'];
      expect(rules['InsiderAudit']['.write'], 'no node-level write: history cannot be wiped').toBeUndefined();
      expect(row['.write']).toContain(ADMIN_GATE);
      expect(row['.write']).toContain('!data.exists()');
      expect(row['.validate']).toContain("newData.child('AdminUid').val() === auth.uid");
    });

    it('ReferredUsers: a person reads only their own pointer; admins write', () => {
      const node = rules['ReferredUsers'];
      expect(node['.write']).toBe(ADMIN);
      expect(node['$uid']['.read']).toBe('auth != null && auth.uid == $uid');
    });

    it('Campaigns: admin-only, per campaign', () => {
      const node = rules['Campaigns'];
      expect(node['.read']).toBe(ADMIN);
      expect(node['.write']).toBeUndefined();
      expect(node['$id']['.write']).toBe(ADMIN);
    });

    it("a non-admin has no grant on another person's Insider row, a code, an audit row or a campaign", () => {
      for (const p of ['Insiders/someUid/Status', 'InsiderCodes/ABCD12', 'InsiderAudit/-x', 'Campaigns/-x', 'ReferredUsers/someUid']) {
        const { links, bindings } = writeChain({ rules }, p);
        expect(links.some((l) => grants('own', l, bindings)), `${file}: ${p}`).toBe(false);
      }
    });

    // THE BUG CLASS: a top-level node an app reads or writes that has no
    // entry in the rules is denied wholesale (writes always; reads too once
    // the root read is gone). Scan what the apps actually reference.
    it('every top-level node the fan app references has a rules entry', () => {
      const names = fanTopLevelNodes();
      expect(names.size, 'the scan found nothing - the regex or lib/ moved').toBeGreaterThan(8);
      const missing = [...names].filter((n) => !(n in rules)).sort();
      expect(missing, `${file}: top-level nodes referenced in lib/ with NO rules entry`).toEqual([]);
    });

    const managerPaths = path.join(repoRoot(), '..', 'InfiniteSportsManagerFlutter',
      'lib', 'core', 'constants', 'firebase_paths.dart');
    it.skipIf(!fs.existsSync(managerPaths))(
      "every top-level node in the Manager's FirebasePaths has a rules entry (sibling checkout only)", () => {
        const src = fs.readFileSync(managerPaths, 'utf8');
        const names = new Set<string>();
        for (const m of src.matchAll(/static const String \w+ = '([^'/$]+)';/g)) names.add(m[1]);
        expect(names.size).toBeGreaterThan(8);
        const missing = [...names].filter((n) => !(n in rules)).sort();
        expect(missing, `${file}: Manager top-level nodes with NO rules entry`).toEqual([]);
      });
  });
}

/** Top-level RTDB node names the fan app passes straight to
 *  `FirebaseDatabase.instance.ref('<Name>…')` (interpolated first segments
 *  and Storage refs are skipped). */
function fanTopLevelNodes(): Set<string> {
  const out = new Set<string>();
  const walk = (dir: string): void => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.name.endsWith('.dart')) {
        const src = fs.readFileSync(full, 'utf8');
        for (const m of src.matchAll(/FirebaseDatabase\.instance\s*\.ref\(\s*['"]([A-Za-z][^'"/$]*)/g)) {
          out.add(m[1].trim());
        }
      }
    }
  };
  walk(path.join(repoRoot(), 'lib'));
  return out;
}

// ── Registration waiver, forged profile history, flagged names (2026-11-13) ─
// Each closes a hole verified on the emulator (functions/tools/probe_rules.ts
// proves the expressions on real payloads; these pin their shape).
const ADMIN_ONLY = "auth != null && root.child('Admins').child(auth.uid).exists()";
const USERS_ADMIN_ONLY_CHILDREN = ['Awards', 'Played', 'TournamentsPlayed', 'MergedInto',
  'MergedAt', 'MergedHint', 'MergedFrom'];
const MANAGERS_VALIDATE =
  "newData.child('TeamName').isString() && newData.child('TeamName').val().length >= 3 && " +
  "newData.child('TeamName').val().length <= 30 && " +
  "(root.child('Admins').child(auth.uid).exists() || " +
  "(newData.child('NameFlagged').exists() && newData.child('NameFlagged').val() == false && " +
  "(!data.child('NameFlagged').exists() || data.child('NameFlagged').val() != true || " +
  "newData.child('TeamName').val() != data.child('TeamName').val())))";

describe.each(RULES_FILES)('rules contract: registration, profile history, team names - %s', (file) => {
  const rules = loadRules(file)['rules'];

  // A registrant could create a team with CodeWaivesPayment: true and point
  // their own submission at it to be born Paid. The app creates exactly
  // {Name, CaptainUid, Status:'pending', CodeWaivesPayment:false, CreatedAt}
  // (registration_service.dart submitCaptain); the Manager approves, sets
  // the JoinCode and the waiver.
  it('Registrations Teams/$tid: create-only captain write; a non-admin team is pending, unwaived, codeless', () => {
    const team = rules['Registrations']['$regId']['Teams']['$tid'];
    expect(team['.write'])
      .toBe("auth != null && !data.exists() && newData.child('CaptainUid').val() == auth.uid");
    expect(team['.validate']).toBe(
      "root.child('Admins').child(auth.uid).exists() || " +
      "(newData.child('Status').val() == 'pending' && " +
      "(!newData.child('CodeWaivesPayment').exists() || newData.child('CodeWaivesPayment').val() == false) && " +
      "!newData.child('JoinCode').exists())");
    // A non-admin writes ONLY the five keys the app sends, each a scalar:
    // nothing can be planted INSIDE a team (TeamId used to be followed as a
    // path - "-evil/X"). Members is the functions' mirror (admin SDK).
    const scalar = { '.validate': "root.child('Admins').child(auth.uid).exists() || !newData.hasChildren()" };
    for (const k of ['Name', 'CaptainUid', 'Status', 'CodeWaivesPayment', 'CreatedAt']) {
      expect(team[k], `${file}: Teams/$tid/${k}`).toEqual(scalar);
    }
    expect(team['$other']).toEqual({ '.validate': ADMIN_ONLY });
    expect(team['Members']['.validate']).toBe(ADMIN_ONLY);
    expect(team['Members']['$uid']['.read']).toBe('auth != null && auth.uid == $uid');
  });

  it('Registrations Submissions/$uid: a code waiver counts only on an APPROVED waiving team, by a push-id TeamId', () => {
    const v = String(rules['Registrations']['$regId']['Submissions']['$uid']['.validate']);
    const team = "root.child('Registrations').child($regId).child('Teams').child(newData.child('TeamId').val())";
    expect(v).toContain(
      "(newData.child('TeamId').isString() && newData.child('TeamId').val().matches(/^[A-Za-z0-9_-]+$/) && " +
      `${team}.child('CodeWaivesPayment').val() == true && ${team}.child('Status').val() == 'approved')`);
    expect(v).not.toMatch(/\|\| root\.child\('Registrations'\)[^(]*\.child\('CodeWaivesPayment'\)\.val\(\) == true$/);
  });

  // Trophies, league/tournament history (mirrored to the public profile)
  // and the account-combine stamps are written by admins (Manager) and
  // Cloud Functions only. No fan-app write carries these keys (inventory in
  // the 2026-11-13 rules fix report), so a child .validate is safe. A
  // .validate never runs on a delete, so this blocks forging, not removal.
  it('Users/$uid: trophies, history and merge stamps are admin-only (validate)', () => {
    const user = rules['Users']['$uid'];
    for (const k of USERS_ADMIN_ONLY_CHILDREN) {
      expect(user[k], `${file}: Users/$uid/${k}`).toEqual({ '.validate': ADMIN_ONLY });
    }
    // Every real fan-app child of Users/<uid> has NO such rule.
    const fanChildren = CONTRACT.filter((e) => e.path.startsWith('Users/UID/'))
      .map((e) => e.path.split('/')[2]);
    expect(fanChildren.length).toBeGreaterThan(5);
    for (const k of fanChildren) {
      expect(user[k], `${file}: Users/$uid/${k} is a fan write`).toBeUndefined();
      expect(USERS_ADMIN_ONLY_CHILDREN).not.toContain(k);
    }
  });

  // saveTeamName always writes {TeamName, NameFlagged:false}. The old
  // `!exists || ==false && (...)` let an owner write {TeamName} with no
  // flag key (precedence: `||` before `&&`-group) and clear an admin's flag
  // while keeping the flagged name. The non-admin branch now requires the
  // flag key, false, AND (not flagged before OR a new name).
  it('Fantasy Managers/$uid: explicit parentheses; a flagged name cannot be re-saved unchanged', () => {
    const v = rules['Fantasy']['$sport']['$season']['Managers']['$uid']['.validate'];
    expect(v).toBe(MANAGERS_VALIDATE);
  });
});

// ── Support ticket keys are ticket numbers (2026-11-13) ─────────────────────
// Support/Tickets/$n accepted ANY key and the server mails that key as the
// "ticket number" (subject + body). The app only creates under the integer
// the Support/Counter transaction issued (support_service.dart createTicket,
// one multi-path update with the fan's UserTickets/<uid>/<n> index entry).
// A .validate on $n also runs for every write below it, so admin status /
// close / reply / note writes and the fan's Thread replies still need a
// numeric ticket - which every real ticket is.
const TICKET_KEY = '$n.matches(/^[0-9]{1,9}$/)';
describe.each(RULES_FILES)('rules contract: support ticket keys - %s', (file) => {
  const support = loadRules(file)['rules']['Support'];

  it('Support/Tickets/$n and Support/UserTickets/$uid/$n accept only a 1-9 digit key', () => {
    expect(support['Tickets']['$n']['.validate']).toBe(TICKET_KEY);
    expect(support['UserTickets']['$uid']['$n']).toEqual({ '.validate': TICKET_KEY });
    // The grants themselves are unchanged.
    expect(support['Tickets']['$n']['.write'])
      .toBe("auth != null && !data.exists() && newData.child('Uid').val() == auth.uid");
    expect(support['UserTickets']['$uid']['.write'])
      .toBe("auth != null && (auth.uid == $uid || root.child('Admins').child(auth.uid).exists())");
  });
});
