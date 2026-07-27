// Pure fan-side Infinite Insiders model + tier helpers (Task F2).
//
// NO Flutter/Firebase imports — unit-tested directly
// (test/insider_model_test.dart). Mirrors the parsing conventions of
// lib/registration/registration_models.dart (tolerant fromFirebase parsers)
// and byte-mirrors the THREE tier pure functions from the Manager's
// lib/models/insider_models.dart (read-only reference, not imported —
// the apps share no code; see that file's own header comment).
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md
// §2 (tiers), §7 (fan experience), §9 (RTDB data shape).

// ---------------------------------------------------------------------------
// Tiers (spec §2) — byte-identical logic to the Manager's insider_models.dart
// ---------------------------------------------------------------------------

/// Ladder thresholds, index == tier (index 0 is "no tier", unused as a
/// threshold). Tier N is reached at CurrentStanding >= _kTierThresholds[N]
/// for N in 1..5.
const List<int> _kTierThresholds = [0, 5, 10, 15, 20, 25];

const List<String> _kTierNames = [
  '',
  'Bronze',
  'Silver',
  'Gold',
  'Platinum',
  'Infinite',
];

const List<int> _kTierDiscountPct = [0, 5, 10, 15, 20, 25];

/// Maps a ladder-progress counter to a tier 0-5 (0 = no tier, below Bronze).
/// Bronze >=5, Silver >=10, Gold >=15, Platinum >=20, Infinite >=25+.
int tierForStanding(int standing) {
  var tier = 0;
  for (var t = 1; t < _kTierThresholds.length; t++) {
    if (standing >= _kTierThresholds[t]) tier = t;
  }
  return tier;
}

/// Display name for a tier (0 = ''), e.g. tierName(1) == 'Bronze'.
/// Out-of-range tiers return ''.
String tierName(int tier) =>
    (tier >= 0 && tier < _kTierNames.length) ? _kTierNames[tier] : '';

/// The Insider's own-registration-fee discount percent for a tier.
/// Out-of-range tiers return 0.
int tierDiscountPct(int tier) =>
    (tier >= 0 && tier < _kTierDiscountPct.length) ? _kTierDiscountPct[tier] : 0;

/// The trimmed/uppercased form every Insider code is stored and compared in
/// (Task F3 — code entry on the registration form). Byte-identical rule to
/// the Manager's normalizeInsiderCode (lib/models/insider_models.dart) —
/// codes are generated/approved there and looked up here, so both sides
/// must agree on canonical form.
String normalizeInsiderCode(String input) => input.trim().toUpperCase();

// ---------------------------------------------------------------------------
// Insider (RTDB: /Insiders/<uid> — spec §9)
// ---------------------------------------------------------------------------

const List<String> kInsiderStatuses = [
  'pending',
  'active',
  'suspended',
  'declined',
];

/// Fan-side view of an Insider — only the fields the fan app reads/writes
/// (Task F2 scope): Status, Code, Tier, CurrentStanding, TotalReferred,
/// SportsOfInterest, Name, Email. The Manager's node carries more (audit
/// trail fields, opt-ins, etc. — see spec §9); this model ignores those.
class Insider {
  final String uid;
  final String code;
  final String status; // pending | active | suspended | declined
  final int tier; // 0-5, derived/stored alongside currentStanding
  final int currentStanding; // ladder progress counter
  final int totalReferred; // lifetime; only decreases on refund-voids
  final List<String> sportsOfInterest;

  // Written by the fan app at apply time (Task F2) so the Manager inbox has
  // something human-readable to show — see Manager's insider_models.dart
  // header note.
  final String name;
  final String email;

  const Insider({
    required this.uid,
    this.code = '',
    this.status = 'pending',
    this.tier = 0,
    this.currentStanding = 0,
    this.totalReferred = 0,
    this.sportsOfInterest = const [],
    this.name = '',
    this.email = '',
  });

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isDeclined => status == 'declined';

  /// Defensive/tolerant parse; returns null only when [raw] isn't a Map at
  /// all (a present-but-empty node still parses to an all-defaults Insider).
  static Insider? fromFirebase(String uid, Object? raw) {
    if (raw is! Map) return null;
    num? asNum(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '');
    int asInt(Object? v, [int fallback = 0]) => asNum(v)?.toInt() ?? fallback;
    final rawStatus = raw['Status']?.toString() ?? 'pending';
    final rawSports = raw['SportsOfInterest'];
    return Insider(
      uid: uid,
      code: raw['Code']?.toString() ?? '',
      status: kInsiderStatuses.contains(rawStatus) ? rawStatus : 'pending',
      tier: asInt(raw['Tier']),
      currentStanding: asInt(raw['CurrentStanding']),
      totalReferred: asInt(raw['TotalReferred']),
      sportsOfInterest: rawSports is List
          ? rawSports.map((s) => s.toString()).toList()
          : const <String>[],
      name: raw['Name']?.toString() ?? '',
      email: raw['Email']?.toString() ?? '',
    );
  }
}
