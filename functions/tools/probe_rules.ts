// Rules probe: evaluates the REAL Realtime Database rules, on the LOCAL
// emulator only, for the client writes and reads around the Insiders
// program, audit rows and push campaigns (2026-11-13: these nodes had no
// rule, so the Manager's approve / audit / campaign saves were refused in
// production with no message).
//
// The static contract (src/rules_contract.test.ts) proves a grant EXISTS on
// each path; this proves the rule EXPRESSIONS accept the real payloads
// (validate rules, the code regex, the create-only audit rows) and refuse
// what they must.
//
//   npm run probe:rules      (needs Java; e.g. Android Studio's jbr\bin on PATH)
//
// Never points at production: it refuses to run without
// FIREBASE_DATABASE_EMULATOR_HOST, and every id here is made up.

import * as fs from 'fs';
import * as path from 'path';

/* eslint-disable @typescript-eslint/no-explicit-any */

const HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
const NS = 'demo-rules-probe';
const ADMIN = 'uid_admin';
const OTHER_ADMIN = 'uid_admin2';
const FAN = 'uid_fan';
const APPLICANT = 'uid_applicant';

type Who = 'admin' | 'fan' | 'applicant' | 'anon';
type Verdict = 'allow' | 'deny';

interface Check {
  name: string;
  who: Who;
  method: 'GET' | 'PUT' | 'PATCH' | 'POST' | 'DELETE';
  path: string;
  body?: unknown;
  /** One verdict for both files, or per file when the postures differ
   *  (stage 1 still has the open root read). */
  expect: Verdict | { stage1: Verdict; target: Verdict };
}

function b64url(o: unknown): string {
  return Buffer.from(JSON.stringify(o)).toString('base64')
    .replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}

/** An unsigned ID token — the emulator accepts these (it never verifies
 *  signatures); production would reject it. */
function token(uid: string): string {
  const now = Math.floor(Date.now() / 1000);
  return `${b64url({ alg: 'none', typ: 'JWT' })}.${b64url({
    iss: `https://securetoken.google.com/${NS}`, aud: NS,
    iat: now, exp: now + 3600, auth_time: now, sub: uid, user_id: uid,
    firebase: { sign_in_provider: 'password', identities: {} },
  })}.`;
}

const UIDS: Record<Exclude<Who, 'anon'>, string> = {
  admin: ADMIN, fan: FAN, applicant: APPLICANT,
};

/** REST address; a signed-in user's ID token rides in `auth=` (an
 *  `Authorization: Bearer` header means an ADMIN OAuth token to RTDB, and the
 *  emulator treats any such header as the owner - rules would be skipped). */
function url(p: string, idToken?: string): string {
  const auth = idToken === undefined ? '' : `&auth=${encodeURIComponent(idToken)}`;
  return `http://${HOST}/${p}.json?ns=${NS}${auth}`;
}

async function asOwner(method: string, p: string, body?: unknown): Promise<void> {
  const res = await fetch(url(p), {
    method, headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`owner ${method} ${p} failed: ${res.status} ${await res.text()}`);
}

async function attempt(c: Check): Promise<Verdict> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  const idToken = c.who === 'anon' ? undefined : token(UIDS[c.who]);
  const res = await fetch(url(c.path, idToken), {
    method: c.method, headers,
    body: c.body === undefined ? undefined : JSON.stringify(c.body),
  });
  if (res.ok) return 'allow';
  if (res.status === 401 || res.status === 403) return 'deny';
  throw new Error(`${c.name}: unexpected HTTP ${res.status} ${await res.text()}`);
}

const TS = { '.sv': 'timestamp' };

function auditRow(adminUid: string): Record<string, unknown> {
  return {
    AdminUid: adminUid, Target: `Insiders/${APPLICANT}`, Field: 'Status',
    Old: 'pending', New: 'active', Reason: 'Application approved - code PZAB12', At: 1,
  };
}

const REG = 'Registrations/Reg-Probe';
const FS = 'Fantasy/Futsal/16';

/** RegTeam.toFirebaseMap for a new captain's team (submitCaptain). */
function appTeam(captainUid: string): Record<string, unknown> {
  return { Name: 'Probe FC', CaptainUid: captainUid, Status: 'pending', CodeWaivesPayment: false, CreatedAt: 1 };
}

/** RegSubmission.toFirebaseMap from submitJoiner on a waiving team. */
function joinerSub(teamId: string): Record<string, unknown> {
  return { Path: 'joiner', Answers: { firstName: 'Test' }, TeamId: teamId, TeamName: 'Probe FC',
    Paid: true, PaidVia: 'team code', DisplayName: 'Test Person', SubmittedAt: 1 };
}

/** Owner-seeded data for the 2026-11-13 registration / profile / fantasy checks. */
const SEED_2026_11_13 = {
  Registrations: { 'Reg-Probe': {
    Config: { Status: 'open' },
    Teams: {
      '-adminTeam': { Name: 'Approved FC', CaptainUid: 'uid_captain', Status: 'approved',
        JoinCode: 'WAIVE1', CodeWaivesPayment: true, CreatedAt: 1 },
      '-pendingWaive': { Name: 'Pending FC', CaptainUid: 'uid_captain', Status: 'pending',
        CodeWaivesPayment: true, CreatedAt: 1 },
      '-fanPending': appTeam(FAN),
    },
  } },
  Users: { [FAN]: { 'First Name': 'Test', Awards: { '-a1': { Title: 'Champion' } },
    Played: { '15': { Sport: 'Futsal', Team: 'Old' } } } },
  Fantasy: { Futsal: { '16': { Managers: { [FAN]: { TeamName: 'Rude Name', NameFlagged: true } } } } },
};

const CHECKS: Check[] = [
  // ── The owner's exact tap: approve = one atomic multi-path update ─────────
  { name: 'admin approves an application (status + code reserved, atomic)',
    who: 'admin', method: 'PATCH', path: '', expect: 'allow',
    body: {
      [`Insiders/${APPLICANT}/Status`]: 'active',
      [`Insiders/${APPLICANT}/Code`]: 'PZAB12',
      [`Insiders/${APPLICANT}/ApprovedBy`]: ADMIN,
      [`Insiders/${APPLICANT}/ApprovedAt`]: TS,
      'InsiderCodes/PZAB12': APPLICANT,
    } },
  { name: 'admin writes the audit row for it',
    who: 'admin', method: 'PUT', path: 'InsiderAudit/-row1', body: auditRow(ADMIN), expect: 'allow' },
  { name: 'an audit row cannot be rewritten afterwards',
    who: 'admin', method: 'PUT', path: 'InsiderAudit/-row1',
    body: { ...auditRow(ADMIN), Reason: 'edited later' }, expect: 'deny' },
  { name: 'an audit row cannot be deleted',
    who: 'admin', method: 'DELETE', path: 'InsiderAudit/-row1', expect: 'deny' },
  { name: "an audit row cannot carry another admin's id",
    who: 'admin', method: 'PUT', path: 'InsiderAudit/-row2', body: auditRow(OTHER_ADMIN), expect: 'deny' },
  { name: 'a code outside the 4-15 A-Z/0-9 format is refused, even for an admin',
    who: 'admin', method: 'PUT', path: 'InsiderCodes/ab', body: APPLICANT, expect: 'deny' },
  { name: 'the whole code list cannot be wiped in one call',
    who: 'admin', method: 'DELETE', path: 'InsiderCodes', expect: 'deny' },
  { name: 'admin declines / suspends (single status set)',
    who: 'admin', method: 'PUT', path: `Insiders/${APPLICANT}/Status`, body: 'suspended', expect: 'allow' },
  { name: 'admin adds a manual referral',
    who: 'admin', method: 'PUT', path: 'Referrals/-ref1',
    body: { InsiderUid: APPLICANT, ReferredUid: '', State: 'counted', CountedAt: 1 }, expect: 'allow' },
  { name: 'admin voids a referral (atomic: referral + once-ever pointer)',
    who: 'admin', method: 'PATCH', path: '', expect: 'allow',
    body: {
      'Referrals/-ref1/State': 'voided', 'Referrals/-ref1/VoidedAt': TS,
      'Referrals/-ref1/VoidReason': 'refund', 'ReferredUsers/uid_referred': null,
      [`Insiders/${APPLICANT}/TotalReferred`]: 0,
    } },
  { name: 'admin creates a push campaign',
    who: 'admin', method: 'PUT', path: 'Campaigns/-camp1',
    body: { Title: 'Game day', Body: 'See you tonight', Status: 'pending', CreatedAt: TS }, expect: 'allow' },

  // ── A regular signed-in person ────────────────────────────────────────────
  { name: 'a fan applies (their own row, pending)',
    who: 'fan', method: 'PUT', path: `Insiders/${FAN}`,
    body: { Status: 'pending', Name: 'Test Fan', Email: 'f***@example.com', AppliedAt: 1 }, expect: 'allow' },
  { name: 'a fan cannot approve themselves',
    who: 'fan', method: 'PUT', path: `Insiders/${FAN}/Status`, body: 'active', expect: 'deny' },
  { name: "a fan cannot touch someone else's application",
    who: 'fan', method: 'PUT', path: `Insiders/${APPLICANT}/Status`, body: 'declined', expect: 'deny' },
  { name: 'a fan cannot reserve a code',
    who: 'fan', method: 'PUT', path: 'InsiderCodes/HACK12', body: FAN, expect: 'deny' },
  { name: 'a fan cannot write an audit row',
    who: 'fan', method: 'PUT', path: 'InsiderAudit/-rowX', body: auditRow(FAN), expect: 'deny' },
  { name: 'a fan cannot create a push campaign',
    who: 'fan', method: 'PUT', path: 'Campaigns/-campX',
    body: { Title: 'spam', Status: 'pending' }, expect: 'deny' },
  { name: 'a fan cannot clear a once-ever referral pointer',
    who: 'fan', method: 'DELETE', path: `ReferredUsers/${FAN}`, expect: 'deny' },
  { name: 'a fan can look up ONE code (registration promo check)',
    who: 'fan', method: 'GET', path: 'InsiderCodes/PZAB12', expect: 'allow' },
  { name: 'a fan can read their own referred-by pointer',
    who: 'fan', method: 'GET', path: `ReferredUsers/${FAN}`, expect: 'allow' },
  // Reads that only close with the target posture (stage 1 = open root read).
  { name: 'a fan lists every code',
    who: 'fan', method: 'GET', path: 'InsiderCodes', expect: { stage1: 'allow', target: 'deny' } },
  { name: 'a fan reads the audit trail',
    who: 'fan', method: 'GET', path: 'InsiderAudit', expect: { stage1: 'allow', target: 'deny' } },
  { name: 'a fan reads the campaign history',
    who: 'fan', method: 'GET', path: 'Campaigns', expect: { stage1: 'allow', target: 'deny' } },

  // ── Registration: teams + the team-code payment waiver (2026-11-13) ───────
  // A registrant could mark themselves Paid by CREATING a team with
  // CodeWaivesPayment: true and pointing their submission at it. The app
  // creates exactly {Name, CaptainUid, Status:'pending',
  // CodeWaivesPayment:false, CreatedAt} (registration_service.dart
  // submitCaptain); approval, JoinCode and the waiver are the Manager's.
  { name: "a fan creates a team with the app's exact payload",
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-fanNew`, body: appTeam(FAN), expect: 'allow' },
  { name: 'a fan cannot create a team that waives payment',
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-forge1`,
    body: { ...appTeam(FAN), CodeWaivesPayment: true }, expect: 'deny' },
  { name: 'a fan cannot create an already-approved team',
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-forge2`,
    body: { ...appTeam(FAN), Status: 'approved' }, expect: 'deny' },
  { name: 'a fan cannot create a team with a join code',
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-forge3`,
    body: { ...appTeam(FAN), JoinCode: 'FREE1' }, expect: 'deny' },
  { name: "a fan cannot create a team in someone else's name",
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-forge4`, body: appTeam(APPLICANT), expect: 'deny' },
  { name: 'a captain cannot edit their team after creating it',
    who: 'fan', method: 'PUT', path: `${REG}/Teams/-fanNew/CodeWaivesPayment`, body: true, expect: 'deny' },
  { name: 'a fan cannot submit Paid:true against their own pending team',
    who: 'fan', method: 'PUT', path: `${REG}/Submissions/${FAN}`,
    body: { ...joinerSub('-fanPending'), Path: 'captain' }, expect: 'deny' },
  { name: 'a fan cannot submit Paid:true against a waiving team that is not approved',
    who: 'fan', method: 'PUT', path: `${REG}/Submissions/${FAN}`,
    body: joinerSub('-pendingWaive'), expect: 'deny' },
  { name: 'a fan cannot submit Paid:true against a missing team',
    who: 'fan', method: 'PUT', path: `${REG}/Submissions/${FAN}`,
    body: joinerSub('-nope'), expect: 'deny' },
  { name: 'a joiner of an admin-approved waiving team is born Paid (submitJoiner)',
    who: 'applicant', method: 'PUT', path: `${REG}/Submissions/${APPLICANT}`,
    body: joinerSub('-adminTeam'), expect: 'allow' },
  { name: 'a plain individual submission (Paid:false) is allowed',
    who: 'fan', method: 'PUT', path: `${REG}/Submissions/${FAN}`,
    body: { Path: 'individual', Answers: { firstName: 'Test' }, Paid: false,
      DisplayName: 'Test Fan', SubmittedAt: 1 }, expect: 'allow' },
  { name: "a captain's submission (Paid:false, own new team) is allowed",
    who: 'fan', method: 'PUT', path: `${REG}/Submissions/${FAN}`,
    body: { Path: 'captain', Answers: { firstName: 'Test' }, TeamId: '-fanNew', Paid: false,
      DisplayName: 'Test Fan', SubmittedAt: 1 }, expect: 'allow' },
  { name: 'an admin approves a team with a waiving code (Manager approveTeam)',
    who: 'admin', method: 'PATCH', path: `${REG}/Teams/-fanNew`,
    body: { Status: 'approved', JoinCode: 'TEAM12', CodeWaivesPayment: true }, expect: 'allow' },
  { name: 'an admin un-approves it (Manager unapproveTeam: nulls code + waiver)',
    who: 'admin', method: 'PATCH', path: `${REG}/Teams/-fanNew`,
    body: { Status: 'pending', JoinCode: null, CodeWaivesPayment: null }, expect: 'allow' },

  // ── Users/<uid>: trophies, history and merge stamps (2026-11-13) ──────────
  // Every real fan write under Users/<uid> (tip + store build) must still
  // land; Awards / Played / TournamentsPlayed / Merged* are admin-only.
  { name: 'Google/Apple first sign-in base profile (update)',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { 'First Name': 'Test', 'Last Name': 'Fan', 'Date Joined': '2026-11-13 10:00:00.000' }, expect: 'allow' },
  { name: 'About You (update)',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { DOB: '01/01/2000', City: 'Town', Zip: '95000', Gender: 'Prefer not to say',
      ReferralSource: 'Friend', ProfileCompleted: true, 'Phone Number': '5550000000' }, expect: 'allow' },
  { name: 'email sign-up fields + token + photo url (sets)',
    who: 'fan', method: 'PATCH', path: '',
    body: { [`Users/${FAN}/First Name`]: 'Test', [`Users/${FAN}/Last Name`]: 'Fan',
      [`Users/${FAN}/Phone Number`]: '5550000000', [`Users/${FAN}/Date Joined`]: 'x',
      [`Users/${FAN}/Token`]: 'tok', [`Users/${FAN}/ProfileUrl`]: 'https://example.com/p.jpg' },
    expect: 'allow' },
  { name: 'Information set (addUpdateInfo)',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/Information`,
    body: { Age: 20, Height: '5ft10', FutsalPosition: 'ATT', BasketballPosition: 'G' }, expect: 'allow' },
  { name: 'registration write-back (Information update)',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}/Information`,
    body: { FutsalPosition: 'DEF;ATT', Age: 21, Height: '5ft11' }, expect: 'allow' },
  { name: 'favourite sports + answered flag',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { 'FavoriteSports/Futsal': true, FavoriteSportsAnswered: true }, expect: 'allow' },
  { name: 'photo removed / favourite turned off (removes)',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { ProfileUrl: null, 'FavoriteSports/Futsal': null }, expect: 'allow' },
  { name: 'a fan cannot give themselves a trophy',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/Awards/-forged`,
    body: { Title: 'Champion', Season: '16' }, expect: 'deny' },
  { name: 'a fan cannot edit an existing trophy',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/Awards/-a1/Title`, body: 'MVP', expect: 'deny' },
  { name: 'a fan cannot slip a trophy into a profile update',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { 'First Name': 'Test', Awards: { '-forged': { Title: 'MVP' } } }, expect: 'deny' },
  { name: 'a fan cannot rewrite their whole node with forged history',
    who: 'fan', method: 'PUT', path: `Users/${FAN}`,
    body: { 'First Name': 'Test', Played: { '16': { Sport: 'Futsal', Team: 'X' } } }, expect: 'deny' },
  { name: 'a fan cannot add league history',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/Played/17`,
    body: { Sport: 'Futsal', Team: 'Champs' }, expect: 'deny' },
  { name: 'a fan cannot add tournament history',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/TournamentsPlayed/t1`, body: true, expect: 'deny' },
  { name: 'a fan cannot stamp MergedInto',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/MergedInto`, body: 'uid_other', expect: 'deny' },
  { name: 'a fan cannot stamp MergedAt',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/MergedAt`, body: 1, expect: 'deny' },
  { name: 'a fan cannot stamp MergedHint',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/MergedHint`, body: 'x***@example.com', expect: 'deny' },
  { name: 'a fan cannot stamp MergedFrom',
    who: 'fan', method: 'PUT', path: `Users/${FAN}/MergedFrom/uid_other`, body: true, expect: 'deny' },
  { name: 'an admin awards a trophy (Manager)',
    who: 'admin', method: 'PUT', path: `Users/${FAN}/Awards/-a2`,
    body: { Title: 'Champion', Season: '16' }, expect: 'allow' },
  { name: 'an admin writes league history (Manager)',
    who: 'admin', method: 'PUT', path: `Users/${FAN}/Played/16`,
    body: { Sport: 'Futsal', Team: 'Champs' }, expect: 'allow' },
  { name: 'a fan profile update still lands next to existing trophies',
    who: 'fan', method: 'PATCH', path: `Users/${FAN}`,
    body: { 'First Name': 'Renamed' }, expect: 'allow' },

  // ── Fantasy team name flag (2026-11-13) ───────────────────────────────────
  // saveTeamName always writes {TeamName, NameFlagged:false}. Operator
  // precedence let an owner write {TeamName} with NO flag key and clear an
  // admin's flag while keeping the flagged name.
  { name: 'a flagged owner cannot clear the flag by omitting NameFlagged',
    who: 'fan', method: 'PUT', path: `${FS}/Managers/${FAN}`,
    body: { TeamName: 'Rude Name' }, expect: 'deny' },
  { name: 'a flagged name cannot be re-saved unchanged',
    who: 'fan', method: 'PUT', path: `${FS}/Managers/${FAN}`,
    body: { TeamName: 'Rude Name', NameFlagged: false }, expect: 'deny' },
  { name: 'a fan cannot flag their own name',
    who: 'fan', method: 'PUT', path: `${FS}/Managers/${FAN}`,
    body: { TeamName: 'Nice Name', NameFlagged: true }, expect: 'deny' },
  { name: 'a flagged owner saves a NEW name (saveTeamName)',
    who: 'fan', method: 'PUT', path: `${FS}/Managers/${FAN}`,
    body: { TeamName: 'Nice Name', NameFlagged: false }, expect: 'allow' },
  { name: 'a first-time team name save (saveTeamName)',
    who: 'applicant', method: 'PUT', path: `${FS}/Managers/${APPLICANT}`,
    body: { TeamName: 'Fresh Team', NameFlagged: false }, expect: 'allow' },
  { name: 'a first-time save with no flag key is refused (the app always sends it)',
    who: 'applicant', method: 'PUT', path: `${FS}/Managers/${APPLICANT}`,
    body: { TeamName: 'Other Team' }, expect: 'deny' },
  { name: 'an admin flags a name (Manager setNameFlagged)',
    who: 'admin', method: 'PUT', path: `${FS}/Managers/${FAN}/NameFlagged`, body: true, expect: 'allow' },

  // ── Signed out ────────────────────────────────────────────────────────────
  { name: 'signed out: no application',
    who: 'anon', method: 'PUT', path: 'Insiders/uid_nobody',
    body: { Status: 'pending' }, expect: 'deny' },
  { name: 'signed out: no campaign',
    who: 'anon', method: 'PUT', path: 'Campaigns/-campY', body: { Title: 'x' }, expect: 'deny' },
  { name: 'signed out: no code',
    who: 'anon', method: 'PUT', path: 'InsiderCodes/ANON12', body: 'x', expect: 'deny' },
];

async function probe(file: string, which: 'stage1' | 'target'): Promise<number> {
  const rules = fs.readFileSync(path.join(__dirname, '..', '..', '..', '..', '..', file), 'utf8');
  // Fresh data + this file's rules.
  await asOwner('PUT', '.settings/rules', JSON.parse(rules));
  await asOwner('PUT', '', {
    Admins: { [ADMIN]: true, [OTHER_ADMIN]: true },
    Insiders: { [APPLICANT]: { Status: 'pending', Name: 'Test Applicant', Email: 'a***@example.com', AppliedAt: 1 } },
    ReferredUsers: { uid_referred: '-ref1', [FAN]: '-ref0' },
    ...SEED_2026_11_13,
  });
  let bad = 0;
  console.log(`\n${file}`);
  for (const c of CHECKS) {
    const want = typeof c.expect === 'string' ? c.expect : c.expect[which];
    const got = await attempt(c);
    const ok = got === want;
    if (!ok) bad++;
    console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${want.padEnd(5)} ${c.name}${ok ? '' : `  (got ${got})`}`);
  }
  return bad;
}

async function main(): Promise<void> {
  if (!HOST) {
    throw new Error('FIREBASE_DATABASE_EMULATOR_HOST is not set - this probe only runs ' +
      'against the local emulator (npm run probe:rules).');
  }
  const bad = (await probe('database.rules.stage1.json', 'stage1')) +
    (await probe('database.rules.json', 'target'));
  if (bad > 0) {
    console.log(`\nprobe:rules FAILED - ${bad} check(s) did not match`);
    process.exit(1);
  }
  console.log(`\nprobe:rules OK - ${CHECKS.length} checks x 2 rules files`);
}

main().catch((e) => {
  console.error(String(e instanceof Error ? e.message : e));
  process.exit(1);
});
