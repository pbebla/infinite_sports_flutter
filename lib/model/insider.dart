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

/// Parses an /Insiders root node into {uid: Insider}, skipping malformed
/// entries. Byte-identical semantics to the Manager's insidersFromNode
/// (lib/models/insider_models.dart) — used by the public leaderboard
/// (Task F6) via `InsiderService.watchAllInsiders`.
Map<String, Insider> insidersFromNode(Object? raw) {
  final out = <String, Insider>{};
  if (raw is Map) {
    raw.forEach((uid, value) {
      final insider = Insider.fromFirebase(uid.toString(), value);
      if (insider != null) out[uid.toString()] = insider;
    });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Profile "Infinite Insider" box (Task F7 — spec §7 privacy paragraph)
// ---------------------------------------------------------------------------

/// The exact "Status:" line value for the public profile box: tier 0 (an
/// approved Insider who hasn't reached Bronze yet) reads as plain 'Insider'
/// rather than an empty string; tiered Insiders show their tier name.
String profileStatusLabel(int tier) => tier == 0 ? 'Insider' : tierName(tier);

// ---------------------------------------------------------------------------
// Public leaderboard (Task F6 — spec §8)
// ---------------------------------------------------------------------------

/// Period scope for the leaderboard's ranking + program stats. All-time
/// ranks by each Insider's lifetime `TotalReferred`; the other two derive
/// their count from the `/Referrals` list's `CountedAt` timestamps.
enum LeaderboardPeriod { allTime, thisYear, thisMonth }

/// True when [countedAtMs] (a `CountedAt` epoch-ms timestamp) falls within
/// [period]'s window as measured from [nowMs] — both interpreted as UTC so
/// the result doesn't depend on the device's local timezone (matches the
/// epoch-ms values `/Referrals/*/CountedAt` actually stores). All-time is
/// always "within".
bool _withinPeriod(int countedAtMs, LeaderboardPeriod period, int nowMs) {
  if (period == LeaderboardPeriod.allTime) return true;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  final counted = DateTime.fromMillisecondsSinceEpoch(countedAtMs, isUtc: true);
  if (counted.year != now.year) return false;
  if (period == LeaderboardPeriod.thisYear) return true;
  return counted.month == now.month;
}

/// One ranked row on the public leaderboard (spec §8): display name, tier,
/// the referral count the row is ranked/sorted by (already period- and
/// sport-filtered), and a per-sport breakdown (period-filtered, but NEVER
/// narrowed by the sport filter — the breakdown line is meant to show the
/// Insider's full cross-sport spread for context even while a single sport
/// is selected for ranking).
class LeaderboardRow {
  final String uid;
  final String name;
  final int tier;
  final int referralCount;
  final Map<String, int> perSport;

  const LeaderboardRow({
    required this.uid,
    required this.name,
    required this.tier,
    required this.referralCount,
    required this.perSport,
  });
}

/// Builds the ranked, filtered public leaderboard (spec §8) from the live
/// `/Insiders` and `/Referrals` streams (`InsiderService.watchAllInsiders`,
/// `watchAllReferrals`). Pure/deterministic given [nowMs] — no wall-clock
/// reads — so it's directly unit-testable.
///
/// Eligibility: only `Status == active` AND `PublicLeaderboardOptIn == true`
/// Insiders ever appear (opt-out is fully respected — an opted-out Insider
/// is simply never in the returned list, not merely hidden). [tierFilter],
/// when given, further restricts to insiders at exactly that tier.
///
/// Ranking count:
/// - [periodFilter] `allTime` with no [sportFilter]: the Insider's lifetime
///   `TotalReferred` (spec §2 — the canonical lifetime counter, already
///   void-adjusted).
/// - Otherwise (a sport filter is set, and/or the period is narrower than
///   all-time): counted straight from [referrals] — `State == counted`,
///   matching [sportFilter] when set, and matching [periodFilter]'s
///   `CountedAt` window when not all-time. This is required because
///   `TotalReferred` is a single cross-sport lifetime number and can't
///   answer "how many Futsal referrals" or "how many this month".
///
/// Sort: referral count descending, ties broken by name ascending (a
/// deterministic tie-break, not dependent on input order).
List<LeaderboardRow> leaderboardRows({
  required List<Insider> insiders,
  required List<InsiderReferral> referrals,
  LeaderboardPeriod periodFilter = LeaderboardPeriod.allTime,
  String? sportFilter,
  int? tierFilter,
  required int nowMs,
}) {
  final hasSportFilter = sportFilter != null && sportFilter.isNotEmpty;
  final rows = <LeaderboardRow>[];

  for (final insider in insiders) {
    if (!insider.isActive || !insider.publicLeaderboardOptIn) continue;
    if (tierFilter != null && insider.tier != tierFilter) continue;

    final counted = referrals.where(
        (r) => r.insiderUid == insider.uid && r.isCounted);
    final inPeriod = counted
        .where((r) => _withinPeriod(r.countedAt, periodFilter, nowMs))
        .toList();

    final int referralCount;
    if (periodFilter == LeaderboardPeriod.allTime && !hasSportFilter) {
      referralCount = insider.totalReferred;
    } else {
      referralCount = inPeriod
          .where((r) => !hasSportFilter || r.sport == sportFilter)
          .length;
    }

    rows.add(LeaderboardRow(
      uid: insider.uid,
      name: insider.name,
      tier: insider.tier,
      referralCount: referralCount,
      perSport: perSportCounts(inPeriod),
    ));
  }

  rows.sort((a, b) {
    final byCount = b.referralCount.compareTo(a.referralCount);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return rows;
}

/// Program-wide stats for the leaderboard header (spec §8): total active
/// Insiders, total (currently-counted, i.e. void-adjusted) referrals across
/// the whole program, and how many of those were counted this UTC month.
/// Unlike [leaderboardRows], these aggregate numbers don't expose any
/// individual Insider's identity, so they are NOT gated by
/// `PublicLeaderboardOptIn`.
class ProgramStats {
  final int totalInsiders;
  final int totalReferrals;
  final int thisMonth;

  const ProgramStats({
    required this.totalInsiders,
    required this.totalReferrals,
    required this.thisMonth,
  });
}

ProgramStats programStats(
  List<Insider> insiders,
  List<InsiderReferral> referrals,
  int nowMs,
) {
  final totalInsiders = insiders.where((i) => i.isActive).length;
  final counted = referrals.where((r) => r.isCounted).toList();
  final thisMonth = counted
      .where((r) =>
          _withinPeriod(r.countedAt, LeaderboardPeriod.thisMonth, nowMs))
      .length;
  return ProgramStats(
    totalInsiders: totalInsiders,
    totalReferrals: counted.length,
    thisMonth: thisMonth,
  );
}
