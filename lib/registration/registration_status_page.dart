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
///
/// LIVE: the submission and team ride RTDB streams, so an admin approving
/// the team or flipping Paid in the Manager updates this open screen
/// instantly — no refresh, no back-and-forth.
class RegistrationStatusPage extends StatefulWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationStatusPage(
      {super.key, required this.regId, required this.config});

  @override
  State<RegistrationStatusPage> createState() => _RegistrationStatusPageState();
}

class _RegistrationStatusPageState extends State<RegistrationStatusPage> {
  late final Stream<RegSubmission?> _submission;
  late final Future<List<RegQuestion>> _form;

  // The team stream is created lazily from the live submission's teamId and
  // cached so rebuilds don't resubscribe (which would flash a spinner).
  Stream<RegTeam?>? _teamStream;
  String _teamStreamTeamId = '';

  // Same caching pattern for the captain's roster stream.
  Stream<List<RegSubmission>>? _rosterStream;
  String _rosterStreamTeamId = '';

  @override
  void initState() {
    super.initState();
    _submission = RegistrationService.watchMySubmission(widget.regId);
    _form = RegistrationService.getForm(widget.regId);
  }

  Stream<RegTeam?> _teamStreamFor(String teamId) {
    if (_teamStream == null || _teamStreamTeamId != teamId) {
      _teamStreamTeamId = teamId;
      _teamStream = RegistrationService.watchTeam(widget.regId, teamId);
    }
    return _teamStream!;
  }

  Stream<List<RegSubmission>> _rosterStreamFor(String teamId) {
    if (_rosterStream == null || _rosterStreamTeamId != teamId) {
      _rosterStreamTeamId = teamId;
      _rosterStream =
          RegistrationService.watchTeamMembers(widget.regId, teamId);
    }
    return _rosterStream!;
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
              subtitle: const Text('Approved! Teammates join with this code.'),
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
            const Divider(height: 1),
            _teamRoster(team),
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

  Widget _teamRoster(RegTeam team) {
    return StreamBuilder<List<RegSubmission>>(
      stream: _rosterStreamFor(team.id),
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <RegSubmission>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team roster (${members.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              if (team.codeWaivesPayment) ...[
                const SizedBox(height: 4),
                Text(
                  'Fees covered by you — players register free.',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontStyle: FontStyle.italic,
                      fontSize: 13),
                ),
              ],
              const SizedBox(height: 8),
              if (members.isEmpty)
                Text(
                  'No players have joined with your code yet — share it with your team!',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color),
                )
              else
                for (final member in members)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(member.displayName.isEmpty
                                ? '(no name)'
                                : member.displayName)),
                        if (!team.codeWaivesPayment)
                          _paidChip(context,
                              paid: member.paid,
                              label: member.paid ? 'Paid' : 'Not paid'),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Paid/Not-paid chip that reads correctly in BOTH light and dark mode
  /// (pale shade100 fills wash out on a dark background).
  Widget _paidChip(BuildContext context,
      {required bool paid, required String label}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color background = paid
        ? (dark ? Colors.green.shade900 : Colors.green.shade100)
        : (dark ? Colors.orange.shade900 : Colors.orange.shade100);
    final Color foreground = paid
        ? (dark ? Colors.green.shade100 : Colors.green.shade900)
        : (dark ? Colors.orange.shade100 : Colors.orange.shade900);
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(color: foreground),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }

  Widget _spinner(BuildContext context) {
    return Center(
        child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary));
  }

  /// "Done" always exits all the way to this navigator's home route —
  /// whether we were reached post-submission (the entry/path/form stack is
  /// already cleared, so this is a no-op pop-wise beyond leaving this page)
  /// or from the entry page's "already registered" tap (where back would
  /// otherwise just return to the entry list; Done skips that and leaves
  /// the registration area entirely).
  void _done(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('My Registration'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Done',
          onPressed: () => _done(context),
        ),
      ),
      body: FutureBuilder(
        future: _form,
        builder: (context, formSnapshot) => StreamBuilder(
          stream: _submission,
          builder: (context, subSnapshot) {
            if (formSnapshot.connectionState == ConnectionState.waiting ||
                subSnapshot.connectionState == ConnectionState.waiting) {
              return _spinner(context);
            }
            final sub = subSnapshot.data;
            if (sub == null) {
              return const Center(
                  child: Text('No registration found for your account.'));
            }
            final form = formSnapshot.data ?? const <RegQuestion>[];
            if (sub.teamId.isEmpty) return _statusBody(sub, form, null);
            // Nested team stream: approval / join code / waive changes land
            // live while the captain (or joiner) is looking at the page.
            return StreamBuilder(
              stream: _teamStreamFor(sub.teamId),
              builder: (context, teamSnapshot) {
                if (teamSnapshot.connectionState == ConnectionState.waiting) {
                  return _spinner(context);
                }
                return _statusBody(sub, form, teamSnapshot.data);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _statusBody(RegSubmission sub, List<RegQuestion> form, RegTeam? team) {
    final byKey = {for (final q in form) q.key: q};
    final orderedKeys = [
      ...form.map((q) => q.key).where(sub.answers.containsKey),
      ...sub.answers.keys.where((k) => !byKey.containsKey(k)),
    ];
    final owes = paymentOwed(
        config: widget.config,
        submission: sub,
        codeWaivesPayment: team?.codeWaivesPayment ?? false);
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
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Registered as: ${_pathLabel(sub.path)}'),
                  trailing: _paidChip(context,
                      paid: sub.paid,
                      label: sub.paid
                          ? (sub.paidVia == 'team code'
                              ? 'Paid via team code'
                              : 'Paid')
                          : 'Payment pending'),
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
                  subtitle: Text(_displayValue(byKey[key], sub.answers[key])),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // No refresh-on-return needed — the submission
                    // stream picks up the admin's Paid flip live.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PaymentScreen(
                              regId: widget.regId,
                              config: widget.config,
                              amount: amountOwed(
                                  config: widget.config,
                                  submission: sub,
                                  codeWaivesPayment:
                                      team?.codeWaivesPayment ?? false))),
                    );
                  },
                  child: const Text('Complete payment',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
