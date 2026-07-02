import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/join_code_page.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// "How are you registering?" — all three paths are live as of L1b:
/// individual, join a team with a code (joiner), register a new team
/// (captain — asks the team name first, hygiene-cleaned and non-empty).
class RegistrationPathPage extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationPathPage(
      {super.key, required this.regId, required this.config});

  Future<void> _startCaptain(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your team name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Team name',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final cleaned = cleanTeamName(controller.text);
              if (cleaned.isEmpty) return; // require a non-empty name
              Navigator.pop(ctx, cleaned);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) {
      return RegistrationFormPage(
          regId: regId, config: config, path: 'captain', teamName: name);
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(config.label),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
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
                  return RegistrationFormPage(regId: regId, config: config);
                }));
              },
            ),
          ),
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
                  return JoinCodePage(regId: regId, config: config);
                }));
              },
            ),
          ),
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
