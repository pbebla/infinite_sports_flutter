import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/my_registrations.dart';
import 'package:infinite_sports_flutter/registration/registration_chip.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// The list a "couldn't load" registration list shows (with Retry).
const String kRegistrationsCouldNotLoad =
    "Couldn't load your registrations. Try again.";

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
  const RegistrationEntryPage({
    super.key,
    this.registrationsOverride,
    this.openStatusOverride,
  });

  /// Test seams: the live registrations (null = watchMyRegistrations) and
  /// what tapping one of MY registrations does (null = the status page).
  final Stream<MyRegistrations> Function()? registrationsOverride;
  final void Function(String regId, RegistrationConfig config)?
      openStatusOverride;

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

  /// The registration being checked with the server (one tap at a time).
  String? _opening;

  void _openMine(MyRegistration m) {
    final override = widget.openStatusOverride;
    if (override != null) {
      override(m.regId, m.config);
      return;
    }
    // The status page follows the live config and submission itself.
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationStatusPage(regId: m.regId, config: m.config);
    }));
  }

  /// Fresh reads (Task 3, #74, and Task 4's entry-page fee): the list above
  /// is live, but its first answer can be the phone's saved copy, so the
  /// tile only shows what is open; the config (open state, fee, paths) that
  /// goes into the form and the payment screen is re-read SERVER-FIRST here,
  /// together with "already registered?" (one barrier, one 8 s bound). A
  /// saved copy or a failed read shows "couldn't check".
  Future<void> _openRegistration(String regId) async {
    if (_opening != null) return;
    setState(() => _opening = regId);
    final entry = await RegistrationService.checkEntry(regId);
    if (!mounted) return;
    setState(() => _opening = null);
    final config = entry.config;
    switch (entry.route) {
      case RegistrationRoute.status:
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          return RegistrationStatusPage(regId: regId, config: config!);
        }));
      case RegistrationRoute.register:
        Navigator.push(context, MaterialPageRoute(builder: (_) {
          return RegistrationPathPage(regId: regId, config: config!);
        }));
      case RegistrationRoute.closed:
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration is closed')));
      case RegistrationRoute.couldNotCheck:
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(kRegistrationCouldNotCheck)));
      case RegistrationRoute.unavailable:
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(kRegistrationUnavailable)));
    }
  }

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
          if (snapshot.hasError && !snapshot.hasData) {
            return _loadFailed();
          }
          if (!snapshot.hasData) {
            // Skeleton sweep (F3 Fix 2): "sign-ups/registration list"
            // priority spot — matches the list below.
            return const SkeletonList();
          }
          final regs = snapshot.data!;
          if (regs.mine.isEmpty && regs.openForSignUp.isEmpty) {
            return const Center(
                child: Text('No registrations are open right now.'));
          }
          return ListView(
            padding: EdgeInsets.only(
                bottom: 8 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (regs.mine.isNotEmpty) ...[
                _header(context, 'My registrations'),
                for (final m in regs.mine) _mineTile(context, m),
              ],
              if (regs.openForSignUp.isNotEmpty) ...[
                _header(context, 'Open for sign-up'),
                for (final e in regs.openForSignUp.entries)
                  _openTile(context, e.key, e.value),
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
    final owed = m.owed;
    final chip = m.paid
        ? const RegistrationStatusChip(paid: true, label: 'Paid')
        : owed > 0
            ? RegistrationStatusChip(
                paid: false, label: 'You owe ${formatOwed(owed)}')
            : const RegistrationStatusChip(paid: true, label: 'Covered');
    return ListTile(
      leading: const Icon(Icons.assignment_turned_in),
      title: Text(m.config.label,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle:
          Text('Registered as: ${registrationPathLabel(m.submission.path)}'),
      trailing: chip,
      onTap: () => _openMine(m),
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
      trailing: _opening == regId
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
            )
          : null,
      onTap: () => _openRegistration(regId),
    );
  }
}
