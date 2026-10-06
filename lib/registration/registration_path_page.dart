import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/misc/tournament_colors.dart';
import 'package:infinite_sports_flutter/registration/join_code_page.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// "How are you registering?" — all three paths are live as of L1b:
/// individual, join a team with a code (joiner), register a new team
/// (captain — asks the team name first, hygiene-cleaned and non-empty).
///
/// Which paths exist is a per-registration owner choice (Config.Paths,
/// Futsal S16 ask): only the enabled cards render, and when exactly one of
/// individual/joiner is enabled the chooser skips itself and renders that
/// path's page directly (captain-only still shows its single card — the
/// captain flow starts with a dialog, which needs a page under it).
class RegistrationPathPage extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  /// Test seams (house pattern, cf. insiders_info_page.dart's
  /// dashboardPageBuilder): replace the real pages the single-path
  /// redirects build — RegistrationFormPage fetches Firebase in initState.
  final Widget Function()? individualFormBuilder;
  final Widget Function()? joinCodePageBuilder;

  const RegistrationPathPage(
      {super.key,
      required this.regId,
      required this.config,
      this.individualFormBuilder,
      this.joinCodePageBuilder});

  Widget _individualForm() =>
      individualFormBuilder?.call() ??
      RegistrationFormPage(regId: regId, config: config);

  Widget _joinCodePage() =>
      joinCodePageBuilder?.call() ?? JoinCodePage(regId: regId, config: config);

  Future<void> _startCaptain(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _TeamNameDialog(),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: regId, config: config, path: 'captain', teamName: name);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = config.enabledPaths;
    if (enabled.length == 1 && enabled.single == 'individual') {
      return _individualForm();
    }
    if (enabled.length == 1 && enabled.single == 'joiner') {
      return _joinCodePage();
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(config.label),
        backgroundColor: TournamentColors.headerBackground(context),
        foregroundColor: TournamentColors.headerForeground(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('How are you registering?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center),
          ),
          if (config.pathIndividual)
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Register as an individual',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text("We'll place you on a team"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) {
                    return _individualForm();
                  }));
                },
              ),
            ),
          if (config.pathJoiner)
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.group),
                title: const Text('Join a team with a code',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Enter the code your captain sent you'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) {
                    return _joinCodePage();
                  }));
                },
              ),
            ),
          if (config.pathCaptain)
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Register a new team (captain)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Name your team — an admin approves it and you get a join code'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _startCaptain(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// Owns its TextEditingController so it is disposed with the dialog subtree
/// (disposing it right after showDialog resolves crashes the dialog's exit
/// animation: '_dependents.isEmpty is not true'). Pops the cleaned name.
class _TeamNameDialog extends StatefulWidget {
  const _TeamNameDialog();

  @override
  State<_TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<_TeamNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final cleaned = cleanTeamName(_controller.text);
    if (cleaned.isEmpty) return; // require a non-empty name
    Navigator.pop(context, cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your team name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _continue(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Team name',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _continue, child: const Text('Continue')),
      ],
    );
  }
}
