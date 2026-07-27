// Pure Insider promo-code + first-timer engine (Infinite Insiders program,
// Fan Task F3 — Phase P2).
//
// NO Flutter/Firebase imports — unit-tested directly
// (test/promo_engine_test.dart). The async lookups this engine's callers
// need (code -> uid, Insider status, once-ever guard, prior submissions)
// live in lib/misc/insider_service.dart and
// lib/registration/registration_service.dart; this file only holds the
// deterministic decision logic so it can be TDD'd without Firebase.
//
// Spec: docs/superpowers/specs/2026-07-27-infinite-insiders-design.md §3
// (referral lifecycle incl. once-ever rule + error copy), §4 (first-timer
// promo engine), §5 (discount stacking/ceiling), §9 (RTDB data shape). Plan:
// docs/superpowers/plans/2026-07-27-infinite-insiders.md Task F3.

import 'package:infinite_sports_flutter/model/insider.dart'
    show tierForStanding, tierName;
import 'package:infinite_sports_flutter/registration/payment_adjustment.dart'
    show adjustedOwed;

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

/// Trims and lowercases an email for deterministic first-timer/account
/// matching ("  Zaya@Example.COM " -> "zaya@example.com").
String normalizeEmail(String input) => input.trim().toLowerCase();

/// Keeps digits only, matching lib/registration/registration_models.dart's
/// normalizePhone (kept as a separate, byte-simple function here so this
/// pure-engine file has no dependency on the question-engine model file).
String normalizePhoneDigits(String input) =>
    input.replaceAll(RegExp(r'[^0-9]'), '');

// ---------------------------------------------------------------------------
// Per-registration promo config (spec §9 /Registrations/<regId>/Promo)
// ---------------------------------------------------------------------------

/// Whether a per-registration first-timer promo is currently redeemable.
/// [start]/[end] are inclusive bounds; either may be null (no bound).
/// [maxRedemptions] null means unlimited; otherwise the promo is exhausted
/// once [used] reaches it.
bool promoActiveNow({
  required bool enabled,
  DateTime? start,
  DateTime? end,
  int? maxRedemptions,
  required int used,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (start != null && now.isBefore(start)) return false;
  if (end != null && now.isAfter(end)) return false;
  if (maxRedemptions != null && used >= maxRedemptions) return false;
  return true;
}

/// [eligibleFee] discounted by [pct] percent, clamped to zero or more and
/// rounded to the nearest cent (a promo discount is always a plain
/// percentage off, unlike the manual-adjustment absolute-amount mode in
/// payment_adjustment.dart).
double promoDiscountedTotal(double eligibleFee, double pct) {
  final raw = eligibleFee * (1 - pct / 100);
  final clamped = raw < 0 ? 0.0 : raw;
  return (clamped * 100).round() / 100;
}

/// Defensive/tolerant parse of `/Registrations/<regId>/Promo` (spec §9).
/// M3 (the Manager's promo-config editor) has not shipped yet, so this must
/// never throw: a missing or malformed node parses to an all-defaults,
/// DISABLED promo rather than null.
class RegPromo {
  final bool enabled;
  final double percent;
  final DateTime? start;
  final DateTime? end;
  final int? maxRedemptions;
  final int used;

  const RegPromo({
    this.enabled = false,
    this.percent = 0,
    this.start,
    this.end,
    this.maxRedemptions,
    this.used = 0,
  });

  static DateTime? _dateTime(Object? v) {
    if (v == null) return null;
    final ms = v is num ? v.toInt() : int.tryParse(v.toString());
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Never null — absent/junk nodes parse to a disabled promo (this task's
  /// defensive-parse requirement: "absent node = promo disabled").
  static RegPromo fromFirebase(Object? raw) {
    if (raw is! Map) return const RegPromo();
    double asDouble(Object? v, [double fallback = 0]) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    int? asIntOrNull(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return RegPromo(
      enabled: raw['Enabled'] == true,
      percent: asDouble(raw['Percent']),
      start: _dateTime(raw['Start']),
      end: _dateTime(raw['End']),
      maxRedemptions: asIntOrNull(raw['MaxRedemptions']),
      used: asIntOrNull(raw['Used']) ?? 0,
    );
  }

  /// Convenience wrapper around [promoActiveNow] using this config's fields.
  bool activeAt(DateTime now) => promoActiveNow(
        enabled: enabled,
        start: start,
        end: end,
        maxRedemptions: maxRedemptions,
        used: used,
        now: now,
      );
}

// ---------------------------------------------------------------------------
// Code validation chain (spec §3, §11 edge cases)
// ---------------------------------------------------------------------------

/// Every outcome [evaluateCode] can return.
enum CodeCheckStatus { ok, invalid, suspended, selfReferral, alreadyReferred }

const String kCodeInvalidMessage = 'Invalid code';
const String kCodeSuspendedMessage = 'This code is not active right now';
const String kCodeSelfReferralMessage = "You can't use your own code";
const String kCodeAlreadyReferredMessage =
    'A referral code has already been used on this account.';

/// The result of validating an entered Insider code. [message] is '' only
/// when [status] is [CodeCheckStatus.ok].
class CodeCheckResult {
  final CodeCheckStatus status;
  final String message;
  const CodeCheckResult(this.status, [this.message = '']);

  bool get isOk => status == CodeCheckStatus.ok;
}

/// Validates an entered code against the Insider it resolves to.
///
/// Chain order (first match wins): [CodeCheckStatus.invalid] (the code
/// doesn't resolve to any Insider — [codeOwnerUid] null/empty) ->
/// [CodeCheckStatus.suspended] (resolves, but the owning Insider's status
/// isn't 'active') -> [CodeCheckStatus.selfReferral] (the code's owner IS
/// [myUid]) -> [CodeCheckStatus.alreadyReferred] (the entering user has
/// already redeemed a referral before — the global once-ever guard, spec
/// §3) -> [CodeCheckStatus.ok].
CodeCheckResult evaluateCode({
  required String? codeOwnerUid,
  required String? codeOwnerStatus,
  required String myUid,
  required bool alreadyReferred,
}) {
  if (codeOwnerUid == null || codeOwnerUid.isEmpty) {
    return const CodeCheckResult(CodeCheckStatus.invalid, kCodeInvalidMessage);
  }
  if (codeOwnerStatus != 'active') {
    return const CodeCheckResult(
        CodeCheckStatus.suspended, kCodeSuspendedMessage);
  }
  if (codeOwnerUid == myUid) {
    return const CodeCheckResult(
        CodeCheckStatus.selfReferral, kCodeSelfReferralMessage);
  }
  if (alreadyReferred) {
    return const CodeCheckResult(
        CodeCheckStatus.alreadyReferred, kCodeAlreadyReferredMessage);
  }
  return const CodeCheckResult(CodeCheckStatus.ok);
}

// ---------------------------------------------------------------------------
// First-timer determination (spec §4)
// ---------------------------------------------------------------------------

/// Outcome of [firstTimer] — [isFirstTimer] is the decision;
/// [matchedByEmail]/[matchedByPhone] say which signal(s) found a prior
/// submission, for logging/debugging.
class FirstTimerResult {
  final bool isFirstTimer;
  final bool matchedByEmail;
  final bool matchedByPhone;
  const FirstTimerResult({
    required this.isFirstTimer,
    this.matchedByEmail = false,
    this.matchedByPhone = false,
  });
}

/// Deterministic-only first-time check (spec §4): normalized [email] OR
/// normalized [phone] matching ANY prior submission -> existing player;
/// otherwise a first-timer. [priorSubmissions] entries are tolerant Maps —
/// each may carry an 'email'/'Email' and/or 'phone'/'Phone' key (missing
/// keys are simply not matched against). Name-only similarity is
/// intentionally never checked here (owner-accepted paper-era win-back,
/// spec §4/§11).
FirstTimerResult firstTimer({
  required String email,
  required String phone,
  required Iterable<Map> priorSubmissions,
}) {
  final normEmail = normalizeEmail(email);
  final normPhone = normalizePhoneDigits(phone);
  var matchedEmail = false;
  var matchedPhone = false;
  for (final sub in priorSubmissions) {
    final subEmail = normalizeEmail(
        (sub['email'] ?? sub['Email'] ?? '').toString());
    final subPhone = normalizePhoneDigits(
        (sub['phone'] ?? sub['Phone'] ?? '').toString());
    if (normEmail.isNotEmpty && subEmail == normEmail) matchedEmail = true;
    if (normPhone.isNotEmpty && subPhone == normPhone) matchedPhone = true;
  }
  return FirstTimerResult(
    isFirstTimer: !(matchedEmail || matchedPhone),
    matchedByEmail: matchedEmail,
    matchedByPhone: matchedPhone,
  );
}

// ---------------------------------------------------------------------------
// Stamped submission fields (spec §9 InsiderCode/FirstTimer/DiscountSource/
// DiscountPct/EligibleFee)
// ---------------------------------------------------------------------------

/// The fields a validated promo-code entry stamps onto a fresh submission
/// (spec §4/§9) — built once code validation + the first-timer check +
/// the per-registration promo-config check all complete.
class InsiderPromoOutcome {
  final String insiderCode; // normalized (uppercased)
  final bool firstTimer;
  final String discountSource; // '' | 'first_timer_promo'
  final double? discountPct;
  final double? eligibleFee;

  const InsiderPromoOutcome({
    required this.insiderCode,
    required this.firstTimer,
    this.discountSource = '',
    this.discountPct,
    this.eligibleFee,
  });
}

// ---------------------------------------------------------------------------
// Best-discount-wins display math (spec §5)
// ---------------------------------------------------------------------------

/// The amount actually owed when a submission may carry a manual admin
/// adjustment (`DiscountSource == 'manual'`, spec §6/Task M1), an automatic
/// first-timer promo (`DiscountSource == 'first_timer_promo'`, Task F3), OR
/// an automatic Insider tier discount (`DiscountSource == 'insider_tier'`,
/// Task F5 — spec §2) in its shared AdjustedFee/DiscountPct/EligibleFee
/// fields. 'first_timer_promo' and 'insider_tier' compute IDENTICALLY (a
/// plain percent off [eligibleFee]) — they are two different WHYS for the
/// exact same math, and best-discount-wins (spec §5) has already picked the
/// single winning source before this submission was ever written (see
/// [pickBestDiscount]), so at read time there is only ever one automatic
/// source stamped.
///
/// Today 'manual' never truly coexists with an automatic source in the SAME
/// submission (the Manager's adjustSubmissionAmount always fully overwrites
/// DiscountSource/DiscountPct to 'manual' — M3, which would let an admin
/// apply a manual adjustment on top of a live automatic discount, hasn't
/// shipped). This function is written defensively per spec §5
/// ("best-discount-wins ... if both exist show the LARGER single discount")
/// so a future coexistence never under-discounts the player: it computes
/// both interpretations when both are plausible and returns whichever total
/// is LOWER (the bigger discount). With only one signal present it degrades
/// to that signal's total; with neither it returns [baseFee] unchanged.
double bestDiscountedTotal({
  required double baseFee,
  double? eligibleFee,
  double? adjustedFee,
  double? discountPct,
  required String discountSource,
}) {
  final base = baseFee < 0 ? 0.0 : baseFee;
  if (adjustedFee == null && discountPct == null) return base;

  final manualTotal = discountSource == 'manual'
      ? adjustedOwed(
          baseFee: base, adjustedFee: adjustedFee, discountPct: discountPct)
      : null;
  final isAutomaticPromo = discountSource == 'first_timer_promo' ||
      discountSource == 'insider_tier';
  final promoTotal = isAutomaticPromo && discountPct != null
      ? promoDiscountedTotal(eligibleFee ?? base, discountPct)
      : null;

  final candidates = [manualTotal, promoTotal].whereType<double>().toList();
  if (candidates.isEmpty) {
    // Unrecognized/legacy discountSource but fields are set anyway — fall
    // back to the original manual-only precedence rule so old data (written
    // before this task) keeps behaving exactly as before.
    return adjustedOwed(
        baseFee: base, adjustedFee: adjustedFee, discountPct: discountPct);
  }
  candidates.sort();
  return candidates.first;
}

// ---------------------------------------------------------------------------
// Insider tier discount at checkout (spec §2 "Insider's own-fee discount",
// §5 "best-discount-wins", Task F5)
// ---------------------------------------------------------------------------

/// Which discount source wins when both an Insider's own tier discount and
/// a first-timer promo could apply to the SAME individual registration
/// (spec §5: automatic discounts never stack — best-discount-wins). [none]
/// means neither candidate discount applies at all.
enum DiscountWinner { none, insiderTier, firstTimerPromo }

/// The winning discount computed by [pickBestDiscount] — [pct] is null only
/// when [source] is [DiscountWinner.none].
class DiscountCandidate {
  final DiscountWinner source;
  final double? pct;
  const DiscountCandidate(this.source, this.pct);

  bool get isNone => source == DiscountWinner.none;
}

const DiscountCandidate _kNoDiscount =
    DiscountCandidate(DiscountWinner.none, null);

/// Best-discount-wins picker (spec §5) for the two AUTOMATIC discount
/// sources that can compete on the same individual registration: the
/// Insider's own tier discount ([insiderPct], spec §2 — the registrant's
/// OWN active-Insider tier percent; callers must apply the
/// [insiderTierDiscountApplies] guard BEFORE passing a value here, since
/// this function has no notion of registration path) and the
/// per-registration first-timer promo ([promoPct], spec §4, already
/// computed by the F3 engine — pass the promo's pct only when its own
/// DiscountSource is 'first_timer_promo', i.e. it actually won the
/// first-timer check).
///
/// Neither/either-only degrades to whichever is present (or [none] with
/// both absent). With BOTH present, the LARGER percent wins (cheaper for the
/// registrant — spec §5 "best-discount-wins"); a TIE goes to the insider
/// tier discount. That tie-break is an arbitrary-but-deterministic pick, NOT
/// a business requirement — the org's payout is identical either way at a
/// tie, so this only exists to make the function total or deterministic.
///
/// A zero-or-negative candidate is treated as absent — a caller should never
/// pass 0 for an eligible discount, but this keeps the picker defensive
/// regardless.
DiscountCandidate pickBestDiscount({double? insiderPct, double? promoPct}) {
  final insider = (insiderPct != null && insiderPct > 0) ? insiderPct : null;
  final promo = (promoPct != null && promoPct > 0) ? promoPct : null;
  if (insider == null && promo == null) return _kNoDiscount;
  if (promo == null) {
    return DiscountCandidate(DiscountWinner.insiderTier, insider);
  }
  if (insider == null) {
    return DiscountCandidate(DiscountWinner.firstTimerPromo, promo);
  }
  return insider >= promo
      ? DiscountCandidate(DiscountWinner.insiderTier, insider)
      : DiscountCandidate(DiscountWinner.firstTimerPromo, promo);
}

/// Guard (spec §2 "Tier discount applies to the Insider's individual
/// registration fees only (never team fees)"): the Insider tier discount is
/// only ever a candidate on the INDIVIDUAL registration path — a
/// team-captain's fee is a TEAM fee, and the joiner path never owes a fee of
/// its own. Also requires the registrant's own Insider record to be
/// [active] with a [tier] of at least 1 (Bronze) — pending/suspended/
/// declined Insiders and tier 0 (not yet Bronze, discount 0%) never get a
/// checkout discount.
bool insiderTierDiscountApplies({
  required String path,
  required bool active,
  required int tier,
}) =>
    path == 'individual' && active && tier >= 1;

/// Tier display name for a STAMPED insider-tier discount percent (spec §9
/// Submission.DiscountPct on a DiscountSource=='insider_tier' submission) —
/// used by the fan payment screen, which only has the stamped pct (not a
/// live Insider record, since the discount is stamped once at submission
/// time per spec's "stamp-at-submit" design and is never re-derived from a
/// possibly-since-changed tier). The five tier discount percents
/// (5/10/15/20/25) happen to equal their own ladder threshold (Bronze
/// unlocks at BOTH standing 5 and discount 5%, Silver at 10/10%, etc.) so
/// this is exactly [tierForStanding] fed the pct as if it were a standing,
/// then named via [tierName] — that coincidence is documented here as the
/// ONE place it's relied on, rather than silently assumed at every call
/// site. An out-of-range/unrecognized pct (never produced by
/// [tierDiscountPct] in lib/model/insider.dart) maps to ''.
String tierNameForDiscountPct(double pct) =>
    tierName(tierForStanding(pct.round()));
