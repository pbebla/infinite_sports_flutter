// DB security lockdown Phase A (Task A3): pure matching logic for the two
// registration callables (src/registration_lookups.ts). NO firebase imports
// — unit-tested directly (registration_lookups_logic.test.ts).
//
// This is a 1:1 port of the fan app's client-side logic, which the lockdown
// moves server-side because the data it scans becomes unreadable:
//  - first-timer check: lib/registration/registration_service.dart
//    getAllSubmissionAnswersForMatch + lib/registration/promo_engine.dart
//    firstTimer/normalizeEmail/normalizePhoneDigits
//  - join-code match: lib/registration/registration_models.dart
//    regTeamsFromNode/RegTeam.fromNode/normalizeJoinCode/matchJoinCode
//
// Port fidelity notes (all deliberate, matching the Dart byte-for-byte):
//  - Dart's `is! Map` defensive parses skip RTDB array-coerced nodes (a
//    Dart List is not a Map); arrays are skipped here identically, so a
//    coerced node can never crash NOR change the verdict vs the old client.
//  - Dart's `??` fires only on null; a PRESENT-but-empty 'email' key shadows
//    a capitalized 'Email' key. Mirrored with JS `??` (null/undefined).
//  - Dart `v?.toString() ?? ''` stringifies ANY non-null value (a numeric
//    join code stored as 234567 matches the string '234567'). Mirrored with
//    String(v).

/** True for a plain object — arrays (RTDB integer-key coercion) and scalars
 *  are NOT maps, exactly like Dart's `is Map` on an RTDB snapshot value. */
function isPlainMap(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// ---------------------------------------------------------------------------
// Normalization (promo_engine.dart / registration_models.dart parity)
// ---------------------------------------------------------------------------

/** Trim + lowercase ("  Zaya@Example.COM " -> "zaya@example.com"). */
export function normalizeEmail(input: string): string {
  return input.trim().toLowerCase();
}

/** Digits only ("(408) 555-1234" -> "4085551234"). */
export function normalizePhoneDigits(input: string): string {
  return input.replace(/[^0-9]/g, '');
}

/** Trim + uppercase — the form every join code is stored and compared in. */
export function normalizeJoinCode(input: string): string {
  return input.trim().toUpperCase();
}

// ---------------------------------------------------------------------------
// First-timer check (getAllSubmissionAnswersForMatch + firstTimer port)
// ---------------------------------------------------------------------------

/** Walks a whole /Registrations snapshot and collects every submission's
 *  Answers map across EVERY registration — the server-side twin of
 *  RegistrationService.getAllSubmissionAnswersForMatch. Non-map nodes at any
 *  level (junk, deleted, RTDB array coercion) are skipped, never fatal. */
export function collectSubmissionAnswers(
  registrationsNode: unknown,
): Array<Record<string, unknown>> {
  const out: Array<Record<string, unknown>> = [];
  if (!isPlainMap(registrationsNode)) return out;
  for (const registration of Object.values(registrationsNode)) {
    if (!isPlainMap(registration)) continue;
    const submissions = registration['Submissions'];
    if (!isPlainMap(submissions)) continue;
    for (const submission of Object.values(submissions)) {
      if (!isPlainMap(submission)) continue;
      const answers = submission['Answers'];
      if (isPlainMap(answers)) out.push(answers);
    }
  }
  return out;
}

/** The checkFirstTimer wire shape — field-for-field the fan app's
 *  FirstTimerResult (promo_engine.dart) so the Dart side consumes it the
 *  same way: [isFirstTimer] is the decision; [matchedByEmail]/
 *  [matchedByPhone] say which signal(s) found a prior submission. */
export interface FirstTimerVerdict {
  isFirstTimer: boolean;
  matchedByEmail: boolean;
  matchedByPhone: boolean;
}

/** Deterministic-only first-time check (spec §4 port of promo_engine.dart's
 *  firstTimer): normalized [email] OR normalized [phone] matching ANY prior
 *  submission's Answers -> existing player; otherwise a first-timer. Each
 *  answers map may carry an 'email'/'Email' and/or 'phone'/'Phone' key
 *  (missing keys are simply not matched against); an empty normalized input
 *  never matches anything. Name similarity is intentionally never checked
 *  (owner-accepted paper-era win-back). */
export function firstTimerVerdict(
  email: string,
  phone: string,
  priorAnswers: Iterable<Record<string, unknown>>,
): FirstTimerVerdict {
  const normEmail = normalizeEmail(email);
  const normPhone = normalizePhoneDigits(phone);
  let matchedEmail = false;
  let matchedPhone = false;
  for (const answers of priorAnswers) {
    const subEmail = normalizeEmail(
      String(answers['email'] ?? answers['Email'] ?? ''));
    const subPhone = normalizePhoneDigits(
      String(answers['phone'] ?? answers['Phone'] ?? ''));
    if (normEmail.length > 0 && subEmail === normEmail) matchedEmail = true;
    if (normPhone.length > 0 && subPhone === normPhone) matchedPhone = true;
  }
  return {
    isFirstTimer: !(matchedEmail || matchedPhone),
    matchedByEmail: matchedEmail,
    matchedByPhone: matchedPhone,
  };
}

// ---------------------------------------------------------------------------
// Join-code resolution (regTeamsFromNode + matchJoinCode port)
// ---------------------------------------------------------------------------

/** Valid RegTeam.Status values (registration_models.dart kRegTeamStatuses);
 *  anything else parses as 'pending', exactly like RegTeam.fromNode. */
const REG_TEAM_STATUSES = ['pending', 'approved', 'rejected'] as const;

interface ParsedTeam {
  id: string;
  name: string;
  status: string;
  joinCode: string;
  codeWaivesPayment: boolean;
}

/** RegTeam.fromNode port: null for malformed nodes (non-map, empty id/Name);
 *  Status outside the known set falls back to 'pending'; JoinCode/Name
 *  stringify any non-null value. */
function parseTeam(id: string, raw: unknown): ParsedTeam | null {
  if (!isPlainMap(raw)) return null;
  const name = raw['Name'] == null ? '' : String(raw['Name']);
  if (id.length === 0 || name.length === 0) return null;
  const rawStatus = raw['Status'] == null ? 'pending' : String(raw['Status']);
  return {
    id,
    name,
    status: (REG_TEAM_STATUSES as readonly string[]).includes(rawStatus)
      ? rawStatus : 'pending',
    joinCode: raw['JoinCode'] == null ? '' : String(raw['JoinCode']),
    codeWaivesPayment: raw['CodeWaivesPayment'] === true,
  };
}

/** The resolveJoinCode wire shape. [status] carries the client's three
 *  matchJoinCode outcomes ('ok' | 'notApproved' | 'notFound') so the join
 *  code page keeps its distinct "awaiting approval" message; [found] is true
 *  ONLY for 'ok'. The matched team's identity ships ONLY on 'ok' — a
 *  pending/rejected team's code resolves to a bare status so no other
 *  team's data ever leaves the server. */
export type JoinCodeResolution =
  | {
      found: true;
      status: 'ok';
      teamId: string;
      teamName: string;
      codeWaivesPayment: boolean;
    }
  | { found: false; status: 'notApproved' | 'notFound' };

/** matchJoinCode port over a raw Registrations/{regId}/Teams snapshot:
 *  codes compare normalized (trim/uppercase, BOTH sides); teams with no
 *  code never match; an approved team always wins over a non-approved one
 *  with the same code; a code that only matches pending/rejected teams is
 *  'notApproved'. Malformed team nodes are skipped, a non-map Teams node
 *  (missing, junk, RTDB array coercion) resolves to 'notFound' — exactly
 *  what the Dart client's `is! Map` parse produced. */
export function resolveJoinCodeFromTeams(
  teamsNode: unknown,
  input: string,
): JoinCodeResolution {
  const code = normalizeJoinCode(input);
  if (code.length === 0) return { found: false, status: 'notFound' };
  if (!isPlainMap(teamsNode)) return { found: false, status: 'notFound' };

  let sawNonApproved = false;
  for (const [id, raw] of Object.entries(teamsNode)) {
    const team = parseTeam(id, raw);
    if (team === null) continue;
    if (team.joinCode.length === 0) continue;
    if (normalizeJoinCode(team.joinCode) !== code) continue;
    if (team.status === 'approved') {
      return {
        found: true,
        status: 'ok',
        teamId: team.id,
        teamName: team.name,
        codeWaivesPayment: team.codeWaivesPayment,
      };
    }
    sawNonApproved = true;
  }
  return { found: false, status: sawNonApproved ? 'notApproved' : 'notFound' };
}
