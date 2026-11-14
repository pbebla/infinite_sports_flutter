// The registration's config, LIVE, for the screens that show what a fan owes
// (second review, Important 2): the status page and the payment screen.
//
// The config is confirmed with the server when the fan enters
// (RegistrationService.checkEntry), but the fan can then sit on the form,
// the status page or the payment screen for minutes. The card charge is
// computed on the server from `Registrations/<regId>/Config` at the moment
// of payment, so these screens watch that same node (readable by everyone
// under both rules files: `Registrations/$regId/Config/.read: true` — the
// RegistrationsPublic mirror is a trigger-maintained copy of it that can lag
// a second behind) and compute every amount from the latest value:
//   • a fee change while open updates the amounts in place and raises
//     [feeChanged] (the screens show a short notice);
//   • a stream error keeps the last confirmed value and raises [error]: the
//     pay actions show the existing "couldn't check" state (a failed read
//     is not a fact) with a retry;
//   • a CLOSED registration changes nothing here: the owner closes sign-ups
//     to stop NEW registrations, and players who registered but have not
//     paid still pay (the server accepts it) — so the pay actions stay and
//     the amounts keep following the live config (correction to 4cad135;
//     the closed wording stays only where it stops a new registration);
//   • a REMOVED registration (the Config node is gone) raises [removed]:
//     no amount is offered as payable and the pay actions give way to
//     [kRegistrationUnavailable].

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

class LiveRegistrationConfig extends ChangeNotifier {
  LiveRegistrationConfig({
    required RegistrationConfig initial,
    required Stream<RegistrationConfig?> Function() source,
  })  : _config = initial,
        _source = source;

  final Stream<RegistrationConfig?> Function() _source;
  RegistrationConfig _config;
  StreamSubscription<RegistrationConfig?>? _sub;
  bool _removed = false;
  bool _error = false;
  bool _retrying = false;
  bool _feeChanged = false;
  bool _disposed = false;

  /// The latest confirmed config (the entry-time one until the first event).
  RegistrationConfig get config => _config;

  /// The registration no longer exists (its Config node is gone).
  bool get removed => _removed;

  /// The live read failed; [config] is the last confirmed value.
  bool get error => _error;

  /// A "Try again" is waiting for its first answer (the pay actions stay in
  /// the couldn't-check state until a confirmed config arrives — final
  /// round, item 3).
  bool get retrying => _retrying;

  /// The fee changed while the screen was open.
  bool get feeChanged => _feeChanged;

  /// Pay actions are allowed: the registration exists (open OR closed) and
  /// its config is confirmed.
  bool get canPay => !_removed && !_error;

  /// Subscribes. [error] is NOT cleared here: only a confirmed config event
  /// clears it, so a retry never shows the pay actions before anything is
  /// confirmed.
  void start() {
    if (_sub != null || _disposed) return;
    try {
      _sub = _source().listen(_onConfig, onError: (Object _) {
        _sub?.cancel();
        _sub = null;
        _error = true;
        _retrying = false;
        _notify();
      });
    } catch (_) {
      _error = true;
      _retrying = false;
      _notify();
    }
  }

  /// Re-subscribes after an error (the "Try again" on the pay actions); the
  /// couldn't-check state stays until the first confirmed event.
  void retry() {
    _sub?.cancel();
    _sub = null;
    _retrying = true;
    _notify();
    start();
  }

  void _onConfig(RegistrationConfig? next) {
    _error = false;
    _retrying = false;
    if (next == null) {
      _removed = true;
      _notify();
      return;
    }
    // Open or closed alike: the amounts follow the live config.
    _removed = false;
    if (feeDiffers(_config, next)) _feeChanged = true;
    _config = next;
    _notify();
  }

  /// Whether what a registrant owes can differ between [a] and [b].
  static bool feeDiffers(RegistrationConfig a, RegistrationConfig b) =>
      a.fee != b.fee ||
      a.teamFee != b.teamFee ||
      a.paymentMode != b.paymentMode;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

/// The message in place of the pay actions when the registration was
/// deleted.
const String kRegistrationUnavailable =
    'This registration is no longer available.';

/// The notice shown when the fee changed while a screen was open.
const String kRegistrationFeeChanged =
    'The fee for this registration changed. The amount below is the '
    'current one.';
