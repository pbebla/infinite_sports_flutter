/// Pure helpers for the "About You" profile step (auth-wall B2 plan):
/// validators for the DOB/ZIP fields, the fixed referral-source options, and
/// a completeness check used to decide whether an existing signed-in user
/// still needs the one-time mandatory profile-completion prompt.
///
/// Deliberately Firebase-free so these can be unit-tested without standing
/// up real Firebase or a mocking package — mirrors the pattern already used
/// by `lib/misc/auth_gate.dart`.
library;

/// "How did you hear about us?" — single-select options shown as chips on
/// the About You page. Order matches the owner's explicit spec.
const List<String> kReferralOptions = [
  'Instagram',
  'Facebook',
  'TikTok',
  'Friend or family',
  'Flyer / promo',
  'At a game or event',
  'Google / app store search',
  'Other',
];

/// Null when [s] is exactly 5 digits; otherwise a user-facing error string.
String? validateZip(String s) {
  if (RegExp(r'^\d{5}$').hasMatch(s)) return null;
  return 'Enter a 5-digit ZIP code';
}

/// Null when [d] is present, not in the future, and no more than 120 years
/// ago; otherwise a user-facing error string.
String? validateDob(DateTime? d) {
  if (d == null) return 'Date of birth is required';
  final now = DateTime.now();
  if (d.isAfter(now)) return "Date of birth can't be in the future";
  final oldestAllowed = DateTime(now.year - 120, now.month, now.day);
  if (d.isBefore(oldestAllowed)) return 'Enter a valid date of birth';
  return null;
}

/// True only when [usersNode] is a `Users/<uid>` RTDB snapshot value (a Map)
/// that is either explicitly flagged `ProfileCompleted: true`, or already
/// carries all five About You fields (non-empty). Anything else — a missing
/// field, an empty string, or a non-Map value (including `null`, meaning the
/// node doesn't exist) — is treated as incomplete.
bool profileCompleted(dynamic usersNode) {
  if (usersNode is! Map) return false;
  if (usersNode['ProfileCompleted'] == true) return true;

  bool nonEmpty(String key) {
    final value = usersNode[key];
    return value != null && value.toString().trim().isNotEmpty;
  }

  return nonEmpty('DOB') &&
      nonEmpty('City') &&
      nonEmpty('Zip') &&
      nonEmpty('Gender') &&
      nonEmpty('ReferralSource');
}

/// True when [usersNode]'s `Phone Number` field is missing or empty — i.e.
/// this account still needs the phone-collecting variant of About You.
/// Email sign-ups always collect a phone in Step 1 (see
/// `createDatabaseLocation` in lib/misc/utility.dart), so this only ever
/// returns true for Google/Apple sign-ins, which never collect a phone
/// number at credential sign-in time. A missing/non-Map node (account
/// doesn't exist yet, or a network hiccup reading it) is treated as "still
/// needs a phone" — the safer default.
bool needsPhoneNumber(dynamic usersNode) {
  if (usersNode is! Map) return true;
  final value = usersNode['Phone Number'];
  return value == null || value.toString().trim().isEmpty;
}

/// True when `MyHomePage._setupNotificationPrefs` (lib/main.dart) — the
/// one-time "complete your profile" + favorites gate — should skip itself
/// entirely because an in-flight signup flow (email, Google, or Apple; see
/// `onboardingFlowActive` in lib/misc/utility.dart) is already driving its
/// own About You + favorites steps and will finish them itself. Running the
/// gate at the same time races the flow's own `Users/<uid>` writes: the gate
/// reads the node before the flow has written to it, decides the profile is
/// incomplete, and pushes a second, stale About You page on top of the
/// flow's own one (auth-wall F2 fix).
bool shouldSkipOnboardingGate({required bool onboardingFlowActive}) =>
    onboardingFlowActive;

/// Formats [d] as `MM/DD/YYYY`, zero-padded (the DB storage format for DOB).
String formatDob(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.month)}/${two(d.day)}/${d.year.toString().padLeft(4, '0')}';
}
