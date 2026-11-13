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
