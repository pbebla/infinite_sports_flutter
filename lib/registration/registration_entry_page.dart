import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/utility.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_path_page.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:infinite_sports_flutter/registration/registration_status_page.dart';

/// Lists every open registration, LIVE — an admin opening or closing a
/// registration updates this list instantly, no refresh. Tapping one shows
/// the player's existing submission (status page) or starts the path
/// selector. Registering twice for the same registration is therefore
/// impossible — the status page opens instead (spec section 7).
class RegistrationEntryPage extends StatefulWidget {
  const RegistrationEntryPage({super.key});

  @override
  State<RegistrationEntryPage> createState() => _RegistrationEntryPageState();
}

class _RegistrationEntryPageState extends State<RegistrationEntryPage> {
  late final Stream<Map<String, RegistrationConfig>> _openRegs;

  @override
  void initState() {
    super.initState();
    _openRegs = RegistrationService.watchOpenRegistrations();
  }

  Future<void> _openRegistration(
      String regId, RegistrationConfig config) async {
    final existing = await RegistrationService.getMySubmission(regId);
    if (!mounted) return;
    if (existing != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) {
        return RegistrationStatusPage(regId: regId, config: config);
      }));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) {
        return RegistrationPathPage(regId: regId, config: config);
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Registration'),
        backgroundColor: appBarBackground(context),
        foregroundColor: appBarForeground(context),
      ),
      body: StreamBuilder(
        stream: _openRegs,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final regs = snapshot.data ?? {};
          if (regs.isEmpty) {
            return const Center(
                child: Text('No registrations are open right now.'));
          }
          final entries = regs.entries.toList();
          return ListView.separated(
            separatorBuilder: (context, index) =>
                Divider(color: Theme.of(context).dividerColor),
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
                onTap: () => _openRegistration(regId, config),
              );
            },
          );
        },
      ),
    );
  }
}
