import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

/// Joiner-path code entry: 6 pin boxes, auto-uppercased, resolved against
/// this registration's teams as the user types. An approved match shows
/// "Joining {team}" + Continue; a pending/rejected team's code and unknown
/// codes get friendly errors (spec section 7).
///
/// DB lockdown B4: codes resolve SERVER-SIDE via the resolveJoinCode
/// callable (RegistrationService.resolveJoinCode) — the old flow downloaded
/// every team's join code (payment-waiving ones included) and matched
/// locally, which is both a privacy bug and impossible once Teams go
/// captain-only. Lookups are debounced per keystroke and start at 4 entered
/// characters (validateJoinCode's minimum code length), so admin-edited
/// codes shorter than 6 still match; a stale in-flight lookup can never
/// clobber a newer one (generation guard).
class JoinCodePage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  /// Test seam replacing the real callable round trip — mirrors the
  /// injectable-override pattern in insider_promo_field.dart.
  final Future<JoinCodeMatch> Function(
      {required String regId, required String code})? resolveOverride;

  const JoinCodePage(
      {super.key,
      required this.regId,
      required this.config,
      this.resolveOverride});

  @override
  State<JoinCodePage> createState() => _JoinCodePageState();
}

class _JoinCodePageState extends State<JoinCodePage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  /// Bumped on every keystroke; a lookup only applies its result while it
  /// is still the newest one.
  int _generation = 0;

  bool _checking = false;
  RegTeam? _match;
  String? _error;

  /// True when [_error] is the "couldn't check" failure — shows Try again.
  bool _lookupFailed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _generation++;
    final entered = _controller.text.trim();
    // Below the 4-character code minimum nothing can match — partial input
    // just clears the state (same quiet behavior as before).
    if (entered.length < 4) {
      setState(() {
        _checking = false;
        _match = null;
        _error = null;
        _lookupFailed = false;
      });
      return;
    }
    setState(() {
      _checking = true;
      _match = null;
      _error = null;
      _lookupFailed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), _check);
  }

  void _retry() {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _checking = true;
      _error = null;
      _lookupFailed = false;
    });
    _check();
  }

  void _onCompleted() {
    // All six boxes filled — resolve immediately, no debounce wait.
    _debounce?.cancel();
    _check();
  }

  Future<void> _check() async {
    final entered = _controller.text.trim();
    final gen = _generation;
    final resolve =
        widget.resolveOverride ?? RegistrationService.resolveJoinCode;
    final result = await resolve(regId: widget.regId, code: entered);
    if (!mounted || gen != _generation) return; // superseded by newer input
    setState(() {
      _checking = false;
      _lookupFailed = false;
      if (result.status == 'ok') {
        _match = result.team;
        _error = null;
      } else if (result.status == 'notApproved') {
        _match = null;
        _error =
            'That team is still awaiting approval — ask your captain to check back soon.';
      } else if (result.status == 'error') {
        // The lookup itself failed (offline, timeout, cold start) — that
        // says nothing about the code, so never call it a mismatch.
        // Like a not-found, stay quiet until the code is complete.
        _match = null;
        _lookupFailed = entered.length >= 6;
        _error = _lookupFailed
            ? "Couldn't check the code. Check your connection and try again."
            : null;
      } else {
        _match = null;
        // Only complain once all six boxes are filled; shorter input that
        // doesn't match just stays quiet (an admin-edited 4-5 char code
        // that DOES match lands in the 'ok' branch above).
        _error = entered.length >= 6
            ? "That code doesn't match any team in this registration."
            : null;
      }
    });
  }

  void _continue() {
    final team = _match;
    if (team == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: widget.regId,
          config: widget.config,
          path: 'joiner',
          team: team);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.config.label),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: ListView(
        // Bottom inset clears the floating glass nav bar (PR #12 review).
        padding: EdgeInsets.fromLTRB(
            15, 15, 15, 15 + MediaQuery.paddingOf(context).bottom),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Enter your team code',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text(
                'Your captain got a 6-character code when the team was approved.',
                textAlign: TextAlign.center),
          ),
          PinCodeTextField(
            appContext: context,
            length: 6,
            controller: _controller,
            autoDisposeControllers: false,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            animationType: AnimationType.fade,
            backgroundColor: Colors.transparent,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              TextInputFormatter.withFunction((oldV, newV) =>
                  newV.copyWith(text: newV.text.toUpperCase())),
            ],
            textStyle:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            pinTheme: PinTheme(
              shape: PinCodeFieldShape.box,
              borderRadius: BorderRadius.circular(8),
              fieldHeight: 52,
              fieldWidth: 44,
              activeColor: Theme.of(context).colorScheme.primary,
              selectedColor: Theme.of(context).colorScheme.primary,
              inactiveColor: Theme.of(context).dividerColor,
            ),
            onChanged: (_) => _onChanged(),
            onCompleted: (_) => _onCompleted(),
          ),
          if (_checking)
            Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_lookupFailed && !_checking)
            Center(
              child: TextButton(
                onPressed: _retry,
                child: const Text('Try again'),
              ),
            ),
          if (_match != null) ...[
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.verified, color: Colors.green),
                title: Text('Joining ${_match!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_match!.codeWaivesPayment
                    ? 'Your captain covers the team fee — no payment needed.'
                    : "You'll pay the \$${widget.config.fee} player fee after registering."),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: _continue,
                child: const Text('Continue', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
