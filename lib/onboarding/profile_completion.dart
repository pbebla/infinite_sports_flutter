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

/// Formats [d] as `MM/DD/YYYY`, zero-padded (the DB storage format for DOB).
String formatDob(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.month)}/${two(d.day)}/${d.year.toString().padLeft(4, '0')}';
}
