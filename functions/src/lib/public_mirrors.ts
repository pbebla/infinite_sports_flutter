// DB security lockdown Phase A (Task A1): pure projection functions for the
// public mirrors that let the fan app keep reading public subsets of
// otherwise-private nodes once the rules flip to default-deny.
//
// NO firebase imports — unit-tested directly (public_mirrors.test.ts). The
// triggers that apply these projections live in src/public_mirrors_watch.ts.
//
// Spec: docs/superpowers/specs/2026-10-27-db-security-lockdown-design.md §4
// (the mirror pattern). Plan:
// docs/superpowers/plans/2026-10-27-db-lockdown-implementation.md Task A1.
//
// RTDB array coercion: both the admin SDK and the client SDKs hand back a
// JS Array/Dart List when a node's keys are mostly small integers. None of
// these nodes should ever coerce (uids and push ids), but a coerced value
// must never crash a trigger — an Array where a Map is expected is treated
// as "not a map" and projects to null (mirror deleted), matching the fan
// app's own `is! Map` defensive parses.

/** True for a plain object — the only shape RTDB hands back for a real map
 *  node. Arrays (RTDB integer-key coercion) are explicitly NOT maps. */
function isPlainMap(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** The ONLY Users/{uid} keys that ever reach PublicProfiles/{uid}. Everything
 *  else — DOB, 'Phone Number', Token, Zip, City, Gender, ReferralSource,
 *  FavoriteSports, 'Date Joined', Email, and any field added in the future —
 *  is private by construction because this is a whitelist, not a blacklist. */
export const PUBLIC_PROFILE_KEYS: readonly string[] = [
  'First Name',
  'Last Name',
  'ProfileUrl',
  'Played',
  'TournamentsPlayed',
  'Awards',
  'Information',
  'ProfileCompleted',
];

/** Whitelist copy of a Users/{uid} node for PublicProfiles/{uid}.
 *
 *  Returns null when the mirror should be DELETED: null/absent source,
 *  non-map source (including RTDB array coercion), a MERGED account (a
 *  non-empty string MergedInto, stamped on the old uid by the merge tool —
 *  plan docs/superpowers/plans/2026-11-06-merge-duplicate-accounts.md,
 *  Task 1 / design D7), or a node carrying none of the whitelisted keys
 *  (RTDB cannot store an empty node anyway, so an empty projection and a
 *  deleted mirror are the same thing).
 *  Absent whitelisted keys are omitted; present ones are copied verbatim
 *  (Information's nested map included — spec §4 lists it as public:
 *  positions/height). MergedHint, MergedAt and MergedInto are not on the
 *  whitelist and are never copied. */
export function publicProfileProjection(
  userNode: unknown,
): Record<string, unknown> | null {
  if (!isPlainMap(userNode)) return null;
  const mergedInto = userNode['MergedInto'];
  if (typeof mergedInto === 'string' && mergedInto.length > 0) return null;
  const out: Record<string, unknown> = {};
  for (const key of PUBLIC_PROFILE_KEYS) {
    const value = userNode[key];
    if (value !== undefined && value !== null) out[key] = value;
  }
  return Object.keys(out).length > 0 ? out : null;
}

/** Registrations/{regId}/Config for RegistrationsPublic/{regId}: the Config
 *  node verbatim when it is a map (spec §4 — Config is public content: fees,
 *  dates, paths), else null (delete the mirror). A shallow copy is returned
 *  so callers can never mutate the trigger's snapshot by accident. */
export function registrationConfigProjection(
  configNode: unknown,
): Record<string, unknown> | null {
  if (!isPlainMap(configNode)) return null;
  if (Object.keys(configNode).length === 0) return null;
  return { ...configNode };
}

/** The mirror entry one submission contributes to its team's Members node. */
export interface TeamMemberEntry {
  teamId: string;
  value: { DisplayName: string; Paid: boolean };
}

/** Projects a Registrations/{regId}/Submissions/{uid} node onto the
 *  Registrations/{regId}/Teams/{teamId}/Members/{uid} mirror.
 *
 *  Only submissions carrying a non-empty string TeamId (the joiner and
 *  captain paths) produce an entry; individual-path submissions (no TeamId)
 *  and null/malformed/array-coerced nodes return null. The value is EXACTLY
 *  {DisplayName, Paid} — never Answers or any other submission field —
 *  with DisplayName falling back to '' when missing/non-string and Paid
 *  true only when the node's Paid is literally true. */
export function teamMemberEntry(
  submissionNode: unknown,
): TeamMemberEntry | null {
  if (!isPlainMap(submissionNode)) return null;
  const teamId = submissionNode['TeamId'];
  if (typeof teamId !== 'string' || teamId.length === 0) return null;
  const displayName = submissionNode['DisplayName'];
  return {
    teamId,
    value: {
      DisplayName: typeof displayName === 'string' ? displayName : '',
      Paid: submissionNode['Paid'] === true,
    },
  };
}
