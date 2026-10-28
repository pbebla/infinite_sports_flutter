// Client-side team-name check (P3a feedback, spec §10b): length 3–30 plus a
// modest English profanity blocklist with leetspeak folding. Pure Dart, fully
// unit-tested (test/fantasy/name_check_test.dart).
//
// Design choices, deliberately conservative (the owner moderates server-side
// via NameFlagged — this check only catches the obvious up front, so a false
// NEGATIVE is fine and a false POSITIVE on a normal name is not):
// - Two tiers: unambiguous terms match as SUBSTRINGS of the normalized,
//   letters-only input (catches "Sh1tSquad", "s h i t"); shorter/ambiguous
//   terms match whole words only (so "Spice Boys" or "Fagerberg" style names
//   don't trip on embedded letters).
// - Mild words (ass, hell, damn) and profanity that collides with real names
//   (dick, cock, kike — a common Spanish nickname) are left OFF the list.
// - Scunthorpe problem: known-clean words are stripped as whole tokens
//   before the substring scan, so "Scunthorpe-free" passes while
//   "xscunthorpecuntx" still fails.

/// Verdict of [checkTeamName]: [ok] with a human [reason] when rejected.
class NameCheckResult {
  const NameCheckResult.ok()
      : ok = true,
        reason = null;
  const NameCheckResult.bad(this.reason) : ok = false;

  final bool ok;
  final String? reason;
}

/// Min/max team-name length — mirrors the live RTDB validate rule on
/// `Fantasy/<sport>/<season>/Managers/<uid>/TeamName`.
const int kTeamNameMinLength = 3;
const int kTeamNameMaxLength = 30;

const String _kLengthReason =
    'Team names are $kTeamNameMinLength–$kTeamNameMaxLength characters.';
const String _kBlockedReason =
    "That name isn't allowed — pick something league-friendly.";

/// Unambiguous terms: a hit anywhere in the normalized letters-only string
/// blocks the name.
const List<String> _substringBlocklist = [
  'fuck', 'shit', 'bitch', 'cunt', 'nigger', 'nigga', 'faggot',
  'asshole', 'wanker', 'dickhead', 'hitler',
];

/// Ambiguous/short terms: blocked only as a whole word, never embedded
/// ("Spice", "Twatson"-style surnames stay fine... mostly).
const List<String> _wordBlocklist = [
  'fag', 'spic', 'slut', 'whore', 'twat', 'retard', 'nazi',
];

/// Whole tokens stripped before the substring scan — the Scunthorpe fix.
const Set<String> _cleanTokenAllowlist = {'scunthorpe'};

/// Leetspeak folding applied after lowercasing: common digit/symbol
/// substitutions become the letters they imitate.
const Map<String, String> _leetMap = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's',
  '7': 't', '8': 'b', '@': 'a', r'$': 's', '!': 'i',
};

/// Validates a fantasy team name: trims, enforces 3–30 chars, then runs the
/// profanity check (case-insensitive, leetspeak-folded).
NameCheckResult checkTeamName(String raw) {
  final name = raw.trim();
  if (name.length < kTeamNameMinLength || name.length > kTeamNameMaxLength) {
    return const NameCheckResult.bad(_kLengthReason);
  }
  return containsBlockedWord(name)
      ? const NameCheckResult.bad(_kBlockedReason)
      : const NameCheckResult.ok();
}

/// The profanity core, exposed for tests: true when [raw] hits the blocklist
/// after normalization.
bool containsBlockedWord(String raw) {
  var folded = raw.toLowerCase();
  _leetMap.forEach((from, to) => folded = folded.replaceAll(from, to));

  // Tokens: runs of letters after folding (digits/punctuation separate).
  final tokens = folded
      .split(RegExp(r'[^a-z]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  for (final t in tokens) {
    if (_wordBlocklist.contains(t)) return true;
  }

  // Letters-only collapse (clean tokens removed whole) catches spaced-out
  // and punctuated spellings: "s h i t", "f.u.c.k".
  final collapsed =
      tokens.where((t) => !_cleanTokenAllowlist.contains(t)).join();
  for (final term in _substringBlocklist) {
    if (collapsed.contains(term)) return true;
  }
  return false;
}
