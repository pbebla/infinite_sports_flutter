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
// Dashboard progress helpers (Task F4 — spec §7 tier badge + progress bar)
// ---------------------------------------------------------------------------

/// Same ladder as [_kTierThresholds] without the leading "no tier" 0 —
/// convenient for "what's the next/previous rung" arithmetic.
const List<int> _kProgressThresholds = [5, 10, 15, 20, 25];

/// The next tier threshold to climb toward from [standing] (5/10/15/20/25).
/// Infinite has no further ceiling, so standing >=25 always returns 25.
int nextTierThreshold(int standing) {
  final s = standing < 0 ? 0 : standing;
  for (final t in _kProgressThresholds) {
    if (s < t) return t;
  }
  return 25;
}

/// The threshold already reached at/below [standing] (0 if still below
/// Bronze) — the bottom edge of the tier band [tierProgress]/[progressLabel]
/// report progress within.
int _previousTierThreshold(int standing) {
  final s = standing < 0 ? 0 : standing;
  var prev = 0;
  for (final t in _kProgressThresholds) {
    if (s >= t) {
      prev = t;
    } else {
      break;
    }
  }
  return prev;
}

/// 0..1 fraction of progress toward [nextTierThreshold] from
/// [_previousTierThreshold] — e.g. standing=7 (between Bronze-5 and
/// Silver-10) is 0.4 of the way to Silver. Infinite (standing >= 25) is
/// always 1.0 — there's no further tier to climb toward.
double tierProgress(int standing) {
  final s = standing < 0 ? 0 : standing;
  if (s >= 25) return 1.0;
  final prev = _previousTierThreshold(s);
  final next = nextTierThreshold(s);
  final span = next - prev;
  if (span <= 0) return 1.0;
  return (s - prev) / span;
}

/// Human-readable progress sentence for the dashboard header, e.g.
/// '3 of 5 referrals to Bronze', or 'Infinite reached' once standing hits
/// 25+ (spec §2 — Infinite has no ceiling to progress toward).
String progressLabel(int standing) {
  final s = standing < 0 ? 0 : standing;
  if (s >= 25) return 'Infinite reached';
  final prev = _previousTierThreshold(s);
  final next = nextTierThreshold(s);
  final targetTier = tierForStanding(s) + 1;
  final have = s - prev;
  final need = next - prev;
  return '$have of $need referrals to ${tierName(targetTier)}';
}

/// The share-sheet invite text for [code] (Task F4 — code card Share
/// button). Exact wording is owner-approved copy; keep byte-identical if
/// ever changed since it's user-facing marketing copy, not just a template.
String inviteMessage(String code) =>
    'Join Infinite Sports leagues & tournaments! Use my Insider code $code '
    'when you register. Download the app: '
    'https://play.google.com/store/apps/details?'
    'id=com.infinitesports.Infinite_Sports_App';

/// Generic newest-first sort by an extracted "counted at" timestamp —
/// doesn't require the input to be [InsiderReferral] so it's trivially unit
/// testable with plain ints, but that's exactly what
/// `InsiderService.watchMyReferrals` uses it for. Returns a new list; never
/// mutates [items].
List<T> sortReferralsNewestFirst<T>(
  List<T> items,
  int Function(T item) countedAtOf,
) {
  final sorted = List<T>.of(items)
    ..sort((a, b) => countedAtOf(b).compareTo(countedAtOf(a)));
  return sorted;
}

/// 'X of 5 this year' for the Infinite-tier annual-maintenance meter (spec
/// §2 — Infinite needs 5 counted referrals per calendar year to avoid
/// dropping to Platinum). Callers gate visibility on `insider.tier == 5`.
String infiniteMaintenanceLabel(int currentYearCount) =>
    '$currentYearCount of 5 this year';

// ---------------------------------------------------------------------------
// Insider (RTDB: /Insiders/<uid> — spec §9)
// ---------------------------------------------------------------------------

const List<String> kInsiderStatuses = [
  'pending',
  'active',
  'suspended',
  'declined',
];

/// Fan-side view of an Insider — Status, Code, Tier, CurrentStanding,
/// TotalReferred, SportsOfInterest, Name, Email (Task F2 scope), plus the
/// dashboard fields Task F4 added: CurrentYearCount (Infinite annual
/// maintenance meter) and the two opt-in flags (leaderboard row, profile
/// badge). The Manager's node carries a few more admin/audit-only fields
/// (spec §9) this model still doesn't need.
class Insider {
  final String uid;
  final String code;
  final String status; // pending | active | suspended | declined
  final int tier; // 0-5, derived/stored alongside currentStanding
  final int currentStanding; // ladder progress counter
  final int totalReferred; // lifetime; only decreases on refund-voids
  final int currentYearCount; // Infinite annual-maintenance counter
  final bool publicLeaderboardOptIn;
  final bool profileBadgeOptIn;
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
    this.currentYearCount = 0,
    this.publicLeaderboardOptIn = true,
    this.profileBadgeOptIn = true,
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
      currentYearCount: asInt(raw['CurrentYearCount']),
      // Tolerant default-true: absent (pre-F4 nodes, or never touched by
      // the owner) reads as opted IN, matching the Manager's own model.
      publicLeaderboardOptIn: raw['PublicLeaderboardOptIn'] != false,
      profileBadgeOptIn: raw['ProfileBadgeOptIn'] != false,
      sportsOfInterest: rawSports is List
          ? rawSports.map((s) => s.toString()).toList()
          : const <String>[],
      name: raw['Name']?.toString() ?? '',
      email: raw['Email']?.toString() ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// InsiderReferral (RTDB: /Referrals/<pushId> — spec §9, Task F4 fan reads)
// ---------------------------------------------------------------------------

const List<String> kInsiderReferralStates = ['counted', 'voided'];

/// Fan-side view of a single referral row for "Your referrals" (Task F4) —
/// only the fields the dashboard displays. Field names/semantics mirror the
/// Manager's InsiderReferral (lib/models/insider_models.dart) byte-for-byte
/// where they overlap; this is a separate class since the apps share no
/// code (same convention as [Insider] above).
class InsiderReferral {
  final String id; // pushId — not serialized, assigned from the node key
  final String insiderUid;
  final String referredUid; // '' for a manual admin-added referral
  final String referredName;
  final String sport;
  final String state; // counted | voided
  final bool verified; // auto-set on the referred player's first stat
  final int countedAt; // millisecondsSinceEpoch
  final int voidedAt; // millisecondsSinceEpoch, 0 until voided
  final bool manual; // admin-added rather than automation-created

  const InsiderReferral({
    required this.id,
    required this.insiderUid,
    this.referredUid = '',
    this.referredName = '',
    this.sport = '',
    this.state = 'counted',
    this.verified = false,
    this.countedAt = 0,
    this.voidedAt = 0,
    this.manual = false,
  });

  bool get isCounted => state == 'counted';
  bool get isVoided => state == 'voided';

  /// Defensive/tolerant parse; returns null when [raw] isn't a Map or is
  /// missing InsiderUid (a referral with no owning Insider is meaningless —
  /// mirrors the Manager's same guard).
  static InsiderReferral? fromFirebase(String id, Object? raw) {
    if (raw is! Map) return null;
    final insiderUid = raw['InsiderUid']?.toString() ?? '';
    if (insiderUid.isEmpty) return null;
    num? asNum(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '');
    int asInt(Object? v) => asNum(v)?.toInt() ?? 0;
    final rawState = raw['State']?.toString() ?? 'counted';
    return InsiderReferral(
      id: id,
      insiderUid: insiderUid,
      referredUid: raw['ReferredUid']?.toString() ?? '',
      referredName: raw['ReferredName']?.toString() ?? '',
      sport: raw['Sport']?.toString() ?? '',
      state: kInsiderReferralStates.contains(rawState) ? rawState : 'counted',
      verified: raw['Verified'] == true,
      countedAt: asInt(raw['CountedAt']),
      voidedAt: asInt(raw['VoidedAt']),
      manual: raw['Manual'] == true,
    );
  }
}

/// Parses a /Referrals root node into a flat list, skipping malformed
/// entries. Order is not guaranteed — sort with [sortReferralsNewestFirst]
/// before display.
List<InsiderReferral> referralsFromNode(Object? raw) {
  final out = <InsiderReferral>[];
  if (raw is Map) {
    raw.forEach((id, value) {
      final referral = InsiderReferral.fromFirebase(id.toString(), value);
      if (referral != null) out.add(referral);
    });
  }
  return out;
}

/// Sport -> count of COUNTED referrals only (a voided referral no longer
/// counts toward an Insider's tally, so it's excluded from the per-sport
/// breakdown too — spec §7 "per-sport breakdown"). Sports with no counted
/// referrals are simply absent from the map.
Map<String, int> perSportCounts(List<InsiderReferral> referrals) {
  final counts = <String, int>{};
  for (final r in referrals) {
    if (!r.isCounted) continue;
    final sport = r.sport.isEmpty ? 'Other' : r.sport;
    counts[sport] = (counts[sport] ?? 0) + 1;
  }
  return counts;
}
