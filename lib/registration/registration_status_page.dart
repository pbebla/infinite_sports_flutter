import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:infinite_sports_flutter/registration/payment_screen.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';
import 'package:infinite_sports_flutter/registration/registration_service.dart';
import 'package:share_plus/share_plus.dart';

/// The player's registration state: Paid badge, team state (captain sees
/// "pending approval" / a rejection notice / the join code prominently with
/// copy + Share once approved; a joiner sees their team name), the submitted
/// answers, and a persistent "Complete payment" button (reopening the
/// payment screen with the right amount) while unpaid.
class RegistrationStatusPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationStatusPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationStatusPage> createState() => _RegistrationStatusPageState();
}

class _RegistrationStatusPageState extends State<RegistrationStatusPage> {
  late Future<(RegSubmission?, List<RegQuestion>, RegTeam?)> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadAll();
  }

  Future<(RegSubmission?, List<RegQuestion>, RegTeam?)> _loadAll() async {
    final sub = await RegistrationService.getMySubmission(widget.regId);
    final form = await RegistrationService.getForm(widget.regId);
    final team = (sub == null || sub.teamId.isEmpty)
        ? null
        : await RegistrationService.getTeam(widget.regId, sub.teamId);
    return (sub, form, team);
  }

  void _refresh() {
    setState(() => _load = _loadAll());
  }

  String _displayValue(RegQuestion? q, Object? value) {
    if (value is List) return value.map((v) => v.toString()).join(', ');
    if (value is bool) return value ? 'Yes' : 'No';
    if (q?.type == 'phone') return formatPhone(value?.toString() ?? '');
    return value?.toString() ?? '';
  }

  String _pathLabel(String path) {
    switch (path) {
      case 'captain':
        return 'Team captain';
      case 'joiner':
        return 'Team member';
      default:
        return 'Individual';
    }
  }

  void _copyCode(RegTeam team) {
    Clipboard.setData(ClipboardData(text: team.joinCode));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Join code copied.')));
  }

  void _shareCode(RegTeam team) {
    SharePlus.instance.share(ShareParams(
        text:
            'Join my team "${team.name}" for ${widget.config.label}! Open the Infinite Sports app, go to Registration, pick "Join a team with a code" and enter: ${team.joinCode}'));
  }

  Widget? _teamCard(RegSubmission sub, RegTeam? team) {
    if (sub.teamId.isEmpty) return null;
    if (team == null) {
      return const Card(
        elevation: 2,
        child: ListTile(
          leading: Icon(Icons.group),
          title: Text('Team'),
          subtitle:
              Text("Couldn't load your team right now — go back and retry."),
        ),
      );
    }
    if (sub.path == 'captain') {
      if (team.isPending) {
        return Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.hourglass_top, color: Colors.orange),
            title: Text(team.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Team pending approval — you'll get your join code here once an admin approves it. Check back soon."),
          ),
        );
      }
      if (team.isRejected) {
        return Card(
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text(team.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
                "Your team wasn't approved. Your own registration still counts — contact us and we'll sort it out."),
          ),
        );
      }
      // Approved: the join code, prominently, with copy + share.
      return Card(
        elevation: 2,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.verified, color: Colors.green),
              title: Text(team.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Approved! Teammates join with this code.'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(team.joinCode,
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6)),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy code',
                  onPressed: () => _copyCode(team),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Share code'),
                  onPressed: () => _shareCode(team),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Joiner.
    return Card(
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.group),
        title: Text(team.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub.paidVia == 'team code'
            ? "You're on the team — payment covered by your captain."
            : "You're on the team."),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Registration'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary));
          }
          final (sub, form, team) =
              snapshot.data ?? (null, const <RegQuestion>[], null);
          if (sub == null) {
            return const Center(
                child: Text('No registration found for your account.'));
          }
          final byKey = {for (final q in form) q.key: q};
          final orderedKeys = [
            ...form.map((q) => q.key).where(sub.answers.containsKey),
            ...sub.answers.keys.where((k) => !byKey.containsKey(k)),
          ];
          final owes = paymentOwed(config: widget.config, submission: sub);
          final teamCard = _teamCard(sub, team);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(15),
                  children: [
                    Card(
                      elevation: 2,
                      child: ListTile(
                        title: Text(widget.config.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'Registered as: ${_pathLabel(sub.path)}'),
                        trailing: Chip(
                          label: Text(sub.paid
                              ? (sub.paidVia == 'team code'
                                  ? 'Paid via team code'
                                  : 'Paid')
                              : 'Payment pending'),
                          backgroundColor: sub.paid
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                        ),
                      ),
                    ),
                    if (teamCard != null) ...[
                      const SizedBox(height: 8),
                      teamCard,
                    ],
                    const SizedBox(height: 8),
                    for (final key in orderedKeys)
                      ListTile(
                        dense: true,
                        title: Text(byKey[key]?.label ?? key),
                        subtitle:
                            Text(_displayValue(byKey[key], sub.answers[key])),
                      ),
                  ],
                ),
              ),
              if (owes)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                    regId: widget.regId,
                                    config: widget.config,
                                    amount: amountOwed(
                                        config: widget.config,
                                        submission: sub))),
                          ).then((_) => _refresh());
                        },
                        child: const Text('Complete payment',
                            style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
