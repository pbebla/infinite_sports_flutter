import 'package:flutter/material.dart';
import 'package:infinite_sports_flutter/registration/registration_form_page.dart';
import 'package:infinite_sports_flutter/registration/registration_models.dart';

/// "How are you registering?" — L1a ships the individual path only; the two
/// team paths are visible but disabled until L1b.
class RegistrationPathPage extends StatelessWidget {
  final String regId;
  final RegistrationConfig config;

  const RegistrationPathPage(
      {super.key, required this.regId, required this.config});

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
          const Card(
            elevation: 2,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.group),
              title: Text('Join a team with a code',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Coming soon'),
            ),
          ),
          const Card(
            elevation: 2,
            child: ListTile(
              enabled: false,
              leading: Icon(Icons.groups),
              title: Text('Register a new team (captain)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Coming soon'),
            ),
          ),
        ],
      ),
    );
  }
}
