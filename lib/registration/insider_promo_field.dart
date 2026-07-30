// Insider promo-code entry field for the registration form (Infinite
// Insiders program, Fan Task F3 — Phase P2). Rendered on the individual AND
// team-captain registration paths only (spec §7) via
// DynamicRegistrationForm's `promoField` slot (lib/registration/
// dynamic_form.dart) — the joiner path never offers it.
//
// This is a FormBuilderField wired into the SAME FormBuilder ancestor the
// dynamic question fields use (same pattern as dynamic_form.dart's private
// _HeightField/_LinkAcknowledgeField): its value flows through
// state.saveAndValidate() and cleanAnswers() like any other field, under the
// reserved key [kInsiderPromoAnswerKey] — RegistrationFormPage pulls it back
// out of the answers map before writing (it is not a real RegQuestion
// answer).
//
// All Firebase/FirebaseAuth reads are behind injectable overrides (mirrors
// lib/insiders/insiders_info_page.dart's applyOverride/insiderStream seams)
// so this widget is fully unit-testable without a Firebase app — see
// test/insider_promo_field_test.dart.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:infinite_sports_flutter/misc/insider_service.dart';
import 'package:infinite_sports_flutter/model/insider.dart';
import 'package:infinite_sports_flutter/registration/promo_engine.dart';

/// Reserved FormBuilder field name for the promo widget's value — DOES NOT
/// correspond to any admin-created RegQuestion key (double-underscore
/// prefix keeps collisions with a real question key implausible).
/// RegistrationFormPage reads `answers[kInsiderPromoAnswerKey]` (cast to
/// [InsiderPromoOutcome]?) and removes it before persisting Answers.
const String kInsiderPromoAnswerKey = '__insiderPromo';

class InsiderPromoCodeField extends StatefulWidget {
  /// The fee this registrant would owe absent any discount — config.fee for
  /// the individual path, config.teamFee for the captain path (spec §4: the
  /// promo computes "against the registration's eligible fee only").
  final double eligibleFee;

  /// This registration's promo config (Registrations/{regId}/Promo) —
  /// already fetched once by RegistrationFormPage (defensive: disabled
  /// default when the node doesn't exist, since M3 hasn't shipped it yet).
  final RegPromo promo;

  /// Every prior submission's Answers map across all registrations
  /// (RegistrationService.getAllSubmissionAnswersForMatch), fetched ONCE per
  /// form session by the parent page and handed down here so re-validating
  /// the code never re-reads Firebase.
  final List<Map<String, dynamic>> priorSubmissions;

  /// The signed-in account's email (FirebaseAuth currentUser.email) and
  /// phone (Users/{uid}/Phone Number, already loaded as the form's prefill)
  /// — the first-timer check's two signals (spec §4).
  final String myEmail;
  final String myPhone;

  // -- Test seams (default to the real InsiderService/FirebaseAuth calls) --
  final Future<String?> Function(String code)? lookupCodeOverride;
  final Future<String> Function(String uid)? insiderStatusOverride;
  final Future<bool> Function(String uid)? alreadyReferredOverride;
  final Future<String> Function(String uid)? insiderNameOverride;
  final String? myUidOverride;
  final DateTime? nowOverride;

  const InsiderPromoCodeField({
    super.key,
    required this.eligibleFee,
    required this.promo,
    this.priorSubmissions = const [],
    this.myEmail = '',
    this.myPhone = '',
    this.lookupCodeOverride,
    this.insiderStatusOverride,
    this.alreadyReferredOverride,
    this.insiderNameOverride,
    this.myUidOverride,
    this.nowOverride,
  });

  @override
  State<InsiderPromoCodeField> createState() => _InsiderPromoCodeFieldState();
}

class _InsiderPromoCodeFieldState extends State<InsiderPromoCodeField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  bool _checking = false;
  String? _errorMessage; // null == no error
  String _insiderName = '';
  bool _friendlyNotFirstTimer = false;
  InsiderPromoOutcome? _outcome;
  String? _lastCheckedCode; // avoids re-validating an unchanged code

  FormFieldState<InsiderPromoOutcome?>? _fieldState;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _maybeValidate();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _maybeValidate);
  }

  void _maybeValidate() {
    final raw = _controller.text.trim();
    if (raw == _lastCheckedCode) return;
    _validate();
  }

  Future<void> _validate() async {
    final field = _fieldState;
    if (field == null) return;
    final raw = _controller.text.trim();
    _lastCheckedCode = raw;

    if (raw.isEmpty) {
      setState(() {
        _checking = false;
        _errorMessage = null;
        _insiderName = '';
        _friendlyNotFirstTimer = false;
        _outcome = null;
      });
      field.didChange(null);
      field.validate();
      return;
    }

    setState(() {
      _checking = true;
      _errorMessage = null;
    });

    final code = normalizeInsiderCode(raw);
    final lookupCode = widget.lookupCodeOverride ?? InsiderService.lookupCode;
    final insiderStatusFn =
        widget.insiderStatusOverride ?? InsiderService.insiderStatus;
    final alreadyReferredFn =
        widget.alreadyReferredOverride ?? InsiderService.alreadyReferred;
    final insiderNameFn =
        widget.insiderNameOverride ?? InsiderService.getInsiderName;
    final myUid =
        widget.myUidOverride ?? (FirebaseAuth.instance.currentUser?.uid ?? '');

    final ownerUid = await lookupCode(code);
    final ownerStatus =
        ownerUid == null ? null : await insiderStatusFn(ownerUid);
    final referred = await alreadyReferredFn(myUid);

    final result = evaluateCode(
      codeOwnerUid: ownerUid,
      codeOwnerStatus: ownerStatus,
      myUid: myUid,
      alreadyReferred: referred,
    );

    if (!mounted) return;
    if (!result.isOk) {
      setState(() {
        _checking = false;
        _errorMessage = result.message;
        _insiderName = '';
        _friendlyNotFirstTimer = false;
        _outcome = null;
      });
      field.didChange(null);
      field.validate();
      return;
    }

    final name = await insiderNameFn(ownerUid!);
    final firstTimerResult = firstTimer(
      email: widget.myEmail,
      phone: widget.myPhone,
      priorSubmissions: widget.priorSubmissions,
    );
    final now = widget.nowOverride ?? DateTime.now();
    final promoOn = widget.promo.activeAt(now);
    final applyDiscount = promoOn && firstTimerResult.isFirstTimer;
    final outcome = InsiderPromoOutcome(
      insiderCode: code,
      firstTimer: firstTimerResult.isFirstTimer,
      discountSource: applyDiscount ? 'first_timer_promo' : '',
      discountPct: applyDiscount ? widget.promo.percent : null,
      eligibleFee: applyDiscount ? widget.eligibleFee : null,
    );

    if (!mounted) return;
    setState(() {
      _checking = false;
      _errorMessage = null;
      _insiderName = name;
      _friendlyNotFirstTimer = promoOn && !firstTimerResult.isFirstTimer;
      _outcome = outcome;
    });
    field.didChange(outcome);
    field.validate();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormBuilderField<InsiderPromoOutcome?>(
      name: kInsiderPromoAnswerKey,
      initialValue: null,
      validator: (_) {
        if (_controller.text.trim().isEmpty) return null; // optional field
        if (_checking) return 'Still checking your code…';
        return _errorMessage;
      },
      builder: (field) {
        _fieldState = field;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('insider_promo_code_field'),
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toUpperCase())),
              ],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Insider Promo Code (optional)',
                suffixIcon: _checking
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_outcome != null
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : null),
                errorText: field.errorText,
              ),
              onChanged: (value) {
                _onChanged(value);
              },
              onSubmitted: (_) => _maybeValidate(),
            ),
            if (!_checking && field.errorText == null && _outcome != null) ...[
              const SizedBox(height: 6),
              Text(
                _insiderName.isNotEmpty
                    ? "Code accepted — $_insiderName's referral"
                    : 'Code accepted.',
                style: TextStyle(color: Colors.green.shade700),
              ),
              if (_friendlyNotFirstTimer)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Welcome back! This promo is for first-time players, so '
                    "the discount doesn't apply — but glad you're returning.",
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.bold),
                  ),
                )
              else if (_outcome!.discountSource == 'first_timer_promo')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_pctLabel(_outcome!.discountPct)}% first-time player '
                    'discount will be applied at checkout!',
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  String _pctLabel(double? pct) {
    if (pct == null) return '';
    return pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toString();
  }
}
