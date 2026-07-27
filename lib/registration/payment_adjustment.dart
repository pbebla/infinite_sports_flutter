// Manual payment-adjustment pure helpers (Infinite Insiders program, P1
// Task M1 — "standalone value" per the design spec).
//
// NO Flutter/Firebase imports — unit-tested directly (test/
// payment_adjustment_test.dart). Lets an owner/admin manually change what a
// registration submission owes (new total, percent off, or a full comp to
// $0), always with a required reason and an immutable audit trail.
//
// Spec: infinite_sports_flutter/docs/superpowers/specs/
// 2026-07-27-infinite-insiders-design.md §5 (stacking/ceiling) and §9
// (InsiderAudit RTDB shape). This file is Manager-only for now; the fan
// repo's Task F1 mirrors [adjustedOwed] there so the payment screen shows
// the same number the admin set here.

/// The dollar amount actually owed after a manual admin adjustment.
///
/// Precedence: [adjustedFee] (an absolute new total) wins over
/// [discountPct] (a percent off [baseFee]) when both are somehow set. No
/// adjustment at all returns [baseFee] unchanged. The result is always
/// clamped to zero or more — a comp (100% off, or an adjustedFee of 0 or
/// less) never goes negative.
double adjustedOwed({
  required double baseFee,
  double? adjustedFee,
  double? discountPct,
}) {
  if (adjustedFee != null) return adjustedFee < 0 ? 0 : adjustedFee;
  if (discountPct != null) {
    final result = baseFee * (1 - discountPct / 100);
    return result < 0 ? 0 : result;
  }
  return baseFee < 0 ? 0 : baseFee;
}

/// null when the proposed adjustment is valid; otherwise the message to
/// show the admin.
///
/// Pass exactly one of [newAmount] (an absolute new total, "New total $"
/// mode) or [pct] (percent off [baseFee], "Percent off %" mode) — whichever
/// the dialog mode is currently on. [compConfirmed] is the explicit
/// "Comp to $0" checkbox; when true it bypasses the [maxPct] ceiling (the
/// ONLY way to grant more than [maxPct] off — there is no way to grant,
/// say, 60% off without going all the way to a confirmed comp, matching the
/// owner's locked design in spec §5/§6).
///
/// Rules: negative amounts/percents are always rejected; [newAmount] may
/// never exceed [baseFee] ('Cannot charge more than the base fee'); the
/// discount implied by either [newAmount] or [pct] may not exceed [maxPct]
/// (default 25) unless [compConfirmed] is true; [pct] itself may never
/// exceed 100.
String? validateAdjustment({
  required double baseFee,
  double? newAmount,
  double? pct,
  required bool compConfirmed,
  double maxPct = 25,
}) {
  if (newAmount != null) {
    if (newAmount < 0) return 'Amount cannot be negative.';
    if (newAmount > baseFee) return 'Cannot charge more than the base fee';
    final impliedPct = baseFee > 0 ? (baseFee - newAmount) / baseFee * 100 : 0;
    if (impliedPct > maxPct && !compConfirmed) {
      return 'That discount is more than the ${_pctLabel(maxPct)}% cap — '
          r'use Comp to $0 to confirm a larger discount.';
    }
  }
  if (pct != null) {
    if (pct < 0) return 'Percent off cannot be negative.';
    if (pct > 100) return 'Percent off cannot exceed 100%.';
    if (pct > maxPct && !compConfirmed) {
      return 'That discount is more than the ${_pctLabel(maxPct)}% cap — '
          r'use Comp to $0 to confirm a larger discount.';
    }
  }
  return null;
}

String _pctLabel(double maxPct) =>
    maxPct == maxPct.roundToDouble() ? maxPct.toStringAsFixed(0) : '$maxPct';

/// Builds one immutable `/InsiderAudit/<pushId>` record — spec §9 shape:
/// `{ AdminUid, Target, Field, Old, New, Reason, At }`. [reason] is
/// REQUIRED and non-blank (throws [ArgumentError] otherwise — every
/// adjustment must be explainable). [atMs] is optional and injectable for
/// deterministic tests; callers writing to Firebase may leave it unset (it
/// defaults to the current device time) since the write layer typically
/// overrides 'At' with `ServerValue.timestamp` for cross-device ordering.
Map<String, Object?> auditEntry({
  required String adminUid,
  required String regId,
  required String submissionId,
  required String field,
  required Object? oldValue,
  required Object? newValue,
  required String reason,
  int? atMs,
}) {
  final trimmedReason = reason.trim();
  if (trimmedReason.isEmpty) {
    throw ArgumentError.value(reason, 'reason', 'reason is required for an audit entry');
  }
  return {
    'AdminUid': adminUid,
    'Target': '$regId/$submissionId',
    'Field': field,
    'Old': oldValue,
    'New': newValue,
    'Reason': trimmedReason,
    'At': atMs ?? DateTime.now().millisecondsSinceEpoch,
  };
}
