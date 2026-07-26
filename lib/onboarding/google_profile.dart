/// Pure helpers for turning a Google Sign-In credential into the base
/// `Users/<uid>` profile write for brand-new Google sign-ups (auth-wall C2
/// plan). Deliberately Firebase-free, mirroring the pattern already used by
/// `lib/onboarding/profile_completion.dart`, so these can be unit-tested
/// without standing up real Firebase.
library;

/// Splits a Google account's `displayName` into a first/last name pair for
/// the base profile write, matching the shape `createDatabaseLocation`
/// (lib/misc/utility.dart) writes for email signups ('First Name' / 'Last
/// Name'):
/// - `null`, empty, or whitespace-only → both empty strings.
/// - A single token (e.g. "Cher") → that token as the first name, empty
///   last name.
/// - Multiple tokens → the first token is the first name; everything else
///   (rejoined with single spaces) is the last name, so "Mary Jane Watson"
///   splits to first: "Mary", last: "Jane Watson".
({String first, String last}) splitDisplayName(String? displayName) {
  final trimmed = displayName?.trim() ?? '';
  if (trimmed.isEmpty) return (first: '', last: '');
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) return (first: parts.first, last: '');
  return (first: parts.first, last: parts.sublist(1).join(' '));
}

/// New-vs-returning decision for a Google (or future Apple) credential
/// sign-in. True ("this is a new user — write the base profile") when
/// EITHER signal says so: Firebase's own `additionalUserInfo.isNewUser`, or
/// — as a defensive fallback, since a `Users/<uid>` node genuinely missing
/// is the thing that actually matters to this app — the RTDB node not
/// existing yet.
bool isNewSignInUser({
  required bool isNewUserFlag,
  required bool usersNodeExists,
}) {
  return isNewUserFlag || !usersNodeExists;
}
