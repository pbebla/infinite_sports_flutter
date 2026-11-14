import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/live_registration_config.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';
import 'package:infinite_sports_flutter/widgets/skeleton.dart';

/// Lists every open registration, LIVE — an admin opening or closing a
/// registration updates this list instantly, no refresh. Tapping one shows
/// the player's existing submission (status page) or starts the path
/// selector. Registering twice for the same registration is therefore
/// impossible — the status page opens instead (spec section 7).
class RegistrationEntryPage extends StatefulWidget {
  const RegistrationEntryPage({super.key, this.openRegistrationsOverride});

  /// Test seam replacing the live open-registrations list (null = real).
  final Stream<Map<String, RegistrationConfig>>? openRegistrationsOverride;

  @override
  State<RegistrationEntryPage> createState() => _RegistrationEntryPageState();
}

class _RegistrationEntryPageState extends State<RegistrationEntryPage> {
  late final Stream<Map<String, RegistrationConfig>> _openRegs;

  @override
  void initState() {
    super.initState();
    _openRegs = widget.openRegistrationsOverride ??
        RegistrationService.watchOpenRegistrations();
  }

  /// The registration being checked with the server (one tap at a time).
  String? _opening;

  /// Fresh reads (Task 3, #74, and Task 4's entry-page fee): the list above
  /// is live, but its first answer can be the phone's saved copy, so the
  /// tile only shows what is open; the config (open state, fee, paths) that
  /// goes into the form and the payment screen is re-read SERVER-FIRST here,
  /// together with "already registered?" (one barrier, one 8 s bound). A
  /// saved copy or a failed read shows "couldn't check"; a registration the
  /// server says has closed shows "Registration is closed".
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
      body: StreamBuilder(
        stream: _openRegs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Skeleton sweep (F3 Fix 2): "sign-ups/registration list"
            // priority spot — matches the ListView.separated below.
            return const SkeletonList();
          }
          final regs = snapshot.data ?? {};
          if (regs.isEmpty) {
            return const Center(
                child: Text('No registrations are open right now.'));
          }
          final entries = regs.entries.toList();
          return ListView.separated(
            // Theme-staleness fix (F3.1): separatorBuilder's own `context`
            // can go stale after a theme toggle, same as itemBuilder rows
            // (see fixtures_tab.dart, F3 Fix 1) — wrap in a Builder so this
            // Divider's Theme.of() lookup stays live/dependency-tracked.
            separatorBuilder: (context, index) => Builder(
              builder: (context) =>
                  Divider(color: Theme.of(context).dividerColor),
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final regId = entries[index].key;
              final config = entries[index].value;
              // All three paths are live (L1b): show the per-player fee
              // and/or the team fee this registration is configured with.
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
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : null,
                onTap: () => _openRegistration(regId),
              );
            },
          );
        },
      ),
    );
  }
}
