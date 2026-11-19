import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_chip.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_open.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// The list a "couldn't load" registration list shows (with Retry).
const String kRegistrationsCouldNotLoad =
    "Couldn't load your registrations. Try again.";

/// The small line above a list that is still shown after a later read
/// failed (final small round, N3).
const String kRegistrationsCouldNotRefresh =
    "Couldn't refresh — showing your last loaded registrations.";

/// The registration list (home banner / drawer), LIVE, in two groups:
///   1. "My registrations" — every existing registration the signed-in fan
///      has a submission in, OPEN OR CLOSED (way back, owner-approved
///      2026-11-14: a registered player can always see their registration
///      and, if they still owe, pay), each with "Registered as …" and a
///      Paid / "You owe $X" chip (the status page's discountedAmountOwed).
///      Tapping opens the status page.
///   2. "Open for sign-up" — open registrations the fan has NOT registered
///      for. Tapping re-checks with the server ([RegistrationService
///      .checkEntry]) and starts the path selector (or the status page when
///      a submission turns out to exist).
/// One loading state for both groups (no pop-in); a failed read is
/// "couldn't load" with Retry.
class RegistrationEntryPage extends StatefulWidget {
  const RegistrationEntryPage(
      {super.key, this.registrationsOverride, this.legacySignUp});

  /// Test seam: the live registrations (null = watchMyRegistrations).
  final Stream<MyRegistrations> Function()? registrationsOverride;

  /// The OLD sign-up page (legacy Sign Up Status), when the drawer brought
  /// the fan here while it is open and no new-style registration is (way
  /// back fix round, Minor 4): a "Sign Up List" row at the bottom opens it.
  final ({String detail, WidgetBuilder page})? legacySignUp;

  @override
  State<RegistrationEntryPage> createState() => _RegistrationEntryPageState();
}

class _RegistrationEntryPageState extends State<RegistrationEntryPage> {
  late Stream<MyRegistrations> _regs;

  Stream<MyRegistrations> _watch() =>
      (widget.registrationsOverride ?? watchMyRegistrations)();

  @override
  void initState() {
    super.initState();
    _regs = _watch();
  }

  /// The last list shown (kept across a later stream error, N3).
  MyRegistrations? _lastGood;

  /// The registration being checked with the server (one tap at a time).
  String? _opening;

  /// Every tap — one of MY registrations or an open one — confirms with
  /// the server first (RegistrationOpen.open → checkEntry) and follows its
  /// outcome (way back fix round, Important 1: the list's config can be the
  /// phone's saved copy, so it never opens the status page on its own).
  /// One tap at a time, with a spinner on the tapped row.
  Future<void> _openRegistration(String regId) async {
    if (_opening != null) return;
    setState(() => _opening = regId);
    try {
      await RegistrationOpen.open(context, regId,
          onRetry: () => _openRegistration(regId));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Widget? _spinnerFor(String regId) => _opening == regId
      ? SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Registration'),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: StreamBuilder<MyRegistrations>(
        stream: _regs,
        builder: (context, snapshot) {
          // Final small round, N3: StreamBuilder drops its data on an error,
          // so the last good list is kept here; a later error keeps showing
          // it (with a small "couldn't refresh" line). The full "Couldn't
          // load" is only for an error before anything was shown.
          if (snapshot.hasData) _lastGood = snapshot.data;
          final refreshFailed = snapshot.hasError && _lastGood != null;
          if (snapshot.hasError && _lastGood == null) {
            return _loadFailed();
          }
          if (_lastGood == null) {
            // Skeleton sweep (F3 Fix 2): "sign-ups/registration list"
            // priority spot — matches the list below.
            return const SkeletonList();
          }
          final regs = _lastGood!;
          final legacy = widget.legacySignUp;
          if (regs.mine.isEmpty &&
              regs.openForSignUp.isEmpty &&
              legacy == null) {
            return const Center(
                child: Text('No registrations are open right now.'));
          }
          return ListView(
            padding: EdgeInsets.only(
                bottom: 8 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (refreshFailed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(kRegistrationsCouldNotRefresh,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              if (regs.mine.isNotEmpty) ...[
                _header(context, 'My registrations'),
                for (final m in regs.mine) _mineTile(context, m),
              ],
              if (regs.openForSignUp.isNotEmpty) ...[
                _header(context, 'Open for sign-up'),
                for (final e in regs.openForSignUp.entries)
                  _openTile(context, e.key, e.value),
              ],
              if (legacy != null) ...[
                if (regs.openForSignUp.isEmpty)
                  _header(context, 'Open for sign-up'),
                ListTile(
                  leading: const Icon(Icons.how_to_reg),
                  title: const Text('Sign Up List',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(legacy.detail),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: legacy.page)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _loadFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(kRegistrationsCouldNotLoad, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _regs = _watch()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)),
    );
  }

  Widget _mineTile(BuildContext context, MyRegistration m) {
    // The status page's own chip decision (fix round, Minor 1); a pending
    // chip with money owed is worded with the amount.
    final decision = m.chip;
    final chip = RegistrationStatusChip(
        paid: decision.settled,
        label:
            decision.kind == RegistrationChipKind.pending && decision.owed > 0
                ? 'You owe ${formatOwed(decision.owed)}'
                : decision.label);
    return ListTile(
      leading: const Icon(Icons.assignment_turned_in),
      title: Text(m.config.label,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle:
          Text('Registered as: ${registrationPathLabel(m.submission.path)}'),
      trailing: _spinnerFor(m.regId) ?? chip,
      onTap: () => _openRegistration(m.regId),
    );
  }

  Widget _openTile(
      BuildContext context, String regId, RegistrationConfig config) {
    // All three paths are live (L1b): show the per-player fee and/or the
    // team fee this registration is configured with.
    final feeParts = <String>[
      if (config.paymentMode != 'teamFee' && config.fee > 0)
        '\$${config.fee} per player',
      if (config.paymentMode != 'perPlayer' && config.teamFee > 0)
        '\$${config.teamFee} per team',
    ];
    final feeText = feeParts.isEmpty
        ? 'Free'
        : 'Fee: ${feeParts.join(' · ')}${config.feeNote.isNotEmpty ? ' — ${config.feeNote}' : ''}';
    return ListTile(
      enabled: signedIn,
      leading: const Icon(Icons.how_to_reg),
      title: Text(config.label,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(signedIn ? feeText : 'Log in to register'),
      trailing: _spinnerFor(regId),
      onTap: () => _openRegistration(regId),
    );
  }
}
