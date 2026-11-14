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
//   • a registration that is closed or removed raises [closed]: the pay
//     actions disable with the existing "Registration is closed" wording.

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
  bool _closed = false;
  bool _error = false;
  bool _feeChanged = false;
  bool _disposed = false;

  /// The latest confirmed config (the entry-time one until the first event).
  RegistrationConfig get config => _config;

  /// The registration is closed or no longer exists.
  bool get closed => _closed;

  /// The live read failed; [config] is the last confirmed value.
  bool get error => _error;

  /// The fee changed while the screen was open.
  bool get feeChanged => _feeChanged;

  /// Pay actions are allowed: open and confirmed.
  bool get canPay => !_closed && !_error;

  void start() {
    if (_sub != null || _disposed) return;
    _error = false;
    try {
      _sub = _source().listen(_onConfig, onError: (Object _) {
        _sub?.cancel();
        _sub = null;
        _error = true;
        _notify();
      });
    } catch (_) {
      _error = true;
      _notify();
    }
  }

  /// Re-subscribes after an error (the "Try again" on the pay actions).
  void retry() {
    _sub?.cancel();
    _sub = null;
    start();
    _notify();
  }

  void _onConfig(RegistrationConfig? next) {
    _error = false;
    if (next == null || !next.isOpen) {
      _closed = true;
      _notify();
      return;
    }
    _closed = false;
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

/// The notice shown when the fee changed while a screen was open.
const String kRegistrationFeeChanged =
    'The fee for this registration changed. The amount below is the '
    'current one.';
