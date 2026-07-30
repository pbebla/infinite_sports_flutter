/// Pure helpers for turning a Google or Apple (auth-wall D1) sign-in
/// credential into the base `Users/<uid>` profile write for brand-new
/// sign-ups (auth-wall C2/D1 plans). Deliberately Firebase-free, mirroring
/// the pattern already used by `lib/onboarding/profile_completion.dart`, so
/// these can be unit-tested without standing up real Firebase. Kept in one
/// file (rather than a separate `apple_profile.dart`) because `combineAppleName`
/// exists specifically to feed the same `splitDisplayName` + `isNewSignInUser`
/// pair already used by Google.
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

/// Combines an Apple ID credential's `givenName`/`familyName` (auth-wall D1)
/// into a single display-name string, the same shape a Google account's
/// `displayName` already comes in — so `signInWithApple` can call
/// `user.updateDisplayName(...)` with the result and the existing
/// `splitDisplayName` path above (and the `_handleGoogleSignIn`-mirroring
/// caller in main.dart) works unchanged for Apple sign-ins too.
///
/// Apple only supplies these on the FIRST authorization for a given app;
/// every sign-in after that gets `null` for both, which is why this returns
/// `null` (rather than an empty string) when there is nothing to combine —
/// callers use that to skip the `updateDisplayName` call entirely instead of
/// clobbering a name Apple already gave a name on a prior sign-in.
/// - Both null/blank → `null`.
/// - Only one present → that one, trimmed.
/// - Both present → trimmed and joined with a single space.
String? combineAppleName(String? givenName, String? familyName) {
  final given = givenName?.trim() ?? '';
  final family = familyName?.trim() ?? '';
  if (given.isEmpty && family.isEmpty) return null;
  if (family.isEmpty) return given;
  if (given.isEmpty) return family;
  return '$given $family';
}
